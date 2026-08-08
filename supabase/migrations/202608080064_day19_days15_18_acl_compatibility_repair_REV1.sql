-- ============================================================================
-- StayQR v1.0
-- Day 19 Migration 064 REV1
-- Days 15-18 Existing-Object ACL Compatibility Repair
-- Date: 2026-08-08
--
-- PURPOSE
-- Re-apply the accepted Day 15-18 browser/API privilege boundaries after the
-- Day 18 canonical fresh-database restore. This migration is ACL-only:
-- it does not insert, update or delete hotel/business rows.
--
-- SOURCE OF TRUTH
-- - Day 15 Migration 051 REV2 privilege fix
-- - Day 15 Migration 052 trusted food/service workflows
-- - Day 15 Migration 054 premium dining/i18n
-- - Day 16 Migration 055 trusted reporting kernel
-- - Day 17 Migration 056 notification/support/settings foundation
-- - Day 17 Migration 057 trusted-config hotfix
-- - Day 18 Migration 058 trusted pagination
-- - Day 18 Migration 059 monitoring/diagnostics
--
-- SAFETY
-- - Forward-only and idempotent.
-- - Existing business data is untouched.
-- - service_role/owner privileges are preserved unless an accepted source
--   migration explicitly grants them.
-- - All target objects are preflighted before any ACL change is committed.
-- - Verification aborts the transaction if the intended browser/API boundary
--   is not restored.
-- ============================================================================

begin;

set local lock_timeout = '10s';
set local statement_timeout = '120s';

select pg_advisory_xact_lock(
  hashtext('stayqr:202608080064:days15-18-acl-compatibility-repair')
);

-- ============================================================================
-- 1. PRECHECK ALL TARGET OBJECTS
-- ============================================================================

do $preflight$
declare
  v_name text;
  v_signature text;
begin
  foreach v_name in array array[
    -- Day 15
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

    -- Day 17
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

    -- Day 18
    'public.operational_error_events'
  ]
  loop
    if to_regclass(v_name) is null then
      raise exception 'Migration 064 preflight: required relation % is missing.', v_name;
    end if;
  end loop;

  foreach v_signature in array array[
    -- Day 15 private helpers
    'private.day15_guest_context(text,text,boolean)',
    'private.day15_actor_staff_id(uuid)',
    'private.day15_notify_guest(uuid,uuid,uuid,uuid,text,uuid,text,text,text,jsonb)',
    'private.day15_menu_item_available_now(public.menu_categories,text)',

    -- Day 15 guest RPCs
    'public.get_guest_food_menu(text,text)',
    'public.place_guest_food_order(text,text,jsonb)',
    'public.get_guest_food_orders(text,text)',
    'public.cancel_guest_food_order(text,text,uuid,text)',
    'public.get_guest_service_catalog(text,text)',
    'public.create_guest_service_request(text,text,text)',
    'public.get_guest_service_requests(text,text)',
    'public.cancel_guest_service_request(text,text,uuid,text)',
    'public.get_guest_notifications(text,text)',

    -- Day 15 staff RPCs
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

    -- Day 16 private helpers
    'private.day16_assert_report_access(uuid,date,date)',
    'private.day16_assert_filter_access(uuid)',

    -- Day 16 report RPCs
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

    -- Day 17 private helpers
    'private.day17_can_manage_hotel(uuid)',
    'private.resolve_hotel_business_date(uuid,timestamptz)',
    'private.day17_render_notification_text(text,jsonb)',
    'private.day17_enqueue_notification_event_internal(uuid,text,uuid,jsonb,uuid)',
    'private.day17_capture_critical_event()',
    'private.day17_capture_support_event()',
    'private.day17_capture_announcement_event()',

    -- Day 17 public RPCs
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

    -- Day 18 private pagination helpers
    'private.day18_page_limit(integer)',
    'private.day18_encode_cursor(timestamptz,uuid)',
    'private.day18_decode_cursor(text)',
    'private.day18_assert_page_access(uuid)',

    -- Day 18 pagination RPCs
    'public.get_reservations_page(uuid,integer,text,text,text,text)',
    'public.get_guests_page(uuid,integer,text,text)',
    'public.get_guest_sessions_page(uuid,integer,text,text)',
    'public.get_service_requests_page(uuid,integer,text,text,text)',
    'public.get_food_orders_page(uuid,integer,text,text)',
    'public.get_activity_logs_page(uuid,integer,text,text,text)',
    'public.get_notification_deliveries_page(uuid,integer,text,text,text)',
    'public.get_folios_page(uuid,integer,text,text)',
    'public.get_day18_query_health(uuid)',

    -- Day 18 monitoring
    'private.day18_safe_log_text(text,integer)',
    'private.day18_safe_log_context(jsonb)',
    'public.report_operational_error(uuid,jsonb)',
    'public.get_operational_health_snapshot(uuid)',
    'public.get_operational_diagnostics(uuid,timestamptz,timestamptz,integer,text,text,text,text)',
    'public.set_operational_incident_status(uuid,uuid,text,text)'
  ]
  loop
    if to_regprocedure(v_signature) is null then
      raise exception 'Migration 064 preflight: required function % is missing.', v_signature;
    end if;
  end loop;
end;
$preflight$;


-- ============================================================================
-- 2. DAY 15 — FOOD / SERVICE ACL CONTRACT
-- ============================================================================

-- Menu modifier administration remains authenticated, but anonymous/public
-- direct mutation is forbidden.
revoke all
on table
  public.menu_item_modifier_groups,
  public.menu_item_modifiers
from public, anon;

-- Operational food/service rows remain readable to authenticated staff through
-- RLS, but all browser/API writes are RPC-only.
revoke insert, update, delete, truncate, references, trigger
on table
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

grant select
on table
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

-- Day 15 private helpers are not browser/API executable.
revoke all on function private.day15_guest_context(text,text,boolean)
from public, anon, authenticated;

revoke all on function private.day15_actor_staff_id(uuid)
from public, anon, authenticated;

revoke all on function private.day15_notify_guest(
  uuid,uuid,uuid,uuid,text,uuid,text,text,text,jsonb
)
from public, anon, authenticated;

revoke all on function private.day15_menu_item_available_now(
  public.menu_categories,text
)
from public, anon, authenticated;

-- Signed guest RPCs.
revoke all on function public.get_guest_food_menu(text,text) from public;
revoke all on function public.place_guest_food_order(text,text,jsonb) from public;
revoke all on function public.get_guest_food_orders(text,text) from public;
revoke all on function public.cancel_guest_food_order(text,text,uuid,text) from public;
revoke all on function public.get_guest_service_catalog(text,text) from public;
revoke all on function public.create_guest_service_request(text,text,text) from public;
revoke all on function public.get_guest_service_requests(text,text) from public;
revoke all on function public.cancel_guest_service_request(text,text,uuid,text) from public;
revoke all on function public.get_guest_notifications(text,text) from public;

grant execute on function public.get_guest_food_menu(text,text)
to anon, authenticated, service_role;
grant execute on function public.place_guest_food_order(text,text,jsonb)
to anon, authenticated, service_role;
grant execute on function public.get_guest_food_orders(text,text)
to anon, authenticated, service_role;
grant execute on function public.cancel_guest_food_order(text,text,uuid,text)
to anon, authenticated, service_role;
grant execute on function public.get_guest_service_catalog(text,text)
to anon, authenticated, service_role;
grant execute on function public.create_guest_service_request(text,text,text)
to anon, authenticated, service_role;
grant execute on function public.get_guest_service_requests(text,text)
to anon, authenticated, service_role;
grant execute on function public.cancel_guest_service_request(text,text,uuid,text)
to anon, authenticated, service_role;
grant execute on function public.get_guest_notifications(text,text)
to anon, authenticated, service_role;

-- Staff-only food/service RPCs.
revoke all on function public.update_food_order_status(
  uuid,uuid,text,integer,text
) from public, anon;
revoke all on function public.post_food_order_to_folio(uuid,uuid)
from public, anon;
revoke all on function public.get_food_order_kot(uuid,uuid)
from public, anon;
revoke all on function public.get_food_operations_analytics(
  uuid,timestamptz,timestamptz
) from public, anon;
revoke all on function public.assign_service_request(uuid,uuid,uuid)
from public, anon;
revoke all on function public.update_service_request_priority(uuid,uuid,text)
from public, anon;
revoke all on function public.update_service_request_status(
  uuid,uuid,text,integer,text
) from public, anon;
revoke all on function public.escalate_overdue_service_requests(uuid)
from public, anon;
revoke all on function public.get_service_operations_analytics(
  uuid,timestamptz,timestamptz
) from public, anon;

grant execute on function public.update_food_order_status(
  uuid,uuid,text,integer,text
) to authenticated, service_role;
grant execute on function public.post_food_order_to_folio(uuid,uuid)
to authenticated, service_role;
grant execute on function public.get_food_order_kot(uuid,uuid)
to authenticated, service_role;
grant execute on function public.get_food_operations_analytics(
  uuid,timestamptz,timestamptz
) to authenticated, service_role;
grant execute on function public.assign_service_request(uuid,uuid,uuid)
to authenticated, service_role;
grant execute on function public.update_service_request_priority(uuid,uuid,text)
to authenticated, service_role;
grant execute on function public.update_service_request_status(
  uuid,uuid,text,integer,text
) to authenticated, service_role;
grant execute on function public.escalate_overdue_service_requests(uuid)
to authenticated, service_role;
grant execute on function public.get_service_operations_analytics(
  uuid,timestamptz,timestamptz
) to authenticated, service_role;

-- Premium dining translation writer.
revoke all on function public.save_menu_locale_translations(uuid,text,jsonb)
from public, anon;
grant execute on function public.save_menu_locale_translations(uuid,text,jsonb)
to authenticated, service_role;


-- ============================================================================
-- 3. DAY 16 — TRUSTED REPORTING ACL CONTRACT
-- ============================================================================

revoke all on function private.day16_assert_report_access(uuid,date,date)
from public, anon, authenticated;
revoke all on function private.day16_assert_filter_access(uuid)
from public, anon, authenticated;

grant execute on function private.day16_assert_report_access(uuid,date,date)
to authenticated;
grant execute on function private.day16_assert_filter_access(uuid)
to authenticated;

revoke all on function public.get_report_filter_options(uuid)
from public, anon;
revoke all on function public.get_report_occupancy_daily(uuid,date,date)
from public, anon;
revoke all on function public.get_report_revenue_daily(uuid,date,date)
from public, anon;
revoke all on function public.get_report_revenue_by_category(uuid,date,date)
from public, anon;
revoke all on function public.get_report_reservations_by_source(uuid,date,date)
from public, anon;
revoke all on function public.get_report_arrivals_departures(uuid,date,date)
from public, anon;
revoke all on function public.get_report_payments_by_method(uuid,date,date)
from public, anon;
revoke all on function public.get_report_tax_gst_summary(uuid,date,date)
from public, anon;
revoke all on function public.get_report_guest_food_service(uuid,date,date)
from public, anon;
revoke all on function public.get_report_service_sla(uuid,date,date)
from public, anon;
revoke all on function public.get_report_housekeeping(uuid,date,date)
from public, anon;
revoke all on function public.get_report_staff_department(uuid,date,date)
from public, anon;
revoke all on function public.get_report_kpi_summary(uuid,date,date)
from public, anon;
revoke all on function public.get_report_export_rows(
  uuid,date,date,text,jsonb
) from public, anon;

grant execute on function public.get_report_filter_options(uuid)
to authenticated;
grant execute on function public.get_report_occupancy_daily(uuid,date,date)
to authenticated;
grant execute on function public.get_report_revenue_daily(uuid,date,date)
to authenticated;
grant execute on function public.get_report_revenue_by_category(uuid,date,date)
to authenticated;
grant execute on function public.get_report_reservations_by_source(uuid,date,date)
to authenticated;
grant execute on function public.get_report_arrivals_departures(uuid,date,date)
to authenticated;
grant execute on function public.get_report_payments_by_method(uuid,date,date)
to authenticated;
grant execute on function public.get_report_tax_gst_summary(uuid,date,date)
to authenticated;
grant execute on function public.get_report_guest_food_service(uuid,date,date)
to authenticated;
grant execute on function public.get_report_service_sla(uuid,date,date)
to authenticated;
grant execute on function public.get_report_housekeeping(uuid,date,date)
to authenticated;
grant execute on function public.get_report_staff_department(uuid,date,date)
to authenticated;
grant execute on function public.get_report_kpi_summary(uuid,date,date)
to authenticated;
grant execute on function public.get_report_export_rows(
  uuid,date,date,text,jsonb
) to authenticated;


-- ============================================================================
-- 4. DAY 17 — NOTIFICATION / SUPPORT / SETTINGS ACL CONTRACT
-- ============================================================================

revoke all on table
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

revoke all on function
  private.day17_can_manage_hotel(uuid),
  private.resolve_hotel_business_date(uuid,timestamptz),
  private.day17_render_notification_text(text,jsonb),
  private.day17_enqueue_notification_event_internal(uuid,text,uuid,jsonb,uuid),
  private.day17_capture_critical_event(),
  private.day17_capture_support_event(),
  private.day17_capture_announcement_event()
from public, anon, authenticated;

-- Migration 057 intentionally re-opens only the management RLS helper to
-- authenticated callers.
grant execute on function private.day17_can_manage_hotel(uuid)
to authenticated;

revoke all on function
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

-- Explicit RPC-only direct-write closure from Migration 057.
revoke insert, update, delete on table
  public.email_adapter_configs,
  public.whatsapp_templates
from public, anon, authenticated;


-- ============================================================================
-- 5. DAY 18 — PAGINATION / MONITORING ACL CONTRACT
-- ============================================================================

revoke all on function private.day18_page_limit(integer)
from public, anon, authenticated;
revoke all on function private.day18_encode_cursor(timestamptz,uuid)
from public, anon, authenticated;
revoke all on function private.day18_decode_cursor(text)
from public, anon, authenticated;
revoke all on function private.day18_assert_page_access(uuid)
from public, anon, authenticated;

revoke all on function public.get_reservations_page(
  uuid,integer,text,text,text,text
) from public, anon;
revoke all on function public.get_guests_page(
  uuid,integer,text,text
) from public, anon;
revoke all on function public.get_guest_sessions_page(
  uuid,integer,text,text
) from public, anon;
revoke all on function public.get_service_requests_page(
  uuid,integer,text,text,text
) from public, anon;
revoke all on function public.get_food_orders_page(
  uuid,integer,text,text
) from public, anon;
revoke all on function public.get_activity_logs_page(
  uuid,integer,text,text,text
) from public, anon;
revoke all on function public.get_notification_deliveries_page(
  uuid,integer,text,text,text
) from public, anon;
revoke all on function public.get_folios_page(
  uuid,integer,text,text
) from public, anon;
revoke all on function public.get_day18_query_health(uuid)
from public, anon;

grant execute on function public.get_reservations_page(
  uuid,integer,text,text,text,text
) to authenticated;
grant execute on function public.get_guests_page(
  uuid,integer,text,text
) to authenticated;
grant execute on function public.get_guest_sessions_page(
  uuid,integer,text,text
) to authenticated;
grant execute on function public.get_service_requests_page(
  uuid,integer,text,text,text
) to authenticated;
grant execute on function public.get_food_orders_page(
  uuid,integer,text,text
) to authenticated;
grant execute on function public.get_activity_logs_page(
  uuid,integer,text,text,text
) to authenticated;
grant execute on function public.get_notification_deliveries_page(
  uuid,integer,text,text,text
) to authenticated;
grant execute on function public.get_folios_page(
  uuid,integer,text,text
) to authenticated;
grant execute on function public.get_day18_query_health(uuid)
to authenticated;

-- Monitoring table is RPC-only, including reads.
revoke all on table public.operational_error_events
from public, anon, authenticated;

revoke all on function private.day18_safe_log_text(text,integer)
from public, anon, authenticated;
revoke all on function private.day18_safe_log_context(jsonb)
from public, anon, authenticated;

revoke all on function public.report_operational_error(uuid,jsonb)
from public, anon;
revoke all on function public.get_operational_health_snapshot(uuid)
from public, anon;
revoke all on function public.get_operational_diagnostics(
  uuid,timestamptz,timestamptz,integer,text,text,text,text
) from public, anon;
revoke all on function public.set_operational_incident_status(
  uuid,uuid,text,text
) from public, anon;

grant execute on function public.report_operational_error(uuid,jsonb)
to authenticated, service_role;
grant execute on function public.get_operational_health_snapshot(uuid)
to authenticated;
grant execute on function public.get_operational_diagnostics(
  uuid,timestamptz,timestamptz,integer,text,text,text,text
) to authenticated;
grant execute on function public.set_operational_incident_status(
  uuid,uuid,text,text
) to authenticated;

-- Keep acceptance helpers unreachable to browser/API roles.
revoke all on function private.day15_migration_051_acceptance_rev1()
from public, anon, authenticated;
revoke all on function private.day15_migration_052_acceptance_rev1()
from public, anon, authenticated;
revoke all on function private.day15_migration_053_acceptance_rev1()
from public, anon, authenticated;
revoke all on function private.day16_migration_055_acceptance_rev1()
from public, anon, authenticated;
revoke all on function private.day17_migration_056_acceptance_rev2()
from public, anon, authenticated;
revoke all on function private.day17_migration_057_acceptance_rev1()
from public, anon, authenticated;
revoke all on function private.day18_migration_058_acceptance_rev1()
from public, anon, authenticated;
revoke all on function private.day18_migration_059_acceptance_rev1()
from public, anon, authenticated;
revoke all on function private.day18_migration_059_acceptance_rev2()
from public, anon, authenticated;


-- ============================================================================
-- 6. VERIFY ONLY THE ACL CONTRACT CHANGED BY THIS MIGRATION
-- ============================================================================

drop table if exists pg_temp.day19_m064_acl_results;

create temporary table day19_m064_acl_results (
  area text not null,
  test_name text not null,
  passed boolean not null,
  details text not null
) on commit preserve rows;

do $verify$
declare
  v_name text;
  v_signature text;
  v_failed integer;
begin
  -- Day 15 operational rows: no API-role direct writes.
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
    insert into pg_temp.day19_m064_acl_results
    values (
      'DAY15_TABLE',
      v_name || '.authenticated_rpc_only',
      not (
        has_table_privilege('authenticated', 'public.' || v_name, 'INSERT')
        or has_table_privilege('authenticated', 'public.' || v_name, 'UPDATE')
        or has_table_privilege('authenticated', 'public.' || v_name, 'DELETE')
      ),
      'Authenticated direct INSERT/UPDATE/DELETE denied.'
    );

    insert into pg_temp.day19_m064_acl_results
    values (
      'DAY15_TABLE',
      v_name || '.anon_rpc_only',
      not (
        has_table_privilege('anon', 'public.' || v_name, 'INSERT')
        or has_table_privilege('anon', 'public.' || v_name, 'UPDATE')
        or has_table_privilege('anon', 'public.' || v_name, 'DELETE')
      ),
      'Anonymous direct INSERT/UPDATE/DELETE denied.'
    );
  end loop;

  foreach v_name in array array[
    'menu_item_modifier_groups',
    'menu_item_modifiers'
  ]
  loop
    insert into pg_temp.day19_m064_acl_results
    values (
      'DAY15_MENU',
      v_name || '.anon_no_write',
      not (
        has_table_privilege('anon', 'public.' || v_name, 'INSERT')
        or has_table_privilege('anon', 'public.' || v_name, 'UPDATE')
        or has_table_privilege('anon', 'public.' || v_name, 'DELETE')
      ),
      'Anonymous menu-modifier writes denied.'
    );
  end loop;

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
    insert into pg_temp.day19_m064_acl_results
    values (
      'DAY15_GUEST_RPC',
      v_signature,
      has_function_privilege('anon', v_signature, 'EXECUTE')
        and has_function_privilege('authenticated', v_signature, 'EXECUTE'),
      'Signed guest RPC executable by anon/authenticated.'
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
    'public.save_menu_locale_translations(uuid,text,jsonb)'
  ]
  loop
    insert into pg_temp.day19_m064_acl_results
    values (
      'DAY15_STAFF_RPC',
      v_signature,
      has_function_privilege('authenticated', v_signature, 'EXECUTE')
        and not has_function_privilege('anon', v_signature, 'EXECUTE'),
      'Authenticated execution granted; anonymous execution denied.'
    );
  end loop;

  -- Day 16 reports.
  foreach v_signature in array array[
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
    'public.get_report_export_rows(uuid,date,date,text,jsonb)'
  ]
  loop
    insert into pg_temp.day19_m064_acl_results
    values (
      'DAY16_REPORT_RPC',
      v_signature,
      has_function_privilege('authenticated', v_signature, 'EXECUTE')
        and not has_function_privilege('anon', v_signature, 'EXECUTE'),
      'Authenticated report execution granted; anonymous execution denied.'
    );
  end loop;

  -- Day 17 data plane.
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
    insert into pg_temp.day19_m064_acl_results
    values (
      'DAY17_TABLE',
      v_name,
      has_table_privilege('authenticated', 'public.' || v_name, 'SELECT')
        and not (
          has_table_privilege('anon', 'public.' || v_name, 'SELECT')
          or has_table_privilege('anon', 'public.' || v_name, 'INSERT')
          or has_table_privilege('anon', 'public.' || v_name, 'UPDATE')
          or has_table_privilege('anon', 'public.' || v_name, 'DELETE')
        ),
      'Authenticated SELECT retained; anonymous direct access denied.'
    );
  end loop;

  foreach v_signature in array array[
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
    'public.upsert_manual_whatsapp_template(uuid,jsonb)'
  ]
  loop
    insert into pg_temp.day19_m064_acl_results
    values (
      'DAY17_RPC',
      v_signature,
      has_function_privilege('authenticated', v_signature, 'EXECUTE')
        and not has_function_privilege('anon', v_signature, 'EXECUTE'),
      'Authenticated execution granted; anonymous execution denied.'
    );
  end loop;

  insert into pg_temp.day19_m064_acl_results
  values (
    'DAY17_HELPER',
    'private.day17_can_manage_hotel(uuid)',
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
    'Authenticated RLS evaluation allowed; anonymous execution denied.'
  );

  -- Day 18 trusted pagination.
  foreach v_signature in array array[
    'public.get_reservations_page(uuid,integer,text,text,text,text)',
    'public.get_guests_page(uuid,integer,text,text)',
    'public.get_guest_sessions_page(uuid,integer,text,text)',
    'public.get_service_requests_page(uuid,integer,text,text,text)',
    'public.get_food_orders_page(uuid,integer,text,text)',
    'public.get_activity_logs_page(uuid,integer,text,text,text)',
    'public.get_notification_deliveries_page(uuid,integer,text,text,text)',
    'public.get_folios_page(uuid,integer,text,text)',
    'public.get_day18_query_health(uuid)'
  ]
  loop
    insert into pg_temp.day19_m064_acl_results
    values (
      'DAY18_PAGE_RPC',
      v_signature,
      has_function_privilege('authenticated', v_signature, 'EXECUTE')
        and not has_function_privilege('anon', v_signature, 'EXECUTE'),
      'Authenticated pagination execution granted; anonymous execution denied.'
    );
  end loop;

  insert into pg_temp.day19_m064_acl_results
  values (
    'DAY18_MONITORING_TABLE',
    'operational_error_events.api_closed',
    not (
      has_table_privilege('anon', 'public.operational_error_events', 'SELECT')
      or has_table_privilege('anon', 'public.operational_error_events', 'INSERT')
      or has_table_privilege('authenticated', 'public.operational_error_events', 'SELECT')
      or has_table_privilege('authenticated', 'public.operational_error_events', 'INSERT')
      or has_table_privilege('authenticated', 'public.operational_error_events', 'UPDATE')
      or has_table_privilege('authenticated', 'public.operational_error_events', 'DELETE')
    ),
    'Operational log table is RPC-only.'
  );

  foreach v_signature in array array[
    'public.report_operational_error(uuid,jsonb)',
    'public.get_operational_health_snapshot(uuid)',
    'public.get_operational_diagnostics(uuid,timestamptz,timestamptz,integer,text,text,text,text)',
    'public.set_operational_incident_status(uuid,uuid,text,text)'
  ]
  loop
    insert into pg_temp.day19_m064_acl_results
    values (
      'DAY18_MONITORING_RPC',
      v_signature,
      has_function_privilege('authenticated', v_signature, 'EXECUTE')
        and not has_function_privilege('anon', v_signature, 'EXECUTE'),
      'Authenticated monitoring execution granted; anonymous execution denied.'
    );
  end loop;

  select count(*)
  into v_failed
  from pg_temp.day19_m064_acl_results
  where not passed;

  if v_failed <> 0 then
    raise exception
      'Migration 064 verification failed: % ACL contract check(s) failed.',
      v_failed;
  end if;
end;
$verify$;

commit;


-- ============================================================================
-- 7. ACCEPTANCE OUTPUT
-- ============================================================================

select
  area,
  count(*) as total_checks,
  count(*) filter (where passed) as passed_checks,
  count(*) filter (where not passed) as failed_checks
from pg_temp.day19_m064_acl_results
group by area
order by area;

select
  count(*) as total_checks,
  count(*) filter (where passed) as passed_checks,
  count(*) filter (where not passed) as failed_checks
from pg_temp.day19_m064_acl_results;

drop table if exists pg_temp.day19_m064_acl_results;
