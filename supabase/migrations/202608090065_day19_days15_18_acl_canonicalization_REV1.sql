-- ============================================================================
-- StayQR v1.0
-- Day 19 Migration 065 REV1
-- Days 15-18 ACL Canonicalization + Default-Privilege Re-Hardening
-- Date: 2026-08-09
--
-- PURPOSE
-- Canonicalize the effective browser/API privilege boundary for Days 15-18
-- after the Day 19 diagnostic proved that anon/authenticated have direct ACL
-- grants on tables and RPCs that should be restricted.
--
-- WHY THIS EXISTS
-- Migration 064 was intended to restore these boundaries, but the post-run
-- diagnostic showed the effective database state still contained direct grants.
-- This migration deliberately uses stronger "REVOKE ALL PRIVILEGES" resets on
-- the affected browser roles, then re-grants only the accepted privileges.
--
-- SAFETY
-- - ACL-only and idempotent.
-- - No hotel/business rows are inserted, updated, or deleted.
-- - Existing service_role privileges are left untouched.
-- - Day 18 default privileges are re-hardened to prevent recurrence.
-- - Verification runs before COMMIT and a separate post-COMMIT audit is used.
-- ============================================================================

begin;

set local lock_timeout = '10s';
set local statement_timeout = '180s';

select pg_advisory_xact_lock(
  hashtext('stayqr:202608090065:days15-18-acl-canonicalization-rev1')
);

-- ============================================================================
-- 1. PRECHECK
-- ============================================================================

do $preflight$
declare
  v_name text;
  v_signature text;
begin
  if pg_has_role('anon', 'service_role', 'MEMBER')
     or pg_has_role('authenticated', 'service_role', 'MEMBER')
     or pg_has_role('anon', 'pg_write_all_data', 'MEMBER')
     or pg_has_role('authenticated', 'pg_write_all_data', 'MEMBER')
  then
    raise exception
      'Migration 065 stopped: unsafe API-role inheritance detected.';
  end if;

  foreach v_name in array array[
    'public.menu_item_modifier_groups',
    'public.menu_item_modifiers',
    'public.food_orders',
    'public.food_order_items',
    'public.food_order_item_modifiers',
    'public.food_order_events',
    'public.kitchen_tickets',
    'public.service_requests',
    'public.service_request_events',
    'public.guest_notifications',
    'public.service_escalations',

    'public.notification_event_catalog',
    'public.notification_preferences',
    'public.notification_templates',
    'public.notification_template_versions',
    'public.notification_outbox',
    'public.notification_deliveries',
    'public.notification_delivery_attempts',
    'public.notification_dead_letters',
    'public.notification_recipients',
    'public.email_adapter_configs',
    'public.whatsapp_templates',
    'public.business_day_settings',

    'public.operational_error_events'
  ]
  loop
    if to_regclass(v_name) is null then
      raise exception
        'Migration 065 preflight: required relation % is missing.',
        v_name;
    end if;
  end loop;

  foreach v_signature in array array[
    'private.day15_guest_context(text,text,boolean)',
    'private.day15_actor_staff_id(uuid)',
    'private.day15_notify_guest(uuid,uuid,uuid,uuid,text,uuid,text,text,text,jsonb)',
    'private.day15_menu_item_available_now(public.menu_categories,text)',

    'public.get_guest_food_menu(text,text)',
    'public.place_guest_food_order(text,text,jsonb)',
    'public.get_guest_food_orders(text,text)',
    'public.cancel_guest_food_order(text,text,uuid,text)',
    'public.get_guest_service_catalog(text,text)',
    'public.create_guest_service_request(text,text,text)',
    'public.get_guest_service_requests(text,text)',
    'public.cancel_guest_service_request(text,text,uuid,text)',
    'public.get_guest_notifications(text,text)',

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

    'private.day16_assert_report_access(uuid,date,date)',
    'private.day16_assert_filter_access(uuid)',
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

    'private.day17_can_manage_hotel(uuid)',
    'private.resolve_hotel_business_date(uuid,timestamptz)',
    'private.day17_render_notification_text(text,jsonb)',
    'private.day17_enqueue_notification_event_internal(uuid,text,uuid,jsonb,uuid)',
    'private.day17_capture_critical_event()',
    'private.day17_capture_support_event()',
    'private.day17_capture_announcement_event()',

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

    'private.day18_page_limit(integer)',
    'private.day18_encode_cursor(timestamptz,uuid)',
    'private.day18_decode_cursor(text)',
    'private.day18_assert_page_access(uuid)',

    'public.get_reservations_page(uuid,integer,text,text,text,text)',
    'public.get_guests_page(uuid,integer,text,text)',
    'public.get_guest_sessions_page(uuid,integer,text,text)',
    'public.get_service_requests_page(uuid,integer,text,text,text)',
    'public.get_food_orders_page(uuid,integer,text,text)',
    'public.get_activity_logs_page(uuid,integer,text,text,text)',
    'public.get_notification_deliveries_page(uuid,integer,text,text,text)',
    'public.get_folios_page(uuid,integer,text,text)',
    'public.get_day18_query_health(uuid)',

    'private.day18_safe_log_text(text,integer)',
    'private.day18_safe_log_context(jsonb)',
    'public.report_operational_error(uuid,jsonb)',
    'public.get_operational_health_snapshot(uuid)',
    'public.get_operational_diagnostics(uuid,timestamptz,timestamptz,integer,text,text,text,text)',
    'public.set_operational_incident_status(uuid,uuid,text,text)'
  ]
  loop
    if to_regprocedure(v_signature) is null then
      raise exception
        'Migration 065 preflight: required function % is missing.',
        v_signature;
    end if;
  end loop;
end;
$preflight$;


-- ============================================================================
-- 2. RE-HARDEN FUTURE DEFAULT PRIVILEGES
-- ============================================================================

alter default privileges for role postgres in schema public
  revoke all on tables from anon, authenticated;

alter default privileges for role postgres in schema public
  revoke all on sequences from anon, authenticated;

alter default privileges for role postgres in schema public
  revoke all on functions from anon, authenticated;


-- ============================================================================
-- 3. DAY 15 TABLE ACL CANONICALIZATION
-- ============================================================================

-- Menu modifier administration: authenticated CRUD; anon/PUBLIC none.
revoke all privileges on table
  public.menu_item_modifier_groups,
  public.menu_item_modifiers
from public, anon, authenticated;

grant select, insert, update, delete on table
  public.menu_item_modifier_groups,
  public.menu_item_modifiers
to authenticated;

-- Operational food/service tables: authenticated read-only; anon/PUBLIC none.
revoke all privileges on table
  public.food_orders,
  public.food_order_items,
  public.food_order_item_modifiers,
  public.food_order_events,
  public.kitchen_tickets,
  public.service_requests,
  public.service_request_events,
  public.guest_notifications,
  public.service_escalations
from public, anon, authenticated;

grant select on table
  public.food_orders,
  public.food_order_items,
  public.food_order_item_modifiers,
  public.food_order_events,
  public.kitchen_tickets,
  public.service_requests,
  public.service_request_events,
  public.guest_notifications,
  public.service_escalations
to authenticated;


-- ============================================================================
-- 4. DAY 15 FUNCTION ACL CANONICALIZATION
-- ============================================================================

revoke all privileges on function
  private.day15_guest_context(text,text,boolean),
  private.day15_actor_staff_id(uuid),
  private.day15_notify_guest(uuid,uuid,uuid,uuid,text,uuid,text,text,text,jsonb),
  private.day15_menu_item_available_now(public.menu_categories,text)
from public, anon, authenticated;

-- Signed guest RPCs are intentionally available to token-bound guest callers.
revoke all privileges on function
  public.get_guest_food_menu(text,text),
  public.place_guest_food_order(text,text,jsonb),
  public.get_guest_food_orders(text,text),
  public.cancel_guest_food_order(text,text,uuid,text),
  public.get_guest_service_catalog(text,text),
  public.create_guest_service_request(text,text,text),
  public.get_guest_service_requests(text,text),
  public.cancel_guest_service_request(text,text,uuid,text),
  public.get_guest_notifications(text,text)
from public, anon, authenticated;

grant execute on function
  public.get_guest_food_menu(text,text),
  public.place_guest_food_order(text,text,jsonb),
  public.get_guest_food_orders(text,text),
  public.cancel_guest_food_order(text,text,uuid,text),
  public.get_guest_service_catalog(text,text),
  public.create_guest_service_request(text,text,text),
  public.get_guest_service_requests(text,text),
  public.cancel_guest_service_request(text,text,uuid,text),
  public.get_guest_notifications(text,text)
to anon, authenticated;

-- Staff/admin RPCs are authenticated-only at the API boundary.
revoke all privileges on function
  public.update_food_order_status(uuid,uuid,text,integer,text),
  public.post_food_order_to_folio(uuid,uuid),
  public.get_food_order_kot(uuid,uuid),
  public.get_food_operations_analytics(uuid,timestamptz,timestamptz),
  public.assign_service_request(uuid,uuid,uuid),
  public.update_service_request_priority(uuid,uuid,text),
  public.update_service_request_status(uuid,uuid,text,integer,text),
  public.escalate_overdue_service_requests(uuid),
  public.get_service_operations_analytics(uuid,timestamptz,timestamptz),
  public.save_menu_locale_translations(uuid,text,jsonb)
from public, anon, authenticated;

grant execute on function
  public.update_food_order_status(uuid,uuid,text,integer,text),
  public.post_food_order_to_folio(uuid,uuid),
  public.get_food_order_kot(uuid,uuid),
  public.get_food_operations_analytics(uuid,timestamptz,timestamptz),
  public.assign_service_request(uuid,uuid,uuid),
  public.update_service_request_priority(uuid,uuid,text),
  public.update_service_request_status(uuid,uuid,text,integer,text),
  public.escalate_overdue_service_requests(uuid),
  public.get_service_operations_analytics(uuid,timestamptz,timestamptz),
  public.save_menu_locale_translations(uuid,text,jsonb)
to authenticated;


-- ============================================================================
-- 5. DAY 16 REPORTING ACL CANONICALIZATION
-- ============================================================================

revoke all privileges on function
  private.day16_assert_report_access(uuid,date,date),
  private.day16_assert_filter_access(uuid)
from public, anon, authenticated;

grant execute on function
  private.day16_assert_report_access(uuid,date,date),
  private.day16_assert_filter_access(uuid)
to authenticated;

revoke all privileges on function
  public.get_report_filter_options(uuid),
  public.get_report_occupancy_daily(uuid,date,date),
  public.get_report_revenue_daily(uuid,date,date),
  public.get_report_revenue_by_category(uuid,date,date),
  public.get_report_reservations_by_source(uuid,date,date),
  public.get_report_arrivals_departures(uuid,date,date),
  public.get_report_payments_by_method(uuid,date,date),
  public.get_report_tax_gst_summary(uuid,date,date),
  public.get_report_guest_food_service(uuid,date,date),
  public.get_report_service_sla(uuid,date,date),
  public.get_report_housekeeping(uuid,date,date),
  public.get_report_staff_department(uuid,date,date),
  public.get_report_kpi_summary(uuid,date,date),
  public.get_report_export_rows(uuid,date,date,text,jsonb)
from public, anon, authenticated;

grant execute on function
  public.get_report_filter_options(uuid),
  public.get_report_occupancy_daily(uuid,date,date),
  public.get_report_revenue_daily(uuid,date,date),
  public.get_report_revenue_by_category(uuid,date,date),
  public.get_report_reservations_by_source(uuid,date,date),
  public.get_report_arrivals_departures(uuid,date,date),
  public.get_report_payments_by_method(uuid,date,date),
  public.get_report_tax_gst_summary(uuid,date,date),
  public.get_report_guest_food_service(uuid,date,date),
  public.get_report_service_sla(uuid,date,date),
  public.get_report_housekeeping(uuid,date,date),
  public.get_report_staff_department(uuid,date,date),
  public.get_report_kpi_summary(uuid,date,date),
  public.get_report_export_rows(uuid,date,date,text,jsonb)
to authenticated;


-- ============================================================================
-- 6. DAY 17 TABLE/FUNCTION ACL CANONICALIZATION
-- ============================================================================

revoke all privileges on table
  public.notification_event_catalog,
  public.notification_preferences,
  public.notification_templates,
  public.notification_template_versions,
  public.notification_outbox,
  public.notification_deliveries,
  public.notification_delivery_attempts,
  public.notification_dead_letters,
  public.notification_recipients,
  public.email_adapter_configs,
  public.whatsapp_templates,
  public.business_day_settings
from public, anon, authenticated;

grant select on table
  public.notification_event_catalog,
  public.notification_preferences,
  public.notification_templates,
  public.notification_template_versions,
  public.notification_outbox,
  public.notification_deliveries,
  public.notification_delivery_attempts,
  public.notification_dead_letters,
  public.notification_recipients,
  public.email_adapter_configs,
  public.whatsapp_templates,
  public.business_day_settings
to authenticated;

revoke all privileges on function
  private.day17_can_manage_hotel(uuid),
  private.resolve_hotel_business_date(uuid,timestamptz),
  private.day17_render_notification_text(text,jsonb),
  private.day17_enqueue_notification_event_internal(uuid,text,uuid,jsonb,uuid),
  private.day17_capture_critical_event(),
  private.day17_capture_support_event(),
  private.day17_capture_announcement_event()
from public, anon, authenticated;

grant execute on function
  private.day17_can_manage_hotel(uuid)
to authenticated;

revoke all privileges on function
  public.get_notification_inbox(uuid,integer,timestamptz),
  public.mark_notification_read(uuid),
  public.mark_all_notifications_read(uuid),
  public.upsert_notification_preferences(uuid,jsonb),
  public.publish_notification_template(uuid,text,text,jsonb),
  public.enqueue_notification_event(uuid,text,uuid,jsonb),
  public.process_notification_outbox(integer),
  public.retry_notification_delivery(uuid),
  public.get_activity_timeline(uuid,timestamptz,timestamptz,jsonb),
  public.get_hotel_system_settings(uuid),
  public.update_hotel_system_settings(uuid,jsonb),
  public.get_support_workspace(uuid),
  public.get_active_announcements(uuid),
  public.upsert_email_adapter_config(uuid,jsonb),
  public.upsert_manual_whatsapp_template(uuid,jsonb)
from public, anon, authenticated;

grant execute on function
  public.get_notification_inbox(uuid,integer,timestamptz),
  public.mark_notification_read(uuid),
  public.mark_all_notifications_read(uuid),
  public.upsert_notification_preferences(uuid,jsonb),
  public.publish_notification_template(uuid,text,text,jsonb),
  public.enqueue_notification_event(uuid,text,uuid,jsonb),
  public.process_notification_outbox(integer),
  public.retry_notification_delivery(uuid),
  public.get_activity_timeline(uuid,timestamptz,timestamptz,jsonb),
  public.get_hotel_system_settings(uuid),
  public.update_hotel_system_settings(uuid,jsonb),
  public.get_support_workspace(uuid),
  public.get_active_announcements(uuid),
  public.upsert_email_adapter_config(uuid,jsonb),
  public.upsert_manual_whatsapp_template(uuid,jsonb)
to authenticated;


-- ============================================================================
-- 7. DAY 18 PAGINATION/MONITORING ACL CANONICALIZATION
-- ============================================================================

revoke all privileges on function
  private.day18_page_limit(integer),
  private.day18_encode_cursor(timestamptz,uuid),
  private.day18_decode_cursor(text),
  private.day18_assert_page_access(uuid)
from public, anon, authenticated;

revoke all privileges on function
  public.get_reservations_page(uuid,integer,text,text,text,text),
  public.get_guests_page(uuid,integer,text,text),
  public.get_guest_sessions_page(uuid,integer,text,text),
  public.get_service_requests_page(uuid,integer,text,text,text),
  public.get_food_orders_page(uuid,integer,text,text),
  public.get_activity_logs_page(uuid,integer,text,text,text),
  public.get_notification_deliveries_page(uuid,integer,text,text,text),
  public.get_folios_page(uuid,integer,text,text),
  public.get_day18_query_health(uuid)
from public, anon, authenticated;

grant execute on function
  public.get_reservations_page(uuid,integer,text,text,text,text),
  public.get_guests_page(uuid,integer,text,text),
  public.get_guest_sessions_page(uuid,integer,text,text),
  public.get_service_requests_page(uuid,integer,text,text,text),
  public.get_food_orders_page(uuid,integer,text,text),
  public.get_activity_logs_page(uuid,integer,text,text,text),
  public.get_notification_deliveries_page(uuid,integer,text,text,text),
  public.get_folios_page(uuid,integer,text,text),
  public.get_day18_query_health(uuid)
to authenticated;

revoke all privileges on table
  public.operational_error_events
from public, anon, authenticated;

revoke all privileges on function
  private.day18_safe_log_text(text,integer),
  private.day18_safe_log_context(jsonb)
from public, anon, authenticated;

revoke all privileges on function
  public.report_operational_error(uuid,jsonb),
  public.get_operational_health_snapshot(uuid),
  public.get_operational_diagnostics(uuid,timestamptz,timestamptz,integer,text,text,text,text),
  public.set_operational_incident_status(uuid,uuid,text,text)
from public, anon, authenticated;

grant execute on function
  public.report_operational_error(uuid,jsonb),
  public.get_operational_health_snapshot(uuid),
  public.get_operational_diagnostics(uuid,timestamptz,timestamptz,integer,text,text,text,text),
  public.set_operational_incident_status(uuid,uuid,text,text)
to authenticated;


-- ============================================================================
-- 8. ACCEPTANCE HELPER CLOSURE
-- ============================================================================

revoke all privileges on function
  private.day15_migration_051_acceptance_rev1(),
  private.day15_migration_052_acceptance_rev1(),
  private.day15_migration_053_acceptance_rev1(),
  private.day16_migration_055_acceptance_rev1(),
  private.day17_migration_056_acceptance_rev2(),
  private.day17_migration_057_acceptance_rev1(),
  private.day18_migration_058_acceptance_rev1(),
  private.day18_migration_059_acceptance_rev1(),
  private.day18_migration_059_acceptance_rev2()
from public, anon, authenticated;


-- ============================================================================
-- 9. PRE-COMMIT VERIFICATION
-- ============================================================================

do $verify$
declare
  v_failed integer := 0;
  v_unsafe_default_acl_count integer := 0;
  v_name text;
  v_signature text;
begin
  -- Default privilege recurrence guard.
  select count(*)
  into v_unsafe_default_acl_count
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

  if v_unsafe_default_acl_count <> 0 then
    raise exception
      'Migration 065 verification failed: % unsafe anon/authenticated default ACL entrie(s) remain.',
      v_unsafe_default_acl_count;
  end if;

  -- Day 15 menu modifier tables: authenticated CRUD, anon no access.
  foreach v_name in array array[
    'menu_item_modifier_groups',
    'menu_item_modifiers'
  ]
  loop
    if has_table_privilege('anon', 'public.' || v_name, 'SELECT')
       or has_table_privilege('anon', 'public.' || v_name, 'INSERT')
       or has_table_privilege('anon', 'public.' || v_name, 'UPDATE')
       or has_table_privilege('anon', 'public.' || v_name, 'DELETE')
       or not has_table_privilege('authenticated', 'public.' || v_name, 'SELECT')
       or not has_table_privilege('authenticated', 'public.' || v_name, 'INSERT')
       or not has_table_privilege('authenticated', 'public.' || v_name, 'UPDATE')
       or not has_table_privilege('authenticated', 'public.' || v_name, 'DELETE')
    then
      v_failed := v_failed + 1;
    end if;
  end loop;

  -- Day 15 operational tables: authenticated read-only, anon no access.
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
    if not has_table_privilege('authenticated', 'public.' || v_name, 'SELECT')
       or has_table_privilege('authenticated', 'public.' || v_name, 'INSERT')
       or has_table_privilege('authenticated', 'public.' || v_name, 'UPDATE')
       or has_table_privilege('authenticated', 'public.' || v_name, 'DELETE')
       or has_table_privilege('anon', 'public.' || v_name, 'SELECT')
       or has_table_privilege('anon', 'public.' || v_name, 'INSERT')
       or has_table_privilege('anon', 'public.' || v_name, 'UPDATE')
       or has_table_privilege('anon', 'public.' || v_name, 'DELETE')
    then
      v_failed := v_failed + 1;
    end if;
  end loop;

  -- Day 15 guest RPCs.
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
    if not has_function_privilege('anon', v_signature, 'EXECUTE')
       or not has_function_privilege('authenticated', v_signature, 'EXECUTE')
    then
      v_failed := v_failed + 1;
    end if;
  end loop;

  -- Authenticated-only public RPCs.
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
    if not has_function_privilege('authenticated', v_signature, 'EXECUTE')
       or has_function_privilege('anon', v_signature, 'EXECUTE')
    then
      v_failed := v_failed + 1;
    end if;
  end loop;

  -- Day 17 direct table boundary.
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
    if not has_table_privilege('authenticated', 'public.' || v_name, 'SELECT')
       or has_table_privilege('authenticated', 'public.' || v_name, 'INSERT')
       or has_table_privilege('authenticated', 'public.' || v_name, 'UPDATE')
       or has_table_privilege('authenticated', 'public.' || v_name, 'DELETE')
       or has_table_privilege('anon', 'public.' || v_name, 'SELECT')
       or has_table_privilege('anon', 'public.' || v_name, 'INSERT')
       or has_table_privilege('anon', 'public.' || v_name, 'UPDATE')
       or has_table_privilege('anon', 'public.' || v_name, 'DELETE')
    then
      v_failed := v_failed + 1;
    end if;
  end loop;

  -- Day 17 trusted private RLS helper exception.
  if not has_function_privilege(
       'authenticated',
       'private.day17_can_manage_hotel(uuid)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'private.day17_can_manage_hotel(uuid)',
       'EXECUTE'
     )
  then
    v_failed := v_failed + 1;
  end if;

  -- Monitoring table is closed to API roles.
  if has_table_privilege('anon', 'public.operational_error_events', 'SELECT')
     or has_table_privilege('anon', 'public.operational_error_events', 'INSERT')
     or has_table_privilege('anon', 'public.operational_error_events', 'UPDATE')
     or has_table_privilege('anon', 'public.operational_error_events', 'DELETE')
     or has_table_privilege('authenticated', 'public.operational_error_events', 'SELECT')
     or has_table_privilege('authenticated', 'public.operational_error_events', 'INSERT')
     or has_table_privilege('authenticated', 'public.operational_error_events', 'UPDATE')
     or has_table_privilege('authenticated', 'public.operational_error_events', 'DELETE')
  then
    v_failed := v_failed + 1;
  end if;

  if v_failed <> 0 then
    raise exception
      'Migration 065 verification failed: % ACL boundary group(s) failed.',
      v_failed;
  end if;
end;
$verify$;

commit;


-- ============================================================================
-- 10. POST-COMMIT SUMMARY
-- ============================================================================

select
  current_user as current_user,
  session_user as session_user,
  pg_has_role('anon', 'service_role', 'MEMBER') as anon_service_role,
  pg_has_role('authenticated', 'service_role', 'MEMBER') as authenticated_service_role;

select
  'M065_POSTCOMMIT'::text as suite,
  not has_table_privilege('anon', 'public.food_order_events', 'INSERT')
    and not has_table_privilege('authenticated', 'public.food_order_events', 'INSERT')
    and not has_function_privilege(
      'anon',
      'public.update_food_order_status(uuid,uuid,text,integer,text)',
      'EXECUTE'
    )
    and not has_function_privilege(
      'anon',
      'public.get_report_filter_options(uuid)',
      'EXECUTE'
    )
    and not has_function_privilege(
      'anon',
      'public.get_notification_inbox(uuid,integer,timestamptz)',
      'EXECUTE'
    )
    and not has_function_privilege(
      'anon',
      'public.get_reservations_page(uuid,integer,text,text,text,text)',
      'EXECUTE'
    )
    and not has_table_privilege(
      'anon',
      'public.operational_error_events',
      'SELECT'
    )
    and not has_table_privilege(
      'authenticated',
      'public.operational_error_events',
      'SELECT'
    )
    and not has_function_privilege(
      'anon',
      'public.report_operational_error(uuid,jsonb)',
      'EXECUTE'
    ) as passed,
  'Representative post-COMMIT ACL boundaries are canonical.'::text as details;
