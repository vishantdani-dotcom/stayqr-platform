-- ============================================================================
-- StayQR v1.0
-- Day 16 Audit 067 REV1
-- Analytics and Standard Reports Preflight
--
-- ROADMAP SCOPE
-- Date filters; occupancy; ADR/ARR; RevPAR; revenue drill-down;
-- reservation/source; arrival/departure; payments/cashier; tax/GST;
-- guest; food; service SLA; housekeeping; staff/department; CSV/PDF exports.
--
-- PURPOSE
-- Inventory the locked Days 1-15 database and identify the exact Day 16 gaps.
-- This preflight is read-only for hotel business data.
--
-- EXPECTED OUTPUT
-- 132 rows.
-- Baseline/informational checks should pass.
-- DAY16_PLANNED_GAPS are expected to be false before Migration 055.
-- ============================================================================

begin;

set local lock_timeout = '10s';
set local statement_timeout = '180s';

select pg_advisory_xact_lock(
  hashtext('stayqr:202608050067:day16-analytics-preflight-rev1')
);

create schema if not exists private;

create or replace function private.day16_audit_067_preflight_rev1()
returns table (
  suite text,
  test_name text,
  passed boolean,
  state text,
  details text
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  r record;
  v_exists boolean;
  v_count bigint;
begin
  -- A. Required source tables.
  for r in
    select *
    from (values
      ('hotels', 'Hotel identity, status, timezone and tax context.'),
      ('rooms', 'Physical room inventory.'),
      ('room_types', 'Room classification and capacity.'),
      ('reservations', 'Reservation header, dates, source and revenue.'),
      ('reservation_rooms', 'Sold-room and rate allocation lines.'),
      ('reservation_guests', 'Reservation-to-guest identity.'),
      ('guest_sessions', 'Actual stay/check-in/check-out source.'),
      ('guests', 'Guest identity source.'),
      ('folios', 'Authoritative guest financial account.'),
      ('folio_items', 'Posted room, food, service and tax charges.'),
      ('folio_collections', 'Authoritative collections by payment method.'),
      ('invoices', 'Issued invoice and GST summary source.'),
      ('invoice_lines', 'Issued invoice line and tax breakdown.'),
      ('payments', 'Legacy/current payment records.'),
      ('food_orders', 'Food order lifecycle and delivered revenue.'),
      ('food_order_items', 'Food order item detail.'),
      ('service_requests', 'Guest service lifecycle and SLA source.'),
      ('service_request_types', 'Dynamic service catalogue and department routing.'),
      ('housekeeping_tasks', 'Housekeeping workload and completion source.'),
      ('maintenance_tasks', 'Maintenance workload and closure source.'),
      ('staff', 'Staff and department workload source.'),
      ('role_permissions', 'Role/permission reporting boundary.'),
      ('room_blocks', 'Out-of-order and blocked room-night source.'),
      ('room_inventory_allocations', 'Authoritative room inventory ledger.')
    ) as source_table(object_name, purpose)
  loop
    suite := 'A_SOURCE_TABLES';
    test_name := r.object_name;
    passed := to_regclass(format('public.%I', r.object_name)) is not null;
    state := 'baseline';
    details := r.purpose;
    return next;
  end loop;

  -- B. Required source columns.
  for r in
    select *
    from (values
      ('hotels', 'id', 'Tenant key.'),
      ('hotels', 'timezone', 'Hotel-local date boundary.'),
      ('hotels', 'status', 'Active hotel scope.'),
      ('rooms', 'hotel_id', 'Tenant scope.'),
      ('rooms', 'status', 'Current room state.'),
      ('rooms', 'room_type_id', 'Room-type drill-down.'),
      ('reservations', 'hotel_id', 'Tenant scope.'),
      ('reservations', 'booking_source', 'Reservation/source report.'),
      ('reservations', 'arrival_date', 'Arrival filtering.'),
      ('reservations', 'departure_date', 'Departure filtering.'),
      ('reservations', 'status', 'Reservation lifecycle.'),
      ('reservations', 'room_subtotal', 'Room revenue source.'),
      ('reservations', 'tax_amount', 'Reservation tax source.'),
      ('reservations', 'discount_amount', 'Reservation discount source.'),
      ('reservations', 'total_amount', 'Reservation total source.'),
      ('reservation_rooms', 'reservation_id', 'Reservation line identity.'),
      ('reservation_rooms', 'room_id', 'Physical room drill-down.'),
      ('reservation_rooms', 'room_type_id', 'Room-type drill-down.'),
      ('reservation_rooms', 'nightly_rate', 'ADR/ARR input.'),
      ('reservation_rooms', 'total_amount', 'Reservation-room total.'),
      ('guest_sessions', 'hotel_id', 'Tenant scope.'),
      ('guest_sessions', 'room_id', 'Actual occupied room.'),
      ('guest_sessions', 'reservation_id', 'Reservation/stay reconciliation.'),
      ('guest_sessions', 'checkin_time', 'Actual arrival.'),
      ('guest_sessions', 'checkout_time', 'Actual departure.'),
      ('guest_sessions', 'status', 'Stay lifecycle.'),
      ('folios', 'hotel_id', 'Tenant scope.'),
      ('folios', 'guest_session_id', 'Stay/folio reconciliation.'),
      ('folios', 'status', 'Open/settled account state.'),
      ('folio_items', 'charge_category', 'Room/food/service/manual revenue split.'),
      ('folio_items', 'amount', 'Posted charge amount.'),
      ('folio_items', 'posting_status', 'Posted-versus-voided filter.'),
      ('folio_items', 'service_at', 'Hotel-local revenue date.'),
      ('folio_collections', 'amount', 'Collection value.'),
      ('folio_collections', 'payment_method', 'Payment method drill-down.'),
      ('folio_collections', 'status', 'Posted/voided/reversed filter.'),
      ('folio_collections', 'collected_at', 'Collection date.'),
      ('invoices', 'total_amount', 'Issued invoice total.'),
      ('invoices', 'cgst_amount', 'CGST report.'),
      ('invoices', 'sgst_amount', 'SGST report.'),
      ('invoices', 'igst_amount', 'IGST report.'),
      ('food_orders', 'order_status', 'Food lifecycle filter.'),
      ('food_orders', 'total_amount', 'Delivered food revenue.'),
      ('food_orders', 'created_at', 'Order date filter.'),
      ('service_requests', 'department', 'Department report.'),
      ('service_requests', 'sla_due_at', 'SLA report.'),
      ('service_requests', 'accepted_at', 'Acceptance-time metric.'),
      ('service_requests', 'completed_at', 'Completion-time metric.'),
      ('housekeeping_tasks', 'assigned_staff_id', 'Staff workload.'),
      ('housekeeping_tasks', 'status', 'Housekeeping status.'),
      ('maintenance_tasks', 'assigned_staff_id', 'Maintenance workload.'),
      ('maintenance_tasks', 'status', 'Maintenance status.'),
      ('staff', 'role', 'Role drill-down.'),
      ('staff', 'department', 'Department drill-down.')
    ) as source_column(table_name, column_name, purpose)
  loop
    select exists (
      select 1
      from information_schema.columns c
      where c.table_schema = 'public'
        and c.table_name = r.table_name
        and c.column_name = r.column_name
    )
    into v_exists;

    suite := 'B_SOURCE_COLUMNS';
    test_name := r.table_name || '.' || r.column_name;
    passed := v_exists;
    state := 'baseline';
    details := r.purpose;
    return next;
  end loop;

  -- C. Existing permission and analytics helpers.
  for r in
    select *
    from (values
      ('private.user_has_permission(uuid,text)', 'Tenant permission enforcement.'),
      ('private.user_has_any_permission(uuid,text[])', 'Multi-permission enforcement.'),
      ('private.is_platform_admin()', 'Platform-admin override.'),
      ('public.get_my_hotel_permissions(uuid)', 'Frontend permission resolution.'),
      ('public.get_cashier_shift_report(uuid,uuid)', 'Existing standard cashier report.'),
      ('public.get_food_operations_analytics(uuid,timestamptz,timestamptz)', 'Existing Day 15 food analytics.'),
      ('public.get_service_operations_analytics(uuid,timestamptz,timestamptz)', 'Existing Day 15 service analytics.')
    ) as baseline_function(signature, purpose)
  loop
    suite := 'C_EXISTING_FUNCTIONS';
    test_name := r.signature;
    passed := to_regprocedure(r.signature) is not null;
    state := 'baseline';
    details := r.purpose;
    return next;
  end loop;

  -- D. Existing performance indexes.
  for r in
    select *
    from (values
      ('idx_reservations_hotel_dates_status', 'Reservation date/status filtering.'),
      ('idx_reservation_rooms_room_status', 'Room allocation filtering.'),
      ('idx_folios_hotel_status_updated', 'Folio status/date filtering.'),
      ('idx_folio_items_folio_posted', 'Posted folio lines.'),
      ('idx_food_orders_hotel_status_created', 'Food date/status filtering.'),
      ('idx_service_requests_hotel_department_status', 'Service department/status filtering.'),
      ('idx_service_requests_hotel_sla_due', 'Service SLA filtering.'),
      ('idx_housekeeping_tasks_hotel_status_created', 'Housekeeping date/status filtering.'),
      ('idx_housekeeping_tasks_workload', 'Housekeeping staff workload.'),
      ('idx_maintenance_tasks_workload', 'Maintenance staff workload.'),
      ('idx_invoices_hotel_created', 'Invoice date filtering.'),
      ('idx_payments_hotel_created', 'Payment date filtering.')
    ) as source_index(index_name, purpose)
  loop
    suite := 'D_INDEXES';
    test_name := r.index_name;
    passed := to_regclass(format('public.%I', r.index_name)) is not null;
    state := 'baseline';
    details := r.purpose;
    return next;
  end loop;

  -- E. Permission matrix and security boundary.
  suite := 'E_SECURITY';
  test_name := 'reports_view_owner';
  select exists (
    select 1 from public.role_permissions
    where role_name = 'owner' and permission_key = 'reports.view'
  ) into passed;
  state := 'baseline';
  details := 'Owner has reports.view.';
  return next;

  suite := 'E_SECURITY';
  test_name := 'reports_view_manager';
  select exists (
    select 1 from public.role_permissions
    where role_name = 'manager' and permission_key = 'reports.view'
  ) into passed;
  state := 'baseline';
  details := 'Manager has reports.view.';
  return next;

  suite := 'E_SECURITY';
  test_name := 'reports_view_accounts';
  select exists (
    select 1 from public.role_permissions
    where role_name = 'accounts' and permission_key = 'reports.view'
  ) into passed;
  state := 'baseline';
  details := 'Accounts has reports.view.';
  return next;

  suite := 'E_SECURITY';
  test_name := 'anon_no_permission_helper';
  passed := not has_function_privilege(
    'anon',
    'public.get_my_hotel_permissions(uuid)',
    'EXECUTE'
  );
  state := 'baseline';
  details := 'Anonymous role cannot enumerate hotel permissions.';
  return next;

  suite := 'E_SECURITY';
  test_name := 'authenticated_permission_helper';
  passed := has_function_privilege(
    'authenticated',
    'public.get_my_hotel_permissions(uuid)',
    'EXECUTE'
  );
  state := 'baseline';
  details := 'Authenticated staff can resolve their own permissions.';
  return next;

  suite := 'E_SECURITY';
  test_name := 'reports_page_permission_key_exists';
  select exists (
    select 1 from public.role_permissions
    where permission_key = 'reports.view'
  ) into passed;
  state := 'baseline';
  details := 'Canonical reports.view permission exists.';
  return next;

  suite := 'E_SECURITY';
  test_name := 'hotels_rls_enabled';
  select c.relrowsecurity
  into passed
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relname = 'hotels';
  state := 'baseline';
  details := 'Tenant root remains protected by RLS.';
  return next;

  suite := 'E_SECURITY';
  test_name := 'folios_rls_enabled';
  select c.relrowsecurity
  into passed
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relname = 'folios';
  state := 'baseline';
  details := 'Authoritative folios remain protected by RLS.';
  return next;

  -- F. Planned Day 16 RPCs. False is expected before implementation.
  for r in
    select *
    from (values
      ('public.get_report_kpi_summary(uuid,date,date)', 'Occupancy, room nights, ADR/ARR, RevPAR and revenue summary.'),
      ('public.get_report_occupancy_daily(uuid,date,date)', 'Daily available/sold/occupied/blocked room nights.'),
      ('public.get_report_revenue_daily(uuid,date,date)', 'Daily posted revenue and collections.'),
      ('public.get_report_revenue_by_category(uuid,date,date)', 'Room/food/service/manual/tax revenue drill-down.'),
      ('public.get_report_reservations_by_source(uuid,date,date)', 'Reservation source and conversion report.'),
      ('public.get_report_arrivals_departures(uuid,date,date)', 'Arrival/departure operational report.'),
      ('public.get_report_payments_by_method(uuid,date,date)', 'Cash/card/UPI/payment-link collections.'),
      ('public.get_report_tax_gst_summary(uuid,date,date)', 'CGST/SGST/IGST and taxable totals.'),
      ('public.get_report_guest_food_service(uuid,date,date)', 'Guest, food and service performance.'),
      ('public.get_report_service_sla(uuid,date,date)', 'Department SLA, overdue and completion metrics.'),
      ('public.get_report_housekeeping(uuid,date,date)', 'Housekeeping status and turnaround.'),
      ('public.get_report_staff_department(uuid,date,date)', 'Staff/department workload and completion.'),
      ('public.get_report_export_rows(uuid,date,date,text,jsonb)', 'Role/date-filtered export dataset.'),
      ('public.get_report_filter_options(uuid)', 'Safe source/department/room/staff filter options.')
    ) as planned_function(signature, purpose)
  loop
    suite := 'F_DAY16_PLANNED_GAPS';
    test_name := r.signature;
    passed := to_regprocedure(r.signature) is not null;
    state := case when passed then 'implemented' else 'planned_gap' end;
    details := r.purpose;
    return next;
  end loop;

  -- G. Informational source-row counts.
  for r in
    select *
    from (values
      ('hotels', 'Current source-row count.'),
      ('rooms', 'Current source-row count.'),
      ('reservations', 'Current source-row count.'),
      ('reservation_rooms', 'Current source-row count.'),
      ('guest_sessions', 'Current source-row count.'),
      ('folios', 'Current source-row count.'),
      ('folio_items', 'Current source-row count.'),
      ('folio_collections', 'Current source-row count.'),
      ('invoices', 'Current source-row count.'),
      ('food_orders', 'Current source-row count.'),
      ('service_requests', 'Current source-row count.'),
      ('housekeeping_tasks', 'Current source-row count.')
    ) as data_source(table_name, purpose)
  loop
    if to_regclass(format('public.%I', r.table_name)) is null then
      v_count := 0;
    else
      execute format('select count(*) from public.%I', r.table_name)
      into v_count;
    end if;

    suite := 'G_DATA_COUNTS';
    test_name := r.table_name;
    passed := true;
    state := 'informational';
    details := format('%s row(s).', v_count);
    return next;
  end loop;

  suite := 'H_FINAL';
  test_name := 'day16_preflight_complete';
  passed := true;
  state := 'informational';
  details :=
    'Preflight complete. Migration 055 may now build the trusted report kernel.';
  return next;
end;
$function$;

revoke all on function private.day16_audit_067_preflight_rev1()
from public, anon, authenticated;

commit;

select suite, test_name, passed, state, details
from private.day16_audit_067_preflight_rev1()
order by suite, test_name;
