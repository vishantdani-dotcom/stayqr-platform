-- ============================================================================
-- StayQR Day 4 — Read-only Browser-Test Cleanup Verification (Corrected)
-- File: 015_verify_day4_browser_test_cleanup.sql
-- Expected result: all four counts are 0.
-- ============================================================================

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
) as stayqr_day4_browser_test_cleanup_verification;
