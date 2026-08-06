-- StayQR v1.0 — Day 14 Migration 046 REV1
-- Authenticated Guest-RPC Execute Compatibility Fix
-- Date: 2026-08-01
--
-- ROOT CAUSE
-- Migration 045 replaced public.resolve_guest_portal(...) and the new Day 14
-- guest feedback/review RPCs, then granted EXECUTE only to anon.
--
-- A guest link opened in a browser profile that already has an authenticated
-- StayQR session calls Supabase as role=authenticated, even when the URL itself
-- is a signed guest capability URL. The RPC call is therefore rejected before
-- token validation, and the frontend correctly falls back to the safe inactive
-- screen.
--
-- FIX
-- Restore the accepted Day 7 compatibility model:
--   * anon and authenticated may execute the approved signed guest RPCs;
--   * every call still requires the signed hotel/stay/room token;
--   * no direct guest table access is granted;
--   * PUBLIC/default execution remains revoked.
--
-- SAFETY
--   * No business rows are inserted, updated or deleted.
--   * No function body is changed.
--   * Direct table access remains unchanged.
--   * Only three function ACLs are corrected.
--
-- EXPECTED RESULT
-- 18 rows, every passed value must be true.

begin;

revoke all on function
  public.resolve_guest_portal(text,text)
from public, anon, authenticated;

grant execute on function
  public.resolve_guest_portal(text,text)
to anon, authenticated;

revoke all on function
  public.submit_guest_feedback(text,text,integer,text,boolean)
from public, anon, authenticated;

grant execute on function
  public.submit_guest_feedback(text,text,integer,text,boolean)
to anon, authenticated;

revoke all on function
  public.record_guest_review_reward_action(text,text,text)
from public, anon, authenticated;

grant execute on function
  public.record_guest_review_reward_action(text,text,text)
to anon, authenticated;

commit;

with checks(test_name, passed, details) as (
  values
    (
      '01_resolve_guest_portal_exists',
      to_regprocedure(
        'public.resolve_guest_portal(text,text)'
      ) is not null,
      'Signed guest portal resolver exists.'
    ),
    (
      '02_submit_guest_feedback_exists',
      to_regprocedure(
        'public.submit_guest_feedback(text,text,integer,text,boolean)'
      ) is not null,
      'Signed private feedback RPC exists.'
    ),
    (
      '03_record_review_reward_exists',
      to_regprocedure(
        'public.record_guest_review_reward_action(text,text,text)'
      ) is not null,
      'Signed review/reward action RPC exists.'
    ),
    (
      '04_resolve_guest_portal_security_definer',
      (
        select p.prosecdef
        from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
        where p.oid =
          'public.resolve_guest_portal(text,text)'::regprocedure
      ),
      'Guest portal resolver remains SECURITY DEFINER.'
    ),
    (
      '05_submit_feedback_security_definer',
      (
        select p.prosecdef
        from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
        where p.oid =
          'public.submit_guest_feedback(text,text,integer,text,boolean)'::regprocedure
      ),
      'Feedback RPC remains SECURITY DEFINER.'
    ),
    (
      '06_record_action_security_definer',
      (
        select p.prosecdef
        from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
        where p.oid =
          'public.record_guest_review_reward_action(text,text,text)'::regprocedure
      ),
      'Review/reward RPC remains SECURITY DEFINER.'
    ),
    (
      '07_anon_can_resolve_guest_portal',
      has_function_privilege(
        'anon',
        'public.resolve_guest_portal(text,text)',
        'EXECUTE'
      ),
      'Anonymous signed guest links can resolve.'
    ),
    (
      '08_authenticated_can_resolve_guest_portal',
      has_function_privilege(
        'authenticated',
        'public.resolve_guest_portal(text,text)',
        'EXECUTE'
      ),
      'Signed guest links also work in a browser with an authenticated StayQR session.'
    ),
    (
      '09_anon_can_submit_feedback',
      has_function_privilege(
        'anon',
        'public.submit_guest_feedback(text,text,integer,text,boolean)',
        'EXECUTE'
      ),
      'Anonymous signed guests can submit private feedback.'
    ),
    (
      '10_authenticated_can_submit_feedback',
      has_function_privilege(
        'authenticated',
        'public.submit_guest_feedback(text,text,integer,text,boolean)',
        'EXECUTE'
      ),
      'Authenticated browser sessions can submit token-bound private feedback.'
    ),
    (
      '11_anon_can_record_review_reward',
      has_function_privilege(
        'anon',
        'public.record_guest_review_reward_action(text,text,text)',
        'EXECUTE'
      ),
      'Anonymous signed guests can record review/reward actions.'
    ),
    (
      '12_authenticated_can_record_review_reward',
      has_function_privilege(
        'authenticated',
        'public.record_guest_review_reward_action(text,text,text)',
        'EXECUTE'
      ),
      'Authenticated browser sessions can record token-bound review/reward actions.'
    ),
    (
      '13_anon_no_feedback_table_insert',
      not has_table_privilege(
        'anon',
        'public.guest_feedback',
        'INSERT'
      ),
      'Anonymous users still cannot insert feedback directly.'
    ),
    (
      '14_anon_no_reward_table_insert',
      not has_table_privilege(
        'anon',
        'public.guest_review_rewards',
        'INSERT'
      ),
      'Anonymous users still cannot insert review/reward rows directly.'
    ),
    (
      '15_authenticated_no_feedback_table_insert',
      not has_table_privilege(
        'authenticated',
        'public.guest_feedback',
        'INSERT'
      ),
      'Authenticated browser users still cannot bypass the feedback RPC.'
    ),
    (
      '16_authenticated_no_reward_table_insert',
      not has_table_privilege(
        'authenticated',
        'public.guest_review_rewards',
        'INSERT'
      ),
      'Authenticated browser users still cannot bypass the review/reward RPC.'
    ),
    (
      '17_token_resolver_retained',
      to_regprocedure(
        'private.resolve_guest_access_token(text,text,boolean)'
      ) is not null,
      'All three guest RPCs continue to rely on the signed-token resolver.'
    ),
    (
      '18_no_duplicate_active_tokens',
      not exists (
        select 1
        from (
          select guest_session_id
          from public.guest_access_tokens
          where status = 'active'
          group by guest_session_id
          having count(*) > 1
        ) duplicate_active
      ),
      'The token lifecycle still permits at most one active token per stay.'
    )
)
select test_name, passed, details
from checks
order by test_name;
