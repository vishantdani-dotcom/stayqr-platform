-- StayQR Day 3 — Browser Runtime Test Cleanup Verification
-- READ-ONLY. Run after 010_cleanup_day3_browser_test_data.sql.

select jsonb_pretty(
  jsonb_build_object(
    'generated_at', now(),
    'remaining_test_reservations', (
      select count(*)
      from public.reservations r
      where r.reservation_number in (
        'RES-2026-000001',
        'RES-2026-000002'
      )
        or r.source_reference in (
          'DAY3-UI-EDIT-TEST',
          'DAY3-UI-WALKIN-NOSHOW'
        )
    ),
    'remaining_test_guest', (
      select count(*)
      from public.guests g
      where g.full_name = 'StayQR UI Test Guest'
        and g.phone = '9000000011'
        and lower(coalesce(g.email, '')) =
          'stayqr-ui-test@stayqr.invalid'
    ),
    'remaining_test_activity_logs', (
      select count(*)
      from public.activity_logs log
      where log.description ilike '%RES-2026-000001%'
         or log.description ilike '%RES-2026-000002%'
    ),
    'remaining_2026_sequence_without_reservations', (
      select count(*)
      from public.reservation_number_sequences sequence
      where sequence.sequence_year = 2026
        and not exists (
          select 1
          from public.reservations r
          where r.hotel_id = sequence.hotel_id
            and r.reservation_number like 'RES-2026-%'
        )
    ),
    'expected_result',
      'All four numeric values must be 0.'
  )
) as stayqr_day3_browser_test_cleanup_verification;
