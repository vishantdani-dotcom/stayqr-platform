-- StayQR Day 3 corrective migration verification
-- READ-ONLY.

select jsonb_pretty(
  jsonb_build_object(
    'generated_at', now(),
    'migration',
      '202607220004_reservation_deposit_delete_sync_fix',
    'recalculation_helper_exists',
      to_regprocedure(
        'private.recalculate_reservation_deposit_total(uuid,uuid)'
      ) is not null,
    'trigger_function_exists',
      to_regprocedure(
        'private.sync_reservation_deposit_total()'
      ) is not null,
    'deposit_trigger_exists', exists (
      select 1
      from information_schema.triggers
      where trigger_schema = 'public'
        and event_object_table = 'reservation_payments'
        and trigger_name = 'reservation_payments_sync_deposit'
    ),
    'reservation_count',
      (select count(*) from public.reservations),
    'reservation_payment_count',
      (select count(*) from public.reservation_payments)
  )
) as stayqr_day3_deposit_trigger_fix_verification;
