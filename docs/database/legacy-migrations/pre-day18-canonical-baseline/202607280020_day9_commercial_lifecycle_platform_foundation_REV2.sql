-- ============================================================================
-- StayQR v1.0
-- Day 9 Migration 020 REV2 — Commercial, Lifecycle Event and Platform Foundation
--
-- PRIMARY OUTCOME
-- Establishes the production-safe Day 9 schema layer for:
--   - structured plan codes, annual pricing and expandable limits;
--   - provider/billing metadata on hotel subscriptions;
--   - provider-specific plan-price mapping;
--   - immutable subscription lifecycle events;
--   - authoritative usage counters;
--   - support tickets and immutable ticket events;
--   - platform announcements;
--   - explicit, time-bound support-access sessions;
--   - signed-webhook idempotency ledger;
--   - guarded reconciliation of the two risks proven by Audits 049 and 050.
--
-- GUARDED PRODUCTION RECONCILIATION
-- 1. VD Stay Inn has 12 rooms, cached status active and no subscription row.
--    It receives the smallest active plan that supports its room inventory
--    (currently Growth) as an internal complimentary legacy subscription.
--    This preserves current access without falsely counting paid MRR.
-- 2. Hotel Apex Stay Inn has an active subscription row whose end_date passed
--    on 21 July 2026. The row and cached hotel status are reconciled to expired.
--    Hotel access is not suspended by this migration; suspension/recovery is a
--    separately tested Day 9 lifecycle action.
--
-- SCOPE BOUNDARY
-- This migration does NOT yet create trial-extension, paid-conversion,
-- suspension/reactivation, plan-change, MRR dashboard, support-ticket workflow,
-- safe-support-access or Razorpay Edge Function actions. Those are built on
-- this accepted foundation in the next bounded package.
--
-- SAFETY
-- - Run once in Supabase SQL Editor with role: postgres.
-- - Transactional and idempotent.
-- - The two reconciled hotels are archived in private JSON snapshots first.
-- - Existing plans, subscriptions and Day 8 onboarding records are not deleted.
-- - No Razorpay secret or API key is stored in public tables or frontend code.
--
-- REV2 FIX
-- The subscription-events idempotency index is partial:
--   WHERE idempotency_key IS NOT NULL
-- PostgreSQL cannot infer that partial index from:
--   ON CONFLICT (idempotency_key)
-- REV2 uses a target-free ON CONFLICT DO NOTHING for the initial immutable
-- snapshot backfill. The original REV1 query was inside one transaction and
-- failed before COMMIT, so all attempted schema and business-data changes were
-- rolled back automatically.
--
-- EXPECTED RESULT
-- 30 rows, and every passed value must be true.
-- ============================================================================

begin;

set local lock_timeout = '10s';
set local statement_timeout = '240s';

select pg_advisory_xact_lock(
  hashtext('stayqr:202607280020:day9-commercial-lifecycle-foundation')
);

select set_config(
  'stayqr.subscription_event_source',
  'migration_020',
  true
);

-- ============================================================================
-- 0. PRE-MIGRATION ASSERTIONS
-- ============================================================================

do $preflight$
declare
  vd_hotel_id constant uuid :=
    '77d850d0-016d-4155-bc44-a6207d30e7b9'::uuid;
  apex_hotel_id constant uuid :=
    '9e105be7-0d93-4dc9-84c6-f729b53f1368'::uuid;
  apex_subscription_id constant uuid :=
    'b2870090-4736-4716-819e-56e403e930cb'::uuid;
begin
  if to_regclass('public.subscription_plans') is null
     or to_regclass('public.hotel_subscriptions') is null
     or to_regclass('public.hotels') is null
  then
    raise exception
      'Migration 020 stopped: subscription foundation tables are missing.';
  end if;

  if to_regprocedure('private.is_platform_admin()') is null
     or to_regprocedure('private.user_has_hotel_access(uuid)') is null
     or to_regprocedure('private.set_updated_at()') is null
  then
    raise exception
      'Migration 020 stopped: locked authorization/update helpers are missing.';
  end if;

  if not exists (
    select 1
    from public.hotels h
    where h.id = vd_hotel_id
      and h.slug = 'vd-stay-inn'
      and h.status = 'active'
      and h.subscription_status = 'active'
  ) then
    raise exception
      'Migration 020 stopped: VD Stay Inn no longer matches Audit 050.';
  end if;

  if exists (
    select 1
    from public.hotel_subscriptions hs
    where hs.hotel_id = vd_hotel_id
      and hs.status in (
        'trial',
        'trialing',
        'active',
        'past_due',
        'suspended'
      )
  ) then
    raise exception
      'Migration 020 stopped: VD Stay Inn already has a current subscription.';
  end if;

  if not exists (
    select 1
    from public.hotel_subscriptions hs
    where hs.id = apex_subscription_id
      and hs.hotel_id = apex_hotel_id
      and hs.status = 'active'
      and hs.end_date <= now()
  ) then
    raise exception
      'Migration 020 stopped: Apex expired-active row no longer matches Audit 050.';
  end if;

  if not exists (
    select 1
    from public.hotels h
    where h.id = apex_hotel_id
      and h.slug = 'hotel-apex-stay-inn'
      and h.subscription_status = 'trial'
  ) then
    raise exception
      'Migration 020 stopped: Apex cached status no longer matches Audit 050.';
  end if;

  if exists (
    select 1
    from (
      select lower(trim(sp.plan_name))
      from public.subscription_plans sp
      group by lower(trim(sp.plan_name))
      having count(*) > 1
    ) duplicate_plan
  ) then
    raise exception
      'Migration 020 stopped: duplicate subscription plan names exist.';
  end if;

  if exists (
    select 1
    from (
      select hs.hotel_id
      from public.hotel_subscriptions hs
      where hs.status in (
        'trial',
        'trialing',
        'active',
        'past_due',
        'suspended'
      )
      group by hs.hotel_id
      having count(*) > 1
    ) duplicate_current
  ) then
    raise exception
      'Migration 020 stopped: a hotel has multiple current subscriptions.';
  end if;
end;
$preflight$;

-- ============================================================================
-- 1. PRIVATE RECONCILIATION ARCHIVE
-- ============================================================================

create table if not exists
  private.day9_subscription_reconciliation_archive_20260728 (
    archive_key text primary key,
    hotel_id uuid,
    subscription_id uuid,
    reason text not null,
    hotel_snapshot jsonb,
    subscription_snapshot jsonb,
    archived_at timestamptz not null default now()
  );

revoke all on
  private.day9_subscription_reconciliation_archive_20260728
from public, anon, authenticated;

insert into
  private.day9_subscription_reconciliation_archive_20260728 (
    archive_key,
    hotel_id,
    subscription_id,
    reason,
    hotel_snapshot,
    subscription_snapshot
  )
select
  'vd-stay-inn-before-migration-020',
  h.id,
  null,
  'Audit 050 proved active cached status with no subscription row.',
  to_jsonb(h),
  (
    select coalesce(jsonb_agg(to_jsonb(hs)), '[]'::jsonb)
    from public.hotel_subscriptions hs
    where hs.hotel_id = h.id
  )
from public.hotels h
where h.id =
  '77d850d0-016d-4155-bc44-a6207d30e7b9'::uuid
on conflict (archive_key) do nothing;

insert into
  private.day9_subscription_reconciliation_archive_20260728 (
    archive_key,
    hotel_id,
    subscription_id,
    reason,
    hotel_snapshot,
    subscription_snapshot
  )
select
  'hotel-apex-before-migration-020',
  h.id,
  hs.id,
  'Audit 050 proved cached trial status and an active subscription whose end_date had passed.',
  to_jsonb(h),
  to_jsonb(hs)
from public.hotels h
join public.hotel_subscriptions hs
  on hs.hotel_id = h.id
where h.id =
    '9e105be7-0d93-4dc9-84c6-f729b53f1368'::uuid
  and hs.id =
    'b2870090-4736-4716-819e-56e403e930cb'::uuid
on conflict (archive_key) do nothing;

-- ============================================================================
-- 2. EXPAND SUBSCRIPTION PLAN COMMERCIAL/LIMIT CONTRACT
-- ============================================================================

alter table public.subscription_plans
  add column if not exists plan_code text,
  add column if not exists price_annual numeric,
  add column if not exists max_staff integer,
  add column if not exists max_properties integer,
  add column if not exists max_storage_mb bigint,
  add column if not exists trial_days integer,
  add column if not exists currency_code text,
  add column if not exists is_public boolean,
  add column if not exists updated_at timestamptz;

update public.subscription_plans sp
set
  plan_code = coalesce(
    nullif(trim(sp.plan_code), ''),
    upper(private.normalize_hotel_slug(sp.plan_name))
  ),
  max_properties = coalesce(sp.max_properties, 1),
  trial_days = coalesce(sp.trial_days, 14),
  currency_code = upper(
    coalesce(nullif(trim(sp.currency_code), ''), 'INR')
  ),
  is_public = coalesce(sp.is_public, true),
  updated_at = coalesce(sp.updated_at, sp.created_at, now());

alter table public.subscription_plans
  alter column plan_code set not null,
  alter column max_properties set default 1,
  alter column max_properties set not null,
  alter column trial_days set default 14,
  alter column trial_days set not null,
  alter column currency_code set default 'INR',
  alter column currency_code set not null,
  alter column is_public set default true,
  alter column is_public set not null,
  alter column updated_at set default now(),
  alter column updated_at set not null;

alter table public.subscription_plans
  drop constraint if exists subscription_plans_plan_code_not_blank,
  drop constraint if exists subscription_plans_price_check,
  drop constraint if exists subscription_plans_limit_check,
  drop constraint if exists subscription_plans_trial_days_check,
  drop constraint if exists subscription_plans_currency_check,
  drop constraint if exists subscription_plans_status_check;

alter table public.subscription_plans
  add constraint subscription_plans_plan_code_not_blank
    check (length(trim(plan_code)) between 1 and 40)
    not valid,
  add constraint subscription_plans_price_check
    check (
      coalesce(price_monthly, 0) >= 0
      and (price_annual is null or price_annual >= 0)
    )
    not valid,
  add constraint subscription_plans_limit_check
    check (
      (max_rooms is null or max_rooms > 0)
      and (max_staff is null or max_staff > 0)
      and max_properties > 0
      and (max_storage_mb is null or max_storage_mb > 0)
    )
    not valid,
  add constraint subscription_plans_trial_days_check
    check (trial_days between 0 and 90)
    not valid,
  add constraint subscription_plans_currency_check
    check (currency_code ~ '^[A-Z]{3}$')
    not valid,
  add constraint subscription_plans_status_check
    check (status in ('active', 'inactive', 'archived'))
    not valid;

alter table public.subscription_plans
  validate constraint subscription_plans_plan_code_not_blank,
  validate constraint subscription_plans_price_check,
  validate constraint subscription_plans_limit_check,
  validate constraint subscription_plans_trial_days_check,
  validate constraint subscription_plans_currency_check,
  validate constraint subscription_plans_status_check;

create unique index if not exists
  uq_subscription_plans_plan_code
on public.subscription_plans (upper(trim(plan_code)));

create unique index if not exists
  uq_subscription_plans_name_lower
on public.subscription_plans (lower(trim(plan_name)));

drop trigger if exists
  set_subscription_plans_updated_at
on public.subscription_plans;

create trigger set_subscription_plans_updated_at
before update on public.subscription_plans
for each row execute function private.set_updated_at();

-- ============================================================================
-- 3. PROVIDER-SPECIFIC PLAN PRICE MAPPING
-- ============================================================================

create table if not exists public.subscription_plan_prices (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null
    references public.subscription_plans(id) on delete cascade,
  provider text not null default 'manual',
  billing_cycle text not null default 'monthly',
  currency_code text not null default 'INR',
  amount_minor bigint not null,
  provider_plan_id text,
  status text not null default 'active',
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint subscription_plan_prices_provider_not_blank
    check (length(trim(provider)) > 0),
  constraint subscription_plan_prices_cycle_check
    check (billing_cycle in ('monthly', 'annual', 'one_time')),
  constraint subscription_plan_prices_currency_check
    check (currency_code ~ '^[A-Z]{3}$'),
  constraint subscription_plan_prices_amount_check
    check (amount_minor >= 0),
  constraint subscription_plan_prices_status_check
    check (status in ('draft', 'active', 'inactive', 'archived')),
  constraint subscription_plan_prices_metadata_object
    check (jsonb_typeof(metadata) = 'object')
);

create unique index if not exists
  uq_subscription_plan_prices_contract
on public.subscription_plan_prices (
  plan_id,
  provider,
  billing_cycle,
  currency_code
);

create unique index if not exists
  uq_subscription_plan_prices_provider_plan
on public.subscription_plan_prices (
  provider,
  provider_plan_id
)
where provider_plan_id is not null;

create index if not exists
  idx_subscription_plan_prices_active
on public.subscription_plan_prices (
  provider,
  billing_cycle,
  currency_code,
  status
);

insert into public.subscription_plan_prices (
  plan_id,
  provider,
  billing_cycle,
  currency_code,
  amount_minor,
  status,
  metadata,
  created_at,
  updated_at
)
select
  sp.id,
  'manual',
  'monthly',
  sp.currency_code,
  round(coalesce(sp.price_monthly, 0) * 100)::bigint,
  case
    when sp.status = 'active' then 'active'
    else 'inactive'
  end,
  jsonb_build_object(
    'source', 'migration_020',
    'legacy_price_monthly', sp.price_monthly
  ),
  now(),
  now()
from public.subscription_plans sp
on conflict (
  plan_id,
  provider,
  billing_cycle,
  currency_code
) do update
set
  amount_minor = excluded.amount_minor,
  status = excluded.status,
  metadata =
    public.subscription_plan_prices.metadata
    || excluded.metadata,
  updated_at = now();

drop trigger if exists
  set_subscription_plan_prices_updated_at
on public.subscription_plan_prices;

create trigger set_subscription_plan_prices_updated_at
before update on public.subscription_plan_prices
for each row execute function private.set_updated_at();

-- ============================================================================
-- 4. EXPAND HOTEL SUBSCRIPTION PROVIDER/LIFECYCLE CONTRACT
-- ============================================================================

alter table public.hotel_subscriptions
  add column if not exists billing_mode text,
  add column if not exists billing_cycle text,
  add column if not exists currency_code text,
  add column if not exists amount_minor bigint,
  add column if not exists provider text,
  add column if not exists provider_customer_id text,
  add column if not exists provider_subscription_id text,
  add column if not exists provider_payment_link_id text,
  add column if not exists provider_status text,
  add column if not exists provider_metadata jsonb,
  add column if not exists current_period_start timestamptz,
  add column if not exists current_period_end timestamptz,
  add column if not exists grace_ends_at timestamptz,
  add column if not exists suspended_at timestamptz,
  add column if not exists reactivated_at timestamptz,
  add column if not exists last_payment_at timestamptz;

update public.hotel_subscriptions hs
set
  billing_mode = coalesce(
    nullif(trim(hs.billing_mode), ''),
    case
      when hs.status in ('trial', 'trialing') then 'trial'
      else 'manual'
    end
  ),
  billing_cycle = coalesce(
    nullif(trim(hs.billing_cycle), ''),
    'monthly'
  ),
  currency_code = upper(
    coalesce(
      nullif(trim(hs.currency_code), ''),
      sp.currency_code,
      h.currency_code,
      'INR'
    )
  ),
  amount_minor = coalesce(
    hs.amount_minor,
    round(coalesce(sp.price_monthly, 0) * 100)::bigint
  ),
  provider = coalesce(
    nullif(trim(hs.provider), ''),
    'manual'
  ),
  provider_metadata = coalesce(
    hs.provider_metadata,
    '{}'::jsonb
  ),
  current_period_start = coalesce(
    hs.current_period_start,
    hs.start_date
  ),
  current_period_end = coalesce(
    hs.current_period_end,
    hs.end_date
  )
from public.subscription_plans sp,
     public.hotels h
where sp.id = hs.plan_id
  and h.id = hs.hotel_id;

update public.hotel_subscriptions hs
set
  billing_mode = coalesce(hs.billing_mode, 'manual'),
  billing_cycle = coalesce(hs.billing_cycle, 'monthly'),
  currency_code = coalesce(hs.currency_code, 'INR'),
  amount_minor = coalesce(hs.amount_minor, 0),
  provider = coalesce(hs.provider, 'manual'),
  provider_metadata = coalesce(
    hs.provider_metadata,
    '{}'::jsonb
  );

alter table public.hotel_subscriptions
  alter column billing_mode set default 'manual',
  alter column billing_mode set not null,
  alter column billing_cycle set default 'monthly',
  alter column billing_cycle set not null,
  alter column currency_code set default 'INR',
  alter column currency_code set not null,
  alter column amount_minor set default 0,
  alter column amount_minor set not null,
  alter column provider set default 'manual',
  alter column provider set not null,
  alter column provider_metadata set default '{}'::jsonb,
  alter column provider_metadata set not null;

alter table public.hotel_subscriptions
  drop constraint if exists hotel_subscriptions_status_check,
  drop constraint if exists hotel_subscriptions_billing_mode_check,
  drop constraint if exists hotel_subscriptions_billing_cycle_check,
  drop constraint if exists hotel_subscriptions_currency_check,
  drop constraint if exists hotel_subscriptions_amount_check,
  drop constraint if exists hotel_subscriptions_provider_not_blank,
  drop constraint if exists hotel_subscriptions_provider_metadata_object,
  drop constraint if exists hotel_subscriptions_period_check,
  drop constraint if exists hotel_subscriptions_grace_check;

alter table public.hotel_subscriptions
  add constraint hotel_subscriptions_status_check
    check (
      status in (
        'trial',
        'trialing',
        'active',
        'past_due',
        'suspended',
        'cancelled',
        'expired'
      )
    )
    not valid,
  add constraint hotel_subscriptions_billing_mode_check
    check (
      billing_mode in (
        'trial',
        'paid',
        'manual',
        'complimentary'
      )
    )
    not valid,
  add constraint hotel_subscriptions_billing_cycle_check
    check (
      billing_cycle in (
        'monthly',
        'annual',
        'one_time',
        'none'
      )
    )
    not valid,
  add constraint hotel_subscriptions_currency_check
    check (currency_code ~ '^[A-Z]{3}$')
    not valid,
  add constraint hotel_subscriptions_amount_check
    check (amount_minor >= 0)
    not valid,
  add constraint hotel_subscriptions_provider_not_blank
    check (length(trim(provider)) > 0)
    not valid,
  add constraint hotel_subscriptions_provider_metadata_object
    check (jsonb_typeof(provider_metadata) = 'object')
    not valid,
  add constraint hotel_subscriptions_period_check
    check (
      current_period_end is null
      or current_period_start is null
      or current_period_end > current_period_start
    )
    not valid,
  add constraint hotel_subscriptions_grace_check
    check (
      grace_ends_at is null
      or current_period_end is null
      or grace_ends_at >= current_period_end
    )
    not valid;

alter table public.hotel_subscriptions
  validate constraint hotel_subscriptions_status_check,
  validate constraint hotel_subscriptions_billing_mode_check,
  validate constraint hotel_subscriptions_billing_cycle_check,
  validate constraint hotel_subscriptions_currency_check,
  validate constraint hotel_subscriptions_amount_check,
  validate constraint hotel_subscriptions_provider_not_blank,
  validate constraint hotel_subscriptions_provider_metadata_object,
  validate constraint hotel_subscriptions_period_check,
  validate constraint hotel_subscriptions_grace_check;

drop index if exists public.uq_hotel_current_subscription;

create unique index uq_hotel_current_subscription
on public.hotel_subscriptions (hotel_id)
where status in (
  'trial',
  'trialing',
  'active',
  'past_due',
  'suspended'
);

create unique index if not exists
  uq_hotel_subscriptions_provider_subscription
on public.hotel_subscriptions (
  provider,
  provider_subscription_id
)
where provider_subscription_id is not null;

create unique index if not exists
  uq_hotel_subscriptions_provider_payment_link
on public.hotel_subscriptions (
  provider,
  provider_payment_link_id
)
where provider_payment_link_id is not null;

create index if not exists
  idx_hotel_subscriptions_provider_status
on public.hotel_subscriptions (
  provider,
  provider_status,
  status
);

create index if not exists
  idx_hotel_subscriptions_period_end
on public.hotel_subscriptions (
  current_period_end,
  status
);

-- ============================================================================
-- 5. IMMUTABLE SUBSCRIPTION EVENT LEDGER
-- ============================================================================

create table if not exists public.subscription_events (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null
    references public.hotels(id) on delete cascade,
  subscription_id uuid
    references public.hotel_subscriptions(id) on delete set null,
  event_type text not null,
  event_source text not null default 'database',
  actor_user_id uuid references auth.users(id) on delete set null,
  old_status text,
  new_status text,
  old_plan_id uuid references public.subscription_plans(id)
    on delete set null,
  new_plan_id uuid references public.subscription_plans(id)
    on delete set null,
  provider text,
  provider_event_id text,
  idempotency_key text,
  details jsonb not null default '{}'::jsonb,
  old_record jsonb,
  new_record jsonb,
  occurred_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint subscription_events_event_type_not_blank
    check (length(trim(event_type)) > 0),
  constraint subscription_events_source_not_blank
    check (length(trim(event_source)) > 0),
  constraint subscription_events_details_object
    check (jsonb_typeof(details) = 'object')
);

create unique index if not exists
  uq_subscription_events_idempotency
on public.subscription_events (idempotency_key)
where idempotency_key is not null;

create unique index if not exists
  uq_subscription_events_provider_event
on public.subscription_events (
  provider,
  provider_event_id,
  event_type
)
where provider is not null
  and provider_event_id is not null;

create index if not exists
  idx_subscription_events_hotel_occurred
on public.subscription_events (
  hotel_id,
  occurred_at desc
);

create index if not exists
  idx_subscription_events_subscription_occurred
on public.subscription_events (
  subscription_id,
  occurred_at desc
);

create or replace function
  private.prevent_immutable_event_mutation_20260728()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if current_setting(
    'stayqr.allow_immutable_event_mutation',
    true
  ) = 'on' then
    if tg_op = 'DELETE' then
      return old;
    end if;

    return new;
  end if;

  raise exception
    '% is append-only; % is not permitted.',
    tg_table_name,
    tg_op;
end;
$$;

revoke all on function
  private.prevent_immutable_event_mutation_20260728()
from public, anon, authenticated;

drop trigger if exists
  prevent_subscription_event_mutation_20260728
on public.subscription_events;

create trigger
  prevent_subscription_event_mutation_20260728
before update or delete on public.subscription_events
for each row execute function
  private.prevent_immutable_event_mutation_20260728();

create or replace function
  private.log_subscription_change_20260728()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  event_name text;
  source_name text := coalesce(
    nullif(
      current_setting(
        'stayqr.subscription_event_source',
        true
      ),
      ''
    ),
    'database'
  );
  target_hotel_id uuid;
  target_subscription_id uuid;
begin
  if tg_op = 'INSERT' then
    event_name := 'subscription_created';
    target_hotel_id := new.hotel_id;
    target_subscription_id := new.id;
  elsif tg_op = 'DELETE' then
    event_name := 'subscription_deleted';
    target_hotel_id := old.hotel_id;
    target_subscription_id := old.id;
  elsif old.status is distinct from new.status then
    event_name :=
      'status_' || coalesce(old.status, 'null')
      || '_to_' || coalesce(new.status, 'null');
    target_hotel_id := new.hotel_id;
    target_subscription_id := new.id;
  elsif old.plan_id is distinct from new.plan_id then
    event_name := 'plan_changed';
    target_hotel_id := new.hotel_id;
    target_subscription_id := new.id;
  elsif old.provider_subscription_id is distinct from
        new.provider_subscription_id
     or old.provider_payment_link_id is distinct from
        new.provider_payment_link_id
     or old.provider_status is distinct from
        new.provider_status
  then
    event_name := 'provider_state_changed';
    target_hotel_id := new.hotel_id;
    target_subscription_id := new.id;
  else
    event_name := 'subscription_updated';
    target_hotel_id := new.hotel_id;
    target_subscription_id := new.id;
  end if;

  insert into public.subscription_events (
    hotel_id,
    subscription_id,
    event_type,
    event_source,
    actor_user_id,
    old_status,
    new_status,
    old_plan_id,
    new_plan_id,
    provider,
    details,
    old_record,
    new_record,
    occurred_at,
    created_at
  ) values (
    target_hotel_id,
    target_subscription_id,
    event_name,
    source_name,
    (select auth.uid()),
    case when tg_op in ('UPDATE', 'DELETE')
      then old.status end,
    case when tg_op in ('INSERT', 'UPDATE')
      then new.status end,
    case when tg_op in ('UPDATE', 'DELETE')
      then old.plan_id end,
    case when tg_op in ('INSERT', 'UPDATE')
      then new.plan_id end,
    case when tg_op = 'DELETE'
      then old.provider else new.provider end,
    jsonb_build_object(
      'trigger_operation', tg_op
    ),
    case when tg_op in ('UPDATE', 'DELETE')
      then to_jsonb(old) end,
    case when tg_op in ('INSERT', 'UPDATE')
      then to_jsonb(new) end,
    now(),
    now()
  );

  if tg_op = 'DELETE' then
    return old;
  end if;

  return new;
end;
$$;

revoke all on function
  private.log_subscription_change_20260728()
from public, anon, authenticated;

insert into public.subscription_events (
  hotel_id,
  subscription_id,
  event_type,
  event_source,
  old_status,
  new_status,
  old_plan_id,
  new_plan_id,
  provider,
  idempotency_key,
  details,
  new_record,
  occurred_at,
  created_at
)
select
  hs.hotel_id,
  hs.id,
  'legacy_snapshot',
  'migration_020',
  null,
  hs.status,
  null,
  hs.plan_id,
  hs.provider,
  'migration020:legacy-snapshot:' || hs.id::text,
  jsonb_build_object(
    'reason',
    'Initial immutable snapshot when Day 9 event ledger was introduced.'
  ),
  to_jsonb(hs),
  coalesce(hs.created_at, now()),
  now()
from public.hotel_subscriptions hs
on conflict do nothing;

drop trigger if exists
  log_subscription_change_20260728
on public.hotel_subscriptions;

create trigger log_subscription_change_20260728
after insert or update or delete on public.hotel_subscriptions
for each row execute function
  private.log_subscription_change_20260728();

-- ============================================================================
-- 6. GUARDED PRODUCTION RECONCILIATION
-- ============================================================================

-- 6.1 Expire the Apex subscription whose contractual end date has passed.
update public.hotel_subscriptions hs
set
  status = 'expired',
  provider = coalesce(hs.provider, 'manual'),
  billing_mode = coalesce(hs.billing_mode, 'manual'),
  provider_status = 'expired',
  current_period_start = coalesce(
    hs.current_period_start,
    hs.start_date
  ),
  current_period_end = coalesce(
    hs.current_period_end,
    hs.end_date
  ),
  metadata = coalesce(hs.metadata, '{}'::jsonb)
    || jsonb_build_object(
      'migration_020_reconciliation',
      jsonb_build_object(
        'reason',
        'Active row had passed end_date and was reconciled to expired.',
        'reconciled_at',
        now()
      )
    ),
  updated_at = now()
where hs.id =
    'b2870090-4736-4716-819e-56e403e930cb'::uuid
  and hs.hotel_id =
    '9e105be7-0d93-4dc9-84c6-f729b53f1368'::uuid
  and hs.status = 'active'
  and hs.end_date <= now();

update public.hotels h
set
  subscription_status = 'expired',
  updated_at = now()
where h.id =
    '9e105be7-0d93-4dc9-84c6-f729b53f1368'::uuid
  and h.subscription_status = 'trial';

-- 6.2 Give VD Stay Inn a documented, zero-MRR complimentary legacy contract.
with target_hotel as (
  select
    h.id,
    h.created_at,
    h.currency_code,
    count(r.id) as room_count
  from public.hotels h
  left join public.rooms r on r.hotel_id = h.id
  where h.id =
    '77d850d0-016d-4155-bc44-a6207d30e7b9'::uuid
  group by h.id, h.created_at, h.currency_code
),
eligible_plan as (
  select sp.id, sp.plan_name, sp.max_rooms
  from public.subscription_plans sp
  cross join target_hotel th
  where sp.status = 'active'
    and sp.max_rooms is not null
    and sp.max_rooms >= th.room_count
  order by sp.max_rooms, sp.price_monthly, sp.plan_name
  limit 1
)
insert into public.hotel_subscriptions (
  hotel_id,
  plan_id,
  status,
  start_date,
  end_date,
  created_at,
  trial_started_at,
  trial_ends_at,
  activated_at,
  metadata,
  updated_at,
  billing_mode,
  billing_cycle,
  currency_code,
  amount_minor,
  provider,
  provider_status,
  provider_metadata,
  current_period_start,
  current_period_end
)
select
  th.id,
  ep.id,
  'active',
  th.created_at,
  null,
  now(),
  null,
  null,
  now(),
  jsonb_build_object(
    'source', 'migration_020',
    'contract_type', 'legacy_complimentary',
    'reason',
    'Audit 050 proved active cached state with no subscription row.',
    'selected_plan_name', ep.plan_name,
    'selected_plan_max_rooms', ep.max_rooms,
    'room_count_at_reconciliation', th.room_count
  ),
  now(),
  'complimentary',
  'none',
  th.currency_code,
  0,
  'manual',
  'complimentary',
  jsonb_build_object(
    'source', 'legacy_reconciliation'
  ),
  th.created_at,
  null
from target_hotel th
cross join eligible_plan ep
where not exists (
  select 1
  from public.hotel_subscriptions existing
  where existing.hotel_id = th.id
    and existing.status in (
      'trial',
      'trialing',
      'active',
      'past_due',
      'suspended'
    )
);

-- Refresh legacy onboarding readiness without marking completion automatically.
update public.hotel_onboarding ho
set
  readiness_state =
    private.compute_hotel_onboarding_readiness(ho.hotel_id),
  last_saved_at = now(),
  version = ho.version + 1,
  updated_at = now()
where ho.hotel_id in (
  '77d850d0-016d-4155-bc44-a6207d30e7b9'::uuid,
  '9e105be7-0d93-4dc9-84c6-f729b53f1368'::uuid
);

-- ============================================================================
-- 7. AUTHORITATIVE USAGE COUNTERS
-- ============================================================================

create table if not exists public.usage_counters (
  hotel_id uuid not null
    references public.hotels(id) on delete cascade,
  metric_key text not null,
  current_value numeric not null default 0,
  limit_value numeric,
  source text not null default 'database',
  captured_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  primary key (hotel_id, metric_key),
  constraint usage_counters_metric_not_blank
    check (length(trim(metric_key)) > 0),
  constraint usage_counters_value_check
    check (current_value >= 0),
  constraint usage_counters_limit_check
    check (limit_value is null or limit_value >= 0),
  constraint usage_counters_source_not_blank
    check (length(trim(source)) > 0),
  constraint usage_counters_metadata_object
    check (jsonb_typeof(metadata) = 'object')
);

create index if not exists
  idx_usage_counters_metric
on public.usage_counters (
  metric_key,
  captured_at desc
);

drop trigger if exists
  set_usage_counters_updated_at
on public.usage_counters;

create trigger set_usage_counters_updated_at
before update on public.usage_counters
for each row execute function private.set_updated_at();

create or replace function
  private.refresh_subscription_usage_internal(
    target_hotel_id uuid
  )
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_plan public.subscription_plans%rowtype;
  room_count_value bigint := 0;
  active_staff_value bigint := 0;
  active_room_types_value bigint := 0;
  menu_items_value bigint := 0;
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

  select sp.*
  into current_plan
  from public.hotel_subscriptions hs
  join public.subscription_plans sp on sp.id = hs.plan_id
  where hs.hotel_id = target_hotel_id
    and hs.status in (
      'trial',
      'trialing',
      'active',
      'past_due',
      'suspended'
    )
  order by
    coalesce(hs.updated_at, hs.created_at) desc,
    hs.created_at desc,
    hs.id desc
  limit 1;

  select count(*)
  into room_count_value
  from public.rooms r
  where r.hotel_id = target_hotel_id;

  select count(*)
  into active_staff_value
  from public.staff s
  where s.hotel_id = target_hotel_id
    and s.status = 'active';

  select count(*)
  into active_room_types_value
  from public.room_types rt
  where rt.hotel_id = target_hotel_id
    and rt.is_active;

  select count(*)
  into menu_items_value
  from public.menu_items mi
  where mi.hotel_id = target_hotel_id
    and coalesce(mi.is_available, true);

  insert into public.usage_counters (
    hotel_id,
    metric_key,
    current_value,
    limit_value,
    source,
    captured_at,
    updated_at,
    metadata
  )
  values
    (
      target_hotel_id,
      'rooms',
      room_count_value,
      current_plan.max_rooms,
      'database',
      now(),
      now(),
      '{}'::jsonb
    ),
    (
      target_hotel_id,
      'active_staff',
      active_staff_value,
      current_plan.max_staff,
      'database',
      now(),
      now(),
      '{}'::jsonb
    ),
    (
      target_hotel_id,
      'active_room_types',
      active_room_types_value,
      null,
      'database',
      now(),
      now(),
      '{}'::jsonb
    ),
    (
      target_hotel_id,
      'available_menu_items',
      menu_items_value,
      null,
      'database',
      now(),
      now(),
      '{}'::jsonb
    )
  on conflict (hotel_id, metric_key) do update
  set
    current_value = excluded.current_value,
    limit_value = excluded.limit_value,
    source = excluded.source,
    captured_at = excluded.captured_at,
    metadata = excluded.metadata,
    updated_at = now();

  return jsonb_build_object(
    'hotel_id', target_hotel_id,
    'rooms', room_count_value,
    'active_staff', active_staff_value,
    'active_room_types', active_room_types_value,
    'available_menu_items', menu_items_value,
    'room_limit', current_plan.max_rooms,
    'staff_limit', current_plan.max_staff,
    'captured_at', now()
  );
end;
$$;

revoke all on function
  private.refresh_subscription_usage_internal(uuid)
from public, anon, authenticated;

do $seed_usage$
declare
  hotel_row record;
begin
  for hotel_row in
    select h.id
    from public.hotels h
    order by h.created_at, h.id
  loop
    perform private.refresh_subscription_usage_internal(
      hotel_row.id
    );
  end loop;
end;
$seed_usage$;

-- ============================================================================
-- 8. SUPPORT TICKETS AND IMMUTABLE TICKET EVENTS
-- ============================================================================

create sequence if not exists
  public.support_ticket_number_seq;

revoke all on sequence
  public.support_ticket_number_seq
from public, anon, authenticated;

create table if not exists public.support_tickets (
  id uuid primary key default gen_random_uuid(),
  ticket_number text not null default (
    'STQ-'
    || to_char(now(), 'YYYY')
    || '-'
    || lpad(
      nextval(
        'public.support_ticket_number_seq'::regclass
      )::text,
      8,
      '0'
    )
  ),
  hotel_id uuid not null
    references public.hotels(id) on delete cascade,
  subject text not null,
  description text not null,
  category text not null default 'general',
  priority text not null default 'normal',
  status text not null default 'open',
  created_by uuid not null
    references auth.users(id) on delete restrict,
  assigned_to uuid references auth.users(id) on delete set null,
  resolved_by uuid references auth.users(id) on delete set null,
  resolved_at timestamptz,
  closed_at timestamptz,
  last_response_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint support_tickets_number_not_blank
    check (length(trim(ticket_number)) > 0),
  constraint support_tickets_subject_not_blank
    check (length(trim(subject)) between 1 and 200),
  constraint support_tickets_description_not_blank
    check (length(trim(description)) > 0),
  constraint support_tickets_category_not_blank
    check (length(trim(category)) > 0),
  constraint support_tickets_priority_check
    check (priority in ('low', 'normal', 'high', 'urgent')),
  constraint support_tickets_status_check
    check (
      status in (
        'open',
        'in_progress',
        'waiting_on_hotel',
        'resolved',
        'closed'
      )
    ),
  constraint support_tickets_metadata_object
    check (jsonb_typeof(metadata) = 'object')
);

create unique index if not exists
  uq_support_tickets_ticket_number
on public.support_tickets (ticket_number);

create index if not exists
  idx_support_tickets_hotel_status
on public.support_tickets (
  hotel_id,
  status,
  priority,
  created_at desc
);

create index if not exists
  idx_support_tickets_assignee_status
on public.support_tickets (
  assigned_to,
  status,
  created_at desc
);

drop trigger if exists
  set_support_tickets_updated_at
on public.support_tickets;

create trigger set_support_tickets_updated_at
before update on public.support_tickets
for each row execute function private.set_updated_at();

create table if not exists public.support_ticket_events (
  id uuid primary key default gen_random_uuid(),
  ticket_id uuid not null
    references public.support_tickets(id) on delete cascade,
  hotel_id uuid not null
    references public.hotels(id) on delete cascade,
  event_type text not null,
  actor_user_id uuid references auth.users(id) on delete set null,
  message text,
  old_status text,
  new_status text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint support_ticket_events_type_not_blank
    check (length(trim(event_type)) > 0),
  constraint support_ticket_events_details_object
    check (jsonb_typeof(details) = 'object')
);

create index if not exists
  idx_support_ticket_events_ticket_created
on public.support_ticket_events (
  ticket_id,
  created_at
);

drop trigger if exists
  prevent_support_ticket_event_mutation_20260728
on public.support_ticket_events;

create trigger
  prevent_support_ticket_event_mutation_20260728
before update or delete on public.support_ticket_events
for each row execute function
  private.prevent_immutable_event_mutation_20260728();

-- ============================================================================
-- 9. PLATFORM ANNOUNCEMENTS
-- ============================================================================

create table if not exists public.announcements (
  id uuid primary key default gen_random_uuid(),
  scope text not null default 'global',
  target_hotel_id uuid
    references public.hotels(id) on delete cascade,
  title text not null,
  body text not null,
  severity text not null default 'info',
  status text not null default 'draft',
  starts_at timestamptz,
  ends_at timestamptz,
  created_by uuid not null
    references auth.users(id) on delete restrict,
  published_by uuid references auth.users(id) on delete set null,
  published_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint announcements_scope_check
    check (
      (scope = 'global' and target_hotel_id is null)
      or
      (scope = 'hotel' and target_hotel_id is not null)
    ),
  constraint announcements_title_not_blank
    check (length(trim(title)) between 1 and 200),
  constraint announcements_body_not_blank
    check (length(trim(body)) > 0),
  constraint announcements_severity_check
    check (severity in ('info', 'success', 'warning', 'critical')),
  constraint announcements_status_check
    check (status in ('draft', 'published', 'archived')),
  constraint announcements_dates_check
    check (
      ends_at is null
      or starts_at is null
      or ends_at > starts_at
    ),
  constraint announcements_metadata_object
    check (jsonb_typeof(metadata) = 'object')
);

create index if not exists
  idx_announcements_visibility
on public.announcements (
  status,
  scope,
  target_hotel_id,
  starts_at,
  ends_at
);

drop trigger if exists
  set_announcements_updated_at
on public.announcements;

create trigger set_announcements_updated_at
before update on public.announcements
for each row execute function private.set_updated_at();

-- ============================================================================
-- 10. EXPLICIT SAFE SUPPORT-ACCESS SESSIONS
-- ============================================================================

create table if not exists public.support_access_sessions (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null
    references public.hotels(id) on delete cascade,
  platform_admin_user_id uuid not null
    references auth.users(id) on delete restrict,
  reason text not null,
  status text not null default 'active',
  permissions text[] not null default '{}'::text[],
  started_at timestamptz not null default now(),
  expires_at timestamptz not null,
  ended_at timestamptz,
  ended_by uuid references auth.users(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint support_access_reason_not_blank
    check (length(trim(reason)) > 0),
  constraint support_access_status_check
    check (status in ('active', 'ended', 'revoked', 'expired')),
  constraint support_access_expiry_check
    check (expires_at > started_at),
  constraint support_access_end_check
    check (
      ended_at is null
      or ended_at >= started_at
    ),
  constraint support_access_metadata_object
    check (jsonb_typeof(metadata) = 'object')
);

create unique index if not exists
  uq_support_access_active_admin_hotel
on public.support_access_sessions (
  hotel_id,
  platform_admin_user_id
)
where status = 'active';

create index if not exists
  idx_support_access_expiry
on public.support_access_sessions (
  status,
  expires_at
);

drop trigger if exists
  set_support_access_sessions_updated_at
on public.support_access_sessions;

create trigger set_support_access_sessions_updated_at
before update on public.support_access_sessions
for each row execute function private.set_updated_at();

-- ============================================================================
-- 11. SIGNED WEBHOOK IDEMPOTENCY LEDGER
-- ============================================================================

create table if not exists public.webhook_events (
  id uuid primary key default gen_random_uuid(),
  provider text not null,
  provider_event_id text not null,
  event_type text not null,
  processing_status text not null default 'received',
  signature_valid boolean not null default false,
  payload_hash text,
  payload jsonb not null,
  headers jsonb not null default '{}'::jsonb,
  attempts integer not null default 0,
  last_error text,
  received_at timestamptz not null default now(),
  processing_started_at timestamptz,
  processed_at timestamptz,
  next_retry_at timestamptz,
  subscription_id uuid
    references public.hotel_subscriptions(id) on delete set null,
  hotel_id uuid references public.hotels(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint webhook_events_provider_not_blank
    check (length(trim(provider)) > 0),
  constraint webhook_events_provider_event_not_blank
    check (length(trim(provider_event_id)) > 0),
  constraint webhook_events_type_not_blank
    check (length(trim(event_type)) > 0),
  constraint webhook_events_status_check
    check (
      processing_status in (
        'received',
        'processing',
        'processed',
        'ignored',
        'failed'
      )
    ),
  constraint webhook_events_attempts_check
    check (attempts >= 0),
  constraint webhook_events_payload_object
    check (jsonb_typeof(payload) = 'object'),
  constraint webhook_events_headers_object
    check (jsonb_typeof(headers) = 'object'),
  constraint webhook_events_metadata_object
    check (jsonb_typeof(metadata) = 'object')
);

create unique index if not exists
  uq_webhook_events_provider_event
on public.webhook_events (
  provider,
  provider_event_id
);

create index if not exists
  idx_webhook_events_processing
on public.webhook_events (
  processing_status,
  next_retry_at,
  received_at
);

create index if not exists
  idx_webhook_events_subscription
on public.webhook_events (
  subscription_id,
  received_at desc
);

drop trigger if exists
  set_webhook_events_updated_at
on public.webhook_events;

create trigger set_webhook_events_updated_at
before update on public.webhook_events
for each row execute function private.set_updated_at();

-- ============================================================================
-- 12. GRANTS AND RLS
-- ============================================================================

-- Plan prices.
revoke all on public.subscription_plan_prices
from public, anon;

grant select, insert, update, delete
on public.subscription_plan_prices
to authenticated;

alter table public.subscription_plan_prices
  enable row level security;

drop policy if exists
  stayqr_subscription_plan_prices_select
on public.subscription_plan_prices;

drop policy if exists
  stayqr_subscription_plan_prices_manage
on public.subscription_plan_prices;

create policy stayqr_subscription_plan_prices_select
on public.subscription_plan_prices
for select to authenticated
using (
  private.is_platform_admin()
  or status = 'active'
);

create policy stayqr_subscription_plan_prices_manage
on public.subscription_plan_prices
for all to authenticated
using (private.is_platform_admin())
with check (private.is_platform_admin());

-- Subscription events.
revoke all on public.subscription_events
from public, anon, authenticated;

grant select on public.subscription_events
to authenticated;

alter table public.subscription_events
  enable row level security;

drop policy if exists
  stayqr_subscription_events_select
on public.subscription_events;

create policy stayqr_subscription_events_select
on public.subscription_events
for select to authenticated
using (
  private.is_platform_admin()
  or private.user_has_hotel_access(hotel_id)
);

-- Usage counters.
revoke all on public.usage_counters
from public, anon, authenticated;

grant select on public.usage_counters
to authenticated;

alter table public.usage_counters
  enable row level security;

drop policy if exists
  stayqr_usage_counters_select
on public.usage_counters;

create policy stayqr_usage_counters_select
on public.usage_counters
for select to authenticated
using (
  private.is_platform_admin()
  or private.user_has_hotel_access(hotel_id)
);

-- Support tickets.
revoke all on public.support_tickets
from public, anon, authenticated;

grant select on public.support_tickets
to authenticated;

alter table public.support_tickets
  enable row level security;

drop policy if exists
  stayqr_support_tickets_select
on public.support_tickets;

create policy stayqr_support_tickets_select
on public.support_tickets
for select to authenticated
using (
  private.is_platform_admin()
  or private.user_has_hotel_access(hotel_id)
);

-- Support ticket events.
revoke all on public.support_ticket_events
from public, anon, authenticated;

grant select on public.support_ticket_events
to authenticated;

alter table public.support_ticket_events
  enable row level security;

drop policy if exists
  stayqr_support_ticket_events_select
on public.support_ticket_events;

create policy stayqr_support_ticket_events_select
on public.support_ticket_events
for select to authenticated
using (
  private.is_platform_admin()
  or private.user_has_hotel_access(hotel_id)
);

-- Announcements.
revoke all on public.announcements
from public, anon;

grant select, insert, update, delete
on public.announcements
to authenticated;

alter table public.announcements
  enable row level security;

drop policy if exists
  stayqr_announcements_select
on public.announcements;

drop policy if exists
  stayqr_announcements_manage
on public.announcements;

create policy stayqr_announcements_select
on public.announcements
for select to authenticated
using (
  private.is_platform_admin()
  or (
    status = 'published'
    and coalesce(starts_at, '-infinity'::timestamptz)
      <= now()
    and coalesce(ends_at, 'infinity'::timestamptz)
      > now()
    and (
      scope = 'global'
      or (
        scope = 'hotel'
        and private.user_has_hotel_access(target_hotel_id)
      )
    )
  )
);

create policy stayqr_announcements_manage
on public.announcements
for all to authenticated
using (private.is_platform_admin())
with check (private.is_platform_admin());

-- Support access sessions.
revoke all on public.support_access_sessions
from public, anon, authenticated;

grant select on public.support_access_sessions
to authenticated;

alter table public.support_access_sessions
  enable row level security;

drop policy if exists
  stayqr_support_access_sessions_select
on public.support_access_sessions;

create policy stayqr_support_access_sessions_select
on public.support_access_sessions
for select to authenticated
using (
  private.is_platform_admin()
  or private.user_has_hotel_access(hotel_id)
);

-- Webhook events.
revoke all on public.webhook_events
from public, anon, authenticated;

grant select on public.webhook_events
to authenticated;

alter table public.webhook_events
  enable row level security;

drop policy if exists
  stayqr_webhook_events_select
on public.webhook_events;

create policy stayqr_webhook_events_select
on public.webhook_events
for select to authenticated
using (private.is_platform_admin());

-- ============================================================================
-- 13. POST-MIGRATION ASSERTIONS
-- ============================================================================

do $verify$
declare
  vd_hotel_id constant uuid :=
    '77d850d0-016d-4155-bc44-a6207d30e7b9'::uuid;
  apex_hotel_id constant uuid :=
    '9e105be7-0d93-4dc9-84c6-f729b53f1368'::uuid;
begin
  if not exists (
    select 1
    from public.hotel_subscriptions hs
    join public.subscription_plans sp on sp.id = hs.plan_id
    where hs.hotel_id = vd_hotel_id
      and hs.status = 'active'
      and hs.billing_mode = 'complimentary'
      and hs.amount_minor = 0
      and sp.max_rooms >= 12
  ) then
    raise exception
      'Migration 020 failed: VD Stay Inn complimentary capacity-safe subscription was not created.';
  end if;

  if not exists (
    select 1
    from public.hotel_subscriptions hs
    where hs.id =
        'b2870090-4736-4716-819e-56e403e930cb'::uuid
      and hs.hotel_id = apex_hotel_id
      and hs.status = 'expired'
  ) then
    raise exception
      'Migration 020 failed: Apex expired subscription was not reconciled.';
  end if;

  if not exists (
    select 1
    from public.hotels h
    where h.id = apex_hotel_id
      and h.subscription_status = 'expired'
  ) then
    raise exception
      'Migration 020 failed: Apex cached subscription status was not reconciled.';
  end if;

  if exists (
    select 1
    from (
      select hs.hotel_id
      from public.hotel_subscriptions hs
      where hs.status in (
        'trial',
        'trialing',
        'active',
        'past_due',
        'suspended'
      )
      group by hs.hotel_id
      having count(*) > 1
    ) duplicate_current
  ) then
    raise exception
      'Migration 020 failed: multiple current subscriptions exist.';
  end if;

  if exists (
    select 1
    from public.subscription_plans sp
    where sp.plan_code is null
       or nullif(trim(sp.plan_code), '') is null
       or sp.currency_code !~ '^[A-Z]{3}$'
  ) then
    raise exception
      'Migration 020 failed: invalid plan commercial metadata exists.';
  end if;

  if has_table_privilege(
    'anon',
    'public.subscription_events',
    'SELECT'
  ) or has_table_privilege(
    'anon',
    'public.webhook_events',
    'SELECT'
  ) or has_table_privilege(
    'anon',
    'public.support_tickets',
    'SELECT'
  ) then
    raise exception
      'Migration 020 failed: anonymous access exists on a Day 9 protected table.';
  end if;
end;
$verify$;

commit;

-- ============================================================================
-- 14. ACCEPTANCE RESULT
-- ============================================================================

with checks(test_name, passed, details) as (
  values
    (
      '01_plan_commercial_columns',
      (
        select count(*) = 9
        from information_schema.columns c
        where c.table_schema = 'public'
          and c.table_name = 'subscription_plans'
          and c.column_name in (
            'plan_code',
            'price_annual',
            'max_staff',
            'max_properties',
            'max_storage_mb',
            'trial_days',
            'currency_code',
            'is_public',
            'updated_at'
          )
      ),
      'Plan code, annual price, expandable limits, trial, currency, visibility and update fields exist.'
    ),
    (
      '02_plan_code_coverage',
      not exists (
        select 1
        from public.subscription_plans sp
        where nullif(trim(sp.plan_code), '') is null
      ),
      'Every subscription plan has a stable plan code.'
    ),
    (
      '03_plan_commercial_constraints',
      (
        select count(*) = 6
        from pg_constraint c
        where c.conrelid =
          'public.subscription_plans'::regclass
          and c.conname in (
            'subscription_plans_plan_code_not_blank',
            'subscription_plans_price_check',
            'subscription_plans_limit_check',
            'subscription_plans_trial_days_check',
            'subscription_plans_currency_check',
            'subscription_plans_status_check'
          )
          and c.convalidated
      ),
      'Plan prices, limits, trial days, currency and status are constrained.'
    ),
    (
      '04_provider_plan_prices',
      to_regclass(
        'public.subscription_plan_prices'
      ) is not null
      and not exists (
        select 1
        from public.subscription_plans sp
        where not exists (
          select 1
          from public.subscription_plan_prices spp
          where spp.plan_id = sp.id
            and spp.provider = 'manual'
            and spp.billing_cycle = 'monthly'
        )
      ),
      'Every plan has a provider-neutral monthly price row.'
    ),
    (
      '05_subscription_provider_columns',
      (
        select count(*) = 16
        from information_schema.columns c
        where c.table_schema = 'public'
          and c.table_name = 'hotel_subscriptions'
          and c.column_name in (
            'billing_mode',
            'billing_cycle',
            'currency_code',
            'amount_minor',
            'provider',
            'provider_customer_id',
            'provider_subscription_id',
            'provider_payment_link_id',
            'provider_status',
            'provider_metadata',
            'current_period_start',
            'current_period_end',
            'grace_ends_at',
            'suspended_at',
            'reactivated_at',
            'last_payment_at'
          )
      ),
      'Hotel subscriptions have complete billing/provider lifecycle fields.'
    ),
    (
      '06_current_subscription_unique_index',
      exists (
        select 1
        from pg_indexes i
        where i.schemaname = 'public'
          and i.indexname =
            'uq_hotel_current_subscription'
          and i.indexdef like '%suspended%'
      ),
      'Trial, active, past-due and suspended states share one current-subscription uniqueness boundary.'
    ),
    (
      '07_subscription_event_ledger',
      to_regclass('public.subscription_events') is not null,
      'Immutable subscription lifecycle event ledger exists.'
    ),
    (
      '08_subscription_event_immutability',
      exists (
        select 1
        from pg_trigger t
        where t.tgrelid =
          'public.subscription_events'::regclass
          and t.tgname =
            'prevent_subscription_event_mutation_20260728'
          and not t.tgisinternal
      ),
      'Subscription event update/delete protection trigger exists.'
    ),
    (
      '09_subscription_change_logging',
      exists (
        select 1
        from pg_trigger t
        where t.tgrelid =
          'public.hotel_subscriptions'::regclass
          and t.tgname =
            'log_subscription_change_20260728'
          and not t.tgisinternal
      ),
      'Every subscription insert/update/delete is event logged.'
    ),
    (
      '10_existing_subscription_snapshots',
      not exists (
        select 1
        from public.hotel_subscriptions hs
        where not exists (
          select 1
          from public.subscription_events se
          where se.subscription_id = hs.id
            and se.event_type in (
              'legacy_snapshot',
              'subscription_created'
            )
        )
      ),
      'Every existing subscription has an immutable initial snapshot or creation event.'
    ),
    (
      '11_vd_stay_inn_subscription_reconciled',
      exists (
        select 1
        from public.hotel_subscriptions hs
        where hs.hotel_id =
            '77d850d0-016d-4155-bc44-a6207d30e7b9'::uuid
          and hs.status = 'active'
          and hs.billing_mode = 'complimentary'
          and hs.amount_minor = 0
      ),
      'VD Stay Inn has a documented zero-MRR complimentary current subscription.'
    ),
    (
      '12_vd_stay_inn_plan_capacity',
      exists (
        select 1
        from public.hotel_subscriptions hs
        join public.subscription_plans sp
          on sp.id = hs.plan_id
        where hs.hotel_id =
            '77d850d0-016d-4155-bc44-a6207d30e7b9'::uuid
          and hs.status = 'active'
          and sp.max_rooms >= (
            select count(*)
            from public.rooms r
            where r.hotel_id = hs.hotel_id
          )
      ),
      'VD Stay Inn was assigned the smallest active plan that safely supports its 12 rooms.'
    ),
    (
      '13_apex_expired_reconciled',
      exists (
        select 1
        from public.hotel_subscriptions hs
        where hs.id =
            'b2870090-4736-4716-819e-56e403e930cb'::uuid
          and hs.status = 'expired'
          and hs.end_date <= now()
      ),
      'The ended Apex contract is no longer falsely active.'
    ),
    (
      '14_apex_cached_status_reconciled',
      exists (
        select 1
        from public.hotels h
        where h.id =
            '9e105be7-0d93-4dc9-84c6-f729b53f1368'::uuid
          and h.subscription_status = 'expired'
      ),
      'Apex cached subscription status matches its expired contract.'
    ),
    (
      '15_no_multiple_current_subscriptions',
      not exists (
        select 1
        from (
          select hs.hotel_id
          from public.hotel_subscriptions hs
          where hs.status in (
            'trial',
            'trialing',
            'active',
            'past_due',
            'suspended'
          )
          group by hs.hotel_id
          having count(*) > 1
        ) duplicate_current
      ),
      'No hotel has multiple current lifecycle subscriptions.'
    ),
    (
      '16_usage_counter_table',
      to_regclass('public.usage_counters') is not null,
      'Authoritative hotel usage-counter table exists.'
    ),
    (
      '17_usage_counter_coverage',
      not exists (
        select 1
        from public.hotels h
        where not exists (
          select 1
          from public.usage_counters uc
          where uc.hotel_id = h.id
            and uc.metric_key = 'rooms'
        )
        or not exists (
          select 1
          from public.usage_counters uc
          where uc.hotel_id = h.id
            and uc.metric_key = 'active_staff'
        )
      ),
      'Every hotel has room and active-staff usage counters.'
    ),
    (
      '18_support_ticket_foundation',
      to_regclass('public.support_tickets') is not null
      and to_regclass(
        'public.support_ticket_events'
      ) is not null,
      'Support ticket and immutable ticket-event tables exist.'
    ),
    (
      '19_support_ticket_event_immutability',
      exists (
        select 1
        from pg_trigger t
        where t.tgrelid =
          'public.support_ticket_events'::regclass
          and t.tgname =
            'prevent_support_ticket_event_mutation_20260728'
          and not t.tgisinternal
      ),
      'Support ticket history cannot be updated or deleted normally.'
    ),
    (
      '20_announcements_foundation',
      to_regclass('public.announcements') is not null,
      'Global and hotel-targeted announcement foundation exists.'
    ),
    (
      '21_safe_support_access_foundation',
      to_regclass(
        'public.support_access_sessions'
      ) is not null,
      'Explicit time-bound and auditable support-access session table exists.'
    ),
    (
      '22_webhook_event_ledger',
      to_regclass('public.webhook_events') is not null,
      'Provider webhook receipt and processing ledger exists.'
    ),
    (
      '23_webhook_idempotency_index',
      to_regclass(
        'public.uq_webhook_events_provider_event'
      ) is not null,
      'Provider event IDs are unique per provider.'
    ),
    (
      '24_webhook_signature_field',
      exists (
        select 1
        from information_schema.columns c
        where c.table_schema = 'public'
          and c.table_name = 'webhook_events'
          and c.column_name = 'signature_valid'
          and c.is_nullable = 'NO'
      ),
      'Every webhook event records explicit signature validation state.'
    ),
    (
      '25_new_tables_have_rls',
      (
        select bool_and(c.relrowsecurity)
        from pg_class c
        where c.oid in (
          'public.subscription_plan_prices'::regclass,
          'public.subscription_events'::regclass,
          'public.usage_counters'::regclass,
          'public.support_tickets'::regclass,
          'public.support_ticket_events'::regclass,
          'public.announcements'::regclass,
          'public.support_access_sessions'::regclass,
          'public.webhook_events'::regclass
        )
      ),
      'Every new public Day 9 table has RLS enabled.'
    ),
    (
      '26_anonymous_day9_tables_blocked',
      not has_table_privilege(
        'anon',
        'public.subscription_events',
        'SELECT'
      )
      and not has_table_privilege(
        'anon',
        'public.usage_counters',
        'SELECT'
      )
      and not has_table_privilege(
        'anon',
        'public.support_tickets',
        'SELECT'
      )
      and not has_table_privilege(
        'anon',
        'public.webhook_events',
        'SELECT'
      ),
      'Anonymous users have no direct read access to protected Day 9 tables.'
    ),
    (
      '27_reconciliation_archive',
      (
        select count(*) = 2
        from
          private.day9_subscription_reconciliation_archive_20260728
        where archive_key in (
          'vd-stay-inn-before-migration-020',
          'hotel-apex-before-migration-020'
        )
      ),
      'Both guarded production reconciliations were archived before modification.'
    ),
    (
      '28_day8_onboarding_preserved',
      to_regprocedure(
        'public.bootstrap_hotel_onboarding(jsonb)'
      ) is not null
      and to_regprocedure(
        'public.get_hotel_onboarding_readiness(uuid)'
      ) is not null
      and to_regprocedure(
        'public.import_hotel_rooms(uuid,jsonb)'
      ) is not null,
      'Locked Day 8 onboarding and inventory RPCs remain installed.'
    ),
    (
      '29_no_razorpay_secret_storage',
      not exists (
        select 1
        from information_schema.columns c
        where c.table_schema = 'public'
          and (
            c.column_name ilike '%secret%'
            or c.column_name ilike '%api_key%'
          )
          and c.table_name in (
            'subscription_plans',
            'subscription_plan_prices',
            'hotel_subscriptions',
            'webhook_events'
          )
      ),
      'No provider secret or API key column exists in public billing tables.'
    ),
    (
      '30_day9_foundation_ready',
      to_regclass('public.subscription_events') is not null
      and to_regclass('public.usage_counters') is not null
      and to_regclass('public.support_tickets') is not null
      and to_regclass('public.webhook_events') is not null,
      'Migration 020 foundation is ready for lifecycle RPCs, MRR, support actions and Razorpay Edge Functions.'
    )
)
select test_name, passed, details
from checks
order by test_name;
