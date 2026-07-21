-- ============================================================================
-- StayQR Day 4 — Booking Calendar and Room Allocation Exit Test
--
-- Run only after Verification 012 is green.
-- This function creates isolated far-future test records, validates calendar
-- views, room movement, overlap rejection, blocks, pagination, tenant access
-- and cleanup, then removes all generated records before returning.
--
-- Expected: every row has passed = true.
-- ============================================================================

create or replace function private.run_day4_calendar_exit_test_20260723()
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
  unaffiliated_user uuid := gen_random_uuid();

  target_hotel uuid;
  target_hotel_name text;
  source_room uuid;
  source_room_number text;
  source_room_type uuid;
  source_rate_plan uuid;

  temporary_room uuid;
  temporary_room_number text :=
    'D4-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));

  test_guest uuid;
  test_guest_phone text :=
    'D4' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 10);

  seasonal_rate uuid;
  fixed_nightly_rate numeric(12,2) := 1700;

  test_start date := current_date + 1200;
  test_end date := current_date + 1202;
  moved_start date := current_date + 1205;
  moved_end date := current_date + 1207;
  adjacent_end date := current_date + 1209;

  main_reservation jsonb;
  main_reservation_id uuid;
  main_reservation_room_id uuid;
  main_reservation_number text;
  main_updated_at timestamptz;

  draft_reservation jsonb;
  unallocated_reservation_id uuid;
  unallocated_reservation_room_id uuid;
  unallocated_reservation_number text;
  unallocated_updated_at timestamptz;

  active_block jsonb;
  active_block_id uuid;
  adjacent_block jsonb;
  adjacent_block_id uuid;

  test_sequence_year integer :=
    extract(year from (current_date + 1200))::integer;
  sequence_existed boolean := false;
  sequence_before bigint;

  day_calendar jsonb;
  week_calendar jsonb;
  month_calendar jsonb;
  first_page jsonb;
  second_page jsonb;
  unallocated_calendar jsonb;
  assigned_calendar jsonb;

  calendar_day_passed boolean := false;
  calendar_week_passed boolean := false;
  calendar_month_passed boolean := false;
  pagination_passed boolean := false;
  valid_reassignment_passed boolean := false;
  invalid_drag_rejected boolean := false;
  invalid_drag_no_corruption boolean := false;
  block_create_passed boolean := false;
  block_overlap_rejected boolean := false;
  block_update_passed boolean := false;
  block_release_passed boolean := false;
  adjacent_block_passed boolean := false;
  unallocated_visible_passed boolean := false;
  unallocated_assignment_passed boolean := false;
  cross_hotel_access_denied boolean := false;
  activity_logs_passed boolean := false;
  cleanup_passed boolean := false;

  rejected_message text;
begin
  select administrator.user_id
  into actor_user
  from public.platform_admins administrator
  where administrator.status = 'active'
  order by administrator.created_at
  limit 1;

  if actor_user is null then
    raise exception 'Day 4 test requires an active platform administrator.';
  end if;

  perform set_config(
    'request.jwt.claim.sub',
    actor_user::text,
    true
  );

  select
    hotel.id,
    hotel.hotel_name,
    room.id,
    room.room_number,
    room.room_type_id,
    rate_plan.id
  into
    target_hotel,
    target_hotel_name,
    source_room,
    source_room_number,
    source_room_type,
    source_rate_plan
  from public.hotels hotel
  join public.rooms room
    on room.hotel_id = hotel.id
   and room.status not in ('maintenance', 'out_of_order')
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
    and not exists (
      select 1
      from public.room_inventory_allocations allocation
      where allocation.hotel_id = hotel.id
        and allocation.room_id = room.id
        and allocation.status = 'active'
        and allocation.stay_dates &&
          daterange(test_start, adjacent_end, '[)')
    )
  order by hotel.created_at, room.created_at
  limit 1;

  if source_room is null then
    raise exception
      'Day 4 test requires one usable room and active rate plan.';
  end if;

  select exists (
    select 1
    from public.reservation_number_sequences sequence
    where sequence.hotel_id = target_hotel
      and sequence.sequence_year =
        test_sequence_year
  )
  into sequence_existed;

  if sequence_existed then
    select sequence.last_number
    into sequence_before
    from public.reservation_number_sequences sequence
    where sequence.hotel_id = target_hotel
      and sequence.sequence_year =
        test_sequence_year;
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
    temporary_room_number,
    room.room_type,
    source_room_type,
    'available'
  from public.rooms room
  where room.id = source_room
    and room.hotel_id = target_hotel
  returning id into temporary_room;

  insert into public.guests (
    hotel_id,
    full_name,
    phone,
    email,
    preferred_language
  )
  values (
    target_hotel,
    'StayQR Day 4 Calendar Test Guest',
    test_guest_phone,
    'day4-calendar-test@stayqr.invalid',
    'english'
  )
  returning id into test_guest;

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
    'Day 4 Calendar Fixed Test Rate',
    test_start - 1,
    adjacent_end + 1,
    fixed_nightly_rate,
    -2000,
    true
  )
  returning id into seasonal_rate;

  main_reservation := public.create_reservation(
    target_hotel,
    jsonb_build_object(
      'status', 'confirmed',
      'booking_source', 'other',
      'source_reference', 'DAY4-CALENDAR-MAIN',
      'arrival_date', test_start,
      'departure_date', test_end,
      'adults', 1,
      'children', 0,
      'room_type_id', source_room_type,
      'room_id', source_room,
      'rate_plan_id', source_rate_plan,
      'guest', jsonb_build_object('id', test_guest),
      'internal_notes', 'Day 4 calendar exit test'
    )
  );

  main_reservation_id := (main_reservation->>'id')::uuid;
  main_reservation_room_id :=
    (main_reservation->'rooms'->0->>'id')::uuid;
  main_reservation_number :=
    main_reservation->>'reservation_number';
  main_updated_at :=
    (main_reservation->>'updated_at')::timestamptz;

  day_calendar := public.get_booking_calendar(
    target_hotel,
    test_start,
    test_start + 1,
    null,
    array['confirmed'],
    array['active'],
    100,
    0
  );

  week_calendar := public.get_booking_calendar(
    target_hotel,
    test_start - 1,
    test_start + 6,
    null,
    array['confirmed'],
    array['active'],
    100,
    0
  );

  month_calendar := public.get_booking_calendar(
    target_hotel,
    test_start - 7,
    test_start + 35,
    null,
    array['confirmed'],
    array['active'],
    100,
    0
  );

  calendar_day_passed := exists (
    select 1
    from jsonb_array_elements(day_calendar->'events') event
    where event->>'event_type' = 'reservation'
      and (event->>'reservation_id')::uuid =
        main_reservation_id
  );

  calendar_week_passed := exists (
    select 1
    from jsonb_array_elements(week_calendar->'events') event
    where event->>'event_type' = 'reservation'
      and (event->>'reservation_id')::uuid =
        main_reservation_id
  );

  calendar_month_passed := exists (
    select 1
    from jsonb_array_elements(month_calendar->'events') event
    where event->>'event_type' = 'reservation'
      and (event->>'reservation_id')::uuid =
        main_reservation_id
  );

  first_page := public.get_booking_calendar(
    target_hotel,
    test_start,
    test_end,
    source_room_type,
    array['confirmed'],
    array['active'],
    1,
    0
  );

  second_page := public.get_booking_calendar(
    target_hotel,
    test_start,
    test_end,
    source_room_type,
    array['confirmed'],
    array['active'],
    1,
    1
  );

  pagination_passed :=
    (first_page->'pagination'->>'total_rooms')::integer >= 2
    and jsonb_array_length(first_page->'rooms') = 1
    and jsonb_array_length(second_page->'rooms') = 1
    and first_page->'rooms'->0->>'id' is distinct from
      second_page->'rooms'->0->>'id';

  main_reservation := public.move_reservation_on_calendar(
    target_hotel,
    main_reservation_id,
    main_reservation_room_id,
    temporary_room,
    moved_start,
    main_updated_at
  );

  main_updated_at :=
    (main_reservation->>'updated_at')::timestamptz;

  valid_reassignment_passed :=
    (main_reservation->>'arrival_date')::date = moved_start
    and (main_reservation->>'departure_date')::date = moved_end
    and (
      main_reservation->'rooms'->0->>'room_id'
    )::uuid = temporary_room
    and exists (
      select 1
      from public.room_inventory_allocations allocation
      where allocation.hotel_id = target_hotel
        and allocation.reservation_room_id =
          main_reservation_room_id
        and allocation.room_id = temporary_room
        and allocation.starts_on = moved_start
        and allocation.ends_on = moved_end
        and allocation.status = 'active'
    );

  active_block := public.create_calendar_room_block(
    target_hotel,
    jsonb_build_object(
      'room_id', source_room,
      'block_type', 'maintenance',
      'start_date', moved_start,
      'end_date', moved_end,
      'reason', 'Day 4 invalid-drag blocker'
    )
  );

  active_block_id := (active_block->>'id')::uuid;
  block_create_passed :=
    active_block->>'status' = 'active'
    and exists (
      select 1
      from public.room_inventory_allocations allocation
      where allocation.room_block_id = active_block_id
        and allocation.status = 'active'
    );

  begin
    perform public.move_reservation_on_calendar(
      target_hotel,
      main_reservation_id,
      main_reservation_room_id,
      source_room,
      moved_start,
      main_updated_at
    );
  exception
    when others then
      rejected_message := sqlerrm;
      invalid_drag_rejected :=
        position('unavailable' in lower(sqlerrm)) > 0
        or position('overlap' in lower(sqlerrm)) > 0;
  end;

  invalid_drag_no_corruption :=
    exists (
      select 1
      from public.room_inventory_allocations allocation
      where allocation.hotel_id = target_hotel
        and allocation.reservation_room_id =
          main_reservation_room_id
        and allocation.room_id = temporary_room
        and allocation.starts_on = moved_start
        and allocation.ends_on = moved_end
        and allocation.status = 'active'
    )
    and not exists (
      select 1
      from public.room_inventory_allocations allocation
      where allocation.hotel_id = target_hotel
        and allocation.reservation_room_id =
          main_reservation_room_id
        and allocation.room_id = source_room
        and allocation.status = 'active'
    );

  begin
    perform public.create_calendar_room_block(
      target_hotel,
      jsonb_build_object(
        'room_id', temporary_room,
        'block_type', 'operational',
        'start_date', moved_start,
        'end_date', moved_end,
        'reason', 'Day 4 overlap rejection test'
      )
    );
  exception
    when others then
      block_overlap_rejected :=
        position('overlap' in lower(sqlerrm)) > 0
        or position('inventory' in lower(sqlerrm)) > 0;
  end;

  adjacent_block := public.create_calendar_room_block(
    target_hotel,
    jsonb_build_object(
      'room_id', temporary_room,
      'block_type', 'deep_cleaning',
      'start_date', moved_end,
      'end_date', moved_end + 1,
      'reason', 'Day 4 adjacent block test'
    )
  );

  adjacent_block_id := (adjacent_block->>'id')::uuid;
  adjacent_block_passed :=
    adjacent_block->>'status' = 'active';

  active_block := public.update_calendar_room_block(
    target_hotel,
    active_block_id,
    jsonb_build_object(
      'end_date', moved_end + 1,
      'reason', 'Day 4 updated invalid-drag blocker'
    ),
    (active_block->>'updated_at')::timestamptz
  );

  block_update_passed :=
    (active_block->>'end_date')::date = moved_end + 1
    and active_block->>'reason' =
      'Day 4 updated invalid-drag blocker';

  active_block := public.change_calendar_room_block_status(
    target_hotel,
    active_block_id,
    'released',
    'Day 4 release verification'
  );

  block_release_passed :=
    active_block->>'status' = 'released'
    and active_block->>'release_reason' =
      'Day 4 release verification'
    and not exists (
      select 1
      from public.room_inventory_allocations allocation
      where allocation.room_block_id = active_block_id
        and allocation.status = 'active'
    );

  draft_reservation := public.create_reservation(
    target_hotel,
    jsonb_build_object(
      'status', 'draft',
      'booking_source', 'other',
      'source_reference', 'DAY4-UNALLOCATED',
      'arrival_date', test_start + 20,
      'departure_date', test_start + 22,
      'adults', 1,
      'children', 0,
      'room_type_id', source_room_type,
      'rate_plan_id', source_rate_plan,
      'guest', jsonb_build_object('id', test_guest)
    )
  );

  unallocated_reservation_id :=
    (draft_reservation->>'id')::uuid;
  unallocated_reservation_room_id :=
    (draft_reservation->'rooms'->0->>'id')::uuid;
  unallocated_reservation_number :=
    draft_reservation->>'reservation_number';

  update public.reservations
  set
    status = 'tentative',
    updated_by = actor_user,
    updated_at = now()
  where hotel_id = target_hotel
    and id = unallocated_reservation_id;

  select reservation.updated_at
  into unallocated_updated_at
  from public.reservations reservation
  where reservation.hotel_id = target_hotel
    and reservation.id = unallocated_reservation_id;

  unallocated_calendar := public.get_booking_calendar(
    target_hotel,
    test_start + 19,
    test_start + 24,
    source_room_type,
    array['tentative'],
    array['active'],
    100,
    0
  );

  unallocated_visible_passed := exists (
    select 1
    from jsonb_array_elements(
      unallocated_calendar->'unallocated_reservations'
    ) item
    where (item->>'reservation_id')::uuid =
      unallocated_reservation_id
  );

  draft_reservation := public.move_reservation_on_calendar(
    target_hotel,
    unallocated_reservation_id,
    unallocated_reservation_room_id,
    source_room,
    test_start + 20,
    unallocated_updated_at
  );

  assigned_calendar := public.get_booking_calendar(
    target_hotel,
    test_start + 19,
    test_start + 24,
    source_room_type,
    array['tentative'],
    array['active'],
    100,
    0
  );

  unallocated_assignment_passed :=
    not exists (
      select 1
      from jsonb_array_elements(
        assigned_calendar->'unallocated_reservations'
      ) item
      where (item->>'reservation_id')::uuid =
        unallocated_reservation_id
    )
    and exists (
      select 1
      from jsonb_array_elements(assigned_calendar->'events') event
      where event->>'event_type' = 'reservation'
        and (event->>'reservation_id')::uuid =
          unallocated_reservation_id
        and (event->>'room_id')::uuid = source_room
    )
    and exists (
      select 1
      from public.room_inventory_allocations allocation
      where allocation.reservation_room_id =
        unallocated_reservation_room_id
        and allocation.room_id = source_room
        and allocation.status = 'active'
    );

  perform set_config(
    'request.jwt.claim.sub',
    unaffiliated_user::text,
    true
  );

  begin
    perform public.get_booking_calendar(
      target_hotel,
      test_start,
      test_end,
      null,
      null,
      array['active'],
      20,
      0
    );
  exception
    when others then
      cross_hotel_access_denied :=
        position('Hotel access denied' in sqlerrm) > 0;
  end;

  perform set_config(
    'request.jwt.claim.sub',
    actor_user::text,
    true
  );

  activity_logs_passed :=
    exists (
      select 1
      from public.activity_logs log
      where log.hotel_id = target_hotel
        and log.entity_id = main_reservation_id
        and log.action = 'reservation.calendar_moved'
    )
    and exists (
      select 1
      from public.activity_logs log
      where log.hotel_id = target_hotel
        and log.entity_id = active_block_id
        and log.action = 'room_block.created'
    )
    and exists (
      select 1
      from public.activity_logs log
      where log.hotel_id = target_hotel
        and log.entity_id = active_block_id
        and log.action = 'room_block.updated'
    )
    and exists (
      select 1
      from public.activity_logs log
      where log.hotel_id = target_hotel
        and log.entity_id = active_block_id
        and log.action = 'room_block.released'
    );

  -- Cleanup generic logs before their source records.
  delete from public.activity_logs log
  where log.hotel_id = target_hotel
    and (
      log.entity_id in (
        main_reservation_id,
        unallocated_reservation_id,
        active_block_id,
        adjacent_block_id
      )
      or log.description ilike '%Day 4%'
    );

  delete from public.reservations reservation
  where reservation.hotel_id = target_hotel
    and reservation.id in (
      main_reservation_id,
      unallocated_reservation_id
    );

  delete from public.room_blocks block
  where block.hotel_id = target_hotel
    and block.id in (
      active_block_id,
      adjacent_block_id
    );

  delete from public.seasonal_rates rate
  where rate.hotel_id = target_hotel
    and rate.id = seasonal_rate;

  delete from public.guests guest
  where guest.hotel_id = target_hotel
    and guest.id = test_guest;

  delete from public.rooms room
  where room.hotel_id = target_hotel
    and room.id = temporary_room;

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
      from public.reservations reservation
      where reservation.reservation_number in (
        main_reservation_number,
        unallocated_reservation_number
      )
        or reservation.source_reference in (
          'DAY4-CALENDAR-MAIN',
          'DAY4-UNALLOCATED'
        )
    )
    and not exists (
      select 1
      from public.rooms room
      where room.id = temporary_room
    )
    and not exists (
      select 1
      from public.room_blocks block
      where block.id in (active_block_id, adjacent_block_id)
    )
    and not exists (
      select 1
      from public.guests guest
      where guest.id = test_guest
    )
    and not exists (
      select 1
      from public.seasonal_rates rate
      where rate.id = seasonal_rate
    );

  return query
  values
    (
      'calendar_day_representation'::text,
      calendar_day_passed,
      'Day view returned the reservation event.'::text
    ),
    (
      'calendar_week_representation'::text,
      calendar_week_passed,
      'Week view returned the same reservation event.'::text
    ),
    (
      'calendar_month_representation'::text,
      calendar_month_passed,
      'Month view returned the same reservation event.'::text
    ),
    (
      'room_pagination'::text,
      pagination_passed,
      'Room pagination returned distinct one-room pages.'::text
    ),
    (
      'valid_calendar_move'::text,
      valid_reassignment_passed,
      'Reservation moved atomically to the target room and dates.'::text
    ),
    (
      'invalid_drag_rejected'::text,
      invalid_drag_rejected,
      coalesce(rejected_message, 'Invalid move was rejected.')::text
    ),
    (
      'invalid_drag_no_corruption'::text,
      invalid_drag_no_corruption,
      'Rejected movement left the authoritative allocation unchanged.'::text
    ),
    (
      'room_block_creation'::text,
      block_create_passed,
      'Active room block created an inventory allocation.'::text
    ),
    (
      'room_block_overlap_rejected'::text,
      block_overlap_rejected,
      'Room block overlapping a reservation was rejected.'::text
    ),
    (
      'room_block_update'::text,
      block_update_passed,
      'Active block dates and reason were updated.'::text
    ),
    (
      'room_block_release'::text,
      block_release_passed,
      'Released block removed its active inventory allocation.'::text
    ),
    (
      'adjacent_block_allowed'::text,
      adjacent_block_passed,
      'Block beginning exactly at checkout was accepted.'::text
    ),
    (
      'unallocated_reservation_visible'::text,
      unallocated_visible_passed,
      'Tentative unallocated reservation appeared in the queue.'::text
    ),
    (
      'unallocated_room_assignment'::text,
      unallocated_assignment_passed,
      'Unallocated reservation received one valid room allocation.'::text
    ),
    (
      'tenant_access_denied'::text,
      cross_hotel_access_denied,
      'Unaffiliated identity was denied calendar access.'::text
    ),
    (
      'activity_logs'::text,
      activity_logs_passed,
      'Calendar movement and room-block actions were logged.'::text
    ),
    (
      'cleanup_completed'::text,
      cleanup_passed,
      format(
        'All Day 4 test records for %s were removed.',
        target_hotel_name
      )
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

    if target_hotel is not null then
      delete from public.activity_logs log
      where log.hotel_id = target_hotel
        and (
          log.entity_id in (
            main_reservation_id,
            unallocated_reservation_id,
            active_block_id,
            adjacent_block_id
          )
          or log.description ilike '%Day 4%'
        );

      delete from public.reservations reservation
      where reservation.hotel_id = target_hotel
        and reservation.id in (
          main_reservation_id,
          unallocated_reservation_id
        );

      delete from public.room_blocks block
      where block.hotel_id = target_hotel
        and block.id in (
          active_block_id,
          adjacent_block_id
        );

      if seasonal_rate is not null then
        delete from public.seasonal_rates rate
        where rate.hotel_id = target_hotel
          and rate.id = seasonal_rate;
      end if;

      if test_guest is not null then
        delete from public.guests guest
        where guest.hotel_id = target_hotel
          and guest.id = test_guest;
      end if;

      if temporary_room is not null then
        delete from public.rooms room
        where room.hotel_id = target_hotel
          and room.id = temporary_room;
      end if;

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

revoke all on function private.run_day4_calendar_exit_test_20260723()
from public;

select *
from private.run_day4_calendar_exit_test_20260723()
order by test_name;
