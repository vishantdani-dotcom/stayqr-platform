-- ============================================================================
-- StayQR v1.0
-- Day 9 Migration 023 REV2 — Safe Support Access End-Action Ambiguity Fix
--
-- ROOT CAUSE
-- Audit 052 passed the full lifecycle flow through safe-support session start,
-- then public.end_safe_support_access(...) failed with:
--   column reference "reason" is ambiguous
--
-- The function input parameter is named `reason`, while
-- public.support_access_sessions also has a `reason` column. In the UPDATE
-- statement PostgreSQL could not decide which `reason` was intended.
--
-- FIX
-- Preserve the public RPC signature and use the positional parameter `$2`
-- inside SQL expressions. This removes ambiguity without breaking frontend,
-- Edge Function or API callers.
--
-- SAFETY
-- - Run once in Supabase SQL Editor with role: postgres.
-- - Transactional and idempotent.
-- - Replaces one function only.
-- - Does not create, update or delete any support session or business record.
--
-- REV2 FIX
-- The REV1 preflight attempted to recognize the old function body by searching
-- pg_get_functiondef(...) for the exact text trim(reason). PostgreSQL may
-- normalize stored function source differently, so that check rejected a valid
-- installed function before replacement. REV2 removes only that brittle
-- source-text assertion and safely replaces the function by its exact signature.
-- REV1 stopped before CREATE OR REPLACE and before COMMIT, so it changed no
-- schema or business records.
--
-- EXPECTED RESULT
-- 12 rows, and every passed value must be true.
-- ============================================================================

begin;

set local lock_timeout = '10s';
set local statement_timeout = '120s';

select pg_advisory_xact_lock(
  hashtext('stayqr:202607280023:safe-support-end-ambiguity-fix')
);

-- ============================================================================
-- 0. PRE-MIGRATION ASSERTIONS
-- ============================================================================

do $preflight$
begin
  if to_regclass('public.support_access_sessions') is null
     or to_regclass('public.support_access_events') is null
  then
    raise exception
      'Migration 023 stopped: safe-support foundation tables are missing.';
  end if;

  if to_regprocedure(
    'public.end_safe_support_access(uuid,text)'
  ) is null
     or to_regprocedure(
       'private.require_platform_admin_20260728()'
     ) is null
  then
    raise exception
      'Migration 023 stopped: Migration 021 safe-support functions are missing.';
  end if;

end;
$preflight$;

-- ============================================================================
-- 1. REPLACE ONLY THE AMBIGUOUS END ACTION
-- ============================================================================

create or replace function public.end_safe_support_access(
  target_session_id uuid,
  reason text default 'Support work completed.'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid :=
    private.require_platform_admin_20260728();
  session_row public.support_access_sessions%rowtype;
  resolved_reason text := coalesce(
    nullif(trim($2), ''),
    'Support work completed.'
  );
begin
  select sas.*
  into session_row
  from public.support_access_sessions sas
  where sas.id = target_session_id
  for update;

  if not found then
    raise exception
      'Support-access session was not found.';
  end if;

  if session_row.status <> 'active' then
    return jsonb_build_object(
      'session_id', session_row.id,
      'status', session_row.status,
      'idempotent', true
    );
  end if;

  update public.support_access_sessions sas
  set
    status = 'ended',
    ended_at = now(),
    ended_by = actor_user_id,
    metadata = sas.metadata
      || jsonb_build_object(
        'end_reason',
        resolved_reason
      ),
    updated_at = now()
  where sas.id = target_session_id
  returning * into session_row;

  insert into public.support_access_events (
    session_id,
    hotel_id,
    event_type,
    actor_user_id,
    message,
    details,
    created_at
  ) values (
    session_row.id,
    session_row.hotel_id,
    'support_access_ended',
    actor_user_id,
    resolved_reason,
    jsonb_build_object(
      'ended_at', session_row.ended_at
    ),
    now()
  );

  return jsonb_build_object(
    'session', to_jsonb(session_row),
    'idempotent', false
  );
end;
$$;

revoke all on function
  public.end_safe_support_access(uuid,text)
from public, anon, authenticated;

grant execute on function
  public.end_safe_support_access(uuid,text)
to authenticated;

comment on function
  public.end_safe_support_access(uuid,text) is
  'Ends an active Platform Admin support-access session and appends immutable end history. Migration 023 resolves the reason parameter/column ambiguity.';

-- ============================================================================
-- 2. POST-MIGRATION ASSERTIONS
-- ============================================================================

do $verify$
declare
  function_source text;
begin
  function_source := lower(
    pg_get_functiondef(
      'public.end_safe_support_access(uuid,text)'::regprocedure
    )
  );

  if position('resolved_reason' in function_source) = 0
     or position('trim($2)' in function_source) = 0
  then
    raise exception
      'Migration 023 failed: positional reason resolution is not installed.';
  end if;

  if position('trim(reason)' in function_source) > 0 then
    raise exception
      'Migration 023 failed: ambiguous trim(reason) remains installed.';
  end if;

  if has_function_privilege(
    'anon',
    'public.end_safe_support_access(uuid,text)',
    'EXECUTE'
  ) then
    raise exception
      'Migration 023 failed: anon can execute the safe-support end action.';
  end if;

  if not has_function_privilege(
    'authenticated',
    'public.end_safe_support_access(uuid,text)',
    'EXECUTE'
  ) then
    raise exception
      'Migration 023 failed: authenticated execute grant is missing.';
  end if;
end;
$verify$;

commit;

-- ============================================================================
-- 3. ACCEPTANCE RESULT
-- ============================================================================

with checks(test_name, passed, details) as (
  values
    (
      '01_end_action_present',
      to_regprocedure(
        'public.end_safe_support_access(uuid,text)'
      ) is not null,
      'Safe-support end RPC remains installed with its original public signature.'
    ),
    (
      '02_security_definer',
      (
        select p.prosecdef
        from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public'
          and p.oid =
            'public.end_safe_support_access(uuid,text)'::regprocedure
      ),
      'Safe-support end RPC remains SECURITY DEFINER.'
    ),
    (
      '03_search_path_locked',
      (
        select
          p.proconfig @> array['search_path=""']::text[]
          or p.proconfig @> array['search_path=']::text[]
        from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public'
          and p.oid =
            'public.end_safe_support_access(uuid,text)'::regprocedure
      ),
      'Safe-support end RPC locks search_path.'
    ),
    (
      '04_positional_reason_resolution',
      position(
        'trim($2)'
        in lower(
          pg_get_functiondef(
            'public.end_safe_support_access(uuid,text)'::regprocedure
          )
        )
      ) > 0,
      'The second input parameter is referenced positionally.'
    ),
    (
      '05_resolved_reason_variable',
      position(
        'resolved_reason'
        in lower(
          pg_get_functiondef(
            'public.end_safe_support_access(uuid,text)'::regprocedure
          )
        )
      ) > 0,
      'One unambiguous normalized reason value is reused for metadata and event history.'
    ),
    (
      '06_ambiguous_reference_removed',
      position(
        'trim(reason)'
        in lower(
          pg_get_functiondef(
            'public.end_safe_support_access(uuid,text)'::regprocedure
          )
        )
      ) = 0,
      'The audited ambiguous trim(reason) expression is absent.'
    ),
    (
      '07_authenticated_execute_preserved',
      has_function_privilege(
        'authenticated',
        'public.end_safe_support_access(uuid,text)',
        'EXECUTE'
      ),
      'Authenticated callers retain execute permission subject to Platform Admin authorization.'
    ),
    (
      '08_anonymous_execute_blocked',
      not has_function_privilege(
        'anon',
        'public.end_safe_support_access(uuid,text)',
        'EXECUTE'
      ),
      'Anonymous callers cannot execute the safe-support end action.'
    ),
    (
      '09_platform_admin_guard_preserved',
      position(
        'private.require_platform_admin_20260728'
        in pg_get_functiondef(
          'public.end_safe_support_access(uuid,text)'::regprocedure
        )
      ) > 0,
      'The Platform Admin authorization guard remains mandatory.'
    ),
    (
      '10_end_event_insert_preserved',
      position(
        'support_access_ended'
        in pg_get_functiondef(
          'public.end_safe_support_access(uuid,text)'::regprocedure
        )
      ) > 0,
      'Ending a session still appends support_access_ended history.'
    ),
    (
      '11_support_event_immutability_preserved',
      exists (
        select 1
        from pg_trigger t
        where t.tgrelid =
          'public.support_access_events'::regclass
          and t.tgname =
            'prevent_support_access_event_mutation_20260728'
          and not t.tgisinternal
      ),
      'Safe-support history remains append-only.'
    ),
    (
      '12_day9_runtime_retest_ready',
      to_regprocedure(
        'public.start_safe_support_access(uuid,text,integer,text[])'
      ) is not null
      and to_regprocedure(
        'public.end_safe_support_access(uuid,text)'
      ) is not null
      and to_regprocedure(
        'public.save_platform_announcement(jsonb)'
      ) is not null
      and to_regprocedure(
        'public.get_super_admin_dashboard()'
      ) is not null,
      'Audit 052 can now resume through safe-support end, announcements and authorization gates.'
    )
)
select test_name, passed, details
from checks
order by test_name;
