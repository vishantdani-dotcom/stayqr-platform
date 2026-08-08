-- ============================================================================
-- StayQR v1.0
-- Day 19 Audit 076 REV1
-- Post-Commit ACL Canonicalization Acceptance
-- Date: 2026-08-09
--
-- PERSISTENT-DATA READ-ONLY.
-- Uses a session-local temporary results table for assertions, so the
-- transaction itself is intentionally not declared READ ONLY.
-- Verifies the exact browser/API ACL matrix repaired by Migration 065.
-- Does not depend on historical runtime fixtures and does not mutate
-- persistent StayQR business/schema objects.
-- ============================================================================

\pset pager off

begin;

drop table if exists pg_temp.day19_a076_results;

create temporary table day19_a076_results (
  area text not null,
  test_name text not null,
  passed boolean not null,
  details text not null
) on commit preserve rows;

-- --------------------------------------------------------------------------
-- 1. Role inheritance and default ACL recurrence
-- --------------------------------------------------------------------------

insert into pg_temp.day19_a076_results
values
  (
    'ROLE',
    'anon_not_service_role',
    not pg_has_role('anon','service_role','MEMBER'),
    'anon must not inherit service_role'
  ),
  (
    'ROLE',
    'authenticated_not_service_role',
    not pg_has_role('authenticated','service_role','MEMBER'),
    'authenticated must not inherit service_role'
  ),
  (
    'ROLE',
    'anon_not_pg_write_all_data',
    not pg_has_role('anon','pg_write_all_data','MEMBER'),
    'anon must not inherit pg_write_all_data'
  ),
  (
    'ROLE',
    'authenticated_not_pg_write_all_data',
    not pg_has_role('authenticated','pg_write_all_data','MEMBER'),
    'authenticated must not inherit pg_write_all_data'
  );

insert into pg_temp.day19_a076_results
select
  'DEFAULT_ACL',
  'postgres_public_schema_browser_defaults_closed',
  count(*) = 0,
  format('unsafe_default_acl_entries=%s', count(*))
from pg_catalog.pg_default_acl d
join pg_catalog.pg_namespace n
  on n.oid = d.defaclnamespace
cross join lateral pg_catalog.aclexplode(d.defaclacl) x
join pg_catalog.pg_roles grantee_role
  on grantee_role.oid = x.grantee
join pg_catalog.pg_roles owner_role
  on owner_role.oid = d.defaclrole
where n.nspname = 'public'
  and owner_role.rolname = 'postgres'
  and grantee_role.rolname in ('anon', 'authenticated');


-- --------------------------------------------------------------------------
-- 2. Day 15 table matrix
-- --------------------------------------------------------------------------

do $day15_tables$
declare
  v_name text;
begin
  foreach v_name in array array[
    'menu_item_modifier_groups',
    'menu_item_modifiers'
  ]
  loop
    insert into pg_temp.day19_a076_results
    values (
      'DAY15_TABLE',
      v_name || '.authenticated_crud_anon_closed',
      has_table_privilege('authenticated', 'public.' || v_name, 'SELECT')
        and has_table_privilege('authenticated', 'public.' || v_name, 'INSERT')
        and has_table_privilege('authenticated', 'public.' || v_name, 'UPDATE')
        and has_table_privilege('authenticated', 'public.' || v_name, 'DELETE')
        and not has_table_privilege('anon', 'public.' || v_name, 'SELECT')
        and not has_table_privilege('anon', 'public.' || v_name, 'INSERT')
        and not has_table_privilege('anon', 'public.' || v_name, 'UPDATE')
        and not has_table_privilege('anon', 'public.' || v_name, 'DELETE'),
      'Authenticated modifier CRUD retained; anon access denied.'
    );
  end loop;

  foreach v_name in array array[
    'food_orders',
    'food_order_items',
    'food_order_item_modifiers',
    'food_order_events',
    'kitchen_tickets',
    'service_requests',
    'service_request_events',
    'guest_notifications',
    'service_escalations'
  ]
  loop
    insert into pg_temp.day19_a076_results
    values (
      'DAY15_TABLE',
      v_name || '.authenticated_read_only_anon_closed',
      has_table_privilege('authenticated', 'public.' || v_name, 'SELECT')
        and not has_table_privilege('authenticated', 'public.' || v_name, 'INSERT')
        and not has_table_privilege('authenticated', 'public.' || v_name, 'UPDATE')
        and not has_table_privilege('authenticated', 'public.' || v_name, 'DELETE')
        and not has_table_privilege('anon', 'public.' || v_name, 'SELECT')
        and not has_table_privilege('anon', 'public.' || v_name, 'INSERT')
        and not has_table_privilege('anon', 'public.' || v_name, 'UPDATE')
        and not has_table_privilege('anon', 'public.' || v_name, 'DELETE'),
      'Operational table is authenticated read-only and anon-closed.'
    );
  end loop;
end;
$day15_tables$;


-- --------------------------------------------------------------------------
-- 3. Function execution matrices
-- --------------------------------------------------------------------------

do $functions$
declare
  v_signature text;
begin
  foreach v_signature in array array[
    'public.get_guest_food_menu(text,text)',
    'public.place_guest_food_order(text,text,jsonb)',
    'public.get_guest_food_orders(text,text)',
    'public.cancel_guest_food_order(text,text,uuid,text)',
    'public.get_guest_service_catalog(text,text)',
    'public.create_guest_service_request(text,text,text)',
    'public.get_guest_service_requests(text,text)',
    'public.cancel_guest_service_request(text,text,uuid,text)',
    'public.get_guest_notifications(text,text)'
  ]
  loop
    insert into pg_temp.day19_a076_results
    values (
      'DAY15_GUEST_RPC',
      v_signature,
      has_function_privilege('anon', v_signature, 'EXECUTE')
        and has_function_privilege('authenticated', v_signature, 'EXECUTE'),
      'Signed guest RPC remains available to anon/authenticated token-bound callers.'
    );
  end loop;

  foreach v_signature in array array[
    'public.update_food_order_status(uuid,uuid,text,integer,text)',
    'public.post_food_order_to_folio(uuid,uuid)',
    'public.get_food_order_kot(uuid,uuid)',
    'public.get_food_operations_analytics(uuid,timestamptz,timestamptz)',
    'public.assign_service_request(uuid,uuid,uuid)',
    'public.update_service_request_priority(uuid,uuid,text)',
    'public.update_service_request_status(uuid,uuid,text,integer,text)',
    'public.escalate_overdue_service_requests(uuid)',
    'public.get_service_operations_analytics(uuid,timestamptz,timestamptz)',
    'public.save_menu_locale_translations(uuid,text,jsonb)',

    'public.get_report_filter_options(uuid)',
    'public.get_report_occupancy_daily(uuid,date,date)',
    'public.get_report_revenue_daily(uuid,date,date)',
    'public.get_report_revenue_by_category(uuid,date,date)',
    'public.get_report_reservations_by_source(uuid,date,date)',
    'public.get_report_arrivals_departures(uuid,date,date)',
    'public.get_report_payments_by_method(uuid,date,date)',
    'public.get_report_tax_gst_summary(uuid,date,date)',
    'public.get_report_guest_food_service(uuid,date,date)',
    'public.get_report_service_sla(uuid,date,date)',
    'public.get_report_housekeeping(uuid,date,date)',
    'public.get_report_staff_department(uuid,date,date)',
    'public.get_report_kpi_summary(uuid,date,date)',
    'public.get_report_export_rows(uuid,date,date,text,jsonb)',

    'public.get_notification_inbox(uuid,integer,timestamptz)',
    'public.mark_notification_read(uuid)',
    'public.mark_all_notifications_read(uuid)',
    'public.upsert_notification_preferences(uuid,jsonb)',
    'public.publish_notification_template(uuid,text,text,jsonb)',
    'public.enqueue_notification_event(uuid,text,uuid,jsonb)',
    'public.process_notification_outbox(integer)',
    'public.retry_notification_delivery(uuid)',
    'public.get_activity_timeline(uuid,timestamptz,timestamptz,jsonb)',
    'public.get_hotel_system_settings(uuid)',
    'public.update_hotel_system_settings(uuid,jsonb)',
    'public.get_support_workspace(uuid)',
    'public.get_active_announcements(uuid)',
    'public.upsert_email_adapter_config(uuid,jsonb)',
    'public.upsert_manual_whatsapp_template(uuid,jsonb)',

    'public.get_reservations_page(uuid,integer,text,text,text,text)',
    'public.get_guests_page(uuid,integer,text,text)',
    'public.get_guest_sessions_page(uuid,integer,text,text)',
    'public.get_service_requests_page(uuid,integer,text,text,text)',
    'public.get_food_orders_page(uuid,integer,text,text)',
    'public.get_activity_logs_page(uuid,integer,text,text,text)',
    'public.get_notification_deliveries_page(uuid,integer,text,text,text)',
    'public.get_folios_page(uuid,integer,text,text)',
    'public.get_day18_query_health(uuid)',

    'public.report_operational_error(uuid,jsonb)',
    'public.get_operational_health_snapshot(uuid)',
    'public.get_operational_diagnostics(uuid,timestamptz,timestamptz,integer,text,text,text,text)',
    'public.set_operational_incident_status(uuid,uuid,text,text)'
  ]
  loop
    insert into pg_temp.day19_a076_results
    values (
      'AUTH_ONLY_RPC',
      v_signature,
      has_function_privilege('authenticated', v_signature, 'EXECUTE')
        and not has_function_privilege('anon', v_signature, 'EXECUTE'),
      'Authenticated execution granted and anonymous execution denied.'
    );
  end loop;
end;
$functions$;


-- --------------------------------------------------------------------------
-- 4. Day 17 table matrix
-- --------------------------------------------------------------------------

do $day17_tables$
declare
  v_name text;
begin
  foreach v_name in array array[
    'notification_event_catalog',
    'notification_preferences',
    'notification_templates',
    'notification_template_versions',
    'notification_outbox',
    'notification_deliveries',
    'notification_delivery_attempts',
    'notification_dead_letters',
    'notification_recipients',
    'email_adapter_configs',
    'whatsapp_templates',
    'business_day_settings'
  ]
  loop
    insert into pg_temp.day19_a076_results
    values (
      'DAY17_TABLE',
      v_name || '.authenticated_read_only_anon_closed',
      has_table_privilege('authenticated', 'public.' || v_name, 'SELECT')
        and not has_table_privilege('authenticated', 'public.' || v_name, 'INSERT')
        and not has_table_privilege('authenticated', 'public.' || v_name, 'UPDATE')
        and not has_table_privilege('authenticated', 'public.' || v_name, 'DELETE')
        and not has_table_privilege('anon', 'public.' || v_name, 'SELECT')
        and not has_table_privilege('anon', 'public.' || v_name, 'INSERT')
        and not has_table_privilege('anon', 'public.' || v_name, 'UPDATE')
        and not has_table_privilege('anon', 'public.' || v_name, 'DELETE'),
      'Authenticated SELECT retained; anon access and authenticated writes denied.'
    );
  end loop;
end;
$day17_tables$;

insert into pg_temp.day19_a076_results
values (
  'DAY17_HELPER',
  'day17_can_manage_hotel',
  has_function_privilege(
    'authenticated',
    'private.day17_can_manage_hotel(uuid)',
    'EXECUTE'
  )
    and not has_function_privilege(
      'anon',
      'private.day17_can_manage_hotel(uuid)',
      'EXECUTE'
    ),
  'Authenticated RLS helper execution retained; anon denied.'
);


-- --------------------------------------------------------------------------
-- 5. Day 18 monitoring table + signing key
-- --------------------------------------------------------------------------

insert into pg_temp.day19_a076_results
values (
  'DAY18_TABLE',
  'operational_error_events.api_closed',
  not has_table_privilege('anon', 'public.operational_error_events', 'SELECT')
    and not has_table_privilege('anon', 'public.operational_error_events', 'INSERT')
    and not has_table_privilege('anon', 'public.operational_error_events', 'UPDATE')
    and not has_table_privilege('anon', 'public.operational_error_events', 'DELETE')
    and not has_table_privilege('authenticated', 'public.operational_error_events', 'SELECT')
    and not has_table_privilege('authenticated', 'public.operational_error_events', 'INSERT')
    and not has_table_privilege('authenticated', 'public.operational_error_events', 'UPDATE')
    and not has_table_privilege('authenticated', 'public.operational_error_events', 'DELETE'),
  'Monitoring table is RPC-only.'
);

insert into pg_temp.day19_a076_results
select
  'DAY19_SIGNING_KEY',
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


-- --------------------------------------------------------------------------
-- 6. Failure-only output + final gate
-- --------------------------------------------------------------------------

select
  area,
  test_name,
  passed,
  details
from pg_temp.day19_a076_results
where not passed
order by area, test_name;

select
  area,
  count(*) as total_checks,
  count(*) filter (where passed) as passed_checks,
  count(*) filter (where not passed) as failed_checks
from pg_temp.day19_a076_results
group by area
order by area;

select
  count(*) as total_checks,
  count(*) filter (where passed) as passed_checks,
  count(*) filter (where not passed) as failed_checks
from pg_temp.day19_a076_results;

do $gate$
declare
  v_failed integer;
begin
  select count(*)
  into v_failed
  from pg_temp.day19_a076_results
  where not passed;

  if v_failed <> 0 then
    raise exception
      'Audit 076 failed: % ACL canonicalization check(s) failed.',
      v_failed;
  end if;
end;
$gate$;

commit;

\echo
\echo '=== AUDIT 076 PASS - POST-COMMIT ACL CANONICALIZATION VERIFIED ==='
