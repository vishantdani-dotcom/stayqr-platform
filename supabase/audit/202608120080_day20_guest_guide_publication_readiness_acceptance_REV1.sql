-- StayQR v1.0 — Day 20 Audit 080 REV1
-- Gate 20A-3 read-only acceptance for publication-aware QR readiness.
-- READ ONLY: no business data is written.

with function_defs as (
  select
    lower(pg_get_functiondef('private.day20_guest_guide_has_published_version_20260812(uuid)'::regprocedure)) as helper_def,
    lower(pg_get_functiondef('private.compute_hotel_onboarding_readiness(uuid)'::regprocedure)) as compute_def,
    lower(pg_get_functiondef('public.refresh_hotel_onboarding_readiness(uuid)'::regprocedure)) as refresh_def,
    lower(pg_get_functiondef('public.resolve_premium_guest_guide(text,text)'::regprocedure)) as resolver_def
),
checks(seq, check_name, passed, details) as (
  select 1,
    'published_version_helper_present',
    to_regprocedure('private.day20_guest_guide_has_published_version_20260812(uuid)') is not null,
    'Authoritative published-version predicate exists.'
  union all
  select 2,
    'qr_readiness_requires_published_version',
    position('day20_guest_guide_has_published_version_20260812' in compute_def) > 0,
    'QR readiness includes the immutable published-version predicate.'
  from function_defs
  union all
  select 3,
    'qr_readiness_retains_guest_access_infrastructure',
    position('guest_access_tokens' in compute_def) > 0
      and position('get_guest_access_links' in compute_def) > 0
      and position('resolve_guest_portal' in compute_def) > 0,
    'Existing signed guest-access infrastructure remains required.'
  from function_defs
  union all
  select 4,
    'refresh_prevents_publication_deadlock',
    position('non_qr_ready' in refresh_def) > 0
      and position('ensure_guest_guide_foundation_20260811' in refresh_def) > 0,
    'Initial publication can occur only after the non-QR readiness gates are green.'
  from function_defs
  union all
  select 5,
    'premium_resolver_fail_closed',
    position('guest guide is not published yet' in resolver_def) > 0,
    'Unpublished Premium Guest Guides are rejected.'
  from function_defs
  union all
  select 6,
    'premium_resolver_live_draft_fallback_removed',
    position('v_snapshot := private.day14_build_guide_snapshot' in resolver_def) = 0,
    'Guest-facing resolver no longer renders the current live draft as a fallback.'
  from function_defs
  union all
  select 7,
    'completed_hotels_have_published_version',
    not exists (
      select 1
      from public.hotel_onboarding ho
      where ho.status = 'complete'
        and not private.day20_guest_guide_has_published_version_20260812(ho.hotel_id)
    ),
    'Every completed onboarding has an immutable published Guest Guide version.'
  union all
  select 8,
    'published_version_references_resolve',
    not exists (
      select 1
      from public.guest_guide_settings s
      where s.published_version >= 1
        and not exists (
          select 1
          from public.guest_guide_versions v
          where v.hotel_id = s.hotel_id
            and v.version_number = s.published_version
        )
    ),
    'Every nonzero published_version resolves to a real immutable version row.'
  union all
  select 9,
    'qr_true_never_without_published_version',
    not exists (
      select 1
      from public.hotels h
      cross join lateral private.compute_hotel_onboarding_readiness(h.id) as x(readiness)
      where coalesce((x.readiness -> 'checklist' ->> 'qr_ready')::boolean, false)
        and not private.day20_guest_guide_has_published_version_20260812(h.id)
    ),
    'No hotel can calculate QR Ready without a published version.'
  union all
  select 10,
    'draft_edits_do_not_destroy_previous_publication',
    position('publish_status' in helper_def) = 0
      and position('published_version' in helper_def) > 0,
    'Readiness is based on the published immutable version, not the current draft flag.'
  from function_defs
  union all
  select 11,
    'premium_guest_resolver_anon_access_retained',
    has_function_privilege('anon', 'public.resolve_premium_guest_guide(text,text)', 'EXECUTE'),
    'Signed anonymous guest access remains available.'
  union all
  select 12,
    'publication_helper_not_browser_executable',
    not has_function_privilege(
      'authenticated',
      'private.day20_guest_guide_has_published_version_20260812(uuid)',
      'EXECUTE'
    )
    and not has_function_privilege(
      'anon',
      'private.day20_guest_guide_has_published_version_20260812(uuid)',
      'EXECUTE'
    ),
    'Internal publication predicate is not directly browser-executable.'
)
select
  seq,
  check_name,
  case when passed then 'PASS' else 'FAIL' end as result,
  details
from checks
order by seq;
