-- ============================================================================
-- StayQR v1.0
-- Day 8 Migration 019 — Inventory, Amenities, Request Categories and Bulk Rooms
--
-- PRIMARY OUTCOME
-- Completes the server-side configuration layer required by the Day 8
-- onboarding wizard:
--   - normalized hotel amenities;
--   - normalized service-request categories;
--   - normalized menu-category metadata and legacy compatibility;
--   - atomic room type/floor/rate configuration;
--   - validated bulk room import/upsert;
--   - idempotent hotel configuration/menu defaults;
--   - automatic defaults for every future hotel;
--   - onboarding-readiness refresh after configuration changes.
--
-- COMPATIBILITY
-- Existing text fields remain available:
--   - rooms.room_type
--   - menu_items.category
--   - service_requests.request_type
-- New normalized foreign keys are kept synchronized so existing guest and
-- operations flows continue to work while the Day 8 frontend is upgraded.
--
-- SAFETY
-- - Run once in Supabase SQL Editor with role: postgres.
-- - Transactional and idempotent.
-- - Existing rooms, room types, rates, menu items and service requests are not
--   deleted.
-- - Existing text categories/types are normalized and linked in place.
-- - No synthetic hotel or room is created by the migration.
--
-- EXPECTED RESULT
-- 24 rows, and every passed value must be true.
-- ============================================================================

begin;

set local lock_timeout = '10s';
set local statement_timeout = '240s';

select pg_advisory_xact_lock(
  hashtext('stayqr:202607270019:inventory-amenities-request-categories')
);

-- ============================================================================
-- 0. PRE-MIGRATION ASSERTIONS
-- ============================================================================

do $preflight$
begin
  if to_regclass('public.rooms') is null
     or to_regclass('public.room_types') is null
     or to_regclass('public.rate_plans') is null
     or to_regclass('public.floors') is null
     or to_regclass('public.menu_categories') is null
     or to_regclass('public.menu_items') is null
     or to_regclass('public.service_requests') is null
  then
    raise exception
      'Migration 019 stopped: required inventory/menu/request tables are missing.';
  end if;

  if to_regprocedure('private.normalize_hotel_slug(text)') is null
     or to_regprocedure(
       'private.compute_hotel_onboarding_readiness(uuid)'
     ) is null
     or to_regprocedure('private.user_has_permission(uuid,text)') is null
     or to_regprocedure('private.set_updated_at()') is null
  then
    raise exception
      'Migration 019 stopped: Migration 018 authorization/readiness helpers are missing.';
  end if;

  if exists (
    select 1
    from (
      select r.hotel_id, lower(trim(r.room_number))
      from public.rooms r
      group by r.hotel_id, lower(trim(r.room_number))
      having count(*) > 1
    ) duplicate_room
  ) then
    raise exception
      'Migration 019 stopped: duplicate room numbers exist inside a hotel.';
  end if;

  if exists (
    select 1
    from (
      select rt.hotel_id, upper(trim(rt.code))
      from public.room_types rt
      group by rt.hotel_id, upper(trim(rt.code))
      having count(*) > 1
    ) duplicate_room_type_code
  ) then
    raise exception
      'Migration 019 stopped: duplicate room-type codes exist inside a hotel.';
  end if;

  if exists (
    select 1
    from (
      select rp.hotel_id, upper(trim(rp.code))
      from public.rate_plans rp
      group by rp.hotel_id, upper(trim(rp.code))
      having count(*) > 1
    ) duplicate_rate_code
  ) then
    raise exception
      'Migration 019 stopped: duplicate rate-plan codes exist inside a hotel.';
  end if;
end;
$preflight$;

-- ============================================================================
-- 1. LOCKED INVENTORY UNIQUENESS
-- ============================================================================

create unique index if not exists uq_rooms_hotel_room_number
on public.rooms (hotel_id, lower(trim(room_number)));

create unique index if not exists uq_room_types_hotel_code
on public.room_types (hotel_id, upper(trim(code)));

create unique index if not exists uq_room_types_hotel_name
on public.room_types (hotel_id, lower(trim(name)));

create unique index if not exists uq_rate_plans_hotel_code
on public.rate_plans (hotel_id, upper(trim(code)));

-- ============================================================================
-- 2. NORMALIZED AMENITIES
-- ============================================================================

create table if not exists public.amenities (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null
    references public.hotels(id) on delete cascade,
  name text not null,
  code text not null,
  category text not null default 'general',
  description text,
  instructions text,
  icon text,
  guest_visible boolean not null default true,
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint amenities_name_not_blank
    check (length(trim(name)) > 0),
  constraint amenities_code_not_blank
    check (length(trim(code)) > 0),
  constraint amenities_category_not_blank
    check (length(trim(category)) > 0)
);

create unique index if not exists uq_amenities_hotel_id_id
on public.amenities (hotel_id, id);

create unique index if not exists uq_amenities_hotel_code
on public.amenities (hotel_id, upper(trim(code)));

create unique index if not exists uq_amenities_hotel_name
on public.amenities (hotel_id, lower(trim(name)));

create index if not exists idx_amenities_hotel_active_sort
on public.amenities (
  hotel_id,
  guest_visible,
  is_active,
  sort_order
);

drop trigger if exists set_amenities_updated_at
on public.amenities;

create trigger set_amenities_updated_at
before update on public.amenities
for each row execute function private.set_updated_at();

revoke all on public.amenities
from public, anon;

grant select, insert, update, delete
on public.amenities
to authenticated;

alter table public.amenities enable row level security;

drop policy if exists stayqr_amenities_select
on public.amenities;
drop policy if exists stayqr_amenities_insert
on public.amenities;
drop policy if exists stayqr_amenities_update
on public.amenities;
drop policy if exists stayqr_amenities_delete
on public.amenities;

create policy stayqr_amenities_select
on public.amenities
for select to authenticated
using (private.user_has_hotel_access(hotel_id));

create policy stayqr_amenities_insert
on public.amenities
for insert to authenticated
with check (private.user_has_permission(hotel_id, 'hotel.manage'));

create policy stayqr_amenities_update
on public.amenities
for update to authenticated
using (private.user_has_permission(hotel_id, 'hotel.manage'))
with check (private.user_has_permission(hotel_id, 'hotel.manage'));

create policy stayqr_amenities_delete
on public.amenities
for delete to authenticated
using (private.user_has_permission(hotel_id, 'hotel.manage'));

-- ============================================================================
-- 3. NORMALIZED SERVICE-REQUEST CATEGORIES
-- ============================================================================

create table if not exists public.service_request_types (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null
    references public.hotels(id) on delete cascade,
  name text not null,
  code text not null,
  description text,
  default_priority text not null default 'normal',
  default_estimated_minutes integer,
  guest_visible boolean not null default true,
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint service_request_types_name_not_blank
    check (length(trim(name)) > 0),
  constraint service_request_types_code_not_blank
    check (length(trim(code)) > 0),
  constraint service_request_types_priority_check
    check (default_priority in ('low', 'normal', 'high', 'urgent')),
  constraint service_request_types_estimate_check
    check (
      default_estimated_minutes is null
      or default_estimated_minutes between 0 and 1440
    )
);

create unique index if not exists uq_service_request_types_hotel_id_id
on public.service_request_types (hotel_id, id);

create unique index if not exists uq_service_request_types_hotel_code
on public.service_request_types (hotel_id, upper(trim(code)));

create unique index if not exists uq_service_request_types_hotel_name
on public.service_request_types (hotel_id, lower(trim(name)));

create index if not exists idx_service_request_types_hotel_active_sort
on public.service_request_types (
  hotel_id,
  guest_visible,
  is_active,
  sort_order
);

drop trigger if exists set_service_request_types_updated_at
on public.service_request_types;

create trigger set_service_request_types_updated_at
before update on public.service_request_types
for each row execute function private.set_updated_at();

revoke all on public.service_request_types
from public, anon;

grant select, insert, update, delete
on public.service_request_types
to authenticated;

alter table public.service_request_types enable row level security;

drop policy if exists stayqr_service_request_types_select
on public.service_request_types;
drop policy if exists stayqr_service_request_types_insert
on public.service_request_types;
drop policy if exists stayqr_service_request_types_update
on public.service_request_types;
drop policy if exists stayqr_service_request_types_delete
on public.service_request_types;

create policy stayqr_service_request_types_select
on public.service_request_types
for select to authenticated
using (private.user_has_hotel_access(hotel_id));

create policy stayqr_service_request_types_insert
on public.service_request_types
for insert to authenticated
with check (private.user_has_permission(hotel_id, 'hotel.manage'));

create policy stayqr_service_request_types_update
on public.service_request_types
for update to authenticated
using (private.user_has_permission(hotel_id, 'hotel.manage'))
with check (private.user_has_permission(hotel_id, 'hotel.manage'));

create policy stayqr_service_request_types_delete
on public.service_request_types
for delete to authenticated
using (private.user_has_permission(hotel_id, 'hotel.manage'));

-- ============================================================================
-- 4. MENU-CATEGORY METADATA AND HOTEL-SCOPED OWNERSHIP
-- ============================================================================

alter table public.menu_categories
  add column if not exists code text,
  add column if not exists description text,
  add column if not exists sort_order integer not null default 0,
  add column if not exists is_active boolean not null default true,
  add column if not exists created_by uuid
    references auth.users(id) on delete set null,
  add column if not exists updated_by uuid
    references auth.users(id) on delete set null,
  add column if not exists updated_at timestamptz;

update public.menu_categories
set updated_at = coalesce(updated_at, created_at, now());

alter table public.menu_categories
  alter column updated_at set default now(),
  alter column updated_at set not null;

with ranked_codes as (
  select
    mc.id,
    private.normalize_hotel_slug(mc.name) as base_code,
    row_number() over (
      partition by
        mc.hotel_id,
        private.normalize_hotel_slug(mc.name)
      order by mc.created_at nulls last, mc.id
    ) as duplicate_number
  from public.menu_categories mc
  where mc.code is null
     or nullif(trim(mc.code), '') is null
)
update public.menu_categories mc
set code = case
  when rc.duplicate_number = 1 then rc.base_code
  else left(
    rc.base_code,
    greatest(1, 48 - length(rc.duplicate_number::text) - 1)
  ) || '-' || rc.duplicate_number::text
end
from ranked_codes rc
where rc.id = mc.id;

alter table public.menu_categories
  alter column code set not null;

alter table public.menu_categories
  drop constraint if exists menu_categories_code_not_blank;

alter table public.menu_categories
  add constraint menu_categories_code_not_blank
  check (length(trim(code)) > 0)
  not valid;

alter table public.menu_categories
  validate constraint menu_categories_code_not_blank;

create unique index if not exists uq_menu_categories_hotel_id_id
on public.menu_categories (hotel_id, id);

create unique index if not exists uq_menu_categories_hotel_code
on public.menu_categories (hotel_id, upper(trim(code)));

create unique index if not exists uq_menu_categories_hotel_name
on public.menu_categories (hotel_id, lower(trim(name)));

create index if not exists idx_menu_categories_hotel_active_sort
on public.menu_categories (hotel_id, is_active, sort_order);

drop trigger if exists set_menu_categories_updated_at
on public.menu_categories;

create trigger set_menu_categories_updated_at
before update on public.menu_categories
for each row execute function private.set_updated_at();

-- ============================================================================
-- 5. PRIVATE IDEMPOTENT DEFAULT-SEEDING HELPERS
-- ============================================================================

create or replace function private.seed_hotel_menu_defaults_internal(
  target_hotel_id uuid,
  actor_user_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $seed_menu$
declare
  seed_row record;
  inserted_count integer := 0;
begin
  if target_hotel_id is null
     or not exists (
       select 1
       from public.hotels h
       where h.id = target_hotel_id
     )
  then
    raise exception 'Unknown hotel.';
  end if;

  perform pg_advisory_xact_lock(
    hashtext(
      'stayqr:seed-menu-defaults:' || target_hotel_id::text
    )
  );

  for seed_row in
    select *
    from (
      values
        ('Beverages'::text, 'beverages'::text,
         'Hot and cold beverages.', 10),
        ('Breakfast'::text, 'breakfast'::text,
         'Breakfast and morning service.', 20),
        ('Meal'::text, 'meal'::text,
         'Lunch, dinner and all-day meals.', 30)
    ) as defaults(name, code, description, sort_order)
  loop
    if not exists (
      select 1
      from public.menu_categories mc
      where mc.hotel_id = target_hotel_id
        and (
          upper(trim(mc.code)) = upper(seed_row.code)
          or lower(trim(mc.name)) = lower(seed_row.name)
        )
    ) then
      insert into public.menu_categories (
        hotel_id,
        name,
        code,
        description,
        sort_order,
        is_active,
        created_by,
        updated_by,
        created_at,
        updated_at
      ) values (
        target_hotel_id,
        seed_row.name,
        seed_row.code,
        seed_row.description,
        seed_row.sort_order,
        true,
        actor_user_id,
        actor_user_id,
        now(),
        now()
      );

      inserted_count := inserted_count + 1;
    end if;
  end loop;

  return jsonb_build_object(
    'hotel_id', target_hotel_id,
    'menu_categories_inserted', inserted_count
  );
end;
$seed_menu$;

revoke all on function
  private.seed_hotel_menu_defaults_internal(uuid,uuid)
from public, anon, authenticated;

create or replace function private.seed_hotel_configuration_defaults_internal(
  target_hotel_id uuid,
  actor_user_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $seed_configuration$
declare
  seed_row record;
  amenities_inserted integer := 0;
  request_types_inserted integer := 0;
  menu_result jsonb;
begin
  if target_hotel_id is null
     or not exists (
       select 1
       from public.hotels h
       where h.id = target_hotel_id
     )
  then
    raise exception 'Unknown hotel.';
  end if;

  perform pg_advisory_xact_lock(
    hashtext(
      'stayqr:seed-configuration-defaults:'
      || target_hotel_id::text
    )
  );

  for seed_row in
    select *
    from (
      values
        ('Wi-Fi'::text, 'wifi'::text, 'connectivity'::text,
         'Wireless internet access.', 'wifi'::text, 10),
        ('Air Conditioning'::text, 'air-conditioning'::text,
         'room'::text, 'In-room air conditioning.',
         'air-conditioning'::text, 20),
        ('Hot Water'::text, 'hot-water'::text, 'bathroom'::text,
         'Hot-water availability.', 'droplets'::text, 30),
        ('Television'::text, 'television'::text, 'entertainment'::text,
         'In-room television.', 'tv'::text, 40),
        ('Housekeeping'::text, 'housekeeping'::text, 'service'::text,
         'Housekeeping support.', 'sparkles'::text, 50)
    ) as defaults(
      name,
      code,
      category,
      description,
      icon,
      sort_order
    )
  loop
    if not exists (
      select 1
      from public.amenities a
      where a.hotel_id = target_hotel_id
        and (
          upper(trim(a.code)) = upper(seed_row.code)
          or lower(trim(a.name)) = lower(seed_row.name)
        )
    ) then
      insert into public.amenities (
        hotel_id,
        name,
        code,
        category,
        description,
        icon,
        guest_visible,
        is_active,
        sort_order,
        created_by,
        updated_by,
        created_at,
        updated_at
      ) values (
        target_hotel_id,
        seed_row.name,
        seed_row.code,
        seed_row.category,
        seed_row.description,
        seed_row.icon,
        true,
        true,
        seed_row.sort_order,
        actor_user_id,
        actor_user_id,
        now(),
        now()
      );

      amenities_inserted := amenities_inserted + 1;
    end if;
  end loop;

  for seed_row in
    select *
    from (
      values
        ('Housekeeping'::text, 'housekeeping'::text,
         'Housekeeping assistance.', 'normal'::text, 20, 10),
        ('Towel'::text, 'towel'::text,
         'Request additional towels.', 'normal'::text, 15, 20),
        ('Water'::text, 'water'::text,
         'Request drinking water.', 'normal'::text, 10, 30),
        ('Checkout Request'::text, 'checkout-request'::text,
         'Request checkout assistance.', 'high'::text, 15, 40)
    ) as defaults(
      name,
      code,
      description,
      default_priority,
      default_estimated_minutes,
      sort_order
    )
  loop
    if not exists (
      select 1
      from public.service_request_types srt
      where srt.hotel_id = target_hotel_id
        and (
          upper(trim(srt.code)) = upper(seed_row.code)
          or lower(trim(srt.name)) = lower(seed_row.name)
        )
    ) then
      insert into public.service_request_types (
        hotel_id,
        name,
        code,
        description,
        default_priority,
        default_estimated_minutes,
        guest_visible,
        is_active,
        sort_order,
        created_by,
        updated_by,
        created_at,
        updated_at
      ) values (
        target_hotel_id,
        seed_row.name,
        seed_row.code,
        seed_row.description,
        seed_row.default_priority,
        seed_row.default_estimated_minutes,
        true,
        true,
        seed_row.sort_order,
        actor_user_id,
        actor_user_id,
        now(),
        now()
      );

      request_types_inserted := request_types_inserted + 1;
    end if;
  end loop;

  menu_result :=
    private.seed_hotel_menu_defaults_internal(
      target_hotel_id,
      actor_user_id
    );

  return jsonb_build_object(
    'hotel_id', target_hotel_id,
    'amenities_inserted', amenities_inserted,
    'request_types_inserted', request_types_inserted,
    'menu', menu_result
  );
end;
$seed_configuration$;

revoke all on function
  private.seed_hotel_configuration_defaults_internal(uuid,uuid)
from public, anon, authenticated;

-- Seed every existing hotel before normalizing historical text values.
do $seed_existing_hotels$
declare
  hotel_row record;
begin
  for hotel_row in
    select h.id
    from public.hotels h
    order by h.created_at
  loop
    perform private.seed_hotel_configuration_defaults_internal(
      hotel_row.id,
      null
    );
  end loop;
end;
$seed_existing_hotels$;

-- ============================================================================
-- 6. NORMALIZE EXISTING MENU ITEM CATEGORIES
-- ============================================================================

do $normalize_menu_categories$
declare
  category_row record;
  base_code text;
  code_candidate text;
  suffix integer;
begin
  for category_row in
    select distinct
      mi.hotel_id,
      trim(mi.category) as category_name
    from public.menu_items mi
    where nullif(trim(mi.category), '') is not null
      and not exists (
        select 1
        from public.menu_categories mc
        where mc.hotel_id = mi.hotel_id
          and lower(trim(mc.name)) =
            lower(trim(mi.category))
      )
    order by mi.hotel_id, trim(mi.category)
  loop
    base_code :=
      private.normalize_hotel_slug(category_row.category_name);
    code_candidate := base_code;
    suffix := 1;

    while exists (
      select 1
      from public.menu_categories mc
      where mc.hotel_id = category_row.hotel_id
        and upper(trim(mc.code)) =
          upper(code_candidate)
    )
    loop
      suffix := suffix + 1;
      code_candidate :=
        left(
          base_code,
          greatest(1, 48 - length(suffix::text) - 1)
        ) || '-' || suffix::text;
    end loop;

    insert into public.menu_categories (
      hotel_id,
      name,
      code,
      sort_order,
      is_active,
      created_at,
      updated_at
    ) values (
      category_row.hotel_id,
      category_row.category_name,
      code_candidate,
      100 + suffix,
      true,
      now(),
      now()
    );
  end loop;
end;
$normalize_menu_categories$;

update public.menu_items mi
set category_id = mc.id
from public.menu_categories mc
where mc.hotel_id = mi.hotel_id
  and lower(trim(mc.name)) =
    lower(trim(mi.category))
  and mi.category_id is null
  and nullif(trim(mi.category), '') is not null;

do $menu_category_fk$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'menu_items_hotel_category_fkey'
      and conrelid = 'public.menu_items'::regclass
  ) then
    alter table public.menu_items
      add constraint menu_items_hotel_category_fkey
      foreign key (hotel_id, category_id)
      references public.menu_categories(hotel_id, id)
      on delete restrict
      not valid;

    alter table public.menu_items
      validate constraint menu_items_hotel_category_fkey;
  end if;
end;
$menu_category_fk$;

create index if not exists idx_menu_items_hotel_category
on public.menu_items (hotel_id, category_id, is_available);

create or replace function private.sync_menu_item_category_20260727()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  resolved_id uuid;
  resolved_name text;
begin
  if new.category_id is not null then
    select mc.id, mc.name
    into resolved_id, resolved_name
    from public.menu_categories mc
    where mc.hotel_id = new.hotel_id
      and mc.id = new.category_id;

    if resolved_id is null then
      raise exception
        'Menu category does not belong to this hotel.';
    end if;

    new.category := resolved_name;
  elsif nullif(trim(new.category), '') is not null then
    select mc.id, mc.name
    into resolved_id, resolved_name
    from public.menu_categories mc
    where mc.hotel_id = new.hotel_id
      and lower(trim(mc.name)) =
        lower(trim(new.category))
    order by mc.sort_order, mc.created_at nulls last, mc.id
    limit 1;

    if resolved_id is not null then
      new.category_id := resolved_id;
      new.category := resolved_name;
    end if;
  end if;

  return new;
end;
$$;

revoke all on function
  private.sync_menu_item_category_20260727()
from public, anon, authenticated;

drop trigger if exists sync_menu_item_category_20260727
on public.menu_items;

create trigger sync_menu_item_category_20260727
before insert or update of hotel_id, category_id, category
on public.menu_items
for each row execute function
  private.sync_menu_item_category_20260727();

-- ============================================================================
-- 7. NORMALIZE EXISTING SERVICE-REQUEST TYPES
-- ============================================================================

alter table public.service_requests
  add column if not exists request_type_id uuid;

do $normalize_request_types$
declare
  request_row record;
  base_code text;
  code_candidate text;
  suffix integer;
begin
  for request_row in
    select distinct
      sr.hotel_id,
      trim(sr.request_type) as request_name
    from public.service_requests sr
    where nullif(trim(sr.request_type), '') is not null
      and not exists (
        select 1
        from public.service_request_types srt
        where srt.hotel_id = sr.hotel_id
          and lower(trim(srt.name)) =
            lower(trim(sr.request_type))
      )
    order by sr.hotel_id, trim(sr.request_type)
  loop
    base_code :=
      private.normalize_hotel_slug(request_row.request_name);
    code_candidate := base_code;
    suffix := 1;

    while exists (
      select 1
      from public.service_request_types srt
      where srt.hotel_id = request_row.hotel_id
        and upper(trim(srt.code)) =
          upper(code_candidate)
    )
    loop
      suffix := suffix + 1;
      code_candidate :=
        left(
          base_code,
          greatest(1, 48 - length(suffix::text) - 1)
        ) || '-' || suffix::text;
    end loop;

    insert into public.service_request_types (
      hotel_id,
      name,
      code,
      description,
      default_priority,
      guest_visible,
      is_active,
      sort_order,
      created_at,
      updated_at
    ) values (
      request_row.hotel_id,
      request_row.request_name,
      code_candidate,
      'Imported from existing StayQR service requests.',
      'normal',
      true,
      true,
      100 + suffix,
      now(),
      now()
    );
  end loop;
end;
$normalize_request_types$;

update public.service_requests sr
set request_type_id = srt.id
from public.service_request_types srt
where srt.hotel_id = sr.hotel_id
  and lower(trim(srt.name)) =
    lower(trim(sr.request_type))
  and sr.request_type_id is null;

do $request_type_fk$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname =
      'service_requests_hotel_request_type_fkey'
      and conrelid = 'public.service_requests'::regclass
  ) then
    alter table public.service_requests
      add constraint service_requests_hotel_request_type_fkey
      foreign key (hotel_id, request_type_id)
      references public.service_request_types(hotel_id, id)
      on delete restrict
      not valid;

    alter table public.service_requests
      validate constraint
        service_requests_hotel_request_type_fkey;
  end if;
end;
$request_type_fk$;

create index if not exists
  idx_service_requests_hotel_request_type
on public.service_requests (
  hotel_id,
  request_type_id,
  status,
  created_at
);

create or replace function
  private.sync_service_request_type_20260727()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  resolved_id uuid;
  resolved_name text;
begin
  if new.request_type_id is not null then
    select srt.id, srt.name
    into resolved_id, resolved_name
    from public.service_request_types srt
    where srt.hotel_id = new.hotel_id
      and srt.id = new.request_type_id;

    if resolved_id is null then
      raise exception
        'Service request type does not belong to this hotel.';
    end if;

    new.request_type := resolved_name;
  elsif nullif(trim(new.request_type), '') is not null then
    select srt.id, srt.name
    into resolved_id, resolved_name
    from public.service_request_types srt
    where srt.hotel_id = new.hotel_id
      and lower(trim(srt.name)) =
        lower(trim(new.request_type))
    order by srt.sort_order, srt.created_at, srt.id
    limit 1;

    if resolved_id is not null then
      new.request_type_id := resolved_id;
      new.request_type := resolved_name;
    end if;
  end if;

  return new;
end;
$$;

revoke all on function
  private.sync_service_request_type_20260727()
from public, anon, authenticated;

drop trigger if exists sync_service_request_type_20260727
on public.service_requests;

create trigger sync_service_request_type_20260727
before insert or update of hotel_id, request_type_id, request_type
on public.service_requests
for each row execute function
  private.sync_service_request_type_20260727();

-- ============================================================================
-- 8. PUBLIC DEFAULT-SEEDING RPCs
-- ============================================================================

create or replace function public.seed_hotel_menu_defaults(
  target_hotel_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid := (select auth.uid());
  result jsonb;
  readiness jsonb;
begin
  if actor_user_id is null then
    raise exception 'Authentication required.';
  end if;

  if not (
    private.is_platform_admin()
    or private.user_has_permission(target_hotel_id, 'hotel.manage')
  ) then
    raise exception 'Hotel configuration access denied.';
  end if;

  result :=
    private.seed_hotel_menu_defaults_internal(
      target_hotel_id,
      actor_user_id
    );

  readiness :=
    private.compute_hotel_onboarding_readiness(
      target_hotel_id
    );

  update public.hotel_onboarding ho
  set
    readiness_state = readiness,
    last_saved_at = now(),
    updated_by = actor_user_id,
    version = ho.version + 1
  where ho.hotel_id = target_hotel_id;

  return result || jsonb_build_object(
    'readiness',
    readiness
  );
end;
$$;

revoke all on function
  public.seed_hotel_menu_defaults(uuid)
from public, anon, authenticated;

grant execute on function
  public.seed_hotel_menu_defaults(uuid)
to authenticated;

create or replace function
  public.seed_hotel_configuration_defaults(
    target_hotel_id uuid
  )
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid := (select auth.uid());
  result jsonb;
  readiness jsonb;
begin
  if actor_user_id is null then
    raise exception 'Authentication required.';
  end if;

  if not (
    private.is_platform_admin()
    or private.user_has_permission(target_hotel_id, 'hotel.manage')
  ) then
    raise exception 'Hotel configuration access denied.';
  end if;

  result :=
    private.seed_hotel_configuration_defaults_internal(
      target_hotel_id,
      actor_user_id
    );

  readiness :=
    private.compute_hotel_onboarding_readiness(
      target_hotel_id
    );

  update public.hotel_onboarding ho
  set
    readiness_state = readiness,
    last_saved_at = now(),
    updated_by = actor_user_id,
    version = ho.version + 1
  where ho.hotel_id = target_hotel_id;

  return result || jsonb_build_object(
    'readiness',
    readiness
  );
end;
$$;

revoke all on function
  public.seed_hotel_configuration_defaults(uuid)
from public, anon, authenticated;

grant execute on function
  public.seed_hotel_configuration_defaults(uuid)
to authenticated;

-- Automatically seed every future hotel, including Migration 018 bootstrap.
create or replace function
  private.seed_new_hotel_configuration_defaults_20260727()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.seed_hotel_configuration_defaults_internal(
    new.id,
    (select auth.uid())
  );

  return new;
end;
$$;

revoke all on function
  private.seed_new_hotel_configuration_defaults_20260727()
from public, anon, authenticated;

drop trigger if exists
  seed_new_hotel_configuration_defaults_20260727
on public.hotels;

create trigger
  seed_new_hotel_configuration_defaults_20260727
after insert on public.hotels
for each row execute function
  private.seed_new_hotel_configuration_defaults_20260727();

-- ============================================================================
-- 9. ATOMIC ROOM TYPE, FLOOR AND RATE CONFIGURATION
-- ============================================================================

create or replace function public.configure_hotel_inventory(
  target_hotel_id uuid,
  payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $configure$
declare
  actor_user_id uuid := (select auth.uid());
  floor_item jsonb;
  room_type_item jsonb;
  rate_item jsonb;

  item_name text;
  item_code text;
  item_description text;
  room_type_code_value text;
  currency_value text;

  existing_id uuid;
  resolved_room_type_id uuid;

  floor_inserted integer := 0;
  floor_updated integer := 0;
  room_type_inserted integer := 0;
  room_type_updated integer := 0;
  rate_inserted integer := 0;
  rate_updated integer := 0;

  readiness jsonb;
begin
  if actor_user_id is null then
    raise exception 'Authentication required.';
  end if;

  if target_hotel_id is null
     or not exists (
       select 1
       from public.hotels h
       where h.id = target_hotel_id
     )
  then
    raise exception 'Unknown hotel.';
  end if;

  if not (
    private.is_platform_admin()
    or private.user_has_permission(target_hotel_id, 'hotel.manage')
  ) then
    raise exception 'Hotel inventory access denied.';
  end if;

  if payload is null or jsonb_typeof(payload) <> 'object' then
    raise exception 'Inventory payload must be a JSON object.';
  end if;

  if payload ? 'floors'
     and coalesce(
       jsonb_typeof(payload -> 'floors'),
       'null'
     ) <> 'array'
  then
    raise exception 'floors must be a JSON array.';
  end if;

  if payload ? 'room_types'
     and coalesce(
       jsonb_typeof(payload -> 'room_types'),
       'null'
     ) <> 'array'
  then
    raise exception 'room_types must be a JSON array.';
  end if;

  if payload ? 'rate_plans'
     and coalesce(
       jsonb_typeof(payload -> 'rate_plans'),
       'null'
     ) <> 'array'
  then
    raise exception 'rate_plans must be a JSON array.';
  end if;

  perform pg_advisory_xact_lock(
    hashtext(
      'stayqr:configure-inventory:' || target_hotel_id::text
    )
  );

  for floor_item in
    select value
    from jsonb_array_elements(
      coalesce(payload -> 'floors', '[]'::jsonb)
    )
  loop
    item_name := nullif(trim(floor_item ->> 'name'), '');
    item_code := upper(
      coalesce(
        nullif(trim(floor_item ->> 'code'), ''),
        private.normalize_hotel_slug(item_name)
      )
    );
    item_description :=
      nullif(trim(floor_item ->> 'description'), '');

    if item_name is null or item_code is null then
      raise exception 'Each floor requires a name and code.';
    end if;

    select f.id
    into existing_id
    from public.floors f
    where f.hotel_id = target_hotel_id
      and upper(trim(f.code)) = item_code
    limit 1;

    if existing_id is null then
      insert into public.floors (
        hotel_id,
        name,
        code,
        floor_number,
        description,
        sort_order,
        is_active,
        created_by,
        updated_by,
        created_at,
        updated_at
      ) values (
        target_hotel_id,
        item_name,
        item_code,
        nullif(trim(floor_item ->> 'floor_number'), '')::integer,
        item_description,
        coalesce(
          nullif(trim(floor_item ->> 'sort_order'), '')::integer,
          0
        ),
        coalesce(
          nullif(trim(floor_item ->> 'is_active'), '')::boolean,
          true
        ),
        actor_user_id,
        actor_user_id,
        now(),
        now()
      );

      floor_inserted := floor_inserted + 1;
    else
      update public.floors f
      set
        name = item_name,
        floor_number = coalesce(
          nullif(trim(floor_item ->> 'floor_number'), '')::integer,
          f.floor_number
        ),
        description = item_description,
        sort_order = coalesce(
          nullif(trim(floor_item ->> 'sort_order'), '')::integer,
          f.sort_order
        ),
        is_active = coalesce(
          nullif(trim(floor_item ->> 'is_active'), '')::boolean,
          f.is_active
        ),
        updated_by = actor_user_id,
        updated_at = now()
      where f.id = existing_id;

      floor_updated := floor_updated + 1;
    end if;
  end loop;

  for room_type_item in
    select value
    from jsonb_array_elements(
      coalesce(payload -> 'room_types', '[]'::jsonb)
    )
  loop
    item_name :=
      nullif(trim(room_type_item ->> 'name'), '');
    item_code := upper(
      coalesce(
        nullif(trim(room_type_item ->> 'code'), ''),
        private.normalize_hotel_slug(item_name)
      )
    );
    item_description :=
      nullif(trim(room_type_item ->> 'description'), '');

    if item_name is null or item_code is null then
      raise exception
        'Each room type requires a name and code.';
    end if;

    select rt.id
    into existing_id
    from public.room_types rt
    where rt.hotel_id = target_hotel_id
      and upper(trim(rt.code)) = item_code
    limit 1;

    if existing_id is null then
      insert into public.room_types (
        hotel_id,
        name,
        code,
        description,
        base_occupancy,
        max_adults,
        max_children,
        max_occupancy,
        base_rate,
        extra_adult_rate,
        extra_child_rate,
        is_active,
        sort_order,
        created_at,
        updated_at
      ) values (
        target_hotel_id,
        item_name,
        item_code,
        item_description,
        coalesce(
          nullif(trim(room_type_item ->> 'base_occupancy'), '')::integer,
          1
        ),
        coalesce(
          nullif(trim(room_type_item ->> 'max_adults'), '')::integer,
          2
        ),
        coalesce(
          nullif(trim(room_type_item ->> 'max_children'), '')::integer,
          1
        ),
        coalesce(
          nullif(trim(room_type_item ->> 'max_occupancy'), '')::integer,
          3
        ),
        coalesce(
          nullif(trim(room_type_item ->> 'base_rate'), '')::numeric,
          0
        ),
        coalesce(
          nullif(trim(room_type_item ->> 'extra_adult_rate'), '')::numeric,
          0
        ),
        coalesce(
          nullif(trim(room_type_item ->> 'extra_child_rate'), '')::numeric,
          0
        ),
        coalesce(
          nullif(trim(room_type_item ->> 'is_active'), '')::boolean,
          true
        ),
        coalesce(
          nullif(trim(room_type_item ->> 'sort_order'), '')::integer,
          0
        ),
        now(),
        now()
      );

      room_type_inserted := room_type_inserted + 1;
    else
      update public.room_types rt
      set
        name = item_name,
        description = item_description,
        base_occupancy = coalesce(
          nullif(trim(room_type_item ->> 'base_occupancy'), '')::integer,
          rt.base_occupancy
        ),
        max_adults = coalesce(
          nullif(trim(room_type_item ->> 'max_adults'), '')::integer,
          rt.max_adults
        ),
        max_children = coalesce(
          nullif(trim(room_type_item ->> 'max_children'), '')::integer,
          rt.max_children
        ),
        max_occupancy = coalesce(
          nullif(trim(room_type_item ->> 'max_occupancy'), '')::integer,
          rt.max_occupancy
        ),
        base_rate = coalesce(
          nullif(trim(room_type_item ->> 'base_rate'), '')::numeric,
          rt.base_rate
        ),
        extra_adult_rate = coalesce(
          nullif(trim(room_type_item ->> 'extra_adult_rate'), '')::numeric,
          rt.extra_adult_rate
        ),
        extra_child_rate = coalesce(
          nullif(trim(room_type_item ->> 'extra_child_rate'), '')::numeric,
          rt.extra_child_rate
        ),
        is_active = coalesce(
          nullif(trim(room_type_item ->> 'is_active'), '')::boolean,
          rt.is_active
        ),
        sort_order = coalesce(
          nullif(trim(room_type_item ->> 'sort_order'), '')::integer,
          rt.sort_order
        ),
        updated_at = now()
      where rt.id = existing_id;

      room_type_updated := room_type_updated + 1;
    end if;
  end loop;

  select h.currency_code
  into currency_value
  from public.hotels h
  where h.id = target_hotel_id;

  for rate_item in
    select value
    from jsonb_array_elements(
      coalesce(payload -> 'rate_plans', '[]'::jsonb)
    )
  loop
    item_name := nullif(trim(rate_item ->> 'name'), '');
    item_code := upper(
      coalesce(
        nullif(trim(rate_item ->> 'code'), ''),
        private.normalize_hotel_slug(item_name)
      )
    );
    room_type_code_value :=
      upper(nullif(trim(rate_item ->> 'room_type_code'), ''));
    item_description :=
      nullif(trim(rate_item ->> 'description'), '');

    if item_name is null
       or item_code is null
       or room_type_code_value is null
    then
      raise exception
        'Each rate plan requires name, code and room_type_code.';
    end if;

    select rt.id
    into resolved_room_type_id
    from public.room_types rt
    where rt.hotel_id = target_hotel_id
      and upper(trim(rt.code)) = room_type_code_value
    limit 1;

    if resolved_room_type_id is null then
      raise exception
        'Unknown room_type_code for rate plan: %.',
        room_type_code_value;
    end if;

    select rp.id
    into existing_id
    from public.rate_plans rp
    where rp.hotel_id = target_hotel_id
      and upper(trim(rp.code)) = item_code
    limit 1;

    if existing_id is null then
      insert into public.rate_plans (
        hotel_id,
        room_type_id,
        name,
        code,
        description,
        meal_plan,
        currency_code,
        base_rate,
        extra_adult_rate,
        extra_child_rate,
        minimum_stay,
        maximum_stay,
        cancellation_policy,
        is_refundable,
        is_active,
        priority,
        created_at,
        updated_at
      ) values (
        target_hotel_id,
        resolved_room_type_id,
        item_name,
        item_code,
        item_description,
        coalesce(
          nullif(trim(rate_item ->> 'meal_plan'), ''),
          'room_only'
        ),
        upper(
          coalesce(
            nullif(trim(rate_item ->> 'currency_code'), ''),
            currency_value
          )
        ),
        coalesce(
          nullif(trim(rate_item ->> 'base_rate'), '')::numeric,
          0
        ),
        coalesce(
          nullif(trim(rate_item ->> 'extra_adult_rate'), '')::numeric,
          0
        ),
        coalesce(
          nullif(trim(rate_item ->> 'extra_child_rate'), '')::numeric,
          0
        ),
        coalesce(
          nullif(trim(rate_item ->> 'minimum_stay'), '')::integer,
          1
        ),
        nullif(trim(rate_item ->> 'maximum_stay'), '')::integer,
        nullif(trim(rate_item ->> 'cancellation_policy'), ''),
        coalesce(
          nullif(trim(rate_item ->> 'is_refundable'), '')::boolean,
          true
        ),
        coalesce(
          nullif(trim(rate_item ->> 'is_active'), '')::boolean,
          true
        ),
        coalesce(
          nullif(trim(rate_item ->> 'priority'), '')::integer,
          100
        ),
        now(),
        now()
      );

      rate_inserted := rate_inserted + 1;
    else
      update public.rate_plans rp
      set
        room_type_id = resolved_room_type_id,
        name = item_name,
        description = item_description,
        meal_plan = coalesce(
          nullif(trim(rate_item ->> 'meal_plan'), ''),
          rp.meal_plan
        ),
        currency_code = upper(
          coalesce(
            nullif(trim(rate_item ->> 'currency_code'), ''),
            rp.currency_code
          )
        ),
        base_rate = coalesce(
          nullif(trim(rate_item ->> 'base_rate'), '')::numeric,
          rp.base_rate
        ),
        extra_adult_rate = coalesce(
          nullif(trim(rate_item ->> 'extra_adult_rate'), '')::numeric,
          rp.extra_adult_rate
        ),
        extra_child_rate = coalesce(
          nullif(trim(rate_item ->> 'extra_child_rate'), '')::numeric,
          rp.extra_child_rate
        ),
        minimum_stay = coalesce(
          nullif(trim(rate_item ->> 'minimum_stay'), '')::integer,
          rp.minimum_stay
        ),
        maximum_stay = case
          when rate_item ? 'maximum_stay'
            then nullif(
              trim(rate_item ->> 'maximum_stay'),
              ''
            )::integer
          else rp.maximum_stay
        end,
        cancellation_policy = case
          when rate_item ? 'cancellation_policy'
            then nullif(
              trim(rate_item ->> 'cancellation_policy'),
              ''
            )
          else rp.cancellation_policy
        end,
        is_refundable = coalesce(
          nullif(trim(rate_item ->> 'is_refundable'), '')::boolean,
          rp.is_refundable
        ),
        is_active = coalesce(
          nullif(trim(rate_item ->> 'is_active'), '')::boolean,
          rp.is_active
        ),
        priority = coalesce(
          nullif(trim(rate_item ->> 'priority'), '')::integer,
          rp.priority
        ),
        updated_at = now()
      where rp.id = existing_id;

      rate_updated := rate_updated + 1;
    end if;
  end loop;

  readiness :=
    private.compute_hotel_onboarding_readiness(
      target_hotel_id
    );

  update public.hotel_onboarding ho
  set
    readiness_state = readiness,
    last_saved_at = now(),
    updated_by = actor_user_id,
    version = ho.version + 1
  where ho.hotel_id = target_hotel_id;

  return jsonb_build_object(
    'hotel_id', target_hotel_id,
    'floors', jsonb_build_object(
      'inserted', floor_inserted,
      'updated', floor_updated
    ),
    'room_types', jsonb_build_object(
      'inserted', room_type_inserted,
      'updated', room_type_updated
    ),
    'rate_plans', jsonb_build_object(
      'inserted', rate_inserted,
      'updated', rate_updated
    ),
    'readiness', readiness
  );
exception
  when invalid_text_representation
    or numeric_value_out_of_range
    or check_violation
  then
    raise exception
      'Invalid inventory value: %.',
      sqlerrm;
end;
$configure$;

revoke all on function
  public.configure_hotel_inventory(uuid,jsonb)
from public, anon, authenticated;

grant execute on function
  public.configure_hotel_inventory(uuid,jsonb)
to authenticated;

-- ============================================================================
-- 10. VALIDATED BULK ROOM IMPORT
-- ============================================================================

create or replace function public.import_hotel_rooms(
  target_hotel_id uuid,
  payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $import_rooms$
declare
  actor_user_id uuid := (select auth.uid());
  room_rows jsonb;
  room_item jsonb;

  room_number_value text;
  room_type_code_value text;
  floor_code_value text;
  status_value text;

  resolved_room_type_id uuid;
  resolved_room_type_name text;
  resolved_floor_id uuid;
  existing_room_id uuid;
  existing_status text;
  existing_room_type_id uuid;
  existing_floor_id uuid;

  inserted_count integer := 0;
  updated_count integer := 0;
  unchanged_count integer := 0;

  readiness jsonb;
begin
  if actor_user_id is null then
    raise exception 'Authentication required.';
  end if;

  if target_hotel_id is null
     or not exists (
       select 1
       from public.hotels h
       where h.id = target_hotel_id
     )
  then
    raise exception 'Unknown hotel.';
  end if;

  if not (
    private.is_platform_admin()
    or private.user_has_permission(target_hotel_id, 'hotel.manage')
  ) then
    raise exception 'Room import access denied.';
  end if;

  room_rows := case
    when jsonb_typeof(payload) = 'array' then payload
    when jsonb_typeof(payload) = 'object'
      and jsonb_typeof(payload -> 'rooms') = 'array'
      then payload -> 'rooms'
    else null
  end;

  if room_rows is null then
    raise exception
      'Room import payload must be an array or an object containing a rooms array.';
  end if;

  if jsonb_array_length(room_rows) = 0 then
    raise exception 'At least one room row is required.';
  end if;

  if jsonb_array_length(room_rows) > 1000 then
    raise exception
      'A single room import cannot exceed 1000 rows.';
  end if;

  perform pg_advisory_xact_lock(
    hashtext(
      'stayqr:import-rooms:' || target_hotel_id::text
    )
  );

  if exists (
    select 1
    from (
      select lower(trim(value ->> 'room_number')) as room_key
      from jsonb_array_elements(room_rows)
      group by lower(trim(value ->> 'room_number'))
      having count(*) > 1
    ) duplicate_payload_room
  ) then
    raise exception
      'The import contains duplicate room numbers.';
  end if;

  for room_item in
    select value
    from jsonb_array_elements(room_rows)
  loop
    room_number_value :=
      nullif(trim(room_item ->> 'room_number'), '');
    room_type_code_value :=
      upper(nullif(trim(room_item ->> 'room_type_code'), ''));
    floor_code_value :=
      upper(
        coalesce(
          nullif(trim(room_item ->> 'floor_code'), ''),
          'DEFAULT'
        )
      );
    status_value :=
      lower(
        coalesce(
          nullif(trim(room_item ->> 'status'), ''),
          'available'
        )
      );

    if room_number_value is null then
      raise exception 'Every room row requires room_number.';
    end if;

    if room_type_code_value is null then
      raise exception
        'Room % requires room_type_code.',
        room_number_value;
    end if;

    if status_value not in (
      'available',
      'occupied',
      'cleaning',
      'maintenance',
      'out_of_order'
    ) then
      raise exception
        'Room % has unsupported status %.',
        room_number_value,
        status_value;
    end if;

    select rt.id, rt.name
    into resolved_room_type_id, resolved_room_type_name
    from public.room_types rt
    where rt.hotel_id = target_hotel_id
      and upper(trim(rt.code)) = room_type_code_value
      and rt.is_active
    limit 1;

    if resolved_room_type_id is null then
      raise exception
        'Room % references unknown active room_type_code %.',
        room_number_value,
        room_type_code_value;
    end if;

    select f.id
    into resolved_floor_id
    from public.floors f
    where f.hotel_id = target_hotel_id
      and upper(trim(f.code)) = floor_code_value
      and f.is_active
    limit 1;

    if resolved_floor_id is null then
      raise exception
        'Room % references unknown active floor_code %.',
        room_number_value,
        floor_code_value;
    end if;

    select
      r.id,
      r.status,
      r.room_type_id,
      r.floor_id
    into
      existing_room_id,
      existing_status,
      existing_room_type_id,
      existing_floor_id
    from public.rooms r
    where r.hotel_id = target_hotel_id
      and lower(trim(r.room_number)) =
        lower(room_number_value)
    limit 1
    for update;

    if existing_room_id is null then
      insert into public.rooms (
        hotel_id,
        room_number,
        room_type,
        room_type_id,
        floor_id,
        status,
        created_at
      ) values (
        target_hotel_id,
        room_number_value,
        resolved_room_type_name,
        resolved_room_type_id,
        resolved_floor_id,
        status_value,
        now()
      );

      inserted_count := inserted_count + 1;
    elsif existing_status in ('occupied', 'cleaning')
      and (
        existing_room_type_id is distinct from
          resolved_room_type_id
        or existing_floor_id is distinct from
          resolved_floor_id
        or existing_status is distinct from status_value
      )
    then
      raise exception
        'Occupied/cleaning room % cannot be reconfigured by bulk import.',
        room_number_value;
    elsif existing_room_type_id is not distinct from
          resolved_room_type_id
      and existing_floor_id is not distinct from
          resolved_floor_id
      and existing_status is not distinct from status_value
    then
      unchanged_count := unchanged_count + 1;
    else
      update public.rooms r
      set
        room_type = resolved_room_type_name,
        room_type_id = resolved_room_type_id,
        floor_id = resolved_floor_id,
        status = status_value
      where r.id = existing_room_id;

      updated_count := updated_count + 1;
    end if;
  end loop;

  readiness :=
    private.compute_hotel_onboarding_readiness(
      target_hotel_id
    );

  update public.hotel_onboarding ho
  set
    readiness_state = readiness,
    last_saved_at = now(),
    updated_by = actor_user_id,
    version = ho.version + 1
  where ho.hotel_id = target_hotel_id;

  return jsonb_build_object(
    'hotel_id', target_hotel_id,
    'total_rows', jsonb_array_length(room_rows),
    'inserted', inserted_count,
    'updated', updated_count,
    'unchanged', unchanged_count,
    'readiness', readiness
  );
end;
$import_rooms$;

revoke all on function
  public.import_hotel_rooms(uuid,jsonb)
from public, anon, authenticated;

grant execute on function
  public.import_hotel_rooms(uuid,jsonb)
to authenticated;

-- ============================================================================
-- 11. REFRESH READINESS FOR EXISTING HOTELS
-- ============================================================================

update public.hotel_onboarding ho
set
  readiness_state =
    private.compute_hotel_onboarding_readiness(ho.hotel_id),
  last_saved_at = now(),
  version = ho.version + 1,
  updated_at = now();

-- ============================================================================
-- 12. POST-MIGRATION ASSERTIONS
-- ============================================================================

do $verify$
declare
  function_row record;
begin
  if to_regclass('public.amenities') is null
     or to_regclass('public.service_request_types') is null
  then
    raise exception
      'Migration 019 failed: normalized configuration tables are missing.';
  end if;

  if exists (
    select 1
    from public.menu_items mi
    where nullif(trim(mi.category), '') is not null
      and mi.category_id is null
  ) then
    raise exception
      'Migration 019 failed: an existing menu category was not normalized.';
  end if;

  if exists (
    select 1
    from public.service_requests sr
    where nullif(trim(sr.request_type), '') is not null
      and sr.request_type_id is null
  ) then
    raise exception
      'Migration 019 failed: an existing service request type was not normalized.';
  end if;

  if has_function_privilege(
    'anon',
    'public.configure_hotel_inventory(uuid,jsonb)',
    'EXECUTE'
  ) or has_function_privilege(
    'anon',
    'public.import_hotel_rooms(uuid,jsonb)',
    'EXECUTE'
  ) or has_function_privilege(
    'anon',
    'public.seed_hotel_configuration_defaults(uuid)',
    'EXECUTE'
  ) then
    raise exception
      'Migration 019 failed: anon can execute a protected configuration RPC.';
  end if;

  for function_row in
    select
      p.oid::regprocedure::text as function_name,
      p.prosecdef,
      p.proconfig
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'configure_hotel_inventory',
        'import_hotel_rooms',
        'seed_hotel_menu_defaults',
        'seed_hotel_configuration_defaults'
      )
  loop
    if not function_row.prosecdef then
      raise exception
        'Migration 019 failed: % is not SECURITY DEFINER.',
        function_row.function_name;
    end if;

    if not (
      function_row.proconfig
        @> array['search_path=""']::text[]
      or function_row.proconfig
        @> array['search_path=']::text[]
    ) then
      raise exception
        'Migration 019 failed: % does not lock search_path.',
        function_row.function_name;
    end if;
  end loop;
end;
$verify$;

commit;

-- ============================================================================
-- 13. ACCEPTANCE RESULT
-- ============================================================================

with checks(test_name, passed, details) as (
  values
    (
      '01_amenities_table_created',
      to_regclass('public.amenities') is not null,
      'Normalized hotel-owned amenities table exists.'
    ),
    (
      '02_service_request_types_created',
      to_regclass('public.service_request_types') is not null,
      'Normalized hotel-owned service-request category table exists.'
    ),
    (
      '03_menu_category_metadata_complete',
      (
        select count(*) = 5
        from information_schema.columns
        where table_schema = 'public'
          and table_name = 'menu_categories'
          and column_name in (
            'code',
            'description',
            'sort_order',
            'is_active',
            'updated_at'
          )
      ),
      'Menu categories have stable code, description, ordering, active state and update timestamp.'
    ),
    (
      '04_existing_menu_items_normalized',
      not exists (
        select 1
        from public.menu_items mi
        where nullif(trim(mi.category), '') is not null
          and mi.category_id is null
      ),
      'Every existing text menu category is linked to a normalized category.'
    ),
    (
      '05_existing_requests_normalized',
      not exists (
        select 1
        from public.service_requests sr
        where nullif(trim(sr.request_type), '') is not null
          and sr.request_type_id is null
      ),
      'Every existing text request type is linked to a normalized request category.'
    ),
    (
      '06_menu_category_fk_validated',
      exists (
        select 1
        from pg_constraint
        where conname = 'menu_items_hotel_category_fkey'
          and conrelid = 'public.menu_items'::regclass
          and convalidated
      ),
      'Menu category ownership is protected by a validated hotel-scoped foreign key.'
    ),
    (
      '07_request_type_fk_validated',
      exists (
        select 1
        from pg_constraint
        where conname =
          'service_requests_hotel_request_type_fkey'
          and conrelid = 'public.service_requests'::regclass
          and convalidated
      ),
      'Service-request category ownership is protected by a validated hotel-scoped foreign key.'
    ),
    (
      '08_inventory_unique_indexes',
      to_regclass('public.uq_rooms_hotel_room_number') is not null
      and to_regclass('public.uq_room_types_hotel_code') is not null
      and to_regclass('public.uq_rate_plans_hotel_code') is not null,
      'Room numbers, room-type codes and rate-plan codes are unique within a hotel.'
    ),
    (
      '09_amenities_rls_enabled',
      (
        select c.relrowsecurity
        from pg_class c
        where c.oid = 'public.amenities'::regclass
      ),
      'Amenities is protected by RLS.'
    ),
    (
      '10_request_types_rls_enabled',
      (
        select c.relrowsecurity
        from pg_class c
        where c.oid =
          'public.service_request_types'::regclass
      ),
      'Service request types is protected by RLS.'
    ),
    (
      '11_new_table_policy_matrix',
      (
        select count(*) = 8
        from pg_policies p
        where p.schemaname = 'public'
          and (
            (
              p.tablename = 'amenities'
              and p.policyname like 'stayqr_amenities_%'
            )
            or
            (
              p.tablename = 'service_request_types'
              and p.policyname like
                'stayqr_service_request_types_%'
            )
          )
      ),
      'Both new tenant tables have SELECT/INSERT/UPDATE/DELETE policies.'
    ),
    (
      '12_existing_hotels_have_amenity_defaults',
      not exists (
        select 1
        from public.hotels h
        where not exists (
          select 1
          from public.amenities a
          where a.hotel_id = h.id
            and a.is_active
        )
      ),
      'Every existing hotel has active editable amenity defaults.'
    ),
    (
      '13_existing_hotels_have_request_defaults',
      not exists (
        select 1
        from public.hotels h
        where not exists (
          select 1
          from public.service_request_types srt
          where srt.hotel_id = h.id
            and srt.is_active
        )
      ),
      'Every existing hotel has active editable request-category defaults.'
    ),
    (
      '14_existing_hotels_have_menu_defaults',
      not exists (
        select 1
        from public.hotels h
        where not exists (
          select 1
          from public.menu_categories mc
          where mc.hotel_id = h.id
            and mc.is_active
        )
      ),
      'Every existing hotel has active menu-category defaults.'
    ),
    (
      '15_future_hotel_seed_trigger',
      exists (
        select 1
        from pg_trigger t
        where t.tgrelid = 'public.hotels'::regclass
          and t.tgname =
            'seed_new_hotel_configuration_defaults_20260727'
          and not t.tgisinternal
      ),
      'Every future hotel automatically receives configuration defaults.'
    ),
    (
      '16_configuration_defaults_rpc',
      to_regprocedure(
        'public.seed_hotel_configuration_defaults(uuid)'
      ) is not null,
      'Idempotent hotel amenity/request/menu default RPC exists.'
    ),
    (
      '17_menu_defaults_rpc',
      to_regprocedure(
        'public.seed_hotel_menu_defaults(uuid)'
      ) is not null,
      'Idempotent menu-category default RPC exists.'
    ),
    (
      '18_inventory_configuration_rpc',
      to_regprocedure(
        'public.configure_hotel_inventory(uuid,jsonb)'
      ) is not null,
      'Atomic room-type/floor/rate configuration RPC exists.'
    ),
    (
      '19_bulk_room_import_rpc',
      to_regprocedure(
        'public.import_hotel_rooms(uuid,jsonb)'
      ) is not null,
      'Validated bulk room import/upsert RPC exists.'
    ),
    (
      '20_authenticated_configuration_execute',
      has_function_privilege(
        'authenticated',
        'public.configure_hotel_inventory(uuid,jsonb)',
        'EXECUTE'
      )
      and has_function_privilege(
        'authenticated',
        'public.import_hotel_rooms(uuid,jsonb)',
        'EXECUTE'
      )
      and has_function_privilege(
        'authenticated',
        'public.seed_hotel_configuration_defaults(uuid)',
        'EXECUTE'
      ),
      'Authenticated hotel managers can execute the approved configuration RPCs.'
    ),
    (
      '21_anonymous_configuration_blocked',
      not has_function_privilege(
        'anon',
        'public.configure_hotel_inventory(uuid,jsonb)',
        'EXECUTE'
      )
      and not has_function_privilege(
        'anon',
        'public.import_hotel_rooms(uuid,jsonb)',
        'EXECUTE'
      )
      and not has_function_privilege(
        'anon',
        'public.seed_hotel_configuration_defaults(uuid)',
        'EXECUTE'
      ),
      'Anonymous users cannot configure inventory or defaults.'
    ),
    (
      '22_existing_room_integrity_preserved',
      not exists (
        select 1
        from public.rooms r
        where r.room_type_id is null
           or r.floor_id is null
           or nullif(trim(r.room_number), '') is null
      ),
      'Existing rooms remain fully normalized and valid.'
    ),
    (
      '23_readiness_snapshots_refreshed',
      not exists (
        select 1
        from public.hotel_onboarding ho
        where not (ho.readiness_state ? 'checklist')
          or not (
            ho.readiness_state
            -> 'checklist'
            ? 'amenities'
          )
          or not (
            ho.readiness_state
            -> 'checklist'
            ? 'request_categories'
          )
      ),
      'Every onboarding record has refreshed amenity and request-category readiness.'
    ),
    (
      '24_day8_configuration_backend_ready',
      to_regclass('public.amenities') is not null
      and to_regclass('public.service_request_types') is not null
      and to_regprocedure(
        'public.configure_hotel_inventory(uuid,jsonb)'
      ) is not null
      and to_regprocedure(
        'public.import_hotel_rooms(uuid,jsonb)'
      ) is not null,
      'Day 8 backend configuration foundation is ready for runtime acceptance and frontend wizard integration.'
    )
)
select test_name, passed, details
from checks
order by test_name;
