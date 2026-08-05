-- ============================================================================
-- StayQR v1.0
-- Day 17 Audit 069 REV3 FUNCTION-KIND-SAFE
-- Notifications, Activity, Support and System Settings Preflight
--
-- ROADMAP
-- In-app realtime; notification preferences/templates; email adapters;
-- manual WhatsApp templates; retry/failure log; activity log UI;
-- support tickets; announcements; hotel settings; timezone/business-day
-- consistency.
--
-- EXIT GATE TO DESIGN FOR
-- Critical reservation/payment/service events create auditable notifications
-- without cross-hotel leakage.
--
-- PURPOSE
-- Inventory the locked Days 1-16 baseline and identify exact Day 17 gaps before
-- Migration 056. This audit does not change hotel business data.
--
-- EXPECTED OUTPUT
-- 215 fixed inventory rows.
-- Missing planned Day 17 objects are expected and are reported as successful
-- collision-free checks. Missing locked-baseline objects are failures.
-- ============================================================================

begin;

set local lock_timeout = '10s';
set local statement_timeout = '180s';

select pg_advisory_xact_lock(
  hashtext('stayqr:202608050069:day17-preflight-rev1')
);

create schema if not exists private;

create or replace function private.day17_audit_069_preflight_rev3()
returns table (
  suite text,
  test_name text,
  passed boolean,
  details text
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  rec record;
  v_exists boolean;
  v_count bigint;
  v_count_2 bigint;
  v_text text;
  v_table_regclass regclass;
begin
  -- A. Locked roadmap contract.
  for rec in
    select *
    from (
      values
      ('in_app_realtime', 'In-app realtime notification inbox and live updates.'),
      ('notification_preferences', 'Hotel/user notification channel and event preferences.'),
      ('notification_templates', 'Reusable event templates with safe variables.'),
      ('email_adapters', 'Provider-neutral email adapter and queued delivery boundary.'),
      ('manual_whatsapp_templates', 'Manual WhatsApp templates without automatic message sending.'),
      ('retry_failure_log', 'Delivery attempt, retry and terminal failure audit trail.'),
      ('activity_log_ui', 'Hotel-scoped searchable activity timeline UI.'),
      ('support_tickets', 'Hotel and platform support ticket workflow.'),
      ('announcements', 'Platform and hotel announcement workflow.'),
      ('hotel_settings', 'Operational hotel and system settings.'),
      ('timezone_business_day', 'Timezone and business-day consistency.'),
      ('critical_event_exit_gate', 'Reservation, payment and service events create auditable notifications without cross-hotel leakage.')
    ) roadmap(scope_key, scope_detail)
  loop
    suite := 'ROADMAP_SCOPE';
    test_name := rec.scope_key;
    passed := true;
    details := rec.scope_detail;
    return next;
  end loop;

  -- B. Existing table inventory.
  for rec in
    select *
    from (
      values
      ('notifications', 'Legacy staff-facing notification inbox'),
      ('guest_notifications', 'Day 15 guest-visible status history'),
      ('activity_logs', 'Day 3 tenant activity ledger'),
      ('support_tickets', 'Day 9 support ticket header'),
      ('support_ticket_messages', 'Day 9 support conversation'),
      ('announcements', 'Day 9 platform/hotel announcements'),
      ('hotel_settings', 'Day 8 hotel settings'),
      ('hotels', 'Tenant and timezone authority'),
      ('hotel_info', 'Guest-facing hotel profile'),
      ('staff', 'Hotel staff identity'),
      ('role_permissions', 'Role permission matrix'),
      ('platform_admins', 'Platform administration'),
      ('reservations', 'Critical reservation source'),
      ('reservation_events', 'Reservation lifecycle event source'),
      ('activity_logs', 'Reservation activity source'),
      ('payments', 'Critical payment source'),
      ('payment_collections', 'Cashier collection source'),
      ('payment_events', 'Payment event source when available'),
      ('payment_webhook_events', 'Provider webhook source when available'),
      ('service_requests', 'Critical guest-service source'),
      ('service_request_events', 'Service workflow event source'),
      ('guest_sessions', 'Guest stay scope'),
      ('hotel_subscriptions', 'Commercial lifecycle source'),
      ('subscription_events', 'Commercial event source')
    ) expected(table_name, purpose)
  loop
    select to_regclass('public.' || rec.table_name) is not null
    into v_exists;

    suite := 'LOCKED_TABLE_BASELINE';
    test_name := rec.table_name;
    passed := v_exists;
    details := case
      when v_exists then 'PRESENT — ' || rec.purpose
      else 'MISSING LOCKED BASELINE — ' || rec.purpose
    end;
    return next;
  end loop;

  -- C. Existing column inventory.
  for rec in
    select *
    from (
      values
      ('notifications', 'id'),
      ('notifications', 'hotel_id'),
      ('notifications', 'room_id'),
      ('notifications', 'guest_id'),
      ('notifications', 'type'),
      ('notifications', 'title'),
      ('notifications', 'message'),
      ('notifications', 'is_read'),
      ('notifications', 'created_at'),
      ('guest_notifications', 'id'),
      ('guest_notifications', 'hotel_id'),
      ('guest_notifications', 'guest_session_id'),
      ('guest_notifications', 'source_type'),
      ('guest_notifications', 'source_id'),
      ('guest_notifications', 'event_key'),
      ('guest_notifications', 'title'),
      ('guest_notifications', 'message'),
      ('guest_notifications', 'status'),
      ('guest_notifications', 'metadata'),
      ('guest_notifications', 'created_at'),
      ('activity_logs', 'id'),
      ('activity_logs', 'hotel_id'),
      ('activity_logs', 'actor_user_id'),
      ('activity_logs', 'actor_role'),
      ('activity_logs', 'action'),
      ('activity_logs', 'entity_type'),
      ('activity_logs', 'entity_id'),
      ('activity_logs', 'description'),
      ('activity_logs', 'before_data'),
      ('activity_logs', 'after_data'),
      ('activity_logs', 'metadata'),
      ('activity_logs', 'created_at'),
      ('support_tickets', 'id'),
      ('support_tickets', 'hotel_id'),
      ('support_tickets', 'ticket_number'),
      ('support_tickets', 'subject'),
      ('support_tickets', 'description'),
      ('support_tickets', 'category'),
      ('support_tickets', 'priority'),
      ('support_tickets', 'status'),
      ('support_tickets', 'created_by_user_id'),
      ('support_tickets', 'assigned_to_user_id'),
      ('support_tickets', 'created_at'),
      ('support_tickets', 'updated_at'),
      ('support_tickets', 'metadata'),
      ('support_ticket_messages', 'id'),
      ('support_ticket_messages', 'ticket_id'),
      ('support_ticket_messages', 'author_user_id'),
      ('support_ticket_messages', 'message'),
      ('support_ticket_messages', 'created_at'),
      ('announcements', 'id'),
      ('announcements', 'scope'),
      ('announcements', 'hotel_id'),
      ('announcements', 'title'),
      ('announcements', 'body'),
      ('announcements', 'severity'),
      ('announcements', 'status'),
      ('announcements', 'starts_at'),
      ('announcements', 'ends_at'),
      ('announcements', 'created_by_user_id'),
      ('announcements', 'metadata'),
      ('announcements', 'created_at'),
      ('announcements', 'updated_at'),
      ('hotel_settings', 'hotel_id'),
      ('hotel_settings', 'currency_code'),
      ('hotel_settings', 'tax_rate'),
      ('hotel_settings', 'service_charge_rate'),
      ('hotel_settings', 'invoice_prefix'),
      ('hotel_settings', 'reservation_prefix'),
      ('hotel_settings', 'trial_started_at'),
      ('hotel_settings', 'trial_ends_at'),
      ('hotel_settings', 'created_at'),
      ('hotel_settings', 'updated_at'),
      ('hotels', 'id'),
      ('hotels', 'hotel_name'),
      ('hotels', 'status'),
      ('hotels', 'timezone'),
      ('hotels', 'created_at'),
      ('hotels', 'updated_at'),
      ('reservations', 'id'),
      ('reservations', 'hotel_id'),
      ('reservations', 'reservation_number'),
      ('reservations', 'status'),
      ('reservations', 'arrival_date'),
      ('reservations', 'departure_date'),
      ('reservations', 'created_at'),
      ('reservations', 'updated_at'),
      ('payments', 'id'),
      ('payments', 'hotel_id'),
      ('payments', 'payment_status'),
      ('payments', 'amount'),
      ('payments', 'created_at'),
      ('service_requests', 'id'),
      ('service_requests', 'hotel_id'),
      ('service_requests', 'guest_session_id'),
      ('service_requests', 'status'),
      ('service_requests', 'request_type'),
      ('service_requests', 'department'),
      ('service_requests', 'created_at'),
      ('service_requests', 'updated_at')
    ) expected(table_name, column_name)
  loop
    select exists (
      select 1
      from information_schema.columns c
      where c.table_schema = 'public'
        and c.table_name = rec.table_name
        and c.column_name = rec.column_name
    )
    into v_exists;

    suite := 'LOCKED_COLUMN_BASELINE';
    test_name := rec.table_name || '.' || rec.column_name;
    passed := v_exists;
    details := case
      when v_exists then 'PRESENT'
      else 'MISSING OR SCHEMA-DIFFERENT — confirm before Migration 056'
    end;
    return next;
  end loop;

  -- D. RLS, policy and authenticated-grant inventory.
  for rec in
    select table_name
    from (
      values
      ('notifications'),
      ('guest_notifications'),
      ('activity_logs'),
      ('support_tickets'),
      ('support_ticket_messages'),
      ('announcements'),
      ('hotel_settings'),
      ('reservations'),
      ('payments'),
      ('service_requests')
    ) expected(table_name)
  loop
    select to_regclass(format('public.%I', rec.table_name))
    into v_table_regclass;

    if v_table_regclass is null then
      suite := 'RLS_BASELINE';
      test_name := rec.table_name || '.rls_enabled';
      passed := false;
      details := 'TABLE MISSING — RLS cannot be evaluated.';
      return next;

      suite := 'RLS_BASELINE';
      test_name := rec.table_name || '.policy_count';
      passed := false;
      details := 'TABLE MISSING — policies cannot be evaluated.';
      return next;

      suite := 'RLS_BASELINE';
      test_name := rec.table_name || '.authenticated_select';
      passed := false;
      details := 'TABLE MISSING — authenticated privilege cannot be evaluated.';
      return next;

      continue;
    end if;

    select coalesce(c.relrowsecurity, false)
    into v_exists
    from pg_class c
    where c.oid = v_table_regclass;

    suite := 'RLS_BASELINE';
    test_name := rec.table_name || '.rls_enabled';
    passed := coalesce(v_exists, false);
    details := case
      when coalesce(v_exists, false) then 'RLS ENABLED'
      else 'RLS MISSING'
    end;
    return next;

    select count(*)
    into v_count
    from pg_policies p
    where p.schemaname = 'public'
      and p.tablename = rec.table_name;

    suite := 'RLS_BASELINE';
    test_name := rec.table_name || '.policy_count';
    passed := v_count > 0;
    details := format('%s policy/policies.', v_count);
    return next;

    select has_table_privilege(
      'authenticated',
      v_table_regclass,
      'SELECT'
    )
    into v_exists;

    suite := 'RLS_BASELINE';
    test_name := rec.table_name || '.authenticated_select';
    passed := coalesce(v_exists, false);
    details := case
      when coalesce(v_exists, false) then 'Authenticated SELECT granted; RLS remains authoritative.'
      else 'Authenticated SELECT not granted.'
    end;
    return next;
  end loop;

  -- E. Existing function/RPC inventory.
  for rec in
    select *
    from (
      values
      ('private.user_has_hotel_access(uuid)', 'Tenant membership guard'),
      ('private.user_has_hotel_role(uuid,text[])', 'Role guard'),
      ('private.is_platform_admin()', 'Platform-admin guard'),
      ('public.create_support_ticket(uuid,text,text,text,text)', 'Support ticket creation'),
      ('public.add_support_ticket_message(uuid,text)', 'Support conversation'),
      ('public.update_support_ticket_status(uuid,text,text,uuid)', 'Support status transition'),
      ('public.create_announcement(uuid,text,text,text,text,timestamptz,timestamptz,jsonb)', 'Announcement management'),
      ('public.get_platform_admin_console()', 'Platform support and announcement console'),
      ('public.create_guest_service_request(text,text,text)', 'Guest service request source'),
      ('public.place_guest_food_order(text,jsonb,text)', 'Guest food order source'),
      ('public.get_report_service_sla(uuid,date,date)', 'Service analytics source')
    ) expected(signature, purpose)
  loop
    select to_regprocedure(rec.signature) is not null
    into v_exists;

    suite := 'LOCKED_FUNCTION_BASELINE';
    test_name := rec.signature;
    passed := v_exists;
    details := case
      when v_exists then 'PRESENT — ' || rec.purpose
      else 'MISSING OR SIGNATURE-DIFFERENT — ' || rec.purpose
    end;
    return next;
  end loop;

  -- F. Planned Day 17 table collision checks.
  for rec in
    select *
    from (
      values
      ('notification_event_catalog', 'Canonical event definitions'),
      ('notification_preferences', 'Hotel/user channel preferences'),
      ('notification_templates', 'Localized notification templates'),
      ('notification_template_versions', 'Template publication history'),
      ('notification_outbox', 'Transactional delivery queue'),
      ('notification_deliveries', 'Recipient/channel delivery ledger'),
      ('notification_delivery_attempts', 'Retry/failure attempt log'),
      ('notification_dead_letters', 'Terminal delivery failures'),
      ('notification_recipients', 'Recipient-level inbox/read state'),
      ('email_adapter_configs', 'Hotel/platform email adapter configuration'),
      ('whatsapp_templates', 'Manual WhatsApp template library'),
      ('business_day_settings', 'Business-day cutoff and timezone policy')
    ) proposed(table_name, purpose)
  loop
    select to_regclass('public.' || rec.table_name) is null
    into v_exists;

    suite := 'DAY17_TABLE_COLLISION';
    test_name := rec.table_name;
    passed := v_exists;
    details := case
      when v_exists then 'PLANNED GAP / NAME AVAILABLE — ' || rec.purpose
      else 'OBJECT ALREADY EXISTS — inspect before Migration 056'
    end;
    return next;
  end loop;

  -- G. Planned Day 17 RPC collision checks.
  for rec in
    select *
    from (
      values
      ('public.get_notification_inbox(uuid,integer,timestamptz)', 'Trusted hotel-scoped inbox'),
      ('public.mark_notification_read(uuid)', 'Recipient-scoped read transition'),
      ('public.mark_all_notifications_read(uuid)', 'Hotel/user scoped bulk read'),
      ('public.upsert_notification_preferences(uuid,jsonb)', 'Preference mutation'),
      ('public.publish_notification_template(uuid,text,text,jsonb)', 'Template publication'),
      ('public.enqueue_notification_event(uuid,text,uuid,jsonb)', 'Canonical event/outbox creation'),
      ('public.process_notification_outbox(integer)', 'Delivery dispatcher'),
      ('public.retry_notification_delivery(uuid)', 'Controlled retry'),
      ('public.get_activity_timeline(uuid,timestamptz,timestamptz,jsonb)', 'Trusted activity UI feed'),
      ('public.get_hotel_system_settings(uuid)', 'Trusted settings read'),
      ('public.update_hotel_system_settings(uuid,jsonb)', 'Trusted settings update'),
      ('private.resolve_hotel_business_date(uuid,timestamptz)', 'Business-date authority')
    ) proposed(signature, purpose)
  loop
    select to_regprocedure(rec.signature) is null
    into v_exists;

    suite := 'DAY17_FUNCTION_COLLISION';
    test_name := rec.signature;
    passed := v_exists;
    details := case
      when v_exists then 'PLANNED GAP / SIGNATURE AVAILABLE — ' || rec.purpose
      else 'FUNCTION ALREADY EXISTS — inspect before Migration 056'
    end;
    return next;
  end loop;

  -- H. Realtime, security and data-quality boundary checks.
  suite := 'REALTIME_AND_SECURITY';
  test_name := 'notifications_realtime_publication';
  select exists (
    select 1
    from pg_publication_tables pt
    where pt.pubname = 'supabase_realtime'
      and pt.schemaname = 'public'
      and pt.tablename = 'notifications'
  )
  into v_exists;
  passed := v_exists;
  details := case
    when v_exists then 'Legacy notifications is published to Supabase Realtime.'
    else 'GAP — Navbar subscription cannot receive postgres_changes until publication is installed.'
  end;
  return next;

  suite := 'REALTIME_AND_SECURITY';
  test_name := 'guest_notifications_realtime_publication';
  select exists (
    select 1
    from pg_publication_tables pt
    where pt.pubname = 'supabase_realtime'
      and pt.schemaname = 'public'
      and pt.tablename = 'guest_notifications'
  )
  into v_exists;
  passed := true;
  details := case
    when v_exists then 'PRESENT — guest notifications are realtime enabled.'
    else 'PLANNED GAP — decide whether guest status history requires realtime publication.'
  end;
  return next;

  suite := 'REALTIME_AND_SECURITY';
  test_name := 'notifications_anon_insert_blocked';
  select to_regclass('public.notifications')
  into v_table_regclass;
  if v_table_regclass is null then
    passed := false;
    details := 'TABLE MISSING — anonymous insert boundary cannot be evaluated.';
  else
    select not has_table_privilege(
      'anon',
      v_table_regclass,
      'INSERT'
    )
    into v_exists;
    passed := coalesce(v_exists, false);
    details := case
      when coalesce(v_exists, false) then 'Anonymous direct insert is blocked.'
      else 'SECURITY GAP — anonymous direct insert is granted.'
    end;
  end if;
  return next;

  suite := 'REALTIME_AND_SECURITY';
  test_name := 'activity_logs_anon_select_blocked';
  select to_regclass('public.activity_logs')
  into v_table_regclass;
  if v_table_regclass is null then
    passed := false;
    details := 'TABLE MISSING — anonymous activity-log boundary cannot be evaluated.';
  else
    select not has_table_privilege(
      'anon',
      v_table_regclass,
      'SELECT'
    )
    into v_exists;
    passed := coalesce(v_exists, false);
    details := case
      when coalesce(v_exists, false) then 'Anonymous activity-log reads are blocked.'
      else 'SECURITY GAP — anonymous activity-log read is granted.'
    end;
  end if;
  return next;

  suite := 'REALTIME_AND_SECURITY';
  test_name := 'support_tickets_anon_access_blocked';
  select to_regclass('public.support_tickets')
  into v_table_regclass;
  if v_table_regclass is null then
    passed := false;
    details := 'TABLE MISSING — anonymous support-ticket boundary cannot be evaluated.';
  else
    select not (
      has_table_privilege('anon', v_table_regclass, 'SELECT')
      or has_table_privilege('anon', v_table_regclass, 'INSERT')
      or has_table_privilege('anon', v_table_regclass, 'UPDATE')
    )
    into v_exists;
    passed := coalesce(v_exists, false);
    details := case
      when coalesce(v_exists, false) then 'Anonymous support-ticket access is blocked.'
      else 'SECURITY GAP — anonymous support-ticket privilege exists.'
    end;
  end if;
  return next;

  suite := 'REALTIME_AND_SECURITY';
  test_name := 'notification_preference_foundation_absent';
  passed := to_regclass('public.notification_preferences') is null;
  details := case
    when passed then 'PLANNED GAP — preferences will be installed by Day 17.'
    else 'Existing preference table requires compatibility review.'
  end;
  return next;

  suite := 'REALTIME_AND_SECURITY';
  test_name := 'notification_template_foundation_absent';
  passed := to_regclass('public.notification_templates') is null;
  details := case
    when passed then 'PLANNED GAP — templates will be installed by Day 17.'
    else 'Existing template table requires compatibility review.'
  end;
  return next;

  suite := 'REALTIME_AND_SECURITY';
  test_name := 'delivery_attempt_foundation_absent';
  passed := to_regclass('public.notification_delivery_attempts') is null;
  details := case
    when passed then 'PLANNED GAP — retry/failure ledger will be installed by Day 17.'
    else 'Existing attempt table requires compatibility review.'
  end;
  return next;

  suite := 'DATA_QUALITY';
  test_name := 'hotels_timezone_nonblank';
  select count(*)
  into v_count
  from public.hotels h
  where h.timezone is null
     or length(trim(h.timezone)) = 0;
  passed := v_count = 0;
  details := format('%s hotel(s) have a missing timezone.', v_count);
  return next;

  suite := 'DATA_QUALITY';
  test_name := 'hotel_settings_coverage';
  select count(*)
  into v_count
  from public.hotels h
  where h.status <> 'archived'
    and not exists (
      select 1
      from public.hotel_settings hs
      where hs.hotel_id = h.id
    );
  passed := v_count = 0;
  details := format('%s non-archived hotel(s) have no hotel_settings row.', v_count);
  return next;

  suite := 'DATA_QUALITY';
  test_name := 'notifications_hotel_scope';
  select count(*)
  into v_count
  from public.notifications n
  where n.hotel_id is null
     or not exists (
       select 1
       from public.hotels h
       where h.id = n.hotel_id
     );
  passed := v_count = 0;
  details := format('%s notification row(s) violate hotel scope.', v_count);
  return next;

  suite := 'DATA_QUALITY';
  test_name := 'guest_notifications_session_scope';
  select count(*)
  into v_count
  from public.guest_notifications gn
  left join public.guest_sessions gs
    on gs.id = gn.guest_session_id
   and gs.hotel_id = gn.hotel_id
  where gs.id is null;
  passed := v_count = 0;
  details := format('%s guest notification row(s) have no matching hotel/session.', v_count);
  return next;

  suite := 'DATA_QUALITY';
  test_name := 'activity_logs_hotel_scope';
  select count(*)
  into v_count
  from public.activity_logs al
  where al.hotel_id is null
     or not exists (
       select 1
       from public.hotels h
       where h.id = al.hotel_id
     );
  passed := v_count = 0;
  details := format('%s activity row(s) violate hotel scope.', v_count);
  return next;

  suite := 'DATA_QUALITY';
  test_name := 'support_ticket_hotel_scope';
  select count(*)
  into v_count
  from public.support_tickets st
  where st.hotel_id is not null
    and not exists (
      select 1
      from public.hotels h
      where h.id = st.hotel_id
    );
  passed := v_count = 0;
  details := format('%s support ticket(s) reference a missing hotel.', v_count);
  return next;

  suite := 'DAY17_GAP_SUMMARY';
  test_name := 'critical_event_notification_triggers';
  select count(*)
  into v_count
  from pg_trigger t
  join pg_class c
    on c.oid = t.tgrelid
  join pg_namespace n
    on n.oid = c.relnamespace
  where not t.tgisinternal
    and n.nspname = 'public'
    and c.relname in ('reservations', 'payments', 'service_requests')
    and (
      pg_get_triggerdef(t.oid) ilike '%notification%'
      or pg_get_triggerdef(t.oid) ilike '%outbox%'
    );
  passed := true;
  details := case
    when v_count > 0 then format('PRESENT — %s notification/outbox trigger(s) detected.', v_count)
    else 'PLANNED GAP — no critical reservation/payment/service notification trigger detected.'
  end;
  return next;

  suite := 'DAY17_GAP_SUMMARY';
  test_name := 'business_day_authority';
  select count(*)
  into v_count
  from pg_proc p
  join pg_namespace n
    on n.oid = p.pronamespace
  where n.nspname in ('public', 'private')
    and (
      p.proname ilike '%business%day%'
      or case
        when p.prokind in ('f', 'p')
          then pg_get_functiondef(p.oid) ilike '%business day%'
        else false
      end
    );
  passed := true;
  details := case
    when v_count > 0 then format('PRESENT — %s business-day related function(s) detected.', v_count)
    else 'PLANNED GAP — no canonical hotel business-date resolver detected.'
  end;
  return next;
end;
$function$;

revoke all on function private.day17_audit_069_preflight_rev3()
from public, anon, authenticated;

commit;

select suite, test_name, passed, details
from private.day17_audit_069_preflight_rev3()
order by suite, test_name;
