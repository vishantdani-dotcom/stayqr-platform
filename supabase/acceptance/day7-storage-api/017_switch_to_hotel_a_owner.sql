-- ============================================================================
-- StayQR v1.0
-- Day 7 SQL 017 — Temporarily Switch Storage Audit Actor to Hotel A Owner
--
-- PURPOSE
-- The browser has already created real Hotel B files through the Supabase
-- Storage API. This script temporarily changes the signed-in Platform Admin
-- identity into a Hotel A Owner only, so the browser can run genuine Hotel A
-- versus Hotel B Storage API isolation attacks.
--
-- IMPORTANT
-- - Run this only after the temporary audit page shows: fixtures-ready.
-- - This role switch intentionally remains active until SQL 018 is run.
-- - Keep the audit page and browser session open.
-- - Do not perform normal StayQR administration while this test role is active.
--
-- SAFETY
-- - Snapshots the Platform Admin, staff and compatibility membership states.
-- - Requires an existing staff identity for Hotel A; it does not create a new
--   permanent staff account.
-- - SQL 018 restores the snapshotted state.
--
-- Run once in Supabase SQL Editor with role: postgres.
-- Expected result: one row with phase = owner-active and all checks = true.
-- ============================================================================

begin;

set local lock_timeout = '10s';
set local statement_timeout = '180s';

select pg_advisory_xact_lock(
  hashtext('stayqr:day7:storage-api-audit:sql017:20260727')
);

create schema if not exists private;

create table if not exists private.day7_storage_api_audit_context_20260727 (
  context_key text primary key,
  actor_user_id uuid not null,
  actor_email text,
  hotel_a_id uuid not null,
  hotel_a_name text,
  hotel_b_id uuid not null,
  hotel_b_name text,
  fixture_staff_id uuid not null,
  platform_admin_snapshot jsonb not null,
  staff_snapshots jsonb not null,
  hotel_user_snapshots jsonb not null,
  phase text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint day7_storage_api_audit_context_phase_check
    check (phase in ('owner-active', 'isolation-complete', 'restored'))
);

revoke all on private.day7_storage_api_audit_context_20260727
from public, anon, authenticated;

do $switch_actor$
declare
  actor_user uuid;
  actor_email text;

  hotel_a uuid;
  hotel_a_name text;
  hotel_b uuid;
  hotel_b_name text;

  hotel_a_staff_id uuid;

  platform_snapshot jsonb;
  staff_snapshot jsonb;
  membership_snapshot jsonb;

  existing_phase text;

  helper_scope_ok boolean := false;
  owner_permission_ok boolean := false;
  hotel_b_permission_blocked boolean := false;
  active_hotel_a_staff_count integer := 0;
  active_other_staff_count integer := 0;
begin
  select context.phase
  into existing_phase
  from private.day7_storage_api_audit_context_20260727 context
  where context.context_key = 'day7-storage-api';

  if existing_phase in ('owner-active', 'isolation-complete') then
    raise exception
      'SQL 017 is already active with phase %. Run SQL 018 to restore the account before restarting.',
      existing_phase;
  end if;

  delete from private.day7_storage_api_audit_context_20260727
  where context_key = 'day7-storage-api';

  -- Match the browser page's hotel discovery order: the first two active
  -- hotels with rooms, ordered by created_at.
  select h.id, h.hotel_name
  into hotel_a, hotel_a_name
  from public.hotels h
  where h.status = 'active'
    and exists (
      select 1
      from public.rooms r
      where r.hotel_id = h.id
    )
  order by h.created_at
  limit 1;

  select h.id, h.hotel_name
  into hotel_b, hotel_b_name
  from public.hotels h
  where h.status = 'active'
    and h.id <> hotel_a
    and exists (
      select 1
      from public.rooms r
      where r.hotel_id = h.id
    )
  order by h.created_at
  limit 1;

  if hotel_a is null or hotel_b is null or hotel_a = hotel_b then
    raise exception
      'SQL 017 requires two different active hotels with rooms.';
  end if;

  -- Prefer the active Platform Admin who already has a staff identity for
  -- Hotel A. This resolves the same signed-in account shown on the audit page.
  select pa.user_id, au.email
  into actor_user, actor_email
  from public.platform_admins pa
  join auth.users au on au.id = pa.user_id
  where pa.status = 'active'
    and coalesce(au.banned_until, '-infinity'::timestamptz) <= now()
    and exists (
      select 1
      from public.staff s
      where s.auth_user_id = pa.user_id
        and s.hotel_id = hotel_a
    )
  order by pa.created_at
  limit 1;

  if actor_user is null then
    raise exception
      'No active Platform Admin with an existing Hotel A staff identity was found.';
  end if;

  select s.id
  into hotel_a_staff_id
  from public.staff s
  where s.auth_user_id = actor_user
    and s.hotel_id = hotel_a
  order by
    case when s.status = 'active' then 0 else 1 end,
    s.created_at
  limit 1;

  if hotel_a_staff_id is null then
    raise exception
      'The selected audit identity has no reusable Hotel A staff record.';
  end if;

  select to_jsonb(pa)
  into platform_snapshot
  from public.platform_admins pa
  where pa.user_id = actor_user;

  select coalesce(
    jsonb_agg(to_jsonb(s) order by s.created_at),
    '[]'::jsonb
  )
  into staff_snapshot
  from public.staff s
  where s.auth_user_id = actor_user;

  select coalesce(
    jsonb_agg(to_jsonb(hu) order by hu.created_at),
    '[]'::jsonb
  )
  into membership_snapshot
  from public.hotel_users hu
  where hu.user_id = actor_user;

  insert into private.day7_storage_api_audit_context_20260727 (
    context_key,
    actor_user_id,
    actor_email,
    hotel_a_id,
    hotel_a_name,
    hotel_b_id,
    hotel_b_name,
    fixture_staff_id,
    platform_admin_snapshot,
    staff_snapshots,
    hotel_user_snapshots,
    phase,
    created_at,
    updated_at
  ) values (
    'day7-storage-api',
    actor_user,
    actor_email,
    hotel_a,
    hotel_a_name,
    hotel_b,
    hotel_b_name,
    hotel_a_staff_id,
    platform_snapshot,
    staff_snapshot,
    membership_snapshot,
    'owner-active',
    now(),
    now()
  );

  -- Remove global Platform Admin authority.
  update public.platform_admins
  set status = 'inactive',
      updated_at = now()
  where user_id = actor_user;

  -- Disable every hotel membership for this Auth identity first. The staff
  -- trigger synchronizes the compatibility hotel_users mirror.
  update public.staff
  set status = 'inactive',
      disabled_at = coalesce(disabled_at, now()),
      updated_at = now(),
      updated_by = actor_user,
      identity_reconciliation_note =
        'Temporarily disabled by Day 7 Storage API isolation SQL 017.',
      identity_reconciled_at = now()
  where auth_user_id = actor_user;

  -- Activate Hotel A only, with Owner permissions required for positive
  -- Storage controls.
  update public.staff
  set role = 'owner',
      status = 'active',
      disabled_at = null,
      accepted_at = coalesce(accepted_at, now()),
      updated_at = now(),
      updated_by = actor_user,
      identity_reconciliation_status = 'linked',
      identity_reconciliation_note =
        'Temporary Hotel A Owner for Day 7 Storage API runtime isolation.',
      identity_reconciled_at = now()
  where id = hotel_a_staff_id;

  -- Runtime verification as the browser's authenticated JWT identity.
  perform set_config('request.jwt.claim.sub', actor_user::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  execute 'set local role authenticated';

  helper_scope_ok :=
    private.user_has_hotel_access(hotel_a)
    and not private.user_has_hotel_access(hotel_b);

  owner_permission_ok :=
    private.user_has_permission(hotel_a, 'hotel.manage')
    and private.user_has_permission(hotel_a, 'staff.manage');

  hotel_b_permission_blocked :=
    not private.user_has_permission(hotel_b, 'hotel.manage')
    and not private.user_has_permission(hotel_b, 'staff.manage');

  select count(*)
  into active_hotel_a_staff_count
  from public.staff s
  where s.auth_user_id = actor_user
    and s.hotel_id = hotel_a
    and s.status = 'active'
    and lower(replace(trim(s.role), ' ', '_')) = 'owner';

  select count(*)
  into active_other_staff_count
  from public.staff s
  where s.auth_user_id = actor_user
    and s.hotel_id <> hotel_a
    and s.status = 'active';

  execute 'reset role';

  if not helper_scope_ok then
    raise exception
      'SQL 017 verification failed: Hotel A/Hotel B access scope is incorrect.';
  end if;

  if not owner_permission_ok or not hotel_b_permission_blocked then
    raise exception
      'SQL 017 verification failed: Owner permission scope is incorrect.';
  end if;

  if active_hotel_a_staff_count <> 1 or active_other_staff_count <> 0 then
    raise exception
      'SQL 017 verification failed: active staff scope is Hotel A owner=% and other hotels=%.',
      active_hotel_a_staff_count,
      active_other_staff_count;
  end if;
end;
$switch_actor$;

commit;

with context as (
  select *
  from private.day7_storage_api_audit_context_20260727
  where context_key = 'day7-storage-api'
)
select
  phase,
  actor_email,
  hotel_a_name,
  hotel_b_name,
  (
    select pa.status = 'inactive'
    from public.platform_admins pa
    where pa.user_id = context.actor_user_id
  ) as platform_admin_disabled,
  exists (
    select 1
    from public.staff s
    where s.id = context.fixture_staff_id
      and s.hotel_id = context.hotel_a_id
      and s.auth_user_id = context.actor_user_id
      and s.status = 'active'
      and lower(replace(trim(s.role), ' ', '_')) = 'owner'
  ) as hotel_a_owner_active,
  not exists (
    select 1
    from public.staff s
    where s.auth_user_id = context.actor_user_id
      and s.hotel_id = context.hotel_b_id
      and s.status = 'active'
  ) as hotel_b_access_absent
from context;
