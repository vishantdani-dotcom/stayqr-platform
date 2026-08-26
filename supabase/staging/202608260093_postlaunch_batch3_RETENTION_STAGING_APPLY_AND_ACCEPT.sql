-- StayQR Post-Launch Batch 3
-- Final retention deadline enforcement + historical backfill
-- SQL-Editor-safe / idempotent
-- Target: StayQR Staging first. Production only after browser acceptance.

begin;

select pg_advisory_xact_lock(hashtext('stayqr_postlaunch_batch3_retention_093'));

-- 1. Backfill every existing private KYC row that has no explicit retention deadline.
--    Use its own creation time so the lifecycle is deterministic and auditable.
update public.guest_documents
set
  retention_until = created_at + interval '365 days',
  retention_basis = coalesce(nullif(trim(retention_basis), ''), 'hotel_policy'),
  updated_at = now()
where retention_until is null;

-- 2. Normalize blank retention basis on all existing records.
update public.guest_documents
set
  retention_basis = 'hotel_policy',
  updated_at = now()
where retention_basis is null or trim(retention_basis) = '';

-- 3. Authoritative guard for every future insert/update.
create or replace function private.enforce_guest_document_retention_batch3()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  effective_created_at timestamptz;
begin
  effective_created_at := coalesce(new.created_at, now());

  if new.retention_until is null then
    new.retention_until := effective_created_at + interval '365 days';
  end if;

  new.retention_basis := coalesce(nullif(trim(new.retention_basis), ''), 'hotel_policy');

  if new.retention_until <= effective_created_at then
    raise exception 'Guest document retention deadline must be later than its creation time.';
  end if;

  return new;
end;
$$;

revoke all on function private.enforce_guest_document_retention_batch3() from public, anon, authenticated;

drop trigger if exists trg_guest_documents_retention_batch3 on public.guest_documents;
create trigger trg_guest_documents_retention_batch3
before insert or update of retention_until, retention_basis, created_at
on public.guest_documents
for each row
execute function private.enforce_guest_document_retention_batch3();

-- 4. Retention is mandatory for private KYC evidence after the backfill.
alter table public.guest_documents
  alter column retention_basis set default 'hotel_policy',
  alter column retention_basis set not null,
  alter column retention_until set not null;

-- 5. Keep the existing chronological integrity constraint authoritative.
do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.guest_documents'::regclass
      and conname = 'guest_documents_retention_batch3_check'
  ) then
    alter table public.guest_documents
      add constraint guest_documents_retention_batch3_check
      check (retention_until > created_at);
  end if;
end
$$;

-- 6. Consolidated database acceptance: fail the transaction on any regression.
do $$
declare
  missing_deadline integer;
  missing_basis integer;
  bad_order integer;
  trigger_count integer;
  deadline_nullable text;
  basis_nullable text;
  rls_enabled boolean;
begin
  select count(*) into missing_deadline
  from public.guest_documents
  where deleted_at is null and retention_until is null;

  if missing_deadline <> 0 then
    raise exception 'Batch 3 retention acceptance failed: % active KYC row(s) have no deadline.', missing_deadline;
  end if;

  select count(*) into missing_basis
  from public.guest_documents
  where deleted_at is null
    and (retention_basis is null or trim(retention_basis) = '');

  if missing_basis <> 0 then
    raise exception 'Batch 3 retention acceptance failed: % active KYC row(s) have no retention basis.', missing_basis;
  end if;

  select count(*) into bad_order
  from public.guest_documents
  where retention_until <= created_at;

  if bad_order <> 0 then
    raise exception 'Batch 3 retention acceptance failed: % KYC row(s) have invalid deadline ordering.', bad_order;
  end if;

  select count(*) into trigger_count
  from pg_trigger
  where tgrelid = 'public.guest_documents'::regclass
    and tgname = 'trg_guest_documents_retention_batch3'
    and not tgisinternal;

  if trigger_count <> 1 then
    raise exception 'Batch 3 retention acceptance failed: retention trigger missing or duplicated.';
  end if;

  select is_nullable into deadline_nullable
  from information_schema.columns
  where table_schema = 'public'
    and table_name = 'guest_documents'
    and column_name = 'retention_until';

  if deadline_nullable <> 'NO' then
    raise exception 'Batch 3 retention acceptance failed: retention_until is still nullable.';
  end if;

  select is_nullable into basis_nullable
  from information_schema.columns
  where table_schema = 'public'
    and table_name = 'guest_documents'
    and column_name = 'retention_basis';

  if basis_nullable <> 'NO' then
    raise exception 'Batch 3 retention acceptance failed: retention_basis is still nullable.';
  end if;

  select relrowsecurity into rls_enabled
  from pg_class
  where oid = 'public.guest_documents'::regclass;

  if coalesce(rls_enabled, false) is not true then
    raise exception 'Batch 3 retention acceptance failed: guest_documents RLS is not enabled.';
  end if;
end
$$;

commit;

-- Final visible evidence.
with checks as (
  select 1 as n, 'Active KYC rows all have retention deadlines' as check_name,
    not exists (
      select 1 from public.guest_documents
      where deleted_at is null and retention_until is null
    ) as passed
  union all
  select 2, 'Active KYC rows all have retention basis',
    not exists (
      select 1 from public.guest_documents
      where deleted_at is null
        and (retention_basis is null or trim(retention_basis) = '')
    )
  union all
  select 3, 'Retention deadline always follows creation time',
    not exists (
      select 1 from public.guest_documents
      where retention_until <= created_at
    )
  union all
  select 4, 'Retention enforcement trigger exists',
    exists (
      select 1 from pg_trigger
      where tgrelid = 'public.guest_documents'::regclass
        and tgname = 'trg_guest_documents_retention_batch3'
        and not tgisinternal
    )
  union all
  select 5, 'retention_until is NOT NULL',
    exists (
      select 1 from information_schema.columns
      where table_schema='public'
        and table_name='guest_documents'
        and column_name='retention_until'
        and is_nullable='NO'
    )
  union all
  select 6, 'retention_basis is NOT NULL',
    exists (
      select 1 from information_schema.columns
      where table_schema='public'
        and table_name='guest_documents'
        and column_name='retention_basis'
        and is_nullable='NO'
    )
  union all
  select 7, 'guest_documents RLS remains enabled',
    coalesce((
      select relrowsecurity
      from pg_class
      where oid='public.guest_documents'::regclass
    ),false)
  union all
  select 8, 'Retention due index remains present',
    to_regclass('public.idx_guest_documents_retention_batch3') is not null
)
select
  n,
  case when passed then 'PASS' else 'FAIL' end as status,
  check_name
from checks
order by n;

select
  case
    when count(*) filter (where passed) = 8
      then 'POSTLAUNCH_BATCH3_RETENTION_ACCEPTANCE: PASS (8/8)'
    else format(
      'POSTLAUNCH_BATCH3_RETENTION_ACCEPTANCE: FAIL (%s/8)',
      count(*) filter (where passed)
    )
  end as batch3_retention_acceptance
from (
  select not exists (
    select 1 from public.guest_documents
    where deleted_at is null and retention_until is null
  ) as passed
  union all
  select not exists (
    select 1 from public.guest_documents
    where deleted_at is null
      and (retention_basis is null or trim(retention_basis) = '')
  )
  union all
  select not exists (
    select 1 from public.guest_documents
    where retention_until <= created_at
  )
  union all
  select exists (
    select 1 from pg_trigger
    where tgrelid='public.guest_documents'::regclass
      and tgname='trg_guest_documents_retention_batch3'
      and not tgisinternal
  )
  union all
  select exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='guest_documents'
      and column_name='retention_until' and is_nullable='NO'
  )
  union all
  select exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='guest_documents'
      and column_name='retention_basis' and is_nullable='NO'
  )
  union all
  select coalesce((
    select relrowsecurity from pg_class
    where oid='public.guest_documents'::regclass
  ),false)
  union all
  select to_regclass('public.idx_guest_documents_retention_batch3') is not null
) s;
