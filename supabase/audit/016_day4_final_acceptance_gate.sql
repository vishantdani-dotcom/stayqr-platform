-- ============================================================================
-- StayQR Day 4 — Final Acceptance Gate (Targeted Pendency Closure)
--
-- Run after migration 202607230006_day4_acceptance_hardening.sql.
-- This creates isolated far-future records, tests the remaining server-side
-- acceptance requirements, cleans everything and returns one row per test.
--
-- Expected: every row has passed = true.
-- ============================================================================

create or replace function private.run_day4_final_acceptance_gate_20260723()
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
  target_room uuid;
  target_room_number text;
  target_room_type uuid;
  target_rate_plan uuid;
  max_adults integer;
  max_children integer;
  max_occupancy integer;

  temporary_room uuid;
  temporary_room_number text :=
    'D4A-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
  test_guest uuid;
  test_phone text :=
    'D4A' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 10);
  test_source_reference text :=
    'DAY4-FINAL-ACCEPTANCE-' ||
    upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));

  baseline_rate uuid;
  changed_rate uuid;
  baseline_nightly numeric(12,2) := 1400;
  changed_nightly numeric(12,2) := 2400;

  test_start date := current_date + 2200;
  test_end date := current_date + 2202;
  changed_start date := current_date + 2210;
  changed_end date := current_date + 2212;
  block_start date := current_date + 2220;
  block_end date := current_date + 2222;

  created_reservation jsonb;
  test_reservation_id uuid;
  test_reservation_room_id uuid;
  reservation_number text;
  reservation_updated_at timestamptz;
  original_activity_count bigint;
  final_activity_count bigint;

  created_block jsonb;
  block_id uuid;
  cancelled_block jsonb;

  test_sequence_year integer :=
    extract(year from (current_date + 2200))::integer;
  sequence_existed boolean := false;
  sequence_before bigint;

  matching_calendar jsonb;
  excluding_calendar jsonb;

  filter_include_passed boolean := false;
  filter_exclude_passed boolean := false;
  stale_rejected boolean := false;
  capacity_rejected boolean := false;
  rate_change_rejected boolean := false;
  no_partial_activity boolean := false;
  block_actor_visible boolean := false;
  block_reason_required boolean := false;
  block_cancel_passed boolean := false;
  cleanup_passed boolean := false;

  stale_message text;
  capacity_message text;
  rate_message text;
  reason_message text;
begin
  select administrator.user_id
  into actor_user
  from public.platform_admins administrator
  where administrator.status = 'active'
  order by administrator.created_at
  limit 1;

  if actor_user is null then
    raise exception 'Day 4 acceptance requires an active platform administrator.';
  end if;

  perform set_config(
    'request.jwt.claim.sub',
    actor_user::text,
    true
  );

  select
    hotel.id,
    room.id,
    room.room_number,
    room.room_type_id,
    rate_plan.id,
    room_type.max_adults,
    room_type.max_children,
    room_type.max_occupancy
  into
    target_hotel,
    target_room,
    target_room_number,
    target_room_type,
    target_rate_plan,
    max_adults,
    max_children,
    max_occupancy
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
    and not exists (
      select 1
      from public.room_inventory_allocations allocation
      where allocation.hotel_id = hotel.id
        and allocation.room_id = room.id
        and allocation.status = 'active'
        and allocation.stay_dates &&
          daterange(test_start, block_end, '[)')
    )
  order by hotel.created_at, room.created_at
  limit 1;

  if target_room is null then
    raise exception
      'Day 4 acceptance requires one usable room and active rate plan.';
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
    target_room_type,
    'available'
  from public.rooms room
  where room.id = target_room
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
    'StayQR Day 4 Final Acceptance Guest',
    test_phone,
    lower(test_source_reference) || '@stayqr.invalid',
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
    target_rate_plan,
    'Day 4 Final Acceptance Baseline Rate',
    test_start,
    test_end,
    baseline_nightly,
    -3000,
    true
  )
  returning id into baseline_rate;

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
    'Day 4 Final Acceptance Changed Rate',
    changed_start,
    changed_end,
    changed_nightly,
    -3000,
    true
  )
  returning id into changed_rate;

  created_reservation := public.create_reservation(
    target_hotel,
    jsonb_build_object(
      'status', 'confirmed',
      'booking_source', 'other',
      'source_reference', test_source_reference,
      'arrival_date', test_start,
      'departure_date', test_end,
      'adults', 1,
      'children', 0,
      'room_type_id', target_room_type,
      'room_id', target_room,
      'rate_plan_id', target_rate_plan,
      'guest', jsonb_build_object('id', test_guest),
      'internal_notes', 'Temporary Day 4 final acceptance record'
    )
  );

  test_reservation_id := (created_reservation->>'id')::uuid;
  test_reservation_room_id :=
    (created_reservation->'rooms'->0->>'id')::uuid;
  reservation_number := created_reservation->>'reservation_number';
  reservation_updated_at :=
    (created_reservation->>'updated_at')::timestamptz;

  matching_calendar := public.get_booking_calendar(
    target_hotel,
    test_start - 1,
    test_end + 1,
    target_room_type,
    array['confirmed'],
    array['active'],
    100,
    0
  );

  excluding_calendar := public.get_booking_calendar(
    target_hotel,
    test_start - 1,
    test_end + 1,
    target_room_type,
    array['draft'],
    array['active'],
    100,
    0
  );

  filter_include_passed := exists (
    select 1
    from jsonb_array_elements(matching_calendar->'events') event
    where event->>'event_type' = 'reservation'
      and (event->>'reservation_id')::uuid = test_reservation_id
  );

  filter_exclude_passed := not exists (
    select 1
    from jsonb_array_elements(excluding_calendar->'events') event
    where event->>'event_type' = 'reservation'
      and (event->>'reservation_id')::uuid = test_reservation_id
  );

  select count(*)
  into original_activity_count
  from public.activity_logs log
  where log.hotel_id = target_hotel
    and log.entity_type = 'reservation'
    and log.entity_id = test_reservation_id;

  begin
    perform public.move_reservation_on_calendar(
      target_hotel,
      test_reservation_id,
      test_reservation_room_id,
      temporary_room,
      test_start,
      reservation_updated_at - interval '1 second'
    );
  exception
    when others then
      stale_message := sqlerrm;
      stale_rejected :=
        position('Refresh and try again' in sqlerrm) > 0
        or position('changed after the calendar loaded' in lower(sqlerrm)) > 0;
  end;

  update public.reservations
  set
    adults = greatest(max_adults, max_occupancy) + 1,
    updated_by = actor_user,
    updated_at = now()
  where hotel_id = target_hotel
    and id = test_reservation_id;

  select reservation.updated_at
  into reservation_updated_at
  from public.reservations reservation
  where reservation.hotel_id = target_hotel
    and reservation.id = test_reservation_id;

  begin
    perform public.move_reservation_on_calendar(
      target_hotel,
      test_reservation_id,
      test_reservation_room_id,
      temporary_room,
      test_start,
      reservation_updated_at
    );
  exception
    when others then
      capacity_message := sqlerrm;
      capacity_rejected :=
        position('capacity' in lower(sqlerrm)) > 0
        or position('guest count exceeds' in lower(sqlerrm)) > 0;
  end;

  update public.reservations
  set
    adults = 1,
    children = 0,
    updated_by = actor_user,
    updated_at = now()
  where hotel_id = target_hotel
    and id = test_reservation_id;

  select reservation.updated_at
  into reservation_updated_at
  from public.reservations reservation
  where reservation.hotel_id = target_hotel
    and reservation.id = test_reservation_id;

  begin
    perform public.move_reservation_on_calendar(
      target_hotel,
      test_reservation_id,
      test_reservation_room_id,
      temporary_room,
      changed_start,
      reservation_updated_at
    );
  exception
    when others then
      rate_message := sqlerrm;
      rate_change_rejected :=
        position('change the reservation rate' in lower(sqlerrm)) > 0
        or position('target dates change' in lower(sqlerrm)) > 0;
  end;

  select count(*)
  into final_activity_count
  from public.activity_logs log
  where log.hotel_id = target_hotel
    and log.entity_type = 'reservation'
    and log.entity_id = test_reservation_id;

  no_partial_activity :=
    final_activity_count = original_activity_count
    and exists (
      select 1
      from public.reservation_rooms room_record
      where room_record.hotel_id = target_hotel
        and room_record.id = test_reservation_room_id
        and room_record.room_id = target_room
        and room_record.status = 'confirmed'
    )
    and exists (
      select 1
      from public.reservations reservation
      where reservation.hotel_id = target_hotel
        and reservation.id = test_reservation_id
        and reservation.arrival_date = test_start
        and reservation.departure_date = test_end
    )
    and exists (
      select 1
      from public.room_inventory_allocations allocation
      where allocation.hotel_id = target_hotel
        and allocation.reservation_room_id = test_reservation_room_id
        and allocation.room_id = target_room
        and allocation.status = 'active'
        and allocation.stay_dates = daterange(test_start, test_end, '[)')
    );

  created_block := public.create_calendar_room_block(
    target_hotel,
    jsonb_build_object(
      'room_id', temporary_room,
      'block_type', 'operational',
      'start_date', block_start,
      'end_date', block_end,
      'reason', 'Day 4 final acceptance cancellation test',
      'notes', 'Temporary record; must be cleaned automatically'
    )
  );

  block_id := (created_block->>'id')::uuid;
  created_block := public.get_calendar_room_block_details(
    target_hotel,
    block_id
  );

  block_actor_visible :=
    nullif(trim(created_block->>'created_by_name'), '') is not null;

  begin
    perform public.change_calendar_room_block_status(
      target_hotel,
      block_id,
      'cancelled',
      null
    );
  exception
    when others then
      reason_message := sqlerrm;
      block_reason_required :=
        position('reason is required' in lower(sqlerrm)) > 0;
  end;

  cancelled_block := public.change_calendar_room_block_status(
    target_hotel,
    block_id,
    'cancelled',
    'Day 4 final acceptance cancellation reason'
  );

  block_cancel_passed :=
    cancelled_block->>'status' = 'cancelled'
    and cancelled_block->>'release_reason' =
      'Day 4 final acceptance cancellation reason'
    and not exists (
      select 1
      from public.room_inventory_allocations allocation
      where allocation.hotel_id = target_hotel
        and allocation.room_block_id = block_id
        and allocation.status = 'active'
    )
    and exists (
      select 1
      from public.activity_logs log
      where log.hotel_id = target_hotel
        and log.entity_type = 'room_block'
        and log.entity_id = block_id
        and log.action = 'room_block.cancelled'
    );

  delete from public.activity_logs log
  where log.hotel_id = target_hotel
    and log.entity_id in (test_reservation_id, block_id);

  delete from public.reservations reservation
  where reservation.hotel_id = target_hotel
    and reservation.id = test_reservation_id;

  delete from public.room_blocks block
  where block.hotel_id = target_hotel
    and block.id = block_id;

  delete from public.seasonal_rates rate
  where rate.hotel_id = target_hotel
    and rate.id in (baseline_rate, changed_rate);

  delete from public.guests guest
  where guest.hotel_id = target_hotel
    and guest.id = test_guest;

  delete from public.rooms room
  where room.hotel_id = target_hotel
    and room.id = temporary_room;

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

  cleanup_passed :=
    not exists (
      select 1
      from public.reservations reservation
      where reservation.id = test_reservation_id
        or reservation.source_reference = test_source_reference
    )
    and not exists (
      select 1
      from public.room_blocks block
      where block.id = block_id
    )
    and not exists (
      select 1
      from public.rooms room
      where room.id = temporary_room
    )
    and not exists (
      select 1
      from public.guests guest
      where guest.id = test_guest
    )
    and not exists (
      select 1
      from public.seasonal_rates rate
      where rate.id in (baseline_rate, changed_rate)
    );

  return query
  values
    (
      'status_filter_includes_matching_reservation'::text,
      filter_include_passed,
      'Confirmed filter returned the confirmed test reservation.'::text
    ),
    (
      'status_filter_excludes_non_matching_reservation'::text,
      filter_exclude_passed,
      'Draft filter excluded the confirmed test reservation.'::text
    ),
    (
      'stale_update_rejected'::text,
      stale_rejected,
      coalesce(stale_message, 'Expected stale-update rejection was not raised.')::text
    ),
    (
      'capacity_violation_rejected'::text,
      capacity_rejected,
      coalesce(capacity_message, 'Expected capacity rejection was not raised.')::text
    ),
    (
      'rate_changing_move_rejected'::text,
      rate_change_rejected,
      coalesce(rate_message, 'Expected rate-change rejection was not raised.')::text
    ),
    (
      'rejected_moves_created_no_partial_activity'::text,
      no_partial_activity,
      'Rejected moves left room, dates, inventory and activity unchanged.'::text
    ),
    (
      'room_block_created_by_visible'::text,
      block_actor_visible,
      coalesce(
        'Created by: ' || nullif(created_block->>'created_by_name', ''),
        'Room-block actor name was missing.'
      )::text
    ),
    (
      'room_block_cancellation_requires_reason'::text,
      block_reason_required,
      coalesce(reason_message, 'Expected mandatory-reason rejection was not raised.')::text
    ),
    (
      'room_block_cancellation_releases_inventory'::text,
      block_cancel_passed,
      'Cancelled block released inventory and recorded activity.'::text
    ),
    (
      'cleanup_completed'::text,
      cleanup_passed,
      format(
        'Temporary reservation %s, room %s and related records were removed.',
        coalesce(reservation_number, 'unknown'),
        coalesce(temporary_room_number, 'unknown')
      )::text
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
        and log.entity_id in (test_reservation_id, block_id);

      if test_reservation_id is not null then
        delete from public.reservations reservation
        where reservation.hotel_id = target_hotel
          and reservation.id = test_reservation_id;
      end if;

      if block_id is not null then
        delete from public.room_blocks block
        where block.hotel_id = target_hotel
          and block.id = block_id;
      end if;

      delete from public.seasonal_rates rate
      where rate.hotel_id = target_hotel
        and rate.id in (baseline_rate, changed_rate);

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

revoke all on function private.run_day4_final_acceptance_gate_20260723()
from public;

select *
from private.run_day4_final_acceptance_gate_20260723()
order by test_name;
