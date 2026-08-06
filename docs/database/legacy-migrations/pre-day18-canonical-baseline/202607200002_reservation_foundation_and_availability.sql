-- ============================================================================
-- StayQR v1.0
-- Migration: 202607200002_reservation_foundation_and_availability
-- Revision: 1 (adds composite tenant parent keys for guests and guest_sessions)
-- Date: 20 July 2026
--
-- PURPOSE
--   1. Introduce the production Reservation and Booking data model.
--   2. Normalize room types and rate plans without breaking the existing UI.
--   3. Establish one authoritative room-inventory allocation ledger.
--   4. Prevent overlapping room reservations/blocks/stays at database level.
--   5. Synchronize existing and future direct guest stays into inventory.
--   6. Expose secure hotel-scoped availability and nightly-rate quote RPCs.
--
-- PREREQUISITE
--   Migration 202607200001_tenant_foundation_and_guarded_repairs must have
--   completed and its verification must be green.
--
-- SAFETY
--   - Run the complete file once using the postgres role.
--   - The complete migration is transactional.
--   - Existing `rooms.room_type` remains for frontend compatibility.
--   - Existing reservations are not assumed because no reservation table exists.
--   - No hotel room price is invented. Backfilled Standard Rate plans use 0
--     until the hotel configures real rates.
-- ============================================================================

begin;

set local lock_timeout = '10s';
set local statement_timeout = '240s';

select pg_advisory_xact_lock(
  hashtext('stayqr:202607200002_reservation_foundation_and_availability')
);

-- ============================================================================
-- 0. PREREQUISITE ASSERTIONS
-- ============================================================================

do $$
begin
  if to_regprocedure('private.user_has_hotel_access(uuid)') is null
     or to_regprocedure('private.user_has_hotel_role(uuid,text[])') is null
     or to_regprocedure('private.set_updated_at()') is null
  then
    raise exception
      'Migration stopped: tenant foundation helper functions are missing.';
  end if;

  if exists (
    select 1
    from information_schema.columns c
    where c.table_schema = 'public'
      and c.column_name = 'hotel_id'
      and c.table_name in (
        'rooms',
        'guests',
        'guest_sessions',
        'staff',
        'hotel_users'
      )
      and c.is_nullable = 'YES'
  ) then
    raise exception
      'Migration stopped: tenant foundation NOT NULL rules are incomplete.';
  end if;

  if exists (
    select 1
    from public.guest_sessions gs
    where gs.status = 'active'
      and (
        gs.room_id is null
        or gs.checkout_time <= gs.checkin_time
        or not exists (
          select 1
          from public.rooms r
          where r.id = gs.room_id
            and r.hotel_id = gs.hotel_id
        )
      )
  ) then
    raise exception
      'Migration stopped: an active guest session has invalid inventory dates or room ownership.';
  end if;
end
$$;

create extension if not exists btree_gist with schema extensions;

-- ============================================================================
-- 1. ROOM TYPES
-- ============================================================================

create table if not exists public.room_types (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references public.hotels(id) on delete restrict,
  name text not null,
  code text not null,
  description text,
  base_occupancy integer not null default 1,
  max_adults integer not null default 2,
  max_children integer not null default 1,
  max_occupancy integer not null default 3,
  base_rate numeric(12,2) not null default 0,
  extra_adult_rate numeric(12,2) not null default 0,
  extra_child_rate numeric(12,2) not null default 0,
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint room_types_name_not_blank
    check (length(trim(name)) > 0),
  constraint room_types_code_not_blank
    check (length(trim(code)) > 0),
  constraint room_types_occupancy_check
    check (
      base_occupancy >= 1
      and max_adults >= 1
      and max_children >= 0
      and max_occupancy >= base_occupancy
      and max_occupancy >= max_adults
    ),
  constraint room_types_rates_nonnegative
    check (
      base_rate >= 0
      and extra_adult_rate >= 0
      and extra_child_rate >= 0
    )
);

create unique index if not exists uq_room_types_hotel_id_id
on public.room_types (hotel_id, id);

create unique index if not exists uq_room_types_hotel_name
on public.room_types (hotel_id, lower(name));

create unique index if not exists uq_room_types_hotel_code
on public.room_types (hotel_id, upper(code));

create index if not exists idx_room_types_hotel_active
on public.room_types (hotel_id, is_active, sort_order);

-- Backfill one normalized room type per existing textual type.
insert into public.room_types (
  hotel_id,
  name,
  code,
  sort_order
)
select
  x.hotel_id,
  x.type_name,
  'RT-' || upper(substr(md5(x.hotel_id::text || ':' || lower(x.type_name)), 1, 8)),
  row_number() over (
    partition by x.hotel_id
    order by lower(x.type_name)
  ) - 1
from (
  select distinct
    r.hotel_id,
    coalesce(nullif(trim(r.room_type), ''), 'Standard') as type_name
  from public.rooms r
) x
on conflict (hotel_id, lower(name)) do nothing;

alter table public.rooms
  add column if not exists room_type_id uuid;

update public.rooms r
set
  room_type = coalesce(nullif(trim(r.room_type), ''), 'Standard'),
  room_type_id = rt.id
from public.room_types rt
where rt.hotel_id = r.hotel_id
  and lower(rt.name) = lower(
    coalesce(nullif(trim(r.room_type), ''), 'Standard')
  )
  and r.room_type_id is null;

do $$
begin
  if exists (
    select 1
    from public.rooms
    where room_type_id is null
  ) then
    raise exception
      'Migration stopped: not every room received a normalized room type.';
  end if;
end
$$;

alter table public.rooms
  alter column room_type_id set not null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'rooms_hotel_room_type_fkey'
      and conrelid = 'public.rooms'::regclass
  ) then
    alter table public.rooms
      add constraint rooms_hotel_room_type_fkey
      foreign key (hotel_id, room_type_id)
      references public.room_types(hotel_id, id)
      on delete restrict;
  end if;
end
$$;

create unique index if not exists uq_rooms_hotel_id_id
on public.rooms (hotel_id, id);

create index if not exists idx_rooms_hotel_room_type_status
on public.rooms (hotel_id, room_type_id, status);

-- Composite parent keys required by hotel-scoped foreign keys below.
-- A normal primary key on `id` alone is not sufficient for a foreign key
-- that references `(hotel_id, id)`.
create unique index if not exists uq_guests_hotel_id_id
on public.guests (hotel_id, id);

create unique index if not exists uq_guest_sessions_hotel_id_id
on public.guest_sessions (hotel_id, id);

-- ============================================================================
-- 2. RATE PLANS AND SEASONAL PRICING
-- ============================================================================

create table if not exists public.rate_plans (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references public.hotels(id) on delete restrict,
  room_type_id uuid not null,
  name text not null,
  code text not null,
  description text,
  meal_plan text not null default 'room_only',
  currency_code text not null default 'INR',
  base_rate numeric(12,2) not null default 0,
  extra_adult_rate numeric(12,2) not null default 0,
  extra_child_rate numeric(12,2) not null default 0,
  minimum_stay integer not null default 1,
  maximum_stay integer,
  cancellation_policy text,
  is_refundable boolean not null default true,
  is_active boolean not null default true,
  priority integer not null default 100,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint rate_plans_room_type_fkey
    foreign key (hotel_id, room_type_id)
    references public.room_types(hotel_id, id)
    on delete restrict,
  constraint rate_plans_name_not_blank
    check (length(trim(name)) > 0),
  constraint rate_plans_code_not_blank
    check (length(trim(code)) > 0),
  constraint rate_plans_currency_check
    check (currency_code ~ '^[A-Z]{3}$'),
  constraint rate_plans_rate_nonnegative
    check (
      base_rate >= 0
      and extra_adult_rate >= 0
      and extra_child_rate >= 0
    ),
  constraint rate_plans_stay_check
    check (
      minimum_stay >= 1
      and (
        maximum_stay is null
        or maximum_stay >= minimum_stay
      )
    )
);

create unique index if not exists uq_rate_plans_hotel_id_id
on public.rate_plans (hotel_id, id);

create unique index if not exists uq_rate_plans_hotel_code
on public.rate_plans (hotel_id, upper(code));

create index if not exists idx_rate_plans_hotel_room_type_active
on public.rate_plans (hotel_id, room_type_id, is_active, priority);

insert into public.rate_plans (
  hotel_id,
  room_type_id,
  name,
  code,
  currency_code,
  base_rate,
  extra_adult_rate,
  extra_child_rate,
  is_active,
  priority
)
select
  rt.hotel_id,
  rt.id,
  'Standard Rate',
  'BAR-' || upper(substr(md5(rt.id::text), 1, 8)),
  h.currency_code,
  rt.base_rate,
  rt.extra_adult_rate,
  rt.extra_child_rate,
  true,
  100
from public.room_types rt
join public.hotels h on h.id = rt.hotel_id
where not exists (
  select 1
  from public.rate_plans rp
  where rp.hotel_id = rt.hotel_id
    and rp.room_type_id = rt.id
)
on conflict do nothing;

create table if not exists public.seasonal_rates (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references public.hotels(id) on delete restrict,
  rate_plan_id uuid not null,
  name text not null,
  start_date date not null,
  end_date date not null,
  nightly_rate numeric(12,2) not null,
  extra_adult_rate numeric(12,2),
  extra_child_rate numeric(12,2),
  priority integer not null default 100,
  is_active boolean not null default true,
  days_of_week smallint[],
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint seasonal_rates_rate_plan_fkey
    foreign key (hotel_id, rate_plan_id)
    references public.rate_plans(hotel_id, id)
    on delete cascade,
  constraint seasonal_rates_dates_check
    check (end_date > start_date),
  constraint seasonal_rates_amount_check
    check (
      nightly_rate >= 0
      and (extra_adult_rate is null or extra_adult_rate >= 0)
      and (extra_child_rate is null or extra_child_rate >= 0)
    ),
  constraint seasonal_rates_days_check
    check (
      days_of_week is null
      or days_of_week <@ array[0,1,2,3,4,5,6]::smallint[]
    )
);

create unique index if not exists uq_seasonal_rates_hotel_id_id
on public.seasonal_rates (hotel_id, id);

create index if not exists idx_seasonal_rates_lookup
on public.seasonal_rates (
  hotel_id,
  rate_plan_id,
  is_active,
  start_date,
  end_date,
  priority desc
);

-- ============================================================================
-- 3. RESERVATION HEADER AND ROOMS
-- ============================================================================

create table if not exists public.reservation_number_sequences (
  hotel_id uuid not null references public.hotels(id) on delete cascade,
  sequence_year integer not null,
  last_number bigint not null default 0,
  updated_at timestamptz not null default now(),
  primary key (hotel_id, sequence_year),
  constraint reservation_sequences_year_check
    check (sequence_year between 2000 and 9999),
  constraint reservation_sequences_number_check
    check (last_number >= 0)
);

create table if not exists public.reservations (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references public.hotels(id) on delete restrict,
  reservation_number text not null,
  primary_guest_id uuid,
  status text not null default 'draft',
  booking_source text not null default 'walk_in',
  source_reference text,
  arrival_date date not null,
  departure_date date not null,
  expected_checkin_time time,
  expected_checkout_time time,
  adults integer not null default 1,
  children integer not null default 0,
  currency_code text not null default 'INR',
  room_subtotal numeric(12,2) not null default 0,
  tax_amount numeric(12,2) not null default 0,
  discount_amount numeric(12,2) not null default 0,
  total_amount numeric(12,2) not null default 0,
  deposit_required numeric(12,2) not null default 0,
  deposit_collected numeric(12,2) not null default 0,
  special_requests text,
  internal_notes text,
  cancellation_reason text,
  cancelled_at timestamptz,
  cancelled_by uuid references auth.users(id) on delete set null,
  no_show_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint reservations_hotel_guest_fkey
    foreign key (hotel_id, primary_guest_id)
    references public.guests(hotel_id, id)
    on delete restrict,
  constraint reservations_dates_check
    check (departure_date > arrival_date),
  constraint reservations_status_check
    check (
      status in (
        'draft',
        'tentative',
        'confirmed',
        'checked_in',
        'checked_out',
        'cancelled',
        'no_show'
      )
    ),
  constraint reservations_booking_source_check
    check (
      booking_source in (
        'walk_in',
        'phone',
        'website',
        'ota_manual',
        'travel_agent',
        'corporate',
        'repeat_guest',
        'other'
      )
    ),
  constraint reservations_guest_count_check
    check (adults >= 1 and children >= 0),
  constraint reservations_currency_check
    check (currency_code ~ '^[A-Z]{3}$'),
  constraint reservations_amounts_nonnegative
    check (
      room_subtotal >= 0
      and tax_amount >= 0
      and discount_amount >= 0
      and total_amount >= 0
      and deposit_required >= 0
      and deposit_collected >= 0
    ),
  constraint reservations_total_check
    check (
      total_amount =
        greatest(room_subtotal + tax_amount - discount_amount, 0)
    ),
  constraint reservations_cancelled_metadata_check
    check (
      status <> 'cancelled'
      or cancelled_at is not null
    ),
  constraint reservations_no_show_metadata_check
    check (
      status <> 'no_show'
      or no_show_at is not null
    )
);

create unique index if not exists uq_reservations_hotel_id_id
on public.reservations (hotel_id, id);

create unique index if not exists uq_reservations_hotel_number
on public.reservations (hotel_id, reservation_number);

create index if not exists idx_reservations_hotel_dates_status
on public.reservations (
  hotel_id,
  arrival_date,
  departure_date,
  status
);

create index if not exists idx_reservations_hotel_guest
on public.reservations (hotel_id, primary_guest_id, created_at desc);

create index if not exists idx_reservations_hotel_created
on public.reservations (hotel_id, created_at desc);

create table if not exists public.reservation_rooms (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references public.hotels(id) on delete restrict,
  reservation_id uuid not null,
  room_type_id uuid not null,
  room_id uuid,
  rate_plan_id uuid,
  status text not null default 'held',
  adults integer not null default 1,
  children integer not null default 0,
  nightly_rate numeric(12,2) not null default 0,
  room_subtotal numeric(12,2) not null default 0,
  tax_amount numeric(12,2) not null default 0,
  discount_amount numeric(12,2) not null default 0,
  total_amount numeric(12,2) not null default 0,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint reservation_rooms_reservation_fkey
    foreign key (hotel_id, reservation_id)
    references public.reservations(hotel_id, id)
    on delete cascade,
  constraint reservation_rooms_room_type_fkey
    foreign key (hotel_id, room_type_id)
    references public.room_types(hotel_id, id)
    on delete restrict,
  constraint reservation_rooms_room_fkey
    foreign key (hotel_id, room_id)
    references public.rooms(hotel_id, id)
    on delete restrict,
  constraint reservation_rooms_rate_plan_fkey
    foreign key (hotel_id, rate_plan_id)
    references public.rate_plans(hotel_id, id)
    on delete restrict,
  constraint reservation_rooms_status_check
    check (
      status in (
        'held',
        'confirmed',
        'checked_in',
        'checked_out',
        'cancelled',
        'released'
      )
    ),
  constraint reservation_rooms_guest_count_check
    check (adults >= 1 and children >= 0),
  constraint reservation_rooms_amounts_nonnegative
    check (
      nightly_rate >= 0
      and room_subtotal >= 0
      and tax_amount >= 0
      and discount_amount >= 0
      and total_amount >= 0
    ),
  constraint reservation_rooms_total_check
    check (
      total_amount =
        greatest(room_subtotal + tax_amount - discount_amount, 0)
    )
);

create unique index if not exists uq_reservation_rooms_hotel_id_id
on public.reservation_rooms (hotel_id, id);

create index if not exists idx_reservation_rooms_reservation
on public.reservation_rooms (hotel_id, reservation_id);

create index if not exists idx_reservation_rooms_room_status
on public.reservation_rooms (hotel_id, room_id, status);

create index if not exists idx_reservation_rooms_type_status
on public.reservation_rooms (hotel_id, room_type_id, status);

create table if not exists public.reservation_guests (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references public.hotels(id) on delete restrict,
  reservation_id uuid not null,
  guest_id uuid not null,
  is_primary boolean not null default false,
  created_at timestamptz not null default now(),
  constraint reservation_guests_reservation_fkey
    foreign key (hotel_id, reservation_id)
    references public.reservations(hotel_id, id)
    on delete cascade,
  constraint reservation_guests_guest_fkey
    foreign key (hotel_id, guest_id)
    references public.guests(hotel_id, id)
    on delete restrict
);

create unique index if not exists uq_reservation_guests_hotel_id_id
on public.reservation_guests (hotel_id, id);

create unique index if not exists uq_reservation_guests_reservation_guest
on public.reservation_guests (reservation_id, guest_id);

create unique index if not exists uq_reservation_guests_one_primary
on public.reservation_guests (reservation_id)
where is_primary;

create table if not exists public.reservation_status_history (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references public.hotels(id) on delete restrict,
  reservation_id uuid not null,
  old_status text,
  new_status text not null,
  reason text,
  changed_by uuid references auth.users(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint reservation_status_history_reservation_fkey
    foreign key (hotel_id, reservation_id)
    references public.reservations(hotel_id, id)
    on delete cascade
);

create index if not exists idx_reservation_status_history_reservation
on public.reservation_status_history (
  hotel_id,
  reservation_id,
  created_at desc
);

-- ============================================================================
-- 4. ROOM BLOCKS
-- ============================================================================

create table if not exists public.room_blocks (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references public.hotels(id) on delete restrict,
  room_id uuid not null,
  block_type text not null default 'operational',
  status text not null default 'active',
  start_date date not null,
  end_date date not null,
  reason text not null,
  notes text,
  created_by uuid references auth.users(id) on delete set null,
  released_at timestamptz,
  released_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint room_blocks_room_fkey
    foreign key (hotel_id, room_id)
    references public.rooms(hotel_id, id)
    on delete restrict,
  constraint room_blocks_dates_check
    check (end_date > start_date),
  constraint room_blocks_type_check
    check (
      block_type in (
        'operational',
        'maintenance',
        'out_of_order',
        'owner_use',
        'deep_cleaning',
        'other'
      )
    ),
  constraint room_blocks_status_check
    check (status in ('active', 'released', 'cancelled')),
  constraint room_blocks_reason_not_blank
    check (length(trim(reason)) > 0),
  constraint room_blocks_release_metadata_check
    check (
      status = 'active'
      or released_at is not null
    )
);

create unique index if not exists uq_room_blocks_hotel_id_id
on public.room_blocks (hotel_id, id);

create index if not exists idx_room_blocks_hotel_dates_status
on public.room_blocks (
  hotel_id,
  start_date,
  end_date,
  status
);

create index if not exists idx_room_blocks_room_status
on public.room_blocks (hotel_id, room_id, status);

-- ============================================================================
-- 5. AUTHORITATIVE ROOM INVENTORY LEDGER
-- ============================================================================

create table if not exists public.room_inventory_allocations (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references public.hotels(id) on delete restrict,
  room_id uuid not null,
  allocation_type text not null,
  reservation_room_id uuid,
  room_block_id uuid,
  guest_session_id uuid,
  starts_on date not null,
  ends_on date not null,
  stay_dates daterange generated always as (
    daterange(starts_on, ends_on, '[)')
  ) stored,
  status text not null default 'active',
  released_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint room_inventory_room_fkey
    foreign key (hotel_id, room_id)
    references public.rooms(hotel_id, id)
    on delete restrict,
  constraint room_inventory_reservation_room_fkey
    foreign key (hotel_id, reservation_room_id)
    references public.reservation_rooms(hotel_id, id)
    on delete cascade,
  constraint room_inventory_room_block_fkey
    foreign key (hotel_id, room_block_id)
    references public.room_blocks(hotel_id, id)
    on delete cascade,
  constraint room_inventory_guest_session_fkey
    foreign key (hotel_id, guest_session_id)
    references public.guest_sessions(hotel_id, id)
    on delete cascade,
  constraint room_inventory_dates_check
    check (ends_on > starts_on),
  constraint room_inventory_type_check
    check (
      allocation_type in ('reservation', 'block', 'stay')
    ),
  constraint room_inventory_status_check
    check (status in ('active', 'released', 'cancelled')),
  constraint room_inventory_source_check
    check (
      (
        allocation_type = 'reservation'
        and reservation_room_id is not null
        and room_block_id is null
        and guest_session_id is null
      )
      or
      (
        allocation_type = 'block'
        and reservation_room_id is null
        and room_block_id is not null
        and guest_session_id is null
      )
      or
      (
        allocation_type = 'stay'
        and reservation_room_id is null
        and room_block_id is null
        and guest_session_id is not null
      )
    )
);

create unique index if not exists uq_room_inventory_reservation_room
on public.room_inventory_allocations (reservation_room_id)
where reservation_room_id is not null;

create unique index if not exists uq_room_inventory_room_block
on public.room_inventory_allocations (room_block_id)
where room_block_id is not null;

create unique index if not exists uq_room_inventory_guest_session
on public.room_inventory_allocations (guest_session_id)
where guest_session_id is not null;

create index if not exists idx_room_inventory_hotel_dates
on public.room_inventory_allocations (
  hotel_id,
  starts_on,
  ends_on,
  status
);

create index if not exists idx_room_inventory_room_dates
on public.room_inventory_allocations
using gist (room_id, stay_dates);

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'room_inventory_no_overlapping_active_allocations'
      and conrelid = 'public.room_inventory_allocations'::regclass
  ) then
    alter table public.room_inventory_allocations
      add constraint room_inventory_no_overlapping_active_allocations
      exclude using gist (
        room_id with =,
        stay_dates with &&
      )
      where (status = 'active');
  end if;
end
$$;

-- Reservation linkage on guest sessions. Existing direct stays remain valid.
alter table public.guest_sessions
  add column if not exists reservation_id uuid,
  add column if not exists reservation_room_id uuid;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'guest_sessions_reservation_fkey'
      and conrelid = 'public.guest_sessions'::regclass
  ) then
    alter table public.guest_sessions
      add constraint guest_sessions_reservation_fkey
      foreign key (hotel_id, reservation_id)
      references public.reservations(hotel_id, id)
      on delete restrict;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'guest_sessions_reservation_room_fkey'
      and conrelid = 'public.guest_sessions'::regclass
  ) then
    alter table public.guest_sessions
      add constraint guest_sessions_reservation_room_fkey
      foreign key (hotel_id, reservation_room_id)
      references public.reservation_rooms(hotel_id, id)
      on delete restrict;
  end if;
end
$$;

create index if not exists idx_guest_sessions_reservation
on public.guest_sessions (hotel_id, reservation_id);

-- ============================================================================
-- 6. RESERVATION NUMBERING AND STATUS VALIDATION
-- ============================================================================

create or replace function private.next_reservation_number(
  target_hotel_id uuid,
  target_date date default current_date
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_year integer;
  next_number bigint;
begin
  if target_hotel_id is null then
    raise exception 'Hotel is required.';
  end if;

  target_year := extract(year from target_date)::integer;

  insert into public.reservation_number_sequences (
    hotel_id,
    sequence_year,
    last_number
  )
  values (
    target_hotel_id,
    target_year,
    1
  )
  on conflict (hotel_id, sequence_year)
  do update
  set
    last_number =
      public.reservation_number_sequences.last_number + 1,
    updated_at = now()
  returning last_number into next_number;

  return
    'RES-' ||
    target_year::text ||
    '-' ||
    lpad(next_number::text, 6, '0');
end;
$$;

create or replace function private.validate_reservation_status_transition()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if new.status = 'cancelled' and new.cancelled_at is null then
      new.cancelled_at := now();
      new.cancelled_by := coalesce(new.cancelled_by, auth.uid());
    end if;

    if new.status = 'no_show' and new.no_show_at is null then
      new.no_show_at := now();
    end if;

    return new;
  end if;

  if new.status = old.status then
    return new;
  end if;

  if not (
    (old.status = 'draft'
      and new.status in ('tentative', 'confirmed', 'cancelled'))
    or
    (old.status = 'tentative'
      and new.status in ('confirmed', 'cancelled', 'no_show'))
    or
    (old.status = 'confirmed'
      and new.status in ('checked_in', 'cancelled', 'no_show'))
    or
    (old.status = 'checked_in'
      and new.status = 'checked_out')
  ) then
    raise exception
      'Invalid reservation status transition: % -> %',
      old.status,
      new.status;
  end if;

  if new.status = 'cancelled' then
    new.cancelled_at := coalesce(new.cancelled_at, now());
    new.cancelled_by := coalesce(new.cancelled_by, auth.uid());
  end if;

  if new.status = 'no_show' then
    new.no_show_at := coalesce(new.no_show_at, now());
  end if;

  new.updated_by := coalesce(auth.uid(), new.updated_by);
  return new;
end;
$$;

create or replace function private.log_reservation_status_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.reservation_status_history (
      hotel_id,
      reservation_id,
      old_status,
      new_status,
      changed_by
    )
    values (
      new.hotel_id,
      new.id,
      null,
      new.status,
      coalesce(new.created_by, auth.uid())
    );

    return new;
  end if;

  if new.status is distinct from old.status then
    insert into public.reservation_status_history (
      hotel_id,
      reservation_id,
      old_status,
      new_status,
      changed_by,
      reason
    )
    values (
      new.hotel_id,
      new.id,
      old.status,
      new.status,
      coalesce(new.updated_by, auth.uid()),
      case
        when new.status = 'cancelled' then new.cancellation_reason
        else null
      end
    );
  end if;

  return new;
end;
$$;

-- ============================================================================
-- 7. INVENTORY SYNCHRONIZATION TRIGGERS
-- ============================================================================

create or replace function private.sync_reservation_room_allocation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  reservation_row public.reservations%rowtype;
  should_allocate boolean;
begin
  if tg_op = 'DELETE' then
    delete from public.room_inventory_allocations
    where reservation_room_id = old.id;

    return old;
  end if;

  select *
  into reservation_row
  from public.reservations r
  where r.id = new.reservation_id
    and r.hotel_id = new.hotel_id;

  if not found then
    raise exception
      'Reservation % does not belong to hotel %.',
      new.reservation_id,
      new.hotel_id;
  end if;

  should_allocate :=
    new.room_id is not null
    and reservation_row.status in ('tentative', 'confirmed', 'checked_in')
    and new.status in ('held', 'confirmed', 'checked_in');

  if not should_allocate then
    update public.room_inventory_allocations
    set
      status = 'released',
      released_at = coalesce(released_at, now()),
      updated_at = now()
    where reservation_room_id = new.id
      and status = 'active';

    return new;
  end if;

  insert into public.room_inventory_allocations (
    hotel_id,
    room_id,
    allocation_type,
    reservation_room_id,
    starts_on,
    ends_on,
    status,
    released_at
  )
  values (
    new.hotel_id,
    new.room_id,
    'reservation',
    new.id,
    reservation_row.arrival_date,
    reservation_row.departure_date,
    'active',
    null
  )
  on conflict (reservation_room_id)
    where reservation_room_id is not null
  do update
  set
    room_id = excluded.room_id,
    starts_on = excluded.starts_on,
    ends_on = excluded.ends_on,
    status = 'active',
    released_at = null,
    updated_at = now();

  return new;
end;
$$;

create or replace function private.sync_reservation_header_allocations()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status in ('tentative', 'confirmed', 'checked_in') then
    insert into public.room_inventory_allocations (
      hotel_id,
      room_id,
      allocation_type,
      reservation_room_id,
      starts_on,
      ends_on,
      status,
      released_at
    )
    select
      rr.hotel_id,
      rr.room_id,
      'reservation',
      rr.id,
      new.arrival_date,
      new.departure_date,
      'active',
      null
    from public.reservation_rooms rr
    where rr.hotel_id = new.hotel_id
      and rr.reservation_id = new.id
      and rr.room_id is not null
      and rr.status in ('held', 'confirmed', 'checked_in')
    on conflict (reservation_room_id)
      where reservation_room_id is not null
    do update
    set
      room_id = excluded.room_id,
      starts_on = excluded.starts_on,
      ends_on = excluded.ends_on,
      status = 'active',
      released_at = null,
      updated_at = now();
  else
    update public.room_inventory_allocations ria
    set
      status = 'released',
      released_at = coalesce(ria.released_at, now()),
      updated_at = now()
    where ria.allocation_type = 'reservation'
      and ria.status = 'active'
      and exists (
        select 1
        from public.reservation_rooms rr
        where rr.id = ria.reservation_room_id
          and rr.hotel_id = new.hotel_id
          and rr.reservation_id = new.id
      );
  end if;

  return new;
end;
$$;

create or replace function private.sync_room_block_allocation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    delete from public.room_inventory_allocations
    where room_block_id = old.id;

    return old;
  end if;

  if new.status <> 'active' then
    update public.room_inventory_allocations
    set
      status = case
        when new.status = 'cancelled' then 'cancelled'
        else 'released'
      end,
      released_at = coalesce(released_at, now()),
      updated_at = now()
    where room_block_id = new.id
      and status = 'active';

    return new;
  end if;

  insert into public.room_inventory_allocations (
    hotel_id,
    room_id,
    allocation_type,
    room_block_id,
    starts_on,
    ends_on,
    status,
    released_at
  )
  values (
    new.hotel_id,
    new.room_id,
    'block',
    new.id,
    new.start_date,
    new.end_date,
    'active',
    null
  )
  on conflict (room_block_id)
    where room_block_id is not null
  do update
  set
    room_id = excluded.room_id,
    starts_on = excluded.starts_on,
    ends_on = excluded.ends_on,
    status = 'active',
    released_at = null,
    updated_at = now();

  return new;
end;
$$;

create or replace function private.sync_guest_session_allocation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  hotel_timezone text;
  starts_date date;
  ends_date date;
begin
  if tg_op = 'DELETE' then
    delete from public.room_inventory_allocations
    where guest_session_id = old.id;

    return old;
  end if;

  -- Reservation-linked stays keep the reservation allocation as the source
  -- of truth, preventing a duplicate overlapping allocation for the same stay.
  if new.reservation_room_id is not null then
    update public.room_inventory_allocations
    set
      status = 'released',
      released_at = coalesce(released_at, now()),
      updated_at = now()
    where guest_session_id = new.id
      and status = 'active';

    return new;
  end if;

  if new.status <> 'active' or new.room_id is null then
    update public.room_inventory_allocations
    set
      status = 'released',
      released_at = coalesce(released_at, now()),
      updated_at = now()
    where guest_session_id = new.id
      and status = 'active';

    return new;
  end if;

  select h.timezone
  into hotel_timezone
  from public.hotels h
  where h.id = new.hotel_id;

  if hotel_timezone is null then
    raise exception
      'Hotel timezone is missing for guest session %.',
      new.id;
  end if;

  starts_date :=
    (new.checkin_time at time zone hotel_timezone)::date;

  ends_date :=
    (coalesce(new.extended_until, new.checkout_time)
      at time zone hotel_timezone)::date;

  if ends_date <= starts_date then
    ends_date := starts_date + 1;
  end if;

  insert into public.room_inventory_allocations (
    hotel_id,
    room_id,
    allocation_type,
    guest_session_id,
    starts_on,
    ends_on,
    status,
    released_at
  )
  values (
    new.hotel_id,
    new.room_id,
    'stay',
    new.id,
    starts_date,
    ends_date,
    'active',
    null
  )
  on conflict (guest_session_id)
    where guest_session_id is not null
  do update
  set
    room_id = excluded.room_id,
    starts_on = excluded.starts_on,
    ends_on = excluded.ends_on,
    status = 'active',
    released_at = null,
    updated_at = now();

  return new;
end;
$$;

-- Updated-at triggers
drop trigger if exists room_types_set_updated_at
on public.room_types;
create trigger room_types_set_updated_at
before update on public.room_types
for each row
execute function private.set_updated_at();

drop trigger if exists rate_plans_set_updated_at
on public.rate_plans;
create trigger rate_plans_set_updated_at
before update on public.rate_plans
for each row
execute function private.set_updated_at();

drop trigger if exists seasonal_rates_set_updated_at
on public.seasonal_rates;
create trigger seasonal_rates_set_updated_at
before update on public.seasonal_rates
for each row
execute function private.set_updated_at();

drop trigger if exists reservations_validate_status
on public.reservations;
create trigger reservations_validate_status
before insert or update of status
on public.reservations
for each row
execute function private.validate_reservation_status_transition();

drop trigger if exists reservations_set_updated_at
on public.reservations;
create trigger reservations_set_updated_at
before update on public.reservations
for each row
execute function private.set_updated_at();

drop trigger if exists reservations_log_status
on public.reservations;
create trigger reservations_log_status
after insert or update of status
on public.reservations
for each row
execute function private.log_reservation_status_change();

drop trigger if exists reservations_sync_allocations
on public.reservations;
create trigger reservations_sync_allocations
after update of arrival_date, departure_date, status
on public.reservations
for each row
execute function private.sync_reservation_header_allocations();

drop trigger if exists reservation_rooms_set_updated_at
on public.reservation_rooms;
create trigger reservation_rooms_set_updated_at
before update on public.reservation_rooms
for each row
execute function private.set_updated_at();

drop trigger if exists reservation_rooms_sync_allocation
on public.reservation_rooms;
create trigger reservation_rooms_sync_allocation
after insert or update of room_id, status, reservation_id
or delete
on public.reservation_rooms
for each row
execute function private.sync_reservation_room_allocation();

drop trigger if exists room_blocks_set_updated_at
on public.room_blocks;
create trigger room_blocks_set_updated_at
before update on public.room_blocks
for each row
execute function private.set_updated_at();

drop trigger if exists room_blocks_sync_allocation
on public.room_blocks;
create trigger room_blocks_sync_allocation
after insert or update of room_id, start_date, end_date, status
or delete
on public.room_blocks
for each row
execute function private.sync_room_block_allocation();

drop trigger if exists guest_sessions_sync_inventory
on public.guest_sessions;
create trigger guest_sessions_sync_inventory
after insert or update of
  hotel_id,
  room_id,
  checkin_time,
  checkout_time,
  extended_until,
  status,
  reservation_room_id
or delete
on public.guest_sessions
for each row
execute function private.sync_guest_session_allocation();

-- Backfill current active direct guest stays.
insert into public.room_inventory_allocations (
  hotel_id,
  room_id,
  allocation_type,
  guest_session_id,
  starts_on,
  ends_on,
  status
)
select
  gs.hotel_id,
  gs.room_id,
  'stay',
  gs.id,
  (gs.checkin_time at time zone h.timezone)::date,
  greatest(
    (
      coalesce(gs.extended_until, gs.checkout_time)
      at time zone h.timezone
    )::date,
    (gs.checkin_time at time zone h.timezone)::date + 1
  ),
  'active'
from public.guest_sessions gs
join public.hotels h on h.id = gs.hotel_id
where gs.status = 'active'
  and gs.room_id is not null
  and gs.reservation_room_id is null
on conflict (guest_session_id)
  where guest_session_id is not null
do update
set
  room_id = excluded.room_id,
  starts_on = excluded.starts_on,
  ends_on = excluded.ends_on,
  status = 'active',
  released_at = null,
  updated_at = now();

-- ============================================================================
-- 8. SECURE AVAILABILITY AND RATE QUOTE FUNCTIONS
-- ============================================================================

create or replace function public.get_available_rooms(
  target_hotel_id uuid,
  target_arrival_date date,
  target_departure_date date,
  target_room_type_id uuid default null
)
returns table (
  room_id uuid,
  room_number text,
  room_type_id uuid,
  room_type_name text,
  room_status text,
  max_adults integer,
  max_children integer,
  max_occupancy integer,
  standard_rate numeric,
  active_rate_plan_id uuid,
  active_rate_plan_name text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.user_has_hotel_access(target_hotel_id) then
    raise exception 'Hotel access denied.';
  end if;

  if target_arrival_date is null
     or target_departure_date is null
     or target_departure_date <= target_arrival_date
  then
    raise exception
      'Departure date must be after arrival date.';
  end if;

  if target_departure_date - target_arrival_date > 365 then
    raise exception
      'Availability searches are limited to 365 nights.';
  end if;

  return query
  select
    r.id,
    r.room_number,
    rt.id,
    rt.name,
    r.status,
    rt.max_adults,
    rt.max_children,
    rt.max_occupancy,
    coalesce(rp.base_rate, rt.base_rate)::numeric,
    rp.id,
    rp.name
  from public.rooms r
  join public.room_types rt
    on rt.id = r.room_type_id
   and rt.hotel_id = r.hotel_id
   and rt.is_active
  left join lateral (
    select candidate.*
    from public.rate_plans candidate
    where candidate.hotel_id = r.hotel_id
      and candidate.room_type_id = r.room_type_id
      and candidate.is_active
    order by candidate.priority asc, candidate.created_at asc
    limit 1
  ) rp on true
  join public.hotels h on h.id = r.hotel_id
  where r.hotel_id = target_hotel_id
    and (
      target_room_type_id is null
      or r.room_type_id = target_room_type_id
    )
    and r.status not in ('maintenance', 'out_of_order')
    and not (
      r.status = 'cleaning'
      and target_arrival_date <=
        (now() at time zone h.timezone)::date
    )
    and not exists (
      select 1
      from public.room_inventory_allocations ria
      where ria.hotel_id = r.hotel_id
        and ria.room_id = r.id
        and ria.status = 'active'
        and ria.stay_dates &&
          daterange(
            target_arrival_date,
            target_departure_date,
            '[)'
          )
    )
  order by
    rt.sort_order,
    nullif(regexp_replace(r.room_number, '[^0-9]', '', 'g'), '')::integer
      nulls last,
    r.room_number;
end;
$$;

create or replace function public.get_room_type_availability(
  target_hotel_id uuid,
  target_arrival_date date,
  target_departure_date date
)
returns table (
  room_type_id uuid,
  room_type_name text,
  total_rooms bigint,
  available_rooms bigint,
  standard_rate numeric,
  active_rate_plan_id uuid,
  active_rate_plan_name text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.user_has_hotel_access(target_hotel_id) then
    raise exception 'Hotel access denied.';
  end if;

  if target_arrival_date is null
     or target_departure_date is null
     or target_departure_date <= target_arrival_date
  then
    raise exception
      'Departure date must be after arrival date.';
  end if;

  return query
  with available as (
    select *
    from public.get_available_rooms(
      target_hotel_id,
      target_arrival_date,
      target_departure_date,
      null
    )
  )
  select
    rt.id,
    rt.name,
    count(r.id)::bigint as total_rooms,
    count(a.room_id)::bigint as available_rooms,
    coalesce(rp.base_rate, rt.base_rate)::numeric,
    rp.id,
    rp.name
  from public.room_types rt
  left join public.rooms r
    on r.hotel_id = rt.hotel_id
   and r.room_type_id = rt.id
  left join available a on a.room_id = r.id
  left join lateral (
    select candidate.*
    from public.rate_plans candidate
    where candidate.hotel_id = rt.hotel_id
      and candidate.room_type_id = rt.id
      and candidate.is_active
    order by candidate.priority asc, candidate.created_at asc
    limit 1
  ) rp on true
  where rt.hotel_id = target_hotel_id
    and rt.is_active
  group by
    rt.id,
    rt.name,
    rt.sort_order,
    rt.base_rate,
    rp.id,
    rp.name,
    rp.base_rate
  order by rt.sort_order, rt.name;
end;
$$;

create or replace function public.get_rate_quote(
  target_hotel_id uuid,
  target_rate_plan_id uuid,
  target_arrival_date date,
  target_departure_date date
)
returns table (
  stay_date date,
  rate_plan_id uuid,
  room_type_id uuid,
  currency_code text,
  nightly_rate numeric,
  extra_adult_rate numeric,
  extra_child_rate numeric,
  rate_source text,
  seasonal_rate_id uuid
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.user_has_hotel_access(target_hotel_id) then
    raise exception 'Hotel access denied.';
  end if;

  if target_arrival_date is null
     or target_departure_date is null
     or target_departure_date <= target_arrival_date
  then
    raise exception
      'Departure date must be after arrival date.';
  end if;

  if target_departure_date - target_arrival_date > 365 then
    raise exception
      'Rate quotes are limited to 365 nights.';
  end if;

  if not exists (
    select 1
    from public.rate_plans rp
    where rp.id = target_rate_plan_id
      and rp.hotel_id = target_hotel_id
      and rp.is_active
  ) then
    raise exception
      'Active rate plan not found for this hotel.';
  end if;

  return query
  select
    nights.stay_date,
    rp.id,
    rp.room_type_id,
    rp.currency_code,
    coalesce(sr.nightly_rate, rp.base_rate)::numeric,
    coalesce(sr.extra_adult_rate, rp.extra_adult_rate)::numeric,
    coalesce(sr.extra_child_rate, rp.extra_child_rate)::numeric,
    case
      when sr.id is null then 'base'
      else 'seasonal'
    end,
    sr.id
  from (
    select generate_series(
      target_arrival_date,
      target_departure_date - 1,
      interval '1 day'
    )::date as stay_date
  ) nights
  join public.rate_plans rp
    on rp.id = target_rate_plan_id
   and rp.hotel_id = target_hotel_id
   and rp.is_active
  left join lateral (
    select candidate.*
    from public.seasonal_rates candidate
    where candidate.hotel_id = rp.hotel_id
      and candidate.rate_plan_id = rp.id
      and candidate.is_active
      and nights.stay_date >= candidate.start_date
      and nights.stay_date < candidate.end_date
      and (
        candidate.days_of_week is null
        or extract(dow from nights.stay_date)::smallint =
          any(candidate.days_of_week)
      )
    order by candidate.priority asc, candidate.created_at desc
    limit 1
  ) sr on true
  order by nights.stay_date;
end;
$$;

revoke all on function public.get_available_rooms(
  uuid,
  date,
  date,
  uuid
) from public;

revoke all on function public.get_room_type_availability(
  uuid,
  date,
  date
) from public;

revoke all on function public.get_rate_quote(
  uuid,
  uuid,
  date,
  date
) from public;

grant execute on function public.get_available_rooms(
  uuid,
  date,
  date,
  uuid
) to authenticated;

grant execute on function public.get_room_type_availability(
  uuid,
  date,
  date
) to authenticated;

grant execute on function public.get_rate_quote(
  uuid,
  uuid,
  date,
  date
) to authenticated;

revoke all on function private.next_reservation_number(
  uuid,
  date
) from public;

revoke all on function private.validate_reservation_status_transition()
from public;

revoke all on function private.log_reservation_status_change()
from public;

revoke all on function private.sync_reservation_room_allocation()
from public;

revoke all on function private.sync_reservation_header_allocations()
from public;

revoke all on function private.sync_room_block_allocation()
from public;

revoke all on function private.sync_guest_session_allocation()
from public;

-- ============================================================================
-- 9. RLS
-- ============================================================================

do $$
declare
  tenant_table text;
begin
  foreach tenant_table in array array[
    'room_types',
    'rate_plans',
    'seasonal_rates',
    'reservation_number_sequences',
    'reservations',
    'reservation_rooms',
    'reservation_guests',
    'reservation_status_history',
    'room_blocks',
    'room_inventory_allocations'
  ]
  loop
    execute format(
      'alter table public.%I enable row level security',
      tenant_table
    );
  end loop;
end
$$;

-- Configuration tables: hotel users read; owner/manager manage.
do $$
declare
  config_table text;
begin
  foreach config_table in array array[
    'room_types',
    'rate_plans',
    'seasonal_rates'
  ]
  loop
    execute format(
      'drop policy if exists stayqr_config_select on public.%I',
      config_table
    );
    execute format(
      'drop policy if exists stayqr_config_insert on public.%I',
      config_table
    );
    execute format(
      'drop policy if exists stayqr_config_update on public.%I',
      config_table
    );
    execute format(
      'drop policy if exists stayqr_config_delete on public.%I',
      config_table
    );

    execute format(
      'create policy stayqr_config_select
       on public.%I
       for select
       to authenticated
       using (private.user_has_hotel_access(hotel_id))',
      config_table
    );

    execute format(
      'create policy stayqr_config_insert
       on public.%I
       for insert
       to authenticated
       with check (
         private.user_has_hotel_role(
           hotel_id,
           array[''owner'', ''manager'']
         )
       )',
      config_table
    );

    execute format(
      'create policy stayqr_config_update
       on public.%I
       for update
       to authenticated
       using (
         private.user_has_hotel_role(
           hotel_id,
           array[''owner'', ''manager'']
         )
       )
       with check (
         private.user_has_hotel_role(
           hotel_id,
           array[''owner'', ''manager'']
         )
       )',
      config_table
    );

    execute format(
      'create policy stayqr_config_delete
       on public.%I
       for delete
       to authenticated
       using (
         private.user_has_hotel_role(
           hotel_id,
           array[''owner'', ''manager'']
         )
       )',
      config_table
    );
  end loop;
end
$$;

-- Reservation operational tables: owner/manager/reception/front desk write.
do $$
declare
  operational_table text;
begin
  foreach operational_table in array array[
    'reservations',
    'reservation_rooms',
    'reservation_guests',
    'room_blocks'
  ]
  loop
    execute format(
      'drop policy if exists stayqr_reservation_select on public.%I',
      operational_table
    );
    execute format(
      'drop policy if exists stayqr_reservation_insert on public.%I',
      operational_table
    );
    execute format(
      'drop policy if exists stayqr_reservation_update on public.%I',
      operational_table
    );

    execute format(
      'create policy stayqr_reservation_select
       on public.%I
       for select
       to authenticated
       using (private.user_has_hotel_access(hotel_id))',
      operational_table
    );

    execute format(
      'create policy stayqr_reservation_insert
       on public.%I
       for insert
       to authenticated
       with check (
         private.user_has_hotel_role(
           hotel_id,
           array[
             ''owner'',
             ''manager'',
             ''reception'',
             ''front_desk'',
             ''frontdesk''
           ]
         )
       )',
      operational_table
    );

    execute format(
      'create policy stayqr_reservation_update
       on public.%I
       for update
       to authenticated
       using (
         private.user_has_hotel_role(
           hotel_id,
           array[
             ''owner'',
             ''manager'',
             ''reception'',
             ''front_desk'',
             ''frontdesk''
           ]
         )
       )
       with check (
         private.user_has_hotel_role(
           hotel_id,
           array[
             ''owner'',
             ''manager'',
             ''reception'',
             ''front_desk'',
             ''frontdesk''
           ]
         )
       )',
      operational_table
    );
  end loop;
end
$$;

-- No direct browser writes to sequences, status history or the inventory
-- ledger. Trusted functions/triggers are the only writers.
create policy stayqr_reservation_sequences_select
on public.reservation_number_sequences
for select
to authenticated
using (private.user_has_hotel_access(hotel_id));

create policy stayqr_reservation_history_select
on public.reservation_status_history
for select
to authenticated
using (private.user_has_hotel_access(hotel_id));

create policy stayqr_inventory_select
on public.room_inventory_allocations
for select
to authenticated
using (private.user_has_hotel_access(hotel_id));

-- ============================================================================
-- 10. FINAL ASSERTIONS
-- ============================================================================

do $$
declare
  active_direct_stays bigint;
  active_stay_allocations bigint;
begin
  if exists (
    select 1
    from public.rooms
    where room_type_id is null
  ) then
    raise exception
      'Migration stopped: room type normalization is incomplete.';
  end if;

  if to_regclass('public.uq_guests_hotel_id_id') is null
     or to_regclass('public.uq_guest_sessions_hotel_id_id') is null
  then
    raise exception
      'Migration stopped: composite guest/session tenant keys are missing.';
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'room_inventory_no_overlapping_active_allocations'
      and conrelid = 'public.room_inventory_allocations'::regclass
  ) then
    raise exception
      'Migration stopped: overlap prevention constraint is missing.';
  end if;

  select count(*)
  into active_direct_stays
  from public.guest_sessions gs
  where gs.status = 'active'
    and gs.room_id is not null
    and gs.reservation_room_id is null;

  select count(*)
  into active_stay_allocations
  from public.room_inventory_allocations ria
  where ria.allocation_type = 'stay'
    and ria.status = 'active';

  if active_direct_stays <> active_stay_allocations then
    raise exception
      'Migration stopped: active stay allocation count mismatch (% vs %).',
      active_direct_stays,
      active_stay_allocations;
  end if;

  if to_regprocedure(
    'public.get_available_rooms(uuid,date,date,uuid)'
  ) is null
  then
    raise exception
      'Migration stopped: availability function is missing.';
  end if;

  if to_regprocedure(
    'public.get_rate_quote(uuid,uuid,date,date)'
  ) is null
  then
    raise exception
      'Migration stopped: rate quote function is missing.';
  end if;
end
$$;

commit;

-- Supabase may display one blank `pg_advisory_xact_lock` result row.
-- That is expected and is not an error.
