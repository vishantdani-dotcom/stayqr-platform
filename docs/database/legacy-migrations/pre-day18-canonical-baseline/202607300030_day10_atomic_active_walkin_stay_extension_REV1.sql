-- StayQR v1.0
-- Day 10 Migration 030 REV1
-- Atomic active direct-walk-in stay extension
--
-- This migration installs the authoritative backend contract.
-- It does not extend any stay by itself.

begin;

create table if not exists public.guest_session_extension_events (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null,
  guest_session_id uuid not null,
  room_id uuid not null,
  idempotency_key text not null,
  previous_checkout_at timestamptz not null,
  new_checkout_at timestamptz not null,
  previous_room_charge numeric(12,2) not null,
  additional_room_charge numeric(12,2) not null,
  current_room_charge numeric(12,2) not null,
  extension_reason text not null,
  result_snapshot jsonb not null default '{}'::jsonb,
  created_by uuid null,
  created_at timestamptz not null default now(),

  constraint guest_session_extension_events_hotel_fkey
    foreign key (hotel_id)
    references public.hotels(id)
    on delete restrict,

  constraint guest_session_extension_events_session_fkey
    foreign key (hotel_id, guest_session_id)
    references public.guest_sessions(hotel_id, id)
    on delete cascade,

  constraint guest_session_extension_events_room_fkey
    foreign key (hotel_id, room_id)
    references public.rooms(hotel_id, id)
    on delete restrict,

  constraint guest_session_extension_events_created_by_fkey
    foreign key (created_by)
    references auth.users(id)
    on delete set null,

  constraint guest_session_extension_events_dates_check
    check (new_checkout_at > previous_checkout_at),

  constraint guest_session_extension_events_charge_check
    check (
      previous_room_charge >= 0
      and additional_room_charge >= 0
      and current_room_charge =
        previous_room_charge + additional_room_charge
    ),

  constraint guest_session_extension_events_reason_check
    check (length(trim(extension_reason)) >= 3),

  constraint guest_session_extension_events_idempotency_check
    check (length(trim(idempotency_key)) >= 8),

  constraint guest_session_extension_events_hotel_request_unique
    unique (hotel_id, idempotency_key)
);

create index if not exists
  idx_guest_session_extension_events_session_created
on public.guest_session_extension_events (
  hotel_id,
  guest_session_id,
  created_at desc
);

create index if not exists
  idx_guest_session_extension_events_room_created
on public.guest_session_extension_events (
  hotel_id,
  room_id,
  created_at desc
);

alter table public.guest_session_extension_events
  enable row level security;

drop policy if exists
  stayqr_day10_extension_events_select
on public.guest_session_extension_events;

create policy stayqr_day10_extension_events_select
on public.guest_session_extension_events
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
on table public.guest_session_extension_events
from public, anon, authenticated;

grant select
on table public.guest_session_extension_events
to authenticated, service_role;

create or replace function public.extend_active_walkin_guest_stay(
  target_hotel_id uuid,
  target_guest_session_id uuid,
  payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  existing_event
    public.guest_session_extension_events%rowtype;
  session_row public.guest_sessions%rowtype;
  room_row public.rooms%rowtype;
  allocation_row public.room_inventory_allocations%rowtype;
  refreshed_allocation
    public.room_inventory_allocations%rowtype;
  payment_row public.payments%rowtype;
  history_row public.stay_room_history%rowtype;
  actor_id uuid := auth.uid();
  hotel_timezone text;
  request_id_value text;
  extension_reason_value text;
  expected_checkout_at_value timestamptz;
  new_checkout_at_value timestamptz;
  current_checkout_at_value timestamptz;
  current_room_charge numeric(12,2);
  additional_room_charge_value numeric(12,2);
  final_room_charge numeric(12,2);
  confirm_room_charge boolean;
  old_end_date date;
  new_end_date date;
  session_before jsonb;
  allocation_before jsonb;
  payment_before jsonb;
  result_value jsonb;
begin
  if not private.user_has_any_permission(
    target_hotel_id,
    array[
      'guests.manage',
      'checkin.manage'
    ]::text[]
  ) then
    raise exception
      'Active-stay extension access denied.';
  end if;

  if target_guest_session_id is null then
    raise exception
      'Guest session is required.';
  end if;

  if payload is null
     or jsonb_typeof(payload) <> 'object'
  then
    raise exception
      'Stay-extension payload must be a JSON object.';
  end if;

  request_id_value :=
    nullif(trim(payload ->> 'request_id'), '');

  if request_id_value is null
     or length(request_id_value) < 8
  then
    raise exception
      'A stable request_id of at least 8 characters is required.';
  end if;

  extension_reason_value :=
    nullif(trim(payload ->> 'extension_reason'), '');

  if extension_reason_value is null
     or length(extension_reason_value) < 3
  then
    raise exception
      'An extension reason of at least 3 characters is required.';
  end if;

  begin
    expected_checkout_at_value :=
      nullif(
        trim(payload ->> 'expected_checkout_at'),
        ''
      )::timestamptz;
  exception
    when others then
      raise exception
        'expected_checkout_at must be a valid timestamp.';
  end;

  if expected_checkout_at_value is null then
    raise exception
      'expected_checkout_at is required for stale-screen protection.';
  end if;

  begin
    new_checkout_at_value :=
      nullif(
        trim(payload ->> 'new_checkout_at'),
        ''
      )::timestamptz;
  exception
    when others then
      raise exception
        'new_checkout_at must be a valid timestamp.';
  end;

  if new_checkout_at_value is null then
    raise exception
      'new_checkout_at is required.';
  end if;

  begin
    additional_room_charge_value :=
      nullif(
        trim(payload ->> 'additional_room_charge'),
        ''
      )::numeric;
  exception
    when others then
      raise exception
        'additional_room_charge must be a valid amount.';
  end;

  if additional_room_charge_value is null
     or additional_room_charge_value < 0
  then
    raise exception
      'A non-negative additional room charge is required.';
  end if;

  begin
    confirm_room_charge :=
      coalesce(
        nullif(
          trim(payload ->> 'confirm_room_charge'),
          ''
        )::boolean,
        false
      );
  exception
    when others then
      raise exception
        'confirm_room_charge must be true or false.';
  end;

  if not confirm_room_charge then
    raise exception
      'The additional room charge must be explicitly confirmed.';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      'stayqr:active-stay-extension:'
      || target_hotel_id::text
      || ':'
      || request_id_value,
      0
    )
  );

  select event_record.*
  into existing_event
  from public.guest_session_extension_events event_record
  where event_record.hotel_id = target_hotel_id
    and event_record.idempotency_key = request_id_value
  limit 1;

  if existing_event.id is not null then
    if existing_event.guest_session_id
         is distinct from target_guest_session_id
       or existing_event.new_checkout_at
         is distinct from new_checkout_at_value
    then
      raise exception
        'This request_id was already used for a different stay extension.';
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
    raise exception
      'Active guest session was not found.';
  end if;

  if session_row.status <> 'active' then
    raise exception
      'Only an active guest session may be extended.';
  end if;

  if session_row.reservation_id is not null
     or session_row.reservation_room_id is not null
  then
    raise exception
      'This workflow currently accepts direct walk-in stays only. Use the reservation modification workflow for reservation-linked stays.';
  end if;

  if session_row.room_id is null then
    raise exception
      'The active stay has no physical room assigned.';
  end if;

  current_checkout_at_value :=
    coalesce(
      session_row.extended_until,
      session_row.checkout_time
    );

  if current_checkout_at_value
       is distinct from expected_checkout_at_value
  then
    raise exception
      'The checkout time changed after the screen loaded. Refresh and try again.';
  end if;

  if new_checkout_at_value <= current_checkout_at_value then
    raise exception
      'The new checkout must be later than the current checkout.';
  end if;

  if new_checkout_at_value
       > current_checkout_at_value + interval '365 days'
  then
    raise exception
      'A single stay extension cannot exceed 365 days.';
  end if;

  if new_checkout_at_value <= now() then
    raise exception
      'The new checkout must be in the future.';
  end if;

  select hotel.timezone
  into hotel_timezone
  from public.hotels hotel
  where hotel.id = target_hotel_id;

  if hotel_timezone is null then
    raise exception
      'Hotel timezone is missing.';
  end if;

  old_end_date :=
    (
      current_checkout_at_value
      at time zone hotel_timezone
    )::date;

  new_end_date :=
    (
      new_checkout_at_value
      at time zone hotel_timezone
    )::date;

  select room_record.*
  into room_row
  from public.rooms room_record
  where room_record.hotel_id = target_hotel_id
    and room_record.id = session_row.room_id
  for update;

  if not found then
    raise exception
      'The stay room was not found.';
  end if;

  if room_row.status <> 'occupied' then
    raise exception
      'The stay room is not marked occupied. Refresh and review the stay.';
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
       is distinct from session_row.room_id
  then
    raise exception
      'The active allocation does not match the stay room.';
  end if;

  if allocation_row.ends_on
       is distinct from old_end_date
  then
    raise exception
      'The stay allocation changed after the screen loaded. Refresh and try again.';
  end if;

  if exists (
    select 1
    from public.room_inventory_allocations other_allocation
    where other_allocation.hotel_id = target_hotel_id
      and other_allocation.room_id = session_row.room_id
      and other_allocation.status = 'active'
      and other_allocation.id <> allocation_row.id
      and other_allocation.stay_dates
            && daterange(
              allocation_row.starts_on,
              new_end_date,
              '[)'
            )
  ) then
    raise exception
      'The room is unavailable for the requested extension period.';
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

  select history.*
  into history_row
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

  if history_row.room_id
       is distinct from session_row.room_id
  then
    raise exception
      'The open room-history segment does not match the stay room.';
  end if;

  current_room_charge :=
    coalesce(payment_row.amount, 0);

  final_room_charge :=
    current_room_charge +
    additional_room_charge_value;

  session_before := to_jsonb(session_row);
  allocation_before := to_jsonb(allocation_row);
  payment_before := to_jsonb(payment_row);

  update public.guest_sessions
  set extended_until = new_checkout_at_value
  where hotel_id = target_hotel_id
    and id = target_guest_session_id
    and status = 'active'
    and coalesce(extended_until, checkout_time)
          = expected_checkout_at_value;

  if not found then
    raise exception
      'The active stay changed while the extension was processing.';
  end if;

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
          is distinct from session_row.room_id
     or refreshed_allocation.ends_on
          is distinct from new_end_date
  then
    raise exception
      'The stay allocation did not extend to the requested date.';
  end if;

  update public.payments
  set amount = final_room_charge
  where hotel_id = target_hotel_id
    and id = payment_row.id
    and guest_session_id =
        target_guest_session_id
    and payment_type = 'room_charge'
    and amount = current_room_charge;

  if not found then
    raise exception
      'The room-charge record changed while the extension was processing.';
  end if;

  update public.stay_room_history
  set
    rate_amount = final_room_charge,
    metadata =
      coalesce(metadata, '{}'::jsonb)
      || jsonb_build_object(
        'last_stay_extension',
        jsonb_build_object(
          'request_id', request_id_value,
          'previous_checkout_at',
            current_checkout_at_value,
          'new_checkout_at',
            new_checkout_at_value,
          'additional_room_charge',
            additional_room_charge_value,
          'extended_by', actor_id,
          'extended_at', now()
        )
      )
  where hotel_id = target_hotel_id
    and id = history_row.id
    and segment_end is null;

  if not found then
    raise exception
      'The active room-history segment changed while the extension was processing.';
  end if;

  result_value := jsonb_build_object(
    'ok', true,
    'idempotent', false,
    'hotel_id', target_hotel_id,
    'guest_session_id', target_guest_session_id,
    'guest_id', session_row.guest_id,
    'room_id', session_row.room_id,
    'room_number', room_row.room_number,
    'request_id', request_id_value,
    'extension_reason', extension_reason_value,
    'previous_checkout_at',
      current_checkout_at_value,
    'new_checkout_at',
      new_checkout_at_value,
    'hotel_timezone', hotel_timezone,
    'allocation', jsonb_build_object(
      'id', refreshed_allocation.id,
      'room_id', refreshed_allocation.room_id,
      'starts_on', refreshed_allocation.starts_on,
      'previous_ends_on', allocation_row.ends_on,
      'ends_on', refreshed_allocation.ends_on,
      'stay_dates', refreshed_allocation.stay_dates,
      'status', refreshed_allocation.status
    ),
    'room_charge', jsonb_build_object(
      'payment_id', payment_row.id,
      'previous_amount', current_room_charge,
      'additional_amount',
        additional_room_charge_value,
      'current_amount', final_room_charge,
      'payment_status', payment_row.payment_status
    ),
    'room_history', jsonb_build_object(
      'segment_id', history_row.id,
      'segment_number', history_row.segment_number,
      'room_id', history_row.room_id,
      'rate_amount', final_room_charge
    )
  );

  insert into public.guest_session_extension_events (
    hotel_id,
    guest_session_id,
    room_id,
    idempotency_key,
    previous_checkout_at,
    new_checkout_at,
    previous_room_charge,
    additional_room_charge,
    current_room_charge,
    extension_reason,
    result_snapshot,
    created_by
  )
  values (
    target_hotel_id,
    target_guest_session_id,
    session_row.room_id,
    request_id_value,
    current_checkout_at_value,
    new_checkout_at_value,
    current_room_charge,
    additional_room_charge_value,
    final_room_charge,
    extension_reason_value,
    result_value,
    actor_id
  );

  perform private.write_activity_log(
    target_hotel_id,
    'front_office.active_stay_extended',
    'guest_session',
    target_guest_session_id,
    format(
      'Active stay in Room %s extended from %s to %s.',
      room_row.room_number,
      current_checkout_at_value,
      new_checkout_at_value
    ),
    jsonb_build_object(
      'guest_session', session_before,
      'allocation', allocation_before,
      'room_charge', payment_before,
      'open_history_segment_id', history_row.id
    ),
    result_value,
    jsonb_build_object(
      'request_id', request_id_value,
      'extension_reason',
        extension_reason_value,
      'previous_checkout_at',
        current_checkout_at_value,
      'new_checkout_at',
        new_checkout_at_value,
      'additional_room_charge',
        additional_room_charge_value,
      'payment_id', payment_row.id,
      'allocation_id', allocation_row.id
    )
  );

  return result_value;
end;
$function$;

comment on function public.extend_active_walkin_guest_stay(
  uuid,
  uuid,
  jsonb
) is
'Day 10 authoritative atomic direct-walk-in stay extension. Validates hotel-local checkout, stale screens, room availability, one active allocation, explicitly confirmed charge impact, open room history, immutable activity evidence and request idempotency in one transaction.';

revoke all
on function public.extend_active_walkin_guest_stay(
  uuid,
  uuid,
  jsonb
)
from public, anon;

grant execute
on function public.extend_active_walkin_guest_stay(
  uuid,
  uuid,
  jsonb
)
to authenticated, service_role;

commit;
