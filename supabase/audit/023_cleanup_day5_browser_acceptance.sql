-- ============================================================================
-- StayQR Day 5 — Browser Acceptance Cleanup
-- Run only after all Day 5 browser acceptance checks are complete.
-- ============================================================================

do $$
declare
  state_payload jsonb;
  target_hotel uuid;
  actor_user uuid;
  room_prefix text;
  test_sequence_year integer;
  sequence_existed boolean;
  sequence_before bigint;
  temporary_rate_plan_created boolean;
  temporary_rate_plan_id uuid;
begin
  select s.payload
  into state_payload
  from private.day5_browser_acceptance_state_20260724 s
  where s.singleton = true
  for update;

  if state_payload is null then
    raise exception 'Day 5 browser acceptance state was not found. Nothing was cleaned.';
  end if;

  target_hotel := (state_payload->>'hotel_id')::uuid;
  actor_user := (state_payload->>'actor_user')::uuid;
  room_prefix := state_payload->>'room_prefix';
  test_sequence_year := (state_payload->>'sequence_year')::integer;
  sequence_existed := coalesce((state_payload->>'sequence_existed')::boolean, false);
  sequence_before := nullif(state_payload->>'sequence_before', '')::bigint;
  temporary_rate_plan_created := coalesce(
    (state_payload->>'temporary_rate_plan_created')::boolean,
    false
  );
  temporary_rate_plan_id := nullif(state_payload->>'rate_plan_id', '')::uuid;

  perform set_config('request.jwt.claim.sub', actor_user::text, true);

  delete from public.activity_logs l
  where l.hotel_id = target_hotel
    and l.entity_id in (
      select r.id
      from public.reservations r
      where r.hotel_id = target_hotel
        and r.source_reference like 'DAY5-ACCEPT-%'
    );

  delete from public.reservation_checkin_events e
  where e.hotel_id = target_hotel
    and e.reservation_id in (
      select r.id from public.reservations r
      where r.hotel_id = target_hotel
        and r.source_reference like 'DAY5-ACCEPT-%'
    );

  delete from public.reservation_payment_transfers t
  where t.hotel_id = target_hotel
    and t.reservation_id in (
      select r.id from public.reservations r
      where r.hotel_id = target_hotel
        and r.source_reference like 'DAY5-ACCEPT-%'
    );

  delete from public.payment_collections c
  where c.hotel_id = target_hotel
    and c.reservation_id in (
      select r.id from public.reservations r
      where r.hotel_id = target_hotel
        and r.source_reference like 'DAY5-ACCEPT-%'
    );

  delete from public.payments p
  where p.hotel_id = target_hotel
    and p.reservation_id in (
      select r.id from public.reservations r
      where r.hotel_id = target_hotel
        and r.source_reference like 'DAY5-ACCEPT-%'
    );

  delete from public.guest_sessions gs
  where gs.hotel_id = target_hotel
    and gs.reservation_id in (
      select r.id from public.reservations r
      where r.hotel_id = target_hotel
        and r.source_reference like 'DAY5-ACCEPT-%'
    );

  delete from public.room_inventory_allocations a
  where a.hotel_id = target_hotel
    and a.room_id in (
      select rm.id
      from public.rooms rm
      where rm.hotel_id = target_hotel
        and rm.room_number like room_prefix || '%'
    );

  delete from public.reservations r
  where r.hotel_id = target_hotel
    and r.source_reference like 'DAY5-ACCEPT-%';

  delete from public.guests g
  where g.hotel_id = target_hotel
    and lower(coalesce(g.email, '')) like 'day5-%@stayqr.invalid'
    and not exists (
      select 1 from public.reservations r
      where r.hotel_id = g.hotel_id
        and r.primary_guest_id = g.id
    )
    and not exists (
      select 1 from public.guest_sessions gs
      where gs.hotel_id = g.hotel_id
        and gs.guest_id = g.id
    );

  delete from public.rooms rm
  where rm.hotel_id = target_hotel
    and rm.room_number like room_prefix || '%';

  if temporary_rate_plan_created and temporary_rate_plan_id is not null then
    delete from public.rate_plans rp
    where rp.hotel_id = target_hotel
      and rp.id = temporary_rate_plan_id
      and rp.code like 'D5QA-%';
  end if;

  if sequence_existed then
    update public.reservation_number_sequences s
    set last_number = sequence_before
    where s.hotel_id = target_hotel
      and s.sequence_year = test_sequence_year;
  else
    delete from public.reservation_number_sequences s
    where s.hotel_id = target_hotel
      and s.sequence_year = test_sequence_year;
  end if;

  delete from private.day5_browser_acceptance_state_20260724
  where singleton = true;
end
$$;

select jsonb_pretty(
  jsonb_build_object(
    'expected_result', 'All values must be 0.',
    'remaining_acceptance_reservations', (
      select count(*) from public.reservations r
      where r.source_reference like 'DAY5-ACCEPT-%'
    ),
    'remaining_acceptance_rooms', (
      select count(*) from public.rooms rm
      where rm.room_number like 'D5QA-%'
    ),
    'remaining_acceptance_guests', (
      select count(*) from public.guests g
      where lower(coalesce(g.email, '')) like 'day5-%@stayqr.invalid'
    ),
    'remaining_acceptance_sessions', (
      select count(*) from public.guest_sessions gs
      join public.guests g on g.id = gs.guest_id and g.hotel_id = gs.hotel_id
      where lower(coalesce(g.email, '')) like 'day5-%@stayqr.invalid'
    ),
    'remaining_acceptance_rate_plans', (
      select count(*) from public.rate_plans rp
      where rp.code like 'D5QA-%'
        and rp.description = 'Temporary positive rate used only by the controlled Day 5 browser acceptance dataset.'
    ),
    'remaining_acceptance_state_rows', (
      select count(*) from private.day5_browser_acceptance_state_20260724
    )
  )
) as stayqr_day5_browser_acceptance_cleanup;
