-- ============================================================================
-- StayQR Day 4 — Browser Acceptance Cleanup
--
-- Run only after all browser acceptance checks are complete.
-- This uses the state written by audit 017 and removes only DAY4-ACCEPT data.
-- ============================================================================

do $$
declare
  state_payload jsonb;
  target_hotel uuid;
  actor_user uuid;
  room_prefix text;
  direct_session uuid;
  seasonal_rate uuid;
  test_sequence_year integer;
  sequence_existed boolean;
  sequence_before bigint;
begin
  select state.payload
  into state_payload
  from private.day4_browser_acceptance_state_20260723 state
  where state.singleton = true
  for update;

  if state_payload is null then
    raise exception
      'Day 4 browser acceptance state was not found. Nothing was cleaned.';
  end if;

  target_hotel := (state_payload->>'hotel_id')::uuid;
  actor_user := (state_payload->>'actor_user')::uuid;
  room_prefix := state_payload->>'room_prefix';
  direct_session := nullif(state_payload->>'guest_session_id', '')::uuid;
  seasonal_rate := nullif(state_payload->>'seasonal_rate_id', '')::uuid;
  test_sequence_year := (state_payload->>'sequence_year')::integer;
  sequence_existed := coalesce((state_payload->>'sequence_existed')::boolean, false);
  sequence_before := nullif(state_payload->>'sequence_before', '')::bigint;

  perform set_config(
    'request.jwt.claim.sub',
    actor_user::text,
    true
  );

  delete from public.activity_logs log
  where log.hotel_id = target_hotel
    and (
      log.entity_id in (
        select reservation.id
        from public.reservations reservation
        where reservation.hotel_id = target_hotel
          and reservation.source_reference like 'DAY4-ACCEPT-%'
      )
      or log.entity_id in (
        select block.id
        from public.room_blocks block
        where block.hotel_id = target_hotel
          and block.reason like 'DAY4 ACCEPT%'
      )
      or log.entity_id = direct_session
    );

  delete from public.reservations reservation
  where reservation.hotel_id = target_hotel
    and reservation.source_reference like 'DAY4-ACCEPT-%';

  delete from public.room_blocks block
  where block.hotel_id = target_hotel
    and block.reason like 'DAY4 ACCEPT%';

  if direct_session is not null then
    delete from public.guest_sessions session
    where session.hotel_id = target_hotel
      and session.id = direct_session;
  end if;

  -- Remove only allocations attached to the temporary QA rooms. Source records
  -- have already been removed, so these can only be inactive acceptance rows.
  delete from public.room_inventory_allocations allocation
  where allocation.hotel_id = target_hotel
    and allocation.room_id in (
      select room.id
      from public.rooms room
      where room.hotel_id = target_hotel
        and room.room_number like room_prefix || '%'
    );

  if seasonal_rate is not null then
    delete from public.seasonal_rates rate
    where rate.hotel_id = target_hotel
      and rate.id = seasonal_rate;
  end if;

  delete from public.guests guest
  where guest.hotel_id = target_hotel
    and (
      lower(coalesce(guest.email, '')) in (
        'day4-browser-acceptance@stayqr.invalid',
        'day4-direct-stay@stayqr.invalid'
      )
      or lower(coalesce(guest.email, '')) like
        'day4-accept-ui%@stayqr.invalid'
    )
    and not exists (
      select 1
      from public.reservations reservation
      where reservation.hotel_id = guest.hotel_id
        and reservation.primary_guest_id = guest.id
    )
    and not exists (
      select 1
      from public.guest_sessions session
      where session.hotel_id = guest.hotel_id
        and session.guest_id = guest.id
    );

  delete from public.rooms room
  where room.hotel_id = target_hotel
    and room.room_number like room_prefix || '%';

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

  delete from private.day4_browser_acceptance_state_20260723
  where singleton = true;
end
$$;

select jsonb_pretty(
  jsonb_build_object(
    'expected_result', 'All values must be 0.',
    'remaining_acceptance_reservations', (
      select count(*)
      from public.reservations reservation
      where reservation.source_reference like 'DAY4-ACCEPT-%'
    ),
    'remaining_acceptance_blocks', (
      select count(*)
      from public.room_blocks block
      where block.reason like 'DAY4 ACCEPT%'
    ),
    'remaining_acceptance_guests', (
      select count(*)
      from public.guests guest
      where lower(coalesce(guest.email, '')) in (
        'day4-browser-acceptance@stayqr.invalid',
        'day4-direct-stay@stayqr.invalid'
      )
      or lower(coalesce(guest.email, '')) like
        'day4-accept-ui%@stayqr.invalid'
    ),
    'remaining_acceptance_rooms', (
      select count(*)
      from public.rooms room
      where room.room_number like 'D4QA-%'
    ),
    'remaining_acceptance_sessions', (
      select count(*)
      from public.guest_sessions session
      join public.guests guest
        on guest.id = session.guest_id
       and guest.hotel_id = session.hotel_id
      where lower(coalesce(guest.email, '')) =
        'day4-direct-stay@stayqr.invalid'
    ),
    'remaining_acceptance_rates', (
      select count(*)
      from public.seasonal_rates rate
      where rate.name = 'Day 4 Browser Acceptance Fixed Rate'
    ),
    'remaining_acceptance_state_rows', (
      select count(*)
      from private.day4_browser_acceptance_state_20260723
    )
  )
) as stayqr_day4_browser_acceptance_cleanup;
