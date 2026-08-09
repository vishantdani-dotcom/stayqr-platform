-- ============================================================================
-- StayQR v1.0
-- Day 19 Migration 069 REV1
-- Gate 19C — hotel_onboarding cross-tenant RLS hardening
-- Date: 2026-08-09
--
-- EVIDENCE / ROOT CAUSE
-- Audit 078 REV6 executed a real authenticated Hotel A -> Hotel B INSERT attack.
-- 124/125 cross-tenant INSERT attempts wrote zero unauthorized rows. The single
-- breach was public.hotel_onboarding.
--
-- The inherited Day 8 direct INSERT / UPDATE policies allowed:
--   owner_user_id = auth.uid()
-- independently of hotel_id. Therefore Hotel A could construct a Hotel B
-- onboarding row while setting owner_user_id to Hotel A's own authenticated uid.
--
-- SAFE SUPPORTED ONBOARDING PATH
-- Day 8 already installed SECURITY DEFINER onboarding RPCs with their own
-- authorization checks:
--   public.bootstrap_hotel_onboarding(jsonb)
--   public.save_hotel_onboarding_step(uuid,text,jsonb)
--
-- CHANGE
-- Remove only the owner_user_id bypass from DIRECT INSERT and DIRECT UPDATE.
-- Keep same-hotel hotel.manage authorization and Platform Admin authorization.
-- Keep SELECT and DELETE policies unchanged.
-- No hotel, guest, reservation, payment, folio, room or other business row is
-- modified by this migration.
-- ============================================================================

begin;

set local lock_timeout = '10s';
set local statement_timeout = '90s';

select pg_advisory_xact_lock(
  hashtext('stayqr:202608090069:hotel-onboarding-cross-tenant-rls')
);

-- --------------------------------------------------------------------------
-- 1. PRECONDITIONS
-- --------------------------------------------------------------------------

do $preflight$
begin
  if to_regclass('public.hotel_onboarding') is null then
    raise exception
      'Migration 069 stopped: public.hotel_onboarding is missing.';
  end if;

  if not coalesce((
    select c.relrowsecurity
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'hotel_onboarding'
  ), false) then
    raise exception
      'Migration 069 stopped: hotel_onboarding RLS is not enabled.';
  end if;

  if to_regprocedure('public.bootstrap_hotel_onboarding(jsonb)') is null
     or to_regprocedure(
       'public.save_hotel_onboarding_step(uuid,text,jsonb)'
     ) is null
  then
    raise exception
      'Migration 069 stopped: supported Day 8 onboarding RPCs are missing.';
  end if;

  if not has_function_privilege(
    'authenticated',
    'public.bootstrap_hotel_onboarding(jsonb)',
    'EXECUTE'
  ) or not has_function_privilege(
    'authenticated',
    'public.save_hotel_onboarding_step(uuid,text,jsonb)',
    'EXECUTE'
  ) then
    raise exception
      'Migration 069 stopped: authenticated onboarding RPC execution is incomplete.';
  end if;

  if has_function_privilege(
    'anon',
    'public.bootstrap_hotel_onboarding(jsonb)',
    'EXECUTE'
  ) or has_function_privilege(
    'anon',
    'public.save_hotel_onboarding_step(uuid,text,jsonb)',
    'EXECUTE'
  ) then
    raise exception
      'Migration 069 stopped: anon can execute a protected onboarding RPC.';
  end if;
end
$preflight$;

-- --------------------------------------------------------------------------
-- 2. HARDEN DIRECT INSERT
-- --------------------------------------------------------------------------

drop policy if exists stayqr_hotel_onboarding_insert
on public.hotel_onboarding;

create policy stayqr_hotel_onboarding_insert
on public.hotel_onboarding
for insert
to authenticated
with check (
  private.is_platform_admin()
  or private.user_has_permission(hotel_id, 'hotel.manage')
);

-- --------------------------------------------------------------------------
-- 3. HARDEN DIRECT UPDATE
-- --------------------------------------------------------------------------

drop policy if exists stayqr_hotel_onboarding_update
on public.hotel_onboarding;

create policy stayqr_hotel_onboarding_update
on public.hotel_onboarding
for update
to authenticated
using (
  private.is_platform_admin()
  or private.user_has_permission(hotel_id, 'hotel.manage')
)
with check (
  private.is_platform_admin()
  or private.user_has_permission(hotel_id, 'hotel.manage')
);

-- --------------------------------------------------------------------------
-- 4. VERIFY BEFORE COMMIT
-- --------------------------------------------------------------------------

do $verify$
declare
  v_insert_check text;
  v_update_using text;
  v_update_check text;
begin
  select p.with_check
  into v_insert_check
  from pg_policies p
  where p.schemaname = 'public'
    and p.tablename = 'hotel_onboarding'
    and p.policyname = 'stayqr_hotel_onboarding_insert';

  if v_insert_check is null then
    raise exception
      'Migration 069 verification failed: onboarding INSERT policy is missing.';
  end if;

  if v_insert_check ~* 'owner_user_id' then
    raise exception
      'Migration 069 verification failed: owner_user_id remains in direct INSERT authorization.';
  end if;

  if v_insert_check !~* 'user_has_permission'
     or v_insert_check !~* 'hotel.manage'
  then
    raise exception
      'Migration 069 verification failed: INSERT is not hotel.manage scoped.';
  end if;

  select p.qual, p.with_check
  into v_update_using, v_update_check
  from pg_policies p
  where p.schemaname = 'public'
    and p.tablename = 'hotel_onboarding'
    and p.policyname = 'stayqr_hotel_onboarding_update';

  if v_update_using is null or v_update_check is null then
    raise exception
      'Migration 069 verification failed: onboarding UPDATE policy is incomplete.';
  end if;

  if v_update_using ~* 'owner_user_id'
     or v_update_check ~* 'owner_user_id'
  then
    raise exception
      'Migration 069 verification failed: owner_user_id remains in direct UPDATE authorization.';
  end if;

  if v_update_using !~* 'user_has_permission'
     or v_update_check !~* 'user_has_permission'
     or v_update_using !~* 'hotel.manage'
     or v_update_check !~* 'hotel.manage'
  then
    raise exception
      'Migration 069 verification failed: UPDATE is not hotel.manage scoped.';
  end if;

  if not has_function_privilege(
    'authenticated',
    'public.bootstrap_hotel_onboarding(jsonb)',
    'EXECUTE'
  ) or not has_function_privilege(
    'authenticated',
    'public.save_hotel_onboarding_step(uuid,text,jsonb)',
    'EXECUTE'
  ) then
    raise exception
      'Migration 069 verification failed: supported onboarding RPC path was damaged.';
  end if;

  if has_function_privilege(
    'anon',
    'public.bootstrap_hotel_onboarding(jsonb)',
    'EXECUTE'
  ) or has_function_privilege(
    'anon',
    'public.save_hotel_onboarding_step(uuid,text,jsonb)',
    'EXECUTE'
  ) then
    raise exception
      'Migration 069 verification failed: anon onboarding RPC exposure detected.';
  end if;
end
$verify$;

commit;

-- --------------------------------------------------------------------------
-- 5. POST-COMMIT EVIDENCE
-- --------------------------------------------------------------------------

select
  'M069_POSTCOMMIT'::text as suite,
  (
    exists (
      select 1
      from pg_policies p
      where p.schemaname = 'public'
        and p.tablename = 'hotel_onboarding'
        and p.policyname = 'stayqr_hotel_onboarding_insert'
        and coalesce(p.with_check, '') !~* 'owner_user_id'
        and coalesce(p.with_check, '') ~* 'user_has_permission'
        and coalesce(p.with_check, '') ~* 'hotel.manage'
    )
    and exists (
      select 1
      from pg_policies p
      where p.schemaname = 'public'
        and p.tablename = 'hotel_onboarding'
        and p.policyname = 'stayqr_hotel_onboarding_update'
        and coalesce(p.qual, '') !~* 'owner_user_id'
        and coalesce(p.with_check, '') !~* 'owner_user_id'
        and coalesce(p.qual, '') ~* 'user_has_permission'
        and coalesce(p.with_check, '') ~* 'user_has_permission'
        and coalesce(p.qual, '') ~* 'hotel.manage'
        and coalesce(p.with_check, '') ~* 'hotel.manage'
    )
    and has_function_privilege(
      'authenticated',
      'public.bootstrap_hotel_onboarding(jsonb)',
      'EXECUTE'
    )
    and has_function_privilege(
      'authenticated',
      'public.save_hotel_onboarding_step(uuid,text,jsonb)',
      'EXECUTE'
    )
    and not has_function_privilege(
      'anon',
      'public.bootstrap_hotel_onboarding(jsonb)',
      'EXECUTE'
    )
    and not has_function_privilege(
      'anon',
      'public.save_hotel_onboarding_step(uuid,text,jsonb)',
      'EXECUTE'
    )
  ) as passed,
  'hotel_onboarding direct INSERT/UPDATE are same-hotel hotel.manage scoped; supported authenticated onboarding RPCs remain intact.'::text
    as details;
