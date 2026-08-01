-- ============================================================================
-- StayQR v1.0
-- Migration: 202607200001_tenant_foundation_and_guarded_repairs
-- Date: 20 July 2026
--
-- PURPOSE
--   1. Repair only production inconsistencies proven by the read-only audits.
--   2. Establish the first reproducible multi-tenant database foundation.
--   3. Add tenant ownership constraints, indexes and authorization helpers.
--   4. Secure internal hotel tables without breaking the current anonymous
--      Guest Guide, Food Menu and Service Request compatibility flows.
--
-- IMPORTANT
--   - Run this complete file once in Supabase SQL Editor using role `postgres`.
--   - Do not run only selected sections.
--   - The entire migration is transactional: any error rolls everything back.
--   - The 15 historical invoice balance mismatches are deliberately NOT changed.
--   - The active Reception staff row without an Auth account is NOT changed.
--   - Guest-facing RLS hardening is a later migration after secure QR tokens are
--     implemented, because the current guest URLs use public room numbers.
-- ============================================================================

begin;

set local lock_timeout = '10s';
set local statement_timeout = '180s';

select pg_advisory_xact_lock(
  hashtext('stayqr:202607200001_tenant_foundation_and_guarded_repairs')
);

-- ============================================================================
-- 0. PRE-MIGRATION ASSERTIONS
-- ============================================================================

do $$
declare
  unexpected_null_hotel_ids bigint;
  duplicate_room_count bigint;
  duplicate_active_room_sessions bigint;
begin
  select count(*)
  into unexpected_null_hotel_ids
  from (
    select hotel_id from public.analytics_events where hotel_id is null
    union all select hotel_id from public.feedback where hotel_id is null
    union all select hotel_id from public.food_orders where hotel_id is null
    union all select hotel_id from public.guest_sessions where hotel_id is null
    union all select hotel_id from public.guests where hotel_id is null
    union all select hotel_id from public.hotel_subscriptions where hotel_id is null
    union all select hotel_id from public.hotel_users where hotel_id is null
    union all select hotel_id from public.housekeeping_requests where hotel_id is null
    union all select hotel_id from public.housekeeping_tasks where hotel_id is null
    union all select hotel_id from public.invoice_items where hotel_id is null
    union all select hotel_id from public.invoices where hotel_id is null
    union all select hotel_id from public.manual_charges where hotel_id is null
    union all select hotel_id from public.menu_categories where hotel_id is null
    union all select hotel_id from public.menu_items where hotel_id is null
    union all select hotel_id from public.notifications where hotel_id is null
    union all select hotel_id from public.payment_collections where hotel_id is null
    union all select hotel_id from public.payments where hotel_id is null
    union all select hotel_id from public.room_sessions where hotel_id is null
    union all select hotel_id from public.rooms where hotel_id is null
    union all select hotel_id from public.service_requests where hotel_id is null
    union all select hotel_id from public.staff where hotel_id is null
  ) x;

  if unexpected_null_hotel_ids <> 0 then
    raise exception
      'Migration stopped: % unexpected tenant rows have NULL hotel_id.',
      unexpected_null_hotel_ids;
  end if;

  select count(*)
  into duplicate_room_count
  from (
    select hotel_id, room_number
    from public.rooms
    group by hotel_id, room_number
    having count(*) > 1
  ) x;

  if duplicate_room_count <> 0 then
    raise exception
      'Migration stopped: duplicate room numbers exist within a hotel.';
  end if;

  select count(*)
  into duplicate_active_room_sessions
  from (
    select hotel_id, room_id
    from public.guest_sessions
    where status = 'active'
    group by hotel_id, room_id
    having count(*) > 1
  ) x;

  if duplicate_active_room_sessions <> 0 then
    raise exception
      'Migration stopped: a room has more than one active guest session.';
  end if;
end
$$;

-- ============================================================================
-- 1. PRIVATE MIGRATION ARCHIVE
--    Preserve complete copies of every row that this migration deletes/changes.
-- ============================================================================

create schema if not exists private;

revoke all on schema private from public;
revoke all on schema private from anon;
revoke all on schema private from authenticated;

grant usage on schema private to authenticated;

create table if not exists private.hotel_info_archive_20260720
(like public.hotel_info including all);

create table if not exists private.hotel_users_archive_20260720
(like public.hotel_users including all);

create table if not exists private.rooms_archive_20260720
(like public.rooms including all);

revoke all on all tables in schema private from public;
revoke all on all tables in schema private from anon;
revoke all on all tables in schema private from authenticated;

insert into private.hotel_info_archive_20260720
select hi.*
from public.hotel_info hi
where hi.id in (
  'e6e8d28f-1570-43e2-96ba-5476e95da0ea'::uuid,
  '6459507e-ddab-4eea-987e-d9bfa8d518c1'::uuid
)
and not exists (
  select 1
  from private.hotel_info_archive_20260720 a
  where a.id = hi.id
);

insert into private.hotel_users_archive_20260720
select hu.*
from public.hotel_users hu
where hu.id = 'a14d9f1d-03c0-407b-b4f9-d551f18916bb'::uuid
and not exists (
  select 1
  from private.hotel_users_archive_20260720 a
  where a.id = hu.id
);

insert into private.rooms_archive_20260720
select r.*
from public.rooms r
where r.id = '9137c934-1cae-4e99-ae71-8e99d145244e'::uuid
and not exists (
  select 1
  from private.rooms_archive_20260720 a
  where a.id = r.id
);

-- ============================================================================
-- 2. GUARDED DATA REPAIRS
-- ============================================================================

-- 2.1 Correct the linked VD Stay Inn profile name.
update public.hotel_info
set hotel_name = 'VD Stay Inn'
where id = 'e6e8d28f-1570-43e2-96ba-5476e95da0ea'::uuid
  and hotel_id = '77d850d0-016d-4155-bc44-a6207d30e7b9'::uuid
  and hotel_name = 'VD Stay Innn';

-- 2.2 Remove the duplicate orphan profile only after its full row is archived.
delete from public.hotel_info
where id = '6459507e-ddab-4eea-987e-d9bfa8d518c1'::uuid
  and hotel_id is null
  and hotel_name = 'VD Stay Inn';

-- 2.3 Room 102 has a current, non-expired active stay. Operational room state
--     must therefore be occupied, not available.
update public.rooms r
set status = 'occupied'
where r.id = '9137c934-1cae-4e99-ae71-8e99d145244e'::uuid
  and r.hotel_id = '77d850d0-016d-4155-bc44-a6207d30e7b9'::uuid
  and r.room_number = '102'
  and r.status = 'available'
  and exists (
    select 1
    from public.guest_sessions gs
    where gs.id = '054848dc-01d7-42e2-942e-d32349cdb678'::uuid
      and gs.hotel_id = r.hotel_id
      and gs.room_id = r.id
      and gs.status = 'active'
      and coalesce(gs.extended_until, gs.checkout_time) > now()
  );

-- ============================================================================
-- 3. PLATFORM ADMIN IDENTITY
--    Platform administration is separated from hotel-level staff membership.
-- ============================================================================

create table if not exists public.platform_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  status text not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint platform_admins_status_check
    check (status in ('active', 'suspended', 'inactive'))
);

alter table public.platform_admins enable row level security;

drop policy if exists platform_admins_select_self
on public.platform_admins;

create policy platform_admins_select_self
on public.platform_admins
for select
to authenticated
using (user_id = (select auth.uid()));

insert into public.platform_admins (
  user_id,
  display_name,
  status
)
values (
  'a3d5f5a6-6fff-40fe-8fe0-b0b6c436effd'::uuid,
  'Vishant Dani',
  'active'
)
on conflict (user_id) do update
set
  display_name = excluded.display_name,
  status = excluded.status,
  updated_at = now();

-- The duplicate same-hotel `super_admin` membership is replaced by the
-- platform_admins row. The valid Manager membership and Manager staff row stay.
delete from public.hotel_users
where id = 'a14d9f1d-03c0-407b-b4f9-d551f18916bb'::uuid
  and hotel_id = '77d850d0-016d-4155-bc44-a6207d30e7b9'::uuid
  and user_id = 'a3d5f5a6-6fff-40fe-8fe0-b0b6c436effd'::uuid
  and lower(role) = 'super_admin';

-- ============================================================================
-- 4. HOTEL TENANT METADATA
-- ============================================================================

alter table public.hotels
  add column if not exists slug text,
  add column if not exists timezone text,
  add column if not exists currency_code text,
  add column if not exists updated_at timestamptz;

update public.hotels
set
  timezone = coalesce(nullif(trim(timezone), ''), 'Asia/Kolkata'),
  currency_code = upper(coalesce(nullif(trim(currency_code), ''), 'INR')),
  updated_at = coalesce(updated_at, created_at, now());

with base_slugs as (
  select
    id,
    trim(both '-' from regexp_replace(
      lower(coalesce(hotel_name, 'hotel')),
      '[^a-z0-9]+',
      '-',
      'g'
    )) as base_slug
  from public.hotels
  where slug is null or trim(slug) = ''
),
ranked as (
  select
    id,
    case
      when count(*) over (partition by base_slug) > 1
        then base_slug || '-' || left(replace(id::text, '-', ''), 6)
      else base_slug
    end as resolved_slug
  from base_slugs
)
update public.hotels h
set slug = r.resolved_slug
from ranked r
where h.id = r.id;

do $$
begin
  if exists (
    select 1
    from public.hotels
    where slug is null
       or trim(slug) = ''
       or timezone is null
       or trim(timezone) = ''
       or currency_code is null
       or trim(currency_code) = ''
  ) then
    raise exception
      'Migration stopped: hotel tenant metadata could not be populated.';
  end if;
end
$$;

alter table public.hotels
  alter column slug set not null,
  alter column timezone set default 'Asia/Kolkata',
  alter column timezone set not null,
  alter column currency_code set default 'INR',
  alter column currency_code set not null,
  alter column updated_at set default now(),
  alter column updated_at set not null;

create unique index if not exists uq_hotels_slug_lower
on public.hotels (lower(slug));

-- ============================================================================
-- 5. TENANT OWNERSHIP: NOT NULL + FOREIGN KEYS
-- ============================================================================

do $$
declare
  tenant_table text;
begin
  foreach tenant_table in array array[
    'analytics_events',
    'feedback',
    'food_orders',
    'guest_sessions',
    'guests',
    'hotel_info',
    'hotel_subscriptions',
    'hotel_users',
    'housekeeping_requests',
    'housekeeping_tasks',
    'invoice_items',
    'invoices',
    'manual_charges',
    'menu_categories',
    'menu_items',
    'notifications',
    'payment_collections',
    'payments',
    'room_sessions',
    'rooms',
    'service_requests',
    'staff'
  ]
  loop
    execute format(
      'alter table public.%I alter column hotel_id set not null',
      tenant_table
    );
  end loop;
end
$$;

do $$
declare
  tenant_table text;
  constraint_name text;
begin
  foreach tenant_table in array array[
    'food_orders',
    'housekeeping_requests',
    'housekeeping_tasks',
    'invoice_items',
    'invoices',
    'manual_charges',
    'menu_categories',
    'menu_items',
    'payment_collections',
    'room_sessions'
  ]
  loop
    constraint_name := tenant_table || '_hotel_id_fkey';

    if not exists (
      select 1
      from pg_constraint
      where conname = constraint_name
        and conrelid = format('public.%I', tenant_table)::regclass
    ) then
      execute format(
        'alter table public.%I add constraint %I
         foreign key (hotel_id)
         references public.hotels(id)
         on delete restrict',
        tenant_table,
        constraint_name
      );
    end if;
  end loop;
end
$$;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'hotel_users_user_id_fkey'
      and conrelid = 'public.hotel_users'::regclass
  ) then
    alter table public.hotel_users
      add constraint hotel_users_user_id_fkey
      foreign key (user_id)
      references auth.users(id)
      on delete set null
      not valid;

    alter table public.hotel_users
      validate constraint hotel_users_user_id_fkey;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'staff_auth_user_id_fkey'
      and conrelid = 'public.staff'::regclass
  ) then
    alter table public.staff
      add constraint staff_auth_user_id_fkey
      foreign key (auth_user_id)
      references auth.users(id)
      on delete set null
      not valid;

    alter table public.staff
      validate constraint staff_auth_user_id_fkey;
  end if;
end
$$;

-- ============================================================================
-- 6. UNIQUENESS AND QUERY INDEXES
-- ============================================================================

-- A person may legitimately belong to more than one hotel, so email is no
-- longer globally unique. It is unique only within one hotel.
alter table public.hotel_users
  drop constraint if exists hotel_users_email_key;

create unique index if not exists uq_rooms_hotel_room_number
on public.rooms (hotel_id, room_number);

create unique index if not exists uq_hotel_info_hotel
on public.hotel_info (hotel_id);

create unique index if not exists uq_hotel_users_hotel_user
on public.hotel_users (hotel_id, user_id)
where user_id is not null;

create unique index if not exists uq_hotel_users_hotel_email
on public.hotel_users (hotel_id, lower(email));

create unique index if not exists uq_staff_hotel_auth_user
on public.staff (hotel_id, auth_user_id)
where auth_user_id is not null;

create unique index if not exists uq_staff_hotel_email
on public.staff (hotel_id, lower(email));

create unique index if not exists uq_role_permissions_role_permission
on public.role_permissions (
  lower(role_name),
  permission_key
);

create unique index if not exists uq_hotel_current_subscription
on public.hotel_subscriptions (hotel_id)
where status in ('trial', 'trialing', 'active', 'past_due');

create unique index if not exists uq_invoices_hotel_invoice_number
on public.invoices (hotel_id, invoice_number)
where invoice_number is not null;

do $$
declare
  tenant_table text;
begin
  foreach tenant_table in array array[
    'analytics_events',
    'feedback',
    'food_orders',
    'guest_sessions',
    'guests',
    'hotel_info',
    'hotel_subscriptions',
    'hotel_users',
    'housekeeping_requests',
    'housekeeping_tasks',
    'invoice_items',
    'invoices',
    'manual_charges',
    'menu_categories',
    'menu_items',
    'notifications',
    'payment_collections',
    'payments',
    'room_sessions',
    'rooms',
    'service_requests',
    'staff'
  ]
  loop
    execute format(
      'create index if not exists %I on public.%I (hotel_id)',
      'idx_' || tenant_table || '_hotel_id',
      tenant_table
    );
  end loop;
end
$$;

create index if not exists idx_rooms_hotel_status
on public.rooms (hotel_id, status);

create index if not exists idx_guest_sessions_hotel_room_status
on public.guest_sessions (hotel_id, room_id, status);

create index if not exists idx_guest_sessions_hotel_guest_status
on public.guest_sessions (hotel_id, guest_id, status);

create index if not exists idx_food_orders_hotel_status_created
on public.food_orders (hotel_id, order_status, created_at desc);

create index if not exists idx_service_requests_hotel_status_created
on public.service_requests (hotel_id, status, created_at desc);

create index if not exists idx_housekeeping_tasks_hotel_status_created
on public.housekeeping_tasks (hotel_id, status, created_at desc);

create index if not exists idx_invoices_hotel_created
on public.invoices (hotel_id, created_at desc);

create index if not exists idx_payments_hotel_created
on public.payments (hotel_id, created_at desc);

create index if not exists idx_notifications_hotel_read_created
on public.notifications (hotel_id, is_read, created_at desc);

-- ============================================================================
-- 7. CONTROLLED STATUS CONSTRAINTS
-- ============================================================================

alter table public.hotels
  drop constraint if exists hotels_status_check;

alter table public.hotels
  add constraint hotels_status_check
  check (status in ('active', 'suspended', 'inactive', 'archived'))
  not valid;

alter table public.hotels
  validate constraint hotels_status_check;

alter table public.hotels
  drop constraint if exists hotels_subscription_status_check;

alter table public.hotels
  add constraint hotels_subscription_status_check
  check (
    subscription_status in (
      'trial',
      'trialing',
      'active',
      'past_due',
      'suspended',
      'cancelled',
      'expired'
    )
  )
  not valid;

alter table public.hotels
  validate constraint hotels_subscription_status_check;

alter table public.rooms
  drop constraint if exists rooms_status_check;

alter table public.rooms
  add constraint rooms_status_check
  check (
    status in (
      'available',
      'occupied',
      'cleaning',
      'maintenance',
      'out_of_order'
    )
  )
  not valid;

alter table public.rooms
  validate constraint rooms_status_check;

alter table public.staff
  drop constraint if exists staff_status_check;

alter table public.staff
  add constraint staff_status_check
  check (status in ('active', 'invited', 'inactive', 'suspended'))
  not valid;

alter table public.staff
  validate constraint staff_status_check;

alter table public.hotel_users
  drop constraint if exists hotel_users_status_check;

alter table public.hotel_users
  add constraint hotel_users_status_check
  check (status in ('active', 'invited', 'inactive', 'suspended'))
  not valid;

alter table public.hotel_users
  validate constraint hotel_users_status_check;

-- ============================================================================
-- 8. UPDATED-AT TRIGGER FOUNDATION
-- ============================================================================

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

drop trigger if exists hotels_set_updated_at
on public.hotels;

create trigger hotels_set_updated_at
before update on public.hotels
for each row
execute function private.set_updated_at();

drop trigger if exists platform_admins_set_updated_at
on public.platform_admins;

create trigger platform_admins_set_updated_at
before update on public.platform_admins
for each row
execute function private.set_updated_at();

-- ============================================================================
-- 9. AUTHORIZATION HELPER FUNCTIONS
--    SECURITY DEFINER functions use an empty search_path and fully qualified
--    object names. Authorization never relies on editable user metadata.
-- ============================================================================

create or replace function private.is_platform_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    exists (
      select 1
      from public.platform_admins pa
      where pa.user_id = (select auth.uid())
        and pa.status = 'active'
    ),
    false
  );
$$;

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
      where s.hotel_id = target_hotel_id
        and s.auth_user_id = (select auth.uid())
        and lower(s.status) = 'active'
        and lower(h.status) = 'active'
    )
    or exists (
      select 1
      from public.hotel_users hu
      join public.hotels h on h.id = hu.hotel_id
      where hu.hotel_id = target_hotel_id
        and hu.user_id = (select auth.uid())
        and lower(hu.status) = 'active'
        and lower(h.status) = 'active'
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
      where s.hotel_id = target_hotel_id
        and s.auth_user_id = (select auth.uid())
        and lower(s.status) = 'active'
        and lower(replace(trim(s.role), ' ', '_')) = any(allowed_roles)
    )
    or exists (
      select 1
      from public.hotel_users hu
      where hu.hotel_id = target_hotel_id
        and hu.user_id = (select auth.uid())
        and lower(hu.status) = 'active'
        and lower(replace(trim(hu.role), ' ', '_')) = any(allowed_roles)
    );
$$;

revoke all on function private.set_updated_at() from public;
revoke all on function private.is_platform_admin() from public;
revoke all on function private.user_has_hotel_access(uuid) from public;
revoke all on function private.user_has_hotel_role(uuid, text[]) from public;

grant execute on function private.is_platform_admin()
to authenticated;

grant execute on function private.user_has_hotel_access(uuid)
to authenticated;

grant execute on function private.user_has_hotel_role(uuid, text[])
to authenticated;

-- ============================================================================
-- 10. INTERNAL-TABLE RLS
--     The guest-facing compatibility tables are intentionally excluded here:
--     rooms, guests, guest_sessions, hotel_info, feedback, menu_categories,
--     menu_items, food_orders, food_order_items, service_requests,
--     notifications.
-- ============================================================================

-- Remove previously unrestricted public policies from financial tables.
drop policy if exists "Allow delete invoice items"
on public.invoice_items;

drop policy if exists "Allow insert invoice items"
on public.invoice_items;

drop policy if exists "Allow select invoice items"
on public.invoice_items;

drop policy if exists "Allow update invoice items"
on public.invoice_items;

drop policy if exists "Allow all delete payment collections"
on public.payment_collections;

drop policy if exists "Allow all insert payment collections"
on public.payment_collections;

drop policy if exists "Allow all select payment collections"
on public.payment_collections;

drop policy if exists "Allow all update payment collections"
on public.payment_collections;

do $$
declare
  tenant_table text;
begin
  foreach tenant_table in array array[
    'analytics_events',
    'housekeeping_requests',
    'housekeeping_tasks',
    'invoice_items',
    'invoices',
    'manual_charges',
    'payment_collections',
    'payments',
    'room_sessions'
  ]
  loop
    execute format(
      'alter table public.%I enable row level security',
      tenant_table
    );

    execute format(
      'drop policy if exists stayqr_tenant_select on public.%I',
      tenant_table
    );
    execute format(
      'drop policy if exists stayqr_tenant_insert on public.%I',
      tenant_table
    );
    execute format(
      'drop policy if exists stayqr_tenant_update on public.%I',
      tenant_table
    );
    execute format(
      'drop policy if exists stayqr_tenant_delete on public.%I',
      tenant_table
    );

    execute format(
      'create policy stayqr_tenant_select
       on public.%I
       for select
       to authenticated
       using (private.user_has_hotel_access(hotel_id))',
      tenant_table
    );

    execute format(
      'create policy stayqr_tenant_insert
       on public.%I
       for insert
       to authenticated
       with check (private.user_has_hotel_access(hotel_id))',
      tenant_table
    );

    execute format(
      'create policy stayqr_tenant_update
       on public.%I
       for update
       to authenticated
       using (private.user_has_hotel_access(hotel_id))
       with check (private.user_has_hotel_access(hotel_id))',
      tenant_table
    );

    execute format(
      'create policy stayqr_tenant_delete
       on public.%I
       for delete
       to authenticated
       using (private.user_has_hotel_access(hotel_id))',
      tenant_table
    );
  end loop;
end
$$;

-- Hotels
alter table public.hotels enable row level security;

drop policy if exists stayqr_hotels_select
on public.hotels;
drop policy if exists stayqr_hotels_insert
on public.hotels;
drop policy if exists stayqr_hotels_update
on public.hotels;
drop policy if exists stayqr_hotels_delete
on public.hotels;

create policy stayqr_hotels_select
on public.hotels
for select
to authenticated
using (private.user_has_hotel_access(id));

create policy stayqr_hotels_insert
on public.hotels
for insert
to authenticated
with check (private.is_platform_admin());

create policy stayqr_hotels_update
on public.hotels
for update
to authenticated
using (
  private.is_platform_admin()
  or private.user_has_hotel_role(
    id,
    array['owner', 'manager']
  )
)
with check (
  private.is_platform_admin()
  or private.user_has_hotel_role(
    id,
    array['owner', 'manager']
  )
);

create policy stayqr_hotels_delete
on public.hotels
for delete
to authenticated
using (private.is_platform_admin());

-- Hotel users
alter table public.hotel_users enable row level security;

drop policy if exists stayqr_hotel_users_select
on public.hotel_users;
drop policy if exists stayqr_hotel_users_insert
on public.hotel_users;
drop policy if exists stayqr_hotel_users_update
on public.hotel_users;
drop policy if exists stayqr_hotel_users_delete
on public.hotel_users;

create policy stayqr_hotel_users_select
on public.hotel_users
for select
to authenticated
using (private.user_has_hotel_access(hotel_id));

create policy stayqr_hotel_users_insert
on public.hotel_users
for insert
to authenticated
with check (
  private.is_platform_admin()
  or private.user_has_hotel_role(
    hotel_id,
    array['owner', 'manager']
  )
);

create policy stayqr_hotel_users_update
on public.hotel_users
for update
to authenticated
using (
  private.is_platform_admin()
  or private.user_has_hotel_role(
    hotel_id,
    array['owner', 'manager']
  )
)
with check (
  private.is_platform_admin()
  or private.user_has_hotel_role(
    hotel_id,
    array['owner', 'manager']
  )
);

create policy stayqr_hotel_users_delete
on public.hotel_users
for delete
to authenticated
using (
  private.is_platform_admin()
  or private.user_has_hotel_role(
    hotel_id,
    array['owner', 'manager']
  )
);

-- Staff
alter table public.staff enable row level security;

drop policy if exists stayqr_staff_select
on public.staff;
drop policy if exists stayqr_staff_insert
on public.staff;
drop policy if exists stayqr_staff_update
on public.staff;
drop policy if exists stayqr_staff_delete
on public.staff;

create policy stayqr_staff_select
on public.staff
for select
to authenticated
using (private.user_has_hotel_access(hotel_id));

create policy stayqr_staff_insert
on public.staff
for insert
to authenticated
with check (
  private.is_platform_admin()
  or private.user_has_hotel_role(
    hotel_id,
    array['owner', 'manager']
  )
);

create policy stayqr_staff_update
on public.staff
for update
to authenticated
using (
  private.is_platform_admin()
  or private.user_has_hotel_role(
    hotel_id,
    array['owner', 'manager']
  )
)
with check (
  private.is_platform_admin()
  or private.user_has_hotel_role(
    hotel_id,
    array['owner', 'manager']
  )
);

create policy stayqr_staff_delete
on public.staff
for delete
to authenticated
using (
  private.is_platform_admin()
  or private.user_has_hotel_role(
    hotel_id,
    array['owner', 'manager']
  )
);

-- Hotel subscriptions
alter table public.hotel_subscriptions enable row level security;

drop policy if exists stayqr_hotel_subscriptions_select
on public.hotel_subscriptions;
drop policy if exists stayqr_hotel_subscriptions_insert
on public.hotel_subscriptions;
drop policy if exists stayqr_hotel_subscriptions_update
on public.hotel_subscriptions;
drop policy if exists stayqr_hotel_subscriptions_delete
on public.hotel_subscriptions;

create policy stayqr_hotel_subscriptions_select
on public.hotel_subscriptions
for select
to authenticated
using (private.user_has_hotel_access(hotel_id));

create policy stayqr_hotel_subscriptions_insert
on public.hotel_subscriptions
for insert
to authenticated
with check (private.is_platform_admin());

create policy stayqr_hotel_subscriptions_update
on public.hotel_subscriptions
for update
to authenticated
using (private.is_platform_admin())
with check (private.is_platform_admin());

create policy stayqr_hotel_subscriptions_delete
on public.hotel_subscriptions
for delete
to authenticated
using (private.is_platform_admin());

-- Global configuration tables
alter table public.subscription_plans enable row level security;
alter table public.staff_roles enable row level security;
alter table public.role_permissions enable row level security;

drop policy if exists stayqr_subscription_plans_select
on public.subscription_plans;
drop policy if exists stayqr_subscription_plans_manage
on public.subscription_plans;

create policy stayqr_subscription_plans_select
on public.subscription_plans
for select
to authenticated
using (true);

create policy stayqr_subscription_plans_manage
on public.subscription_plans
for all
to authenticated
using (private.is_platform_admin())
with check (private.is_platform_admin());

drop policy if exists stayqr_staff_roles_select
on public.staff_roles;
drop policy if exists stayqr_staff_roles_manage
on public.staff_roles;

create policy stayqr_staff_roles_select
on public.staff_roles
for select
to authenticated
using (true);

create policy stayqr_staff_roles_manage
on public.staff_roles
for all
to authenticated
using (private.is_platform_admin())
with check (private.is_platform_admin());

drop policy if exists stayqr_role_permissions_select
on public.role_permissions;
drop policy if exists stayqr_role_permissions_manage
on public.role_permissions;

create policy stayqr_role_permissions_select
on public.role_permissions
for select
to authenticated
using (true);

create policy stayqr_role_permissions_manage
on public.role_permissions
for all
to authenticated
using (private.is_platform_admin())
with check (private.is_platform_admin());

-- ============================================================================
-- 11. FINAL ASSERTIONS
-- ============================================================================

do $$
begin
  if exists (
    select 1
    from public.hotel_info
    where hotel_id is null
  ) then
    raise exception
      'Migration stopped: hotel_info still contains an orphan profile.';
  end if;

  if not exists (
    select 1
    from public.rooms
    where id = '9137c934-1cae-4e99-ae71-8e99d145244e'::uuid
      and status = 'occupied'
  ) then
    raise exception
      'Migration stopped: Room 102 active-stay state was not repaired.';
  end if;

  if not exists (
    select 1
    from public.platform_admins
    where user_id = 'a3d5f5a6-6fff-40fe-8fe0-b0b6c436effd'::uuid
      and status = 'active'
  ) then
    raise exception
      'Migration stopped: platform admin identity was not established.';
  end if;

  if exists (
    select 1
    from public.hotel_users
    where hotel_id = '77d850d0-016d-4155-bc44-a6207d30e7b9'::uuid
      and user_id = 'a3d5f5a6-6fff-40fe-8fe0-b0b6c436effd'::uuid
    group by hotel_id, user_id
    having count(*) > 1
  ) then
    raise exception
      'Migration stopped: duplicate same-hotel membership remains.';
  end if;
end
$$;

commit;

-- ============================================================================
-- EXPECTED RESULT
-- ============================================================================
-- Supabase SQL Editor should show:
--   Success. No rows returned
--
-- Immediately afterwards run:
--   supabase/audit/004_verify_tenant_foundation.sql
-- ============================================================================
