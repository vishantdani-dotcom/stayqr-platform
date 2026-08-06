-- ============================================================================
-- StayQR v1.0
-- Migration: 202607230005_booking_calendar_and_room_allocation
-- Day 4: Booking Calendar and Room Allocation
--
-- PURPOSE
--   1. Create the secure booking-calendar read model.
--   2. Support day/week/month room timelines with room pagination.
--   3. Return reservations, direct stays, room blocks and unallocated bookings.
--   4. Add atomic room assignment/reassignment and calendar date movement.
--   5. Add atomic room-block create/edit/release/cancel workflows.
--   6. Reject overlaps, incompatible-room moves, stale edits and rate-changing
--      drag operations without partial data changes.
--   7. Record all meaningful calendar and room-allocation actions.
--
-- PREREQUISITES
--   - Day 2 Reservation foundation and authoritative inventory ledger.
--   - Day 3 transactional Reservation CRUD and activity logging.
--
-- IMPORTANT BOUNDARIES
--   - Day 4 calendar movement supports single-room reservations.
--   - Drag movement preserves stay length.
--   - A drag is rejected when the target dates would change the rate total.
--     The explicit Reservation Edit workflow must be used in that case.
--   - Checked-in room moves remain part of the stay/check-in workflow; Day 4
--     moves only tentative or confirmed reservations.
--
-- SAFETY
--   - Run the COMPLETE file once using role postgres.
--   - Transactional and guarded by a PostgreSQL advisory lock.
--   - Existing reservations, blocks and rooms are not rewritten.
-- ============================================================================

begin;

set local lock_timeout = '10s';
set local statement_timeout = '240s';

select pg_advisory_xact_lock(
  hashtext('stayqr:202607230005_booking_calendar_and_room_allocation')
);

-- ============================================================================
-- 0. PREREQUISITE ASSERTIONS
-- ============================================================================

do $$
begin
  if to_regclass('public.reservations') is null
     or to_regclass('public.reservation_rooms') is null
     or to_regclass('public.room_blocks') is null
     or to_regclass('public.room_inventory_allocations') is null
     or to_regclass('public.activity_logs') is null
     or to_regprocedure(
       'private.assert_reservation_write_access(uuid)'
     ) is null
     or to_regprocedure(
       'private.write_activity_log(uuid,text,text,uuid,text,jsonb,jsonb,jsonb)'
     ) is null
     or to_regprocedure(
       'private.build_reservation_json(uuid,uuid)'
     ) is null
     or to_regprocedure(
       'public.get_reservation_rate_quote(uuid,uuid,date,date,integer,integer)'
     ) is null
  then
    raise exception
      'Migration stopped: Day 2 or Day 3 prerequisites are incomplete.';
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'room_inventory_no_overlapping_active_allocations'
      and conrelid = 'public.room_inventory_allocations'::regclass
  ) then
    raise exception
      'Migration stopped: authoritative overlap protection is missing.';
  end if;
end
$$;

-- ============================================================================
-- 1. ROOM-BLOCK AUDIT METADATA
-- ============================================================================

alter table public.room_blocks
  add column if not exists updated_by uuid
    references auth.users(id) on delete set null,
  add column if not exists release_reason text;

create index if not exists idx_room_blocks_hotel_updated
on public.room_blocks (hotel_id, updated_at desc);

create index if not exists idx_reservation_rooms_unallocated
on public.reservation_rooms (
  hotel_id,
  room_type_id,
  reservation_id,
  status
)
where room_id is null
  and status in ('held', 'confirmed');

-- ============================================================================
-- 2. PRIVATE HELPERS
-- ============================================================================

create or replace function private.calendar_room_is_available(
  target_hotel_id uuid,
  target_room_id uuid,
  target_start_date date,
  target_end_date date,
  exclude_reservation_room_id uuid default null,
  exclude_room_block_id uuid default null
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    target_hotel_id is not null
    and target_room_id is not null
    and target_start_date is not null
    and target_end_date is not null
    and target_end_date > target_start_date
    and exists (
      select 1
      from public.rooms room
      where room.id = target_room_id
        and room.hotel_id = target_hotel_id
        and room.status not in ('maintenance', 'out_of_order')
    )
    and not exists (
      select 1
      from public.room_inventory_allocations allocation
      where allocation.hotel_id = target_hotel_id
        and allocation.room_id = target_room_id
        and allocation.status = 'active'
        and allocation.stay_dates &&
          daterange(target_start_date, target_end_date, '[)')
        and (
          exclude_reservation_room_id is null
          or allocation.reservation_room_id is distinct from
            exclude_reservation_room_id
        )
        and (
          exclude_room_block_id is null
          or allocation.room_block_id is distinct from
            exclude_room_block_id
        )
    );
$$;

create or replace function private.build_room_block_json(
  target_hotel_id uuid,
  target_room_block_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', block.id,
    'hotel_id', block.hotel_id,
    'room_id', block.room_id,
    'room_number', room.room_number,
    'room_type_id', room.room_type_id,
    'room_type_name', room_type.name,
    'block_type', block.block_type,
    'status', block.status,
    'start_date', block.start_date,
    'end_date', block.end_date,
    'reason', block.reason,
    'notes', block.notes,
    'release_reason', block.release_reason,
    'created_by', block.created_by,
    'updated_by', block.updated_by,
    'released_at', block.released_at,
    'released_by', block.released_by,
    'created_at', block.created_at,
    'updated_at', block.updated_at
  )
  from public.room_blocks block
  join public.rooms room
    on room.id = block.room_id
   and room.hotel_id = block.hotel_id
  join public.room_types room_type
    on room_type.id = room.room_type_id
   and room_type.hotel_id = room.hotel_id
  where block.hotel_id = target_hotel_id
    and block.id = target_room_block_id;
$$;

-- ============================================================================
-- 3. BOOKING CALENDAR READ MODEL
-- ============================================================================

create or replace function public.get_booking_calendar(
  target_hotel_id uuid,
  range_start date,
  range_end date,
  room_type_filter uuid default null,
  reservation_status_filter text[] default null,
  block_status_filter text[] default array['active']::text[],
  page_limit integer default 40,
  page_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  safe_limit integer;
  safe_offset integer;
  total_rooms bigint;
  room_rows jsonb;
  reservation_events jsonb;
  block_events jsonb;
  direct_stay_events jsonb;
  unallocated_rows jsonb;
  normalized_reservation_statuses text[];
  normalized_block_statuses text[];
begin
  if not private.user_has_hotel_access(target_hotel_id) then
    raise exception 'Hotel access denied.';
  end if;

  if range_start is null
     or range_end is null
     or range_end <= range_start
  then
    raise exception
      'Calendar end date must be after the start date.';
  end if;

  if range_end - range_start > 62 then
    raise exception
      'Calendar ranges are limited to 62 days.';
  end if;

  if room_type_filter is not null
     and not exists (
       select 1
       from public.room_types room_type
       where room_type.id = room_type_filter
         and room_type.hotel_id = target_hotel_id
     )
  then
    raise exception 'Room type does not belong to this hotel.';
  end if;

  if reservation_status_filter is not null
     and exists (
       select 1
       from unnest(reservation_status_filter) status_value
       where status_value not in (
         'draft',
         'tentative',
         'confirmed',
         'checked_in',
         'checked_out',
         'cancelled',
         'no_show'
       )
     )
  then
    raise exception 'Reservation status filter is invalid.';
  end if;

  if block_status_filter is not null
     and exists (
       select 1
       from unnest(block_status_filter) status_value
       where status_value not in (
         'active',
         'released',
         'cancelled'
       )
     )
  then
    raise exception 'Room-block status filter is invalid.';
  end if;

  normalized_reservation_statuses :=
    case
      when reservation_status_filter is null
        or cardinality(reservation_status_filter) = 0
      then null
      else reservation_status_filter
    end;

  normalized_block_statuses :=
    case
      when block_status_filter is null
        or cardinality(block_status_filter) = 0
      then null
      else block_status_filter
    end;

  safe_limit := least(greatest(coalesce(page_limit, 40), 1), 100);
  safe_offset := greatest(coalesce(page_offset, 0), 0);

  select count(*)
  into total_rooms
  from public.rooms room
  join public.room_types room_type
    on room_type.id = room.room_type_id
   and room_type.hotel_id = room.hotel_id
  where room.hotel_id = target_hotel_id
    and (
      room_type_filter is null
      or room.room_type_id = room_type_filter
    );

  with paged_rooms as (
    select
      room.id,
      room.hotel_id,
      room.room_number,
      room.status,
      room.room_type_id,
      room_type.name as room_type_name,
      room_type.max_adults,
      room_type.max_children,
      room_type.max_occupancy,
      room_type.sort_order
    from public.rooms room
    join public.room_types room_type
      on room_type.id = room.room_type_id
     and room_type.hotel_id = room.hotel_id
    where room.hotel_id = target_hotel_id
      and (
        room_type_filter is null
        or room.room_type_id = room_type_filter
      )
    order by
      room_type.sort_order,
      nullif(
        regexp_replace(room.room_number, '[^0-9]', '', 'g'),
        ''
      )::integer nulls last,
      room.room_number
    limit safe_limit
    offset safe_offset
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', paged_rooms.id,
        'hotel_id', paged_rooms.hotel_id,
        'room_number', paged_rooms.room_number,
        'status', paged_rooms.status,
        'room_type_id', paged_rooms.room_type_id,
        'room_type_name', paged_rooms.room_type_name,
        'max_adults', paged_rooms.max_adults,
        'max_children', paged_rooms.max_children,
        'max_occupancy', paged_rooms.max_occupancy
      )
      order by
        paged_rooms.sort_order,
        nullif(
          regexp_replace(
            paged_rooms.room_number,
            '[^0-9]',
            '',
            'g'
          ),
          ''
        )::integer nulls last,
        paged_rooms.room_number
    ),
    '[]'::jsonb
  )
  into room_rows
  from paged_rooms;

  with paged_rooms as (
    select room.id
    from public.rooms room
    join public.room_types room_type
      on room_type.id = room.room_type_id
     and room_type.hotel_id = room.hotel_id
    where room.hotel_id = target_hotel_id
      and (
        room_type_filter is null
        or room.room_type_id = room_type_filter
      )
    order by
      room_type.sort_order,
      nullif(
        regexp_replace(room.room_number, '[^0-9]', '', 'g'),
        ''
      )::integer nulls last,
      room.room_number
    limit safe_limit
    offset safe_offset
  )
  select coalesce(
    jsonb_agg(event_payload order by event_start, event_label),
    '[]'::jsonb
  )
  into reservation_events
  from (
    select
      reservation.arrival_date as event_start,
      reservation.reservation_number as event_label,
      jsonb_build_object(
        'event_type', 'reservation',
        'id', reservation_room.id,
        'reservation_id', reservation.id,
        'reservation_room_id', reservation_room.id,
        'room_id', reservation_room.room_id,
        'room_number', room.room_number,
        'room_type_id', reservation_room.room_type_id,
        'room_type_name', room_type.name,
        'reservation_number', reservation.reservation_number,
        'guest_id', guest.id,
        'guest_name', guest.full_name,
        'guest_phone', guest.phone,
        'status', reservation.status,
        'room_status', reservation_room.status,
        'start_date', reservation.arrival_date,
        'end_date', reservation.departure_date,
        'adults', reservation.adults,
        'children', reservation.children,
        'booking_source', reservation.booking_source,
        'source_reference', reservation.source_reference,
        'currency_code', reservation.currency_code,
        'total_amount', reservation.total_amount,
        'deposit_required', reservation.deposit_required,
        'deposit_collected', reservation.deposit_collected,
        'special_requests', reservation.special_requests,
        'internal_notes', reservation.internal_notes,
        'updated_at', reservation.updated_at,
        'occupies_inventory', exists (
          select 1
          from public.room_inventory_allocations allocation
          where allocation.hotel_id = reservation.hotel_id
            and allocation.reservation_room_id = reservation_room.id
            and allocation.status = 'active'
        )
      ) as event_payload
    from public.reservations reservation
    join public.reservation_rooms reservation_room
      on reservation_room.hotel_id = reservation.hotel_id
     and reservation_room.reservation_id = reservation.id
    join paged_rooms
      on paged_rooms.id = reservation_room.room_id
    join public.rooms room
      on room.id = reservation_room.room_id
     and room.hotel_id = reservation_room.hotel_id
    join public.room_types room_type
      on room_type.id = reservation_room.room_type_id
     and room_type.hotel_id = reservation_room.hotel_id
    left join public.guests guest
      on guest.id = reservation.primary_guest_id
     and guest.hotel_id = reservation.hotel_id
    where reservation.hotel_id = target_hotel_id
      and reservation.arrival_date < range_end
      and reservation.departure_date > range_start
      and (
        normalized_reservation_statuses is null
        or reservation.status =
          any(normalized_reservation_statuses)
      )
  ) reservation_event_rows;

  with paged_rooms as (
    select room.id
    from public.rooms room
    join public.room_types room_type
      on room_type.id = room.room_type_id
     and room_type.hotel_id = room.hotel_id
    where room.hotel_id = target_hotel_id
      and (
        room_type_filter is null
        or room.room_type_id = room_type_filter
      )
    order by
      room_type.sort_order,
      nullif(
        regexp_replace(room.room_number, '[^0-9]', '', 'g'),
        ''
      )::integer nulls last,
      room.room_number
    limit safe_limit
    offset safe_offset
  )
  select coalesce(
    jsonb_agg(event_payload order by event_start, event_label),
    '[]'::jsonb
  )
  into block_events
  from (
    select
      block.start_date as event_start,
      block.reason as event_label,
      jsonb_build_object(
        'event_type', 'room_block',
        'id', block.id,
        'room_block_id', block.id,
        'room_id', block.room_id,
        'room_number', room.room_number,
        'room_type_id', room.room_type_id,
        'room_type_name', room_type.name,
        'block_type', block.block_type,
        'status', block.status,
        'start_date', block.start_date,
        'end_date', block.end_date,
        'reason', block.reason,
        'notes', block.notes,
        'release_reason', block.release_reason,
        'created_by', block.created_by,
        'updated_by', block.updated_by,
        'released_at', block.released_at,
        'released_by', block.released_by,
        'created_at', block.created_at,
        'updated_at', block.updated_at,
        'occupies_inventory', exists (
          select 1
          from public.room_inventory_allocations allocation
          where allocation.hotel_id = block.hotel_id
            and allocation.room_block_id = block.id
            and allocation.status = 'active'
        )
      ) as event_payload
    from public.room_blocks block
    join paged_rooms
      on paged_rooms.id = block.room_id
    join public.rooms room
      on room.id = block.room_id
     and room.hotel_id = block.hotel_id
    join public.room_types room_type
      on room_type.id = room.room_type_id
     and room_type.hotel_id = room.hotel_id
    where block.hotel_id = target_hotel_id
      and block.start_date < range_end
      and block.end_date > range_start
      and (
        normalized_block_statuses is null
        or block.status = any(normalized_block_statuses)
      )
  ) block_event_rows;

  with
  hotel_context as (
    select hotel.timezone
    from public.hotels hotel
    where hotel.id = target_hotel_id
  ),
  paged_rooms as (
    select room.id
    from public.rooms room
    join public.room_types room_type
      on room_type.id = room.room_type_id
     and room_type.hotel_id = room.hotel_id
    where room.hotel_id = target_hotel_id
      and (
        room_type_filter is null
        or room.room_type_id = room_type_filter
      )
    order by
      room_type.sort_order,
      nullif(
        regexp_replace(room.room_number, '[^0-9]', '', 'g'),
        ''
      )::integer nulls last,
      room.room_number
    limit safe_limit
    offset safe_offset
  ),
  direct_stays as (
    select
      stay.id,
      stay.room_id,
      stay.guest_id,
      stay.status,
      (stay.checkin_time at time zone hotel_context.timezone)::date
        as starts_on,
      greatest(
        (
          coalesce(stay.extended_until, stay.checkout_time)
          at time zone hotel_context.timezone
        )::date,
        (stay.checkin_time at time zone hotel_context.timezone)::date + 1
      ) as ends_on
    from public.guest_sessions stay
    cross join hotel_context
    join paged_rooms on paged_rooms.id = stay.room_id
    where stay.hotel_id = target_hotel_id
      and stay.reservation_room_id is null
  )
  select coalesce(
    jsonb_agg(event_payload order by event_start, event_label),
    '[]'::jsonb
  )
  into direct_stay_events
  from (
    select
      direct_stays.starts_on as event_start,
      coalesce(guest.full_name, room.room_number) as event_label,
      jsonb_build_object(
        'event_type', 'direct_stay',
        'id', direct_stays.id,
        'guest_session_id', direct_stays.id,
        'room_id', direct_stays.room_id,
        'room_number', room.room_number,
        'room_type_id', room.room_type_id,
        'room_type_name', room_type.name,
        'guest_id', guest.id,
        'guest_name', guest.full_name,
        'guest_phone', guest.phone,
        'status', direct_stays.status,
        'start_date', direct_stays.starts_on,
        'end_date', direct_stays.ends_on,
        'occupies_inventory', exists (
          select 1
          from public.room_inventory_allocations allocation
          where allocation.hotel_id = target_hotel_id
            and allocation.guest_session_id = direct_stays.id
            and allocation.status = 'active'
        )
      ) as event_payload
    from direct_stays
    join public.rooms room
      on room.id = direct_stays.room_id
     and room.hotel_id = target_hotel_id
    join public.room_types room_type
      on room_type.id = room.room_type_id
     and room_type.hotel_id = room.hotel_id
    left join public.guests guest
      on guest.id = direct_stays.guest_id
     and guest.hotel_id = target_hotel_id
    where direct_stays.starts_on < range_end
      and direct_stays.ends_on > range_start
  ) direct_stay_event_rows;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'reservation_id', reservation.id,
        'reservation_room_id', reservation_room.id,
        'reservation_number', reservation.reservation_number,
        'guest_id', guest.id,
        'guest_name', guest.full_name,
        'guest_phone', guest.phone,
        'status', reservation.status,
        'room_status', reservation_room.status,
        'room_type_id', reservation_room.room_type_id,
        'room_type_name', room_type.name,
        'start_date', reservation.arrival_date,
        'end_date', reservation.departure_date,
        'adults', reservation.adults,
        'children', reservation.children,
        'booking_source', reservation.booking_source,
        'source_reference', reservation.source_reference,
        'total_amount', reservation.total_amount,
        'deposit_collected', reservation.deposit_collected,
        'updated_at', reservation.updated_at
      )
      order by reservation.arrival_date, reservation.created_at
    ),
    '[]'::jsonb
  )
  into unallocated_rows
  from public.reservations reservation
  join public.reservation_rooms reservation_room
    on reservation_room.hotel_id = reservation.hotel_id
   and reservation_room.reservation_id = reservation.id
  join public.room_types room_type
    on room_type.id = reservation_room.room_type_id
   and room_type.hotel_id = reservation_room.hotel_id
  left join public.guests guest
    on guest.id = reservation.primary_guest_id
   and guest.hotel_id = reservation.hotel_id
  where reservation.hotel_id = target_hotel_id
    and reservation_room.room_id is null
    and reservation.arrival_date < range_end
    and reservation.departure_date > range_start
    and (
      room_type_filter is null
      or reservation_room.room_type_id = room_type_filter
    )
    and (
      normalized_reservation_statuses is null
      or reservation.status =
        any(normalized_reservation_statuses)
    );

  return jsonb_build_object(
    'hotel_id', target_hotel_id,
    'range_start', range_start,
    'range_end', range_end,
    'day_count', range_end - range_start,
    'room_type_filter', room_type_filter,
    'reservation_status_filter',
      normalized_reservation_statuses,
    'block_status_filter', normalized_block_statuses,
    'pagination', jsonb_build_object(
      'total_rooms', total_rooms,
      'limit', safe_limit,
      'offset', safe_offset,
      'has_previous', safe_offset > 0,
      'has_next', safe_offset + safe_limit < total_rooms
    ),
    'rooms', room_rows,
    'events',
      coalesce(reservation_events, '[]'::jsonb)
      || coalesce(block_events, '[]'::jsonb)
      || coalesce(direct_stay_events, '[]'::jsonb),
    'unallocated_reservations', unallocated_rows,
    'generated_at', now()
  );
end;
$$;

-- ============================================================================
-- 4. RESERVATION ROOM ASSIGNMENT / REASSIGNMENT / CALENDAR MOVE
-- ============================================================================

create or replace function public.move_reservation_on_calendar(
  target_hotel_id uuid,
  target_reservation_id uuid,
  target_reservation_room_id uuid,
  target_room_id uuid,
  target_arrival_date date,
  expected_updated_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_reservation public.reservations%rowtype;
  current_room public.reservation_rooms%rowtype;
  target_room public.rooms%rowtype;
  original_reservation_room_count integer;
  stay_nights integer;
  target_departure_date date;
  target_quote jsonb;
  quoted_room_subtotal numeric(12,2);
  before_json jsonb;
  after_json jsonb;
  action_name text;
  action_description text;
  next_room_status text;
begin
  perform private.assert_reservation_write_access(target_hotel_id);

  if target_room_id is null or target_arrival_date is null then
    raise exception 'Target room and arrival date are required.';
  end if;

  select reservation.*
  into current_reservation
  from public.reservations reservation
  where reservation.id = target_reservation_id
    and reservation.hotel_id = target_hotel_id
  for update;

  if not found then
    raise exception 'Reservation not found.';
  end if;

  if current_reservation.status not in ('tentative', 'confirmed') then
    raise exception
      'Only tentative or confirmed reservations may be moved on the calendar.';
  end if;

  if expected_updated_at is not null
     and current_reservation.updated_at is distinct from
       expected_updated_at
  then
    raise exception
      'Reservation changed after the calendar loaded. Refresh and try again.';
  end if;

  select reservation_room.*
  into current_room
  from public.reservation_rooms reservation_room
  where reservation_room.id = target_reservation_room_id
    and reservation_room.hotel_id = target_hotel_id
    and reservation_room.reservation_id = target_reservation_id
  for update;

  if not found then
    raise exception 'Reservation room record not found.';
  end if;

  select count(*)
  into original_reservation_room_count
  from public.reservation_rooms reservation_room
  where reservation_room.hotel_id = target_hotel_id
    and reservation_room.reservation_id = target_reservation_id;

  if original_reservation_room_count > 1
     and target_arrival_date is distinct from
       current_reservation.arrival_date
  then
    raise exception
      'Multi-room date movement requires the group-booking workflow.';
  end if;

  select room.*
  into target_room
  from public.rooms room
  where room.id = target_room_id
    and room.hotel_id = target_hotel_id
  for update;

  if not found then
    raise exception 'Target room does not belong to this hotel.';
  end if;

  if target_room.status in ('maintenance', 'out_of_order') then
    raise exception 'Target room is not operational.';
  end if;

  if target_room.room_type_id is distinct from
     current_room.room_type_id
  then
    raise exception
      'Drag-and-drop cannot change room type or rate. Use Reservation Edit.';
  end if;

  if not exists (
    select 1
    from public.room_types room_type
    where room_type.id = current_room.room_type_id
      and room_type.hotel_id = target_hotel_id
      and current_reservation.adults <= room_type.max_adults
      and current_reservation.children <= room_type.max_children
      and current_reservation.adults + current_reservation.children <=
        room_type.max_occupancy
  ) then
    raise exception 'Guest count exceeds the target room capacity.';
  end if;

  stay_nights :=
    current_reservation.departure_date
    - current_reservation.arrival_date;

  if stay_nights < 1 then
    raise exception 'Reservation stay length is invalid.';
  end if;

  target_departure_date := target_arrival_date + stay_nights;

  if target_departure_date - target_arrival_date > 365 then
    raise exception 'Reservation movement exceeds the maximum stay length.';
  end if;

  if current_room.rate_plan_id is null then
    raise exception
      'Calendar movement requires an assigned rate plan.';
  end if;

  target_quote := public.get_reservation_rate_quote(
    target_hotel_id,
    current_room.rate_plan_id,
    target_arrival_date,
    target_departure_date,
    current_room.adults,
    current_room.children
  );

  quoted_room_subtotal :=
    (target_quote->>'room_subtotal')::numeric(12,2);

  if quoted_room_subtotal is distinct from current_room.room_subtotal then
    raise exception
      'Target dates change the reservation rate. Use Reservation Edit to confirm the new amount.';
  end if;

  if not private.calendar_room_is_available(
    target_hotel_id,
    target_room_id,
    target_arrival_date,
    target_departure_date,
    current_room.id,
    null
  ) then
    raise exception
      'Target room is unavailable for the proposed dates.';
  end if;

  if current_room.room_id is not distinct from target_room_id
     and current_reservation.arrival_date is not distinct from
       target_arrival_date
  then
    raise exception 'No room or date change was proposed.';
  end if;

  before_json := private.build_reservation_json(
    target_hotel_id,
    target_reservation_id
  );

  action_name := case
    when current_room.room_id is null then
      'reservation.room_assigned'
    when current_room.room_id is distinct from target_room_id
      and current_reservation.arrival_date is distinct from
        target_arrival_date
      then 'reservation.calendar_moved'
    when current_room.room_id is distinct from target_room_id
      then 'reservation.room_reassigned'
    when current_reservation.arrival_date is distinct from
      target_arrival_date
      then 'reservation.dates_moved'
    else 'reservation.calendar_moved'
  end;

  action_description := format(
    'Reservation %s moved from room %s / %s to room %s / %s.',
    current_reservation.reservation_number,
    coalesce(
      (
        select room.room_number
        from public.rooms room
        where room.id = current_room.room_id
          and room.hotel_id = target_hotel_id
      ),
      'unassigned'
    ),
    current_reservation.arrival_date,
    target_room.room_number,
    target_arrival_date
  );

  -- Release the old allocation before updating dates and physical room.
  update public.reservation_rooms
  set status = 'released'
  where id = current_room.id
    and hotel_id = target_hotel_id;

  update public.reservations
  set
    arrival_date = target_arrival_date,
    departure_date = target_departure_date,
    updated_by = auth.uid(),
    updated_at = now()
  where id = target_reservation_id
    and hotel_id = target_hotel_id;

  next_room_status := case
    when current_reservation.status = 'confirmed'
      then 'confirmed'
    else 'held'
  end;

  update public.reservation_rooms
  set
    room_id = target_room_id,
    status = next_room_status,
    updated_at = now()
  where id = current_room.id
    and hotel_id = target_hotel_id;

  after_json := private.build_reservation_json(
    target_hotel_id,
    target_reservation_id
  );

  perform private.write_activity_log(
    target_hotel_id,
    action_name,
    'reservation',
    target_reservation_id,
    action_description,
    before_json,
    after_json,
    jsonb_build_object(
      'reservation_room_id', current_room.id,
      'from_room_id', current_room.room_id,
      'to_room_id', target_room_id,
      'from_arrival_date', current_reservation.arrival_date,
      'to_arrival_date', target_arrival_date,
      'from_departure_date', current_reservation.departure_date,
      'to_departure_date', target_departure_date,
      'stay_nights', stay_nights
    )
  );

  return after_json;
end;
$$;

-- ============================================================================
-- 5. ROOM-BLOCK WORKFLOWS
-- ============================================================================

create or replace function public.create_calendar_room_block(
  target_hotel_id uuid,
  block_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_room_id uuid;
  target_block_type text;
  target_start_date date;
  target_end_date date;
  target_reason text;
  created_block_id uuid;
  result jsonb;
begin
  perform private.assert_reservation_write_access(target_hotel_id);

  if block_payload is null then
    raise exception 'Room-block payload is required.';
  end if;

  target_room_id :=
    nullif(block_payload->>'room_id', '')::uuid;
  target_block_type :=
    lower(coalesce(
      nullif(trim(block_payload->>'block_type'), ''),
      'operational'
    ));
  target_start_date :=
    nullif(block_payload->>'start_date', '')::date;
  target_end_date :=
    nullif(block_payload->>'end_date', '')::date;
  target_reason :=
    nullif(trim(block_payload->>'reason'), '');

  if target_room_id is null
     or target_start_date is null
     or target_end_date is null
  then
    raise exception 'Room and block dates are required.';
  end if;

  if target_end_date <= target_start_date
     or target_end_date - target_start_date > 365
  then
    raise exception
      'Room-block length must be between 1 and 365 days.';
  end if;

  if target_block_type not in (
    'operational',
    'maintenance',
    'out_of_order',
    'owner_use',
    'deep_cleaning',
    'other'
  ) then
    raise exception 'Room-block type is invalid.';
  end if;

  if target_reason is null then
    raise exception 'Room-block reason is required.';
  end if;

  perform 1
  from public.rooms room
  where room.id = target_room_id
    and room.hotel_id = target_hotel_id
  for update;

  if not found then
    raise exception 'Room does not belong to this hotel.';
  end if;

  if not private.calendar_room_is_available(
    target_hotel_id,
    target_room_id,
    target_start_date,
    target_end_date,
    null,
    null
  ) then
    raise exception
      'Room cannot be blocked because the dates overlap active inventory.';
  end if;

  insert into public.room_blocks (
    hotel_id,
    room_id,
    block_type,
    status,
    start_date,
    end_date,
    reason,
    notes,
    created_by,
    updated_by
  )
  values (
    target_hotel_id,
    target_room_id,
    target_block_type,
    'active',
    target_start_date,
    target_end_date,
    target_reason,
    nullif(trim(block_payload->>'notes'), ''),
    auth.uid(),
    auth.uid()
  )
  returning id into created_block_id;

  result := private.build_room_block_json(
    target_hotel_id,
    created_block_id
  );

  perform private.write_activity_log(
    target_hotel_id,
    'room_block.created',
    'room_block',
    created_block_id,
    format(
      'Room %s blocked from %s to %s.',
      result->>'room_number',
      target_start_date,
      target_end_date
    ),
    null,
    result,
    jsonb_build_object(
      'block_type', target_block_type
    )
  );

  return result;
end;
$$;

create or replace function public.update_calendar_room_block(
  target_hotel_id uuid,
  target_room_block_id uuid,
  block_payload jsonb,
  expected_updated_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_block public.room_blocks%rowtype;
  target_room_id uuid;
  target_block_type text;
  target_start_date date;
  target_end_date date;
  target_reason text;
  before_json jsonb;
  after_json jsonb;
begin
  perform private.assert_reservation_write_access(target_hotel_id);

  if block_payload is null then
    raise exception 'Room-block payload is required.';
  end if;

  select block.*
  into current_block
  from public.room_blocks block
  where block.id = target_room_block_id
    and block.hotel_id = target_hotel_id
  for update;

  if not found then
    raise exception 'Room block not found.';
  end if;

  if current_block.status <> 'active' then
    raise exception 'Only active room blocks may be edited.';
  end if;

  if expected_updated_at is not null
     and current_block.updated_at is distinct from
       expected_updated_at
  then
    raise exception
      'Room block changed after the calendar loaded. Refresh and try again.';
  end if;

  target_room_id := coalesce(
    nullif(block_payload->>'room_id', '')::uuid,
    current_block.room_id
  );
  target_block_type := lower(coalesce(
    nullif(trim(block_payload->>'block_type'), ''),
    current_block.block_type
  ));
  target_start_date := coalesce(
    nullif(block_payload->>'start_date', '')::date,
    current_block.start_date
  );
  target_end_date := coalesce(
    nullif(block_payload->>'end_date', '')::date,
    current_block.end_date
  );
  target_reason := coalesce(
    nullif(trim(block_payload->>'reason'), ''),
    current_block.reason
  );

  if target_end_date <= target_start_date
     or target_end_date - target_start_date > 365
  then
    raise exception
      'Room-block length must be between 1 and 365 days.';
  end if;

  if target_block_type not in (
    'operational',
    'maintenance',
    'out_of_order',
    'owner_use',
    'deep_cleaning',
    'other'
  ) then
    raise exception 'Room-block type is invalid.';
  end if;

  perform 1
  from public.rooms room
  where room.id = target_room_id
    and room.hotel_id = target_hotel_id
  for update;

  if not found then
    raise exception 'Room does not belong to this hotel.';
  end if;

  if not private.calendar_room_is_available(
    target_hotel_id,
    target_room_id,
    target_start_date,
    target_end_date,
    null,
    current_block.id
  ) then
    raise exception
      'Room-block update overlaps active inventory.';
  end if;

  before_json := private.build_room_block_json(
    target_hotel_id,
    current_block.id
  );

  update public.room_blocks
  set
    room_id = target_room_id,
    block_type = target_block_type,
    start_date = target_start_date,
    end_date = target_end_date,
    reason = target_reason,
    notes = case
      when block_payload ? 'notes'
        then nullif(trim(block_payload->>'notes'), '')
      else notes
    end,
    updated_by = auth.uid(),
    updated_at = now()
  where id = current_block.id
    and hotel_id = target_hotel_id;

  after_json := private.build_room_block_json(
    target_hotel_id,
    current_block.id
  );

  perform private.write_activity_log(
    target_hotel_id,
    'room_block.updated',
    'room_block',
    current_block.id,
    format(
      'Room block for room %s was updated.',
      after_json->>'room_number'
    ),
    before_json,
    after_json,
    '{}'::jsonb
  );

  return after_json;
end;
$$;

create or replace function public.change_calendar_room_block_status(
  target_hotel_id uuid,
  target_room_block_id uuid,
  target_status text,
  reason text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_block public.room_blocks%rowtype;
  normalized_status text;
  normalized_reason text;
  before_json jsonb;
  after_json jsonb;
begin
  perform private.assert_reservation_write_access(target_hotel_id);

  normalized_status := lower(trim(coalesce(target_status, '')));
  normalized_reason := nullif(trim(reason), '');

  if normalized_status not in ('released', 'cancelled') then
    raise exception
      'Room-block status may change only to released or cancelled.';
  end if;

  if normalized_reason is null then
    raise exception 'Room-block release/cancellation reason is required.';
  end if;

  select block.*
  into current_block
  from public.room_blocks block
  where block.id = target_room_block_id
    and block.hotel_id = target_hotel_id
  for update;

  if not found then
    raise exception 'Room block not found.';
  end if;

  if current_block.status <> 'active' then
    raise exception 'Only active room blocks may be released or cancelled.';
  end if;

  before_json := private.build_room_block_json(
    target_hotel_id,
    current_block.id
  );

  update public.room_blocks
  set
    status = normalized_status,
    release_reason = normalized_reason,
    released_at = now(),
    released_by = auth.uid(),
    updated_by = auth.uid(),
    updated_at = now()
  where id = current_block.id
    and hotel_id = target_hotel_id;

  after_json := private.build_room_block_json(
    target_hotel_id,
    current_block.id
  );

  perform private.write_activity_log(
    target_hotel_id,
    'room_block.' || normalized_status,
    'room_block',
    current_block.id,
    format(
      'Room block for room %s changed to %s.',
      after_json->>'room_number',
      normalized_status
    ),
    before_json,
    after_json,
    jsonb_build_object('reason', normalized_reason)
  );

  return after_json;
end;
$$;

create or replace function public.get_calendar_room_block_details(
  target_hotel_id uuid,
  target_room_block_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  result jsonb;
begin
  if not private.user_has_hotel_access(target_hotel_id) then
    raise exception 'Hotel access denied.';
  end if;

  result := private.build_room_block_json(
    target_hotel_id,
    target_room_block_id
  );

  if result is null then
    raise exception 'Room block not found.';
  end if;

  return result;
end;
$$;

-- ============================================================================
-- 6. FUNCTION PERMISSIONS
-- ============================================================================

revoke all on function private.calendar_room_is_available(
  uuid,uuid,date,date,uuid,uuid
) from public;
revoke all on function private.build_room_block_json(uuid,uuid)
from public;

revoke all on function public.get_booking_calendar(
  uuid,date,date,uuid,text[],text[],integer,integer
) from public;
revoke all on function public.move_reservation_on_calendar(
  uuid,uuid,uuid,uuid,date,timestamptz
) from public;
revoke all on function public.create_calendar_room_block(uuid,jsonb)
from public;
revoke all on function public.update_calendar_room_block(
  uuid,uuid,jsonb,timestamptz
) from public;
revoke all on function public.change_calendar_room_block_status(
  uuid,uuid,text,text
) from public;
revoke all on function public.get_calendar_room_block_details(uuid,uuid)
from public;

grant execute on function public.get_booking_calendar(
  uuid,date,date,uuid,text[],text[],integer,integer
) to authenticated;
grant execute on function public.move_reservation_on_calendar(
  uuid,uuid,uuid,uuid,date,timestamptz
) to authenticated;
grant execute on function public.create_calendar_room_block(uuid,jsonb)
to authenticated;
grant execute on function public.update_calendar_room_block(
  uuid,uuid,jsonb,timestamptz
) to authenticated;
grant execute on function public.change_calendar_room_block_status(
  uuid,uuid,text,text
) to authenticated;
grant execute on function public.get_calendar_room_block_details(uuid,uuid)
to authenticated;

-- ============================================================================
-- 7. FINAL ASSERTIONS
-- ============================================================================

do $$
begin
  if to_regprocedure(
    'public.get_booking_calendar(uuid,date,date,uuid,text[],text[],integer,integer)'
  ) is null
     or to_regprocedure(
       'public.move_reservation_on_calendar(uuid,uuid,uuid,uuid,date,timestamptz)'
     ) is null
     or to_regprocedure(
       'public.create_calendar_room_block(uuid,jsonb)'
     ) is null
     or to_regprocedure(
       'public.update_calendar_room_block(uuid,uuid,jsonb,timestamptz)'
     ) is null
     or to_regprocedure(
       'public.change_calendar_room_block_status(uuid,uuid,text,text)'
     ) is null
  then
    raise exception
      'Migration stopped: one or more Day 4 functions are missing.';
  end if;

  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'room_blocks'
      and column_name = 'release_reason'
  ) then
    raise exception
      'Migration stopped: room-block release metadata is missing.';
  end if;

  if to_regclass('public.idx_reservation_rooms_unallocated') is null
     or to_regclass('public.idx_room_blocks_hotel_updated') is null
  then
    raise exception
      'Migration stopped: Day 4 supporting indexes are missing.';
  end if;
end
$$;

commit;

-- Supabase may display one blank pg_advisory_xact_lock result row.
-- That is expected and is not an error.
