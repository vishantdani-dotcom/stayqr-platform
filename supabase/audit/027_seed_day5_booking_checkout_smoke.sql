-- ============================================================================
-- StayQR Day 5 — Booking-to-checkout smoke-test seed
--
-- Creates one controlled confirmed reservation with a ₹500 deposit. The user
-- must check it in through Arrivals & Departures and complete Final Bill &
-- Checkout through Guests. Run audit 028 only after browser checkout succeeds.
-- ============================================================================

create table if not exists private.day5_checkout_smoke_state_20260724 (
  singleton boolean primary key default true check (singleton),
  payload jsonb not null,
  created_at timestamptz not null default now()
);

create or replace function private.seed_day5_checkout_smoke_20260724()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user uuid;
  target_hotel uuid;
  target_hotel_name text;
  other_hotel uuid;
  other_hotel_name text;
  hotel_timezone text;
  currency_code text;
  source_room uuid;
  source_room_type uuid;
  source_room_type_name text;
  source_rate_plan uuid;
  temporary_rate_plan_created boolean := false;
  temporary_rate_plan_code text;
  test_today date;
  test_year integer;
  sequence_existed boolean := false;
  sequence_before bigint;
  room_prefix text := 'D5CO-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6));
  smoke_room uuid;
  created jsonb;
  rate_quote jsonb;
  deposit_amount numeric(12,2);
begin
  if exists (select 1 from private.day5_checkout_smoke_state_20260724) then
    raise exception 'Day 5 checkout smoke data already exists. Run audit 029 before reseeding.';
  end if;

  if exists (
    select 1 from public.reservations
    where source_reference = 'DAY5-CHECKOUT-SMOKE'
  ) then
    raise exception 'Existing DAY5-CHECKOUT-SMOKE data was found. Run audit 029 before reseeding.';
  end if;

  select pa.user_id
  into actor_user
  from public.platform_admins pa
  where pa.status = 'active'
  order by pa.created_at
  limit 1;

  if actor_user is null then
    raise exception 'An active Platform Admin is required for the controlled checkout smoke test.';
  end if;

  perform set_config('request.jwt.claim.sub', actor_user::text, true);

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
    currency_code,
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
    raise exception 'The checkout smoke seed requires an active hotel, room and room type.';
  end if;

  select h.id, h.hotel_name
  into other_hotel, other_hotel_name
  from public.hotels h
  where h.status = 'active'
    and h.id <> target_hotel
  order by h.created_at
  limit 1;

  select rp.id
  into source_rate_plan
  from public.rate_plans rp
  where rp.hotel_id = target_hotel
    and rp.room_type_id = source_room_type
    and rp.is_active
    and rp.base_rate > 0
  order by rp.priority, rp.created_at
  limit 1;

  if source_rate_plan is null then
    temporary_rate_plan_code :=
      'D5CO-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10));

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
    ) values (
      target_hotel,
      source_room_type,
      'Day 5 Checkout Smoke Rate',
      temporary_rate_plan_code,
      'Temporary rate used only for the controlled Day 5 booking-to-checkout smoke test.',
      'room_only',
      currency_code,
      1500,
      0,
      0,
      1,
      true,
      true,
      1
    ) returning id into source_rate_plan;

    temporary_rate_plan_created := true;
  end if;

  test_today := (now() at time zone hotel_timezone)::date;
  test_year := extract(year from test_today)::integer;

  select exists (
    select 1
    from public.reservation_number_sequences s
    where s.hotel_id = target_hotel
      and s.sequence_year = test_year
  ) into sequence_existed;

  if sequence_existed then
    select s.last_number
    into sequence_before
    from public.reservation_number_sequences s
    where s.hotel_id = target_hotel
      and s.sequence_year = test_year;
  end if;

  insert into public.rooms (
    hotel_id,
    room_number,
    room_type,
    room_type_id,
    status
  )
  select
    target_hotel,
    room_prefix || '-01',
    src.room_type,
    source_room_type,
    'available'
  from public.rooms src
  where src.hotel_id = target_hotel
    and src.id = source_room
  returning id into smoke_room;

  rate_quote := public.get_reservation_rate_quote(
    target_hotel,
    source_rate_plan,
    test_today,
    test_today + 1,
    1,
    0
  );

  deposit_amount := least(
    500::numeric,
    (rate_quote->>'total_amount')::numeric
  )::numeric(12,2);

  if deposit_amount <= 0 then
    raise exception 'The checkout smoke test requires a positive reservation total and deposit.';
  end if;

  created := public.create_reservation(
    target_hotel,
    jsonb_build_object(
      'status', 'confirmed',
      'booking_source', 'website',
      'source_reference', 'DAY5-CHECKOUT-SMOKE',
      'arrival_date', test_today,
      'departure_date', test_today + 1,
      'expected_checkin_time', '14:00',
      'expected_checkout_time', '11:00',
      'adults', 1,
      'children', 0,
      'room_type_id', source_room_type,
      'room_id', smoke_room,
      'rate_plan_id', source_rate_plan,
      'deposit_required', deposit_amount,
      'deposit_amount', deposit_amount,
      'payment_method', 'upi',
      'payment_reference', 'D5CO-DEPOSIT-500',
      'payment_notes', 'Controlled deposit for booking-to-checkout smoke test',
      'internal_notes', 'Day 5 final reservation-to-checkout acceptance record',
      'guest', jsonb_build_object(
        'full_name', 'StayQR Day 5 Checkout Smoke Guest',
        'phone', '9000050599',
        'email', 'day5-checkout-smoke@stayqr.invalid',
        'preferred_language', 'english'
      )
    )
  );

  insert into private.day5_checkout_smoke_state_20260724 (singleton, payload)
  values (
    true,
    jsonb_build_object(
      'actor_user', actor_user,
      'hotel_id', target_hotel,
      'hotel_name', target_hotel_name,
      'other_hotel_id', other_hotel,
      'other_hotel_name', other_hotel_name,
      'hotel_timezone', hotel_timezone,
      'business_date', test_today,
      'departure_test_date', test_today + 1,
      'room_id', smoke_room,
      'room_number', room_prefix || '-01',
      'room_prefix', room_prefix,
      'room_type_id', source_room_type,
      'room_type_name', source_room_type_name,
      'rate_plan_id', source_rate_plan,
      'temporary_rate_plan_created', temporary_rate_plan_created,
      'temporary_rate_plan_code', temporary_rate_plan_code,
      'sequence_year', test_year,
      'sequence_existed', sequence_existed,
      'sequence_before', sequence_before,
      'reservation_id', (created->>'id')::uuid,
      'reservation_number', created->>'reservation_number',
      'reservation_room_id', (created->'rooms'->0->>'id')::uuid,
      'guest_id', (created->'guest'->>'id')::uuid,
      'deposit_amount', deposit_amount,
      'expected_total', (created->>'total_amount')::numeric
    )
  );

  return jsonb_build_object(
    'result', 'DAY 5 BOOKING-TO-CHECKOUT SMOKE DATA CREATED',
    'hotel', target_hotel_name,
    'other_hotel_for_isolation', other_hotel_name,
    'business_date', test_today,
    'departure_test_date', test_today + 1,
    'reservation', created->>'reservation_number',
    'guest', created->'guest'->>'full_name',
    'room', room_prefix || '-01',
    'room_type', source_room_type_name,
    'total', (created->>'total_amount')::numeric,
    'deposit', deposit_amount,
    'remaining_expected_at_checkout',
      greatest((created->>'total_amount')::numeric - deposit_amount, 0),
    'rate_plan', jsonb_build_object(
      'id', source_rate_plan,
      'temporary', temporary_rate_plan_created,
      'code', temporary_rate_plan_code
    ),
    'browser_instruction',
      'Check in this reservation in Arrivals & Departures, then use Guests > Final Bill & Checkout. Do not run audit 028 until checkout succeeds.'
  );
end;
$$;

revoke all on function private.seed_day5_checkout_smoke_20260724()
from public;

select jsonb_pretty(
  private.seed_day5_checkout_smoke_20260724()
) as stayqr_day5_checkout_smoke_seed;
