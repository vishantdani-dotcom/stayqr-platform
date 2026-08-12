-- StayQR v1.0 Day 20
-- Migration 071 REV1
-- Operational error retention provenance recovery
--
-- Purpose:
--   Restore source-control provenance for the already-accepted Staging runtime
--   retention function and pg_cron schedule that were created during Day 19
--   but never committed to Git.
--
-- Safety:
--   * Forward-only Day 20 migration.
--   * Does not replay the Day 18 canonical baseline.
--   * Does not delete business data during migration execution.
--   * The cleanup function itself deletes only resolved/ignored operational
--     error events older than 90 days when invoked by the scheduled cron job.
--   * Fails closed if pg_cron or the required table is unavailable.

begin;

select pg_advisory_xact_lock(
  hashtextextended('stayqr:day20:migration071:operational-error-retention', 0)
);

do $$
begin
  if not exists (
    select 1
    from pg_catalog.pg_extension
    where extname = 'pg_cron'
  ) then
    raise exception 'Migration 071 requires pg_cron.';
  end if;

  if to_regclass('cron.job') is null then
    raise exception 'Migration 071 requires cron.job.';
  end if;

  if to_regclass('public.operational_error_events') is null then
    raise exception 'Migration 071 requires public.operational_error_events.';
  end if;

  if exists (
    select 1
    from (
      values
        ('status'),
        ('resolved_at'),
        ('last_seen_at'),
        ('created_at')
    ) required(column_name)
    where not exists (
      select 1
      from information_schema.columns c
      where c.table_schema = 'public'
        and c.table_name = 'operational_error_events'
        and c.column_name = required.column_name
    )
  ) then
    raise exception 'Migration 071 operational_error_events prerequisite columns are incomplete.';
  end if;
end;
$$;

create or replace function private.cleanup_operational_error_events_retention()
returns bigint
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private'
as $function$
declare
  deleted_count bigint := 0;
begin
  delete from public.operational_error_events
  where status in ('resolved', 'ignored')
    and coalesce(resolved_at, last_seen_at, created_at)
        < (now() - interval '90 days');

  get diagnostics deleted_count = row_count;
  return deleted_count;
end;
$function$;

alter function private.cleanup_operational_error_events_retention() owner to postgres;

revoke all on function private.cleanup_operational_error_events_retention()
  from public, anon, authenticated, service_role;

do $$
declare
  existing_job record;
begin
  for existing_job in
    select jobid
    from cron.job
    where jobname = 'stayqr-operational-error-retention-v1'
    order by jobid
  loop
    perform cron.unschedule(existing_job.jobid);
  end loop;

  perform cron.schedule(
    'stayqr-operational-error-retention-v1',
    '17 2 * * *',
    'select private.cleanup_operational_error_events_retention();'
  );
end;
$$;

commit;
