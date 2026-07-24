-- ============================================================================
-- StayQR Day 5 — Read-only Browser Acceptance Cleanup Verification
-- Expected: every value is 0.
-- ============================================================================

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
    'remaining_acceptance_checkin_events', (
      select count(*) from public.reservation_checkin_events e
      join public.reservations r on r.id = e.reservation_id and r.hotel_id = e.hotel_id
      where r.source_reference like 'DAY5-ACCEPT-%'
    ),
    'remaining_acceptance_transfers', (
      select count(*) from public.reservation_payment_transfers t
      join public.reservations r on r.id = t.reservation_id and r.hotel_id = t.hotel_id
      where r.source_reference like 'DAY5-ACCEPT-%'
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
) as stayqr_day5_browser_acceptance_cleanup_verification;
