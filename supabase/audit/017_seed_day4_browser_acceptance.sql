-- ============================================================================
-- StayQR Day 4 — Browser Acceptance Seed
--
-- Creates a controlled far-future calendar dataset for final browser QA:
-- every reservation status, three block types, a direct stay, an unallocated
-- booking, and 20 temporary rooms to force room pagination.
--
-- Run once as postgres. Keep the returned JSON screenshot.
-- Cleanup only with audit 018 after browser QA is complete.
-- ============================================================================

create table if not exists private.day4_browser_acceptance_state_20260723 (
  singleton boolean primary key default true check (singleton),
  payload jsonb not null,
  created_at timestamptz not null default now()
);

create or replace function private.seed_day4_browser_acceptance_20260723()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user uuid;
  target_hotel uuid;
  target_hotel_name text;
  hotel_timezone text;
  source_room uuid;
  source_room_type uuid;
  source_room_type_name text;
  source_rate_plan uuid;

  test_start date := current_date + 2300;
  test_end date := current_date + 2302;
  test_sequence_year integer := extract(year from (current_date + 2300))::integer;
  sequence_existed boolean := false;
  sequence_before bigint;

  test_guest uuid;
  direct_guest uuid;
  test_rate uuid;
  direct_session uuid;
  room_ids uuid[] := array[]::uuid[];
  room_id uuid;
  generated_room_number text;
  prefix text := 'D4QA-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6));
  created jsonb;
  created_id uuid;
  created_room_id uuid;
  block_one jsonb;
  block_two jsonb;
  block_three jsonb;
  reservation_ids uuid[] := array[]::uuid[];
  block_ids uuid[] := array[]::uuid[];
  source_references text[] := array[]::text[];
  i integer;
begin
  if exists (
    select 1
    from private.day4_browser_acceptance_state_20260723
  ) then
    raise exception
      'Day 4 browser acceptance data already exists. Run audit 018 before reseeding.';
  end if;

  if exists (
    select 1
    from public.reservations reservation
    where reservation.source_reference like 'DAY4-ACCEPT-%'
  ) then
    raise exception
      'Existing DAY4-ACCEPT reservations were found. Run audit 018 before reseeding.';
  end if;

  select administrator.user_id
  into actor_user
  from public.platform_admins administrator
  where administrator.status = 'active'
  order by administrator.created_at
  limit 1;

  if actor_user is null then
    raise exception 'Browser acceptance seed requires an active platform administrator.';
  end if;

  perform set_config(
    'request.jwt.claim.sub',
    actor_user::text,
    true
  );

  select
    hotel.id,
    hotel.hotel_name,
    coalesce(hotel.timezone, 'UTC'),
    room.id,
    room.room_type_id,
    room_type.name,
    rate_plan.id
  into
    target_hotel,
    target_hotel_name,
    hotel_timezone,
    source_room,
    source_room_type,
    source_room_type_name,
    source_rate_plan
  from public.hotels hotel
  join public.rooms room
    on room.hotel_id = hotel.id
   and room.status not in ('maintenance', 'out_of_order')
  join public.room_types room_type
    on room_type.id = room.room_type_id
   and room_type.hotel_id = room.hotel_id
   and room_type.is_active
  join lateral (
    select candidate.id
    from public.rate_plans candidate
    where candidate.hotel_id = room.hotel_id
      and candidate.room_type_id = room.room_type_id
      and candidate.is_active
    order by candidate.priority, candidate.created_at
    limit 1
  ) rate_plan on true
  where hotel.status = 'active'
  order by hotel.created_at, room.created_at
  limit 1;

  if target_hotel is null then
    raise exception
      'Browser acceptance seed requires an active hotel, room type and rate plan.';
  end if;

  select exists (
    select 1
    from public.reservation_number_sequences sequence
    where sequence.hotel_id = target_hotel
      and sequence.sequence_year = test_sequence_year
  )
  into sequence_existed;

  if sequence_existed then
    select sequence.last_number
    into sequence_before
    from public.reservation_number_sequences sequence
    where sequence.hotel_id = target_hotel
      and sequence.sequence_year = test_sequence_year;
  end if;

  for i in 1..20 loop
    generated_room_number := prefix || '-' || lpad(i::text, 2, '0');

    insert into public.rooms (
      hotel_id,
      room_number,
      room_type,
      room_type_id,
      status
    )
    select
      target_hotel,
      generated_room_number,
      source.room_type,
      source_room_type,
      'available'
    from public.rooms source
    where source.id = source_room
      and source.hotel_id = target_hotel
    returning id into room_id;

    room_ids := array_append(room_ids, room_id);
  end loop;

  insert into public.guests (
    hotel_id,
    full_name,
    phone,
    email,
    preferred_language
  )
  values (
    target_hotel,
    'StayQR Day 4 Browser Acceptance Guest',
    '9000040404',
    'day4-browser-acceptance@stayqr.invalid',
    'english'
  )
  returning id into test_guest;

  insert into public.guests (
    hotel_id,
    full_name,
    phone,
    email,
    preferred_language
  )
  values (
    target_hotel,
    'StayQR Day 4 Direct Stay Guest',
    '9000040405',
    'day4-direct-stay@stayqr.invalid',
    'english'
  )
  returning id into direct_guest;

  insert into public.seasonal_rates (
    hotel_id,
    rate_plan_id,
    name,
    start_date,
    end_date,
    nightly_rate,
    priority,
    is_active
  )
  values (
    target_hotel,
    source_rate_plan,
    'Day 4 Browser Acceptance Fixed Rate',
    test_start - 2,
    test_start + 35,
    1500,
    -4000,
    true
  )
  returning id into test_rate;

  -- Draft reservation on Room 01.
  source_references := array_append(source_references, 'DAY4-ACCEPT-DRAFT');
  created := public.create_reservation(
    target_hotel,
    jsonb_build_object(
      'status', 'draft',
      'booking_source', 'other',
      'source_reference', 'DAY4-ACCEPT-DRAFT',
      'arrival_date', test_start,
      'departure_date', test_end,
      'adults', 1,
      'children', 0,
      'room_type_id', source_room_type,
      'room_id', room_ids[1],
      'rate_plan_id', source_rate_plan,
      'guest', jsonb_build_object('id', test_guest),
      'internal_notes', 'Day 4 status rendering: Draft'
    )
  );
  reservation_ids := array_append(reservation_ids, (created->>'id')::uuid);

  -- Tentative reservation on Room 02.
  source_references := array_append(source_references, 'DAY4-ACCEPT-TENTATIVE');
  created := public.create_reservation(
    target_hotel,
    jsonb_build_object(
      'status', 'tentative',
      'booking_source', 'other',
      'source_reference', 'DAY4-ACCEPT-TENTATIVE',
      'arrival_date', test_start,
      'departure_date', test_end,
      'adults', 1,
      'children', 0,
      'room_type_id', source_room_type,
      'room_id', room_ids[2],
      'rate_plan_id', source_rate_plan,
      'guest', jsonb_build_object('id', test_guest),
      'internal_notes', 'Day 4 status rendering: Tentative'
    )
  );
  reservation_ids := array_append(reservation_ids, (created->>'id')::uuid);

  -- Confirmed reservation used for Edit + Cancel refresh testing on Room 03.
  source_references := array_append(source_references, 'DAY4-ACCEPT-CONFIRMED-EDIT-CANCEL');
  created := public.create_reservation(
    target_hotel,
    jsonb_build_object(
      'status', 'confirmed',
      'booking_source', 'website',
      'source_reference', 'DAY4-ACCEPT-CONFIRMED-EDIT-CANCEL',
      'arrival_date', test_start,
      'departure_date', test_end,
      'adults', 2,
      'children', 0,
      'room_type_id', source_room_type,
      'room_id', room_ids[3],
      'rate_plan_id', source_rate_plan,
      'guest', jsonb_build_object('id', test_guest),
      'internal_notes', 'Use this record for Open Reservation, edit and cancellation refresh tests'
    )
  );
  reservation_ids := array_append(reservation_ids, (created->>'id')::uuid);

  -- Second confirmed reservation used for No-show refresh testing on Room 13.
  source_references := array_append(source_references, 'DAY4-ACCEPT-CONFIRMED-NOSHOW');
  created := public.create_reservation(
    target_hotel,
    jsonb_build_object(
      'status', 'confirmed',
      'booking_source', 'phone',
      'source_reference', 'DAY4-ACCEPT-CONFIRMED-NOSHOW',
      'arrival_date', test_start,
      'departure_date', test_end,
      'adults', 1,
      'children', 0,
      'room_type_id', source_room_type,
      'room_id', room_ids[13],
      'rate_plan_id', source_rate_plan,
      'guest', jsonb_build_object('id', test_guest),
      'internal_notes', 'Use this record for no-show calendar refresh testing'
    )
  );
  reservation_ids := array_append(reservation_ids, (created->>'id')::uuid);

  -- Checked-in reservation on Room 04.
  source_references := array_append(source_references, 'DAY4-ACCEPT-CHECKED-IN');
  created := public.create_reservation(
    target_hotel,
    jsonb_build_object(
      'status', 'confirmed',
      'booking_source', 'other',
      'source_reference', 'DAY4-ACCEPT-CHECKED-IN',
      'arrival_date', test_start,
      'departure_date', test_end,
      'adults', 1,
      'children', 0,
      'room_type_id', source_room_type,
      'room_id', room_ids[4],
      'rate_plan_id', source_rate_plan,
      'guest', jsonb_build_object('id', test_guest)
    )
  );
  created_id := (created->>'id')::uuid;
  created_room_id := (created->'rooms'->0->>'id')::uuid;
  reservation_ids := array_append(reservation_ids, created_id);
  update public.reservations
  set status = 'checked_in', updated_by = actor_user, updated_at = now()
  where hotel_id = target_hotel and id = created_id;
  update public.reservation_rooms
  set status = 'checked_in', updated_at = now()
  where hotel_id = target_hotel and id = created_room_id;

  -- Checked-out historical reservation on Room 05.
  source_references := array_append(source_references, 'DAY4-ACCEPT-CHECKED-OUT');
  created := public.create_reservation(
    target_hotel,
    jsonb_build_object(
      'status', 'confirmed',
      'booking_source', 'other',
      'source_reference', 'DAY4-ACCEPT-CHECKED-OUT',
      'arrival_date', test_start,
      'departure_date', test_end,
      'adults', 1,
      'children', 0,
      'room_type_id', source_room_type,
      'room_id', room_ids[5],
      'rate_plan_id', source_rate_plan,
      'guest', jsonb_build_object('id', test_guest)
    )
  );
  created_id := (created->>'id')::uuid;
  created_room_id := (created->'rooms'->0->>'id')::uuid;
  reservation_ids := array_append(reservation_ids, created_id);
  update public.reservations
  set status = 'checked_in', updated_by = actor_user, updated_at = now()
  where hotel_id = target_hotel and id = created_id;
  update public.reservation_rooms
  set status = 'checked_in', updated_at = now()
  where hotel_id = target_hotel and id = created_room_id;
  update public.reservations
  set status = 'checked_out', updated_by = actor_user, updated_at = now()
  where hotel_id = target_hotel and id = created_id;
  update public.reservation_rooms
  set status = 'checked_out', updated_at = now()
  where hotel_id = target_hotel and id = created_room_id;

  -- Cancelled historical reservation on Room 06.
  source_references := array_append(source_references, 'DAY4-ACCEPT-CANCELLED');
  created := public.create_reservation(
    target_hotel,
    jsonb_build_object(
      'status', 'confirmed',
      'booking_source', 'other',
      'source_reference', 'DAY4-ACCEPT-CANCELLED',
      'arrival_date', test_start,
      'departure_date', test_end,
      'adults', 1,
      'children', 0,
      'room_type_id', source_room_type,
      'room_id', room_ids[6],
      'rate_plan_id', source_rate_plan,
      'guest', jsonb_build_object('id', test_guest)
    )
  );
  created_id := (created->>'id')::uuid;
  reservation_ids := array_append(reservation_ids, created_id);
  perform public.change_reservation_status(
    target_hotel,
    created_id,
    'cancelled',
    'Day 4 browser acceptance pre-seeded cancellation'
  );

  -- No-show historical reservation on Room 07.
  source_references := array_append(source_references, 'DAY4-ACCEPT-NO-SHOW');
  created := public.create_reservation(
    target_hotel,
    jsonb_build_object(
      'status', 'confirmed',
      'booking_source', 'other',
      'source_reference', 'DAY4-ACCEPT-NO-SHOW',
      'arrival_date', test_start,
      'departure_date', test_end,
      'adults', 1,
      'children', 0,
      'room_type_id', source_room_type,
      'room_id', room_ids[7],
      'rate_plan_id', source_rate_plan,
      'guest', jsonb_build_object('id', test_guest)
    )
  );
  created_id := (created->>'id')::uuid;
  reservation_ids := array_append(reservation_ids, created_id);
  perform public.change_reservation_status(
    target_hotel,
    created_id,
    'no_show',
    'Day 4 browser acceptance pre-seeded no-show'
  );

  -- Unallocated tentative reservation for queue drag on Room 12 target.
  source_references := array_append(source_references, 'DAY4-ACCEPT-UNALLOCATED');
  created := public.create_reservation(
    target_hotel,
    jsonb_build_object(
      'status', 'draft',
      'booking_source', 'other',
      'source_reference', 'DAY4-ACCEPT-UNALLOCATED',
      'arrival_date', test_start + 3,
      'departure_date', test_start + 5,
      'adults', 1,
      'children', 0,
      'room_type_id', source_room_type,
      'rate_plan_id', source_rate_plan,
      'guest', jsonb_build_object('id', test_guest),
      'internal_notes', 'Drag this queue record into a compatible free temporary room'
    )
  );
  created_id := (created->>'id')::uuid;
  reservation_ids := array_append(reservation_ids, created_id);
  update public.reservations
  set status = 'tentative', updated_by = actor_user, updated_at = now()
  where hotel_id = target_hotel and id = created_id;

  block_one := public.create_calendar_room_block(
    target_hotel,
    jsonb_build_object(
      'room_id', room_ids[8],
      'block_type', 'maintenance',
      'start_date', test_start,
      'end_date', test_end,
      'reason', 'DAY4 ACCEPT Maintenance block',
      'notes', 'Open details to verify Created by; then leave for cleanup.'
    )
  );
  block_ids := array_append(block_ids, (block_one->>'id')::uuid);

  block_two := public.create_calendar_room_block(
    target_hotel,
    jsonb_build_object(
      'room_id', room_ids[9],
      'block_type', 'operational',
      'start_date', test_start,
      'end_date', test_end,
      'reason', 'DAY4 ACCEPT Operational block — cancel this in browser',
      'notes', 'Use mandatory reason: Day 4 browser cancellation passed'
    )
  );
  block_ids := array_append(block_ids, (block_two->>'id')::uuid);

  block_three := public.create_calendar_room_block(
    target_hotel,
    jsonb_build_object(
      'room_id', room_ids[10],
      'block_type', 'out_of_order',
      'start_date', test_start,
      'end_date', test_end,
      'reason', 'DAY4 ACCEPT Out-of-order block',
      'notes', 'Status and legend rendering verification'
    )
  );
  block_ids := array_append(block_ids, (block_three->>'id')::uuid);

  insert into public.guest_sessions (
    hotel_id,
    room_id,
    guest_id,
    checkin_time,
    checkout_time,
    status
  )
  values (
    target_hotel,
    room_ids[11],
    direct_guest,
    (test_start::timestamp + interval '14 hours') at time zone hotel_timezone,
    (test_end::timestamp + interval '11 hours') at time zone hotel_timezone,
    'active'
  )
  returning id into direct_session;

  insert into private.day4_browser_acceptance_state_20260723 (
    singleton,
    payload
  )
  values (
    true,
    jsonb_build_object(
      'actor_user', actor_user,
      'hotel_id', target_hotel,
      'hotel_name', target_hotel_name,
      'hotel_timezone', hotel_timezone,
      'test_start', test_start,
      'test_end', test_end,
      'room_type_id', source_room_type,
      'room_type_name', source_room_type_name,
      'rate_plan_id', source_rate_plan,
      'room_prefix', prefix,
      'room_ids', to_jsonb(room_ids),
      'reservation_ids', to_jsonb(reservation_ids),
      'source_references', to_jsonb(source_references),
      'block_ids', to_jsonb(block_ids),
      'guest_ids', jsonb_build_array(test_guest, direct_guest),
      'guest_session_id', direct_session,
      'seasonal_rate_id', test_rate,
      'sequence_year', test_sequence_year,
      'sequence_existed', sequence_existed,
      'sequence_before', sequence_before
    )
  );

  return jsonb_build_object(
    'result', 'DAY 4 BROWSER ACCEPTANCE DATA CREATED',
    'hotel', target_hotel_name,
    'date_to_open', test_start,
    'week_range', format('%s to %s', test_start, test_start + 6),
    'month_to_open', to_char(test_start, 'YYYY-MM'),
    'room_type_filter', source_room_type_name,
    'temporary_room_prefix', prefix,
    'temporary_rooms', cardinality(room_ids),
    'reservation_records', cardinality(reservation_ids),
    'room_blocks', cardinality(block_ids),
    'direct_stay_session', direct_session,
    'unallocated_source_reference', 'DAY4-ACCEPT-UNALLOCATED',
    'cleanup_instruction', 'Run audit 018 only after browser acceptance is complete.'
  );
exception
  when others then
    -- The state row is written last. If setup fails before that point, remove
    -- records by the unique acceptance prefixes and references.
    if target_hotel is not null then
      delete from public.activity_logs log
      where log.hotel_id = target_hotel
        and (
          log.entity_id = any(reservation_ids)
          or log.entity_id = any(block_ids)
          or log.entity_id = direct_session
        );

      delete from public.reservations reservation
      where reservation.hotel_id = target_hotel
        and (
          reservation.id = any(reservation_ids)
          or reservation.source_reference like 'DAY4-ACCEPT-%'
        );

      delete from public.room_blocks block
      where block.hotel_id = target_hotel
        and (
          block.id = any(block_ids)
          or block.reason like 'DAY4 ACCEPT%'
        );

      if direct_session is not null then
        delete from public.guest_sessions session
        where session.hotel_id = target_hotel
          and session.id = direct_session;
      end if;

      if test_rate is not null then
        delete from public.seasonal_rates rate
        where rate.hotel_id = target_hotel
          and rate.id = test_rate;
      end if;

      if test_guest is not null or direct_guest is not null then
        delete from public.guests guest
        where guest.hotel_id = target_hotel
          and guest.id in (test_guest, direct_guest);
      end if;

      delete from public.rooms room
      where room.hotel_id = target_hotel
        and (
          room.id = any(room_ids)
          or room.room_number like prefix || '%'
        );

      if sequence_existed then
        update public.reservation_number_sequences sequence
        set last_number = sequence_before
        where sequence.hotel_id = target_hotel
          and sequence.sequence_year = test_sequence_year;
      else
        delete from public.reservation_number_sequences sequence
        where sequence.hotel_id = target_hotel
          and sequence.sequence_year = test_sequence_year;
      end if;
    end if;

    raise;
end;
$$;

revoke all on function private.seed_day4_browser_acceptance_20260723()
from public;

select jsonb_pretty(
  private.seed_day4_browser_acceptance_20260723()
) as stayqr_day4_browser_acceptance_seed;
