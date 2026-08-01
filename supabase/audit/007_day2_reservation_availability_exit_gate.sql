-- ============================================================================
-- StayQR Day 2 — Final Exit-Gate Suite
-- File: 007_day2_reservation_availability_exit_gate.sql
--
-- PURPOSE
-- Verify the complete Day 2 roadmap exit gate:
--   - availability returns correct rooms and room types;
--   - reservation overlap is rejected;
--   - room-block overlap is rejected;
--   - adjacent non-overlapping dates are accepted;
--   - identical dates across different hotels do not conflict;
--   - booking numbers work per hotel;
--   - reservation status history is created;
--   - rate quotation returns one row per night;
--   - an unaffiliated authenticated identity is denied hotel access;
--   - all generated test business data is removed.
--
-- SAFETY
-- Run this COMPLETE file once using role `postgres`.
-- The private test function cleans up all test reservations, blocks,
-- allocations and reservation-number sequence changes before returning.
-- ============================================================================

create or replace function private.run_day2_reservation_exit_gate_20260720()
returns table (
  test_name text,
  passed boolean,
  details text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  platform_test_user uuid;
  unaffiliated_user uuid := gen_random_uuid();

  hotel_a uuid;
  hotel_b uuid;
  hotel_a_name text;
  hotel_b_name text;

  room_a uuid;
  room_b uuid;
  room_a_number text;
  room_b_number text;
  room_type_a uuid;
  room_type_b uuid;
  rate_plan_a uuid;
  rate_plan_b uuid;

  test_start date := current_date + 900;
  test_end date := current_date + 902;

  reservation_a uuid;
  reservation_room_a uuid;
  reservation_a_number text;

  overlapping_reservation uuid;
  cross_tenant_reservation uuid;
  cross_tenant_reservation_room uuid;
  cross_tenant_number text;

  block_a uuid;
  adjacent_block uuid;

  before_room_visible boolean := false;
  after_booking_room_hidden boolean := false;
  after_release_room_visible boolean := false;

  before_type_available bigint := 0;
  after_type_available bigint := 0;

  status_history_created boolean := false;
  reservation_overlap_rejected boolean := false;
  block_overlap_rejected boolean := false;
  adjacent_block_allowed boolean := false;
  block_hides_room boolean := false;
  reservation_against_block_rejected boolean := false;
  cross_tenant_same_dates_allowed boolean := false;
  rate_quote_correct boolean := false;
  booking_number_correct boolean := false;
  unaffiliated_access_denied boolean := false;
  cleanup_completed boolean := false;

  quote_count bigint := 0;
  status_history_count bigint := 0;

  test_sequence_year integer := extract(year from (current_date + 900))::integer;
  sequence_a_existed boolean := false;
  sequence_b_existed boolean := false;
  sequence_a_before bigint;
  sequence_b_before bigint;

  generated_a_1 text;
  generated_a_2 text;
  generated_b_1 text;
begin
  select pa.user_id
  into platform_test_user
  from public.platform_admins pa
  where pa.status = 'active'
  order by pa.created_at
  limit 1;

  if platform_test_user is null then
    raise exception
      'Day 2 exit gate requires one active platform administrator.';
  end if;

  -- Choose two different hotels, each with one usable room and rate plan.
  select
    h.id,
    h.hotel_name,
    r.id,
    r.room_number,
    r.room_type_id,
    rp.id
  into
    hotel_a,
    hotel_a_name,
    room_a,
    room_a_number,
    room_type_a,
    rate_plan_a
  from public.hotels h
  join public.rooms r
    on r.hotel_id = h.id
   and r.status not in ('maintenance', 'out_of_order')
  join lateral (
    select candidate.id
    from public.rate_plans candidate
    where candidate.hotel_id = r.hotel_id
      and candidate.room_type_id = r.room_type_id
      and candidate.is_active
    order by candidate.priority, candidate.created_at
    limit 1
  ) rp on true
  where h.status = 'active'
    and not exists (
      select 1
      from public.room_inventory_allocations ria
      where ria.hotel_id = h.id
        and ria.room_id = r.id
        and ria.status = 'active'
        and ria.stay_dates &&
          daterange(test_start, test_end + 2, '[)')
    )
  order by h.created_at
  limit 1;

  select
    h.id,
    h.hotel_name,
    r.id,
    r.room_number,
    r.room_type_id,
    rp.id
  into
    hotel_b,
    hotel_b_name,
    room_b,
    room_b_number,
    room_type_b,
    rate_plan_b
  from public.hotels h
  join public.rooms r
    on r.hotel_id = h.id
   and r.status not in ('maintenance', 'out_of_order')
  join lateral (
    select candidate.id
    from public.rate_plans candidate
    where candidate.hotel_id = r.hotel_id
      and candidate.room_type_id = r.room_type_id
      and candidate.is_active
    order by candidate.priority, candidate.created_at
    limit 1
  ) rp on true
  where h.status = 'active'
    and h.id <> hotel_a
    and not exists (
      select 1
      from public.room_inventory_allocations ria
      where ria.hotel_id = h.id
        and ria.room_id = r.id
        and ria.status = 'active'
        and ria.stay_dates &&
          daterange(test_start, test_end + 2, '[)')
    )
  order by h.created_at
  limit 1;

  if hotel_a is null or hotel_b is null then
    raise exception
      'Day 2 exit gate requires usable rooms in two different hotels.';
  end if;

  -- Simulate an authenticated platform-admin request for the secure RPCs.
  perform set_config(
    'request.jwt.claim.sub',
    platform_test_user::text,
    true
  );

  -- --------------------------------------------------------------------------
  -- 1. Availability before allocation
  -- --------------------------------------------------------------------------
  select exists (
    select 1
    from public.get_available_rooms(
      hotel_a,
      test_start,
      test_end,
      room_type_a
    ) ar
    where ar.room_id = room_a
  )
  into before_room_visible;

  select coalesce(max(rta.available_rooms), 0)
  into before_type_available
  from public.get_room_type_availability(
    hotel_a,
    test_start,
    test_end
  ) rta
  where rta.room_type_id = room_type_a;

  -- --------------------------------------------------------------------------
  -- 2. Booking-number sequence
  -- --------------------------------------------------------------------------
  select exists (
    select 1
    from public.reservation_number_sequences s
    where s.hotel_id = hotel_a
      and s.sequence_year = test_sequence_year
  )
  into sequence_a_existed;

  if sequence_a_existed then
    select s.last_number
    into sequence_a_before
    from public.reservation_number_sequences s
    where s.hotel_id = hotel_a
      and s.sequence_year = test_sequence_year;
  end if;

  select exists (
    select 1
    from public.reservation_number_sequences s
    where s.hotel_id = hotel_b
      and s.sequence_year = test_sequence_year
  )
  into sequence_b_existed;

  if sequence_b_existed then
    select s.last_number
    into sequence_b_before
    from public.reservation_number_sequences s
    where s.hotel_id = hotel_b
      and s.sequence_year = test_sequence_year;
  end if;

  generated_a_1 :=
    private.next_reservation_number(hotel_a, test_start);
  generated_a_2 :=
    private.next_reservation_number(hotel_a, test_start);
  generated_b_1 :=
    private.next_reservation_number(hotel_b, test_start);

  booking_number_correct :=
    generated_a_1 ~ ('^RES-' || test_sequence_year::text || '-[0-9]{6}$')
    and generated_a_2 ~ ('^RES-' || test_sequence_year::text || '-[0-9]{6}$')
    and generated_b_1 ~ ('^RES-' || test_sequence_year::text || '-[0-9]{6}$')
    and generated_a_1 <> generated_a_2;

  reservation_a_number := generated_a_1;
  cross_tenant_number := generated_b_1;

  -- --------------------------------------------------------------------------
  -- 3. Rate quote
  -- --------------------------------------------------------------------------
  select count(*)
  into quote_count
  from public.get_rate_quote(
    hotel_a,
    rate_plan_a,
    test_start,
    test_end
  );

  rate_quote_correct := quote_count = (test_end - test_start);

  -- --------------------------------------------------------------------------
  -- 4. Confirmed reservation, status history and availability reduction
  -- --------------------------------------------------------------------------
  insert into public.reservations (
    hotel_id,
    reservation_number,
    status,
    booking_source,
    arrival_date,
    departure_date,
    currency_code,
    adults,
    children,
    room_subtotal,
    tax_amount,
    discount_amount,
    total_amount
  )
  values (
    hotel_a,
    reservation_a_number,
    'confirmed',
    'other',
    test_start,
    test_end,
    'INR',
    1,
    0,
    0,
    0,
    0,
    0
  )
  returning id into reservation_a;

  insert into public.reservation_rooms (
    hotel_id,
    reservation_id,
    room_type_id,
    room_id,
    rate_plan_id,
    status,
    adults,
    children,
    nightly_rate,
    room_subtotal,
    tax_amount,
    discount_amount,
    total_amount
  )
  values (
    hotel_a,
    reservation_a,
    room_type_a,
    room_a,
    rate_plan_a,
    'confirmed',
    1,
    0,
    0,
    0,
    0,
    0,
    0
  )
  returning id into reservation_room_a;

  select not exists (
    select 1
    from public.get_available_rooms(
      hotel_a,
      test_start,
      test_end,
      room_type_a
    ) ar
    where ar.room_id = room_a
  )
  into after_booking_room_hidden;

  select coalesce(max(rta.available_rooms), 0)
  into after_type_available
  from public.get_room_type_availability(
    hotel_a,
    test_start,
    test_end
  ) rta
  where rta.room_type_id = room_type_a;

  select count(*)
  into status_history_count
  from public.reservation_status_history h
  where h.hotel_id = hotel_a
    and h.reservation_id = reservation_a;

  status_history_created := status_history_count = 1;

  -- --------------------------------------------------------------------------
  -- 5. Overlapping reservation rejected
  -- --------------------------------------------------------------------------
  begin
    insert into public.reservations (
      hotel_id,
      reservation_number,
      status,
      booking_source,
      arrival_date,
      departure_date,
      currency_code,
      adults,
      children,
      room_subtotal,
      tax_amount,
      discount_amount,
      total_amount
    )
    values (
      hotel_a,
      'EXIT-OVERLAP-' || replace(gen_random_uuid()::text, '-', ''),
      'confirmed',
      'other',
      test_start + 1,
      test_end + 1,
      'INR',
      1,
      0,
      0,
      0,
      0,
      0
    )
    returning id into overlapping_reservation;

    insert into public.reservation_rooms (
      hotel_id,
      reservation_id,
      room_type_id,
      room_id,
      rate_plan_id,
      status,
      adults,
      children,
      nightly_rate,
      room_subtotal,
      tax_amount,
      discount_amount,
      total_amount
    )
    values (
      hotel_a,
      overlapping_reservation,
      room_type_a,
      room_a,
      rate_plan_a,
      'confirmed',
      1,
      0,
      0,
      0,
      0,
      0,
      0
    );
  exception
    when exclusion_violation then
      reservation_overlap_rejected := true;
  end;

  -- --------------------------------------------------------------------------
  -- 6. Overlapping room block rejected
  -- --------------------------------------------------------------------------
  begin
    insert into public.room_blocks (
      hotel_id,
      room_id,
      block_type,
      status,
      start_date,
      end_date,
      reason
    )
    values (
      hotel_a,
      room_a,
      'maintenance',
      'active',
      test_start + 1,
      test_end + 1,
      'Day 2 overlap test'
    );
  exception
    when exclusion_violation then
      block_overlap_rejected := true;
  end;

  -- --------------------------------------------------------------------------
  -- 7. Adjacent block accepted: reservation is [start, end), so a block
  --    starting exactly at checkout date must not overlap.
  -- --------------------------------------------------------------------------
  insert into public.room_blocks (
    hotel_id,
    room_id,
    block_type,
    status,
    start_date,
    end_date,
    reason
  )
  values (
    hotel_a,
    room_a,
    'operational',
    'active',
    test_end,
    test_end + 1,
    'Day 2 adjacent-date test'
  )
  returning id into adjacent_block;

  adjacent_block_allowed := exists (
    select 1
    from public.room_inventory_allocations ria
    where ria.room_block_id = adjacent_block
      and ria.status = 'active'
      and ria.starts_on = test_end
      and ria.ends_on = test_end + 1
  );

  delete from public.room_blocks
  where id = adjacent_block
    and hotel_id = hotel_a;

  adjacent_block := null;

  -- --------------------------------------------------------------------------
  -- 8. Same dates in another hotel are independent
  -- --------------------------------------------------------------------------
  insert into public.reservations (
    hotel_id,
    reservation_number,
    status,
    booking_source,
    arrival_date,
    departure_date,
    currency_code,
    adults,
    children,
    room_subtotal,
    tax_amount,
    discount_amount,
    total_amount
  )
  values (
    hotel_b,
    cross_tenant_number,
    'confirmed',
    'other',
    test_start,
    test_end,
    'INR',
    1,
    0,
    0,
    0,
    0,
    0
  )
  returning id into cross_tenant_reservation;

  insert into public.reservation_rooms (
    hotel_id,
    reservation_id,
    room_type_id,
    room_id,
    rate_plan_id,
    status,
    adults,
    children,
    nightly_rate,
    room_subtotal,
    tax_amount,
    discount_amount,
    total_amount
  )
  values (
    hotel_b,
    cross_tenant_reservation,
    room_type_b,
    room_b,
    rate_plan_b,
    'confirmed',
    1,
    0,
    0,
    0,
    0,
    0,
    0
  )
  returning id into cross_tenant_reservation_room;

  cross_tenant_same_dates_allowed :=
    exists (
      select 1
      from public.room_inventory_allocations ria
      where ria.reservation_room_id = reservation_room_a
        and ria.status = 'active'
    )
    and exists (
      select 1
      from public.room_inventory_allocations ria
      where ria.reservation_room_id = cross_tenant_reservation_room
        and ria.status = 'active'
    );

  delete from public.reservations
  where id = cross_tenant_reservation
    and hotel_id = hotel_b;

  cross_tenant_reservation := null;
  cross_tenant_reservation_room := null;

  -- --------------------------------------------------------------------------
  -- 9. Release reservation and verify availability returns
  -- --------------------------------------------------------------------------
  update public.reservations
  set status = 'checked_in'
  where id = reservation_a
    and hotel_id = hotel_a;

  update public.reservations
  set status = 'checked_out'
  where id = reservation_a
    and hotel_id = hotel_a;

  select exists (
    select 1
    from public.get_available_rooms(
      hotel_a,
      test_start,
      test_end,
      room_type_a
    ) ar
    where ar.room_id = room_a
  )
  into after_release_room_visible;

  -- --------------------------------------------------------------------------
  -- 10. Active room block hides availability and rejects a reservation
  -- --------------------------------------------------------------------------
  insert into public.room_blocks (
    hotel_id,
    room_id,
    block_type,
    status,
    start_date,
    end_date,
    reason
  )
  values (
    hotel_a,
    room_a,
    'maintenance',
    'active',
    test_start,
    test_end,
    'Day 2 room-block availability test'
  )
  returning id into block_a;

  select not exists (
    select 1
    from public.get_available_rooms(
      hotel_a,
      test_start,
      test_end,
      room_type_a
    ) ar
    where ar.room_id = room_a
  )
  into block_hides_room;

  begin
    insert into public.reservations (
      hotel_id,
      reservation_number,
      status,
      booking_source,
      arrival_date,
      departure_date,
      currency_code,
      adults,
      children,
      room_subtotal,
      tax_amount,
      discount_amount,
      total_amount
    )
    values (
      hotel_a,
      'EXIT-BLOCKED-' || replace(gen_random_uuid()::text, '-', ''),
      'confirmed',
      'other',
      test_start,
      test_end,
      'INR',
      1,
      0,
      0,
      0,
      0,
      0
    )
    returning id into overlapping_reservation;

    insert into public.reservation_rooms (
      hotel_id,
      reservation_id,
      room_type_id,
      room_id,
      rate_plan_id,
      status,
      adults,
      children,
      nightly_rate,
      room_subtotal,
      tax_amount,
      discount_amount,
      total_amount
    )
    values (
      hotel_a,
      overlapping_reservation,
      room_type_a,
      room_a,
      rate_plan_a,
      'confirmed',
      1,
      0,
      0,
      0,
      0,
      0,
      0
    );
  exception
    when exclusion_violation then
      reservation_against_block_rejected := true;
  end;

  delete from public.room_blocks
  where id = block_a
    and hotel_id = hotel_a;

  block_a := null;

  -- --------------------------------------------------------------------------
  -- 11. Unaffiliated identity is denied the hotel-scoped RPC
  -- --------------------------------------------------------------------------
  perform set_config(
    'request.jwt.claim.sub',
    unaffiliated_user::text,
    true
  );

  begin
    perform *
    from public.get_available_rooms(
      hotel_a,
      test_start,
      test_end,
      null
    );

    unaffiliated_access_denied := false;
  exception
    when others then
      unaffiliated_access_denied :=
        position('Hotel access denied' in sqlerrm) > 0;
  end;

  -- Restore the test platform admin for remaining checks/cleanup.
  perform set_config(
    'request.jwt.claim.sub',
    platform_test_user::text,
    true
  );

  -- --------------------------------------------------------------------------
  -- 12. Cleanup all successful test data
  -- --------------------------------------------------------------------------
  if block_a is not null then
    delete from public.room_blocks
    where id = block_a and hotel_id = hotel_a;
  end if;

  if adjacent_block is not null then
    delete from public.room_blocks
    where id = adjacent_block and hotel_id = hotel_a;
  end if;

  if cross_tenant_reservation is not null then
    delete from public.reservations
    where id = cross_tenant_reservation
      and hotel_id = hotel_b;
  end if;

  if overlapping_reservation is not null then
    delete from public.reservations
    where id = overlapping_reservation
      and hotel_id = hotel_a;
  end if;

  if reservation_a is not null then
    delete from public.reservations
    where id = reservation_a
      and hotel_id = hotel_a;
  end if;

  -- Restore reservation sequence state exactly as it was.
  if sequence_a_existed then
    update public.reservation_number_sequences
    set last_number = sequence_a_before
    where hotel_id = hotel_a
      and sequence_year = test_sequence_year;
  else
    delete from public.reservation_number_sequences
    where hotel_id = hotel_a
      and reservation_number_sequences.sequence_year =
        test_sequence_year;
  end if;

  if sequence_b_existed then
    update public.reservation_number_sequences
    set last_number = sequence_b_before
    where hotel_id = hotel_b
      and reservation_number_sequences.sequence_year =
        test_sequence_year;
  else
    delete from public.reservation_number_sequences
    where hotel_id = hotel_b
      and reservation_number_sequences.sequence_year =
        test_sequence_year;
  end if;

  cleanup_completed :=
    not exists (
      select 1
      from public.reservations r
      where r.reservation_number in (
        generated_a_1,
        generated_a_2,
        generated_b_1
      )
      or r.reservation_number like 'EXIT-OVERLAP-%'
      or r.reservation_number like 'EXIT-BLOCKED-%'
    )
    and not exists (
      select 1
      from public.room_blocks rb
      where rb.reason like 'Day 2 %test%'
    );

  return query
  values
    (
      'availability_room_before_booking'::text,
      before_room_visible,
      format(
        '%s room %s was available before allocation.',
        hotel_a_name,
        room_a_number
      )
    ),
    (
      'availability_room_hidden_after_booking'::text,
      after_booking_room_hidden,
      'The allocated room was removed from the availability RPC.'::text
    ),
    (
      'availability_room_type_decreased'::text,
      after_type_available = greatest(before_type_available - 1, 0),
      format(
        'Room-type availability changed from %s to %s.',
        before_type_available,
        after_type_available
      )
    ),
    (
      'availability_room_returned_after_release'::text,
      after_release_room_visible,
      'Checked-out reservation released the room back to availability.'::text
    ),
    (
      'booking_number_generation'::text,
      booking_number_correct,
      format(
        'Generated numbers: %s, %s and %s.',
        generated_a_1,
        generated_a_2,
        generated_b_1
      )
    ),
    (
      'rate_quote_nightly_rows'::text,
      rate_quote_correct,
      format(
        'Rate quote returned %s row(s) for %s night(s).',
        quote_count,
        test_end - test_start
      )
    ),
    (
      'reservation_status_history'::text,
      status_history_created,
      format(
        'Initial confirmed reservation created %s history row(s).',
        status_history_count
      )
    ),
    (
      'overlapping_reservation_rejected'::text,
      reservation_overlap_rejected,
      'Same-room overlapping reservation was rejected.'::text
    ),
    (
      'overlapping_room_block_rejected'::text,
      block_overlap_rejected,
      'A room block overlapping a reservation was rejected.'::text
    ),
    (
      'adjacent_non_overlapping_block_allowed'::text,
      adjacent_block_allowed,
      'A block beginning exactly at reservation checkout was accepted.'::text
    ),
    (
      'room_block_hides_availability'::text,
      block_hides_room,
      'An active room block removed the room from availability.'::text
    ),
    (
      'reservation_against_block_rejected'::text,
      reservation_against_block_rejected,
      'A reservation overlapping an active room block was rejected.'::text
    ),
    (
      'same_dates_across_hotels_allowed'::text,
      cross_tenant_same_dates_allowed,
      format(
        'Same dates allocated independently in %s and %s.',
        hotel_a_name,
        hotel_b_name
      )
    ),
    (
      'unaffiliated_hotel_access_denied'::text,
      unaffiliated_access_denied,
      'A random authenticated identity was denied the hotel availability RPC.'::text
    ),
    (
      'cleanup_completed'::text,
      cleanup_completed,
      'All exit-gate test reservations, blocks and sequence changes were removed.'::text
    );
exception
  when others then
    -- Best-effort cleanup before surfacing an unexpected failure.
    perform set_config(
      'request.jwt.claim.sub',
      platform_test_user::text,
      true
    );

    if block_a is not null then
      delete from public.room_blocks
      where id = block_a and hotel_id = hotel_a;
    end if;

    if adjacent_block is not null then
      delete from public.room_blocks
      where id = adjacent_block and hotel_id = hotel_a;
    end if;

    if cross_tenant_reservation is not null then
      delete from public.reservations
      where id = cross_tenant_reservation
        and hotel_id = hotel_b;
    end if;

    if overlapping_reservation is not null then
      delete from public.reservations
      where id = overlapping_reservation
        and hotel_id = hotel_a;
    end if;

    if reservation_a is not null then
      delete from public.reservations
      where id = reservation_a
        and hotel_id = hotel_a;
    end if;

    if sequence_a_existed and hotel_a is not null then
      update public.reservation_number_sequences
      set last_number = sequence_a_before
      where hotel_id = hotel_a
        and reservation_number_sequences.sequence_year =
          test_sequence_year;
    elsif hotel_a is not null then
      delete from public.reservation_number_sequences
      where hotel_id = hotel_a
        and reservation_number_sequences.sequence_year =
          test_sequence_year;
    end if;

    if sequence_b_existed and hotel_b is not null then
      update public.reservation_number_sequences
      set last_number = sequence_b_before
      where hotel_id = hotel_b
        and reservation_number_sequences.sequence_year =
          test_sequence_year;
    elsif hotel_b is not null then
      delete from public.reservation_number_sequences
      where hotel_id = hotel_b
        and reservation_number_sequences.sequence_year =
          test_sequence_year;
    end if;

    raise;
end;
$$;

revoke all on function private.run_day2_reservation_exit_gate_20260720()
from public;

-- This SELECT returns the Day 2 exit-gate report.
select *
from private.run_day2_reservation_exit_gate_20260720()
order by test_name;
