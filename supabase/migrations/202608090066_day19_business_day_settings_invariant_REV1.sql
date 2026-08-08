-- ============================================================================
-- StayQR v1.0
-- Day 19 Migration 066 REV1
-- Business-Day Settings Invariant for Current and Future Hotels
-- Date: 2026-08-09
--
-- PURPOSE
-- Close the only remaining Day 17 current-state defect found after ACL
-- canonicalization: hotels created after Migration 056 can exist without a
-- public.business_day_settings row.
--
-- SAFETY
-- - Forward-only and idempotent.
-- - Inserts only missing configuration rows; no reservation/guest/payment/
--   folio/food/service business rows are modified.
-- - Adds one AFTER INSERT hotel trigger so future hotels receive defaults.
-- - Does not touch production deployment, Cashfree, or Git.
-- ============================================================================

begin;

set local lock_timeout = '10s';
set local statement_timeout = '120s';

select pg_advisory_xact_lock(
  hashtext('stayqr:202608090066:business-day-settings-invariant:rev1')
);

-- --------------------------------------------------------------------------
-- 1. PRECHECK
-- --------------------------------------------------------------------------

do $precheck$
begin
  if to_regclass('public.hotels') is null then
    raise exception 'Migration 066 precheck failed: public.hotels is missing.';
  end if;

  if to_regclass('public.business_day_settings') is null then
    raise exception
      'Migration 066 precheck failed: public.business_day_settings is missing.';
  end if;

  if to_regclass('public.hotel_settings') is null then
    raise exception
      'Migration 066 precheck failed: public.hotel_settings is missing.';
  end if;
end;
$precheck$;

-- --------------------------------------------------------------------------
-- 2. FUTURE-HOTEL INVARIANT
-- --------------------------------------------------------------------------

create or replace function private.day19_ensure_business_day_settings_for_hotel()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  insert into public.business_day_settings (
    hotel_id,
    business_day_cutoff,
    week_starts_on,
    night_audit_time,
    locale,
    created_at,
    updated_at
  )
  values (
    new.id,
    '00:00'::time,
    1,
    '02:00'::time,
    'en-IN',
    now(),
    now()
  )
  on conflict (hotel_id) do nothing;

  return new;
end;
$function$;

revoke all on function private.day19_ensure_business_day_settings_for_hotel()
from public, anon, authenticated;

drop trigger if exists day19_ensure_business_day_settings_after_hotel_insert
on public.hotels;

create trigger day19_ensure_business_day_settings_after_hotel_insert
after insert on public.hotels
for each row
execute function private.day19_ensure_business_day_settings_for_hotel();

-- --------------------------------------------------------------------------
-- 3. BACKFILL CURRENT HOTELS
-- --------------------------------------------------------------------------

insert into public.business_day_settings (
  hotel_id,
  business_day_cutoff,
  week_starts_on,
  night_audit_time,
  locale,
  created_at,
  updated_at
)
select
  h.id,
  '00:00'::time,
  1,
  '02:00'::time,
  coalesce(nullif(trim(hs.locale), ''), 'en-IN'),
  now(),
  now()
from public.hotels h
left join public.hotel_settings hs
  on hs.hotel_id = h.id
where not exists (
  select 1
  from public.business_day_settings bds
  where bds.hotel_id = h.id
)
on conflict (hotel_id) do nothing;

-- --------------------------------------------------------------------------
-- 4. PRE-COMMIT VERIFICATION
-- --------------------------------------------------------------------------

do $verify$
declare
  v_missing integer;
  v_trigger_ok boolean;
  v_function_secure boolean;
begin
  select count(*)
  into v_missing
  from public.hotels h
  where not exists (
    select 1
    from public.business_day_settings bds
    where bds.hotel_id = h.id
  );

  select exists (
    select 1
    from pg_catalog.pg_trigger t
    join pg_catalog.pg_class c
      on c.oid = t.tgrelid
    join pg_catalog.pg_namespace n
      on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'hotels'
      and t.tgname = 'day19_ensure_business_day_settings_after_hotel_insert'
      and not t.tgisinternal
  )
  into v_trigger_ok;

  select
    p.prosecdef
    and not has_function_privilege(
      'anon',
      'private.day19_ensure_business_day_settings_for_hotel()',
      'EXECUTE'
    )
    and not has_function_privilege(
      'authenticated',
      'private.day19_ensure_business_day_settings_for_hotel()',
      'EXECUTE'
    )
  into v_function_secure
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n
    on n.oid = p.pronamespace
  where n.nspname = 'private'
    and p.proname = 'day19_ensure_business_day_settings_for_hotel'
    and pg_catalog.pg_get_function_identity_arguments(p.oid) = '';

  if v_missing <> 0 then
    raise exception
      'Migration 066 verification failed: % hotel(s) still lack business-day settings.',
      v_missing;
  end if;

  if not coalesce(v_trigger_ok, false) then
    raise exception
      'Migration 066 verification failed: future-hotel trigger is missing.';
  end if;

  if not coalesce(v_function_secure, false) then
    raise exception
      'Migration 066 verification failed: trigger function security boundary is incorrect.';
  end if;
end;
$verify$;

commit;

-- --------------------------------------------------------------------------
-- 5. POST-COMMIT EVIDENCE
-- --------------------------------------------------------------------------

select
  'M066_POSTCOMMIT'::text as suite,
  (
    not exists (
      select 1
      from public.hotels h
      where not exists (
        select 1
        from public.business_day_settings bds
        where bds.hotel_id = h.id
      )
    )
    and exists (
      select 1
      from pg_catalog.pg_trigger t
      join pg_catalog.pg_class c
        on c.oid = t.tgrelid
      join pg_catalog.pg_namespace n
        on n.oid = c.relnamespace
      where n.nspname = 'public'
        and c.relname = 'hotels'
        and t.tgname = 'day19_ensure_business_day_settings_after_hotel_insert'
        and not t.tgisinternal
    )
  ) as passed,
  (
    select format(
      'hotels=%s business_day_settings=%s',
      (select count(*) from public.hotels),
      (select count(*) from public.business_day_settings)
    )
  ) as details;
