-- StayQR v1.0
-- Day 10 Migration 029 REV1
-- Atomic active walk-in room move / upgrade / downgrade workflow
--
-- This migration does not move any guest by itself.
-- It installs the authoritative transaction that will later be called by the
-- controlled browser acceptance workflow.

begin;

create table if not exists public.guest_session_room_move_events (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null,
  guest_session_id uuid not null,
  idempotency_key text not null,
  from_room_id uuid not null,
  to_room_id uuid not null,
  movement_type text not null,
  move_reason text not null,
  result_snapshot jsonb not null default '{}'::jsonb,
  created_by uuid null,
  created_at timestamptz not null default now(),

  constraint guest_session_room_move_events_hotel_fkey
    foreign key (hotel_id)
    references public.hotels(id)
    on delete restrict,

  constraint guest_session_room_move_events_session_fkey
    foreign key (hotel_id, guest_session_id)
    references public.guest_sessions(hotel_id, id)
    on delete cascade,

  constraint guest_session_room_move_events_from_room_fkey
    foreign key (hotel_id, from_room_id)
    references public.rooms(hotel_id, id)
    on delete restrict,

  constraint guest_session_room_move_events_to_room_fkey
    foreign key (hotel_id, to_room_id)
    references public.rooms(hotel_id, id)
    on delete restrict,

  constraint guest_session_room_move_events_created_by_fkey
    foreign key (created_by)
    references auth.users(id)
    on delete set null,

  constraint guest_session_room_move_events_type_check
    check (
      movement_type in ('move', 'upgrade', 'downgrade')
    ),

  constraint guest_session_room_move_events_reason_check
    check (length(trim(move_reason)) >= 3),

  constraint guest_session_room_move_events_room_change_check
    check (from_room_id <> to_room_id),

  constraint guest_session_room_move_events_idempotency_check
    check (length(trim(idempotency_key)) >= 8),

  constraint guest_session_room_move_events_hotel_request_unique
    unique (hotel_id, idempotency_key)
);

create index if not exists
  idx_guest_session_room_move_events_session_created
on public.guest_session_room_move_events (
  hotel_id,
  guest_session_id,
  created_at desc
);

create index if not exists
  idx_guest_session_room_move_events_rooms_created
on public.guest_session_room_move_events (
  hotel_id,
  from_room_id,
  to_room_id,
  created_at desc
);

alter table public.guest_session_room_move_events
  enable row level security;

drop policy if exists
  stayqr_day10_room_move_events_select
on public.guest_session_room_move_events;

create policy stayqr_day10_room_move_events_select
on public.guest_session_room_move_events
for select
to authenticated
using (
  private.user_has_any_permission(
    hotel_id,
    array[
      'guests.view',
      'guests.manage',
      'checkin.manage',
      'checkout.manage'
    ]::text[]
  )
);

revoke all
on table public.guest_session_room_move_events
from public, anon, authenticated;

grant select
on table public.guest_session_room_move_events
to authenticated, service_role;

-- The Day 10 walk-in flow already relies on this allocation synchronizer.
-- Ensure one trigger invoking it exists before the room-move RPC is enabled.
do $trigger_guard$
begin
  if not exists (
    select 1
    from pg_trigger trigger_record
    join pg_proc trigger_function
      on trigger_function.oid = trigger_record.tgfoid
    join pg_namespace function_schema
      on function_schema.oid = trigger_function.pronamespace
    where trigger_record.tgrelid =
          'public.guest_sessions'::regclass
      and not trigger_record.tgisinternal
      and function_schema.nspname = 'private'
      and trigger_function.proname =
          'sync_guest_session_allocation'
  ) then
    create trigger stayqr_sync_guest_session_allocation
    after insert
      or delete
      or update of
        room_id,
        status,
        checkin_time,
        checkout_time,
        extended_until
    on public.guest_sessions
    for each row
    execute function private.sync_guest_session_allocation();
  end if;
end;
$trigger_guard$;

create or replace function public.move_active_walkin_guest_room(
  target_hotel_id uuid,
  target_guest_session_id uuid,
  target_room_id uuid,
  payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  existing_event
    public.guest_session_room_move_events%rowtype;
  session_row public.guest_sessions%rowtype;
  source_room public.rooms%rowtype;
  destination_room public.rooms%rowtype;
  allocation_row public.room_inventory_allocations%rowtype;
  open_history public.stay_room_history%rowtype;
  payment_row public.payments%rowtype;
  refreshed_allocation
    public.room_inventory_allocations%rowtype;
  new_history_id uuid;
  housekeeping_task_id uuid;
  actor_id uuid := auth.uid();
  request_id_value text;
  expected_from_room_id uuid;
  move_reason_value text;
  effective_at_value timestamptz;
  effective_checkout timestamptz;
  movement_type_value text;
  confirm_rate_change boolean;
  requested_room_charge numeric(12,2);
  current_room_charge numeric(12,2);
  final_room_charge numeric(12,2);
  result_value jsonb;
  source_room_before jsonb;
  destination_room_before jsonb;
  session_before jsonb;
begin
  if not private.user_has_any_permission(
    target_hotel_id,
    array[
      'guests.manage',
      'checkin.manage'
    ]::text[]
  ) then
    raise exception
      'Active-stay room movement access denied.';
  end if;

  if target_guest_session_id is null
     or target_room_id is null
  then
    raise exception
      'Guest session and target room are required.';
  end if;

  if payload is null
     or jsonb_typeof(payload) <> 'object'
  then
    raise exception
      'Room-move payload must be a JSON object.';
  end if;

  request_id_value :=
    nullif(trim(payload ->> 'request_id'), '');

  if request_id_value is null
     or length(request_id_value) < 8
  then
    raise exception
      'A stable request_id of at least 8 characters is required.';
  end if;

  begin
    expected_from_room_id :=
      nullif(trim(payload ->> 'expected_from_room_id'), '')::uuid;
  exception
    when others then
      raise exception
        'expected_from_room_id must be a valid UUID.';
  end;

  if expected_from_room_id is null then
    raise exception
      'expected_from_room_id is required for stale-screen protection.';
  end if;

  move_reason_value :=
    nullif(trim(payload ->> 'move_reason'), '');

  if move_reason_value is null
     or length(move_reason_value) < 3
  then
    raise exception
      'A room-move reason of at least 3 characters is required.';
  end if;

  begin
    effective_at_value :=
      coalesce(
        nullif(trim(payload ->> 'effective_at'), '')::timestamptz,
        now()
      );
  exception
    when others then
      raise exception
        'effective_at must be a valid timestamp.';
  end;

  confirm_rate_change :=
    coalesce(
      nullif(trim(payload ->> 'confirm_rate_change'), '')::boolean,
      false
    );

  begin
    requested_room_charge :=
      nullif(trim(payload ->> 'new_room_charge'), '')::numeric;
  exception
    when others then
      raise exception
        'new_room_charge must be a valid amount.';
  end;

  if requested_room_charge is not null
     and requested_room_charge < 0
  then
    raise exception
      'new_room_charge cannot be negative.';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      'stayqr:active-room-move:'
      || target_hotel_id::text
      || ':'
      || request_id_value,
      0
    )
  );

  select event_record.*
  into existing_event
  from public.guest_session_room_move_events event_record
  where event_record.hotel_id = target_hotel_id
    and event_record.idempotency_key = request_id_value
  limit 1;

  if existing_event.id is not null then
    if existing_event.guest_session_id
         is distinct from target_guest_session_id
       or existing_event.to_room_id
         is distinct from target_room_id
    then
      raise exception
        'This request_id was already used for a different room move.';
    end if;

    return coalesce(
      existing_event.result_snapshot,
      '{}'::jsonb
    ) || jsonb_build_object('idempotent', true);
  end if;

  select stay.*
  into session_row
  from public.guest_sessions stay
  where stay.hotel_id = target_hotel_id
    and stay.id = target_guest_session_id
  for update;

  if not found then
    raise exception 'Active guest session was not found.';
  end if;

  if session_row.status <> 'active' then
    raise exception
      'Only an active guest session may be moved.';
  end if;

  if session_row.reservation_id is not null
     or session_row.reservation_room_id is not null
  then
    raise exception
      'This workflow currently accepts direct walk-in stays only. Use the reservation stay workflow for reservation-linked guests.';
  end if;

  if session_row.room_id is null then
    raise exception
      'The active stay has no physical room assigned.';
  end if;

  if session_row.room_id is distinct from
       expected_from_room_id
  then
    raise exception
      'The stay changed after the screen loaded. Refresh and try again.';
  end if;

  if session_row.room_id is not distinct from target_room_id then
    raise exception
      'The target room is already assigned to this stay.';
  end if;

  effective_checkout :=
    coalesce(
      session_row.extended_until,
      session_row.checkout_time
    );

  if effective_at_value < session_row.checkin_time
     or effective_at_value > now() + interval '5 minutes'
  then
    raise exception
      'The movement timestamp is outside the accepted operational window.';
  end if;

  if effective_at_value >= effective_checkout then
    raise exception
      'A stay cannot be moved at or after its effective checkout time.';
  end if;

  -- Lock both room rows in deterministic UUID order.
  perform 1
  from public.rooms room_record
  where room_record.hotel_id = target_hotel_id
    and room_record.id in (
      session_row.room_id,
      target_room_id
    )
  order by room_record.id
  for update;

  select room_record.*
  into source_room
  from public.rooms room_record
  where room_record.hotel_id = target_hotel_id
    and room_record.id = session_row.room_id;

  select room_record.*
  into destination_room
  from public.rooms room_record
  where room_record.hotel_id = target_hotel_id
    and room_record.id = target_room_id;

  if source_room.id is null then
    raise exception
      'The current room no longer belongs to this hotel.';
  end if;

  if destination_room.id is null then
    raise exception
      'The target room does not belong to this hotel.';
  end if;

  if source_room.status <> 'occupied' then
    raise exception
      'The current room is not marked occupied. Refresh and review the stay.';
  end if;

  if destination_room.status <> 'available' then
    raise exception
      'The target room is not currently available.';
  end if;

  select allocation.*
  into allocation_row
  from public.room_inventory_allocations allocation
  where allocation.hotel_id = target_hotel_id
    and allocation.guest_session_id =
        target_guest_session_id
    and allocation.status = 'active'
  for update;

  if not found then
    raise exception
      'The active stay allocation is missing.';
  end if;

  if allocation_row.room_id
       is distinct from source_room.id
  then
    raise exception
      'The active allocation does not match the current room.';
  end if;

  if exists (
    select 1
    from public.room_inventory_allocations other_allocation
    where other_allocation.hotel_id = target_hotel_id
      and other_allocation.room_id = target_room_id
      and other_allocation.status = 'active'
      and other_allocation.guest_session_id
            is distinct from target_guest_session_id
      and other_allocation.stay_dates
            && allocation_row.stay_dates
  ) then
    raise exception
      'The target room is unavailable for the remaining stay dates.';
  end if;

  if exists (
    select 1
    from public.guest_sessions other_stay
    where other_stay.hotel_id = target_hotel_id
      and other_stay.room_id = target_room_id
      and other_stay.status = 'active'
      and other_stay.id <> target_guest_session_id
  ) then
    raise exception
      'Another active stay already occupies the target room.';
  end if;

  select history.*
  into open_history
  from public.stay_room_history history
  where history.hotel_id = target_hotel_id
    and history.guest_session_id =
        target_guest_session_id
    and history.segment_end is null
  for update;

  if not found then
    raise exception
      'The open room-history segment is missing.';
  end if;

  if open_history.room_id is distinct from source_room.id then
    raise exception
      'The open room-history segment does not match the current room.';
  end if;

  if effective_at_value <= open_history.segment_start then
    raise exception
      'The room-move time must be after the current room segment began.';
  end if;

  select payment_record.*
  into payment_row
  from public.payments payment_record
  where payment_record.hotel_id = target_hotel_id
    and payment_record.guest_session_id =
        target_guest_session_id
    and payment_record.payment_type = 'room_charge'
  for update;

  if not found then
    raise exception
      'The stay room-charge record is missing.';
  end if;

  current_room_charge :=
    coalesce(payment_row.amount, 0);

  if destination_room.room_type_id
       is distinct from source_room.room_type_id
  then
    if not confirm_rate_change
       or requested_room_charge is null
    then
      raise exception
        'Changing room type requires an explicitly confirmed new room charge.';
    end if;

    final_room_charge := requested_room_charge;

    movement_type_value :=
      case
        when final_room_charge >= current_room_charge
          then 'upgrade'
        else 'downgrade'
      end;
  else
    if requested_room_charge is not null
       and requested_room_charge
             is distinct from current_room_charge
    then
      raise exception
        'A same-type room move must preserve the existing room charge.';
    end if;

    final_room_charge := current_room_charge;
    movement_type_value := 'move';
  end if;

  source_room_before := to_jsonb(source_room);
  destination_room_before := to_jsonb(destination_room);
  session_before := to_jsonb(session_row);

  update public.stay_room_history
  set segment_end = effective_at_value
  where hotel_id = target_hotel_id
    and id = open_history.id
    and segment_end is null;

  if not found then
    raise exception
      'The active room-history segment changed. Refresh and try again.';
  end if;

  update public.guest_sessions
  set room_id = target_room_id
  where hotel_id = target_hotel_id
    and id = target_guest_session_id
    and status = 'active'
    and room_id = source_room.id;

  if not found then
    raise exception
      'The active stay changed while the room move was processing.';
  end if;

  -- The guest-session allocation trigger updates the one authoritative stay
  -- allocation to the target room. Verify that effect before continuing.
  select allocation.*
  into refreshed_allocation
  from public.room_inventory_allocations allocation
  where allocation.hotel_id = target_hotel_id
    and allocation.guest_session_id =
        target_guest_session_id
    and allocation.status = 'active'
  for update;

  if refreshed_allocation.id is null
     or refreshed_allocation.room_id
          is distinct from target_room_id
  then
    raise exception
      'The stay allocation did not move to the target room.';
  end if;

  update public.payments
  set
    room_id = target_room_id,
    amount = final_room_charge
  where hotel_id = target_hotel_id
    and id = payment_row.id
    and guest_session_id =
        target_guest_session_id;

  if not found then
    raise exception
      'The room-charge record changed while the move was processing.';
  end if;

  update public.rooms
  set status = 'cleaning'
  where hotel_id = target_hotel_id
    and id = source_room.id
    and status = 'occupied';

  if not found then
    raise exception
      'The source room status changed while the move was processing.';
  end if;

  update public.rooms
  set status = 'occupied'
  where hotel_id = target_hotel_id
    and id = destination_room.id
    and status = 'available';

  if not found then
    raise exception
      'The target room status changed while the move was processing.';
  end if;

  insert into public.stay_room_history (
    hotel_id,
    guest_session_id,
    room_id,
    segment_number,
    movement_type,
    segment_start,
    rate_amount,
    move_reason,
    created_by,
    metadata
  )
  values (
    target_hotel_id,
    target_guest_session_id,
    target_room_id,
    open_history.segment_number + 1,
    movement_type_value,
    effective_at_value,
    final_room_charge,
    move_reason_value,
    actor_id,
    jsonb_build_object(
      'source', 'move_active_walkin_guest_room',
      'request_id', request_id_value,
      'from_room_id', source_room.id,
      'from_room_number', source_room.room_number,
      'to_room_id', destination_room.id,
      'to_room_number', destination_room.room_number,
      'previous_segment_id', open_history.id,
      'payment_id', payment_row.id
    )
  )
  returning id into new_history_id;

  select task.id
  into housekeeping_task_id
  from public.housekeeping_tasks task
  where task.hotel_id = target_hotel_id
    and task.room_id = source_room.id
    and task.task_type = 'room_cleaning'
    and task.status in ('pending', 'in_progress')
  order by task.created_at
  limit 1
  for update;

  if housekeeping_task_id is null then
    insert into public.housekeeping_tasks (
      hotel_id,
      room_id,
      room_number,
      task_type,
      status,
      notes
    )
    values (
      target_hotel_id,
      source_room.id,
      source_room.room_number,
      'room_cleaning',
      'pending',
      format(
        'Room cleaning after active stay moved from Room %s to Room %s.',
        source_room.room_number,
        destination_room.room_number
      )
    )
    returning id into housekeeping_task_id;
  end if;

  result_value := jsonb_build_object(
    'ok', true,
    'idempotent', false,
    'hotel_id', target_hotel_id,
    'guest_session_id', target_guest_session_id,
    'guest_id', session_row.guest_id,
    'request_id', request_id_value,
    'movement_type', movement_type_value,
    'move_reason', move_reason_value,
    'effective_at', effective_at_value,
    'effective_checkout', effective_checkout,
    'from_room', jsonb_build_object(
      'id', source_room.id,
      'room_number', source_room.room_number,
      'room_type_id', source_room.room_type_id,
      'status_before', source_room.status,
      'status_after', 'cleaning'
    ),
    'to_room', jsonb_build_object(
      'id', destination_room.id,
      'room_number', destination_room.room_number,
      'room_type_id', destination_room.room_type_id,
      'status_before', destination_room.status,
      'status_after', 'occupied'
    ),
    'allocation', jsonb_build_object(
      'id', refreshed_allocation.id,
      'room_id', refreshed_allocation.room_id,
      'starts_on', refreshed_allocation.starts_on,
      'ends_on', refreshed_allocation.ends_on,
      'status', refreshed_allocation.status
    ),
    'room_history', jsonb_build_object(
      'closed_segment_id', open_history.id,
      'new_segment_id', new_history_id,
      'new_segment_number',
        open_history.segment_number + 1
    ),
    'room_charge', jsonb_build_object(
      'payment_id', payment_row.id,
      'previous_amount', current_room_charge,
      'current_amount', final_room_charge
    ),
    'housekeeping_task_id', housekeeping_task_id
  );

  insert into public.guest_session_room_move_events (
    hotel_id,
    guest_session_id,
    idempotency_key,
    from_room_id,
    to_room_id,
    movement_type,
    move_reason,
    result_snapshot,
    created_by
  )
  values (
    target_hotel_id,
    target_guest_session_id,
    request_id_value,
    source_room.id,
    destination_room.id,
    movement_type_value,
    move_reason_value,
    result_value,
    actor_id
  );

  perform private.write_activity_log(
    target_hotel_id,
    'front_office.active_stay_room_moved',
    'guest_session',
    target_guest_session_id,
    format(
      'Active stay moved from Room %s to Room %s.',
      source_room.room_number,
      destination_room.room_number
    ),
    jsonb_build_object(
      'guest_session', session_before,
      'source_room', source_room_before,
      'target_room', destination_room_before,
      'room_charge', current_room_charge,
      'open_history_segment_id', open_history.id,
      'allocation_id', allocation_row.id
    ),
    result_value,
    jsonb_build_object(
      'request_id', request_id_value,
      'movement_type', movement_type_value,
      'move_reason', move_reason_value,
      'from_room_id', source_room.id,
      'to_room_id', destination_room.id,
      'payment_id', payment_row.id,
      'housekeeping_task_id', housekeeping_task_id
    )
  );

  return result_value;
end;
$function$;

comment on function public.move_active_walkin_guest_room(
  uuid,
  uuid,
  uuid,
  jsonb
) is
'Day 10 authoritative atomic active direct-walk-in room move. Performs stale-screen validation, remaining-stay availability validation, allocation transfer, room-state transition, room-charge preservation or confirmed rate change, room-history segmentation, housekeeping creation, immutable activity evidence and request idempotency in one transaction.';

revoke all
on function public.move_active_walkin_guest_room(
  uuid,
  uuid,
  uuid,
  jsonb
)
from public, anon;

grant execute
on function public.move_active_walkin_guest_room(
  uuid,
  uuid,
  uuid,
  jsonb
)
to authenticated, service_role;

commit;
