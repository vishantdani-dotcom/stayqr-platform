-- StayQR Day 6: authentication, staff identity and permission foundation
-- Run once in Supabase SQL Editor with role postgres.

begin;

select pg_advisory_xact_lock(hashtext('stayqr:202607250011:day6-auth-staff'));

create schema if not exists private;

-- --------------------------------------------------------------------------
-- 1. Staff lifecycle metadata
-- --------------------------------------------------------------------------

alter table public.staff
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists invited_at timestamptz,
  add column if not exists invitation_sent_at timestamptz,
  add column if not exists accepted_at timestamptz,
  add column if not exists disabled_at timestamptz,
  add column if not exists created_by uuid references auth.users(id) on delete set null,
  add column if not exists updated_by uuid references auth.users(id) on delete set null;

alter table public.hotel_users
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists invited_at timestamptz,
  add column if not exists accepted_at timestamptz,
  add column if not exists disabled_at timestamptz;

update public.staff
set
  status = case lower(coalesce(status, 'active'))
    when 'disabled' then 'inactive'
    when 'archived' then 'inactive'
    else lower(coalesce(status, 'active'))
  end,
  updated_at = coalesce(updated_at, created_at, now());

update public.hotel_users
set
  status = case lower(coalesce(status, 'active'))
    when 'disabled' then 'inactive'
    when 'archived' then 'inactive'
    else lower(coalesce(status, 'active'))
  end,
  updated_at = coalesce(updated_at, created_at, now());

alter table public.staff drop constraint if exists staff_status_check;
alter table public.staff
  add constraint staff_status_check
  check (status in ('active', 'invited', 'inactive', 'suspended'))
  not valid;
alter table public.staff validate constraint staff_status_check;

alter table public.hotel_users drop constraint if exists hotel_users_status_check;
alter table public.hotel_users
  add constraint hotel_users_status_check
  check (status in ('active', 'invited', 'inactive', 'suspended'))
  not valid;
alter table public.hotel_users validate constraint hotel_users_status_check;

create index if not exists idx_staff_hotel_status_role
on public.staff (hotel_id, status, role);

create index if not exists idx_staff_auth_status
on public.staff (auth_user_id, status)
where auth_user_id is not null;

-- --------------------------------------------------------------------------
-- 2. Updated-at triggers
-- --------------------------------------------------------------------------

create or replace function private.set_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists staff_set_updated_at on public.staff;
create trigger staff_set_updated_at
before update on public.staff
for each row execute function private.set_updated_at();

drop trigger if exists hotel_users_set_updated_at on public.hotel_users;
create trigger hotel_users_set_updated_at
before update on public.hotel_users
for each row execute function private.set_updated_at();

-- --------------------------------------------------------------------------
-- 3. Canonical roles and permission matrix
-- --------------------------------------------------------------------------

insert into public.staff_roles (role_name, description)
values
  ('owner', 'Hotel owner with full hotel administration access.'),
  ('manager', 'Hotel manager with operational and staff administration access.'),
  ('reception', 'Front desk access to reservations, arrivals, guests and payments.'),
  ('housekeeping', 'Room cleaning, housekeeping and service-request access.'),
  ('restaurant', 'Menu and food-order operations access.'),
  ('accounts', 'Payments, charges, invoices and reporting access.')
on conflict (role_name) do update
set description = excluded.description;

with permission_seed(role_name, permission_key) as (
  values
    ('owner','dashboard.view'),('owner','reservations.view'),('owner','reservations.manage'),
    ('owner','checkin.manage'),('owner','checkout.manage'),('owner','calendar.view'),
    ('owner','calendar.manage'),('owner','rooms.view'),('owner','rooms.manage'),
    ('owner','guests.view'),('owner','guests.manage'),('owner','payments.view'),
    ('owner','payments.manage'),('owner','services.view'),('owner','services.manage'),
    ('owner','foodorders.view'),('owner','foodorders.manage'),('owner','housekeeping.view'),
    ('owner','housekeeping.manage'),('owner','menu.manage'),('owner','staff.view'),
    ('owner','staff.manage'),('owner','hotel.manage'),('owner','reports.view'),
    ('owner','invoices.view'),('owner','invoices.manage'),

    ('manager','dashboard.view'),('manager','reservations.view'),('manager','reservations.manage'),
    ('manager','checkin.manage'),('manager','checkout.manage'),('manager','calendar.view'),
    ('manager','calendar.manage'),('manager','rooms.view'),('manager','rooms.manage'),
    ('manager','guests.view'),('manager','guests.manage'),('manager','payments.view'),
    ('manager','payments.manage'),('manager','services.view'),('manager','services.manage'),
    ('manager','foodorders.view'),('manager','foodorders.manage'),('manager','housekeeping.view'),
    ('manager','housekeeping.manage'),('manager','menu.manage'),('manager','staff.view'),
    ('manager','staff.manage'),('manager','hotel.manage'),('manager','reports.view'),
    ('manager','invoices.view'),('manager','invoices.manage'),

    ('reception','dashboard.view'),('reception','reservations.view'),
    ('reception','reservations.manage'),('reception','checkin.manage'),
    ('reception','checkout.manage'),('reception','calendar.view'),
    ('reception','calendar.manage'),('reception','rooms.view'),('reception','guests.view'),
    ('reception','guests.manage'),('reception','payments.view'),
    ('reception','payments.manage'),('reception','services.view'),
    ('reception','services.manage'),('reception','invoices.view'),

    ('housekeeping','dashboard.view'),('housekeeping','rooms.view'),
    ('housekeeping','services.view'),('housekeeping','services.manage'),
    ('housekeeping','housekeeping.view'),('housekeeping','housekeeping.manage'),

    ('restaurant','dashboard.view'),('restaurant','foodorders.view'),
    ('restaurant','foodorders.manage'),('restaurant','menu.manage'),

    ('accounts','dashboard.view'),('accounts','payments.view'),
    ('accounts','payments.manage'),('accounts','reports.view'),
    ('accounts','invoices.view'),('accounts','invoices.manage')
)
insert into public.role_permissions (role_name, permission_key)
select role_name, permission_key from permission_seed
on conflict do nothing;

-- --------------------------------------------------------------------------
-- 4. Permission helpers. Identity is resolved from database membership only.
-- --------------------------------------------------------------------------

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
      join public.role_permissions rp
        on lower(replace(trim(rp.role_name), ' ', '_')) =
           lower(replace(trim(s.role), ' ', '_'))
      where s.hotel_id = target_hotel_id
        and s.auth_user_id = (select auth.uid())
        and s.status = 'active'
        and h.status = 'active'
        and rp.permission_key = target_permission
    )
    or exists (
      select 1
      from public.hotel_users hu
      join public.hotels h on h.id = hu.hotel_id
      join public.role_permissions rp
        on lower(replace(trim(rp.role_name), ' ', '_')) =
           lower(replace(trim(hu.role), ' ', '_'))
      where hu.hotel_id = target_hotel_id
        and hu.user_id = (select auth.uid())
        and hu.status = 'active'
        and h.status = 'active'
        and rp.permission_key = target_permission
    );
$$;

revoke all on function private.user_has_permission(uuid,text) from public;
grant execute on function private.user_has_permission(uuid,text) to authenticated;

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
    from public.hotel_users hu
    join public.role_permissions rp
      on lower(replace(trim(rp.role_name), ' ', '_')) =
         lower(replace(trim(hu.role), ' ', '_'))
    where hu.hotel_id = target_hotel_id
      and hu.user_id = (select auth.uid())
      and hu.status = 'active'

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
-- 5. Invite acceptance. Called only by the authenticated invited user.
-- --------------------------------------------------------------------------

create or replace function public.activate_my_staff_invitation()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  current_email text := lower(coalesce((select auth.jwt() ->> 'email'), ''));
  activated_staff integer := 0;
  activated_memberships integer := 0;
begin
  if current_user_id is null or current_email = '' then
    raise exception 'Authentication is required.' using errcode = '28000';
  end if;

  update public.staff s
  set
    status = 'active',
    accepted_at = coalesce(s.accepted_at, now()),
    disabled_at = null,
    updated_by = current_user_id
  where s.auth_user_id = current_user_id
    and lower(s.email) = current_email
    and s.status = 'invited';
  get diagnostics activated_staff = row_count;

  update public.hotel_users hu
  set
    status = 'active',
    accepted_at = coalesce(hu.accepted_at, now()),
    disabled_at = null
  where hu.user_id = current_user_id
    and lower(hu.email) = current_email
    and hu.status = 'invited';
  get diagnostics activated_memberships = row_count;

  return jsonb_build_object(
    'staff_activated', activated_staff,
    'memberships_activated', activated_memberships
  );
end;
$$;

revoke all on function public.activate_my_staff_invitation() from public;
grant execute on function public.activate_my_staff_invitation() to authenticated;

-- --------------------------------------------------------------------------
-- 6. Keep the compatibility hotel_users membership synchronized from staff.
-- --------------------------------------------------------------------------

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
      disabled_at = coalesce(hu.disabled_at, now())
    where hu.hotel_id = old.hotel_id
      and (
        (old.auth_user_id is not null and hu.user_id = old.auth_user_id)
        or lower(hu.email) = lower(old.email)
      );
    return old;
  end if;

  select hu.id into membership_id
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
      disabled_at
    ) values (
      new.hotel_id,
      new.full_name,
      lower(new.email),
      new.role,
      new.auth_user_id,
      new.status,
      new.invited_at,
      new.accepted_at,
      new.disabled_at
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
      disabled_at = new.disabled_at
    where hu.id = membership_id;
  end if;

  return new;
end;
$$;

drop trigger if exists staff_sync_hotel_user on public.staff;
create trigger staff_sync_hotel_user
after insert or update of full_name, email, role, status, auth_user_id,
  invited_at, accepted_at, disabled_at
on public.staff
for each row execute function private.sync_staff_to_hotel_user();

drop trigger if exists staff_delete_sync_hotel_user on public.staff;
create trigger staff_delete_sync_hotel_user
after delete on public.staff
for each row execute function private.sync_staff_to_hotel_user();

-- Synchronize existing linked staff records now.
update public.staff
set full_name = full_name;

-- --------------------------------------------------------------------------
-- 7. Staff identity writes must go through the trusted Edge Function.
-- --------------------------------------------------------------------------

revoke insert, update, delete on public.staff from authenticated;
revoke insert, update, delete on public.hotel_users from authenticated;
grant select on public.staff to authenticated;
grant select on public.hotel_users to authenticated;

-- Staff list remains hotel scoped; management authority is checked server-side.
alter table public.staff enable row level security;
alter table public.hotel_users enable row level security;

-- --------------------------------------------------------------------------
-- 8. Final assertions
-- --------------------------------------------------------------------------

do $$
begin
  if to_regprocedure('private.user_has_permission(uuid,text)') is null then
    raise exception 'Day 6 migration failed: permission helper is missing.';
  end if;

  if to_regprocedure('public.activate_my_staff_invitation()') is null then
    raise exception 'Day 6 migration failed: invitation activation RPC is missing.';
  end if;

  if not exists (
    select 1 from public.role_permissions
    where lower(role_name) = 'manager' and permission_key = 'staff.manage'
  ) then
    raise exception 'Day 6 migration failed: staff.manage permission was not seeded.';
  end if;
end
$$;

commit;

-- Supabase may show one blank pg_advisory_xact_lock row. That is expected.
