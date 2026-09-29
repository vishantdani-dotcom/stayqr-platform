-- StayQR Migration 124 non-destructive acceptance checks.
select jsonb_build_object(
  'event_table_exists', to_regclass('public.guest_session_room_charge_events') is not null,
  'rpc_exists', to_regprocedure('public.reconcile_active_stay_room_charge(uuid,uuid,jsonb)') is not null,
  'rpc_security_definer', coalesce((select prosecdef from pg_proc where oid = to_regprocedure('public.reconcile_active_stay_room_charge(uuid,uuid,jsonb)')), false),
  'payments_folio_sync_trigger_exists', exists (
    select 1
    from pg_trigger
    where tgrelid = 'public.payments'::regclass
      and tgname = 'payments_day11_folio_sync'
      and not tgisinternal
  ),
  'event_rls_enabled', coalesce((select relrowsecurity from pg_class where oid = 'public.guest_session_room_charge_events'::regclass), false),
  'invoice_guard_present', position('invoice already exists' in lower(pg_get_functiondef(to_regprocedure('public.reconcile_active_stay_room_charge(uuid,uuid,jsonb)')))) > 0,
  'stale_amount_guard_present', position('changed after checkout was opened' in lower(pg_get_functiondef(to_regprocedure('public.reconcile_active_stay_room_charge(uuid,uuid,jsonb)')))) > 0,
  'activity_log_present', position('checkout.room_charge_reconciled' in pg_get_functiondef(to_regprocedure('public.reconcile_active_stay_room_charge(uuid,uuid,jsonb)'))) > 0
) as migration_124_acceptance;
