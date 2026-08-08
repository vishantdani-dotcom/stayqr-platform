-- ============================================================================
-- StayQR v1.0
-- Day 19 Audit 074 REV2 FINAL
-- Gate 19B Current-State Regression (Fixture-Independent Final Gate)
-- Date: 2026-08-09
--
-- PURPOSE
-- Finalize Gate 19B after ACL canonicalization. This REV2 keeps the full
-- current-state regression coverage, adds the Day 19 business-day-settings
-- invariant, and replaces the obsolete exact Day 18 index COUNT assertion with
-- canonical-index-set + validity/readiness checks.
-- The audit replays authoritative migration acceptance helpers for Days 15-18,
-- adds the final Day 17 execution-boundary checks, validates the Day 18
-- monitoring boundary without creating persistent fixtures, and confirms the
-- guest signing-key invariant restored by Migration 063.
--
-- IMPORTANT
-- - No historical Day 15 food/service browser fixture is required.
-- - Migration 057's own acceptance helper uses its built-in reversible fixture
--   and rolls it back before returning.
-- - This file creates only a TEMP result table and leaves no persistent audit
--   object behind.
--
-- PASS CONDITION
-- failed_checks = 0.
-- ============================================================================

set statement_timeout = '300s';

drop table if exists pg_temp.day19_a074_results;

create temporary table day19_a074_results (
  source_gate text not null,
  suite text not null,
  test_name text not null,
  passed boolean not null,
  details text not null
) on commit preserve rows;


-- ============================================================================
-- 1. AUTHORITATIVE MIGRATION ACCEPTANCE HELPERS
-- ============================================================================

do $replay$
declare
  r record;
begin
  for r in
    select *
    from (
      values
        ('DAY15_M051', 'private.day15_migration_051_acceptance_rev1()'),
        ('DAY15_M052', 'private.day15_migration_052_acceptance_rev1()'),
        ('DAY15_M053', 'private.day15_migration_053_acceptance_rev1()'),
        ('DAY16_M055', 'private.day16_migration_055_acceptance_rev1()'),
        ('DAY17_M056', 'private.day17_migration_056_acceptance_rev2()'),
        ('DAY17_M057', 'private.day17_migration_057_acceptance_rev1()'),
        ('DAY18_M058', 'private.day18_migration_058_acceptance_rev1()')
    ) expected(source_gate, signature)
  loop
    if to_regprocedure(r.signature) is null then
      insert into pg_temp.day19_a074_results
      values (
        r.source_gate,
        'HARNESS',
        'acceptance_helper_present',
        false,
        'Missing ' || r.signature
      );
      continue;
    end if;

    begin
      execute format(
        'insert into pg_temp.day19_a074_results
           (source_gate, suite, test_name, passed, details)
         select %L, suite, test_name, passed, details
         from %s',
        r.source_gate,
        r.signature
      );
    exception
      when others then
        insert into pg_temp.day19_a074_results
        values (
          r.source_gate,
          'HARNESS',
          'acceptance_helper_execution',
          false,
          format('%s [%s]', sqlerrm, sqlstate)
        );
    end;
  end loop;
end;
$replay$;

-- ============================================================================
-- 1B. DAY 18 INDEX ACCEPTANCE — CURRENT-STATE SEMANTICS
-- ============================================================================
--
-- Migration 058 created 20 canonical idx_d18_* indexes. Later safe forward
-- work may add additional valid idx_d18_* indexes. Therefore exact COUNT = 20
-- is not a sound launch gate. The current-state gate requires:
--   1. all 20 canonical indexes still exist;
--   2. every idx_d18_* index is valid and ready.
--
-- The legacy helper row is transparently superseded only if both stronger
-- conditions pass.

do $day18_index_current_state$
declare
  v_actual integer;
  v_missing integer;
  v_invalid integer;
begin
  select count(*)
  into v_actual
  from pg_catalog.pg_indexes
  where schemaname = 'public'
    and indexname like 'idx_d18_%';

  with required(index_name) as (
    values
      ('idx_d18_reservations_cursor'),
      ('idx_d18_reservations_status_cursor'),
      ('idx_d18_reservations_source_cursor'),
      ('idx_d18_guests_updated_cursor'),
      ('idx_d18_guests_name_prefix'),
      ('idx_d18_guests_phone_prefix'),
      ('idx_d18_guests_email_prefix'),
      ('idx_d18_guest_sessions_cursor'),
      ('idx_d18_guest_sessions_status_cursor'),
      ('idx_d18_service_requests_status_cursor'),
      ('idx_d18_service_requests_department_cursor'),
      ('idx_d18_food_orders_status_cursor'),
      ('idx_d18_activity_logs_cursor'),
      ('idx_d18_activity_logs_entity_cursor'),
      ('idx_d18_notification_deliveries_status_cursor'),
      ('idx_d18_folios_status_cursor'),
      ('idx_d18_invoices_cursor'),
      ('idx_d18_payments_cursor'),
      ('idx_d18_housekeeping_status_cursor'),
      ('idx_d18_maintenance_status_cursor')
  )
  select count(*)
  into v_missing
  from required r
  where not exists (
    select 1
    from pg_catalog.pg_indexes i
    where i.schemaname = 'public'
      and i.indexname = r.index_name
  );

  select count(*)
  into v_invalid
  from pg_catalog.pg_index i
  join pg_catalog.pg_class c
    on c.oid = i.indexrelid
  join pg_catalog.pg_namespace n
    on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname like 'idx_d18_%'
    and (not i.indisvalid or not i.indisready);

  update pg_temp.day19_a074_results
  set
    test_name = 'day18_required_index_set_20',
    passed = (v_missing = 0 and v_invalid = 0),
    details = format(
      'canonical_required=20 actual_idx_d18=%s required_missing=%s invalid_or_not_ready=%s; exact-count assertion superseded by set+health validation',
      v_actual,
      v_missing,
      v_invalid
    )
  where source_gate = 'DAY18_M058'
    and suite = 'INDEX_HEALTH'
    and test_name = 'day18_index_count_20';

  insert into pg_temp.day19_a074_results
  values (
    'DAY18_M058',
    'INDEX_HEALTH',
    'all_idx_d18_indexes_valid_and_ready',
    v_invalid = 0,
    format('actual_idx_d18=%s invalid_or_not_ready=%s', v_actual, v_invalid)
  );
end;
$day18_index_current_state$;


-- ============================================================================
-- 1C. DAY 19 MIGRATION 066 — BUSINESS-DAY SETTINGS INVARIANT
-- ============================================================================

insert into pg_temp.day19_a074_results
select
  'DAY19_M066',
  'HOTEL_INVARIANT',
  'every_hotel_has_business_day_settings',
  count(*) = 0,
  format('%s hotel(s) missing business-day settings.', count(*))
from public.hotels h
where not exists (
  select 1
  from public.business_day_settings bds
  where bds.hotel_id = h.id
);

insert into pg_temp.day19_a074_results
select
  'DAY19_M066',
  'HOTEL_INVARIANT',
  'future_hotel_trigger_present',
  exists (
    select 1
    from pg_catalog.pg_trigger t
    join pg_catalog.pg_class c
      on c.oid = t.tgrelid
    join pg_catalog.pg_namespace n
      on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'hotels'
      and t.tgname = 'day19_ensure_business_day_settings_after_hotel_insert'
      and not t.tgisinternal
  ),
  'Future hotel inserts automatically receive business-day settings.';

insert into pg_temp.day19_a074_results
select
  'DAY19_M066',
  'HOTEL_INVARIANT',
  'trigger_function_api_closed',
  to_regprocedure(
    'private.day19_ensure_business_day_settings_for_hotel()'
  ) is not null
    and not has_function_privilege(
      'anon',
      'private.day19_ensure_business_day_settings_for_hotel()',
      'EXECUTE'
    )
    and not has_function_privilege(
      'authenticated',
      'private.day19_ensure_business_day_settings_for_hotel()',
      'EXECUTE'
    ),
  'Business-day trigger helper is private to API roles.';


-- ============================================================================
-- 2. DAY 17 FINAL EXECUTION BOUNDARIES
-- ============================================================================

insert into pg_temp.day19_a074_results
values
  (
    'DAY17_FINAL',
    'PRIVILEGE',
    'management_helper_authenticated_execute',
    has_function_privilege(
      'authenticated',
      'private.day17_can_manage_hotel(uuid)',
      'EXECUTE'
    ),
    'Authenticated users can evaluate management RLS.'
  ),
  (
    'DAY17_FINAL',
    'PRIVILEGE',
    'management_helper_anon_blocked',
    not has_function_privilege(
      'anon',
      'private.day17_can_manage_hotel(uuid)',
      'EXECUTE'
    ),
    'Anonymous management-helper execution is denied.'
  ),
  (
    'DAY17_FINAL',
    'PRIVILEGE',
    'notification_inbox_authenticated_execute',
    has_function_privilege(
      'authenticated',
      'public.get_notification_inbox(uuid,integer,timestamptz)',
      'EXECUTE'
    ),
    'Authenticated inbox execution is granted.'
  ),
  (
    'DAY17_FINAL',
    'PRIVILEGE',
    'notification_inbox_anon_blocked',
    not has_function_privilege(
      'anon',
      'public.get_notification_inbox(uuid,integer,timestamptz)',
      'EXECUTE'
    ),
    'Anonymous inbox execution is denied.'
  ),
  (
    'DAY17_FINAL',
    'PRIVILEGE',
    'settings_update_authenticated_execute',
    has_function_privilege(
      'authenticated',
      'public.update_hotel_system_settings(uuid,jsonb)',
      'EXECUTE'
    ),
    'Authenticated settings update execution is granted.'
  ),
  (
    'DAY17_FINAL',
    'PRIVILEGE',
    'settings_update_anon_blocked',
    not has_function_privilege(
      'anon',
      'public.update_hotel_system_settings(uuid,jsonb)',
      'EXECUTE'
    ),
    'Anonymous settings update execution is denied.'
  ),
  (
    'DAY17_FINAL',
    'PRIVILEGE',
    'email_writer_authenticated_execute',
    has_function_privilege(
      'authenticated',
      'public.upsert_email_adapter_config(uuid,jsonb)',
      'EXECUTE'
    ),
    'Authenticated email-adapter writes use the trusted RPC.'
  ),
  (
    'DAY17_FINAL',
    'PRIVILEGE',
    'email_writer_anon_blocked',
    not has_function_privilege(
      'anon',
      'public.upsert_email_adapter_config(uuid,jsonb)',
      'EXECUTE'
    ),
    'Anonymous email-adapter writes are denied.'
  ),
  (
    'DAY17_FINAL',
    'PRIVILEGE',
    'whatsapp_writer_authenticated_execute',
    has_function_privilege(
      'authenticated',
      'public.upsert_manual_whatsapp_template(uuid,jsonb)',
      'EXECUTE'
    ),
    'Authenticated WhatsApp-template writes use the trusted RPC.'
  ),
  (
    'DAY17_FINAL',
    'PRIVILEGE',
    'whatsapp_writer_anon_blocked',
    not has_function_privilege(
      'anon',
      'public.upsert_manual_whatsapp_template(uuid,jsonb)',
      'EXECUTE'
    ),
    'Anonymous WhatsApp-template writes are denied.'
  );


-- ============================================================================
-- 3. DAY 18 MONITORING STATIC SECURITY CONTRACT
-- ============================================================================

insert into pg_temp.day19_a074_results
select
  'DAY18_M059',
  'TABLE_SECURITY',
  'rls_enabled',
  c.relrowsecurity,
  format('relrowsecurity=%s', c.relrowsecurity)
from pg_catalog.pg_class c
where c.oid = 'public.operational_error_events'::regclass;

insert into pg_temp.day19_a074_results
select
  'DAY18_M059',
  'TABLE_SECURITY',
  'rls_forced',
  c.relforcerowsecurity,
  format('relforcerowsecurity=%s', c.relforcerowsecurity)
from pg_catalog.pg_class c
where c.oid = 'public.operational_error_events'::regclass;

insert into pg_temp.day19_a074_results
values
  (
    'DAY18_M059',
    'TABLE_SECURITY',
    'anon_access_blocked',
    not (
      has_table_privilege(
        'anon',
        'public.operational_error_events',
        'SELECT'
      )
      or has_table_privilege(
        'anon',
        'public.operational_error_events',
        'INSERT'
      )
      or has_table_privilege(
        'anon',
        'public.operational_error_events',
        'UPDATE'
      )
      or has_table_privilege(
        'anon',
        'public.operational_error_events',
        'DELETE'
      )
    ),
    'Anonymous direct monitoring-table access is denied.'
  ),
  (
    'DAY18_M059',
    'TABLE_SECURITY',
    'authenticated_access_blocked',
    not (
      has_table_privilege(
        'authenticated',
        'public.operational_error_events',
        'SELECT'
      )
      or has_table_privilege(
        'authenticated',
        'public.operational_error_events',
        'INSERT'
      )
      or has_table_privilege(
        'authenticated',
        'public.operational_error_events',
        'UPDATE'
      )
      or has_table_privilege(
        'authenticated',
        'public.operational_error_events',
        'DELETE'
      )
    ),
    'Authenticated direct monitoring-table access is denied.'
  );

do $m059_functions$
declare
  v_signature text;
begin
  foreach v_signature in array array[
    'private.day18_safe_log_text(text,integer)',
    'private.day18_safe_log_context(jsonb)'
  ]
  loop
    insert into pg_temp.day19_a074_results
    values (
      'DAY18_M059',
      'HELPER_SECURITY',
      v_signature,
      to_regprocedure(v_signature) is not null
        and not has_function_privilege('anon', v_signature, 'EXECUTE')
        and not has_function_privilege('authenticated', v_signature, 'EXECUTE'),
      'Private sanitizer exists and is closed to API roles.'
    );
  end loop;

  foreach v_signature in array array[
    'public.report_operational_error(uuid,jsonb)',
    'public.get_operational_health_snapshot(uuid)',
    'public.get_operational_diagnostics(uuid,timestamptz,timestamptz,integer,text,text,text,text)',
    'public.set_operational_incident_status(uuid,uuid,text,text)'
  ]
  loop
    insert into pg_temp.day19_a074_results
    values (
      'DAY18_M059',
      'RPC_SECURITY',
      v_signature,
      to_regprocedure(v_signature) is not null
        and has_function_privilege('authenticated', v_signature, 'EXECUTE')
        and not has_function_privilege('anon', v_signature, 'EXECUTE'),
      'Trusted monitoring RPC is authenticated-only.'
    );
  end loop;
end;
$m059_functions$;

insert into pg_temp.day19_a074_results
values (
  'DAY18_M059',
  'SERVICE_ROLE',
  'report_operational_error',
  has_function_privilege(
    'service_role',
    'public.report_operational_error(uuid,jsonb)',
    'EXECUTE'
  ),
  'Backend service role can write through the trusted monitoring RPC.'
);


-- ============================================================================
-- 4. DAY 7/19 SIGNING-KEY REPRODUCIBILITY INVARIANT
-- ============================================================================

insert into pg_temp.day19_a074_results
select
  'DAY19_M063',
  'SIGNING_KEY',
  'exactly_one_active_32_byte_key',
  count(*) = 1
    and min(octet_length(secret)) = 32
    and max(octet_length(secret)) = 32
    and count(*) filter (where retired_at is not null) = 0,
  format(
    'active=%s min_bytes=%s max_bytes=%s retired_active=%s',
    count(*),
    coalesce(min(octet_length(secret)), 0),
    coalesce(max(octet_length(secret)), 0),
    count(*) filter (where retired_at is not null)
  )
from private.guest_access_signing_keys
where status = 'active';


-- ============================================================================
-- 4B. DAY 18 EXTRA INDEX INVENTORY - INFORMATIONAL
-- ============================================================================
--
-- Extra valid idx_d18_* indexes are not a correctness failure. They are printed
-- so the final evidence still shows exactly what exists beyond the canonical 20.

with required(index_name) as (
  values
    ('idx_d18_reservations_cursor'),
    ('idx_d18_reservations_status_cursor'),
    ('idx_d18_reservations_source_cursor'),
    ('idx_d18_guests_updated_cursor'),
    ('idx_d18_guests_name_prefix'),
    ('idx_d18_guests_phone_prefix'),
    ('idx_d18_guests_email_prefix'),
    ('idx_d18_guest_sessions_cursor'),
    ('idx_d18_guest_sessions_status_cursor'),
    ('idx_d18_service_requests_status_cursor'),
    ('idx_d18_service_requests_department_cursor'),
    ('idx_d18_food_orders_status_cursor'),
    ('idx_d18_activity_logs_cursor'),
    ('idx_d18_activity_logs_entity_cursor'),
    ('idx_d18_notification_deliveries_status_cursor'),
    ('idx_d18_folios_status_cursor'),
    ('idx_d18_invoices_cursor'),
    ('idx_d18_payments_cursor'),
    ('idx_d18_housekeeping_status_cursor'),
    ('idx_d18_maintenance_status_cursor')
)
select
  i.indexname as extra_valid_idx_d18_index,
  i.indexdef
from pg_catalog.pg_indexes i
where i.schemaname = 'public'
  and i.indexname like 'idx_d18_%'
  and not exists (
    select 1
    from required r
    where r.index_name = i.indexname
  )
order by i.indexname;


-- ============================================================================
-- 5. OUTPUT
-- ============================================================================

-- Failure-only view first. An empty result is ideal.
select
  source_gate,
  suite,
  test_name,
  passed,
  details
from pg_temp.day19_a074_results
where not passed
order by source_gate, suite, test_name;

-- Grouped summary.
select
  source_gate,
  count(*) as total_checks,
  count(*) filter (where passed) as passed_checks,
  count(*) filter (where not passed) as failed_checks
from pg_temp.day19_a074_results
group by source_gate
order by source_gate;

-- Final gate summary.
select
  count(*) as total_checks,
  count(*) filter (where passed) as passed_checks,
  count(*) filter (where not passed) as failed_checks
from pg_temp.day19_a074_results;

do $gate$
declare
  v_failed integer;
begin
  select count(*)
  into v_failed
  from pg_temp.day19_a074_results
  where not passed;

  if v_failed <> 0 then
    raise exception
      'Audit 074 REV2 failed: % current-state regression check(s) failed.',
      v_failed;
  end if;
end;
$gate$;

select
  '=== AUDIT 074 REV2 PASS - GATE 19B CURRENT-STATE REGRESSION ZERO FAILURES ==='::text
  as gate_result;

drop table if exists pg_temp.day19_a074_results;
