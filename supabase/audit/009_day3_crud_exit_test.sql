-- ============================================================================
-- StayQR Day 3 — Transactional CRUD Exit Test
--
-- Run only after 008_verify_day3_crud_foundation.sql is green.
-- The function creates far-future test data, validates the Day 3 CRUD flows,
-- and removes every generated reservation, guest, payment, activity log,
-- seasonal rate and sequence change before returning.
--
-- Expected: every row has passed = true.
-- ============================================================================

create or replace function private.run_day3_crud_exit_test_20260722()
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
  actor_user uuid;
  target_hotel uuid;
  target_hotel_name text;
  target_room uuid;
  target_room_type uuid;
  target_rate_plan uuid;
  target_room_number text;

  test_arrival date := current_date + 1050;
  original_departure date := current_date + 1052;
  edited_arrival date := current_date + 1055;
  edited_departure date := current_date + 1058;
  no_show_arrival date := current_date + 1062;
  no_show_departure date := current_date + 1064;

  seasonal_rate_id uuid;
  created_reservation jsonb;
  edited_reservation jsonb;
  cancelled_reservation jsonb;
  no_show_reservation jsonb;

  created_reservation_id uuid;
  no_show_reservation_id uuid;
  created_guest_id uuid;
  no_show_guest_id uuid;

  created_number text;
  no_show_number text;

  test_sequence_year integer :=
    extract(year from (current_date + 1050))::integer;
  sequence_existed boolean := false;
  sequence_before bigint;

  quoted_nightly numeric(12,2) := 1250;
  expected_create_total numeric(12,2) := 2500;
  expected_edit_total numeric(12,2) := 3750;

  create_flow_passed boolean := false;
  deposit_passed boolean := false;
  availability_after_create_passed boolean := false;
  guest_lookup_passed boolean := false;
  edit_flow_passed boolean := false;
  amount_recalculated_passed boolean := false;
  availability_recalculated_passed boolean := false;
  cancel_flow_passed boolean := false;
  cancel_released_passed boolean := false;
  no_show_flow_passed boolean := false;
  no_show_released_passed boolean := false;
  status_history_passed boolean := false;
  activity_logs_passed boolean := false;
  cleanup_passed boolean := false;

  create_updated_at timestamptz;
begin
  select pa.user_id
  into actor_user
  from public.platform_admins pa
  where pa.status = 'active'
  order by pa.created_at
  limit 1;

  if actor_user is null then
    raise exception 'Day 3 test requires an active platform admin.';
  end if;

  perform set_config(
    'request.jwt.claim.sub',
    actor_user::text,
    true
  );

  select
    h.id,
    h.hotel_name,
    r.id,
    r.room_number,
    r.room_type_id,
    rp.id
  into
    target_hotel,
    target_hotel_name,
    target_room,
    target_room_number,
    target_room_type,
    target_rate_plan
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
          daterange(
            test_arrival,
            no_show_departure,
            '[)'
          )
    )
  order by h.created_at, r.created_at
  limit 1;

  if target_room is null then
    raise exception
      'Day 3 test requires one usable room and rate plan.';
  end if;

  select exists (
    select 1
    from public.reservation_number_sequences s
    where s.hotel_id = target_hotel
      and s.sequence_year = test_sequence_year
  )
  into sequence_existed;

  if sequence_existed then
    select s.last_number
    into sequence_before
    from public.reservation_number_sequences s
    where s.hotel_id = target_hotel
      and s.sequence_year = test_sequence_year;
  end if;

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
    target_rate_plan,
    'Day 3 CRUD Test Rate',
    test_arrival - 1,
    no_show_departure + 1,
    quoted_nightly,
    -1000,
    true
  )
  returning id into seasonal_rate_id;

  created_reservation := public.create_reservation(
    target_hotel,
    jsonb_build_object(
      'status', 'confirmed',
      'booking_source', 'phone',
      'source_reference', 'DAY3-CREATE-TEST',
      'arrival_date', test_arrival,
      'departure_date', original_departure,
      'adults', 1,
      'children', 0,
      'room_type_id', target_room_type,
      'room_id', target_room,
      'rate_plan_id', target_rate_plan,
      'deposit_required', 500,
      'deposit_amount', 500,
      'payment_method', 'upi',
      'payment_reference', 'DAY3-UPI-TEST',
      'special_requests', 'Day 3 create test',
      'internal_notes', 'Remove after test',
      'guest', jsonb_build_object(
        'full_name', 'StayQR Day 3 Test Guest',
        'phone', '9000000003',
        'email', 'day3-test@stayqr.invalid',
        'preferred_language', 'english'
      )
    )
  );

  created_reservation_id :=
    (created_reservation->>'id')::uuid;
  created_guest_id :=
    (created_reservation->'guest'->>'id')::uuid;
  created_number :=
    created_reservation->>'reservation_number';
  create_updated_at :=
    (created_reservation->>'updated_at')::timestamptz;

  create_flow_passed :=
    created_reservation->>'status' = 'confirmed'
    and (created_reservation->>'total_amount')::numeric =
      expected_create_total
    and jsonb_array_length(
      created_reservation->'rooms'
    ) = 1;

  deposit_passed :=
    (created_reservation->>'deposit_collected')::numeric = 500
    and jsonb_array_length(
      created_reservation->'payments'
    ) = 1;

  availability_after_create_passed := not exists (
    select 1
    from public.get_reservation_available_rooms(
      target_hotel,
      test_arrival,
      original_departure,
      target_room_type,
      null
    ) available
    where available.room_id = target_room
  );

  guest_lookup_passed := exists (
    select 1
    from public.search_reservation_guests(
      target_hotel,
      '9000000003',
      10
    ) guest
    where guest.guest_id = created_guest_id
  );

  edited_reservation := public.update_reservation(
    target_hotel,
    created_reservation_id,
    jsonb_build_object(
      'arrival_date', edited_arrival,
      'departure_date', edited_departure,
      'room_type_id', target_room_type,
      'room_id', target_room,
      'rate_plan_id', target_rate_plan,
      'adults', 1,
      'children', 0,
      'booking_source', 'website',
      'source_reference', 'DAY3-EDIT-TEST',
      'deposit_required', 750,
      'additional_deposit_amount', 250,
      'payment_method', 'cash',
      'payment_reference', 'DAY3-CASH-TEST',
      'special_requests', 'Updated request'
    ),
    create_updated_at
  );

  edit_flow_passed :=
    (edited_reservation->>'arrival_date')::date =
      edited_arrival
    and (edited_reservation->>'departure_date')::date =
      edited_departure
    and edited_reservation->>'booking_source' = 'website'
    and (edited_reservation->>'deposit_collected')::numeric =
      750;

  amount_recalculated_passed :=
    (edited_reservation->>'total_amount')::numeric =
      expected_edit_total
    and (edited_reservation->>'room_subtotal')::numeric =
      expected_edit_total;

  availability_recalculated_passed :=
    exists (
      select 1
      from public.get_reservation_available_rooms(
        target_hotel,
        test_arrival,
        original_departure,
        target_room_type,
        null
      ) available
      where available.room_id = target_room
    )
    and not exists (
      select 1
      from public.get_reservation_available_rooms(
        target_hotel,
        edited_arrival,
        edited_departure,
        target_room_type,
        null
      ) available
      where available.room_id = target_room
    );

  cancelled_reservation := public.change_reservation_status(
    target_hotel,
    created_reservation_id,
    'cancelled',
    'Day 3 cancellation test'
  );

  cancel_flow_passed :=
    cancelled_reservation->>'status' = 'cancelled'
    and cancelled_reservation->>'cancellation_reason' =
      'Day 3 cancellation test';

  cancel_released_passed := exists (
    select 1
    from public.get_reservation_available_rooms(
      target_hotel,
      edited_arrival,
      edited_departure,
      target_room_type,
      null
    ) available
    where available.room_id = target_room
  );

  no_show_reservation := public.create_reservation(
    target_hotel,
    jsonb_build_object(
      'status', 'confirmed',
      'booking_source', 'walk_in',
      'source_reference', 'DAY3-NOSHOW-TEST',
      'arrival_date', no_show_arrival,
      'departure_date', no_show_departure,
      'adults', 1,
      'children', 0,
      'room_type_id', target_room_type,
      'room_id', target_room,
      'rate_plan_id', target_rate_plan,
      'guest', jsonb_build_object(
        'full_name', 'StayQR Day 3 No Show Guest',
        'phone', '9000000004',
        'email', 'day3-noshow@stayqr.invalid'
      )
    )
  );

  no_show_reservation_id :=
    (no_show_reservation->>'id')::uuid;
  no_show_guest_id :=
    (no_show_reservation->'guest'->>'id')::uuid;
  no_show_number :=
    no_show_reservation->>'reservation_number';

  no_show_reservation := public.change_reservation_status(
    target_hotel,
    no_show_reservation_id,
    'no_show',
    'Day 3 no-show test'
  );

  no_show_flow_passed :=
    no_show_reservation->>'status' = 'no_show'
    and no_show_reservation->>'no_show_at' is not null;

  no_show_released_passed := exists (
    select 1
    from public.get_reservation_available_rooms(
      target_hotel,
      no_show_arrival,
      no_show_departure,
      target_room_type,
      null
    ) available
    where available.room_id = target_room
  );

  status_history_passed :=
    (
      select count(*)
      from public.reservation_status_history history
      where history.hotel_id = target_hotel
        and history.reservation_id =
          created_reservation_id
    ) >= 2
    and
    (
      select count(*)
      from public.reservation_status_history history
      where history.hotel_id = target_hotel
        and history.reservation_id =
          no_show_reservation_id
    ) >= 2;

  activity_logs_passed :=
    exists (
      select 1
      from public.activity_logs log
      where log.hotel_id = target_hotel
        and log.entity_id = created_reservation_id
        and log.action = 'reservation.created'
    )
    and exists (
      select 1
      from public.activity_logs log
      where log.hotel_id = target_hotel
        and log.entity_id = created_reservation_id
        and log.action = 'reservation.updated'
    )
    and exists (
      select 1
      from public.activity_logs log
      where log.hotel_id = target_hotel
        and log.entity_id = created_reservation_id
        and log.action = 'reservation.cancelled'
    )
    and exists (
      select 1
      from public.activity_logs log
      where log.hotel_id = target_hotel
        and log.entity_id = no_show_reservation_id
        and log.action = 'reservation.no_show'
    );

  delete from public.activity_logs
  where hotel_id = target_hotel
    and entity_type = 'reservation'
    and entity_id in (
      created_reservation_id,
      no_show_reservation_id
    );

  delete from public.reservations
  where hotel_id = target_hotel
    and id in (
      created_reservation_id,
      no_show_reservation_id
    );

  delete from public.guests
  where hotel_id = target_hotel
    and id in (
      created_guest_id,
      no_show_guest_id
    );

  delete from public.seasonal_rates
  where id = seasonal_rate_id
    and hotel_id = target_hotel;

  if sequence_existed then
    update public.reservation_number_sequences
    set last_number = sequence_before
    where hotel_id = target_hotel
      and sequence_year =
        test_sequence_year;
  else
    delete from public.reservation_number_sequences
    where hotel_id = target_hotel
      and sequence_year =
        test_sequence_year;
  end if;

  cleanup_passed :=
    not exists (
      select 1
      from public.reservations
      where reservation_number in (
        created_number,
        no_show_number
      )
    )
    and not exists (
      select 1
      from public.guests
      where id in (
        created_guest_id,
        no_show_guest_id
      )
    )
    and not exists (
      select 1
      from public.seasonal_rates
      where id = seasonal_rate_id
    )
    and not exists (
      select 1
      from public.activity_logs
      where entity_id in (
        created_reservation_id,
        no_show_reservation_id
      )
    );

  return query
  values
    (
      'create_reservation_flow'::text,
      create_flow_passed,
      format(
        'Created %s for %s at total %s.',
        created_number,
        target_hotel_name,
        expected_create_total
      )
    ),
    (
      'deposit_collection'::text,
      deposit_passed,
      'Initial deposit was recorded and synchronized.'::text
    ),
    (
      'availability_after_create'::text,
      availability_after_create_passed,
      format(
        'Room %s was removed from availability.',
        target_room_number
      )
    ),
    (
      'guest_lookup'::text,
      guest_lookup_passed,
      'New guest was returned by secure hotel-scoped search.'::text
    ),
    (
      'edit_reservation_flow'::text,
      edit_flow_passed,
      'Dates, source, notes and additional deposit were updated.'::text
    ),
    (
      'amount_recalculation'::text,
      amount_recalculated_passed,
      format(
        'Total recalculated from %s to %s.',
        expected_create_total,
        expected_edit_total
      )
    ),
    (
      'availability_recalculation'::text,
      availability_recalculated_passed,
      'Old dates were released and edited dates were allocated.'::text
    ),
    (
      'cancel_reservation_flow'::text,
      cancel_flow_passed,
      'Reservation was cancelled with a required reason.'::text
    ),
    (
      'cancel_releases_availability'::text,
      cancel_released_passed,
      'Cancelled reservation released the room.'::text
    ),
    (
      'no_show_flow'::text,
      no_show_flow_passed,
      'Confirmed reservation changed to no_show.'::text
    ),
    (
      'no_show_releases_availability'::text,
      no_show_released_passed,
      'No-show reservation released the room.'::text
    ),
    (
      'status_history'::text,
      status_history_passed,
      'Create, cancel and no-show status history was recorded.'::text
    ),
    (
      'activity_logs'::text,
      activity_logs_passed,
      'Create, update, cancellation and no-show actions were logged.'::text
    ),
    (
      'cleanup_completed'::text,
      cleanup_passed,
      'All test reservations, guests, rates, logs and sequence changes were removed.'::text
    );
exception
  when others then
    if actor_user is not null then
      perform set_config(
        'request.jwt.claim.sub',
        actor_user::text,
        true
      );
    end if;

    if created_reservation_id is not null
       or no_show_reservation_id is not null
    then
      delete from public.activity_logs
      where hotel_id = target_hotel
        and entity_id in (
          created_reservation_id,
          no_show_reservation_id
        );

      delete from public.reservations
      where hotel_id = target_hotel
        and id in (
          created_reservation_id,
          no_show_reservation_id
        );
    end if;

    if created_guest_id is not null
       or no_show_guest_id is not null
    then
      delete from public.guests
      where hotel_id = target_hotel
        and id in (
          created_guest_id,
          no_show_guest_id
        );
    end if;

    if seasonal_rate_id is not null then
      delete from public.seasonal_rates
      where id = seasonal_rate_id
        and hotel_id = target_hotel;
    end if;

    if target_hotel is not null then
      if sequence_existed then
        update public.reservation_number_sequences
        set last_number = sequence_before
        where hotel_id = target_hotel
          and sequence_year =
            test_sequence_year;
      else
        delete from public.reservation_number_sequences
        where hotel_id = target_hotel
          and sequence_year =
            test_sequence_year;
      end if;
    end if;

    raise;
end;
$$;

revoke all on function private.run_day3_crud_exit_test_20260722()
from public;

select *
from private.run_day3_crud_exit_test_20260722()
order by test_name;
