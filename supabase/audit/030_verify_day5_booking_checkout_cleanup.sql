-- ============================================================================
-- StayQR Day 5 — Verify booking-to-checkout smoke cleanup
-- Every remaining_* value must be 0.
-- ============================================================================

select jsonb_pretty(jsonb_build_object(
  'expected_result', 'All remaining values must be 0.',
  'remaining_state_rows', (
    select count(*) from private.day5_checkout_smoke_state_20260724
  ),
  'remaining_reservations', (
    select count(*) from public.reservations
    where source_reference = 'DAY5-CHECKOUT-SMOKE'
  ),
  'remaining_rooms', (
    select count(*) from public.rooms
    where room_number like 'D5CO-%'
  ),
  'remaining_guests', (
    select count(*) from public.guests
    where email = 'day5-checkout-smoke@stayqr.invalid'
       or phone = '9000050599'
  ),
  'remaining_sessions', (
    select count(*)
    from public.guest_sessions gs
    join public.guests g
      on g.hotel_id = gs.hotel_id
     and g.id = gs.guest_id
    where g.email = 'day5-checkout-smoke@stayqr.invalid'
  ),
  'remaining_invoices', (
    select count(*)
    from public.invoices inv
    join public.guests g
      on g.hotel_id = inv.hotel_id
     and g.id = inv.guest_id
    where g.email = 'day5-checkout-smoke@stayqr.invalid'
  ),
  'remaining_checkout_events', (
    select count(*)
    from public.reservation_checkout_events event
    join public.guests g
      on g.hotel_id = event.hotel_id
     and g.id = event.guest_id
    where g.email = 'day5-checkout-smoke@stayqr.invalid'
  ),
  'remaining_housekeeping_tasks', (
    select count(*) from public.housekeeping_tasks
    where room_number like 'D5CO-%'
  ),
  'remaining_temporary_rate_plans', (
    select count(*) from public.rate_plans
    where code like 'D5CO-%'
  )
)) as stayqr_day5_checkout_smoke_cleanup_verification;
