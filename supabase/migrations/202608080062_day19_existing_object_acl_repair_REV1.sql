-- ============================================================================
-- StayQR v1.0
-- Day 19 Migration 062 REV1
-- Existing Object ACL Repair
-- Date: 2026-08-08
--
-- PURPOSE
-- Repair privilege drift exposed by the Day 18 canonical fresh-database
-- restore. Existing Day 14 objects inherited broader browser-role ACLs than
-- the accepted security contract allows.
--
-- SAFETY
-- - Forward-only repair.
-- - Does not edit Day 18 migrations 060 or 061.
-- - No hotel/business rows are inserted, updated or deleted.
-- - No RLS policy or function body is changed.
-- - Signed guest RPC compatibility is not changed.
-- - Transaction rolls back automatically if verification fails.
-- ============================================================================

begin;

set local lock_timeout = '10s';
set local statement_timeout = '180s';

select pg_advisory_xact_lock(
  hashtext('stayqr:202608080062:existing-object-acl-repair')
);

-- ============================================================================
-- 1. PRECONDITION — REQUIRED OBJECTS MUST EXIST
-- ============================================================================

do $preflight$
begin
  if to_regclass('public.hotel_guest_content') is null then
    raise exception 'Migration 062: public.hotel_guest_content is missing.';
  end if;

  if to_regclass('public.guest_feedback') is null then
    raise exception 'Migration 062: public.guest_feedback is missing.';
  end if;

  if to_regclass('public.guest_review_rewards') is null then
    raise exception 'Migration 062: public.guest_review_rewards is missing.';
  end if;

  if to_regclass('public.amenities') is null then
    raise exception 'Migration 062: public.amenities is missing.';
  end if;

  if to_regclass('public.guest_access_tokens') is null then
    raise exception 'Migration 062: public.guest_access_tokens is missing.';
  end if;

  if to_regprocedure(
    'public.get_hotel_guest_content(uuid,text)'
  ) is null then
    raise exception
      'Migration 062: get_hotel_guest_content(uuid,text) is missing.';
  end if;

  if to_regprocedure(
    'public.upsert_hotel_guest_content(uuid,text,jsonb)'
  ) is null then
    raise exception
      'Migration 062: upsert_hotel_guest_content(uuid,text,jsonb) is missing.';
  end if;
end;
$preflight$;


-- ============================================================================
-- 2. REMOVE ANONYMOUS / PUBLIC DIRECT TABLE ACCESS
-- ============================================================================

revoke all on table public.amenities
from public, anon;

revoke all on table public.guest_access_tokens
from public, anon;


-- ============================================================================
-- 3. RESTORE EXACT DAY 14 SENSITIVE-TABLE ACL CONTRACT
-- ============================================================================

revoke all on table public.hotel_guest_content
from public, anon, authenticated;

revoke all on table public.guest_feedback
from public, anon, authenticated;

revoke all on table public.guest_review_rewards
from public, anon, authenticated;


-- Hotel content is edited through the protected content-editor RPC.
grant select
on table public.hotel_guest_content
to authenticated;


-- Hotel staff may read/manage feedback state, but creation remains
-- token-bound through submit_guest_feedback(...).
grant select, update
on table public.guest_feedback
to authenticated;


-- Hotel staff may read/manage reward records, but creation remains
-- token-bound through record_guest_review_reward_action(...).
grant select, update
on table public.guest_review_rewards
to authenticated;


-- ============================================================================
-- 4. RESTORE HOTEL CONTENT EDITOR RPC ACL
-- ============================================================================

revoke all on function
  public.get_hotel_guest_content(uuid,text)
from public, anon;

revoke all on function
  public.upsert_hotel_guest_content(uuid,text,jsonb)
from public, anon;

grant execute on function
  public.get_hotel_guest_content(uuid,text)
to authenticated, service_role;

grant execute on function
  public.upsert_hotel_guest_content(uuid,text,jsonb)
to authenticated, service_role;


-- ============================================================================
-- 5. VERIFY SECURITY CONTRACT BEFORE COMMIT
-- ============================================================================

do $verify$
begin

  -- --------------------------------------------------------------------------
  -- Anonymous direct access: hotel_guest_content
  -- --------------------------------------------------------------------------

  if has_table_privilege(
    'anon', 'public.hotel_guest_content', 'SELECT'
  )
  or has_table_privilege(
    'anon', 'public.hotel_guest_content', 'INSERT'
  )
  or has_table_privilege(
    'anon', 'public.hotel_guest_content', 'UPDATE'
  )
  or has_table_privilege(
    'anon', 'public.hotel_guest_content', 'DELETE'
  ) then
    raise exception
      'Migration 062 verification failed: anon retains hotel_guest_content access.';
  end if;


  -- --------------------------------------------------------------------------
  -- Anonymous direct access: guest_feedback
  -- --------------------------------------------------------------------------

  if has_table_privilege(
    'anon', 'public.guest_feedback', 'SELECT'
  )
  or has_table_privilege(
    'anon', 'public.guest_feedback', 'INSERT'
  )
  or has_table_privilege(
    'anon', 'public.guest_feedback', 'UPDATE'
  )
  or has_table_privilege(
    'anon', 'public.guest_feedback', 'DELETE'
  ) then
    raise exception
      'Migration 062 verification failed: anon retains guest_feedback access.';
  end if;


  -- --------------------------------------------------------------------------
  -- Anonymous direct access: guest_review_rewards
  -- --------------------------------------------------------------------------

  if has_table_privilege(
    'anon', 'public.guest_review_rewards', 'SELECT'
  )
  or has_table_privilege(
    'anon', 'public.guest_review_rewards', 'INSERT'
  )
  or has_table_privilege(
    'anon', 'public.guest_review_rewards', 'UPDATE'
  )
  or has_table_privilege(
    'anon', 'public.guest_review_rewards', 'DELETE'
  ) then
    raise exception
      'Migration 062 verification failed: anon retains guest_review_rewards access.';
  end if;


  -- --------------------------------------------------------------------------
  -- Anonymous guest browsers cannot mutate operational guest tables
  -- --------------------------------------------------------------------------

  if has_table_privilege(
    'anon', 'public.amenities', 'INSERT'
  )
  or has_table_privilege(
    'anon', 'public.amenities', 'UPDATE'
  )
  or has_table_privilege(
    'anon', 'public.amenities', 'DELETE'
  ) then
    raise exception
      'Migration 062 verification failed: anon can mutate amenities.';
  end if;


  if has_table_privilege(
    'anon', 'public.guest_access_tokens', 'INSERT'
  )
  or has_table_privilege(
    'anon', 'public.guest_access_tokens', 'UPDATE'
  )
  or has_table_privilege(
    'anon', 'public.guest_access_tokens', 'DELETE'
  ) then
    raise exception
      'Migration 062 verification failed: anon can mutate guest_access_tokens.';
  end if;


  -- --------------------------------------------------------------------------
  -- Exact authenticated Day 14 table boundary
  -- --------------------------------------------------------------------------

  if not has_table_privilege(
    'authenticated', 'public.hotel_guest_content', 'SELECT'
  )
  or has_table_privilege(
    'authenticated', 'public.hotel_guest_content', 'INSERT'
  )
  or has_table_privilege(
    'authenticated', 'public.hotel_guest_content', 'UPDATE'
  )
  or has_table_privilege(
    'authenticated', 'public.hotel_guest_content', 'DELETE'
  ) then
    raise exception
      'Migration 062 verification failed: hotel_guest_content authenticated ACL incorrect.';
  end if;


  if not has_table_privilege(
    'authenticated', 'public.guest_feedback', 'SELECT'
  )
  or not has_table_privilege(
    'authenticated', 'public.guest_feedback', 'UPDATE'
  )
  or has_table_privilege(
    'authenticated', 'public.guest_feedback', 'INSERT'
  )
  or has_table_privilege(
    'authenticated', 'public.guest_feedback', 'DELETE'
  ) then
    raise exception
      'Migration 062 verification failed: guest_feedback authenticated ACL incorrect.';
  end if;


  if not has_table_privilege(
    'authenticated', 'public.guest_review_rewards', 'SELECT'
  )
  or not has_table_privilege(
    'authenticated', 'public.guest_review_rewards', 'UPDATE'
  )
  or has_table_privilege(
    'authenticated', 'public.guest_review_rewards', 'INSERT'
  )
  or has_table_privilege(
    'authenticated', 'public.guest_review_rewards', 'DELETE'
  ) then
    raise exception
      'Migration 062 verification failed: guest_review_rewards authenticated ACL incorrect.';
  end if;


  -- --------------------------------------------------------------------------
  -- Hotel content editor RPC boundary
  -- --------------------------------------------------------------------------

  if has_function_privilege(
    'anon',
    'public.get_hotel_guest_content(uuid,text)',
    'EXECUTE'
  ) then
    raise exception
      'Migration 062 verification failed: anon can execute content read RPC.';
  end if;


  if has_function_privilege(
    'anon',
    'public.upsert_hotel_guest_content(uuid,text,jsonb)',
    'EXECUTE'
  ) then
    raise exception
      'Migration 062 verification failed: anon can execute content write RPC.';
  end if;


  if not has_function_privilege(
    'authenticated',
    'public.get_hotel_guest_content(uuid,text)',
    'EXECUTE'
  ) then
    raise exception
      'Migration 062 verification failed: authenticated cannot execute content read RPC.';
  end if;


  if not has_function_privilege(
    'authenticated',
    'public.upsert_hotel_guest_content(uuid,text,jsonb)',
    'EXECUTE'
  ) then
    raise exception
      'Migration 062 verification failed: authenticated cannot execute content write RPC.';
  end if;


  -- --------------------------------------------------------------------------
  -- RLS must remain enabled
  -- --------------------------------------------------------------------------

  if exists (
    select 1
    from pg_class c
    join pg_namespace n
      on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname in (
        'hotel_guest_content',
        'guest_feedback',
        'guest_review_rewards',
        'amenities',
        'guest_access_tokens'
      )
      and not c.relrowsecurity
  ) then
    raise exception
      'Migration 062 verification failed: expected RLS is disabled.';
  end if;

end;
$verify$;

commit;


-- ============================================================================
-- 6. POST-COMMIT ACCEPTANCE OUTPUT
-- Expected: every passed value = true.
-- ============================================================================

with checks(test_name, passed, details) as (

  values

  (
    '01_anon_no_content_insert',
    not has_table_privilege(
      'anon', 'public.hotel_guest_content', 'INSERT'
    ),
    'Anonymous users cannot directly create guest content.'
  ),

  (
    '02_anon_no_content_update',
    not has_table_privilege(
      'anon', 'public.hotel_guest_content', 'UPDATE'
    ),
    'Anonymous users cannot directly update guest content.'
  ),

  (
    '03_anon_no_feedback_select',
    not has_table_privilege(
      'anon', 'public.guest_feedback', 'SELECT'
    ),
    'Anonymous users cannot read private feedback.'
  ),

  (
    '04_anon_no_feedback_insert',
    not has_table_privilege(
      'anon', 'public.guest_feedback', 'INSERT'
    ),
    'Anonymous users cannot bypass the feedback RPC.'
  ),

  (
    '05_anon_no_reward_select',
    not has_table_privilege(
      'anon', 'public.guest_review_rewards', 'SELECT'
    ),
    'Anonymous users cannot read review/reward audit rows.'
  ),

  (
    '06_anon_no_reward_insert',
    not has_table_privilege(
      'anon', 'public.guest_review_rewards', 'INSERT'
    ),
    'Anonymous users cannot bypass the review/reward RPC.'
  ),

  (
    '07_authenticated_no_content_insert',
    not has_table_privilege(
      'authenticated', 'public.hotel_guest_content', 'INSERT'
    ),
    'Authenticated browser users cannot bypass content RPCs.'
  ),

  (
    '08_authenticated_no_feedback_insert',
    not has_table_privilege(
      'authenticated', 'public.guest_feedback', 'INSERT'
    ),
    'Authenticated browser users cannot bypass feedback RPCs.'
  ),

  (
    '09_authenticated_no_reward_insert',
    not has_table_privilege(
      'authenticated', 'public.guest_review_rewards', 'INSERT'
    ),
    'Authenticated browser users cannot bypass review/reward RPCs.'
  ),

  (
    '10_anon_no_amenity_write',
    not (
      has_table_privilege(
        'anon', 'public.amenities', 'INSERT'
      )
      or has_table_privilege(
        'anon', 'public.amenities', 'UPDATE'
      )
      or has_table_privilege(
        'anon', 'public.amenities', 'DELETE'
      )
    ),
    'Anonymous guest browsers cannot change amenities.'
  ),

  (
    '11_anon_no_token_table_write',
    not (
      has_table_privilege(
        'anon', 'public.guest_access_tokens', 'INSERT'
      )
      or has_table_privilege(
        'anon', 'public.guest_access_tokens', 'UPDATE'
      )
      or has_table_privilege(
        'anon', 'public.guest_access_tokens', 'DELETE'
      )
    ),
    'Anonymous guest browsers cannot alter token rows.'
  ),

  (
    '12_content_read_rpc_not_anon',
    not has_function_privilege(
      'anon',
      'public.get_hotel_guest_content(uuid,text)',
      'EXECUTE'
    ),
    'Anonymous users cannot execute hotel content editor read RPC.'
  ),

  (
    '13_content_write_rpc_not_anon',
    not has_function_privilege(
      'anon',
      'public.upsert_hotel_guest_content(uuid,text,jsonb)',
      'EXECUTE'
    ),
    'Anonymous users cannot execute hotel content editor write RPC.'
  )

)

select
  test_name,
  passed,
  details
from checks
order by test_name;