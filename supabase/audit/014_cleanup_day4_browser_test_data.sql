-- ============================================================================
-- StayQR Day 4 — Browser Runtime Test Data Cleanup (Corrected / Idempotent)
-- File: 014_cleanup_day4_browser_test_data.sql
--
-- Removes ONLY the exact Day 4 assignment / movement test reservation and its
-- dedicated test guest. Safe to rerun: if the target is already absent, the
-- script performs no deletion and returns an all-zero verification report.
-- ============================================================================

begin;

set local lock_timeout = '10s';
set local statement_timeout = '120s';

select pg_advisory_xact_lock(
  hashtext('stayqr:day4_browser_runtime_test_cleanup')
);

create temporary table stayqr_day4_cleanup_target
on commit drop
as
select
  reservation.id as reservation_id,
  reservation.hotel_id,
  reservation.primary_guest_id,
  reservation.reservation_number,
  reservation.source_reference
from public.reservations reservation
join public.hotels hotel
  on hotel.id = reservation.hotel_id
where reservation.source_reference = 'DAY4-BROWSER-UNALLOCATED'
  and hotel.hotel_name = 'Hotel Apex Stay Inn';

do $$
declare
  target_count integer;
  verified_guest_count integer;
begin
  select count(*)
  into target_count
  from stayqr_day4_cleanup_target;

  if target_count > 1 then
    raise exception
      'Cleanup stopped: expected at most 1 Day 4 browser-test reservation, found %.',
      target_count;
  end if;

  if target_count = 1 then
    select count(*)
    into verified_guest_count
    from public.guests guest
    join stayqr_day4_cleanup_target target
      on target.primary_guest_id = guest.id
     and target.hotel_id = guest.hotel_id
    where guest.full_name = 'StayQR Day 4 Assignment Test'
      and guest.phone = '9000000404'
      and lower(coalesce(guest.email, '')) =
        'day4-assignment-test@stayqr.invalid';

    if verified_guest_count <> 1 then
      raise exception
        'Cleanup stopped: the exact Day 4 test guest could not be verified.';
    end if;
  end if;
end
$$;

-- Generic activity logs do not have an FK to reservations.
delete from public.activity_logs activity
using stayqr_day4_cleanup_target target
where activity.hotel_id = target.hotel_id
  and activity.entity_type = 'reservation'
  and activity.entity_id = target.reservation_id;

-- Cascades remove reservation rooms, guest links, status history, deposits and
-- active inventory allocations.
delete from public.reservations reservation
using stayqr_day4_cleanup_target target
where reservation.id = target.reservation_id
  and reservation.hotel_id = target.hotel_id;

-- Remove only the dedicated test guest when no record still references it.
delete from public.guests guest
using stayqr_day4_cleanup_target target
where guest.id = target.primary_guest_id
  and guest.hotel_id = target.hotel_id
  and guest.full_name = 'StayQR Day 4 Assignment Test'
  and guest.phone = '9000000404'
  and lower(coalesce(guest.email, '')) =
    'day4-assignment-test@stayqr.invalid'
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

commit;

select jsonb_pretty(
  jsonb_build_object(
    'expected_result', 'All four values must be 0.',
    'remaining_test_reservations', (
      select count(*)
      from public.reservations
      where source_reference = 'DAY4-BROWSER-UNALLOCATED'
    ),
    'remaining_test_guests', (
      select count(*)
      from public.guests
      where full_name = 'StayQR Day 4 Assignment Test'
        and phone = '9000000404'
        and lower(coalesce(email, '')) =
          'day4-assignment-test@stayqr.invalid'
    ),
    'remaining_test_reservation_rooms', (
      select count(*)
      from public.reservation_rooms reservation_room
      join public.reservations reservation
        on reservation.id = reservation_room.reservation_id
       and reservation.hotel_id = reservation_room.hotel_id
      where reservation.source_reference = 'DAY4-BROWSER-UNALLOCATED'
    ),
    'remaining_test_inventory_allocations', (
      select count(*)
      from public.room_inventory_allocations allocation
      join public.reservation_rooms reservation_room
        on reservation_room.id = allocation.reservation_room_id
       and reservation_room.hotel_id = allocation.hotel_id
      join public.reservations reservation
        on reservation.id = reservation_room.reservation_id
       and reservation.hotel_id = reservation_room.hotel_id
      where reservation.source_reference = 'DAY4-BROWSER-UNALLOCATED'
    )
  )
) as stayqr_day4_browser_test_cleanup_result;
