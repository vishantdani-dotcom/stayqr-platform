-- StayQR Day 6 final hardening: identity reconciliation and action authorization
-- REV2: PostgreSQL-compatible UUID candidate aggregation (min(uuid) replaced with min(uuid::text)::uuid).
-- Run once in Supabase SQL Editor with role postgres.

begin;

set local lock_timeout = '10s';
set local statement_timeout = '180s';

select pg_advisory_xact_lock(
  hashtext('stayqr:202607250012:day6-identity-authorization')
);

create schema if not exists private;
revoke all on schema private from public, anon;

-- --------------------------------------------------------------------------
-- 1. Identity reconciliation metadata and immutable audit snapshots
-- --------------------------------------------------------------------------

alter table public.staff
  add column if not exists identity_reconciliation_status text,
  add column if not exists identity_reconciliation_note text,
  add column if not exists identity_reconciled_at timestamptz;

alter table public.hotel_users
  add column if not exists identity_reconciliation_status text,
  add column if not exists identity_reconciliation_note text,
  add column if not exists identity_reconciled_at timestamptz;

create table if not exists private.day6_identity_reconciliation_archive_20260725 (
  archive_id bigint generated always as identity primary key,
  source_table text not null,
  source_id uuid not null,
  hotel_id uuid,
  reason text not null,
  row_snapshot jsonb not null,
  archived_at timestamptz not null default now(),
  unique (source_table, source_id, reason)
);

revoke all on private.day6_identity_reconciliation_archive_20260725
from public, anon, authenticated;

insert into private.day6_identity_reconciliation_archive_20260725 (
  source_table,
  source_id,
  hotel_id,
  reason,
  row_snapshot
)
select
  'staff',
  s.id,
  s.hotel_id,
  case
    when s.auth_user_id is null and s.status in ('active', 'invited')
      then 'active_or_invited_staff_without_auth_identity'
    when s.auth_user_id is not null and au.id is null
      then 'staff_references_missing_auth_identity'
    when s.auth_user_id is not null
      and au.id is not null
      and lower(s.email) <> lower(coalesce(au.email, ''))
      then 'staff_email_differs_from_auth_identity'
    else 'staff_identity_reconciliation_baseline'
  end,
  to_jsonb(s)
from public.staff s
left join auth.users au on au.id = s.auth_user_id
where s.auth_user_id is null
   or au.id is null
   or lower(s.email) <> lower(coalesce(au.email, ''))
on conflict do nothing;

insert into private.day6_identity_reconciliation_archive_20260725 (
  source_table,
  source_id,
  hotel_id,
  reason,
  row_snapshot
)
select
  'hotel_users',
  hu.id,
  hu.hotel_id,
  case
    when hu.user_id is null and hu.status in ('active', 'invited')
      then 'active_or_invited_membership_without_auth_identity'
    when hu.user_id is not null and au.id is null
      then 'membership_references_missing_auth_identity'
    when hu.user_id is not null
      and au.id is not null
      and lower(hu.email) <> lower(coalesce(au.email, ''))
      then 'membership_email_differs_from_auth_identity'
    else 'membership_identity_reconciliation_baseline'
  end,
  to_jsonb(hu)
from public.hotel_users hu
left join auth.users au on au.id = hu.user_id
where hu.user_id is null
   or au.id is null
   or lower(hu.email) <> lower(coalesce(au.email, ''))
on conflict do nothing;

-- --------------------------------------------------------------------------
-- 2. Safe automatic linking and authoritative staff creation
-- --------------------------------------------------------------------------

-- Link an unlinked staff row only when its verified email resolves to exactly
-- one Auth user and that Auth user is not already represented in the hotel.
with auth_email_candidates as (
  select
    s.id as staff_id,
    min(au.id::text)::uuid as auth_user_id,
    count(*) as auth_matches
  from public.staff s
  join auth.users au
    on lower(coalesce(au.email, '')) = lower(s.email)
  where s.auth_user_id is null
  group by s.id
), safe_candidates as (
  select candidate.staff_id, candidate.auth_user_id
  from auth_email_candidates candidate
  join public.staff target on target.id = candidate.staff_id
  where candidate.auth_matches = 1
    and not exists (
      select 1
      from public.staff duplicate
      where duplicate.hotel_id = target.hotel_id
        and duplicate.auth_user_id = candidate.auth_user_id
        and duplicate.id <> target.id
    )
)
update public.staff s
set
  auth_user_id = candidate.auth_user_id,
  email = lower(au.email),
  identity_reconciliation_status = 'linked',
  identity_reconciliation_note = 'Linked automatically by exact verified Auth email.',
  identity_reconciled_at = now(),
  updated_at = now()
from safe_candidates candidate
join auth.users au on au.id = candidate.auth_user_id
where s.id = candidate.staff_id;

-- If a valid active membership exists without a matching staff row, create the
-- authoritative staff identity so removing hotel_users as an access source does
-- not remove legitimate access.
insert into public.staff (
  hotel_id,
  full_name,
  email,
  phone,
  role,
  status,
  auth_user_id,
  created_at,
  updated_at,
  invited_at,
  accepted_at,
  disabled_at,
  identity_reconciliation_status,
  identity_reconciliation_note,
  identity_reconciled_at
)
select
  hu.hotel_id,
  hu.full_name,
  lower(coalesce(au.email, hu.email)),
  null,
  lower(replace(trim(coalesce(hu.role, 'reception')), ' ', '_')),
  hu.status,
  hu.user_id,
  coalesce(hu.created_at, now()),
  now(),
  hu.invited_at,
  hu.accepted_at,
  hu.disabled_at,
  'linked',
  'Authoritative staff row created from an existing linked hotel membership.',
  now()
from public.hotel_users hu
join auth.users au on au.id = hu.user_id
where hu.user_id is not null
  and hu.status in ('active', 'invited')
  and not exists (
    select 1
    from public.staff s
    where s.hotel_id = hu.hotel_id
      and s.auth_user_id = hu.user_id
  )
  and not exists (
    select 1
    from public.staff s
    where s.hotel_id = hu.hotel_id
      and lower(s.email) = lower(coalesce(au.email, hu.email))
  );

-- Normalize linked staff to the verified Auth email. The staff row is the
-- authoritative identity and the existing synchronization trigger updates the
-- compatibility membership.
update public.staff s
set
  email = lower(au.email),
  identity_reconciliation_status = 'linked',
  identity_reconciliation_note = case
    when lower(s.email) <> lower(au.email)
      then 'Verified email normalized to the linked Supabase Auth identity.'
    else coalesce(s.identity_reconciliation_note, 'Identity mapping verified.')
  end,
  identity_reconciled_at = now(),
  updated_at = now()
from auth.users au
where s.auth_user_id = au.id
  and au.email is not null;

-- A staff record without a real Auth identity cannot remain active or invited.
-- Preserve it as an inactive historical profile that can be restored through
-- the trusted "Send identity invite" action.
update public.staff s
set
  status = 'inactive',
  disabled_at = coalesce(s.disabled_at, now()),
  identity_reconciliation_status = 'archived_unlinked',
  identity_reconciliation_note =
    'Legacy staff profile preserved without login access. Send an identity invite to restore it.',
  identity_reconciled_at = now(),
  updated_at = now()
where s.auth_user_id is null
  and s.status in ('active', 'invited');

-- References to deleted Auth users are also quarantined without deleting the
-- historical staff profile.
update public.staff s
set
  auth_user_id = null,
  status = 'inactive',
  disabled_at = coalesce(s.disabled_at, now()),
  identity_reconciliation_status = 'archived_missing_auth',
  identity_reconciliation_note =
    'The previously linked Auth identity no longer exists. Send a new identity invite to restore access.',
  identity_reconciled_at = now(),
  updated_at = now()
where s.auth_user_id is not null
  and not exists (select 1 from auth.users au where au.id = s.auth_user_id);

-- The synchronization trigger has already aligned memberships for staff rows.
-- Quarantine any remaining independent membership without a valid identity.
update public.hotel_users hu
set
  status = 'inactive',
  disabled_at = coalesce(hu.disabled_at, now()),
  identity_reconciliation_status = 'archived_unlinked',
  identity_reconciliation_note =
    'Legacy compatibility membership preserved without login access.',
  identity_reconciled_at = now(),
  updated_at = now()
where hu.user_id is null
  and hu.status in ('active', 'invited');

update public.hotel_users hu
set
  user_id = null,
  status = 'inactive',
  disabled_at = coalesce(hu.disabled_at, now()),
  identity_reconciliation_status = 'archived_missing_auth',
  identity_reconciliation_note =
    'The previously linked Auth identity no longer exists.',
  identity_reconciled_at = now(),
  updated_at = now()
where hu.user_id is not null
  and not exists (select 1 from auth.users au where au.id = hu.user_id);

update public.staff s
set
  identity_reconciliation_status = coalesce(
    s.identity_reconciliation_status,
    'archived_unlinked'
  ),
  identity_reconciliation_note = coalesce(
    s.identity_reconciliation_note,
    'Inactive legacy staff profile preserved without login access.'
  ),
  identity_reconciled_at = coalesce(s.identity_reconciled_at, now()),
  updated_at = now()
where s.auth_user_id is null
  and s.status = 'inactive';

update public.hotel_users hu
set
  identity_reconciliation_status = coalesce(
    hu.identity_reconciliation_status,
    'archived_unlinked'
  ),
  identity_reconciliation_note = coalesce(
    hu.identity_reconciliation_note,
    'Inactive legacy compatibility membership preserved without login access.'
  ),
  identity_reconciled_at = coalesce(hu.identity_reconciled_at, now()),
  updated_at = now()
where hu.user_id is null
  and hu.status = 'inactive';

update public.hotel_users hu
set
  email = lower(au.email),
  identity_reconciliation_status = 'linked',
  identity_reconciliation_note = coalesce(
    hu.identity_reconciliation_note,
    'Compatibility membership verified against Supabase Auth.'
  ),
  identity_reconciled_at = now(),
  updated_at = now()
from auth.users au
where hu.user_id = au.id
  and au.email is not null;

-- Keep the compatibility membership aligned with the new reconciliation
-- metadata as well as the core identity fields.
create or replace function private.sync_staff_to_hotel_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  membership_id uuid;
begin
  if tg_op = 'DELETE' then
    update public.hotel_users hu
    set
      status = 'inactive',
      disabled_at = coalesce(hu.disabled_at, now()),
      identity_reconciliation_status = 'archived_unlinked',
      identity_reconciliation_note =
        'Authoritative staff profile was removed; compatibility membership archived.',
      identity_reconciled_at = now()
    where hu.hotel_id = old.hotel_id
      and (
        (old.auth_user_id is not null and hu.user_id = old.auth_user_id)
        or lower(hu.email) = lower(old.email)
      );
    return old;
  end if;

  select hu.id
  into membership_id
  from public.hotel_users hu
  where hu.hotel_id = new.hotel_id
    and (
      (new.auth_user_id is not null and hu.user_id = new.auth_user_id)
      or lower(hu.email) = lower(new.email)
    )
  order by (hu.user_id = new.auth_user_id) desc nulls last
  limit 1;

  if membership_id is null then
    insert into public.hotel_users (
      hotel_id,
      full_name,
      email,
      role,
      user_id,
      status,
      invited_at,
      accepted_at,
      disabled_at,
      identity_reconciliation_status,
      identity_reconciliation_note,
      identity_reconciled_at
    ) values (
      new.hotel_id,
      new.full_name,
      lower(new.email),
      new.role,
      new.auth_user_id,
      new.status,
      new.invited_at,
      new.accepted_at,
      new.disabled_at,
      new.identity_reconciliation_status,
      new.identity_reconciliation_note,
      new.identity_reconciled_at
    );
  else
    update public.hotel_users hu
    set
      full_name = new.full_name,
      email = lower(new.email),
      role = new.role,
      user_id = new.auth_user_id,
      status = new.status,
      invited_at = new.invited_at,
      accepted_at = new.accepted_at,
      disabled_at = new.disabled_at,
      identity_reconciliation_status = new.identity_reconciliation_status,
      identity_reconciliation_note = new.identity_reconciliation_note,
      identity_reconciled_at = new.identity_reconciled_at
    where hu.id = membership_id;
  end if;

  return new;
end;
$$;

drop trigger if exists staff_sync_hotel_user on public.staff;
create trigger staff_sync_hotel_user
after insert or update of
  full_name,
  email,
  role,
  status,
  auth_user_id,
  invited_at,
  accepted_at,
  disabled_at,
  identity_reconciliation_status,
  identity_reconciliation_note,
  identity_reconciled_at
on public.staff
for each row execute function private.sync_staff_to_hotel_user();

drop trigger if exists staff_delete_sync_hotel_user on public.staff;
create trigger staff_delete_sync_hotel_user
after delete on public.staff
for each row execute function private.sync_staff_to_hotel_user();

-- --------------------------------------------------------------------------
-- 3. Enforce identity-backed active access
-- --------------------------------------------------------------------------

alter table public.staff
  drop constraint if exists staff_active_identity_required;

alter table public.staff
  add constraint staff_active_identity_required
  check (
    status not in ('active', 'invited')
    or auth_user_id is not null
  ) not valid;

alter table public.staff validate constraint staff_active_identity_required;

alter table public.hotel_users
  drop constraint if exists hotel_users_active_identity_required;

alter table public.hotel_users
  add constraint hotel_users_active_identity_required
  check (
    status not in ('active', 'invited')
    or user_id is not null
  ) not valid;

alter table public.hotel_users validate constraint hotel_users_active_identity_required;

-- --------------------------------------------------------------------------
-- 4. Durable staff identity event ledger
-- --------------------------------------------------------------------------

create table if not exists public.staff_identity_events (
  id bigint generated always as identity primary key,
  hotel_id uuid not null references public.hotels(id) on delete restrict,
  staff_id uuid references public.staff(id) on delete set null,
  auth_user_id uuid references auth.users(id) on delete set null,
  event_type text not null,
  previous_status text,
  new_status text,
  actor_user_id uuid references auth.users(id) on delete set null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint staff_identity_events_type_check check (
    event_type in (
      'invited', 'linked', 'updated', 'activated', 'disabled',
      'suspended', 'archived', 'reconciled'
    )
  )
);

create index if not exists idx_staff_identity_events_hotel_created
on public.staff_identity_events (hotel_id, created_at desc);

create index if not exists idx_staff_identity_events_staff_created
on public.staff_identity_events (staff_id, created_at desc);

alter table public.staff_identity_events enable row level security;

revoke insert, update, delete on public.staff_identity_events from authenticated;
grant select on public.staff_identity_events to authenticated;

drop policy if exists stayqr_staff_identity_events_select
on public.staff_identity_events;

create policy stayqr_staff_identity_events_select
on public.staff_identity_events
for select
to authenticated
using (private.user_has_permission(hotel_id, 'staff.view'));

insert into public.staff_identity_events (
  hotel_id,
  staff_id,
  auth_user_id,
  event_type,
  previous_status,
  new_status,
  details
)
select
  s.hotel_id,
  s.id,
  s.auth_user_id,
  'reconciled',
  null,
  s.status,
  jsonb_build_object(
    'reconciliation_status', s.identity_reconciliation_status,
    'note', s.identity_reconciliation_note
  )
from public.staff s
where not exists (
  select 1
  from public.staff_identity_events event
  where event.staff_id = s.id
    and event.event_type = 'reconciled'
);

-- --------------------------------------------------------------------------
-- 5. Staff is the sole hotel-access authority; hotel_users is a mirror only
-- --------------------------------------------------------------------------

create or replace function private.user_has_hotel_access(
  target_hotel_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    private.is_platform_admin()
    or exists (
      select 1
      from public.staff s
      join public.hotels h on h.id = s.hotel_id
      join auth.users au on au.id = s.auth_user_id
      where s.hotel_id = target_hotel_id
        and s.auth_user_id = (select auth.uid())
        and s.status = 'active'
        and h.status = 'active'
        and coalesce(au.banned_until, '-infinity'::timestamptz) <= now()
    );
$$;

create or replace function private.user_has_hotel_role(
  target_hotel_id uuid,
  allowed_roles text[]
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    private.is_platform_admin()
    or exists (
      select 1
      from public.staff s
      join auth.users au on au.id = s.auth_user_id
      where s.hotel_id = target_hotel_id
        and s.auth_user_id = (select auth.uid())
        and s.status = 'active'
        and lower(replace(trim(s.role), ' ', '_')) = any(allowed_roles)
        and coalesce(au.banned_until, '-infinity'::timestamptz) <= now()
    );
$$;

create or replace function private.user_has_permission(
  target_hotel_id uuid,
  target_permission text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    private.is_platform_admin()
    or exists (
      select 1
      from public.staff s
      join public.hotels h on h.id = s.hotel_id
      join auth.users au on au.id = s.auth_user_id
      join public.role_permissions rp
        on lower(replace(trim(rp.role_name), ' ', '_')) =
           lower(replace(trim(s.role), ' ', '_'))
      where s.hotel_id = target_hotel_id
        and s.auth_user_id = (select auth.uid())
        and s.status = 'active'
        and h.status = 'active'
        and coalesce(au.banned_until, '-infinity'::timestamptz) <= now()
        and rp.permission_key = target_permission
    );
$$;

create or replace function private.user_has_any_permission(
  target_hotel_id uuid,
  target_permissions text[]
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from unnest(target_permissions) permission_key
    where private.user_has_permission(target_hotel_id, permission_key)
  );
$$;

revoke all on function private.user_has_hotel_access(uuid) from public;
revoke all on function private.user_has_hotel_role(uuid,text[]) from public;
revoke all on function private.user_has_permission(uuid,text) from public;
revoke all on function private.user_has_any_permission(uuid,text[]) from public;

grant execute on function private.user_has_hotel_access(uuid) to authenticated;
grant execute on function private.user_has_hotel_role(uuid,text[]) to authenticated;
grant execute on function private.user_has_permission(uuid,text) to authenticated;
grant execute on function private.user_has_any_permission(uuid,text[]) to authenticated;

create or replace function public.get_my_hotel_permissions(target_hotel_id uuid)
returns table(permission_key text)
language sql
stable
security definer
set search_path = ''
as $$
  select distinct permission.permission_key
  from (
    select rp.permission_key
    from public.staff s
    join public.role_permissions rp
      on lower(replace(trim(rp.role_name), ' ', '_')) =
         lower(replace(trim(s.role), ' ', '_'))
    where s.hotel_id = target_hotel_id
      and s.auth_user_id = (select auth.uid())
      and s.status = 'active'

    union all

    select rp.permission_key
    from public.role_permissions rp
    where private.is_platform_admin()
  ) permission
  where private.user_has_hotel_access(target_hotel_id)
  order by permission.permission_key;
$$;

revoke all on function public.get_my_hotel_permissions(uuid) from public;
grant execute on function public.get_my_hotel_permissions(uuid) to authenticated;

-- --------------------------------------------------------------------------
-- 6. Permission-aware RLS for identity and internal financial operations
-- --------------------------------------------------------------------------

-- Staff lists: users may read their own identity; staff administrators may read
-- the full hotel list.
drop policy if exists stayqr_staff_select on public.staff;
create policy stayqr_staff_select
on public.staff
for select
to authenticated
using (
  auth_user_id = (select auth.uid())
  or private.user_has_permission(hotel_id, 'staff.view')
);

-- hotel_users is retained only as a compatibility mirror.
drop policy if exists stayqr_hotel_users_select on public.hotel_users;
create policy stayqr_hotel_users_select
on public.hotel_users
for select
to authenticated
using (
  user_id = (select auth.uid())
  or private.user_has_permission(hotel_id, 'staff.view')
);

-- Hotel configuration changes require hotel.manage.
drop policy if exists stayqr_hotels_update on public.hotels;
create policy stayqr_hotels_update
on public.hotels
for update
to authenticated
using (private.user_has_permission(id, 'hotel.manage'))
with check (private.user_has_permission(id, 'hotel.manage'));

-- Room types and rates are hotel configuration.
do $$
declare
  config_table text;
begin
  foreach config_table in array array['room_types', 'rate_plans', 'seasonal_rates']
  loop
    execute format('drop policy if exists stayqr_config_insert on public.%I', config_table);
    execute format('drop policy if exists stayqr_config_update on public.%I', config_table);
    execute format('drop policy if exists stayqr_config_delete on public.%I', config_table);

    execute format(
      'create policy stayqr_config_insert on public.%I for insert to authenticated
       with check (private.user_has_permission(hotel_id, ''hotel.manage''))',
      config_table
    );
    execute format(
      'create policy stayqr_config_update on public.%I for update to authenticated
       using (private.user_has_permission(hotel_id, ''hotel.manage''))
       with check (private.user_has_permission(hotel_id, ''hotel.manage''))',
      config_table
    );
    execute format(
      'create policy stayqr_config_delete on public.%I for delete to authenticated
       using (private.user_has_permission(hotel_id, ''hotel.manage''))',
      config_table
    );
  end loop;
end
$$;

-- Reservation tables follow the permission matrix rather than hard-coded role
-- names. This keeps the database and frontend permission model aligned.
do $$
declare
  reservation_table text;
begin
  foreach reservation_table in array array[
    'reservations', 'reservation_rooms', 'reservation_guests'
  ]
  loop
    execute format('drop policy if exists stayqr_reservation_select on public.%I', reservation_table);
    execute format('drop policy if exists stayqr_reservation_insert on public.%I', reservation_table);
    execute format('drop policy if exists stayqr_reservation_update on public.%I', reservation_table);
    execute format('drop policy if exists stayqr_reservation_delete on public.%I', reservation_table);

    execute format(
      'create policy stayqr_reservation_select on public.%I for select to authenticated
       using (private.user_has_permission(hotel_id, ''reservations.view''))',
      reservation_table
    );
    execute format(
      'create policy stayqr_reservation_insert on public.%I for insert to authenticated
       with check (private.user_has_permission(hotel_id, ''reservations.manage''))',
      reservation_table
    );
    execute format(
      'create policy stayqr_reservation_update on public.%I for update to authenticated
       using (private.user_has_permission(hotel_id, ''reservations.manage''))
       with check (private.user_has_permission(hotel_id, ''reservations.manage''))',
      reservation_table
    );
    execute format(
      'create policy stayqr_reservation_delete on public.%I for delete to authenticated
       using (private.user_has_permission(hotel_id, ''reservations.manage''))',
      reservation_table
    );
  end loop;
end
$$;

-- Room blocks are calendar operations.
drop policy if exists stayqr_reservation_select on public.room_blocks;
drop policy if exists stayqr_reservation_insert on public.room_blocks;
drop policy if exists stayqr_reservation_update on public.room_blocks;
drop policy if exists stayqr_reservation_delete on public.room_blocks;

create policy stayqr_reservation_select
on public.room_blocks for select to authenticated
using (private.user_has_permission(hotel_id, 'calendar.view'));
create policy stayqr_reservation_insert
on public.room_blocks for insert to authenticated
with check (private.user_has_permission(hotel_id, 'calendar.manage'));
create policy stayqr_reservation_update
on public.room_blocks for update to authenticated
using (private.user_has_permission(hotel_id, 'calendar.manage'))
with check (private.user_has_permission(hotel_id, 'calendar.manage'));
create policy stayqr_reservation_delete
on public.room_blocks for delete to authenticated
using (private.user_has_permission(hotel_id, 'calendar.manage'));

-- Internal financial tables.
do $$
declare
  financial_table text;
begin
  foreach financial_table in array array[
    'payments', 'payment_collections', 'manual_charges'
  ]
  loop
    execute format('drop policy if exists stayqr_tenant_select on public.%I', financial_table);
    execute format('drop policy if exists stayqr_tenant_insert on public.%I', financial_table);
    execute format('drop policy if exists stayqr_tenant_update on public.%I', financial_table);
    execute format('drop policy if exists stayqr_tenant_delete on public.%I', financial_table);

    execute format(
      'create policy stayqr_tenant_select on public.%I for select to authenticated
       using (private.user_has_permission(hotel_id, ''payments.view''))',
      financial_table
    );
    execute format(
      'create policy stayqr_tenant_insert on public.%I for insert to authenticated
       with check (private.user_has_permission(hotel_id, ''payments.manage''))',
      financial_table
    );
    execute format(
      'create policy stayqr_tenant_update on public.%I for update to authenticated
       using (private.user_has_permission(hotel_id, ''payments.manage''))
       with check (private.user_has_permission(hotel_id, ''payments.manage''))',
      financial_table
    );
    execute format(
      'create policy stayqr_tenant_delete on public.%I for delete to authenticated
       using (private.user_has_permission(hotel_id, ''payments.manage''))',
      financial_table
    );
  end loop;
end
$$;

-- Invoice headers and lines.
do $$
declare
  invoice_table text;
begin
  foreach invoice_table in array array['invoices', 'invoice_items']
  loop
    execute format('drop policy if exists stayqr_tenant_select on public.%I', invoice_table);
    execute format('drop policy if exists stayqr_tenant_insert on public.%I', invoice_table);
    execute format('drop policy if exists stayqr_tenant_update on public.%I', invoice_table);
    execute format('drop policy if exists stayqr_tenant_delete on public.%I', invoice_table);

    execute format(
      'create policy stayqr_tenant_select on public.%I for select to authenticated
       using (private.user_has_permission(hotel_id, ''invoices.view''))',
      invoice_table
    );
    execute format(
      'create policy stayqr_tenant_insert on public.%I for insert to authenticated
       with check (private.user_has_permission(hotel_id, ''invoices.manage''))',
      invoice_table
    );
    execute format(
      'create policy stayqr_tenant_update on public.%I for update to authenticated
       using (private.user_has_permission(hotel_id, ''invoices.manage''))
       with check (private.user_has_permission(hotel_id, ''invoices.manage''))',
      invoice_table
    );
    execute format(
      'create policy stayqr_tenant_delete on public.%I for delete to authenticated
       using (private.user_has_permission(hotel_id, ''invoices.manage''))',
      invoice_table
    );
  end loop;
end
$$;

-- Housekeeping internal tables allow service or housekeeping teams according
-- to the canonical permission matrix.
do $$
declare
  housekeeping_table text;
begin
  foreach housekeeping_table in array array['housekeeping_requests', 'housekeeping_tasks']
  loop
    execute format('drop policy if exists stayqr_tenant_select on public.%I', housekeeping_table);
    execute format('drop policy if exists stayqr_tenant_insert on public.%I', housekeeping_table);
    execute format('drop policy if exists stayqr_tenant_update on public.%I', housekeeping_table);
    execute format('drop policy if exists stayqr_tenant_delete on public.%I', housekeeping_table);

    execute format(
      'create policy stayqr_tenant_select on public.%I for select to authenticated
       using (private.user_has_any_permission(hotel_id, array[''housekeeping.view'', ''services.view'']))',
      housekeeping_table
    );
    execute format(
      'create policy stayqr_tenant_insert on public.%I for insert to authenticated
       with check (private.user_has_any_permission(hotel_id, array[''housekeeping.manage'', ''services.manage'']))',
      housekeeping_table
    );
    execute format(
      'create policy stayqr_tenant_update on public.%I for update to authenticated
       using (private.user_has_any_permission(hotel_id, array[''housekeeping.manage'', ''services.manage'']))
       with check (private.user_has_any_permission(hotel_id, array[''housekeeping.manage'', ''services.manage'']))',
      housekeeping_table
    );
    execute format(
      'create policy stayqr_tenant_delete on public.%I for delete to authenticated
       using (private.user_has_any_permission(hotel_id, array[''housekeeping.manage'', ''services.manage'']))',
      housekeeping_table
    );
  end loop;
end
$$;

-- --------------------------------------------------------------------------
-- 7. Final migration assertions
-- --------------------------------------------------------------------------

do $$
begin
  if exists (
    select 1 from public.staff
    where status in ('active', 'invited') and auth_user_id is null
  ) then
    raise exception 'Day 6 hardening failed: active staff still lacks Auth identity.';
  end if;

  if exists (
    select 1 from public.hotel_users
    where status in ('active', 'invited') and user_id is null
  ) then
    raise exception 'Day 6 hardening failed: active membership still lacks Auth identity.';
  end if;

  if to_regclass('public.staff_identity_events') is null then
    raise exception 'Day 6 hardening failed: staff identity event ledger is missing.';
  end if;

  if to_regprocedure('private.user_has_any_permission(uuid,text[])') is null then
    raise exception 'Day 6 hardening failed: permission helper is missing.';
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.staff'::regclass
      and conname = 'staff_active_identity_required'
      and convalidated
  ) then
    raise exception 'Day 6 hardening failed: active staff identity constraint is missing.';
  end if;
end
$$;

commit;

-- Supabase may display one blank pg_advisory_xact_lock row. That is expected.
