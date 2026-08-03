-- StayQR v1.0 — Day 14 Audit 062 Final Consolidated Acceptance REV1
-- Runtime-aware, SQL-Editor-safe, read-only acceptance audit
-- Date: 2026-08-02
--
-- EXPECTED RESULT
--   80 rows
--   80 passed = true
--   0 failures
--
-- This audit validates:
--   * multilingual hotel guest content
--   * signed guest portal delivery
--   * private guest feedback and consent
--   * review/reward action foundation
--   * dynamic guest-visible amenities
--   * token rotation/revocation/expiry invariants
--   * anon + authenticated signed-RPC compatibility
--   * direct-table write restrictions and RLS
--
-- It does not modify hotel business data and does not use temporary tables.

with checks(area, test_name, passed, details) as (

-- ==========================================================================
-- A. DAY14_SCHEMA — 20 checks
-- ==========================================================================

select
  'DAY14_SCHEMA',
  '01_hotel_guest_content_table',
  to_regclass('public.hotel_guest_content') is not null,
  'Multilingual guest-content table exists.'

union all
select
  'DAY14_SCHEMA',
  '02_guest_feedback_table',
  to_regclass('public.guest_feedback') is not null,
  'Private guest-feedback table exists.'

union all
select
  'DAY14_SCHEMA',
  '03_guest_review_rewards_table',
  to_regclass('public.guest_review_rewards') is not null,
  'Review/reward action audit table exists.'

union all
select
  'DAY14_SCHEMA',
  '04_content_hotel_id_column',
  exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'hotel_guest_content'
      and column_name = 'hotel_id'
      and udt_name = 'uuid'
  ),
  'Guest content is tenant-bound by hotel_id.'

union all
select
  'DAY14_SCHEMA',
  '05_content_locale_column',
  exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'hotel_guest_content'
      and column_name = 'locale'
      and data_type = 'text'
  ),
  'Locale storage exists.'

union all
select
  'DAY14_SCHEMA',
  '06_content_jsonb_column',
  exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'hotel_guest_content'
      and column_name = 'content'
      and udt_name = 'jsonb'
  ),
  'Localized content is stored as JSONB.'

union all
select
  'DAY14_SCHEMA',
  '07_content_active_column',
  exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'hotel_guest_content'
      and column_name = 'is_active'
      and data_type = 'boolean'
  ),
  'Localized content can be activated or disabled.'

union all
select
  'DAY14_SCHEMA',
  '08_content_unique_hotel_locale',
  exists (
    select 1
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = 'public'
      and t.relname = 'hotel_guest_content'
      and c.contype = 'u'
  ),
  'Only one row per hotel and locale is allowed.'

union all
select
  'DAY14_SCHEMA',
  '09_content_locale_constraint',
  exists (
    select 1
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = 'public'
      and t.relname = 'hotel_guest_content'
      and c.contype = 'c'
      and pg_get_constraintdef(c.oid) ilike '%locale%'
  ),
  'Locale format is constrained.'

union all
select
  'DAY14_SCHEMA',
  '10_content_json_constraint',
  exists (
    select 1
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = 'public'
      and t.relname = 'hotel_guest_content'
      and c.contype = 'c'
      and pg_get_constraintdef(c.oid) ilike '%jsonb_typeof%'
  ),
  'Guest content must be a JSON object.'

union all
select
  'DAY14_SCHEMA',
  '11_feedback_guest_session_column',
  exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'guest_feedback'
      and column_name = 'guest_session_id'
      and udt_name = 'uuid'
  ),
  'Feedback is bound to a guest stay.'

union all
select
  'DAY14_SCHEMA',
  '12_feedback_token_column',
  exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'guest_feedback'
      and column_name = 'guest_access_token_id'
      and udt_name = 'uuid'
  ),
  'Feedback records the signed token used.'

union all
select
  'DAY14_SCHEMA',
  '13_feedback_rating_column',
  exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'guest_feedback'
      and column_name = 'rating'
  ),
  'Private rating is stored.'

union all
select
  'DAY14_SCHEMA',
  '14_feedback_consent_column',
  exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'guest_feedback'
      and column_name = 'consent_to_follow_up'
      and data_type = 'boolean'
  ),
  'Follow-up consent is stored explicitly.'

union all
select
  'DAY14_SCHEMA',
  '15_feedback_status_column',
  exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'guest_feedback'
      and column_name = 'status'
  ),
  'Feedback inbox status is available.'

union all
select
  'DAY14_SCHEMA',
  '16_feedback_unique_stay',
  exists (
    select 1
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = 'public'
      and t.relname = 'guest_feedback'
      and c.contype = 'u'
  ),
  'A guest stay has one current private-feedback record.'

union all
select
  'DAY14_SCHEMA',
  '17_reward_action_column',
  exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'guest_review_rewards'
      and column_name = 'action'
  ),
  'Review/reward action type is recorded.'

union all
select
  'DAY14_SCHEMA',
  '18_reward_status_column',
  exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'guest_review_rewards'
      and column_name = 'status'
  ),
  'Review/reward processing status is recorded.'

union all
select
  'DAY14_SCHEMA',
  '19_reward_metadata_jsonb',
  exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'guest_review_rewards'
      and column_name = 'metadata'
      and udt_name = 'jsonb'
  ),
  'Review/reward metadata is JSONB.'

union all
select
  'DAY14_SCHEMA',
  '20_reward_unique_stay_action',
  exists (
    select 1
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = 'public'
      and t.relname = 'guest_review_rewards'
      and c.contype = 'u'
  ),
  'Duplicate review/reward actions per stay are prevented.'

-- ==========================================================================
-- B. DAY14_SECURITY — 20 checks
-- ==========================================================================

union all
select
  'DAY14_SECURITY',
  '01_content_rls_enabled',
  coalesce((
    select c.relrowsecurity
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'hotel_guest_content'
  ), false),
  'RLS is enabled on multilingual guest content.'

union all
select
  'DAY14_SECURITY',
  '02_feedback_rls_enabled',
  coalesce((
    select c.relrowsecurity
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'guest_feedback'
  ), false),
  'RLS is enabled on private feedback.'

union all
select
  'DAY14_SECURITY',
  '03_reward_rls_enabled',
  coalesce((
    select c.relrowsecurity
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'guest_review_rewards'
  ), false),
  'RLS is enabled on review/reward audit rows.'

union all
select
  'DAY14_SECURITY',
  '04_content_policy_present',
  exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'hotel_guest_content'
  ),
  'Protected hotel-content policy exists.'

union all
select
  'DAY14_SECURITY',
  '05_feedback_policy_present',
  exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'guest_feedback'
  ),
  'Protected feedback-inbox policy exists.'

union all
select
  'DAY14_SECURITY',
  '06_reward_policy_present',
  exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'guest_review_rewards'
  ),
  'Protected review/reward policy exists.'

union all
select
  'DAY14_SECURITY',
  '07_anon_no_content_insert',
  not has_table_privilege(
    'anon', 'public.hotel_guest_content', 'INSERT'
  ),
  'Anonymous users cannot directly create guest content.'

union all
select
  'DAY14_SECURITY',
  '08_anon_no_content_update',
  not has_table_privilege(
    'anon', 'public.hotel_guest_content', 'UPDATE'
  ),
  'Anonymous users cannot directly update guest content.'

union all
select
  'DAY14_SECURITY',
  '09_anon_no_feedback_select',
  not has_table_privilege(
    'anon', 'public.guest_feedback', 'SELECT'
  ),
  'Anonymous users cannot read private feedback.'

union all
select
  'DAY14_SECURITY',
  '10_anon_no_feedback_insert',
  not has_table_privilege(
    'anon', 'public.guest_feedback', 'INSERT'
  ),
  'Anonymous users cannot bypass the feedback RPC.'

union all
select
  'DAY14_SECURITY',
  '11_anon_no_reward_select',
  not has_table_privilege(
    'anon', 'public.guest_review_rewards', 'SELECT'
  ),
  'Anonymous users cannot read review/reward audit rows.'

union all
select
  'DAY14_SECURITY',
  '12_anon_no_reward_insert',
  not has_table_privilege(
    'anon', 'public.guest_review_rewards', 'INSERT'
  ),
  'Anonymous users cannot bypass the review/reward RPC.'

union all
select
  'DAY14_SECURITY',
  '13_authenticated_no_content_insert',
  not has_table_privilege(
    'authenticated', 'public.hotel_guest_content', 'INSERT'
  ),
  'Authenticated browser users cannot bypass content RPCs.'

union all
select
  'DAY14_SECURITY',
  '14_authenticated_no_feedback_insert',
  not has_table_privilege(
    'authenticated', 'public.guest_feedback', 'INSERT'
  ),
  'Authenticated browser users cannot bypass feedback RPCs.'

union all
select
  'DAY14_SECURITY',
  '15_authenticated_no_reward_insert',
  not has_table_privilege(
    'authenticated', 'public.guest_review_rewards', 'INSERT'
  ),
  'Authenticated browser users cannot bypass review/reward RPCs.'

union all
select
  'DAY14_SECURITY',
  '16_anon_no_amenity_write',
  not (
    has_table_privilege('anon', 'public.amenities', 'INSERT')
    or has_table_privilege('anon', 'public.amenities', 'UPDATE')
    or has_table_privilege('anon', 'public.amenities', 'DELETE')
  ),
  'Anonymous guest browsers cannot change amenities.'

union all
select
  'DAY14_SECURITY',
  '17_anon_no_token_table_write',
  not (
    has_table_privilege('anon', 'public.guest_access_tokens', 'INSERT')
    or has_table_privilege('anon', 'public.guest_access_tokens', 'UPDATE')
    or has_table_privilege('anon', 'public.guest_access_tokens', 'DELETE')
  ),
  'Anonymous guest browsers cannot alter token rows.'

union all
select
  'DAY14_SECURITY',
  '18_content_read_rpc_not_anon',
  not has_function_privilege(
    'anon',
    'public.get_hotel_guest_content(uuid,text)',
    'EXECUTE'
  ),
  'Anonymous users cannot execute the hotel content editor read RPC.'

union all
select
  'DAY14_SECURITY',
  '19_content_write_rpc_not_anon',
  not has_function_privilege(
    'anon',
    'public.upsert_hotel_guest_content(uuid,text,jsonb)',
    'EXECUTE'
  ),
  'Anonymous users cannot execute the hotel content editor write RPC.'

union all
select
  'DAY14_SECURITY',
  '20_private_helpers_not_browser_executable',
  not has_function_privilege(
    'anon',
    'private.day14_touch_updated_at()',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'private.day14_touch_updated_at()',
    'EXECUTE'
  ),
  'Private Day 14 trigger helper is not browser-executable.'

-- ==========================================================================
-- C. DAY14_RPC — 20 checks
-- ==========================================================================

union all
select
  'DAY14_RPC',
  '01_get_content_rpc_exists',
  to_regprocedure(
    'public.get_hotel_guest_content(uuid,text)'
  ) is not null,
  'Protected content read RPC exists.'

union all
select
  'DAY14_RPC',
  '02_upsert_content_rpc_exists',
  to_regprocedure(
    'public.upsert_hotel_guest_content(uuid,text,jsonb)'
  ) is not null,
  'Protected content write RPC exists.'

union all
select
  'DAY14_RPC',
  '03_submit_feedback_rpc_exists',
  to_regprocedure(
    'public.submit_guest_feedback(text,text,integer,text,boolean)'
  ) is not null,
  'Signed private feedback RPC exists.'

union all
select
  'DAY14_RPC',
  '04_review_reward_rpc_exists',
  to_regprocedure(
    'public.record_guest_review_reward_action(text,text,text)'
  ) is not null,
  'Signed review/reward action RPC exists.'

union all
select
  'DAY14_RPC',
  '05_guest_portal_rpc_exists',
  to_regprocedure(
    'public.resolve_guest_portal(text,text)'
  ) is not null,
  'Signed guest portal resolver exists.'

union all
select
  'DAY14_RPC',
  '06_get_content_security_definer',
  coalesce((
    select p.prosecdef
    from pg_proc p
    where p.oid =
      to_regprocedure(
        'public.get_hotel_guest_content(uuid,text)'
      )
  ), false),
  'Content read RPC is SECURITY DEFINER.'

union all
select
  'DAY14_RPC',
  '07_upsert_content_security_definer',
  coalesce((
    select p.prosecdef
    from pg_proc p
    where p.oid =
      to_regprocedure(
        'public.upsert_hotel_guest_content(uuid,text,jsonb)'
      )
  ), false),
  'Content write RPC is SECURITY DEFINER.'

union all
select
  'DAY14_RPC',
  '08_submit_feedback_security_definer',
  coalesce((
    select p.prosecdef
    from pg_proc p
    where p.oid =
      to_regprocedure(
        'public.submit_guest_feedback(text,text,integer,text,boolean)'
      )
  ), false),
  'Feedback RPC is SECURITY DEFINER.'

union all
select
  'DAY14_RPC',
  '09_review_reward_security_definer',
  coalesce((
    select p.prosecdef
    from pg_proc p
    where p.oid =
      to_regprocedure(
        'public.record_guest_review_reward_action(text,text,text)'
      )
  ), false),
  'Review/reward RPC is SECURITY DEFINER.'

union all
select
  'DAY14_RPC',
  '10_guest_portal_security_definer',
  coalesce((
    select p.prosecdef
    from pg_proc p
    where p.oid =
      to_regprocedure(
        'public.resolve_guest_portal(text,text)'
      )
  ), false),
  'Guest portal resolver is SECURITY DEFINER.'

union all
select
  'DAY14_RPC',
  '11_anon_can_resolve_portal',
  has_function_privilege(
    'anon',
    'public.resolve_guest_portal(text,text)',
    'EXECUTE'
  ),
  'Anonymous signed guest links can resolve.'

union all
select
  'DAY14_RPC',
  '12_authenticated_can_resolve_portal',
  has_function_privilege(
    'authenticated',
    'public.resolve_guest_portal(text,text)',
    'EXECUTE'
  ),
  'Signed links work in authenticated browser profiles.'

union all
select
  'DAY14_RPC',
  '13_anon_can_submit_feedback',
  has_function_privilege(
    'anon',
    'public.submit_guest_feedback(text,text,integer,text,boolean)',
    'EXECUTE'
  ),
  'Anonymous signed guests can submit feedback.'

union all
select
  'DAY14_RPC',
  '14_authenticated_can_submit_feedback',
  has_function_privilege(
    'authenticated',
    'public.submit_guest_feedback(text,text,integer,text,boolean)',
    'EXECUTE'
  ),
  'Authenticated browser profiles can submit token-bound feedback.'

union all
select
  'DAY14_RPC',
  '15_anon_can_record_review_reward',
  has_function_privilege(
    'anon',
    'public.record_guest_review_reward_action(text,text,text)',
    'EXECUTE'
  ),
  'Anonymous signed guests can record review/reward actions.'

union all
select
  'DAY14_RPC',
  '16_authenticated_can_record_review_reward',
  has_function_privilege(
    'authenticated',
    'public.record_guest_review_reward_action(text,text,text)',
    'EXECUTE'
  ),
  'Authenticated browser profiles can record token-bound review/reward actions.'

union all
select
  'DAY14_RPC',
  '17_portal_uses_signed_token_resolver',
  coalesce((
    select pg_get_functiondef(
      to_regprocedure(
        'public.resolve_guest_portal(text,text)'
      )
    ) ilike '%private.resolve_guest_access_token%'
  ), false),
  'Guest portal access remains token-bound.'

union all
select
  'DAY14_RPC',
  '18_feedback_uses_signed_token_resolver',
  coalesce((
    select pg_get_functiondef(
      to_regprocedure(
        'public.submit_guest_feedback(text,text,integer,text,boolean)'
      )
    ) ilike '%private.resolve_guest_access_token%'
  ), false),
  'Private feedback remains token-bound.'

union all
select
  'DAY14_RPC',
  '19_review_reward_uses_signed_token_resolver',
  coalesce((
    select pg_get_functiondef(
      to_regprocedure(
        'public.record_guest_review_reward_action(text,text,text)'
      )
    ) ilike '%private.resolve_guest_access_token%'
  ), false),
  'Review/reward actions remain token-bound.'

union all
select
  'DAY14_RPC',
  '20_portal_returns_content_and_amenities',
  coalesce((
    select
      pg_get_functiondef(
        to_regprocedure(
          'public.resolve_guest_portal(text,text)'
        )
      ) ilike '%hotel_guest_content%'
      and pg_get_functiondef(
        to_regprocedure(
          'public.resolve_guest_portal(text,text)'
        )
      ) ilike '%public.amenities%'
      and pg_get_functiondef(
        to_regprocedure(
          'public.resolve_guest_portal(text,text)'
        )
      ) ilike '%available_locales%'
  ), false),
  'Portal response includes multilingual content and dynamic amenities.'

-- ==========================================================================
-- D. DAY14_RUNTIME — 20 checks
-- ==========================================================================

union all
select
  'DAY14_RUNTIME',
  '01_every_hotel_has_english_content',
  not exists (
    select 1
    from public.hotels h
    where not exists (
      select 1
      from public.hotel_guest_content c
      where c.hotel_id = h.id
        and c.locale = 'en'
        and c.is_active
    )
  ),
  'Every hotel has an active English guest-content baseline.'

union all
select
  'DAY14_RUNTIME',
  '02_multilingual_content_present',
  exists (
    select 1
    from public.hotel_guest_content
    where is_active
    group by hotel_id
    having count(distinct locale) >= 2
  ),
  'At least one hotel has multiple active guest-content locales.'

union all
select
  'DAY14_RUNTIME',
  '03_hindi_content_present',
  exists (
    select 1
    from public.hotel_guest_content
    where locale = 'hi'
      and is_active
  ),
  'Controlled Hindi guest content was saved.'

union all
select
  'DAY14_RUNTIME',
  '04_no_invalid_locales',
  not exists (
    select 1
    from public.hotel_guest_content
    where locale !~ '^[a-z]{2}(-[A-Z]{2})?$'
  ),
  'All stored locales use the accepted format.'

union all
select
  'DAY14_RUNTIME',
  '05_all_content_is_json_object',
  not exists (
    select 1
    from public.hotel_guest_content
    where jsonb_typeof(content) <> 'object'
  ),
  'All localized content rows contain JSON objects.'

union all
select
  'DAY14_RUNTIME',
  '06_no_oversized_content',
  not exists (
    select 1
    from public.hotel_guest_content
    where pg_column_size(content) > 65536
  ),
  'No guest-content payload exceeds the 64 KB limit.'

union all
select
  'DAY14_RUNTIME',
  '07_private_feedback_recorded',
  exists (
    select 1
    from public.guest_feedback
  ),
  'Controlled private feedback was recorded.'

union all
select
  'DAY14_RUNTIME',
  '08_five_star_feedback_recorded',
  exists (
    select 1
    from public.guest_feedback
    where rating = 5
  ),
  'Controlled five-star feedback is present.'

union all
select
  'DAY14_RUNTIME',
  '09_follow_up_consent_recorded',
  exists (
    select 1
    from public.guest_feedback
    where consent_to_follow_up
  ),
  'Controlled follow-up consent is present.'

union all
select
  'DAY14_RUNTIME',
  '10_feedback_status_valid',
  not exists (
    select 1
    from public.guest_feedback
    where status not in ('new', 'reviewed', 'resolved', 'closed')
  ),
  'All feedback inbox statuses are valid.'

union all
select
  'DAY14_RUNTIME',
  '11_feedback_rating_valid',
  not exists (
    select 1
    from public.guest_feedback
    where rating < 1 or rating > 5
  ),
  'All feedback ratings are between one and five.'

union all
select
  'DAY14_RUNTIME',
  '12_feedback_tenant_binding_valid',
  not exists (
    select 1
    from public.guest_feedback f
    join public.guest_sessions gs
      on gs.id = f.guest_session_id
    where gs.hotel_id <> f.hotel_id
  ),
  'Feedback tenant binding matches its guest stay.'

union all
select
  'DAY14_RUNTIME',
  '13_no_duplicate_feedback_stays',
  not exists (
    select 1
    from public.guest_feedback
    group by guest_session_id
    having count(*) > 1
  ),
  'No stay has duplicate private-feedback rows.'

union all
select
  'DAY14_RUNTIME',
  '14_no_duplicate_review_reward_actions',
  not exists (
    select 1
    from public.guest_review_rewards
    group by guest_session_id, action
    having count(*) > 1
  ),
  'No duplicate review/reward action exists for a stay.'

union all
select
  'DAY14_RUNTIME',
  '15_no_expired_active_tokens',
  not exists (
    select 1
    from public.guest_access_tokens
    where status = 'active'
      and expires_at <= now()
  ),
  'No expired token remains active.'

union all
select
  'DAY14_RUNTIME',
  '16_one_active_token_per_stay',
  not exists (
    select 1
    from public.guest_access_tokens
    where status = 'active'
    group by guest_session_id
    having count(*) > 1
  ),
  'At most one active token exists per guest stay.'

union all
select
  'DAY14_RUNTIME',
  '17_rotation_created_revoked_token',
  exists (
    select 1
    from public.guest_access_tokens
    where status = 'revoked'
  ),
  'Controlled token rotation left revoked-token evidence.'

union all
select
  'DAY14_RUNTIME',
  '18_active_token_remains_after_rotation',
  exists (
    select 1
    from public.guest_access_tokens
    where status = 'active'
      and expires_at > now()
  ),
  'A valid replacement token exists after rotation.'

union all
select
  'DAY14_RUNTIME',
  '19_guest_visible_amenities_present',
  exists (
    select 1
    from public.amenities
    where is_active
      and guest_visible
  ),
  'At least one dynamic active guest-visible amenity exists.'

union all
select
  'DAY14_RUNTIME',
  '20_hotel_review_configuration_present',
  exists (
    select 1
    from public.hotel_info
    where nullif(trim(google_review_url), '') is not null
  ),
  'At least one hotel has a configured Google review URL.'
)
select
  area,
  test_name,
  passed,
  details
from checks
order by
  case area
    when 'DAY14_SCHEMA' then 1
    when 'DAY14_SECURITY' then 2
    when 'DAY14_RPC' then 3
    when 'DAY14_RUNTIME' then 4
    else 9
  end,
  test_name;
