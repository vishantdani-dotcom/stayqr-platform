-- ============================================================================
-- StayQR v1.0
-- Day 8 Migration 017 — Onboarding, Hotel Settings, Floors and Trial Foundation
--
-- PRIMARY OUTCOME
-- Establish the first production-safe Day 8 schema layer for:
--   - resumable hotel onboarding;
--   - structured hotel policy/tax/business settings;
--   - normalized floors and room-floor linkage;
--   - hotel-scoped invoice numbering configuration;
--   - explicit trial lifecycle fields;
--   - neutral hotel_info defaults suitable for every tenant.
--
-- SCOPE BOUNDARY
-- This migration does NOT yet create the onboarding bootstrap RPC, bulk-room
-- import RPC, amenities/request-category defaults, or the onboarding frontend.
-- Those belong to the next bounded Day 8 package after this foundation passes.
--
-- SAFETY
-- - Run once in Supabase SQL Editor with role: postgres.
-- - Transactional and idempotent.
-- - No existing room, reservation, invoice, guest, payment, menu or QR record
--   is deleted.
-- - Existing rooms receive a reversible "Default Floor" association, but
--   rooms.floor_id intentionally remains nullable until the Day 8 room UI and
--   import RPC have been upgraded.
--
-- EXPECTED RESULT
-- 12 rows, and every passed value must be true.
-- ============================================================================

begin;

set local lock_timeout = '10s';
set local statement_timeout = '180s';

select pg_advisory_xact_lock(
  hashtext('stayqr:202607270017:day8-onboarding-settings-floors-trial')
);

-- ============================================================================
-- 0. PRE-MIGRATION ASSERTIONS
-- ============================================================================

do $preflight$
begin
  if to_regprocedure('private.user_has_hotel_access(uuid)') is null then
    raise exception
      'Migration 017 stopped: private.user_has_hotel_access(uuid) is missing.';
  end if;

  if to_regprocedure('private.user_has_permission(uuid,text)') is null then
    raise exception
      'Migration 017 stopped: private.user_has_permission(uuid,text) is missing.';
  end if;

  if to_regprocedure('private.set_updated_at()') is null then
    raise exception
      'Migration 017 stopped: private.set_updated_at() is missing.';
  end if;

  if exists (
    select 1
    from public.hotels h
    where nullif(trim(h.hotel_name), '') is null
       or nullif(trim(h.slug), '') is null
       or nullif(trim(h.timezone), '') is null
       or h.currency_code !~ '^[A-Z]{3}$'
  ) then
    raise exception
      'Migration 017 stopped: invalid hotel tenant metadata exists.';
  end if;

  if exists (
    select 1
    from (
      select lower(h.slug)
      from public.hotels h
      group by lower(h.slug)
      having count(*) > 1
    ) duplicate_slug
  ) then
    raise exception
      'Migration 017 stopped: duplicate case-insensitive hotel slugs exist.';
  end if;
end;
$preflight$;

-- ============================================================================
-- 1. REMOVE LEGACY HOTEL-SPECIFIC hotel_info DEFAULTS
--    Fresh tenants must never inherit VD Stay Inn names, phones, Wi-Fi or copy.
-- ============================================================================

alter table public.hotel_info
  alter column hotel_name drop default,
  alter column address drop default,
  alter column reception_phone drop default,
  alter column emergency_phone drop default,
  alter column breakfast_time drop default,
  alter column wifi_name drop default,
  alter column wifi_password drop default,
  alter column hotel_rules drop default,
  alter column about drop default,
  alter column reward_title set default 'Guest Reward',
  alter column reward_description
    set default 'Contact reception to learn about available guest rewards.',
  alter column reward_enabled set default false;

-- Guarantee one neutral hotel_info row per hotel without relying on any legacy
-- table default.
insert into public.hotel_info (
  hotel_id,
  hotel_name,
  address,
  reception_phone,
  emergency_phone,
  checkin_time,
  checkout_time,
  breakfast_time,
  wifi_name,
  wifi_password,
  hotel_rules,
  about,
  created_at,
  google_review_url,
  reward_title,
  reward_description,
  reward_enabled
)
select
  h.id,
  h.hotel_name,
  coalesce(
    nullif(trim(concat_ws(
      ', ',
      nullif(trim(h.address), ''),
      nullif(trim(h.city), ''),
      nullif(trim(h.state), '')
    )), ''),
    nullif(trim(h.location), '')
  ),
  nullif(trim(h.phone), ''),
  nullif(trim(h.phone), ''),
  '2:00 PM',
  '11:00 AM',
  null,
  null,
  null,
  null,
  h.hotel_name || ' uses StayQR for a smarter and more convenient guest experience.',
  now(),
  null,
  'Guest Reward',
  'Contact reception to learn about available guest rewards.',
  false
from public.hotels h
where not exists (
  select 1
  from public.hotel_info hi
  where hi.hotel_id = h.id
);

-- ============================================================================
-- 2. STRUCTURED HOTEL SETTINGS
--    hotels remains the source of truth for timezone and currency_code.
-- ============================================================================

create table if not exists public.hotel_settings (
  hotel_id uuid primary key
    references public.hotels(id) on delete cascade,
  legal_name text,
  tax_registration_number text,
  default_tax_percent numeric(6,3) not null default 0,
  prices_include_tax boolean not null default false,
  tax_label text not null default 'Tax',
  checkin_time time not null default '14:00',
  checkout_time time not null default '11:00',
  checkout_grace_minutes integer not null default 0,
  minimum_checkin_age integer not null default 18,
  cancellation_policy text,
  house_rules text,
  terms_and_conditions text,
  invoice_notes text,
  locale text not null default 'en-IN',
  date_format text not null default 'DD/MM/YYYY',
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint hotel_settings_legal_name_not_blank
    check (legal_name is null or length(trim(legal_name)) > 0),
  constraint hotel_settings_tax_percent_check
    check (default_tax_percent between 0 and 100),
  constraint hotel_settings_tax_label_not_blank
    check (length(trim(tax_label)) > 0),
  constraint hotel_settings_checkout_grace_check
    check (checkout_grace_minutes between 0 and 1440),
  constraint hotel_settings_minimum_age_check
    check (minimum_checkin_age between 0 and 120),
  constraint hotel_settings_locale_not_blank
    check (length(trim(locale)) > 0),
  constraint hotel_settings_date_format_check
    check (date_format in ('DD/MM/YYYY', 'MM/DD/YYYY', 'YYYY-MM-DD'))
);

insert into public.hotel_settings (
  hotel_id,
  legal_name,
  tax_registration_number,
  default_tax_percent,
  prices_include_tax,
  checkin_time,
  checkout_time,
  cancellation_policy,
  house_rules,
  invoice_notes,
  locale,
  date_format,
  created_at,
  updated_at
)
select
  h.id,
  h.hotel_name,
  nullif(trim(h.gst_number), ''),
  0,
  false,
  '14:00'::time,
  '11:00'::time,
  null,
  hi.hotel_rules,
  coalesce(nullif(trim(h.invoice_terms), ''), nullif(trim(h.invoice_footer), '')),
  'en-IN',
  'DD/MM/YYYY',
  now(),
  now()
from public.hotels h
left join public.hotel_info hi on hi.hotel_id = h.id
on conflict (hotel_id) do nothing;

-- ============================================================================
-- 3. RESUMABLE HOTEL ONBOARDING STATE
-- ============================================================================

create table if not exists public.hotel_onboarding (
  hotel_id uuid primary key
    references public.hotels(id) on delete cascade,
  owner_user_id uuid references auth.users(id) on delete set null,
  status text not null default 'draft',
  current_step text not null default 'hotel_details',
  completed_steps text[] not null default '{}'::text[],
  form_state jsonb not null default '{}'::jsonb,
  readiness_state jsonb not null default '{}'::jsonb,
  last_error text,
  version integer not null default 1,
  started_at timestamptz not null default now(),
  last_saved_at timestamptz not null default now(),
  completed_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint hotel_onboarding_status_check
    check (status in ('draft', 'in_progress', 'complete', 'blocked')),
  constraint hotel_onboarding_step_check
    check (
      current_step in (
        'account',
        'hotel_details',
        'policies',
        'room_types',
        'floors_rooms',
        'amenities',
        'request_categories',
        'menu',
        'invoice',
        'subscription',
        'review',
        'complete'
      )
    ),
  constraint hotel_onboarding_form_state_object
    check (jsonb_typeof(form_state) = 'object'),
  constraint hotel_onboarding_readiness_state_object
    check (jsonb_typeof(readiness_state) = 'object'),
  constraint hotel_onboarding_version_check
    check (version >= 1),
  constraint hotel_onboarding_completion_check
    check (
      (status = 'complete' and completed_at is not null and current_step = 'complete')
      or status <> 'complete'
    )
);

insert into public.hotel_onboarding (
  hotel_id,
  owner_user_id,
  status,
  current_step,
  completed_steps,
  form_state,
  readiness_state,
  version,
  started_at,
  last_saved_at,
  created_at,
  updated_at
)
select
  h.id,
  (
    select s.auth_user_id
    from public.staff s
    where s.hotel_id = h.id
      and s.status = 'active'
      and s.auth_user_id is not null
      and lower(replace(trim(s.role::text), ' ', '_')) = 'owner'
    order by s.created_at
    limit 1
  ),
  'in_progress',
  case
    when not exists (
      select 1 from public.hotel_info hi where hi.hotel_id = h.id
    ) then 'hotel_details'
    when not exists (
      select 1 from public.room_types rt where rt.hotel_id = h.id
    ) then 'room_types'
    when not exists (
      select 1 from public.rooms r where r.hotel_id = h.id
    ) then 'floors_rooms'
    when not exists (
      select 1
      from public.hotel_subscriptions hs
      where hs.hotel_id = h.id
        and hs.status in ('trial', 'trialing', 'active', 'past_due')
    ) then 'subscription'
    else 'policies'
  end,
  array_remove(array[
    case when exists (
      select 1 from public.hotel_info hi where hi.hotel_id = h.id
    ) then 'hotel_details'::text end,
    case when exists (
      select 1 from public.room_types rt where rt.hotel_id = h.id
    ) then 'room_types'::text end,
    case when exists (
      select 1 from public.rooms r where r.hotel_id = h.id
    ) then 'floors_rooms'::text end,
    case when exists (
      select 1
      from public.hotel_subscriptions hs
      where hs.hotel_id = h.id
        and hs.status in ('trial', 'trialing', 'active', 'past_due')
    ) then 'subscription'::text end
  ], null),
  jsonb_build_object(
    'source', 'migration_017',
    'legacy_hotel', true
  ),
  '{}'::jsonb,
  1,
  coalesce(h.created_at, now()),
  now(),
  now(),
  now()
from public.hotels h
on conflict (hotel_id) do nothing;

-- ============================================================================
-- 4. NORMALIZED FLOORS AND ROOM LINKAGE
-- ============================================================================

create table if not exists public.floors (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null
    references public.hotels(id) on delete cascade,
  name text not null,
  code text not null,
  floor_number integer,
  description text,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint floors_name_not_blank
    check (length(trim(name)) > 0),
  constraint floors_code_not_blank
    check (length(trim(code)) > 0)
);

create unique index if not exists uq_floors_hotel_id_id
on public.floors (hotel_id, id);

create unique index if not exists uq_floors_hotel_code
on public.floors (hotel_id, upper(code));

create unique index if not exists uq_floors_hotel_number
on public.floors (hotel_id, floor_number)
where floor_number is not null;

create index if not exists idx_floors_hotel_active_sort
on public.floors (hotel_id, is_active, sort_order, floor_number);

insert into public.floors (
  hotel_id,
  name,
  code,
  floor_number,
  description,
  sort_order,
  is_active,
  created_at,
  updated_at
)
select
  h.id,
  'Default Floor',
  'DEFAULT',
  0,
  'Temporary normalized floor for rooms created before Day 8 configuration.',
  0,
  true,
  now(),
  now()
from public.hotels h
where not exists (
  select 1
  from public.floors f
  where f.hotel_id = h.id
    and upper(f.code) = 'DEFAULT'
);

alter table public.rooms
  add column if not exists floor_id uuid;

update public.rooms r
set floor_id = f.id
from public.floors f
where f.hotel_id = r.hotel_id
  and upper(f.code) = 'DEFAULT'
  and r.floor_id is null;

do $floor_fk$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'rooms_hotel_floor_fkey'
      and conrelid = 'public.rooms'::regclass
  ) then
    alter table public.rooms
      add constraint rooms_hotel_floor_fkey
      foreign key (hotel_id, floor_id)
      references public.floors(hotel_id, id)
      on delete restrict
      not valid;

    alter table public.rooms
      validate constraint rooms_hotel_floor_fkey;
  end if;
end;
$floor_fk$;

create index if not exists idx_rooms_hotel_floor_status
on public.rooms (hotel_id, floor_id, status);

-- ============================================================================
-- 5. HOTEL-SCOPED INVOICE NUMBERING CONFIGURATION
-- ============================================================================

create table if not exists public.invoice_number_sequences (
  hotel_id uuid not null
    references public.hotels(id) on delete cascade,
  sequence_year integer not null,
  prefix text not null default 'INV',
  last_number bigint not null default 0,
  padding integer not null default 6,
  reset_annually boolean not null default true,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (hotel_id, sequence_year),
  constraint invoice_number_sequences_year_check
    check (sequence_year between 2000 and 9999),
  constraint invoice_number_sequences_prefix_not_blank
    check (length(trim(prefix)) between 1 and 20),
  constraint invoice_number_sequences_number_check
    check (last_number >= 0),
  constraint invoice_number_sequences_padding_check
    check (padding between 1 and 12)
);

insert into public.invoice_number_sequences (
  hotel_id,
  sequence_year,
  prefix,
  last_number,
  padding,
  reset_annually,
  created_at,
  updated_at
)
select
  h.id,
  extract(year from now())::integer,
  coalesce(
    nullif(
      upper(substr(regexp_replace(h.slug, '[^a-zA-Z0-9]', '', 'g'), 1, 4)),
      ''
    ) || '-INV',
    'INV'
  ),
  coalesce(
    max((substring(i.invoice_number from '([0-9]+)$'))::bigint),
    0
  ),
  6,
  true,
  now(),
  now()
from public.hotels h
left join public.invoices i
  on i.hotel_id = h.id
group by h.id, h.slug
on conflict (hotel_id, sequence_year) do nothing;

-- ============================================================================
-- 6. EXPLICIT SUBSCRIPTION/TRIAL LIFECYCLE
-- ============================================================================

alter table public.hotel_subscriptions
  add column if not exists trial_started_at timestamptz,
  add column if not exists trial_ends_at timestamptz,
  add column if not exists activated_at timestamptz,
  add column if not exists cancelled_at timestamptz,
  add column if not exists cancellation_reason text,
  add column if not exists metadata jsonb,
  add column if not exists updated_at timestamptz;

update public.hotel_subscriptions hs
set
  trial_started_at = coalesce(
    hs.trial_started_at,
    case
      when hs.status in ('trial', 'trialing')
        then coalesce(hs.start_date, hs.created_at, now())
    end
  ),
  trial_ends_at = coalesce(
    hs.trial_ends_at,
    case
      when hs.status in ('trial', 'trialing')
        then hs.end_date
    end
  ),
  activated_at = coalesce(
    hs.activated_at,
    case
      when hs.status = 'active'
        then coalesce(hs.start_date, hs.created_at, now())
    end
  ),
  metadata = coalesce(hs.metadata, '{}'::jsonb),
  updated_at = coalesce(hs.updated_at, hs.created_at, now());

alter table public.hotel_subscriptions
  alter column metadata set default '{}'::jsonb,
  alter column metadata set not null,
  alter column updated_at set default now(),
  alter column updated_at set not null;

alter table public.hotel_subscriptions
  drop constraint if exists hotel_subscriptions_trial_dates_check;

alter table public.hotel_subscriptions
  add constraint hotel_subscriptions_trial_dates_check
  check (
    trial_ends_at is null
    or trial_started_at is null
    or trial_ends_at > trial_started_at
  )
  not valid;

alter table public.hotel_subscriptions
  validate constraint hotel_subscriptions_trial_dates_check;

alter table public.hotel_subscriptions
  drop constraint if exists hotel_subscriptions_cancellation_check;

alter table public.hotel_subscriptions
  add constraint hotel_subscriptions_cancellation_check
  check (
    cancelled_at is null
    or status in ('cancelled', 'expired', 'suspended')
  )
  not valid;

alter table public.hotel_subscriptions
  validate constraint hotel_subscriptions_cancellation_check;

create index if not exists idx_hotel_subscriptions_trial_ends
on public.hotel_subscriptions (trial_ends_at)
where status in ('trial', 'trialing');

-- ============================================================================
-- 7. updated_at TRIGGERS
-- ============================================================================

drop trigger if exists set_hotel_settings_updated_at
on public.hotel_settings;

create trigger set_hotel_settings_updated_at
before update on public.hotel_settings
for each row execute function private.set_updated_at();

drop trigger if exists set_hotel_onboarding_updated_at
on public.hotel_onboarding;

create trigger set_hotel_onboarding_updated_at
before update on public.hotel_onboarding
for each row execute function private.set_updated_at();

drop trigger if exists set_floors_updated_at
on public.floors;

create trigger set_floors_updated_at
before update on public.floors
for each row execute function private.set_updated_at();

drop trigger if exists set_invoice_number_sequences_updated_at
on public.invoice_number_sequences;

create trigger set_invoice_number_sequences_updated_at
before update on public.invoice_number_sequences
for each row execute function private.set_updated_at();

drop trigger if exists set_hotel_subscriptions_updated_at
on public.hotel_subscriptions;

create trigger set_hotel_subscriptions_updated_at
before update on public.hotel_subscriptions
for each row execute function private.set_updated_at();

-- ============================================================================
-- 8. GRANTS AND RLS POLICIES
-- ============================================================================

revoke all on public.hotel_settings
from public, anon;

revoke all on public.hotel_onboarding
from public, anon;

revoke all on public.floors
from public, anon;

revoke all on public.invoice_number_sequences
from public, anon;

grant select, insert, update, delete
on public.hotel_settings
to authenticated;

grant select, insert, update, delete
on public.hotel_onboarding
to authenticated;

grant select, insert, update, delete
on public.floors
to authenticated;

grant select, insert, update, delete
on public.invoice_number_sequences
to authenticated;

alter table public.hotel_settings enable row level security;
alter table public.hotel_onboarding enable row level security;
alter table public.floors enable row level security;
alter table public.invoice_number_sequences enable row level security;

-- Hotel settings.
drop policy if exists stayqr_hotel_settings_select
on public.hotel_settings;
drop policy if exists stayqr_hotel_settings_insert
on public.hotel_settings;
drop policy if exists stayqr_hotel_settings_update
on public.hotel_settings;
drop policy if exists stayqr_hotel_settings_delete
on public.hotel_settings;

create policy stayqr_hotel_settings_select
on public.hotel_settings
for select to authenticated
using (private.user_has_hotel_access(hotel_id));

create policy stayqr_hotel_settings_insert
on public.hotel_settings
for insert to authenticated
with check (
  private.is_platform_admin()
  or private.user_has_permission(hotel_id, 'hotel.manage')
);

create policy stayqr_hotel_settings_update
on public.hotel_settings
for update to authenticated
using (
  private.is_platform_admin()
  or private.user_has_permission(hotel_id, 'hotel.manage')
)
with check (
  private.is_platform_admin()
  or private.user_has_permission(hotel_id, 'hotel.manage')
);

create policy stayqr_hotel_settings_delete
on public.hotel_settings
for delete to authenticated
using (private.is_platform_admin());

-- Onboarding state.
drop policy if exists stayqr_hotel_onboarding_select
on public.hotel_onboarding;
drop policy if exists stayqr_hotel_onboarding_insert
on public.hotel_onboarding;
drop policy if exists stayqr_hotel_onboarding_update
on public.hotel_onboarding;
drop policy if exists stayqr_hotel_onboarding_delete
on public.hotel_onboarding;

create policy stayqr_hotel_onboarding_select
on public.hotel_onboarding
for select to authenticated
using (
  private.is_platform_admin()
  or private.user_has_hotel_access(hotel_id)
  or owner_user_id = (select auth.uid())
);

create policy stayqr_hotel_onboarding_insert
on public.hotel_onboarding
for insert to authenticated
with check (
  private.is_platform_admin()
  or private.user_has_permission(hotel_id, 'hotel.manage')
  or owner_user_id = (select auth.uid())
);

create policy stayqr_hotel_onboarding_update
on public.hotel_onboarding
for update to authenticated
using (
  private.is_platform_admin()
  or private.user_has_permission(hotel_id, 'hotel.manage')
  or owner_user_id = (select auth.uid())
)
with check (
  private.is_platform_admin()
  or private.user_has_permission(hotel_id, 'hotel.manage')
  or owner_user_id = (select auth.uid())
);

create policy stayqr_hotel_onboarding_delete
on public.hotel_onboarding
for delete to authenticated
using (private.is_platform_admin());

-- Floors.
drop policy if exists stayqr_floors_select
on public.floors;
drop policy if exists stayqr_floors_insert
on public.floors;
drop policy if exists stayqr_floors_update
on public.floors;
drop policy if exists stayqr_floors_delete
on public.floors;

create policy stayqr_floors_select
on public.floors
for select to authenticated
using (private.user_has_hotel_access(hotel_id));

create policy stayqr_floors_insert
on public.floors
for insert to authenticated
with check (private.user_has_permission(hotel_id, 'hotel.manage'));

create policy stayqr_floors_update
on public.floors
for update to authenticated
using (private.user_has_permission(hotel_id, 'hotel.manage'))
with check (private.user_has_permission(hotel_id, 'hotel.manage'));

create policy stayqr_floors_delete
on public.floors
for delete to authenticated
using (private.user_has_permission(hotel_id, 'hotel.manage'));

-- Invoice numbering.
drop policy if exists stayqr_invoice_sequences_select
on public.invoice_number_sequences;
drop policy if exists stayqr_invoice_sequences_insert
on public.invoice_number_sequences;
drop policy if exists stayqr_invoice_sequences_update
on public.invoice_number_sequences;
drop policy if exists stayqr_invoice_sequences_delete
on public.invoice_number_sequences;

create policy stayqr_invoice_sequences_select
on public.invoice_number_sequences
for select to authenticated
using (private.user_has_hotel_access(hotel_id));

create policy stayqr_invoice_sequences_insert
on public.invoice_number_sequences
for insert to authenticated
with check (
  private.is_platform_admin()
  or private.user_has_permission(hotel_id, 'hotel.manage')
);

create policy stayqr_invoice_sequences_update
on public.invoice_number_sequences
for update to authenticated
using (
  private.is_platform_admin()
  or private.user_has_permission(hotel_id, 'hotel.manage')
)
with check (
  private.is_platform_admin()
  or private.user_has_permission(hotel_id, 'hotel.manage')
);

create policy stayqr_invoice_sequences_delete
on public.invoice_number_sequences
for delete to authenticated
using (private.is_platform_admin());

-- ============================================================================
-- 9. POST-MIGRATION ASSERTIONS
-- ============================================================================

do $verify$
begin
  if exists (
    select 1
    from public.hotels h
    where not exists (
      select 1 from public.hotel_info hi where hi.hotel_id = h.id
    )
  ) then
    raise exception
      'Migration 017 failed: at least one hotel has no hotel_info row.';
  end if;

  if exists (
    select 1
    from public.hotels h
    where not exists (
      select 1 from public.hotel_settings hs where hs.hotel_id = h.id
    )
  ) then
    raise exception
      'Migration 017 failed: at least one hotel has no hotel_settings row.';
  end if;

  if exists (
    select 1
    from public.hotels h
    where not exists (
      select 1 from public.hotel_onboarding ho where ho.hotel_id = h.id
    )
  ) then
    raise exception
      'Migration 017 failed: at least one hotel has no onboarding state.';
  end if;

  if exists (
    select 1
    from public.hotels h
    where not exists (
      select 1 from public.floors f where f.hotel_id = h.id
    )
  ) then
    raise exception
      'Migration 017 failed: at least one hotel has no floor row.';
  end if;

  if exists (
    select 1
    from public.rooms r
    where r.floor_id is null
  ) then
    raise exception
      'Migration 017 failed: an existing room was not linked to a floor.';
  end if;

  if exists (
    select 1
    from public.hotels h
    where not exists (
      select 1
      from public.invoice_number_sequences ins
      where ins.hotel_id = h.id
        and ins.sequence_year = extract(year from now())::integer
    )
  ) then
    raise exception
      'Migration 017 failed: current-year invoice sequence is missing.';
  end if;

  if exists (
    select 1
    from information_schema.columns col
    join pg_class c on c.relname = col.table_name
    join pg_namespace n
      on n.oid = c.relnamespace
     and n.nspname = col.table_schema
    where col.table_schema = 'public'
      and col.table_name in (
        'hotel_settings',
        'hotel_onboarding',
        'floors',
        'invoice_number_sequences'
      )
      and col.column_name = 'hotel_id'
      and not c.relrowsecurity
  ) then
    raise exception
      'Migration 017 failed: a new tenant table does not have RLS enabled.';
  end if;
end;
$verify$;

commit;

-- ============================================================================
-- 10. ACCEPTANCE RESULT
-- ============================================================================

with checks(test_name, passed, details) as (
  values
    (
      '01_neutral_hotel_info_defaults',
      (
        select column_default is null
        from information_schema.columns
        where table_schema = 'public'
          and table_name = 'hotel_info'
          and column_name = 'hotel_name'
      ),
      'hotel_info no longer has a fixed tenant-name default.'
    ),
    (
      '02_hotel_info_coverage',
      not exists (
        select 1
        from public.hotels h
        where not exists (
          select 1 from public.hotel_info hi where hi.hotel_id = h.id
        )
      ),
      'Every hotel has exactly one hotel_info row through the existing unique index.'
    ),
    (
      '03_hotel_settings_coverage',
      not exists (
        select 1
        from public.hotels h
        where not exists (
          select 1 from public.hotel_settings hs where hs.hotel_id = h.id
        )
      ),
      'Every hotel has structured settings.'
    ),
    (
      '04_resumable_onboarding_coverage',
      not exists (
        select 1
        from public.hotels h
        where not exists (
          select 1 from public.hotel_onboarding ho where ho.hotel_id = h.id
        )
      ),
      'Every hotel has resumable onboarding state.'
    ),
    (
      '05_floor_coverage',
      not exists (
        select 1
        from public.hotels h
        where not exists (
          select 1 from public.floors f where f.hotel_id = h.id
        )
      ),
      'Every hotel has at least one normalized floor.'
    ),
    (
      '06_existing_rooms_floor_linked',
      not exists (
        select 1 from public.rooms r where r.floor_id is null
      ),
      'All rooms that existed at migration time are floor-linked.'
    ),
    (
      '07_room_floor_foreign_key',
      exists (
        select 1
        from pg_constraint
        where conname = 'rooms_hotel_floor_fkey'
          and conrelid = 'public.rooms'::regclass
          and convalidated
      ),
      'Room-to-floor ownership is protected by a validated hotel-scoped foreign key.'
    ),
    (
      '08_invoice_sequence_coverage',
      not exists (
        select 1
        from public.hotels h
        where not exists (
          select 1
          from public.invoice_number_sequences ins
          where ins.hotel_id = h.id
            and ins.sequence_year = extract(year from now())::integer
        )
      ),
      'Every hotel has a current-year invoice numbering configuration.'
    ),
    (
      '09_trial_lifecycle_columns',
      (
        select count(*) = 6
        from information_schema.columns
        where table_schema = 'public'
          and table_name = 'hotel_subscriptions'
          and column_name in (
            'trial_started_at',
            'trial_ends_at',
            'activated_at',
            'cancelled_at',
            'metadata',
            'updated_at'
          )
      ),
      'Explicit trial, activation, cancellation, metadata and update fields exist.'
    ),
    (
      '10_new_tenant_tables_have_rls',
      not exists (
        select 1
        from information_schema.columns col
        join pg_class c on c.relname = col.table_name
        join pg_namespace n
          on n.oid = c.relnamespace
         and n.nspname = col.table_schema
        where col.table_schema = 'public'
          and col.table_name in (
            'hotel_settings',
            'hotel_onboarding',
            'floors',
            'invoice_number_sequences'
          )
          and col.column_name = 'hotel_id'
          and not c.relrowsecurity
      ),
      'All four new tenant tables have RLS enabled.'
    ),
    (
      '11_new_tenant_policy_matrix',
      (
        select count(*) = 16
        from pg_policies
        where schemaname = 'public'
          and (
            (tablename = 'hotel_settings'
              and policyname like 'stayqr_hotel_settings_%')
            or
            (tablename = 'hotel_onboarding'
              and policyname like 'stayqr_hotel_onboarding_%')
            or
            (tablename = 'floors'
              and policyname like 'stayqr_floors_%')
            or
            (tablename = 'invoice_number_sequences'
              and policyname like 'stayqr_invoice_sequences_%')
          )
      ),
      'SELECT/INSERT/UPDATE/DELETE policies exist for every new tenant table.'
    ),
    (
      '12_day8_foundation_ready',
      to_regclass('public.hotel_settings') is not null
      and to_regclass('public.hotel_onboarding') is not null
      and to_regclass('public.floors') is not null
      and to_regclass('public.invoice_number_sequences') is not null,
      'Migration 017 foundation is ready for the atomic onboarding and bulk-configuration RPC package.'
    )
)
select test_name, passed, details
from checks
order by test_name;
