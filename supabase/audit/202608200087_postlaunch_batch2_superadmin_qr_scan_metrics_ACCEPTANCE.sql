-- StayQR v1.1 Post-Launch Batch B
-- Audit 087 — Super Admin Guest Guide QR Scan Metrics Acceptance
-- Supabase SQL Editor safe. Read-only audit.
--
-- Expected summary:
-- POSTLAUNCH_BATCH2_QR_SCAN_METRICS_DATABASE_ACCEPTANCE: PASS (6/6)

with function_def as (
  select pg_get_functiondef(
    'public.get_postlaunch_batch2_platform_metrics()'::regprocedure
  ) as definition
),
checks(check_no, check_name, passed, evidence) as (
  select
    1,
    'guest guide event telemetry exists',
    to_regclass('public.guest_guide_events') is not null,
    'public.guest_guide_events'
  union all
  select
    2,
    'platform metrics exposes total QR scan key',
    position('guest_guide_qr_scans_total' in definition) > 0,
    'guest_guide_qr_scans_total'
  from function_def
  union all
  select
    3,
    'platform metrics exposes unique QR scan key',
    position('guest_guide_qr_scans_unique' in definition) > 0,
    'guest_guide_qr_scans_unique'
  from function_def
  union all
  select
    4,
    'total metric uses guide_opened telemetry',
    position('event_type = ''guide_opened''' in definition) > 0,
    'guide_opened events'
  from function_def
  union all
  select
    5,
    'unique metric deduplicates guest access tokens',
    position('count(distinct guest_access_token_id)' in lower(definition)) > 0,
    'distinct guest_access_token_id'
  from function_def
  union all
  select
    6,
    'platform metrics remains platform-admin guarded',
    position('private.is_platform_admin()' in definition) > 0,
    'private.is_platform_admin()'
  from function_def
),
report as (
  select check_no, check_name, passed, evidence
  from checks
  union all
  select
    999,
    case
      when count(*) filter (where passed) = 6
        then 'POSTLAUNCH_BATCH2_QR_SCAN_METRICS_DATABASE_ACCEPTANCE: PASS (6/6)'
      else format(
        'POSTLAUNCH_BATCH2_QR_SCAN_METRICS_DATABASE_ACCEPTANCE: FAIL (%s/6 passed)',
        count(*) filter (where passed)
      )
    end,
    count(*) filter (where passed) = 6,
    format(
      'Current recorded guide opens: %s total / %s unique access links',
      (select count(*) from public.guest_guide_events where event_type = 'guide_opened'),
      (select count(distinct guest_access_token_id)
       from public.guest_guide_events
       where event_type = 'guide_opened'
         and guest_access_token_id is not null)
    )
  from checks
)
select
  case when check_no = 999 then 'SUMMARY' else check_no::text end as check_no,
  check_name,
  case when passed then 'PASS' else 'FAIL' end as result,
  evidence
from report
order by check_no;
