-- ============================================================================
-- StayQR Day 3 — Browser Runtime Test Data Cleanup
-- File: 010_cleanup_day3_browser_test_data.sql
--
-- Removes ONLY the exact Day 3 browser-test records:
--   Reservation RES-2026-000001 / source DAY3-UI-EDIT-TEST
--   Reservation RES-2026-000002 / source DAY3-UI-WALKIN-NOSHOW
--   Test guest StayQR UI Test Guest / 9000000011
--
-- SAFETY
-- - Run the COMPLETE file once using role postgres.
-- - The transaction aborts unless exactly the two expected reservations exist.
-- - Foreign keys protect the guest from deletion if any unrelated record uses it.
-- - No real hotel, room, rate-plan or operational record is modified.
-- ============================================================================

begin;

set local lock_timeout = '10s';
set local statement_timeout = '120s';

select pg_advisory_xact_lock(
  hashtext('stayqr:day3_browser_runtime_test_cleanup')
);

create temporary table stayqr_day3_cleanup_targets
on commit drop
as
select
  r.id as reservation_id,
  r.hotel_id,
  r.primary_guest_id,
  r.reservation_number,
  r.source_reference
from public.reservations r
where (
    r.reservation_number = 'RES-2026-000001'
    and r.source_reference = 'DAY3-UI-EDIT-TEST'
  )
  or (
    r.reservation_number = 'RES-2026-000002'
    and r.source_reference = 'DAY3-UI-WALKIN-NOSHOW'
  );

do $$
declare
  target_count integer;
  target_hotel_count integer;
  target_guest_count integer;
begin
  select count(*)
  into target_count
  from stayqr_day3_cleanup_targets;

  if target_count <> 2 then
    raise exception
      'Cleanup stopped: expected exactly 2 Day 3 browser-test reservations, found %.',
      target_count;
  end if;

  select count(distinct hotel_id)
  into target_hotel_count
  from stayqr_day3_cleanup_targets;

  if target_hotel_count <> 1 then
    raise exception
      'Cleanup stopped: the two test reservations do not belong to one hotel.';
  end if;

  select count(distinct primary_guest_id)
  into target_guest_count
  from stayqr_day3_cleanup_targets;

  if target_guest_count <> 1 then
    raise exception
      'Cleanup stopped: expected both reservations to use one test guest.';
  end if;

  if not exists (
    select 1
    from public.guests g
    join stayqr_day3_cleanup_targets target
      on target.primary_guest_id = g.id
     and target.hotel_id = g.hotel_id
    where g.full_name = 'StayQR UI Test Guest'
      and g.phone = '9000000011'
      and lower(coalesce(g.email, '')) =
        'stayqr-ui-test@stayqr.invalid'
  ) then
    raise exception
      'Cleanup stopped: the exact Day 3 test guest could not be verified.';
  end if;
end
$$;

-- Generic activity logs do not have a reservation foreign key, so remove them
-- before deleting the Reservation records.
delete from public.activity_logs log
using stayqr_day3_cleanup_targets target
where log.hotel_id = target.hotel_id
  and log.entity_type = 'reservation'
  and log.entity_id = target.reservation_id;

-- Cascades remove reservation rooms, reservation guests, status history,
-- deposits and room-inventory allocations.
delete from public.reservations reservation
using stayqr_day3_cleanup_targets target
where reservation.id = target.reservation_id
  and reservation.hotel_id = target.hotel_id;

-- Delete only the exact test guest, and only if no remaining record uses it.
delete from public.guests guest
using (
  select distinct
    target.hotel_id,
    target.primary_guest_id
  from stayqr_day3_cleanup_targets target
) test_guest
where guest.id = test_guest.primary_guest_id
  and guest.hotel_id = test_guest.hotel_id
  and guest.full_name = 'StayQR UI Test Guest'
  and guest.phone = '9000000011'
  and lower(coalesce(guest.email, '')) =
    'stayqr-ui-test@stayqr.invalid'
  and not exists (
    select 1
    from public.reservations remaining
    where remaining.hotel_id = guest.hotel_id
      and remaining.primary_guest_id = guest.id
  )
  and not exists (
    select 1
    from public.reservation_guests remaining_link
    where remaining_link.hotel_id = guest.hotel_id
      and remaining_link.guest_id = guest.id
  )
  and not exists (
    select 1
    from public.guest_sessions remaining_stay
    where remaining_stay.hotel_id = guest.hotel_id
      and remaining_stay.guest_id = guest.id
  );

-- Verification 008 proved there were no Reservation records before browser
-- testing. Remove the 2026 sequence row only when no 2026 Reservation remains.
delete from public.reservation_number_sequences sequence
using (
  select distinct target.hotel_id
  from stayqr_day3_cleanup_targets target
) target_hotel
where sequence.hotel_id = target_hotel.hotel_id
  and sequence.sequence_year = 2026
  and not exists (
    select 1
    from public.reservations remaining
    where remaining.hotel_id = target_hotel.hotel_id
      and remaining.reservation_number like 'RES-2026-%'
  );

commit;

-- Expected result: one blank pg_advisory_xact_lock row and no error.
