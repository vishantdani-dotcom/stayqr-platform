-- ============================================================================
-- StayQR v1.0
-- Day 17 Audit 071 REV1
-- Final Consolidated Notifications, Activity, Support and Settings Acceptance
--
-- ROADMAP SCOPE
-- In-app realtime; notification preferences/templates; email adapters;
-- manual WhatsApp templates; retry/failure log; activity log UI;
-- support tickets; announcements; hotel settings; timezone/business-day
-- consistency.
--
-- ROADMAP EXIT GATE
-- Critical reservation/payment/service events create auditable notifications
-- without cross-hotel leakage.
--
-- ACCEPTED PREREQUISITES
-- - Audit 069 preflight completed and reviewed.
-- - Migration 056 REV2 accepted: 275/275.
-- - Audit 070 REV2 runtime accepted: 75/75.
-- - Migration 057 accepted: 37/37.
-- - Operations Centre frontend source gate passed.
-- - Lint passed with 0 errors and 7 pre-existing warnings.
-- - Production build passed.
-- - Controlled browser acceptance completed, including hotel switching.
--
-- SAFETY
-- - Replays accepted read-only/reversible acceptance helpers.
-- - Adds/replaces one private Audit 071 helper only.
-- - Final smoke reads use a temporary JWT context and restore it.
-- - No permanent hotel business fixture is inserted.
--
-- EXPECTED RESULT
-- 420 rows
-- 420 passed = true
-- 0 failures
-- ============================================================================

begin;

set local lock_timeout = '10s';
set local statement_timeout = '600s';

select pg_advisory_xact_lock(
  hashtext('stayqr:202608050071:day17-final-consolidated-rev1')
);

create schema if not exists private;

do $preflight$
declare
  v_missing text;
begin
  select string_agg(signature, ', ' order by signature)
  into v_missing
  from (
    values
      (
        'private.day17_migration_056_acceptance_rev2()',
        to_regprocedure(
          'private.day17_migration_056_acceptance_rev2()'
        ) is not null
      ),
      (
        'private.day17_a070_runtime_acceptance_rev2()',
        to_regprocedure(
          'private.day17_a070_runtime_acceptance_rev2()'
        ) is not null
      ),
      (
        'private.day17_migration_057_acceptance_rev1()',
        to_regprocedure(
          'private.day17_migration_057_acceptance_rev1()'
        ) is not null
      ),
      (
        'public.get_notification_inbox(uuid,integer,timestamptz)',
        to_regprocedure(
          'public.get_notification_inbox(uuid,integer,timestamp with time zone)'
        ) is not null
      ),
      (
        'public.get_activity_timeline(uuid,timestamptz,timestamptz,jsonb)',
        to_regprocedure(
          'public.get_activity_timeline(uuid,timestamp with time zone,timestamp with time zone,jsonb)'
        ) is not null
      ),
      (
        'public.get_hotel_system_settings(uuid)',
        to_regprocedure(
          'public.get_hotel_system_settings(uuid)'
        ) is not null
      ),
      (
        'public.get_support_workspace(uuid)',
        to_regprocedure(
          'public.get_support_workspace(uuid)'
        ) is not null
      ),
      (
        'public.get_active_announcements(uuid)',
        to_regprocedure(
          'public.get_active_announcements(uuid)'
        ) is not null
      ),
      (
        'public.upsert_email_adapter_config(uuid,jsonb)',
        to_regprocedure(
          'public.upsert_email_adapter_config(uuid,jsonb)'
        ) is not null
      ),
      (
        'public.upsert_manual_whatsapp_template(uuid,jsonb)',
        to_regprocedure(
          'public.upsert_manual_whatsapp_template(uuid,jsonb)'
        ) is not null
      )
  ) required(signature, exists_now)
  where not exists_now;

  if v_missing is not null then
    raise exception
      'Audit 071 stopped. Missing prerequisite(s): %',
      v_missing;
  end if;
end;
$preflight$;

create or replace function private.day17_a071_final_consolidated_acceptance_rev1()
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
  v_admin_user uuid;
  v_hotel_id uuid;
  v_hotel_name text;

  v_previous_sub text :=
    current_setting('request.jwt.claim.sub', true);
  v_previous_role text :=
    current_setting('request.jwt.claim.role', true);
  v_previous_claims text :=
    current_setting('request.jwt.claims', true);

  v_inbox jsonb;
  v_activity jsonb;
  v_settings jsonb;
  v_support jsonb;
  v_announcements jsonb;
  v_runtime_error text;
begin
  -- ========================================================================
  -- A. Replay all accepted Migration 056 contracts: 275 rows.
  -- ========================================================================
  return query
  select
    'M056_' || accepted.suite,
    accepted.test_name,
    accepted.passed,
    accepted.details
  from private.day17_migration_056_acceptance_rev2() accepted;

  -- ========================================================================
  -- B. Replay complete reversible notification runtime: 75 rows.
  -- ========================================================================
  return query
  select
    'A070_' || accepted.suite,
    accepted.test_name,
    accepted.passed,
    accepted.details
  from private.day17_a070_runtime_acceptance_rev2() accepted;

  -- ========================================================================
  -- C. Replay Migration 057 privilege/RPC hotfix: 37 rows.
  -- ========================================================================
  return query
  select
    'M057_' || accepted.suite,
    accepted.test_name,
    accepted.passed,
    accepted.details
  from private.day17_migration_057_acceptance_rev1() accepted;

  -- ========================================================================
  -- D. Final fixed prerequisite, privilege and data-plane checks: 28 rows.
  -- ========================================================================
  return query
  select
    final_checks.suite,
    final_checks.test_name,
    final_checks.passed,
    final_checks.details
  from (
    values
      -- FINAL_CHECK_01
      (
        'DAY17_FINAL_PREREQUISITE'::text,
        'm056_acceptance_helper'::text,
        to_regprocedure(
          'private.day17_migration_056_acceptance_rev2()'
        ) is not null,
        'Migration 056 accepted helper is installed.'::text
      ),
      -- FINAL_CHECK_02
      (
        'DAY17_FINAL_PREREQUISITE',
        'a070_runtime_helper',
        to_regprocedure(
          'private.day17_a070_runtime_acceptance_rev2()'
        ) is not null,
        'Audit 070 REV2 runtime helper is installed.'
      ),
      -- FINAL_CHECK_03
      (
        'DAY17_FINAL_PREREQUISITE',
        'm057_acceptance_helper',
        to_regprocedure(
          'private.day17_migration_057_acceptance_rev1()'
        ) is not null,
        'Migration 057 acceptance helper is installed.'
      ),
      -- FINAL_CHECK_04
      (
        'DAY17_FINAL_PREREQUISITE',
        'notification_inbox_rpc',
        to_regprocedure(
          'public.get_notification_inbox(uuid,integer,timestamp with time zone)'
        ) is not null,
        'Trusted notification inbox RPC is installed.'
      ),
      -- FINAL_CHECK_05
      (
        'DAY17_FINAL_PREREQUISITE',
        'activity_timeline_rpc',
        to_regprocedure(
          'public.get_activity_timeline(uuid,timestamp with time zone,timestamp with time zone,jsonb)'
        ) is not null,
        'Trusted activity timeline RPC is installed.'
      ),
      -- FINAL_CHECK_06
      (
        'DAY17_FINAL_PREREQUISITE',
        'system_settings_rpc',
        to_regprocedure(
          'public.get_hotel_system_settings(uuid)'
        ) is not null,
        'Trusted system-settings reader is installed.'
      ),
      -- FINAL_CHECK_07
      (
        'DAY17_FINAL_PREREQUISITE',
        'support_workspace_rpc',
        to_regprocedure(
          'public.get_support_workspace(uuid)'
        ) is not null,
        'Trusted support workspace RPC is installed.'
      ),
      -- FINAL_CHECK_08
      (
        'DAY17_FINAL_PREREQUISITE',
        'announcements_rpc',
        to_regprocedure(
          'public.get_active_announcements(uuid)'
        ) is not null,
        'Trusted announcements RPC is installed.'
      ),
      -- FINAL_CHECK_09
      (
        'DAY17_FINAL_PREREQUISITE',
        'email_adapter_writer_rpc',
        to_regprocedure(
          'public.upsert_email_adapter_config(uuid,jsonb)'
        ) is not null,
        'Trusted email adapter writer is installed.'
      ),
      -- FINAL_CHECK_10
      (
        'DAY17_FINAL_PREREQUISITE',
        'manual_whatsapp_writer_rpc',
        to_regprocedure(
          'public.upsert_manual_whatsapp_template(uuid,jsonb)'
        ) is not null,
        'Trusted manual WhatsApp writer is installed.'
      ),
      -- FINAL_CHECK_11
      (
        'DAY17_FINAL_PRIVILEGE',
        'management_helper_authenticated_execute',
        has_function_privilege(
          'authenticated',
          'private.day17_can_manage_hotel(uuid)',
          'EXECUTE'
        ),
        'Authenticated users can evaluate management RLS safely.'
      ),
      -- FINAL_CHECK_12
      (
        'DAY17_FINAL_PRIVILEGE',
        'management_helper_anon_blocked',
        not has_function_privilege(
          'anon',
          'private.day17_can_manage_hotel(uuid)',
          'EXECUTE'
        ),
        'Anonymous execution remains blocked.'
      ),
      -- FINAL_CHECK_13
      (
        'DAY17_FINAL_PRIVILEGE',
        'notification_inbox_authenticated_execute',
        has_function_privilege(
          'authenticated',
          'public.get_notification_inbox(uuid,integer,timestamp with time zone)',
          'EXECUTE'
        ),
        'Authenticated inbox execution is granted.'
      ),
      -- FINAL_CHECK_14
      (
        'DAY17_FINAL_PRIVILEGE',
        'notification_inbox_anon_blocked',
        not has_function_privilege(
          'anon',
          'public.get_notification_inbox(uuid,integer,timestamp with time zone)',
          'EXECUTE'
        ),
        'Anonymous inbox execution is blocked.'
      ),
      -- FINAL_CHECK_15
      (
        'DAY17_FINAL_PRIVILEGE',
        'settings_update_authenticated_execute',
        has_function_privilege(
          'authenticated',
          'public.update_hotel_system_settings(uuid,jsonb)',
          'EXECUTE'
        ),
        'Authenticated settings update execution is granted.'
      ),
      -- FINAL_CHECK_16
      (
        'DAY17_FINAL_PRIVILEGE',
        'settings_update_anon_blocked',
        not has_function_privilege(
          'anon',
          'public.update_hotel_system_settings(uuid,jsonb)',
          'EXECUTE'
        ),
        'Anonymous settings updates are blocked.'
      ),
      -- FINAL_CHECK_17
      (
        'DAY17_FINAL_PRIVILEGE',
        'email_adapter_writer_authenticated_execute',
        has_function_privilege(
          'authenticated',
          'public.upsert_email_adapter_config(uuid,jsonb)',
          'EXECUTE'
        ),
        'Authenticated email adapter writes use the trusted RPC.'
      ),
      -- FINAL_CHECK_18
      (
        'DAY17_FINAL_PRIVILEGE',
        'email_adapter_writer_anon_blocked',
        not has_function_privilege(
          'anon',
          'public.upsert_email_adapter_config(uuid,jsonb)',
          'EXECUTE'
        ),
        'Anonymous email adapter writes are blocked.'
      ),
      -- FINAL_CHECK_19
      (
        'DAY17_FINAL_PRIVILEGE',
        'whatsapp_writer_authenticated_execute',
        has_function_privilege(
          'authenticated',
          'public.upsert_manual_whatsapp_template(uuid,jsonb)',
          'EXECUTE'
        ),
        'Authenticated manual WhatsApp writes use the trusted RPC.'
      ),
      -- FINAL_CHECK_20
      (
        'DAY17_FINAL_PRIVILEGE',
        'whatsapp_writer_anon_blocked',
        not has_function_privilege(
          'anon',
          'public.upsert_manual_whatsapp_template(uuid,jsonb)',
          'EXECUTE'
        ),
        'Anonymous manual WhatsApp writes are blocked.'
      ),
      -- FINAL_CHECK_21
      (
        'DAY17_FINAL_DATA_PLANE',
        'notification_recipients_rls',
        coalesce(
          (
            select c.relrowsecurity
            from pg_catalog.pg_class c
            join pg_catalog.pg_namespace n
              on n.oid = c.relnamespace
            where n.nspname = 'public'
              and c.relname = 'notification_recipients'
          ),
          false
        ),
        'notification_recipients has RLS enabled.'
      ),
      -- FINAL_CHECK_22
      (
        'DAY17_FINAL_DATA_PLANE',
        'notification_deliveries_rls',
        coalesce(
          (
            select c.relrowsecurity
            from pg_catalog.pg_class c
            join pg_catalog.pg_namespace n
              on n.oid = c.relnamespace
            where n.nspname = 'public'
              and c.relname = 'notification_deliveries'
          ),
          false
        ),
        'notification_deliveries has RLS enabled.'
      ),
      -- FINAL_CHECK_23
      (
        'DAY17_FINAL_DATA_PLANE',
        'activity_logs_rls',
        coalesce(
          (
            select c.relrowsecurity
            from pg_catalog.pg_class c
            join pg_catalog.pg_namespace n
              on n.oid = c.relnamespace
            where n.nspname = 'public'
              and c.relname = 'activity_logs'
          ),
          false
        ),
        'activity_logs has RLS enabled.'
      ),
      -- FINAL_CHECK_24
      (
        'DAY17_FINAL_DATA_PLANE',
        'email_adapter_configs_rls',
        coalesce(
          (
            select c.relrowsecurity
            from pg_catalog.pg_class c
            join pg_catalog.pg_namespace n
              on n.oid = c.relnamespace
            where n.nspname = 'public'
              and c.relname = 'email_adapter_configs'
          ),
          false
        ),
        'email_adapter_configs has RLS enabled.'
      ),
      -- FINAL_CHECK_25
      (
        'DAY17_FINAL_DATA_PLANE',
        'whatsapp_templates_rls',
        coalesce(
          (
            select c.relrowsecurity
            from pg_catalog.pg_class c
            join pg_catalog.pg_namespace n
              on n.oid = c.relnamespace
            where n.nspname = 'public'
              and c.relname = 'whatsapp_templates'
          ),
          false
        ),
        'whatsapp_templates has RLS enabled.'
      ),
      -- FINAL_CHECK_26
      (
        'DAY17_FINAL_DATA_PLANE',
        'notification_recipients_realtime',
        exists (
          select 1
          from pg_catalog.pg_publication_tables ppt
          where ppt.pubname = 'supabase_realtime'
            and ppt.schemaname = 'public'
            and ppt.tablename = 'notification_recipients'
        ),
        'notification_recipients is in the realtime publication.'
      ),
      -- FINAL_CHECK_27
      (
        'DAY17_FINAL_DATA_PLANE',
        'notification_deliveries_realtime',
        exists (
          select 1
          from pg_catalog.pg_publication_tables ppt
          where ppt.pubname = 'supabase_realtime'
            and ppt.schemaname = 'public'
            and ppt.tablename = 'notification_deliveries'
        ),
        'notification_deliveries is in the realtime publication.'
      ),
      -- FINAL_CHECK_28
      (
        'DAY17_FINAL_DATA_PLANE',
        'email_adapter_select_policy_uses_management_helper',
        exists (
          select 1
          from pg_catalog.pg_policy pol
          join pg_catalog.pg_class c
            on c.oid = pol.polrelid
          join pg_catalog.pg_namespace n
            on n.oid = c.relnamespace
          where n.nspname = 'public'
            and c.relname = 'email_adapter_configs'
            and pol.polname = 'email_adapter_configs_select_day17'
            and pg_catalog.pg_get_expr(
              pol.polqual,
              pol.polrelid
            ) ilike '%day17_can_manage_hotel%'
        ),
        'Email adapter reads remain management-scoped.'
      )
  ) final_checks(suite, test_name, passed, details);

  -- ========================================================================
  -- E. Final real authorized read smoke with restored JWT state: 5 rows.
  -- ========================================================================

  select pa.user_id
  into v_admin_user
  from public.platform_admins pa
  join auth.users au
    on au.id = pa.user_id
  where pa.status = 'active'
    and coalesce(
      au.banned_until,
      '-infinity'::timestamptz
    ) <= now()
  order by pa.created_at, pa.user_id
  limit 1;

  select h.id, h.hotel_name
  into v_hotel_id, v_hotel_name
  from public.hotels h
  where h.status = 'active'
  order by h.created_at, h.id
  limit 1;

  begin
    if v_admin_user is null then
      raise exception 'No active platform admin was available.';
    end if;

    if v_hotel_id is null then
      raise exception 'No active hotel was available.';
    end if;

    perform set_config(
      'request.jwt.claim.sub',
      v_admin_user::text,
      true
    );
    perform set_config(
      'request.jwt.claim.role',
      'authenticated',
      true
    );
    perform set_config(
      'request.jwt.claims',
      jsonb_build_object(
        'sub', v_admin_user,
        'role', 'authenticated'
      )::text,
      true
    );

    v_inbox := public.get_notification_inbox(
      v_hotel_id,
      10,
      null
    );

    v_activity := public.get_activity_timeline(
      v_hotel_id,
      now() - interval '30 days',
      now(),
      jsonb_build_object('limit', 25)
    );

    v_settings := public.get_hotel_system_settings(
      v_hotel_id
    );

    v_support := public.get_support_workspace(
      v_hotel_id
    );

    v_announcements := public.get_active_announcements(
      v_hotel_id
    );
  exception
    when others then
      v_runtime_error := format(
        '%s [%s]',
        sqlerrm,
        sqlstate
      );
  end;

  perform set_config(
    'request.jwt.claim.sub',
    coalesce(v_previous_sub, ''),
    true
  );
  perform set_config(
    'request.jwt.claim.role',
    coalesce(v_previous_role, ''),
    true
  );
  perform set_config(
    'request.jwt.claims',
    coalesce(v_previous_claims, '{}'),
    true
  );

  return query
  select
    smoke.suite,
    smoke.test_name,
    smoke.passed,
    smoke.details
  from (
    values
      -- FINAL_CHECK_29
      (
        'DAY17_FINAL_RUNTIME'::text,
        'notification_inbox_real_authorized_read'::text,
        v_runtime_error is null
          and jsonb_typeof(v_inbox) = 'object',
        coalesce(
          v_runtime_error,
          format(
            '%s / %s',
            coalesce(v_hotel_name, 'Unknown hotel'),
            coalesce(v_inbox::text, 'null')
          )
        )::text
      ),
      -- FINAL_CHECK_30
      (
        'DAY17_FINAL_RUNTIME',
        'activity_timeline_real_authorized_read',
        v_runtime_error is null
          and jsonb_typeof(v_activity) = 'object',
        coalesce(
          v_runtime_error,
          format(
            '%s / %s',
            coalesce(v_hotel_name, 'Unknown hotel'),
            coalesce(v_activity::text, 'null')
          )
        )
      ),
      -- FINAL_CHECK_31
      (
        'DAY17_FINAL_RUNTIME',
        'system_settings_real_authorized_read',
        v_runtime_error is null
          and jsonb_typeof(v_settings) = 'object',
        coalesce(
          v_runtime_error,
          format(
            '%s / settings loaded',
            coalesce(v_hotel_name, 'Unknown hotel')
          )
        )
      ),
      -- FINAL_CHECK_32
      (
        'DAY17_FINAL_RUNTIME',
        'support_workspace_real_authorized_read',
        v_runtime_error is null
          and jsonb_typeof(v_support) = 'object',
        coalesce(
          v_runtime_error,
          format(
            '%s / support workspace loaded',
            coalesce(v_hotel_name, 'Unknown hotel')
          )
        )
      ),
      -- FINAL_CHECK_33
      (
        'DAY17_FINAL_RUNTIME',
        'announcements_real_authorized_read',
        v_runtime_error is null
          and jsonb_typeof(v_announcements) in ('array', 'object'),
        coalesce(
          v_runtime_error,
          format(
            '%s / announcements loaded',
            coalesce(v_hotel_name, 'Unknown hotel')
          )
        )
      )
  ) smoke(suite, test_name, passed, details);
end;
$function$;

revoke all on function
  private.day17_a071_final_consolidated_acceptance_rev1()
from public, anon, authenticated;

commit;

select suite, test_name, passed, details
from private.day17_a071_final_consolidated_acceptance_rev1()
order by suite, test_name;
