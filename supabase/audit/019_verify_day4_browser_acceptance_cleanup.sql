-- ============================================================================
-- StayQR Day 4 — Read-only Browser Acceptance Cleanup Verification
-- Expected: every value is 0.
-- ============================================================================

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
) as stayqr_day4_browser_acceptance_cleanup_verification;
