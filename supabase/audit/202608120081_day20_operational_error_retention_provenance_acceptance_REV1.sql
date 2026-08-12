-- StayQR v1.0 Day 20
-- Audit 081 REV1
-- Migration 071 operational-error retention provenance acceptance
-- READ ONLY.

with checks as (
  select
    1 as seq,
    'pg_cron_installed'::text as check_name,
    exists (
      select 1 from pg_catalog.pg_extension where extname = 'pg_cron'
    ) as passed,
    null::text as details

  union all
  select
    2,
    'cron_job_relation_present',
    to_regclass('cron.job') is not null,
    null

  union all
  select
    3,
    'cleanup_function_present',
    to_regprocedure('private.cleanup_operational_error_events_retention()') is not null,
    null

  union all
  select
    4,
    'cleanup_function_security_definer',
    coalesce((
      select p.prosecdef
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'private'
        and p.proname = 'cleanup_operational_error_events_retention'
        and pg_get_function_identity_arguments(p.oid) = ''
      limit 1
    ), false),
    null

  union all
  select
    5,
    'cleanup_function_search_path_locked',
    coalesce((
      select p.proconfig @> array['search_path=pg_catalog, public, private']::text[]
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'private'
        and p.proname = 'cleanup_operational_error_events_retention'
        and pg_get_function_identity_arguments(p.oid) = ''
      limit 1
    ), false),
    null

  union all
  select
    6,
    'cleanup_function_90_day_retention',
    coalesce((
      select position('interval ''90 days''' in pg_get_functiondef(p.oid)) > 0
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'private'
        and p.proname = 'cleanup_operational_error_events_retention'
        and pg_get_function_identity_arguments(p.oid) = ''
      limit 1
    ), false),
    null

  union all
  select
    7,
    'cleanup_function_terminal_status_filter',
    coalesce((
      select
        position('resolved' in pg_get_functiondef(p.oid)) > 0
        and position('ignored' in pg_get_functiondef(p.oid)) > 0
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'private'
        and p.proname = 'cleanup_operational_error_events_retention'
        and pg_get_function_identity_arguments(p.oid) = ''
      limit 1
    ), false),
    null

  union all
  select
    8,
    'cleanup_function_browser_execute_revoked',
    not has_function_privilege(
      'anon',
      'private.cleanup_operational_error_events_retention()',
      'EXECUTE'
    )
    and not has_function_privilege(
      'authenticated',
      'private.cleanup_operational_error_events_retention()',
      'EXECUTE'
    ),
    null

  union all
  select
    9,
    'cron_job_exactly_one',
    (select count(*) from cron.job
      where jobname = 'stayqr-operational-error-retention-v1') = 1,
    (select count(*)::text from cron.job
      where jobname = 'stayqr-operational-error-retention-v1')

  union all
  select
    10,
    'cron_schedule_exact',
    coalesce((
      select schedule = '17 2 * * *'
      from cron.job
      where jobname = 'stayqr-operational-error-retention-v1'
      order by jobid
      limit 1
    ), false),
    (select schedule
     from cron.job
     where jobname = 'stayqr-operational-error-retention-v1'
     order by jobid
     limit 1)

  union all
  select
    11,
    'cron_command_exact',
    coalesce((
      select trim(command) = 'select private.cleanup_operational_error_events_retention();'
      from cron.job
      where jobname = 'stayqr-operational-error-retention-v1'
      order by jobid
      limit 1
    ), false),
    (select command
     from cron.job
     where jobname = 'stayqr-operational-error-retention-v1'
     order by jobid
     limit 1)

  union all
  select
    12,
    'cron_job_active',
    coalesce((
      select active
      from cron.job
      where jobname = 'stayqr-operational-error-retention-v1'
      order by jobid
      limit 1
    ), false),
    null
)
select
  seq,
  check_name,
  case when passed then 'PASS' else 'FAIL' end as result,
  details
from checks
order by seq;
