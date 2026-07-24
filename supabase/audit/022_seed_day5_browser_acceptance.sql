-- ============================================================================
-- StayQR Day 5 — Deterministic Browser Acceptance Seed
--
-- Creates a controlled current-date dataset for the Arrivals & Departures,
-- atomic reservation check-in, deposit transfer, multi-room partial check-in,
-- confirmation output and failure/rollback browser tests.
--
-- Run once as postgres. Keep the returned JSON screenshot.
-- Cleanup only with audit 023 after Day 5 browser acceptance is complete.
-- ============================================================================

create table if not exists private.day5_browser_acceptance_state_20260724 (
  singleton boolean primary key default true check (singleton),
  payload jsonb not null,
  created_at timestamptz not null default now()
);

create or replace function private.seed_day5_browser_acceptance_20260724()
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
  source_currency_code text;
  temporary_rate_plan_created boolean := false;
  temporary_rate_plan_code text;
  test_today date;
  test_sequence_year integer;
  sequence_existed boolean := false;
  sequence_before bigint;
  room_ids uuid[] := array[]::uuid[];
  room_id uuid;
  generated_room_number text;
  room_prefix text := 'D5QA-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6));
  created jsonb;
  group_created jsonb;
  group_after_add jsonb;
  inhouse_created jsonb;
  atomic_quote jsonb;
  atomic_deposit numeric(12,2);
  group_updated_at timestamptz;
  inhouse_result jsonb;
  i integer;
begin
  if exists (select 1 from private.day5_browser_acceptance_state_20260724) then
    raise exception 'Day 5 browser acceptance data already exists. Run audit 023 before reseeding.';
  end if;

  if exists (
    select 1 from public.reservations r
    where r.source_reference like 'DAY5-ACCEPT-%'
  ) then
    raise exception 'Existing DAY5-ACCEPT reservations were found. Run audit 023 before reseeding.';
  end if;

  select pa.user_id
  into actor_user
  from public.platform_admins pa
  where pa.status = 'active'
  order by pa.created_at
  limit 1;

  if actor_user is null then
    raise exception 'Day 5 browser acceptance requires an active platform administrator.';
  end if;

  perform set_config('request.jwt.claim.sub', actor_user::text, true);

  -- Select the hotel/room foundation independently from rate plans. Some
  -- existing properties legitimately have zero-value legacy rate plans, so
  -- the acceptance seed must not fail only because production pricing has not
  -- yet been configured. In that case, a temporary positive test rate plan is
  -- created and removed by audit 023.
  select
    h.id,
    h.hotel_name,
    coalesce(h.timezone, 'UTC'),
    coalesce(nullif(trim(h.currency_code), ''), 'INR'),
    rm.id,
    rm.room_type_id,
    rt.name
  into
    target_hotel,
    target_hotel_name,
    hotel_timezone,
    source_currency_code,
    source_room,
    source_room_type,
    source_room_type_name
  from public.hotels h
  join public.rooms rm
    on rm.hotel_id = h.id
   and rm.room_type_id is not null
   and rm.status not in ('maintenance', 'out_of_order')
  join public.room_types rt
    on rt.hotel_id = rm.hotel_id
   and rt.id = rm.room_type_id
   and rt.is_active
  where h.status = 'active'
  order by
    case when lower(h.hotel_name) = 'vd stay inn' then 0 else 1 end,
    h.created_at,
    rm.created_at
  limit 1;

  if target_hotel is null then
    raise exception 'Day 5 seed requires an active hotel with at least one room linked to an active room type.';
  end if;

  select candidate.id
  into source_rate_plan
  from public.rate_plans candidate
  where candidate.hotel_id = target_hotel
    and candidate.room_type_id = source_room_type
    and candidate.is_active
    and candidate.base_rate > 0
  order by candidate.priority, candidate.created_at
  limit 1;

  if source_rate_plan is null then
    temporary_rate_plan_code :=
      'D5QA-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10));

    insert into public.rate_plans (
      hotel_id,
      room_type_id,
      name,
      code,
      description,
      meal_plan,
      currency_code,
      base_rate,
      extra_adult_rate,
      extra_child_rate,
      minimum_stay,
      is_refundable,
      is_active,
      priority
    )
    select
      target_hotel,
      rt.id,
      'Day 5 Acceptance Rate',
      temporary_rate_plan_code,
      'Temporary positive rate used only by the controlled Day 5 browser acceptance dataset.',
      'room_only',
      source_currency_code,
      greatest(coalesce(rt.base_rate, 0), 1500)::numeric(12,2),
      greatest(coalesce(rt.extra_adult_rate, 0), 0)::numeric(12,2),
      greatest(coalesce(rt.extra_child_rate, 0), 0)::numeric(12,2),
      1,
      true,
      true,
      1
    from public.room_types rt
    where rt.hotel_id = target_hotel
      and rt.id = source_room_type
      and rt.is_active
    returning id into source_rate_plan;

    if source_rate_plan is null then
      raise exception 'Day 5 seed could not create a temporary positive rate plan for the selected room type.';
    end if;

    temporary_rate_plan_created := true;
  end if;

  test_today := (now() at time zone hotel_timezone)::date;
  test_sequence_year := extract(year from test_today)::integer;

  select exists (
    select 1
    from public.reservation_number_sequences s
    where s.hotel_id = target_hotel
      and s.sequence_year = test_sequence_year
  ) into sequence_existed;

  if sequence_existed then
    select s.last_number
    into sequence_before
    from public.reservation_number_sequences s
    where s.hotel_id = target_hotel
      and s.sequence_year = test_sequence_year;
  end if;

  for i in 1..7 loop
    generated_room_number := room_prefix || '-' || lpad(i::text, 2, '0');

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
      src.room_type,
      source_room_type,
      'available'
    from public.rooms src
    where src.id = source_room
      and src.hotel_id = target_hotel
    returning id into room_id;

    room_ids := array_append(room_ids, room_id);
  end loop;

  atomic_quote := public.get_reservation_rate_quote(
    target_hotel,
    source_rate_plan,
    test_today,
    test_today + 2,
    1,
    0
  );
  atomic_deposit := least(
    500::numeric,
    (atomic_quote->>'total_amount')::numeric
  )::numeric(12,2);

  if atomic_deposit <= 0 then
    raise exception 'Day 5 deposit-transfer test requires a positive reservation total.';
  end if;

  -- 1. Atomic check-in + positive deposit-transfer candidate.
  created := public.create_reservation(
    target_hotel,
    jsonb_build_object(
      'status', 'confirmed',
      'booking_source', 'website',
      'source_reference', 'DAY5-ACCEPT-ATOMIC-CHECKIN',
      'arrival_date', test_today,
      'departure_date', test_today + 2,
      'expected_checkin_time', '14:00',
      'expected_checkout_time', '11:00',
      'adults', 1,
      'children', 0,
      'room_type_id', source_room_type,
      'room_id', room_ids[1],
      'rate_plan_id', source_rate_plan,
      'deposit_required', atomic_deposit,
      'deposit_amount', atomic_deposit,
      'payment_method', 'upi',
      'payment_reference', 'DAY5-ACCEPT-DEPOSIT-UPI',
      'payment_notes', 'Transfer exactly once during atomic check-in',
      'internal_notes', 'Primary Day 5 atomic check-in and deposit-transfer browser test',
      'guest', jsonb_build_object(
        'full_name', 'StayQR Day 5 Atomic Check-In Guest',
        'phone', '9000050501',
        'email', 'day5-atomic@stayqr.invalid',
        'preferred_language', 'english'
      )
    )
  );

  -- 2. Two-room group booking. Check in one room and verify the other remains.
  group_created := public.create_reservation(
    target_hotel,
    jsonb_build_object(
      'status', 'confirmed',
      'booking_source', 'other',
      'source_reference', 'DAY5-ACCEPT-GROUP',
      'arrival_date', test_today,
      'departure_date', test_today + 3,
      'expected_checkin_time', '14:00',
      'expected_checkout_time', '11:00',
      'adults', 1,
      'children', 0,
      'room_type_id', source_room_type,
      'room_id', room_ids[2],
      'rate_plan_id', source_rate_plan,
      'internal_notes', 'Day 5 two-room partial group check-in test',
      'guest', jsonb_build_object(
        'full_name', 'StayQR Day 5 Group Booking Guest',
        'phone', '9000050502',
        'email', 'day5-group@stayqr.invalid',
        'preferred_language', 'english'
      )
    )
  );

  group_updated_at := (group_created->>'updated_at')::timestamptz;

  group_after_add := public.add_reservation_room(
    target_hotel,
    (group_created->>'id')::uuid,
    jsonb_build_object(
      'room_type_id', source_room_type,
      'room_id', room_ids[3],
      'rate_plan_id', source_rate_plan,
      'adults', 1,
      'children', 0,
      'notes', 'Second room of the controlled Day 5 group booking'
    ),
    group_updated_at
  );

  -- 3. Upcoming confirmed arrival.
  created := public.create_reservation(
    target_hotel,
    jsonb_build_object(
      'status', 'confirmed',
      'booking_source', 'phone',
      'source_reference', 'DAY5-ACCEPT-UPCOMING',
      'arrival_date', test_today + 1,
      'departure_date', test_today + 3,
      'adults', 1,
      'children', 0,
      'room_type_id', source_room_type,
      'room_id', room_ids[4],
      'rate_plan_id', source_rate_plan,
      'internal_notes', 'Upcoming-arrivals queue verification',
      'guest', jsonb_build_object(
        'full_name', 'StayQR Day 5 Upcoming Guest',
        'phone', '9000050503',
        'email', 'day5-upcoming@stayqr.invalid',
        'preferred_language', 'english'
      )
    )
  );

  -- 4. Overdue confirmed arrival that has not checked in.
  created := public.create_reservation(
    target_hotel,
    jsonb_build_object(
      'status', 'confirmed',
      'booking_source', 'walk_in',
      'source_reference', 'DAY5-ACCEPT-OVERDUE',
      'arrival_date', test_today - 1,
      'departure_date', test_today + 2,
      'adults', 1,
      'children', 0,
      'room_type_id', source_room_type,
      'room_id', room_ids[5],
      'rate_plan_id', source_rate_plan,
      'internal_notes', 'Overdue-arrivals queue verification',
      'guest', jsonb_build_object(
        'full_name', 'StayQR Day 5 Overdue Guest',
        'phone', '9000050504',
        'email', 'day5-overdue@stayqr.invalid',
        'preferred_language', 'english'
      )
    )
  );

  -- 5. Valid unallocated tentative arrival.
  created := public.create_reservation(
    target_hotel,
    jsonb_build_object(
      'status', 'draft',
      'booking_source', 'other',
      'source_reference', 'DAY5-ACCEPT-UNALLOCATED',
      'arrival_date', test_today,
      'departure_date', test_today + 2,
      'adults', 1,
      'children', 0,
      'room_type_id', source_room_type,
      'rate_plan_id', source_rate_plan,
      'internal_notes', 'Assign a physical room before check-in',
      'guest', jsonb_build_object(
        'full_name', 'StayQR Day 5 Unallocated Guest',
        'phone', '9000050505',
        'email', 'day5-unallocated@stayqr.invalid',
        'preferred_language', 'english'
      )
    )
  );

  update public.reservations r
  set status = 'tentative', updated_by = actor_user, updated_at = now()
  where r.hotel_id = target_hotel
    and r.id = (created->>'id')::uuid;

  -- 6. Existing in-house stay. It becomes Tomorrow's departure when the
  -- business date is advanced by one day in the UI.
  inhouse_created := public.create_reservation(
    target_hotel,
    jsonb_build_object(
      'status', 'confirmed',
      'booking_source', 'website',
      'source_reference', 'DAY5-ACCEPT-INHOUSE',
      'arrival_date', test_today - 1,
      'departure_date', test_today + 1,
      'expected_checkout_time', '11:00',
      'adults', 1,
      'children', 0,
      'room_type_id', source_room_type,
      'room_id', room_ids[6],
      'rate_plan_id', source_rate_plan,
      'internal_notes', 'In-house and next-business-date departure queue verification',
      'guest', jsonb_build_object(
        'full_name', 'StayQR Day 5 In-House Guest',
        'phone', '9000050506',
        'email', 'day5-inhouse@stayqr.invalid',
        'preferred_language', 'english'
      )
    )
  );

  inhouse_result := public.check_in_reservation_room(
    target_hotel,
    (inhouse_created->>'id')::uuid,
    (inhouse_created->'rooms'->0->>'id')::uuid,
    (inhouse_created->>'updated_at')::timestamptz
  );

  -- 7. Failure/rollback candidate: reservation allocation exists, but the room
  -- is made unavailable before check-in. The browser action must reject safely.
  created := public.create_reservation(
    target_hotel,
    jsonb_build_object(
      'status', 'confirmed',
      'booking_source', 'other',
      'source_reference', 'DAY5-ACCEPT-OCCUPIED-REJECT',
      'arrival_date', test_today,
      'departure_date', test_today + 2,
      'adults', 1,
      'children', 0,
      'room_type_id', source_room_type,
      'room_id', room_ids[7],
      'rate_plan_id', source_rate_plan,
      'internal_notes', 'Check-in must reject because the room status is unavailable',
      'guest', jsonb_build_object(
        'full_name', 'StayQR Day 5 Rollback Guest',
        'phone', '9000050507',
        'email', 'day5-rollback@stayqr.invalid',
        'preferred_language', 'english'
      )
    )
  );

  update public.rooms rm
  set status = 'occupied'
  where rm.hotel_id = target_hotel
    and rm.id = room_ids[7];

  insert into private.day5_browser_acceptance_state_20260724 (singleton, payload)
  values (
    true,
    jsonb_build_object(
      'actor_user', actor_user,
      'hotel_id', target_hotel,
      'hotel_name', target_hotel_name,
      'hotel_timezone', hotel_timezone,
      'business_date', test_today,
      'departure_test_date', test_today + 1,
      'room_prefix', room_prefix,
      'room_type_id', source_room_type,
      'room_type_name', source_room_type_name,
      'rate_plan_id', source_rate_plan,
      'temporary_rate_plan_created', temporary_rate_plan_created,
      'temporary_rate_plan_code', temporary_rate_plan_code,
      'sequence_year', test_sequence_year,
      'sequence_existed', sequence_existed,
      'sequence_before', sequence_before,
      'atomic_reservation_number', (
        select r.reservation_number from public.reservations r
        where r.hotel_id = target_hotel and r.source_reference = 'DAY5-ACCEPT-ATOMIC-CHECKIN'
      ),
      'group_reservation_number', group_after_add->>'reservation_number',
      'upcoming_reservation_number', (
        select r.reservation_number from public.reservations r
        where r.hotel_id = target_hotel and r.source_reference = 'DAY5-ACCEPT-UPCOMING'
      ),
      'overdue_reservation_number', (
        select r.reservation_number from public.reservations r
        where r.hotel_id = target_hotel and r.source_reference = 'DAY5-ACCEPT-OVERDUE'
      ),
      'unallocated_reservation_number', (
        select r.reservation_number from public.reservations r
        where r.hotel_id = target_hotel and r.source_reference = 'DAY5-ACCEPT-UNALLOCATED'
      ),
      'inhouse_reservation_number', inhouse_created->>'reservation_number',
      'rollback_reservation_number', created->>'reservation_number',
      'atomic_deposit', atomic_deposit,
      'expected_today_arrivals', 4,
      'expected_upcoming_arrivals', 1,
      'expected_in_house', 1,
      'expected_unallocated', 1,
      'expected_overdue', 1,
      'expected_departures_on_next_date', 1
    )
  );

  return jsonb_build_object(
    'result', 'DAY 5 BROWSER ACCEPTANCE DATA CREATED',
    'hotel', target_hotel_name,
    'business_date', test_today,
    'departure_test_date', test_today + 1,
    'room_prefix', room_prefix,
    'room_type', source_room_type_name,
    'rate_plan', jsonb_build_object(
      'id', source_rate_plan,
      'temporary', temporary_rate_plan_created,
      'code', temporary_rate_plan_code
    ),
    'atomic_checkin', jsonb_build_object(
      'reservation', (
        select r.reservation_number from public.reservations r
        where r.hotel_id = target_hotel and r.source_reference = 'DAY5-ACCEPT-ATOMIC-CHECKIN'
      ),
      'room', room_prefix || '-01',
      'deposit', atomic_deposit
    ),
    'group_booking', jsonb_build_object(
      'reservation', group_after_add->>'reservation_number',
      'rooms', jsonb_build_array(room_prefix || '-02', room_prefix || '-03')
    ),
    'upcoming', room_prefix || '-04',
    'overdue', room_prefix || '-05',
    'in_house', jsonb_build_object(
      'reservation', inhouse_created->>'reservation_number',
      'room', room_prefix || '-06'
    ),
    'occupied_room_rejection', room_prefix || '-07',
    'expected_counts_today', jsonb_build_object(
      'today_arrivals', 4,
      'upcoming_arrivals', 1,
      'today_departures', 0,
      'in_house', 1,
      'unallocated', 1,
      'overdue', 1
    ),
    'expected_departures_on_next_business_date', 1,
    'cleanup_instruction', 'Run audit 023 only after all Day 5 browser tests are complete.'
  );
end;
$$;

revoke all on function private.seed_day5_browser_acceptance_20260724()
from public;

select jsonb_pretty(
  private.seed_day5_browser_acceptance_20260724()
) as stayqr_day5_browser_acceptance_seed;
