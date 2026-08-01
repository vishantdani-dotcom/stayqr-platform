-- StayQR Day 2 — Reservation Foundation Smoke Test 006 (Revision 1)
--
-- Run the COMPLETE script using role postgres.
-- This version does not use a temporary result table and does not retain test data.

create or replace function private.run_reservation_foundation_smoke_test_20260720()
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
  test_hotel_id uuid;
  test_room_id uuid;
  test_room_type_id uuid;
  test_rate_plan_id uuid;

  first_reservation_id uuid;
  first_reservation_room_id uuid;
  first_reservation_number text;

  second_reservation_id uuid;
  second_reservation_room_id uuid;
  second_reservation_number text;

  test_start date := current_date + 730;
  test_end date := current_date + 732;

  first_allocation_created boolean := false;
  overlapping_allocation_rejected boolean := false;
  cleanup_completed boolean := false;
begin
  select
    r.hotel_id,
    r.id,
    r.room_type_id,
    rp.id
  into
    test_hotel_id,
    test_room_id,
    test_room_type_id,
    test_rate_plan_id
  from public.rooms r
  join lateral (
    select candidate.id
    from public.rate_plans candidate
    where candidate.hotel_id = r.hotel_id
      and candidate.room_type_id = r.room_type_id
      and candidate.is_active
    order by candidate.priority, candidate.created_at
    limit 1
  ) rp on true
  where r.status not in ('maintenance', 'out_of_order')
    and not exists (
      select 1
      from public.room_inventory_allocations ria
      where ria.hotel_id = r.hotel_id
        and ria.room_id = r.id
        and ria.status = 'active'
        and ria.stay_dates &&
          daterange(test_start, test_end + 1, '[)')
    )
  order by r.created_at
  limit 1;

  if test_room_id is null then
    raise exception
      'Smoke test requires a room with an active rate plan and a clear future date range.';
  end if;

  first_reservation_number :=
    'SMOKE-A-' || replace(gen_random_uuid()::text, '-', '');

  second_reservation_number :=
    'SMOKE-B-' || replace(gen_random_uuid()::text, '-', '');

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
    test_hotel_id,
    first_reservation_number,
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
  returning id into first_reservation_id;

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
    test_hotel_id,
    first_reservation_id,
    test_room_type_id,
    test_room_id,
    test_rate_plan_id,
    'confirmed',
    1,
    0,
    0,
    0,
    0,
    0,
    0
  )
  returning id into first_reservation_room_id;

  first_allocation_created := exists (
    select 1
    from public.room_inventory_allocations ria
    where ria.hotel_id = test_hotel_id
      and ria.room_id = test_room_id
      and ria.reservation_room_id = first_reservation_room_id
      and ria.status = 'active'
      and ria.starts_on = test_start
      and ria.ends_on = test_end
  );

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
      test_hotel_id,
      second_reservation_number,
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
    returning id into second_reservation_id;

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
      test_hotel_id,
      second_reservation_id,
      test_room_type_id,
      test_room_id,
      test_rate_plan_id,
      'confirmed',
      1,
      0,
      0,
      0,
      0,
      0,
      0
    )
    returning id into second_reservation_room_id;

  exception
    when exclusion_violation then
      overlapping_allocation_rejected := true;
  end;

  delete from public.reservations
  where id = first_reservation_id
    and hotel_id = test_hotel_id
    and reservation_number = first_reservation_number;

  if second_reservation_id is not null then
    delete from public.reservations
    where id = second_reservation_id
      and hotel_id = test_hotel_id
      and reservation_number = second_reservation_number;
  end if;

  cleanup_completed :=
    not exists (
      select 1
      from public.reservations r
      where r.reservation_number in (
        first_reservation_number,
        second_reservation_number
      )
    )
    and not exists (
      select 1
      from public.room_inventory_allocations ria
      where ria.reservation_room_id in (
        first_reservation_room_id,
        second_reservation_room_id
      )
    );

  return query
  values
    (
      'cleanup_completed'::text,
      cleanup_completed,
      'All smoke-test reservations and allocations were removed.'::text
    ),
    (
      'first_allocation_created'::text,
      first_allocation_created,
      'A confirmed reservation room created one active inventory allocation.'::text
    ),
    (
      'overlapping_allocation_rejected'::text,
      overlapping_allocation_rejected,
      'The database rejected an overlapping allocation for the same room.'::text
    );
exception
  when others then
    if first_reservation_id is not null then
      delete from public.reservations
      where id = first_reservation_id
        and hotel_id = test_hotel_id;
    end if;

    if second_reservation_id is not null then
      delete from public.reservations
      where id = second_reservation_id
        and hotel_id = test_hotel_id;
    end if;

    raise;
end;
$$;

revoke all on function private.run_reservation_foundation_smoke_test_20260720()
from public;

select *
from private.run_reservation_foundation_smoke_test_20260720()
order by test_name;
