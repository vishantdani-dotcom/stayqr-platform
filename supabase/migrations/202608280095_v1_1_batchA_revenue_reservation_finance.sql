-- ============================================================================
-- StayQR v1.1 — Batch A: Revenue, Reservation & Finance Growth
-- Migration 095
-- Date: 2026-08-28
--
-- Scope
--   1. Direct website booking widget foundation (safe anon RPC surface)
--   2. Corporate profiles + negotiated room rates
--   3. Split-stay planned room-move refinement on top of existing atomic move RPC
--   4. Split-bill payer shares on top of the authoritative Day 11 folio ledger
--   5. Accounting export connector profiles/templates on top of Day 12 exports
--
-- Safety
--   * Additive and tenant-scoped.
--   * Existing reservation, folio, invoice, room-move and accounting functions
--     are not replaced.
--   * Public booking is DISABLED by default for every existing hotel.
--   * Anonymous users receive EXECUTE only on narrowly-scoped public booking RPCs;
--     no direct table access is granted.
-- ============================================================================

begin;

set local lock_timeout = '10s';
set local statement_timeout = '120s';

select pg_advisory_xact_lock(hashtext('stayqr:v1.1:batchA:095'));

-- --------------------------------------------------------------------------
-- 0. Preconditions
-- --------------------------------------------------------------------------
do $preflight$
begin
  if to_regclass('public.hotels') is null
     or to_regclass('public.rooms') is null
     or to_regclass('public.room_types') is null
     or to_regclass('public.rate_plans') is null
     or to_regclass('public.seasonal_rates') is null
     or to_regclass('public.reservations') is null
     or to_regclass('public.reservation_rooms') is null
     or to_regclass('public.reservation_guests') is null
     or to_regclass('public.room_inventory_allocations') is null
     or to_regclass('public.guest_sessions') is null
     or to_regclass('public.folios') is null
     or to_regclass('public.folio_collections') is null
     or to_regclass('public.accounting_exports') is null
  then
    raise exception 'Migration 095: required v1.0 foundation table is missing.';
  end if;

  if to_regprocedure('private.user_has_any_permission(uuid,text[])') is null
     or to_regprocedure('private.resolve_reservation_guest(uuid,jsonb)') is null
     or to_regprocedure('private.next_reservation_number(uuid,date)') is null
     or to_regprocedure('private.day11_require_current_actor()') is null
     or to_regprocedure('private.day11_post_collection(uuid,uuid,numeric,text,uuid,text,text,text,text,text,uuid,text,timestamptz,uuid,jsonb)') is null
     or to_regprocedure('private.day12_build_accounting_csv(uuid,date,date)') is null
     or to_regprocedure('private.day12_hash_text(text)') is null
     or to_regprocedure('private.day12_csv_escape(text)') is null
  then
    raise exception 'Migration 095: required authoritative private RPC foundation is missing.';
  end if;
end;
$preflight$;

-- --------------------------------------------------------------------------
-- 1. Public direct-booking configuration
-- --------------------------------------------------------------------------
create table if not exists public.public_booking_settings (
  hotel_id uuid primary key references public.hotels(id) on delete cascade,
  enabled boolean not null default false,
  confirmation_mode text not null default 'instant'
    check (confirmation_mode in ('instant','request')),
  minimum_stay integer not null default 1
    check (minimum_stay between 1 and 365),
  maximum_stay integer not null default 30
    check (maximum_stay between 1 and 365),
  maximum_advance_days integer not null default 365
    check (maximum_advance_days between 1 and 730),
  deposit_percent numeric(5,2) not null default 0
    check (deposit_percent between 0 and 100),
  booking_message text,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint public_booking_settings_stay_check
    check (maximum_stay >= minimum_stay)
);

insert into public.public_booking_settings (hotel_id, enabled)
select h.id, false
from public.hotels h
on conflict (hotel_id) do nothing;

-- --------------------------------------------------------------------------
-- 2. Corporate profiles + negotiated rates
-- --------------------------------------------------------------------------
create table if not exists public.corporate_accounts (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references public.hotels(id) on delete cascade,
  name text not null check (length(trim(name)) > 1),
  code text not null check (length(trim(code)) between 2 and 40),
  booking_code text not null check (length(trim(booking_code)) between 4 and 40),
  gstin text,
  billing_email text,
  billing_phone text,
  billing_address text,
  notes text,
  status text not null default 'active' check (status in ('active','inactive')),
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint corporate_accounts_gstin_check
    check (gstin is null or gstin ~ '^[0-9]{2}[A-Z0-9]{13}$')
);

create unique index if not exists uq_corporate_accounts_code
  on public.corporate_accounts (hotel_id, lower(code));
create unique index if not exists uq_corporate_accounts_booking_code
  on public.corporate_accounts (hotel_id, lower(booking_code));
create unique index if not exists uq_corporate_accounts_hotel_id_id
  on public.corporate_accounts (hotel_id, id);

create table if not exists public.corporate_rates (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references public.hotels(id) on delete cascade,
  corporate_account_id uuid not null,
  room_type_id uuid not null references public.room_types(id) on delete restrict,
  rate_plan_id uuid not null references public.rate_plans(id) on delete restrict,
  negotiated_rate numeric(12,2) not null check (negotiated_rate >= 0),
  extra_adult_rate numeric(12,2) check (extra_adult_rate is null or extra_adult_rate >= 0),
  extra_child_rate numeric(12,2) check (extra_child_rate is null or extra_child_rate >= 0),
  minimum_stay integer not null default 1 check (minimum_stay between 1 and 365),
  maximum_stay integer check (maximum_stay is null or maximum_stay between 1 and 365),
  valid_from date not null default current_date,
  valid_to date,
  is_active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint corporate_rates_account_fk foreign key (hotel_id, corporate_account_id)
    references public.corporate_accounts(hotel_id, id) on delete cascade,
  constraint corporate_rates_dates_check check (valid_to is null or valid_to >= valid_from),
  constraint corporate_rates_stay_check check (maximum_stay is null or maximum_stay >= minimum_stay)
);

create index if not exists ix_corporate_rates_lookup
  on public.corporate_rates (hotel_id, corporate_account_id, room_type_id, is_active, valid_from, valid_to);
create unique index if not exists uq_corporate_rates_hotel_id_id
  on public.corporate_rates (hotel_id, id);

create table if not exists public.reservation_corporate_links (
  hotel_id uuid not null references public.hotels(id) on delete cascade,
  reservation_id uuid primary key references public.reservations(id) on delete cascade,
  corporate_account_id uuid not null,
  corporate_rate_id uuid,
  booking_code text,
  rate_snapshot jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint reservation_corporate_account_fk foreign key (hotel_id, corporate_account_id)
    references public.corporate_accounts(hotel_id, id) on delete restrict,
  constraint reservation_corporate_rate_fk foreign key (hotel_id, corporate_rate_id)
    references public.corporate_rates(hotel_id, id) on delete set null
);

create index if not exists ix_reservation_corporate_links_hotel
  on public.reservation_corporate_links (hotel_id, corporate_account_id, created_at desc);

-- --------------------------------------------------------------------------
-- 3. Public booking idempotency evidence (no raw PII stored)
-- --------------------------------------------------------------------------
create table if not exists public.public_booking_requests (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references public.hotels(id) on delete cascade,
  request_key text not null check (length(trim(request_key)) between 8 and 160),
  request_hash text not null check (length(request_hash) = 32),
  reservation_id uuid not null references public.reservations(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (hotel_id, request_key)
);

-- --------------------------------------------------------------------------
-- 4. Split-stay planned move refinement
--    Actual room move remains the existing authoritative atomic room-move RPC.
-- --------------------------------------------------------------------------
create table if not exists public.stay_move_plans (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references public.hotels(id) on delete cascade,
  guest_session_id uuid not null references public.guest_sessions(id) on delete cascade,
  reservation_id uuid references public.reservations(id) on delete set null,
  from_room_id uuid not null references public.rooms(id) on delete restrict,
  to_room_id uuid not null references public.rooms(id) on delete restrict,
  planned_date date not null,
  status text not null default 'planned' check (status in ('planned','verified','cancelled')),
  notes text,
  created_by uuid not null references auth.users(id) on delete restrict,
  verified_at timestamptz,
  verified_by uuid references auth.users(id) on delete set null,
  cancelled_at timestamptz,
  cancelled_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  constraint stay_move_plan_room_check check (from_room_id <> to_room_id),
  constraint stay_move_plan_verified_check check (status <> 'verified' or verified_at is not null),
  constraint stay_move_plan_cancelled_check check (status <> 'cancelled' or cancelled_at is not null)
);

create unique index if not exists uq_stay_move_plan_active_date
  on public.stay_move_plans (hotel_id, guest_session_id, planned_date)
  where status = 'planned';

-- --------------------------------------------------------------------------
-- 5. Split-bill payer shares. Ledger stays authoritative.
-- --------------------------------------------------------------------------
create table if not exists public.folio_split_shares (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references public.hotels(id) on delete cascade,
  folio_id uuid not null references public.folios(id) on delete cascade,
  payer_label text not null check (length(trim(payer_label)) between 1 and 80),
  allocated_amount numeric(14,2) not null check (allocated_amount > 0),
  paid_amount numeric(14,2) not null default 0 check (paid_amount >= 0),
  status text not null default 'open' check (status in ('open','settled')),
  sort_order integer not null default 0,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  constraint folio_split_share_amount_check check (paid_amount <= allocated_amount),
  constraint folio_split_share_status_check check (
    (status = 'open' and paid_amount < allocated_amount)
    or (status = 'settled' and paid_amount = allocated_amount)
  )
);

create unique index if not exists uq_folio_split_share_label
  on public.folio_split_shares (hotel_id, folio_id, lower(payer_label));
create index if not exists ix_folio_split_shares_folio
  on public.folio_split_shares (hotel_id, folio_id, sort_order, created_at);

-- --------------------------------------------------------------------------
-- 6. Accounting connector profiles
-- --------------------------------------------------------------------------
create table if not exists public.accounting_export_profiles (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references public.hotels(id) on delete cascade,
  profile_name text not null check (length(trim(profile_name)) between 2 and 80),
  template text not null check (template in ('stayqr','tally','zoho_books','quickbooks','generic')),
  is_default boolean not null default false,
  is_active boolean not null default true,
  mapping jsonb not null default '{}'::jsonb check (jsonb_typeof(mapping) = 'object'),
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (hotel_id, template)
);

create unique index if not exists uq_accounting_export_profile_default
  on public.accounting_export_profiles (hotel_id)
  where is_default and is_active;

insert into public.accounting_export_profiles (hotel_id, profile_name, template, is_default)
select h.id, seed.profile_name, seed.template, seed.is_default
from public.hotels h
cross join (values
  ('StayQR Standard','stayqr',true),
  ('Tally Import','tally',false),
  ('Zoho Books','zoho_books',false),
  ('QuickBooks','quickbooks',false)
) as seed(profile_name, template, is_default)
on conflict (hotel_id, template) do nothing;

-- Future-hotel bootstrap: keep v1.1 revenue foundations repeatable for every
-- hotel created after this migration. Direct booking remains disabled.
create or replace function private.v11_seed_revenue_foundations_after_hotel_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  insert into public.public_booking_settings (hotel_id, enabled)
  values (new.id, false)
  on conflict (hotel_id) do nothing;

  insert into public.accounting_export_profiles (
    hotel_id, profile_name, template, is_default
  )
  values
    (new.id, 'StayQR Standard', 'stayqr', true),
    (new.id, 'Tally Import', 'tally', false),
    (new.id, 'Zoho Books', 'zoho_books', false),
    (new.id, 'QuickBooks', 'quickbooks', false)
  on conflict (hotel_id, template) do nothing;

  return new;
end;
$function$;

revoke all on function private.v11_seed_revenue_foundations_after_hotel_insert()
from public, anon, authenticated;

drop trigger if exists trg_v11_seed_revenue_foundations_after_hotel_insert
on public.hotels;

create trigger trg_v11_seed_revenue_foundations_after_hotel_insert
after insert on public.hotels
for each row
execute function private.v11_seed_revenue_foundations_after_hotel_insert();

-- --------------------------------------------------------------------------
-- 7. RLS: direct table reads only to authenticated hotel users.
--    Writes are intentionally RPC-only.
-- --------------------------------------------------------------------------
alter table public.public_booking_settings enable row level security;
alter table public.corporate_accounts enable row level security;
alter table public.corporate_rates enable row level security;
alter table public.reservation_corporate_links enable row level security;
alter table public.public_booking_requests enable row level security;
alter table public.stay_move_plans enable row level security;
alter table public.folio_split_shares enable row level security;
alter table public.accounting_export_profiles enable row level security;

drop policy if exists stayqr_v11_public_booking_settings_select on public.public_booking_settings;
create policy stayqr_v11_public_booking_settings_select
on public.public_booking_settings for select to authenticated
using (private.user_has_any_permission(hotel_id, array['hotel.manage','reservations.view','reservations.manage']::text[]));

drop policy if exists stayqr_v11_corporate_accounts_select on public.corporate_accounts;
create policy stayqr_v11_corporate_accounts_select
on public.corporate_accounts for select to authenticated
using (private.user_has_any_permission(hotel_id, array['reservations.view','reservations.manage','reports.view']::text[]));

drop policy if exists stayqr_v11_corporate_rates_select on public.corporate_rates;
create policy stayqr_v11_corporate_rates_select
on public.corporate_rates for select to authenticated
using (private.user_has_any_permission(hotel_id, array['reservations.view','reservations.manage','reports.view']::text[]));

drop policy if exists stayqr_v11_reservation_corporate_links_select on public.reservation_corporate_links;
create policy stayqr_v11_reservation_corporate_links_select
on public.reservation_corporate_links for select to authenticated
using (private.user_has_any_permission(hotel_id, array['reservations.view','reservations.manage','reports.view']::text[]));

drop policy if exists stayqr_v11_public_booking_requests_select on public.public_booking_requests;
create policy stayqr_v11_public_booking_requests_select
on public.public_booking_requests for select to authenticated
using (private.user_has_any_permission(hotel_id, array['reservations.view','reservations.manage']::text[]));

drop policy if exists stayqr_v11_stay_move_plans_select on public.stay_move_plans;
create policy stayqr_v11_stay_move_plans_select
on public.stay_move_plans for select to authenticated
using (private.user_has_any_permission(hotel_id, array['reservations.view','reservations.manage','checkin.manage']::text[]));

drop policy if exists stayqr_v11_folio_split_shares_select on public.folio_split_shares;
create policy stayqr_v11_folio_split_shares_select
on public.folio_split_shares for select to authenticated
using (private.user_has_any_permission(hotel_id, array['payments.view','payments.manage','invoices.view','invoices.manage']::text[]));

drop policy if exists stayqr_v11_accounting_export_profiles_select on public.accounting_export_profiles;
create policy stayqr_v11_accounting_export_profiles_select
on public.accounting_export_profiles for select to authenticated
using (private.user_has_any_permission(hotel_id, array['payments.view','payments.manage','invoices.view','invoices.manage','reports.view']::text[]));

-- --------------------------------------------------------------------------
-- 8. Private helpers
-- --------------------------------------------------------------------------
create or replace function private.v11_assert_revenue_manage(p_hotel_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := auth.uid();
begin
  if v_actor is null then
    raise exception 'Authenticated staff session required.';
  end if;
  if not private.user_has_any_permission(
    p_hotel_id,
    array['reservations.manage','hotel.manage','payments.manage','invoices.manage']::text[]
  ) then
    raise exception 'Revenue growth management access denied.';
  end if;
  return v_actor;
end;
$function$;

create or replace function private.v11_public_rate_quote(
  p_hotel_id uuid,
  p_room_type_id uuid,
  p_rate_plan_id uuid,
  p_corporate_rate_id uuid,
  p_arrival_date date,
  p_departure_date date,
  p_adults integer,
  p_children integer
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_room_type public.room_types%rowtype;
  v_plan public.rate_plans%rowtype;
  v_corporate public.corporate_rates%rowtype;
  v_nights integer;
  v_extra_adults integer;
  v_total numeric(14,2) := 0;
  v_breakdown jsonb := '[]'::jsonb;
  v_row record;
  v_effective numeric(14,2);
  v_nightly numeric(14,2);
  v_extra_adult numeric(14,2);
  v_extra_child numeric(14,2);
begin
  select * into v_room_type
  from public.room_types
  where id = p_room_type_id and hotel_id = p_hotel_id and is_active;
  if not found then raise exception 'Active room type not found.'; end if;

  select * into v_plan
  from public.rate_plans
  where id = p_rate_plan_id and hotel_id = p_hotel_id
    and room_type_id = p_room_type_id and is_active;
  if not found then raise exception 'Active rate plan not found.'; end if;

  v_nights := p_departure_date - p_arrival_date;
  if v_nights < 1 or v_nights > 365 then raise exception 'Stay length is invalid.'; end if;
  if p_adults < 1 or p_children < 0
     or p_adults > v_room_type.max_adults
     or p_children > v_room_type.max_children
     or p_adults + p_children > v_room_type.max_occupancy
  then
    raise exception 'Guest count exceeds room capacity.';
  end if;

  v_extra_adults := greatest(p_adults - v_room_type.base_occupancy, 0);

  if p_corporate_rate_id is not null then
    select * into v_corporate
    from public.corporate_rates cr
    where cr.id = p_corporate_rate_id
      and cr.hotel_id = p_hotel_id
      and cr.room_type_id = p_room_type_id
      and cr.rate_plan_id = p_rate_plan_id
      and cr.is_active
      and p_arrival_date >= cr.valid_from
      and (cr.valid_to is null or p_departure_date - 1 <= cr.valid_to)
      and v_nights >= cr.minimum_stay
      and (cr.maximum_stay is null or v_nights <= cr.maximum_stay);
    if not found then raise exception 'Corporate rate is not valid for this stay.'; end if;
  end if;

  for v_row in
    select d::date as stay_date,
      sr.id as seasonal_rate_id,
      sr.nightly_rate as seasonal_nightly_rate,
      sr.extra_adult_rate as seasonal_extra_adult_rate,
      sr.extra_child_rate as seasonal_extra_child_rate
    from generate_series(p_arrival_date, p_departure_date - 1, interval '1 day') d
    left join lateral (
      select s.* from public.seasonal_rates s
      where s.hotel_id = p_hotel_id
        and s.rate_plan_id = p_rate_plan_id
        and s.is_active
        and d::date >= s.start_date
        and d::date < s.end_date
        and (s.days_of_week is null or extract(dow from d)::smallint = any(s.days_of_week))
      order by s.priority asc, s.created_at desc
      limit 1
    ) sr on true
    order by d
  loop
    if p_corporate_rate_id is not null then
      v_nightly := v_corporate.negotiated_rate;
      v_extra_adult := coalesce(v_corporate.extra_adult_rate, v_plan.extra_adult_rate);
      v_extra_child := coalesce(v_corporate.extra_child_rate, v_plan.extra_child_rate);
    else
      v_nightly := coalesce(v_row.seasonal_nightly_rate, v_plan.base_rate);
      v_extra_adult := coalesce(v_row.seasonal_extra_adult_rate, v_plan.extra_adult_rate);
      v_extra_child := coalesce(v_row.seasonal_extra_child_rate, v_plan.extra_child_rate);
    end if;

    v_effective := round(
      v_nightly + (v_extra_adult * v_extra_adults) + (v_extra_child * p_children),
      2
    );
    v_total := v_total + v_effective;
    v_breakdown := v_breakdown || jsonb_build_array(jsonb_build_object(
      'stay_date', v_row.stay_date,
      'nightly_rate', v_nightly,
      'extra_adult_rate', v_extra_adult,
      'extra_child_rate', v_extra_child,
      'effective_nightly_rate', v_effective,
      'rate_source', case when p_corporate_rate_id is not null then 'corporate' when v_row.seasonal_rate_id is not null then 'seasonal' else 'base' end
    ));
  end loop;

  return jsonb_build_object(
    'hotel_id', p_hotel_id,
    'room_type_id', p_room_type_id,
    'room_type_name', v_room_type.name,
    'rate_plan_id', p_rate_plan_id,
    'rate_plan_name', v_plan.name,
    'currency_code', v_plan.currency_code,
    'nights', v_nights,
    'adults', p_adults,
    'children', p_children,
    'average_nightly_rate', round(v_total / v_nights, 2),
    'room_subtotal', round(v_total, 2),
    'tax_amount', 0,
    'discount_amount', 0,
    'total_amount', round(v_total, 2),
    'corporate_rate_id', p_corporate_rate_id,
    'corporate_rate_applied', p_corporate_rate_id is not null,
    'nightly_breakdown', v_breakdown
  );
end;
$function$;

-- --------------------------------------------------------------------------
-- 9. Public booking RPCs
-- --------------------------------------------------------------------------
create or replace function public.get_public_booking_hotel(p_hotel_slug text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_result jsonb;
begin
  select jsonb_build_object(
    'hotel_slug', h.slug,
    'hotel_name', h.hotel_name,
    'city', h.city,
    'state', h.state,
    'logo_url', h.logo_url,
    'currency_code', h.currency_code,
    'timezone', h.timezone,
    'enabled', s.enabled,
    'confirmation_mode', s.confirmation_mode,
    'minimum_stay', s.minimum_stay,
    'maximum_stay', s.maximum_stay,
    'maximum_advance_days', s.maximum_advance_days,
    'deposit_percent', s.deposit_percent,
    'booking_message', s.booking_message
  ) into v_result
  from public.hotels h
  join public.public_booking_settings s on s.hotel_id = h.id
  where h.slug = lower(trim(p_hotel_slug))
    and h.status = 'active'
    and h.subscription_status in ('trial','trialing','active');

  if v_result is null then raise exception 'Hotel booking page was not found.'; end if;
  return v_result;
end;
$function$;

create or replace function public.get_public_booking_options(
  p_hotel_slug text,
  p_arrival_date date,
  p_departure_date date,
  p_adults integer default 1,
  p_children integer default 0,
  p_corporate_code text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_hotel public.hotels%rowtype;
  v_settings public.public_booking_settings%rowtype;
  v_corporate public.corporate_accounts%rowtype;
  v_today date;
  v_nights integer;
  v_items jsonb := '[]'::jsonb;
  v_rt record;
  v_rate_id uuid;
  v_quote jsonb;
  v_available bigint;
begin
  select h.* into v_hotel from public.hotels h
  where h.slug = lower(trim(p_hotel_slug))
    and h.status = 'active'
    and h.subscription_status in ('trial','trialing','active');
  if not found then raise exception 'Hotel booking page was not found.'; end if;

  select * into v_settings from public.public_booking_settings where hotel_id = v_hotel.id;
  if not found or not v_settings.enabled then raise exception 'Direct booking is not enabled for this hotel.'; end if;

  v_today := (now() at time zone v_hotel.timezone)::date;
  v_nights := p_departure_date - p_arrival_date;
  if p_arrival_date < v_today then raise exception 'Arrival date cannot be in the past.'; end if;
  if p_arrival_date > v_today + v_settings.maximum_advance_days then raise exception 'Arrival date is outside the booking window.'; end if;
  if v_nights < v_settings.minimum_stay or v_nights > v_settings.maximum_stay then raise exception 'Stay length is outside the hotel booking rules.'; end if;
  if p_adults < 1 or p_children < 0 or p_adults + p_children > 20 then raise exception 'Guest count is invalid.'; end if;

  if nullif(trim(p_corporate_code),'') is not null then
    select * into v_corporate from public.corporate_accounts ca
    where ca.hotel_id = v_hotel.id
      and lower(ca.booking_code) = lower(trim(p_corporate_code))
      and ca.status = 'active';
    if not found then raise exception 'Corporate booking code is invalid.'; end if;
  end if;

  for v_rt in
    select rt.*, rp.id as rate_plan_id, rp.name as rate_plan_name,
      rp.is_refundable, rp.cancellation_policy
    from public.room_types rt
    join lateral (
      select p.* from public.rate_plans p
      where p.hotel_id = rt.hotel_id and p.room_type_id = rt.id and p.is_active
      order by p.priority, p.created_at
      limit 1
    ) rp on true
    where rt.hotel_id = v_hotel.id and rt.is_active
      and p_adults <= rt.max_adults
      and p_children <= rt.max_children
      and p_adults + p_children <= rt.max_occupancy
    order by rt.sort_order, rt.name
  loop
    select count(*) into v_available
    from public.rooms r
    where r.hotel_id = v_hotel.id
      and r.room_type_id = v_rt.id
      and r.is_active
      and r.status not in ('maintenance','out_of_order')
      and not (r.status = 'cleaning' and p_arrival_date <= v_today)
      and exists (select 1 from public.floors f where f.id = r.floor_id and f.hotel_id = r.hotel_id and f.is_active)
      and not exists (
        select 1 from public.room_inventory_allocations a
        where a.hotel_id = r.hotel_id and a.room_id = r.id and a.status = 'active'
          and a.stay_dates && daterange(p_arrival_date,p_departure_date,'[)')
      );

    if v_available > 0 then
      v_rate_id := null;
      if v_corporate.id is not null then
        select cr.id into v_rate_id
        from public.corporate_rates cr
        where cr.hotel_id = v_hotel.id
          and cr.corporate_account_id = v_corporate.id
          and cr.room_type_id = v_rt.id
          and cr.rate_plan_id = v_rt.rate_plan_id
          and cr.is_active
          and p_arrival_date >= cr.valid_from
          and (cr.valid_to is null or p_departure_date - 1 <= cr.valid_to)
          and v_nights >= cr.minimum_stay
          and (cr.maximum_stay is null or v_nights <= cr.maximum_stay)
        order by cr.valid_from desc, cr.created_at desc
        limit 1;

        -- Corporate links show only rooms that actually have a valid negotiated
        -- rate. Falling back silently to BAR would break the commercial contract.
        if v_rate_id is null then
          continue;
        end if;
      end if;

      v_quote := private.v11_public_rate_quote(
        v_hotel.id, v_rt.id, v_rt.rate_plan_id, v_rate_id,
        p_arrival_date, p_departure_date, p_adults, p_children
      );

      v_items := v_items || jsonb_build_array(jsonb_build_object(
        'room_type_id', v_rt.id,
        'room_type_name', v_rt.name,
        'description', v_rt.description,
        'max_adults', v_rt.max_adults,
        'max_children', v_rt.max_children,
        'max_occupancy', v_rt.max_occupancy,
        'available_rooms', v_available,
        'rate_plan_id', v_rt.rate_plan_id,
        'rate_plan_name', v_rt.rate_plan_name,
        'is_refundable', v_rt.is_refundable,
        'cancellation_policy', v_rt.cancellation_policy,
        'quote', v_quote,
        'deposit_required', round(((v_quote->>'total_amount')::numeric * v_settings.deposit_percent / 100),2)
      ));
    end if;
  end loop;

  return jsonb_build_object(
    'hotel_slug', v_hotel.slug,
    'hotel_name', v_hotel.hotel_name,
    'arrival_date', p_arrival_date,
    'departure_date', p_departure_date,
    'adults', p_adults,
    'children', p_children,
    'corporate_rate_applied', v_corporate.id is not null,
    'items', v_items
  );
end;
$function$;

create or replace function public.create_public_booking(
  p_hotel_slug text,
  p_request_id text,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_hotel public.hotels%rowtype;
  v_settings public.public_booking_settings%rowtype;
  v_existing public.public_booking_requests%rowtype;
  v_existing_res public.reservations%rowtype;
  v_request_key text := nullif(trim(p_request_id),'');
  v_request_hash text := md5(coalesce(p_payload,'{}'::jsonb)::text);
  v_arrival date;
  v_departure date;
  v_adults integer;
  v_children integer;
  v_room_type_id uuid;
  v_rate_plan_id uuid;
  v_room public.rooms%rowtype;
  v_corporate public.corporate_accounts%rowtype;
  v_corporate_rate public.corporate_rates%rowtype;
  v_quote jsonb;
  v_guest_id uuid;
  v_reservation_id uuid;
  v_reservation_room_id uuid;
  v_number text;
  v_status text;
  v_nights integer;
  v_deposit numeric(12,2);
  v_today date;
begin
  if v_request_key is null or length(v_request_key) < 8 or length(v_request_key) > 160 then
    raise exception 'A valid booking request id is required.';
  end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then raise exception 'Booking payload is required.'; end if;
  if length(coalesce(p_payload->>'website','')) > 0 then raise exception 'Booking request was rejected.'; end if;

  select h.* into v_hotel from public.hotels h
  where h.slug = lower(trim(p_hotel_slug))
    and h.status = 'active'
    and h.subscription_status in ('trial','trialing','active');
  if not found then raise exception 'Hotel booking page was not found.'; end if;

  select * into v_settings from public.public_booking_settings where hotel_id = v_hotel.id;
  if not found or not v_settings.enabled then raise exception 'Direct booking is not enabled for this hotel.'; end if;

  perform pg_advisory_xact_lock(hashtextextended('stayqr:public-booking:'||v_hotel.id::text||':'||v_request_key,0));

  select * into v_existing from public.public_booking_requests
  where hotel_id = v_hotel.id and request_key = v_request_key;
  if found then
    if v_existing.request_hash <> v_request_hash then raise exception 'Booking request id was reused with different details.'; end if;
    select * into v_existing_res from public.reservations where id = v_existing.reservation_id and hotel_id = v_hotel.id;
    return jsonb_build_object(
      'ok', true, 'idempotent', true,
      'reservation_id', v_existing_res.id,
      'reservation_number', v_existing_res.reservation_number,
      'status', v_existing_res.status,
      'arrival_date', v_existing_res.arrival_date,
      'departure_date', v_existing_res.departure_date,
      'total_amount', v_existing_res.total_amount,
      'deposit_required', v_existing_res.deposit_required,
      'currency_code', v_existing_res.currency_code,
      'hotel_name', v_hotel.hotel_name,
      'corporate_rate_applied', exists(
        select 1 from public.reservation_corporate_links l
        where l.hotel_id = v_hotel.id and l.reservation_id = v_existing_res.id
      )
    );
  end if;

  v_arrival := nullif(p_payload->>'arrival_date','')::date;
  v_departure := nullif(p_payload->>'departure_date','')::date;
  v_adults := coalesce(nullif(p_payload->>'adults','')::integer,1);
  v_children := coalesce(nullif(p_payload->>'children','')::integer,0);
  v_room_type_id := nullif(p_payload->>'room_type_id','')::uuid;
  v_rate_plan_id := nullif(p_payload->>'rate_plan_id','')::uuid;
  v_nights := v_departure - v_arrival;
  v_today := (now() at time zone v_hotel.timezone)::date;

  if v_arrival is null or v_departure is null or v_departure <= v_arrival then raise exception 'Departure date must be after arrival date.'; end if;
  if v_arrival < v_today or v_arrival > v_today + v_settings.maximum_advance_days then raise exception 'Arrival date is outside the booking window.'; end if;
  if v_nights < v_settings.minimum_stay or v_nights > v_settings.maximum_stay then raise exception 'Stay length is outside the hotel booking rules.'; end if;
  if v_room_type_id is null or v_rate_plan_id is null then raise exception 'Room type and rate plan are required.'; end if;
  if nullif(trim(p_payload#>>'{guest,full_name}'),'') is null then raise exception 'Guest full name is required.'; end if;
  if nullif(trim(p_payload#>>'{guest,phone}'),'') is null and nullif(trim(p_payload#>>'{guest,email}'),'') is null then raise exception 'Phone or email is required.'; end if;

  if nullif(trim(p_payload->>'corporate_code'),'') is not null then
    select * into v_corporate from public.corporate_accounts ca
    where ca.hotel_id = v_hotel.id
      and lower(ca.booking_code) = lower(trim(p_payload->>'corporate_code'))
      and ca.status = 'active';
    if not found then raise exception 'Corporate booking code is invalid.'; end if;

    select * into v_corporate_rate from public.corporate_rates cr
    where cr.hotel_id = v_hotel.id
      and cr.corporate_account_id = v_corporate.id
      and cr.room_type_id = v_room_type_id
      and cr.rate_plan_id = v_rate_plan_id
      and cr.is_active
      and v_arrival >= cr.valid_from
      and (cr.valid_to is null or v_departure - 1 <= cr.valid_to)
      and v_nights >= cr.minimum_stay
      and (cr.maximum_stay is null or v_nights <= cr.maximum_stay)
    order by cr.valid_from desc, cr.created_at desc
    limit 1;
    if not found then raise exception 'No negotiated corporate rate is valid for the selected room and dates.'; end if;
  end if;

  v_quote := private.v11_public_rate_quote(
    v_hotel.id, v_room_type_id, v_rate_plan_id, v_corporate_rate.id,
    v_arrival, v_departure, v_adults, v_children
  );

  select r.* into v_room
  from public.rooms r
  where r.hotel_id = v_hotel.id
    and r.room_type_id = v_room_type_id
    and r.is_active
    and r.status not in ('maintenance','out_of_order')
    and not (r.status='cleaning' and v_arrival <= v_today)
    and exists (select 1 from public.floors f where f.id=r.floor_id and f.hotel_id=r.hotel_id and f.is_active)
    and not exists (
      select 1 from public.room_inventory_allocations a
      where a.hotel_id=r.hotel_id and a.room_id=r.id and a.status='active'
        and a.stay_dates && daterange(v_arrival,v_departure,'[)')
    )
  order by nullif(regexp_replace(r.room_number,'[^0-9]','','g'),'')::int nulls last, r.room_number
  for update skip locked
  limit 1;
  if not found then raise exception 'No room is available for the selected dates.'; end if;

  v_guest_id := private.resolve_reservation_guest(
    v_hotel.id,
    jsonb_build_object(
      'full_name', trim(p_payload#>>'{guest,full_name}'),
      'phone', nullif(trim(p_payload#>>'{guest,phone}'),''),
      'email', nullif(lower(trim(p_payload#>>'{guest,email}')),''),
      'preferred_language', coalesce(nullif(trim(p_payload#>>'{guest,preferred_language}'),''),'english')
    )
  );

  v_number := private.next_reservation_number(v_hotel.id, v_arrival);
  v_status := case when v_settings.confirmation_mode='instant' then 'confirmed' else 'tentative' end;
  v_deposit := round(((v_quote->>'total_amount')::numeric * v_settings.deposit_percent / 100),2);

  insert into public.reservations (
    hotel_id,reservation_number,primary_guest_id,status,booking_source,source_reference,
    arrival_date,departure_date,adults,children,currency_code,room_subtotal,tax_amount,
    discount_amount,total_amount,deposit_required,deposit_collected,special_requests,
    internal_notes,created_by,updated_by
  ) values (
    v_hotel.id,v_number,v_guest_id,v_status,'website','DIRECT:'||v_request_key,
    v_arrival,v_departure,v_adults,v_children,v_hotel.currency_code,
    (v_quote->>'room_subtotal')::numeric,0,0,(v_quote->>'total_amount')::numeric,
    v_deposit,0,nullif(trim(p_payload->>'special_requests'),''),null,null,null
  ) returning id into v_reservation_id;

  insert into public.reservation_rooms (
    hotel_id,reservation_id,room_type_id,room_id,rate_plan_id,status,adults,children,
    nightly_rate,room_subtotal,tax_amount,discount_amount,total_amount,notes
  ) values (
    v_hotel.id,v_reservation_id,v_room_type_id,v_room.id,v_rate_plan_id,
    case when v_status='confirmed' then 'confirmed' else 'held' end,
    v_adults,v_children,(v_quote->>'average_nightly_rate')::numeric,
    (v_quote->>'room_subtotal')::numeric,0,0,(v_quote->>'total_amount')::numeric,null
  ) returning id into v_reservation_room_id;

  insert into public.reservation_guests (hotel_id,reservation_id,guest_id,is_primary)
  values (v_hotel.id,v_reservation_id,v_guest_id,true);

  if v_corporate.id is not null then
    insert into public.reservation_corporate_links (
      hotel_id,reservation_id,corporate_account_id,corporate_rate_id,booking_code,rate_snapshot
    ) values (
      v_hotel.id,v_reservation_id,v_corporate.id,v_corporate_rate.id,v_corporate.booking_code,v_quote
    );
  end if;

  insert into public.public_booking_requests (hotel_id,request_key,request_hash,reservation_id)
  values (v_hotel.id,v_request_key,v_request_hash,v_reservation_id);

  insert into public.activity_logs (
    hotel_id,actor_user_id,actor_role,action,entity_type,entity_id,description,metadata
  ) values (
    v_hotel.id,null,'guest','reservation.public_created','reservation',v_reservation_id,
    format('Direct website reservation %s created.',v_number),
    jsonb_build_object('request_id',v_request_key,'reservation_room_id',v_reservation_room_id,'corporate',v_corporate.id is not null)
  );

  return jsonb_build_object(
    'ok', true, 'idempotent', false,
    'reservation_id', v_reservation_id,
    'reservation_number', v_number,
    'status', v_status,
    'arrival_date', v_arrival,
    'departure_date', v_departure,
    'total_amount', (v_quote->>'total_amount')::numeric,
    'deposit_required', v_deposit,
    'currency_code', v_hotel.currency_code,
    'hotel_name', v_hotel.hotel_name,
    'corporate_rate_applied', v_corporate.id is not null
  );
end;
$function$;

-- --------------------------------------------------------------------------
-- 10. Internal Revenue Growth workspace + write RPCs
-- --------------------------------------------------------------------------
create or replace function public.get_v11_revenue_workspace(p_hotel_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  if not private.user_has_any_permission(
    p_hotel_id,
    array['reservations.view','reservations.manage','payments.view','payments.manage','invoices.view','reports.view','hotel.manage']::text[]
  ) then raise exception 'Revenue growth workspace access denied.'; end if;

  return jsonb_build_object(
    'settings', coalesce((select to_jsonb(s) from public.public_booking_settings s where s.hotel_id=p_hotel_id),'{}'::jsonb),
    'corporate_accounts', coalesce((select jsonb_agg(to_jsonb(c) order by c.name) from public.corporate_accounts c where c.hotel_id=p_hotel_id),'[]'::jsonb),
    'corporate_rates', coalesce((
      select jsonb_agg(to_jsonb(cr)||jsonb_build_object(
        'corporate_name',ca.name,'room_type_name',rt.name,'rate_plan_name',rp.name,'currency_code',rp.currency_code
      ) order by ca.name,rt.name,cr.valid_from desc)
      from public.corporate_rates cr
      join public.corporate_accounts ca on ca.id=cr.corporate_account_id and ca.hotel_id=cr.hotel_id
      join public.room_types rt on rt.id=cr.room_type_id and rt.hotel_id=cr.hotel_id
      join public.rate_plans rp on rp.id=cr.rate_plan_id and rp.hotel_id=cr.hotel_id
      where cr.hotel_id=p_hotel_id
    ),'[]'::jsonb),
    'room_types', coalesce((select jsonb_agg(to_jsonb(rt) order by rt.sort_order,rt.name) from public.room_types rt where rt.hotel_id=p_hotel_id and rt.is_active),'[]'::jsonb),
    'rate_plans', coalesce((select jsonb_agg(to_jsonb(rp) order by rp.priority,rp.name) from public.rate_plans rp where rp.hotel_id=p_hotel_id and rp.is_active),'[]'::jsonb),
    'rooms', coalesce((select jsonb_agg(to_jsonb(r) order by r.room_number) from public.rooms r where r.hotel_id=p_hotel_id and r.is_active),'[]'::jsonb),
    'active_stays', coalesce((
      select jsonb_agg(jsonb_build_object(
        'guest_session_id',gs.id,'reservation_id',gs.reservation_id,'guest_name',g.full_name,
        'room_id',gs.room_id,'room_number',r.room_number,'checkin_time',gs.checkin_time,
        'checkout_time',coalesce(gs.extended_until,gs.checkout_time)
      ) order by coalesce(gs.extended_until,gs.checkout_time))
      from public.guest_sessions gs
      join public.guests g on g.id=gs.guest_id and g.hotel_id=gs.hotel_id
      left join public.rooms r on r.id=gs.room_id and r.hotel_id=gs.hotel_id
      where gs.hotel_id=p_hotel_id and gs.status='active'
    ),'[]'::jsonb),
    'move_plans', coalesce((
      select jsonb_agg(to_jsonb(mp)||jsonb_build_object(
        'guest_name',g.full_name,'from_room_number',fr.room_number,'to_room_number',tr.room_number
      ) order by mp.planned_date,mp.created_at)
      from public.stay_move_plans mp
      join public.guest_sessions gs on gs.id=mp.guest_session_id and gs.hotel_id=mp.hotel_id
      join public.guests g on g.id=gs.guest_id and g.hotel_id=gs.hotel_id
      left join public.rooms fr on fr.id=mp.from_room_id and fr.hotel_id=mp.hotel_id
      left join public.rooms tr on tr.id=mp.to_room_id and tr.hotel_id=mp.hotel_id
      where mp.hotel_id=p_hotel_id
    ),'[]'::jsonb),
    'open_folios', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',f.id,'folio_number',f.folio_number,'guest_name',g.full_name,'room_number',r.room_number,
        'balance_amount',f.balance_amount,'currency_code',f.currency_code,'status',f.status
      ) order by f.updated_at desc)
      from public.folios f
      join public.guests g on g.id=f.guest_id and g.hotel_id=f.hotel_id
      left join public.rooms r on r.id=f.room_id and r.hotel_id=f.hotel_id
      where f.hotel_id=p_hotel_id and f.status='open' and f.balance_amount>0
    ),'[]'::jsonb),
    'split_shares', coalesce((select jsonb_agg(to_jsonb(s) order by s.folio_id,s.sort_order,s.created_at) from public.folio_split_shares s where s.hotel_id=p_hotel_id),'[]'::jsonb),
    'accounting_profiles', coalesce((select jsonb_agg(to_jsonb(p) order by p.is_default desc,p.profile_name) from public.accounting_export_profiles p where p.hotel_id=p_hotel_id and p.is_active),'[]'::jsonb),
    'accounting_exports', coalesce((
      select jsonb_agg(to_jsonb(e) order by e.generated_at desc)
      from (select * from public.accounting_exports where hotel_id=p_hotel_id order by generated_at desc limit 25) e
    ),'[]'::jsonb)
  );
end;
$function$;

create or replace function public.upsert_v11_public_booking_settings(p_hotel_id uuid,p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare v_actor uuid; v_row public.public_booking_settings%rowtype;
begin
  v_actor:=private.v11_assert_revenue_manage(p_hotel_id);
  insert into public.public_booking_settings (
    hotel_id,enabled,confirmation_mode,minimum_stay,maximum_stay,maximum_advance_days,
    deposit_percent,booking_message,updated_by,updated_at
  ) values (
    p_hotel_id,coalesce((p_payload->>'enabled')::boolean,false),
    coalesce(nullif(p_payload->>'confirmation_mode',''),'instant'),
    coalesce(nullif(p_payload->>'minimum_stay','')::integer,1),
    coalesce(nullif(p_payload->>'maximum_stay','')::integer,30),
    coalesce(nullif(p_payload->>'maximum_advance_days','')::integer,365),
    coalesce(nullif(p_payload->>'deposit_percent','')::numeric,0),
    nullif(trim(p_payload->>'booking_message'),''),v_actor,now()
  ) on conflict (hotel_id) do update set
    enabled=excluded.enabled,confirmation_mode=excluded.confirmation_mode,
    minimum_stay=excluded.minimum_stay,maximum_stay=excluded.maximum_stay,
    maximum_advance_days=excluded.maximum_advance_days,deposit_percent=excluded.deposit_percent,
    booking_message=excluded.booking_message,updated_by=v_actor,updated_at=now()
  returning * into v_row;
  return to_jsonb(v_row);
end;
$function$;

create or replace function public.upsert_v11_corporate_account(p_hotel_id uuid,p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare v_actor uuid; v_id uuid; v_row public.corporate_accounts%rowtype;
begin
  v_actor:=private.v11_assert_revenue_manage(p_hotel_id);
  v_id:=nullif(p_payload->>'id','')::uuid;
  if nullif(trim(p_payload->>'name'),'') is null then raise exception 'Corporate account name is required.'; end if;
  if nullif(trim(p_payload->>'code'),'') is null then raise exception 'Corporate code is required.'; end if;
  if nullif(trim(p_payload->>'booking_code'),'') is null then raise exception 'Corporate booking code is required.'; end if;

  if v_id is null then
    insert into public.corporate_accounts (
      hotel_id,name,code,booking_code,gstin,billing_email,billing_phone,billing_address,notes,status,created_by,updated_by
    ) values (
      p_hotel_id,trim(p_payload->>'name'),upper(trim(p_payload->>'code')),upper(trim(p_payload->>'booking_code')),
      nullif(upper(trim(p_payload->>'gstin')),''),nullif(lower(trim(p_payload->>'billing_email')),''),
      nullif(trim(p_payload->>'billing_phone'),''),nullif(trim(p_payload->>'billing_address'),''),
      nullif(trim(p_payload->>'notes'),''),coalesce(nullif(p_payload->>'status',''),'active'),v_actor,v_actor
    ) returning * into v_row;
  else
    update public.corporate_accounts set
      name=trim(p_payload->>'name'),code=upper(trim(p_payload->>'code')),booking_code=upper(trim(p_payload->>'booking_code')),
      gstin=nullif(upper(trim(p_payload->>'gstin')),''),billing_email=nullif(lower(trim(p_payload->>'billing_email')),''),
      billing_phone=nullif(trim(p_payload->>'billing_phone'),''),billing_address=nullif(trim(p_payload->>'billing_address'),''),
      notes=nullif(trim(p_payload->>'notes'),''),status=coalesce(nullif(p_payload->>'status',''),'active'),
      updated_by=v_actor,updated_at=now()
    where id=v_id and hotel_id=p_hotel_id returning * into v_row;
    if not found then raise exception 'Corporate account was not found.'; end if;
  end if;
  return to_jsonb(v_row);
end;
$function$;

create or replace function public.upsert_v11_corporate_rate(p_hotel_id uuid,p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare v_actor uuid; v_id uuid; v_account uuid; v_rt uuid; v_rp uuid; v_row public.corporate_rates%rowtype;
begin
  v_actor:=private.v11_assert_revenue_manage(p_hotel_id);
  v_id:=nullif(p_payload->>'id','')::uuid;
  v_account:=nullif(p_payload->>'corporate_account_id','')::uuid;
  v_rt:=nullif(p_payload->>'room_type_id','')::uuid;
  v_rp:=nullif(p_payload->>'rate_plan_id','')::uuid;
  if v_account is null or v_rt is null or v_rp is null then raise exception 'Corporate account, room type and rate plan are required.'; end if;
  if not exists(select 1 from public.corporate_accounts where id=v_account and hotel_id=p_hotel_id) then raise exception 'Corporate account does not belong to this hotel.'; end if;
  if not exists(select 1 from public.rate_plans where id=v_rp and hotel_id=p_hotel_id and room_type_id=v_rt) then raise exception 'Rate plan does not belong to the selected room type.'; end if;

  if v_id is null then
    insert into public.corporate_rates (
      hotel_id,corporate_account_id,room_type_id,rate_plan_id,negotiated_rate,extra_adult_rate,extra_child_rate,
      minimum_stay,maximum_stay,valid_from,valid_to,is_active,created_by,updated_by
    ) values (
      p_hotel_id,v_account,v_rt,v_rp,(p_payload->>'negotiated_rate')::numeric,
      nullif(p_payload->>'extra_adult_rate','')::numeric,nullif(p_payload->>'extra_child_rate','')::numeric,
      coalesce(nullif(p_payload->>'minimum_stay','')::integer,1),nullif(p_payload->>'maximum_stay','')::integer,
      coalesce(nullif(p_payload->>'valid_from','')::date,current_date),nullif(p_payload->>'valid_to','')::date,
      coalesce((p_payload->>'is_active')::boolean,true),v_actor,v_actor
    ) returning * into v_row;
  else
    update public.corporate_rates set
      corporate_account_id=v_account,room_type_id=v_rt,rate_plan_id=v_rp,
      negotiated_rate=(p_payload->>'negotiated_rate')::numeric,
      extra_adult_rate=nullif(p_payload->>'extra_adult_rate','')::numeric,
      extra_child_rate=nullif(p_payload->>'extra_child_rate','')::numeric,
      minimum_stay=coalesce(nullif(p_payload->>'minimum_stay','')::integer,1),
      maximum_stay=nullif(p_payload->>'maximum_stay','')::integer,
      valid_from=coalesce(nullif(p_payload->>'valid_from','')::date,current_date),
      valid_to=nullif(p_payload->>'valid_to','')::date,
      is_active=coalesce((p_payload->>'is_active')::boolean,true),updated_by=v_actor,updated_at=now()
    where id=v_id and hotel_id=p_hotel_id returning * into v_row;
    if not found then raise exception 'Corporate rate was not found.'; end if;
  end if;
  return to_jsonb(v_row);
end;
$function$;

create or replace function public.create_v11_stay_move_plan(
  p_hotel_id uuid,p_guest_session_id uuid,p_to_room_id uuid,p_planned_date date,p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare v_actor uuid; v_session public.guest_sessions%rowtype; v_hotel public.hotels%rowtype; v_plan public.stay_move_plans%rowtype; v_start date; v_end date;
begin
  v_actor:=private.v11_assert_revenue_manage(p_hotel_id);
  select * into v_session from public.guest_sessions where id=p_guest_session_id and hotel_id=p_hotel_id and status='active';
  if not found or v_session.room_id is null then raise exception 'Active stay was not found.'; end if;
  select * into v_hotel from public.hotels where id=p_hotel_id;
  v_start:=(v_session.checkin_time at time zone v_hotel.timezone)::date;
  v_end:=(coalesce(v_session.extended_until,v_session.checkout_time) at time zone v_hotel.timezone)::date;
  if p_planned_date < v_start or p_planned_date >= v_end then raise exception 'Planned move date must fall inside the active stay.'; end if;
  if p_to_room_id=v_session.room_id then raise exception 'Target room must differ from the current room.'; end if;
  if not exists(select 1 from public.rooms where id=p_to_room_id and hotel_id=p_hotel_id and is_active and status not in ('maintenance','out_of_order')) then raise exception 'Target room is not available for planning.'; end if;
  if exists(
    select 1 from public.room_inventory_allocations a
    where a.hotel_id=p_hotel_id and a.room_id=p_to_room_id and a.status='active'
      and a.stay_dates && daterange(p_planned_date,p_planned_date+1,'[)')
      and coalesce(a.guest_session_id,'00000000-0000-0000-0000-000000000000'::uuid)<>p_guest_session_id
  ) then raise exception 'Target room already has a commitment on the planned date.'; end if;

  insert into public.stay_move_plans (
    hotel_id,guest_session_id,reservation_id,from_room_id,to_room_id,planned_date,notes,created_by
  ) values (p_hotel_id,p_guest_session_id,v_session.reservation_id,v_session.room_id,p_to_room_id,p_planned_date,nullif(trim(p_notes),''),v_actor)
  returning * into v_plan;
  return to_jsonb(v_plan);
end;
$function$;

create or replace function public.cancel_v11_stay_move_plan(p_hotel_id uuid,p_plan_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare v_actor uuid; v_row public.stay_move_plans%rowtype;
begin
  v_actor:=private.v11_assert_revenue_manage(p_hotel_id);
  update public.stay_move_plans set status='cancelled',cancelled_at=now(),cancelled_by=v_actor,updated_at=now()
  where id=p_plan_id and hotel_id=p_hotel_id and status='planned' returning * into v_row;
  if not found then raise exception 'Planned move was not found or is already closed.'; end if;
  return to_jsonb(v_row);
end;
$function$;

create or replace function public.verify_v11_stay_move_plan(p_hotel_id uuid,p_plan_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare v_actor uuid; v_plan public.stay_move_plans%rowtype; v_session public.guest_sessions%rowtype;
begin
  v_actor:=private.v11_assert_revenue_manage(p_hotel_id);
  select * into v_plan from public.stay_move_plans where id=p_plan_id and hotel_id=p_hotel_id and status='planned' for update;
  if not found then raise exception 'Planned move was not found or is already closed.'; end if;
  select * into v_session from public.guest_sessions where id=v_plan.guest_session_id and hotel_id=p_hotel_id;
  if not found then raise exception 'Stay was not found.'; end if;
  if v_session.room_id<>v_plan.to_room_id then raise exception 'Execute the authoritative room move first; the stay is not in the planned target room yet.'; end if;
  update public.stay_move_plans set status='verified',verified_at=now(),verified_by=v_actor,updated_at=now()
  where id=v_plan.id returning * into v_plan;
  return to_jsonb(v_plan);
end;
$function$;

create or replace function public.replace_v11_folio_split_plan(p_hotel_id uuid,p_folio_id uuid,p_shares jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare v_actor uuid; v_folio public.folios%rowtype; v_count int; v_total numeric(14,2):=0; v_item record; v_amount numeric(14,2); v_label text; v_sort int:=0;
begin
  v_actor:=private.v11_assert_revenue_manage(p_hotel_id);
  if jsonb_typeof(p_shares)<>'array' then raise exception 'Split plan must be an array.'; end if;
  v_count:=jsonb_array_length(p_shares);
  if v_count<2 or v_count>10 then raise exception 'Split bill requires between 2 and 10 payer shares.'; end if;

  select * into v_folio from public.folios where id=p_folio_id and hotel_id=p_hotel_id for update;
  if not found or v_folio.status<>'open' or v_folio.balance_amount<=0 then raise exception 'An open folio with positive balance is required.'; end if;
  if exists(select 1 from public.folio_split_shares where hotel_id=p_hotel_id and folio_id=p_folio_id and paid_amount>0) then raise exception 'A split plan with posted payer collections cannot be replaced.'; end if;

  for v_item in select value from jsonb_array_elements(p_shares)
  loop
    v_label:=nullif(trim(v_item.value->>'payer_label'),'');
    v_amount:=nullif(v_item.value->>'allocated_amount','')::numeric;
    if v_label is null or v_amount is null or v_amount<=0 then raise exception 'Each payer share needs a label and positive amount.'; end if;
    v_total:=v_total+v_amount;
  end loop;
  if round(v_total,2)<>round(v_folio.balance_amount,2) then raise exception 'Split plan total % must equal current folio balance %.',round(v_total,2),v_folio.balance_amount; end if;

  delete from public.folio_split_shares where hotel_id=p_hotel_id and folio_id=p_folio_id;
  for v_item in select value from jsonb_array_elements(p_shares)
  loop
    v_sort:=v_sort+1;
    insert into public.folio_split_shares (hotel_id,folio_id,payer_label,allocated_amount,paid_amount,status,sort_order,created_by)
    values (p_hotel_id,p_folio_id,trim(v_item.value->>'payer_label'),(v_item.value->>'allocated_amount')::numeric,0,'open',v_sort,v_actor);
  end loop;

  return jsonb_build_object('ok',true,'folio_id',p_folio_id,'balance_amount',v_folio.balance_amount,'shares',(
    select jsonb_agg(to_jsonb(s) order by s.sort_order) from public.folio_split_shares s where s.hotel_id=p_hotel_id and s.folio_id=p_folio_id
  ));
end;
$function$;

create or replace function public.post_v11_split_share_collection(
  p_hotel_id uuid,p_share_id uuid,p_amount numeric,p_payment_method text,
  p_transaction_reference text default null,p_request_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare v_actor uuid; v_share public.folio_split_shares%rowtype; v_folio public.folios%rowtype; v_amount numeric(14,2); v_request text; v_result jsonb; v_new_paid numeric(14,2);
begin
  v_actor:=private.v11_assert_revenue_manage(p_hotel_id);
  v_amount:=round(p_amount,2);
  if v_amount<=0 then raise exception 'Collection amount must be positive.'; end if;
  v_request:=coalesce(nullif(trim(p_request_id),''),gen_random_uuid()::text);

  select * into v_share from public.folio_split_shares where id=p_share_id and hotel_id=p_hotel_id for update;
  if not found then raise exception 'Split-bill payer share was not found.'; end if;
  if v_share.status='settled' then raise exception 'This payer share is already settled.'; end if;
  if v_amount>v_share.allocated_amount-v_share.paid_amount then raise exception 'Collection exceeds payer share remaining amount.'; end if;

  select * into v_folio from public.folios where id=v_share.folio_id and hotel_id=p_hotel_id for update;
  if not found or v_folio.status<>'open' then raise exception 'Folio is not open.'; end if;
  if v_amount>v_folio.balance_amount then raise exception 'Collection exceeds folio balance.'; end if;

  v_result:=private.day11_post_collection(
    p_hotel_id,v_share.folio_id,v_amount,p_payment_method,gen_random_uuid(),
    nullif(trim(p_transaction_reference),''),null,null,null,'settlement_rpc',null,
    'v11-split-share:'||v_share.id::text||':'||v_request,now(),v_actor,
    jsonb_build_object('request_id',v_request,'posting_mode','v11_payer_split','v11_split_share_id',v_share.id,'payer_label',v_share.payer_label)
  );

  -- The authoritative Day 11 helper is idempotent. A network retry must not
  -- increment the payer share a second time when it returns the existing
  -- collection.
  if coalesce((v_result->>'idempotent')::boolean,false) then
    return v_result||jsonb_build_object(
      'split_share_id',v_share.id,
      'payer_label',v_share.payer_label,
      'share_paid_amount',v_share.paid_amount,
      'share_remaining',v_share.allocated_amount-v_share.paid_amount
    );
  end if;

  v_new_paid:=v_share.paid_amount+v_amount;
  update public.folio_split_shares set
    paid_amount=v_new_paid,
    status=case when v_new_paid=allocated_amount then 'settled' else 'open' end,
    updated_at=now()
  where id=v_share.id;

  return v_result||jsonb_build_object('split_share_id',v_share.id,'payer_label',v_share.payer_label,'share_paid_amount',v_new_paid,'share_remaining',v_share.allocated_amount-v_new_paid);
end;
$function$;

create or replace function public.upsert_v11_accounting_profile(p_hotel_id uuid,p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare v_actor uuid; v_template text; v_row public.accounting_export_profiles%rowtype;
begin
  v_actor:=private.v11_assert_revenue_manage(p_hotel_id);
  v_template:=lower(trim(p_payload->>'template'));
  if v_template not in ('stayqr','tally','zoho_books','quickbooks','generic') then raise exception 'Unsupported accounting template.'; end if;
  if coalesce((p_payload->>'is_default')::boolean,false) then
    update public.accounting_export_profiles set is_default=false,updated_by=v_actor,updated_at=now() where hotel_id=p_hotel_id and is_default;
  end if;
  insert into public.accounting_export_profiles (hotel_id,profile_name,template,is_default,is_active,mapping,created_by,updated_by)
  values (
    p_hotel_id,coalesce(nullif(trim(p_payload->>'profile_name'),''),initcap(replace(v_template,'_',' '))),v_template,
    coalesce((p_payload->>'is_default')::boolean,false),coalesce((p_payload->>'is_active')::boolean,true),
    coalesce(p_payload->'mapping','{}'::jsonb),v_actor,v_actor
  ) on conflict (hotel_id,template) do update set
    profile_name=excluded.profile_name,is_default=excluded.is_default,is_active=excluded.is_active,mapping=excluded.mapping,updated_by=v_actor,updated_at=now()
  returning * into v_row;
  return to_jsonb(v_row);
end;
$function$;

create or replace function public.generate_v11_accounting_export(
  p_hotel_id uuid,p_profile_id uuid,p_date_from date,p_date_to date,p_request_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid; v_profile public.accounting_export_profiles%rowtype; v_existing public.accounting_exports%rowtype;
  v_request text; v_csv text; v_rows integer; v_hash text; v_file text; v_template text;
begin
  v_actor:=private.v11_assert_revenue_manage(p_hotel_id);
  if p_date_from is null or p_date_to is null or p_date_to<p_date_from or p_date_to-p_date_from>366 then raise exception 'Accounting export date range is invalid.'; end if;
  select * into v_profile from public.accounting_export_profiles where id=p_profile_id and hotel_id=p_hotel_id and is_active;
  if not found then raise exception 'Accounting export profile was not found.'; end if;
  v_template:=v_profile.template;
  v_request:=coalesce(nullif(trim(p_request_id),''),'v11-accounting:'||gen_random_uuid()::text);
  select * into v_existing from public.accounting_exports where hotel_id=p_hotel_id and idempotency_key=v_request;
  if found then return to_jsonb(v_existing)||jsonb_build_object('ok',true,'idempotent',true); end if;

  if v_template in ('stayqr','generic') then
    select payload->>'csv_content',(payload->>'row_count')::integer,payload->>'content_hash'
    into v_csv,v_rows,v_hash
    from (select private.day12_build_accounting_csv(p_hotel_id,p_date_from,p_date_to) payload) q;
  elsif v_template='tally' then
    select
      'Date,Voucher Type,Voucher Number,Party Ledger,Amount,Reference'||E'\n'||coalesce(string_agg(
        private.day12_csv_escape(i.invoice_date::text)||','||private.day12_csv_escape('Sales')||','||
        private.day12_csv_escape(i.invoice_number)||','||private.day12_csv_escape(coalesce(g.full_name,'Guest'))||','||
        private.day12_csv_escape(i.total_amount::text)||','||private.day12_csv_escape(coalesce(i.buyer_gstin,'')),E'\n' order by i.invoice_date,i.invoice_number
      ),''),count(*)::integer
    into v_csv,v_rows
    from public.invoices i left join public.guests g on g.id=i.guest_id and g.hotel_id=i.hotel_id
    where i.hotel_id=p_hotel_id and i.invoice_date between p_date_from and p_date_to and i.invoice_status in ('issued','paid');
    v_hash:=private.day12_hash_text(v_csv);
  elsif v_template='zoho_books' then
    select
      'Invoice Number,Invoice Date,Customer Name,GSTIN,Total,Status'||E'\n'||coalesce(string_agg(
        private.day12_csv_escape(i.invoice_number)||','||private.day12_csv_escape(i.invoice_date::text)||','||
        private.day12_csv_escape(coalesce(g.full_name,'Guest'))||','||private.day12_csv_escape(coalesce(i.buyer_gstin,''))||','||
        private.day12_csv_escape(i.total_amount::text)||','||private.day12_csv_escape(i.invoice_status),E'\n' order by i.invoice_date,i.invoice_number
      ),''),count(*)::integer
    into v_csv,v_rows
    from public.invoices i left join public.guests g on g.id=i.guest_id and g.hotel_id=i.hotel_id
    where i.hotel_id=p_hotel_id and i.invoice_date between p_date_from and p_date_to and i.invoice_status in ('issued','paid');
    v_hash:=private.day12_hash_text(v_csv);
  else
    select
      'TxnDate,RefNumber,Name,Memo,Amount,PaymentStatus'||E'\n'||coalesce(string_agg(
        private.day12_csv_escape(i.invoice_date::text)||','||private.day12_csv_escape(i.invoice_number)||','||
        private.day12_csv_escape(coalesce(g.full_name,'Guest'))||','||private.day12_csv_escape('StayQR hotel invoice')||','||
        private.day12_csv_escape(i.total_amount::text)||','||private.day12_csv_escape(i.invoice_status),E'\n' order by i.invoice_date,i.invoice_number
      ),''),count(*)::integer
    into v_csv,v_rows
    from public.invoices i left join public.guests g on g.id=i.guest_id and g.hotel_id=i.hotel_id
    where i.hotel_id=p_hotel_id and i.invoice_date between p_date_from and p_date_to and i.invoice_status in ('issued','paid');
    v_hash:=private.day12_hash_text(v_csv);
  end if;

  v_file:='stayqr-'||v_template||'-'||p_date_from::text||case when p_date_to=p_date_from then '' else '-to-'||p_date_to::text end||'.csv';
  insert into public.accounting_exports (
    hotel_id,night_audit_id,export_type,date_from,date_to,file_name,content_type,row_count,csv_content,content_hash,idempotency_key,generated_by,metadata
  ) values (
    p_hotel_id,null,'accounting_csv',p_date_from,p_date_to,v_file,'text/csv',v_rows,v_csv,v_hash,v_request,v_actor,
    jsonb_build_object('generated_from','v1.1_revenue_growth','v11_profile_id',v_profile.id,'v11_template',v_template)
  ) returning * into v_existing;
  return to_jsonb(v_existing)||jsonb_build_object('ok',true,'idempotent',false);
end;
$function$;

-- --------------------------------------------------------------------------
-- 11. Grants. Revoke broad defaults first.
-- --------------------------------------------------------------------------
revoke all on table public.public_booking_settings from public, anon;
revoke all on table public.corporate_accounts from public, anon;
revoke all on table public.corporate_rates from public, anon;
revoke all on table public.reservation_corporate_links from public, anon;
revoke all on table public.public_booking_requests from public, anon;
revoke all on table public.stay_move_plans from public, anon;
revoke all on table public.folio_split_shares from public, anon;
revoke all on table public.accounting_export_profiles from public, anon;

grant select on table public.public_booking_settings to authenticated;
grant select on table public.corporate_accounts to authenticated;
grant select on table public.corporate_rates to authenticated;
grant select on table public.reservation_corporate_links to authenticated;
grant select on table public.public_booking_requests to authenticated;
grant select on table public.stay_move_plans to authenticated;
grant select on table public.folio_split_shares to authenticated;
grant select on table public.accounting_export_profiles to authenticated;

revoke all on function private.v11_assert_revenue_manage(uuid) from public,anon,authenticated;
revoke all on function private.v11_public_rate_quote(uuid,uuid,uuid,uuid,date,date,integer,integer) from public,anon,authenticated;

revoke all on function public.get_public_booking_hotel(text) from public;
revoke all on function public.get_public_booking_options(text,date,date,integer,integer,text) from public;
revoke all on function public.create_public_booking(text,text,jsonb) from public;
grant execute on function public.get_public_booking_hotel(text) to anon,authenticated,service_role;
grant execute on function public.get_public_booking_options(text,date,date,integer,integer,text) to anon,authenticated,service_role;
grant execute on function public.create_public_booking(text,text,jsonb) to anon,authenticated,service_role;

revoke all on function public.get_v11_revenue_workspace(uuid) from public;
revoke all on function public.upsert_v11_public_booking_settings(uuid,jsonb) from public;
revoke all on function public.upsert_v11_corporate_account(uuid,jsonb) from public;
revoke all on function public.upsert_v11_corporate_rate(uuid,jsonb) from public;
revoke all on function public.create_v11_stay_move_plan(uuid,uuid,uuid,date,text) from public;
revoke all on function public.cancel_v11_stay_move_plan(uuid,uuid) from public;
revoke all on function public.verify_v11_stay_move_plan(uuid,uuid) from public;
revoke all on function public.replace_v11_folio_split_plan(uuid,uuid,jsonb) from public;
revoke all on function public.post_v11_split_share_collection(uuid,uuid,numeric,text,text,text) from public;
revoke all on function public.upsert_v11_accounting_profile(uuid,jsonb) from public;
revoke all on function public.generate_v11_accounting_export(uuid,uuid,date,date,text) from public;

grant execute on function public.get_v11_revenue_workspace(uuid) to authenticated,service_role;
grant execute on function public.upsert_v11_public_booking_settings(uuid,jsonb) to authenticated,service_role;
grant execute on function public.upsert_v11_corporate_account(uuid,jsonb) to authenticated,service_role;
grant execute on function public.upsert_v11_corporate_rate(uuid,jsonb) to authenticated,service_role;
grant execute on function public.create_v11_stay_move_plan(uuid,uuid,uuid,date,text) to authenticated,service_role;
grant execute on function public.cancel_v11_stay_move_plan(uuid,uuid) to authenticated,service_role;
grant execute on function public.verify_v11_stay_move_plan(uuid,uuid) to authenticated,service_role;
grant execute on function public.replace_v11_folio_split_plan(uuid,uuid,jsonb) to authenticated,service_role;
grant execute on function public.post_v11_split_share_collection(uuid,uuid,numeric,text,text,text) to authenticated,service_role;
grant execute on function public.upsert_v11_accounting_profile(uuid,jsonb) to authenticated,service_role;
grant execute on function public.generate_v11_accounting_export(uuid,uuid,date,date,text) to authenticated,service_role;

commit;
