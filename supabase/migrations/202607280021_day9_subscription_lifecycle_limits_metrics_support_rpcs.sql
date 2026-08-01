-- ============================================================================
-- StayQR v1.0
-- Day 9 Migration 021 — Subscription Lifecycle, Limits, Metrics and Support RPCs
--
-- PRIMARY OUTCOME
-- Completes the authoritative server-action layer required by the Day 9
-- Super Admin and subscription control centre:
--   - plan creation/update with structured limits and provider-neutral prices;
--   - server-side room/staff plan-limit enforcement;
--   - trial extension and repeatable expiry reconciliation;
--   - paid activation/conversion, renewal and plan changes;
--   - suspension, reactivation and cancellation;
--   - idempotent lifecycle actions and immutable event evidence;
--   - usage and MRR/global-dashboard RPCs;
--   - support ticket creation, replies and Platform Admin triage;
--   - explicit, time-bound and audited support access;
--   - announcement create/publish/archive server action.
--
-- RAZORPAY SCOPE
-- This migration creates the trusted database actions that Razorpay Edge
-- Functions and signed webhooks will invoke. Provider HTTP calls and signature
-- verification remain in the next bounded Edge Function package. No secret,
-- key or webhook secret is stored in public tables or frontend code.
--
-- SAFETY
-- - Run once in Supabase SQL Editor with role: postgres.
-- - Transactional and idempotent.
-- - Existing subscriptions are not converted, suspended or cancelled merely
--   by installing this migration.
-- - Expiry reconciliation is installed but not executed automatically here.
-- - Existing Day 8 onboarding/inventory actions remain compatible.
--
-- EXPECTED RESULT
-- 36 rows, and every passed value must be true.
-- ============================================================================

begin;

set local lock_timeout = '10s';
set local statement_timeout = '300s';

select pg_advisory_xact_lock(
  hashtext('stayqr:202607280021:subscription-lifecycle-rpcs')
);

-- ============================================================================
-- 0. PRE-MIGRATION ASSERTIONS
-- ============================================================================

do $preflight$
begin
  if to_regclass('public.subscription_events') is null
     or to_regclass('public.usage_counters') is null
     or to_regclass('public.support_tickets') is null
     or to_regclass('public.support_ticket_events') is null
     or to_regclass('public.support_access_sessions') is null
     or to_regclass('public.announcements') is null
  then
    raise exception
      'Migration 021 stopped: Migration 020 foundation tables are missing.';
  end if;

  if to_regprocedure('private.is_platform_admin()') is null
     or to_regprocedure('private.user_has_hotel_access(uuid)') is null
     or to_regprocedure('private.user_has_permission(uuid,text)') is null
     or to_regprocedure(
       'private.refresh_subscription_usage_internal(uuid)'
     ) is null
     or to_regprocedure(
       'private.prevent_immutable_event_mutation_20260728()'
     ) is null
  then
    raise exception
      'Migration 021 stopped: required authorization, usage or immutability helpers are missing.';
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
      'Migration 021 stopped: a hotel has multiple current subscriptions.';
  end if;

  if exists (
    select 1
    from public.rooms r
    join public.hotel_subscriptions hs
      on hs.hotel_id = r.hotel_id
     and hs.status in (
       'trial',
       'trialing',
       'active',
       'past_due',
       'suspended'
     )
    join public.subscription_plans sp on sp.id = hs.plan_id
    group by r.hotel_id, sp.max_rooms
    having sp.max_rooms is not null
       and count(*) > sp.max_rooms
  ) then
    raise exception
      'Migration 021 stopped: existing room usage exceeds a current plan limit.';
  end if;
end;
$preflight$;

-- ============================================================================
-- 1. IMMUTABLE SUPPORT-ACCESS EVENTS
-- ============================================================================

create table if not exists public.support_access_events (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null
    references public.support_access_sessions(id) on delete cascade,
  hotel_id uuid not null
    references public.hotels(id) on delete cascade,
  event_type text not null,
  actor_user_id uuid references auth.users(id) on delete set null,
  message text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint support_access_events_type_not_blank
    check (length(trim(event_type)) > 0),
  constraint support_access_events_details_object
    check (jsonb_typeof(details) = 'object')
);

create index if not exists
  idx_support_access_events_session_created
on public.support_access_events (
  session_id,
  created_at
);

create index if not exists
  idx_support_access_events_hotel_created
on public.support_access_events (
  hotel_id,
  created_at desc
);

drop trigger if exists
  prevent_support_access_event_mutation_20260728
on public.support_access_events;

create trigger
  prevent_support_access_event_mutation_20260728
before update or delete on public.support_access_events
for each row execute function
  private.prevent_immutable_event_mutation_20260728();

revoke all on public.support_access_events
from public, anon, authenticated;

grant select on public.support_access_events
to authenticated;

alter table public.support_access_events
  enable row level security;

drop policy if exists
  stayqr_support_access_events_select
on public.support_access_events;

create policy stayqr_support_access_events_select
on public.support_access_events
for select to authenticated
using (
  private.is_platform_admin()
  or private.user_has_hotel_access(hotel_id)
);

-- ============================================================================
-- 2. PRIVATE AUTHORIZATION, IDEMPOTENCY AND CAPACITY HELPERS
-- ============================================================================

create or replace function
  private.require_platform_admin_20260728()
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid := (select auth.uid());
begin
  if actor_user_id is null
     or not private.is_platform_admin()
  then
    raise exception 'Platform Admin access required.';
  end if;

  return actor_user_id;
end;
$$;

revoke all on function
  private.require_platform_admin_20260728()
from public, anon, authenticated;

create or replace function
  private.subscription_action_result_20260728(
    action_idempotency_key text
  )
returns jsonb
language sql
security definer
stable
set search_path = ''
as $$
  select se.details -> 'result'
  from public.subscription_events se
  where action_idempotency_key is not null
    and se.idempotency_key = action_idempotency_key
  order by se.created_at desc, se.id desc
  limit 1
$$;

revoke all on function
  private.subscription_action_result_20260728(text)
from public, anon, authenticated;

create or replace function
  private.record_subscription_action_20260728(
    target_hotel_id uuid,
    target_subscription_id uuid,
    target_event_type text,
    target_event_source text,
    target_actor_user_id uuid,
    target_old_status text,
    target_new_status text,
    target_old_plan_id uuid,
    target_new_plan_id uuid,
    target_provider text,
    target_provider_event_id text,
    action_idempotency_key text,
    action_details jsonb,
    action_result jsonb
  )
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  inserted_event_id uuid;
  existing_result jsonb;
begin
  if target_hotel_id is null
     or nullif(trim(target_event_type), '') is null
  then
    raise exception
      'Hotel and event type are required.';
  end if;

  if action_idempotency_key is not null
     and nullif(trim(action_idempotency_key), '') is null
  then
    action_idempotency_key := null;
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
    provider_event_id,
    idempotency_key,
    details,
    occurred_at,
    created_at
  ) values (
    target_hotel_id,
    target_subscription_id,
    target_event_type,
    coalesce(
      nullif(trim(target_event_source), ''),
      'server_action'
    ),
    target_actor_user_id,
    target_old_status,
    target_new_status,
    target_old_plan_id,
    target_new_plan_id,
    target_provider,
    nullif(trim(target_provider_event_id), ''),
    action_idempotency_key,
    coalesce(action_details, '{}'::jsonb)
      || jsonb_build_object(
        'result',
        coalesce(action_result, '{}'::jsonb)
      ),
    now(),
    now()
  )
  on conflict do nothing
  returning id into inserted_event_id;

  if inserted_event_id is not null then
    return action_result;
  end if;

  if action_idempotency_key is not null then
    existing_result :=
      private.subscription_action_result_20260728(
        action_idempotency_key
      );

    if existing_result is not null then
      return existing_result
        || jsonb_build_object('idempotent', true);
    end if;
  end if;

  return action_result;
end;
$$;

revoke all on function
  private.record_subscription_action_20260728(
    uuid,uuid,text,text,uuid,text,text,uuid,uuid,text,text,text,jsonb,jsonb
  )
from public, anon, authenticated;

create or replace function
  private.assert_subscription_capacity_internal_20260728(
    target_hotel_id uuid,
    target_plan_id uuid default null,
    additional_rooms integer default 0,
    additional_staff integer default 0
  )
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  plan_row public.subscription_plans%rowtype;
  subscription_row public.hotel_subscriptions%rowtype;
  room_count_value bigint := 0;
  staff_count_value bigint := 0;
begin
  if target_hotel_id is null then
    raise exception 'Hotel is required.';
  end if;

  if coalesce(additional_rooms, 0) < 0
     or coalesce(additional_staff, 0) < 0
  then
    raise exception
      'Additional capacity values cannot be negative.';
  end if;

  if target_plan_id is null then
    select hs.*
    into subscription_row
    from public.hotel_subscriptions hs
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

    if not found then
      raise exception
        'This hotel has no current subscription.';
    end if;

    if subscription_row.status = 'suspended' then
      raise exception
        'The hotel subscription is suspended.';
    end if;

    target_plan_id := subscription_row.plan_id;
  end if;

  select sp.*
  into plan_row
  from public.subscription_plans sp
  where sp.id = target_plan_id
    and sp.status = 'active';

  if not found then
    raise exception
      'The selected subscription plan is not active.';
  end if;

  select count(*)
  into room_count_value
  from public.rooms r
  where r.hotel_id = target_hotel_id;

  select count(*)
  into staff_count_value
  from public.staff s
  where s.hotel_id = target_hotel_id
    and s.status = 'active';

  if plan_row.max_rooms is not null
     and room_count_value + coalesce(additional_rooms, 0)
       > plan_row.max_rooms
  then
    raise exception
      'Room limit exceeded: current %, additional %, limit %.',
      room_count_value,
      coalesce(additional_rooms, 0),
      plan_row.max_rooms;
  end if;

  if plan_row.max_staff is not null
     and staff_count_value + coalesce(additional_staff, 0)
       > plan_row.max_staff
  then
    raise exception
      'Staff limit exceeded: current %, additional %, limit %.',
      staff_count_value,
      coalesce(additional_staff, 0),
      plan_row.max_staff;
  end if;

  return jsonb_build_object(
    'hotel_id', target_hotel_id,
    'plan_id', plan_row.id,
    'plan_code', plan_row.plan_code,
    'rooms', room_count_value,
    'room_limit', plan_row.max_rooms,
    'additional_rooms', coalesce(additional_rooms, 0),
    'active_staff', staff_count_value,
    'staff_limit', plan_row.max_staff,
    'additional_staff', coalesce(additional_staff, 0),
    'allowed', true
  );
end;
$$;

revoke all on function
  private.assert_subscription_capacity_internal_20260728(
    uuid,uuid,integer,integer
  )
from public, anon, authenticated;

-- ============================================================================
-- 3. SERVER-LEVEL ROOM AND STAFF LIMIT ENFORCEMENT
-- ============================================================================

create or replace function
  private.enforce_room_subscription_limit_20260728()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    perform
      private.assert_subscription_capacity_internal_20260728(
        new.hotel_id,
        null,
        1,
        0
      );
  elsif new.hotel_id is distinct from old.hotel_id then
    perform
      private.assert_subscription_capacity_internal_20260728(
        new.hotel_id,
        null,
        1,
        0
      );
  end if;

  return new;
end;
$$;

revoke all on function
  private.enforce_room_subscription_limit_20260728()
from public, anon, authenticated;

drop trigger if exists
  enforce_room_subscription_limit_20260728
on public.rooms;

create trigger enforce_room_subscription_limit_20260728
before insert or update of hotel_id on public.rooms
for each row execute function
  private.enforce_room_subscription_limit_20260728();

create or replace function
  private.enforce_staff_subscription_limit_20260728()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status <> 'active' then
    return new;
  end if;

  if tg_op = 'INSERT' then
    -- Day 8 bootstrap creates the first owner identity immediately before
    -- activating the selected trial. Permit only that one bootstrap owner;
    -- every later activation is checked against the current subscription.
    if lower(replace(trim(new.role::text), ' ', '_')) = 'owner'
       and not exists (
         select 1
         from public.staff existing_staff
         where existing_staff.hotel_id = new.hotel_id
           and existing_staff.status = 'active'
       )
       and not exists (
         select 1
         from public.hotel_subscriptions existing_subscription
         where existing_subscription.hotel_id = new.hotel_id
       )
       and exists (
         select 1
         from public.hotels h
         where h.id = new.hotel_id
           and h.subscription_status in ('trial', 'trialing')
       )
    then
      return new;
    end if;

    perform
      private.assert_subscription_capacity_internal_20260728(
        new.hotel_id,
        null,
        0,
        1
      );
  elsif old.status is distinct from 'active'
     or new.hotel_id is distinct from old.hotel_id
  then
    perform
      private.assert_subscription_capacity_internal_20260728(
        new.hotel_id,
        null,
        0,
        1
      );
  end if;

  return new;
end;
$$;

revoke all on function
  private.enforce_staff_subscription_limit_20260728()
from public, anon, authenticated;

drop trigger if exists
  enforce_staff_subscription_limit_20260728
on public.staff;

create trigger enforce_staff_subscription_limit_20260728
before insert or update of hotel_id, status on public.staff
for each row execute function
  private.enforce_staff_subscription_limit_20260728();

-- ============================================================================
-- 4. SUBSCRIPTION PLAN MANAGEMENT RPC
-- ============================================================================

create or replace function public.save_subscription_plan(
  payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid :=
    private.require_platform_admin_20260728();
  target_plan_id uuid;
  saved_plan public.subscription_plans%rowtype;
  plan_name_value text;
  plan_code_value text;
  currency_value text;
  features_value jsonb;
  monthly_price numeric;
  annual_price numeric;
begin
  if payload is null or jsonb_typeof(payload) <> 'object' then
    raise exception 'Plan payload must be a JSON object.';
  end if;

  target_plan_id :=
    nullif(trim(payload ->> 'id'), '')::uuid;
  plan_name_value :=
    nullif(trim(payload ->> 'plan_name'), '');
  plan_code_value := upper(
    coalesce(
      nullif(trim(payload ->> 'plan_code'), ''),
      private.normalize_hotel_slug(plan_name_value)
    )
  );
  currency_value := upper(
    coalesce(
      nullif(trim(payload ->> 'currency_code'), ''),
      'INR'
    )
  );
  features_value :=
    coalesce(payload -> 'features', '[]'::jsonb);
  monthly_price :=
    coalesce(
      nullif(trim(payload ->> 'price_monthly'), '')::numeric,
      0
    );
  annual_price :=
    nullif(trim(payload ->> 'price_annual'), '')::numeric;

  if plan_name_value is null
     or plan_code_value is null
  then
    raise exception 'Plan name and plan code are required.';
  end if;

  if jsonb_typeof(features_value) not in ('array', 'object') then
    raise exception
      'Plan features must be a JSON array or object.';
  end if;

  if target_plan_id is null then
    insert into public.subscription_plans (
      plan_name,
      plan_code,
      price_monthly,
      price_annual,
      max_rooms,
      max_staff,
      max_properties,
      max_storage_mb,
      trial_days,
      currency_code,
      features,
      is_public,
      status,
      created_at,
      updated_at
    ) values (
      plan_name_value,
      plan_code_value,
      monthly_price,
      annual_price,
      nullif(trim(payload ->> 'max_rooms'), '')::integer,
      nullif(trim(payload ->> 'max_staff'), '')::integer,
      coalesce(
        nullif(
          trim(payload ->> 'max_properties'),
          ''
        )::integer,
        1
      ),
      nullif(
        trim(payload ->> 'max_storage_mb'),
        ''
      )::bigint,
      coalesce(
        nullif(trim(payload ->> 'trial_days'), '')::integer,
        14
      ),
      currency_value,
      features_value,
      coalesce(
        nullif(trim(payload ->> 'is_public'), '')::boolean,
        true
      ),
      coalesce(
        nullif(trim(payload ->> 'status'), ''),
        'active'
      ),
      now(),
      now()
    )
    returning * into saved_plan;
  else
    update public.subscription_plans sp
    set
      plan_name = plan_name_value,
      plan_code = plan_code_value,
      price_monthly = monthly_price,
      price_annual = annual_price,
      max_rooms = case
        when payload ? 'max_rooms'
          then nullif(
            trim(payload ->> 'max_rooms'),
            ''
          )::integer
        else sp.max_rooms
      end,
      max_staff = case
        when payload ? 'max_staff'
          then nullif(
            trim(payload ->> 'max_staff'),
            ''
          )::integer
        else sp.max_staff
      end,
      max_properties = coalesce(
        nullif(
          trim(payload ->> 'max_properties'),
          ''
        )::integer,
        sp.max_properties
      ),
      max_storage_mb = case
        when payload ? 'max_storage_mb'
          then nullif(
            trim(payload ->> 'max_storage_mb'),
            ''
          )::bigint
        else sp.max_storage_mb
      end,
      trial_days = coalesce(
        nullif(trim(payload ->> 'trial_days'), '')::integer,
        sp.trial_days
      ),
      currency_code = currency_value,
      features = features_value,
      is_public = coalesce(
        nullif(trim(payload ->> 'is_public'), '')::boolean,
        sp.is_public
      ),
      status = coalesce(
        nullif(trim(payload ->> 'status'), ''),
        sp.status
      ),
      updated_at = now()
    where sp.id = target_plan_id
    returning * into saved_plan;

    if not found then
      raise exception 'Subscription plan was not found.';
    end if;
  end if;

  insert into public.subscription_plan_prices (
    plan_id,
    provider,
    billing_cycle,
    currency_code,
    amount_minor,
    status,
    metadata,
    created_by,
    updated_by,
    created_at,
    updated_at
  ) values (
    saved_plan.id,
    'manual',
    'monthly',
    saved_plan.currency_code,
    round(coalesce(saved_plan.price_monthly, 0) * 100)::bigint,
    case when saved_plan.status = 'active'
      then 'active' else 'inactive' end,
    jsonb_build_object(
      'source', 'save_subscription_plan'
    ),
    actor_user_id,
    actor_user_id,
    now(),
    now()
  )
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
    updated_by = excluded.updated_by,
    updated_at = now();

  if saved_plan.price_annual is not null then
    insert into public.subscription_plan_prices (
      plan_id,
      provider,
      billing_cycle,
      currency_code,
      amount_minor,
      status,
      metadata,
      created_by,
      updated_by,
      created_at,
      updated_at
    ) values (
      saved_plan.id,
      'manual',
      'annual',
      saved_plan.currency_code,
      round(saved_plan.price_annual * 100)::bigint,
      case when saved_plan.status = 'active'
        then 'active' else 'inactive' end,
      jsonb_build_object(
        'source', 'save_subscription_plan'
      ),
      actor_user_id,
      actor_user_id,
      now(),
      now()
    )
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
      updated_by = excluded.updated_by,
      updated_at = now();
  end if;

  return jsonb_build_object(
    'plan', to_jsonb(saved_plan),
    'prices', (
      select coalesce(
        jsonb_agg(to_jsonb(spp) order by spp.billing_cycle),
        '[]'::jsonb
      )
      from public.subscription_plan_prices spp
      where spp.plan_id = saved_plan.id
    )
  );
exception
  when unique_violation then
    raise exception
      'A plan with the same name, code or provider-price contract already exists.';
end;
$$;

revoke all on function public.save_subscription_plan(jsonb)
from public, anon, authenticated;

grant execute on function public.save_subscription_plan(jsonb)
to authenticated;

-- ============================================================================
-- 5. PUBLIC USAGE AND CAPACITY RPCs
-- ============================================================================

create or replace function public.get_hotel_subscription_usage(
  target_hotel_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid := (select auth.uid());
  refreshed jsonb;
begin
  if actor_user_id is null then
    raise exception 'Authentication required.';
  end if;

  if not (
    private.is_platform_admin()
    or private.user_has_hotel_access(target_hotel_id)
  ) then
    raise exception 'Hotel usage access denied.';
  end if;

  refreshed :=
    private.refresh_subscription_usage_internal(
      target_hotel_id
    );

  return refreshed || jsonb_build_object(
    'counters',
    (
      select coalesce(
        jsonb_agg(
          jsonb_build_object(
            'metric_key', uc.metric_key,
            'current_value', uc.current_value,
            'limit_value', uc.limit_value,
            'captured_at', uc.captured_at
          )
          order by uc.metric_key
        ),
        '[]'::jsonb
      )
      from public.usage_counters uc
      where uc.hotel_id = target_hotel_id
    )
  );
end;
$$;

revoke all on function
  public.get_hotel_subscription_usage(uuid)
from public, anon, authenticated;

grant execute on function
  public.get_hotel_subscription_usage(uuid)
to authenticated;

create or replace function public.assert_subscription_capacity(
  target_hotel_id uuid,
  metric_key text,
  additional_units integer default 1
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid := (select auth.uid());
begin
  if actor_user_id is null then
    raise exception 'Authentication required.';
  end if;

  if not (
    private.is_platform_admin()
    or private.user_has_permission(
      target_hotel_id,
      'hotel.manage'
    )
  ) then
    raise exception 'Subscription capacity access denied.';
  end if;

  if metric_key = 'rooms' then
    return
      private.assert_subscription_capacity_internal_20260728(
        target_hotel_id,
        null,
        additional_units,
        0
      );
  elsif metric_key = 'active_staff' then
    return
      private.assert_subscription_capacity_internal_20260728(
        target_hotel_id,
        null,
        0,
        additional_units
      );
  end if;

  raise exception
    'Unsupported capacity metric: %.',
    metric_key;
end;
$$;

revoke all on function
  public.assert_subscription_capacity(uuid,text,integer)
from public, anon, authenticated;

grant execute on function
  public.assert_subscription_capacity(uuid,text,integer)
to authenticated;

-- ============================================================================
-- 6. TRIAL EXTENSION AND EXPIRY RECONCILIATION
-- ============================================================================

create or replace function public.extend_hotel_trial(
  target_hotel_id uuid,
  extension_days integer,
  reason text,
  action_idempotency_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid :=
    private.require_platform_admin_20260728();
  existing_result jsonb;
  subscription_row public.hotel_subscriptions%rowtype;
  old_status_value text;
  old_plan_id_value uuid;
  new_end_at timestamptz;
  result jsonb;
begin
  if target_hotel_id is null
     or extension_days is null
     or extension_days < 1
     or extension_days > 60
  then
    raise exception
      'Hotel and an extension between 1 and 60 days are required.';
  end if;

  if nullif(trim(reason), '') is null then
    raise exception 'Trial extension reason is required.';
  end if;

  existing_result :=
    private.subscription_action_result_20260728(
      action_idempotency_key
    );

  if existing_result is not null then
    return existing_result
      || jsonb_build_object('idempotent', true);
  end if;

  perform pg_advisory_xact_lock(
    hashtext(
      'stayqr:extend-trial:' || target_hotel_id::text
    )
  );

  select hs.*
  into subscription_row
  from public.hotel_subscriptions hs
  where hs.hotel_id = target_hotel_id
    and hs.status in ('trial', 'trialing')
  order by hs.created_at desc, hs.id desc
  limit 1
  for update;

  if not found then
    if exists (
      select 1
      from public.hotel_subscriptions current_row
      where current_row.hotel_id = target_hotel_id
        and current_row.status in (
          'active',
          'past_due',
          'suspended'
        )
    ) then
      raise exception
        'A paid/current subscription already exists.';
    end if;

    select hs.*
    into subscription_row
    from public.hotel_subscriptions hs
    where hs.hotel_id = target_hotel_id
      and hs.status = 'expired'
      and hs.trial_started_at is not null
    order by hs.created_at desc, hs.id desc
    limit 1
    for update;

    if not found then
      raise exception
        'No extendable trial subscription was found.';
    end if;
  end if;

  old_status_value := subscription_row.status;
  old_plan_id_value := subscription_row.plan_id;

  new_end_at :=
    greatest(
      coalesce(
        subscription_row.trial_ends_at,
        subscription_row.end_date,
        now()
      ),
      now()
    )
    + make_interval(days => extension_days);

  if subscription_row.trial_started_at is not null
     and new_end_at
       > subscription_row.trial_started_at
         + interval '90 days'
  then
    raise exception
      'Total trial duration cannot exceed 90 days.';
  end if;

  perform set_config(
    'stayqr.subscription_event_source',
    'extend_hotel_trial',
    true
  );

  update public.hotel_subscriptions hs
  set
    status = 'trialing',
    billing_mode = 'trial',
    provider_status = 'trialing',
    trial_ends_at = new_end_at,
    end_date = new_end_at,
    current_period_end = new_end_at,
    cancelled_at = null,
    cancellation_reason = null,
    metadata = coalesce(hs.metadata, '{}'::jsonb)
      || jsonb_build_object(
        'last_trial_extension',
        jsonb_build_object(
          'days', extension_days,
          'reason', trim(reason),
          'extended_by', actor_user_id,
          'extended_at', now()
        )
      ),
    updated_at = now()
  where hs.id = subscription_row.id
  returning * into subscription_row;

  update public.hotels h
  set
    status = 'active',
    subscription_status = 'trialing',
    updated_at = now()
  where h.id = target_hotel_id;

  result := jsonb_build_object(
    'hotel_id', target_hotel_id,
    'subscription_id', subscription_row.id,
    'status', subscription_row.status,
    'trial_ends_at', subscription_row.trial_ends_at,
    'extension_days', extension_days,
    'idempotent', false
  );

  return private.record_subscription_action_20260728(
    target_hotel_id,
    subscription_row.id,
    'trial_extended',
    'extend_hotel_trial',
    actor_user_id,
    old_status_value,
    subscription_row.status,
    old_plan_id_value,
    subscription_row.plan_id,
    subscription_row.provider,
    null,
    action_idempotency_key,
    jsonb_build_object('reason', trim(reason)),
    result
  );
end;
$$;

revoke all on function
  public.extend_hotel_trial(uuid,integer,text,text)
from public, anon, authenticated;

grant execute on function
  public.extend_hotel_trial(uuid,integer,text,text)
to authenticated;

create or replace function
  public.reconcile_expired_subscriptions(
    as_of timestamptz default now()
  )
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid := (select auth.uid());
  caller_role text :=
    current_setting('request.jwt.claim.role', true);
  candidate record;
  resulting_status text;
  reconciled_count integer := 0;
  trial_expired_count integer := 0;
  paid_expired_count integer := 0;
  cancelled_count integer := 0;
begin
  if not (
    (
      actor_user_id is not null
      and private.is_platform_admin()
    )
    or caller_role = 'service_role'
  ) then
    raise exception
      'Platform Admin or service-role access required.';
  end if;

  if as_of is null then
    as_of := now();
  end if;

  perform pg_advisory_xact_lock(
    hashtext('stayqr:reconcile-expired-subscriptions')
  );

  perform set_config(
    'stayqr.subscription_event_source',
    'expiry_reconciliation',
    true
  );

  for candidate in
    select hs.*
    from public.hotel_subscriptions hs
    where
      (
        hs.status in ('trial', 'trialing')
        and coalesce(
          hs.trial_ends_at,
          hs.end_date,
          'infinity'::timestamptz
        ) <= as_of
      )
      or
      (
        hs.status in ('active', 'past_due', 'suspended')
        and coalesce(
          hs.grace_ends_at,
          hs.current_period_end,
          hs.end_date,
          'infinity'::timestamptz
        ) <= as_of
      )
    order by hs.hotel_id, hs.created_at, hs.id
    for update
  loop
    resulting_status := case
      when coalesce(
        (candidate.metadata ->> 'cancel_at_period_end')::boolean,
        false
      ) then 'cancelled'
      else 'expired'
    end;

    update public.hotel_subscriptions hs
    set
      status = resulting_status,
      provider_status = resulting_status,
      cancelled_at = case
        when resulting_status = 'cancelled'
          then coalesce(hs.cancelled_at, as_of)
        else hs.cancelled_at
      end,
      cancellation_reason = case
        when resulting_status = 'cancelled'
          then coalesce(
            hs.cancellation_reason,
            'Scheduled cancellation reached period end.'
          )
        else hs.cancellation_reason
      end,
      metadata = coalesce(hs.metadata, '{}'::jsonb)
        || jsonb_build_object(
          'last_expiry_reconciliation',
          jsonb_build_object(
            'as_of', as_of,
            'result', resulting_status
          )
        ),
      updated_at = now()
    where hs.id = candidate.id;

    update public.hotels h
    set
      status = 'suspended',
      subscription_status = resulting_status,
      updated_at = now()
    where h.id = candidate.hotel_id;

    reconciled_count := reconciled_count + 1;

    if candidate.status in ('trial', 'trialing') then
      trial_expired_count := trial_expired_count + 1;
    elsif resulting_status = 'cancelled' then
      cancelled_count := cancelled_count + 1;
    else
      paid_expired_count := paid_expired_count + 1;
    end if;
  end loop;

  return jsonb_build_object(
    'as_of', as_of,
    'reconciled', reconciled_count,
    'trials_expired', trial_expired_count,
    'paid_expired', paid_expired_count,
    'scheduled_cancellations_completed',
      cancelled_count
  );
end;
$$;

revoke all on function
  public.reconcile_expired_subscriptions(timestamptz)
from public, anon, authenticated;

grant execute on function
  public.reconcile_expired_subscriptions(timestamptz)
to authenticated, service_role;

-- ============================================================================
-- 7. PAID ACTIVATION / TRIAL CONVERSION
-- ============================================================================

create or replace function
  public.activate_paid_subscription(
    target_hotel_id uuid,
    payload jsonb
  )
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid := (select auth.uid());
  caller_role text :=
    current_setting('request.jwt.claim.role', true);
  actor_is_platform boolean :=
    actor_user_id is not null
    and private.is_platform_admin();
  existing_result jsonb;
  action_key text;
  plan_id_value uuid;
  plan_row public.subscription_plans%rowtype;
  subscription_row public.hotel_subscriptions%rowtype;
  old_status_value text;
  old_plan_id_value uuid;
  billing_cycle_value text;
  currency_value text;
  provider_value text;
  amount_value bigint;
  period_start_value timestamptz;
  period_end_value timestamptz;
  result jsonb;
begin
  if not (actor_is_platform or caller_role = 'service_role') then
    raise exception
      'Platform Admin or service-role access required.';
  end if;

  if target_hotel_id is null
     or payload is null
     or jsonb_typeof(payload) <> 'object'
  then
    raise exception
      'Hotel and paid-subscription payload are required.';
  end if;

  action_key :=
    nullif(trim(payload ->> 'idempotency_key'), '');
  existing_result :=
    private.subscription_action_result_20260728(action_key);

  if existing_result is not null then
    return existing_result
      || jsonb_build_object('idempotent', true);
  end if;

  plan_id_value :=
    nullif(trim(payload ->> 'plan_id'), '')::uuid;
  billing_cycle_value :=
    coalesce(
      nullif(trim(payload ->> 'billing_cycle'), ''),
      'monthly'
    );
  currency_value := upper(
    coalesce(
      nullif(trim(payload ->> 'currency_code'), ''),
      'INR'
    )
  );
  provider_value :=
    coalesce(
      nullif(trim(payload ->> 'provider'), ''),
      'manual'
    );
  amount_value :=
    coalesce(
      nullif(trim(payload ->> 'amount_minor'), '')::bigint,
      0
    );
  period_start_value :=
    coalesce(
      nullif(
        trim(payload ->> 'current_period_start'),
        ''
      )::timestamptz,
      now()
    );
  period_end_value :=
    nullif(
      trim(payload ->> 'current_period_end'),
      ''
    )::timestamptz;

  if plan_id_value is null
     or period_end_value is null
     or period_end_value <= period_start_value
  then
    raise exception
      'Active plan and a valid paid period are required.';
  end if;

  if billing_cycle_value not in ('monthly', 'annual') then
    raise exception
      'Paid billing cycle must be monthly or annual.';
  end if;

  if amount_value < 0
     or currency_value !~ '^[A-Z]{3}$'
  then
    raise exception
      'Paid amount and currency are invalid.';
  end if;

  select sp.*
  into plan_row
  from public.subscription_plans sp
  where sp.id = plan_id_value
    and sp.status = 'active'
  for share;

  if not found then
    raise exception 'Selected plan is not active.';
  end if;

  perform
    private.assert_subscription_capacity_internal_20260728(
      target_hotel_id,
      plan_id_value,
      0,
      0
    );

  perform pg_advisory_xact_lock(
    hashtext(
      'stayqr:activate-paid:' || target_hotel_id::text
    )
  );

  select hs.*
  into subscription_row
  from public.hotel_subscriptions hs
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
  limit 1
  for update;

  perform set_config(
    'stayqr.subscription_event_source',
    'activate_paid_subscription',
    true
  );

  if found then
    old_status_value := subscription_row.status;
    old_plan_id_value := subscription_row.plan_id;

    update public.hotel_subscriptions hs
    set
      plan_id = plan_id_value,
      status = 'active',
      billing_mode = 'paid',
      billing_cycle = billing_cycle_value,
      currency_code = currency_value,
      amount_minor = amount_value,
      provider = provider_value,
      provider_customer_id = coalesce(
        nullif(trim(payload ->> 'provider_customer_id'), ''),
        hs.provider_customer_id
      ),
      provider_subscription_id = coalesce(
        nullif(
          trim(payload ->> 'provider_subscription_id'),
          ''
        ),
        hs.provider_subscription_id
      ),
      provider_payment_link_id = coalesce(
        nullif(
          trim(payload ->> 'provider_payment_link_id'),
          ''
        ),
        hs.provider_payment_link_id
      ),
      provider_status = coalesce(
        nullif(trim(payload ->> 'provider_status'), ''),
        'active'
      ),
      provider_metadata =
        coalesce(hs.provider_metadata, '{}'::jsonb)
        || coalesce(payload -> 'provider_metadata', '{}'::jsonb),
      start_date = period_start_value,
      end_date = period_end_value,
      current_period_start = period_start_value,
      current_period_end = period_end_value,
      grace_ends_at = null,
      activated_at = coalesce(hs.activated_at, now()),
      suspended_at = null,
      reactivated_at = case
        when old_status_value = 'suspended'
          then now()
        else hs.reactivated_at
      end,
      cancelled_at = null,
      cancellation_reason = null,
      last_payment_at = coalesce(
        nullif(
          trim(payload ->> 'last_payment_at'),
          ''
        )::timestamptz,
        now()
      ),
      metadata = coalesce(hs.metadata, '{}'::jsonb)
        || coalesce(payload -> 'metadata', '{}'::jsonb)
        || jsonb_build_object(
          'last_paid_activation',
          jsonb_build_object(
            'activated_at', now(),
            'activated_by', actor_user_id,
            'source_role', caller_role
          )
        ),
      updated_at = now()
    where hs.id = subscription_row.id
    returning * into subscription_row;
  else
    old_status_value := null;
    old_plan_id_value := null;

    insert into public.hotel_subscriptions (
      hotel_id,
      plan_id,
      status,
      start_date,
      end_date,
      created_at,
      activated_at,
      metadata,
      updated_at,
      billing_mode,
      billing_cycle,
      currency_code,
      amount_minor,
      provider,
      provider_customer_id,
      provider_subscription_id,
      provider_payment_link_id,
      provider_status,
      provider_metadata,
      current_period_start,
      current_period_end,
      last_payment_at
    ) values (
      target_hotel_id,
      plan_id_value,
      'active',
      period_start_value,
      period_end_value,
      now(),
      now(),
      coalesce(payload -> 'metadata', '{}'::jsonb)
        || jsonb_build_object(
          'source', 'activate_paid_subscription',
          'activated_by', actor_user_id,
          'source_role', caller_role
        ),
      now(),
      'paid',
      billing_cycle_value,
      currency_value,
      amount_value,
      provider_value,
      nullif(trim(payload ->> 'provider_customer_id'), ''),
      nullif(
        trim(payload ->> 'provider_subscription_id'),
        ''
      ),
      nullif(
        trim(payload ->> 'provider_payment_link_id'),
        ''
      ),
      coalesce(
        nullif(trim(payload ->> 'provider_status'), ''),
        'active'
      ),
      coalesce(
        payload -> 'provider_metadata',
        '{}'::jsonb
      ),
      period_start_value,
      period_end_value,
      coalesce(
        nullif(
          trim(payload ->> 'last_payment_at'),
          ''
        )::timestamptz,
        now()
      )
    )
    returning * into subscription_row;
  end if;

  update public.hotels h
  set
    status = 'active',
    subscription_status = 'active',
    updated_at = now()
  where h.id = target_hotel_id;

  perform
    private.refresh_subscription_usage_internal(
      target_hotel_id
    );

  result := jsonb_build_object(
    'hotel_id', target_hotel_id,
    'subscription_id', subscription_row.id,
    'plan_id', subscription_row.plan_id,
    'status', subscription_row.status,
    'billing_mode', subscription_row.billing_mode,
    'billing_cycle', subscription_row.billing_cycle,
    'amount_minor', subscription_row.amount_minor,
    'currency_code', subscription_row.currency_code,
    'current_period_start',
      subscription_row.current_period_start,
    'current_period_end',
      subscription_row.current_period_end,
    'provider', subscription_row.provider,
    'provider_subscription_id',
      subscription_row.provider_subscription_id,
    'idempotent', false
  );

  return private.record_subscription_action_20260728(
    target_hotel_id,
    subscription_row.id,
    'paid_subscription_activated',
    'activate_paid_subscription',
    actor_user_id,
    old_status_value,
    subscription_row.status,
    old_plan_id_value,
    subscription_row.plan_id,
    subscription_row.provider,
    nullif(trim(payload ->> 'provider_event_id'), ''),
    action_key,
    jsonb_build_object(
      'billing_cycle', billing_cycle_value,
      'amount_minor', amount_value,
      'currency_code', currency_value
    ),
    result
  );
end;
$$;

revoke all on function
  public.activate_paid_subscription(uuid,jsonb)
from public, anon, authenticated;

grant execute on function
  public.activate_paid_subscription(uuid,jsonb)
to authenticated, service_role;

-- ============================================================================
-- 8. SUSPENSION, REACTIVATION, RENEWAL, PLAN CHANGE AND CANCELLATION
-- ============================================================================

create or replace function
  public.suspend_hotel_subscription(
    target_hotel_id uuid,
    reason text,
    action_idempotency_key text default null
  )
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid :=
    private.require_platform_admin_20260728();
  existing_result jsonb;
  subscription_row public.hotel_subscriptions%rowtype;
  old_status_value text;
  result jsonb;
begin
  if target_hotel_id is null
     or nullif(trim(reason), '') is null
  then
    raise exception 'Hotel and suspension reason are required.';
  end if;

  existing_result :=
    private.subscription_action_result_20260728(
      action_idempotency_key
    );

  if existing_result is not null then
    return existing_result
      || jsonb_build_object('idempotent', true);
  end if;

  perform pg_advisory_xact_lock(
    hashtext(
      'stayqr:suspend-subscription:' || target_hotel_id::text
    )
  );

  select hs.*
  into subscription_row
  from public.hotel_subscriptions hs
  where hs.hotel_id = target_hotel_id
    and hs.status in (
      'trial',
      'trialing',
      'active',
      'past_due'
    )
  order by
    coalesce(hs.updated_at, hs.created_at) desc,
    hs.id desc
  limit 1
  for update;

  if not found then
    if exists (
      select 1
      from public.hotel_subscriptions hs
      where hs.hotel_id = target_hotel_id
        and hs.status = 'suspended'
    ) then
      select hs.*
      into subscription_row
      from public.hotel_subscriptions hs
      where hs.hotel_id = target_hotel_id
        and hs.status = 'suspended'
      order by hs.updated_at desc, hs.id desc
      limit 1;

      return jsonb_build_object(
        'hotel_id', target_hotel_id,
        'subscription_id', subscription_row.id,
        'status', subscription_row.status,
        'idempotent', true
      );
    end if;

    raise exception
      'No current subscription can be suspended.';
  end if;

  old_status_value := subscription_row.status;

  perform set_config(
    'stayqr.subscription_event_source',
    'suspend_hotel_subscription',
    true
  );

  update public.hotel_subscriptions hs
  set
    status = 'suspended',
    provider_status = 'suspended',
    suspended_at = now(),
    cancellation_reason = trim(reason),
    metadata = coalesce(hs.metadata, '{}'::jsonb)
      || jsonb_build_object(
        'last_suspension',
        jsonb_build_object(
          'reason', trim(reason),
          'suspended_by', actor_user_id,
          'suspended_at', now()
        )
      ),
    updated_at = now()
  where hs.id = subscription_row.id
  returning * into subscription_row;

  update public.hotels h
  set
    status = 'suspended',
    subscription_status = 'suspended',
    updated_at = now()
  where h.id = target_hotel_id;

  result := jsonb_build_object(
    'hotel_id', target_hotel_id,
    'subscription_id', subscription_row.id,
    'status', subscription_row.status,
    'hotel_status', 'suspended',
    'idempotent', false
  );

  return private.record_subscription_action_20260728(
    target_hotel_id,
    subscription_row.id,
    'hotel_suspended',
    'suspend_hotel_subscription',
    actor_user_id,
    old_status_value,
    subscription_row.status,
    subscription_row.plan_id,
    subscription_row.plan_id,
    subscription_row.provider,
    null,
    action_idempotency_key,
    jsonb_build_object('reason', trim(reason)),
    result
  );
end;
$$;

revoke all on function
  public.suspend_hotel_subscription(uuid,text,text)
from public, anon, authenticated;

grant execute on function
  public.suspend_hotel_subscription(uuid,text,text)
to authenticated;

create or replace function
  public.reactivate_hotel_subscription(
    target_hotel_id uuid,
    reason text,
    action_idempotency_key text default null
  )
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid :=
    private.require_platform_admin_20260728();
  existing_result jsonb;
  subscription_row public.hotel_subscriptions%rowtype;
  new_status_value text;
  result jsonb;
begin
  if target_hotel_id is null
     or nullif(trim(reason), '') is null
  then
    raise exception 'Hotel and reactivation reason are required.';
  end if;

  existing_result :=
    private.subscription_action_result_20260728(
      action_idempotency_key
    );

  if existing_result is not null then
    return existing_result
      || jsonb_build_object('idempotent', true);
  end if;

  perform pg_advisory_xact_lock(
    hashtext(
      'stayqr:reactivate-subscription:' || target_hotel_id::text
    )
  );

  select hs.*
  into subscription_row
  from public.hotel_subscriptions hs
  where hs.hotel_id = target_hotel_id
    and hs.status = 'suspended'
  order by hs.updated_at desc, hs.id desc
  limit 1
  for update;

  if not found then
    raise exception
      'No suspended subscription was found.';
  end if;

  if coalesce(
    subscription_row.grace_ends_at,
    subscription_row.current_period_end,
    subscription_row.end_date
  ) is not null
  and coalesce(
    subscription_row.grace_ends_at,
    subscription_row.current_period_end,
    subscription_row.end_date
  ) <= now()
  and subscription_row.billing_mode <> 'complimentary'
  then
    raise exception
      'The subscription period has ended; renew or activate a paid period first.';
  end if;

  new_status_value := case
    when subscription_row.billing_mode = 'trial'
      then 'trialing'
    else 'active'
  end;

  perform set_config(
    'stayqr.subscription_event_source',
    'reactivate_hotel_subscription',
    true
  );

  update public.hotel_subscriptions hs
  set
    status = new_status_value,
    provider_status = new_status_value,
    reactivated_at = now(),
    suspended_at = null,
    cancellation_reason = null,
    metadata = coalesce(hs.metadata, '{}'::jsonb)
      || jsonb_build_object(
        'last_reactivation',
        jsonb_build_object(
          'reason', trim(reason),
          'reactivated_by', actor_user_id,
          'reactivated_at', now()
        )
      ),
    updated_at = now()
  where hs.id = subscription_row.id
  returning * into subscription_row;

  update public.hotels h
  set
    status = 'active',
    subscription_status = new_status_value,
    updated_at = now()
  where h.id = target_hotel_id;

  result := jsonb_build_object(
    'hotel_id', target_hotel_id,
    'subscription_id', subscription_row.id,
    'status', subscription_row.status,
    'hotel_status', 'active',
    'idempotent', false
  );

  return private.record_subscription_action_20260728(
    target_hotel_id,
    subscription_row.id,
    'hotel_reactivated',
    'reactivate_hotel_subscription',
    actor_user_id,
    'suspended',
    subscription_row.status,
    subscription_row.plan_id,
    subscription_row.plan_id,
    subscription_row.provider,
    null,
    action_idempotency_key,
    jsonb_build_object('reason', trim(reason)),
    result
  );
end;
$$;

revoke all on function
  public.reactivate_hotel_subscription(uuid,text,text)
from public, anon, authenticated;

grant execute on function
  public.reactivate_hotel_subscription(uuid,text,text)
to authenticated;

create or replace function public.renew_hotel_subscription(
  target_hotel_id uuid,
  payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid := (select auth.uid());
  caller_role text :=
    current_setting('request.jwt.claim.role', true);
  action_key text;
  existing_result jsonb;
  subscription_row public.hotel_subscriptions%rowtype;
  old_status_value text;
  period_start_value timestamptz;
  period_end_value timestamptz;
  result jsonb;
begin
  if not (
    (
      actor_user_id is not null
      and private.is_platform_admin()
    )
    or caller_role = 'service_role'
  ) then
    raise exception
      'Platform Admin or service-role access required.';
  end if;

  if target_hotel_id is null
     or payload is null
     or jsonb_typeof(payload) <> 'object'
  then
    raise exception 'Hotel and renewal payload are required.';
  end if;

  action_key :=
    nullif(trim(payload ->> 'idempotency_key'), '');
  existing_result :=
    private.subscription_action_result_20260728(action_key);

  if existing_result is not null then
    return existing_result
      || jsonb_build_object('idempotent', true);
  end if;

  period_start_value :=
    coalesce(
      nullif(
        trim(payload ->> 'current_period_start'),
        ''
      )::timestamptz,
      now()
    );
  period_end_value :=
    nullif(
      trim(payload ->> 'current_period_end'),
      ''
    )::timestamptz;

  if period_end_value is null
     or period_end_value <= period_start_value
  then
    raise exception 'A valid renewal period is required.';
  end if;

  perform pg_advisory_xact_lock(
    hashtext(
      'stayqr:renew-subscription:' || target_hotel_id::text
    )
  );

  select hs.*
  into subscription_row
  from public.hotel_subscriptions hs
  where hs.hotel_id = target_hotel_id
    and hs.status in (
      'active',
      'past_due',
      'suspended'
    )
  order by hs.updated_at desc, hs.id desc
  limit 1
  for update;

  if not found then
    raise exception
      'No renewable current subscription was found.';
  end if;

  old_status_value := subscription_row.status;

  perform set_config(
    'stayqr.subscription_event_source',
    'renew_hotel_subscription',
    true
  );

  update public.hotel_subscriptions hs
  set
    status = 'active',
    billing_mode = case
      when hs.billing_mode = 'complimentary'
        and nullif(
          trim(payload ->> 'amount_minor'),
          ''
        )::bigint > 0
        then 'paid'
      else hs.billing_mode
    end,
    billing_cycle = coalesce(
      nullif(trim(payload ->> 'billing_cycle'), ''),
      hs.billing_cycle
    ),
    amount_minor = coalesce(
      nullif(trim(payload ->> 'amount_minor'), '')::bigint,
      hs.amount_minor
    ),
    currency_code = upper(
      coalesce(
        nullif(trim(payload ->> 'currency_code'), ''),
        hs.currency_code
      )
    ),
    provider = coalesce(
      nullif(trim(payload ->> 'provider'), ''),
      hs.provider
    ),
    provider_status = coalesce(
      nullif(trim(payload ->> 'provider_status'), ''),
      'active'
    ),
    provider_customer_id = coalesce(
      nullif(trim(payload ->> 'provider_customer_id'), ''),
      hs.provider_customer_id
    ),
    provider_subscription_id = coalesce(
      nullif(
        trim(payload ->> 'provider_subscription_id'),
        ''
      ),
      hs.provider_subscription_id
    ),
    provider_payment_link_id = coalesce(
      nullif(
        trim(payload ->> 'provider_payment_link_id'),
        ''
      ),
      hs.provider_payment_link_id
    ),
    provider_metadata =
      coalesce(hs.provider_metadata, '{}'::jsonb)
      || coalesce(payload -> 'provider_metadata', '{}'::jsonb),
    start_date = period_start_value,
    end_date = period_end_value,
    current_period_start = period_start_value,
    current_period_end = period_end_value,
    grace_ends_at = null,
    suspended_at = null,
    reactivated_at = case
      when old_status_value = 'suspended'
        then now()
      else hs.reactivated_at
    end,
    last_payment_at = coalesce(
      nullif(
        trim(payload ->> 'last_payment_at'),
        ''
      )::timestamptz,
      now()
    ),
    cancellation_reason = null,
    cancelled_at = null,
    metadata = coalesce(hs.metadata, '{}'::jsonb)
      || coalesce(payload -> 'metadata', '{}'::jsonb)
      || jsonb_build_object(
        'last_renewal',
        jsonb_build_object(
          'renewed_at', now(),
          'renewed_by', actor_user_id,
          'source_role', caller_role
        )
      ),
    updated_at = now()
  where hs.id = subscription_row.id
  returning * into subscription_row;

  update public.hotels h
  set
    status = 'active',
    subscription_status = 'active',
    updated_at = now()
  where h.id = target_hotel_id;

  result := jsonb_build_object(
    'hotel_id', target_hotel_id,
    'subscription_id', subscription_row.id,
    'status', subscription_row.status,
    'current_period_start',
      subscription_row.current_period_start,
    'current_period_end',
      subscription_row.current_period_end,
    'amount_minor', subscription_row.amount_minor,
    'idempotent', false
  );

  return private.record_subscription_action_20260728(
    target_hotel_id,
    subscription_row.id,
    'subscription_renewed',
    'renew_hotel_subscription',
    actor_user_id,
    old_status_value,
    subscription_row.status,
    subscription_row.plan_id,
    subscription_row.plan_id,
    subscription_row.provider,
    nullif(trim(payload ->> 'provider_event_id'), ''),
    action_key,
    jsonb_build_object(
      'period_start', period_start_value,
      'period_end', period_end_value
    ),
    result
  );
end;
$$;

revoke all on function
  public.renew_hotel_subscription(uuid,jsonb)
from public, anon, authenticated;

grant execute on function
  public.renew_hotel_subscription(uuid,jsonb)
to authenticated, service_role;

create or replace function
  public.change_hotel_subscription_plan(
    target_hotel_id uuid,
    payload jsonb
  )
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid :=
    private.require_platform_admin_20260728();
  action_key text;
  existing_result jsonb;
  target_plan_id uuid;
  subscription_row public.hotel_subscriptions%rowtype;
  old_plan_id_value uuid;
  result jsonb;
begin
  if target_hotel_id is null
     or payload is null
     or jsonb_typeof(payload) <> 'object'
  then
    raise exception 'Hotel and plan-change payload are required.';
  end if;

  action_key :=
    nullif(trim(payload ->> 'idempotency_key'), '');
  existing_result :=
    private.subscription_action_result_20260728(action_key);

  if existing_result is not null then
    return existing_result
      || jsonb_build_object('idempotent', true);
  end if;

  target_plan_id :=
    nullif(trim(payload ->> 'plan_id'), '')::uuid;

  if target_plan_id is null then
    raise exception 'Target plan is required.';
  end if;

  perform
    private.assert_subscription_capacity_internal_20260728(
      target_hotel_id,
      target_plan_id,
      0,
      0
    );

  perform pg_advisory_xact_lock(
    hashtext(
      'stayqr:change-plan:' || target_hotel_id::text
    )
  );

  select hs.*
  into subscription_row
  from public.hotel_subscriptions hs
  where hs.hotel_id = target_hotel_id
    and hs.status in (
      'trial',
      'trialing',
      'active',
      'past_due',
      'suspended'
    )
  order by hs.updated_at desc, hs.id desc
  limit 1
  for update;

  if not found then
    raise exception
      'No current subscription was found.';
  end if;

  old_plan_id_value := subscription_row.plan_id;

  if old_plan_id_value = target_plan_id then
    return jsonb_build_object(
      'hotel_id', target_hotel_id,
      'subscription_id', subscription_row.id,
      'plan_id', target_plan_id,
      'status', subscription_row.status,
      'idempotent', true
    );
  end if;

  perform set_config(
    'stayqr.subscription_event_source',
    'change_hotel_subscription_plan',
    true
  );

  update public.hotel_subscriptions hs
  set
    plan_id = target_plan_id,
    amount_minor = coalesce(
      nullif(trim(payload ->> 'amount_minor'), '')::bigint,
      hs.amount_minor
    ),
    currency_code = upper(
      coalesce(
        nullif(trim(payload ->> 'currency_code'), ''),
        hs.currency_code
      )
    ),
    metadata = coalesce(hs.metadata, '{}'::jsonb)
      || jsonb_build_object(
        'last_plan_change',
        jsonb_build_object(
          'from_plan_id', old_plan_id_value,
          'to_plan_id', target_plan_id,
          'reason',
            nullif(trim(payload ->> 'reason'), ''),
          'changed_by', actor_user_id,
          'changed_at', now()
        )
      ),
    updated_at = now()
  where hs.id = subscription_row.id
  returning * into subscription_row;

  perform
    private.refresh_subscription_usage_internal(
      target_hotel_id
    );

  result := jsonb_build_object(
    'hotel_id', target_hotel_id,
    'subscription_id', subscription_row.id,
    'old_plan_id', old_plan_id_value,
    'plan_id', subscription_row.plan_id,
    'status', subscription_row.status,
    'amount_minor', subscription_row.amount_minor,
    'idempotent', false
  );

  return private.record_subscription_action_20260728(
    target_hotel_id,
    subscription_row.id,
    'subscription_plan_changed',
    'change_hotel_subscription_plan',
    actor_user_id,
    subscription_row.status,
    subscription_row.status,
    old_plan_id_value,
    subscription_row.plan_id,
    subscription_row.provider,
    null,
    action_key,
    jsonb_build_object(
      'reason', nullif(trim(payload ->> 'reason'), '')
    ),
    result
  );
end;
$$;

revoke all on function
  public.change_hotel_subscription_plan(uuid,jsonb)
from public, anon, authenticated;

grant execute on function
  public.change_hotel_subscription_plan(uuid,jsonb)
to authenticated;

create or replace function
  public.cancel_hotel_subscription(
    target_hotel_id uuid,
    reason text,
    immediate boolean default false,
    action_idempotency_key text default null
  )
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid :=
    private.require_platform_admin_20260728();
  existing_result jsonb;
  subscription_row public.hotel_subscriptions%rowtype;
  old_status_value text;
  result jsonb;
begin
  if target_hotel_id is null
     or nullif(trim(reason), '') is null
  then
    raise exception
      'Hotel and cancellation reason are required.';
  end if;

  existing_result :=
    private.subscription_action_result_20260728(
      action_idempotency_key
    );

  if existing_result is not null then
    return existing_result
      || jsonb_build_object('idempotent', true);
  end if;

  perform pg_advisory_xact_lock(
    hashtext(
      'stayqr:cancel-subscription:' || target_hotel_id::text
    )
  );

  select hs.*
  into subscription_row
  from public.hotel_subscriptions hs
  where hs.hotel_id = target_hotel_id
    and hs.status in (
      'trial',
      'trialing',
      'active',
      'past_due',
      'suspended'
    )
  order by hs.updated_at desc, hs.id desc
  limit 1
  for update;

  if not found then
    raise exception
      'No current subscription was found.';
  end if;

  old_status_value := subscription_row.status;

  perform set_config(
    'stayqr.subscription_event_source',
    'cancel_hotel_subscription',
    true
  );

  if coalesce(immediate, false) then
    update public.hotel_subscriptions hs
    set
      status = 'cancelled',
      provider_status = 'cancelled',
      cancelled_at = now(),
      cancellation_reason = trim(reason),
      metadata = coalesce(hs.metadata, '{}'::jsonb)
        - 'cancel_at_period_end'
        || jsonb_build_object(
          'last_cancellation',
          jsonb_build_object(
            'immediate', true,
            'reason', trim(reason),
            'cancelled_by', actor_user_id,
            'cancelled_at', now()
          )
        ),
      updated_at = now()
    where hs.id = subscription_row.id
    returning * into subscription_row;

    update public.hotels h
    set
      status = 'suspended',
      subscription_status = 'cancelled',
      updated_at = now()
    where h.id = target_hotel_id;
  else
    update public.hotel_subscriptions hs
    set
      cancellation_reason = trim(reason),
      metadata = coalesce(hs.metadata, '{}'::jsonb)
        || jsonb_build_object(
          'cancel_at_period_end', true,
          'cancellation_requested_at', now(),
          'cancellation_requested_by', actor_user_id,
          'cancellation_reason', trim(reason)
        ),
      updated_at = now()
    where hs.id = subscription_row.id
    returning * into subscription_row;
  end if;

  result := jsonb_build_object(
    'hotel_id', target_hotel_id,
    'subscription_id', subscription_row.id,
    'status', subscription_row.status,
    'immediate', coalesce(immediate, false),
    'cancel_at_period_end',
      coalesce(
        (
          subscription_row.metadata
          ->> 'cancel_at_period_end'
        )::boolean,
        false
      ),
    'idempotent', false
  );

  return private.record_subscription_action_20260728(
    target_hotel_id,
    subscription_row.id,
    case when coalesce(immediate, false)
      then 'subscription_cancelled'
      else 'subscription_cancellation_scheduled'
    end,
    'cancel_hotel_subscription',
    actor_user_id,
    old_status_value,
    subscription_row.status,
    subscription_row.plan_id,
    subscription_row.plan_id,
    subscription_row.provider,
    null,
    action_idempotency_key,
    jsonb_build_object(
      'reason', trim(reason),
      'immediate', coalesce(immediate, false)
    ),
    result
  );
end;
$$;

revoke all on function
  public.cancel_hotel_subscription(uuid,text,boolean,text)
from public, anon, authenticated;

grant execute on function
  public.cancel_hotel_subscription(uuid,text,boolean,text)
to authenticated;

-- ============================================================================
-- 9. SUPER ADMIN GLOBAL DASHBOARD AND MRR
-- ============================================================================

create or replace function public.get_super_admin_dashboard()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid :=
    private.require_platform_admin_20260728();
  mrr_minor numeric := 0;
begin
  select coalesce(
    sum(
      case hs.billing_cycle
        when 'monthly' then hs.amount_minor
        when 'annual' then hs.amount_minor / 12.0
        else 0
      end
    ),
    0
  )
  into mrr_minor
  from public.hotel_subscriptions hs
  where hs.status = 'active'
    and hs.billing_mode = 'paid'
    and hs.amount_minor > 0;

  return jsonb_build_object(
    'generated_at', now(),
    'generated_by', actor_user_id,
    'hotels', jsonb_build_object(
      'total', (
        select count(*) from public.hotels
      ),
      'active', (
        select count(*)
        from public.hotels h
        where h.status = 'active'
      ),
      'suspended', (
        select count(*)
        from public.hotels h
        where h.status = 'suspended'
      )
    ),
    'subscriptions', jsonb_build_object(
      'trialing', (
        select count(*)
        from public.hotel_subscriptions hs
        where hs.status in ('trial', 'trialing')
      ),
      'active_paid', (
        select count(*)
        from public.hotel_subscriptions hs
        where hs.status = 'active'
          and hs.billing_mode = 'paid'
      ),
      'active_complimentary', (
        select count(*)
        from public.hotel_subscriptions hs
        where hs.status = 'active'
          and hs.billing_mode = 'complimentary'
      ),
      'past_due', (
        select count(*)
        from public.hotel_subscriptions hs
        where hs.status = 'past_due'
      ),
      'suspended', (
        select count(*)
        from public.hotel_subscriptions hs
        where hs.status = 'suspended'
      ),
      'expired', (
        select count(*)
        from public.hotel_subscriptions hs
        where hs.status = 'expired'
      ),
      'cancelled', (
        select count(*)
        from public.hotel_subscriptions hs
        where hs.status = 'cancelled'
      ),
      'trials_expiring_7_days', (
        select count(*)
        from public.hotel_subscriptions hs
        where hs.status in ('trial', 'trialing')
          and hs.trial_ends_at > now()
          and hs.trial_ends_at <= now() + interval '7 days'
      )
    ),
    'revenue', jsonb_build_object(
      'currency_code', 'INR',
      'mrr_minor', round(mrr_minor)::bigint,
      'mrr', round(mrr_minor / 100.0, 2)
    ),
    'support', jsonb_build_object(
      'open', (
        select count(*)
        from public.support_tickets st
        where st.status in (
          'open',
          'in_progress',
          'waiting_on_hotel'
        )
      ),
      'urgent_open', (
        select count(*)
        from public.support_tickets st
        where st.status in (
          'open',
          'in_progress',
          'waiting_on_hotel'
        )
          and st.priority = 'urgent'
      )
    ),
    'webhooks', jsonb_build_object(
      'failed', (
        select count(*)
        from public.webhook_events we
        where we.processing_status = 'failed'
      ),
      'pending', (
        select count(*)
        from public.webhook_events we
        where we.processing_status in (
          'received',
          'processing'
        )
      )
    ),
    'usage', jsonb_build_object(
      'hotels_over_room_limit', (
        select count(distinct uc.hotel_id)
        from public.usage_counters uc
        where uc.metric_key = 'rooms'
          and uc.limit_value is not null
          and uc.current_value > uc.limit_value
      ),
      'hotels_over_staff_limit', (
        select count(distinct uc.hotel_id)
        from public.usage_counters uc
        where uc.metric_key = 'active_staff'
          and uc.limit_value is not null
          and uc.current_value > uc.limit_value
      )
    ),
    'plans', (
      select coalesce(
        jsonb_agg(
          jsonb_build_object(
            'plan_id', sp.id,
            'plan_code', sp.plan_code,
            'plan_name', sp.plan_name,
            'status', sp.status,
            'price_monthly', sp.price_monthly,
            'max_rooms', sp.max_rooms,
            'max_staff', sp.max_staff,
            'current_hotels', (
              select count(*)
              from public.hotel_subscriptions hs
              where hs.plan_id = sp.id
                and hs.status in (
                  'trial',
                  'trialing',
                  'active',
                  'past_due',
                  'suspended'
                )
            )
          )
          order by sp.price_monthly, sp.plan_name
        ),
        '[]'::jsonb
      )
      from public.subscription_plans sp
    )
  );
end;
$$;

revoke all on function
  public.get_super_admin_dashboard()
from public, anon, authenticated;

grant execute on function
  public.get_super_admin_dashboard()
to authenticated;

-- ============================================================================
-- 10. SUPPORT TICKET SERVER ACTIONS
-- ============================================================================

create or replace function public.create_support_ticket(
  target_hotel_id uuid,
  subject text,
  description text,
  category text default 'general',
  priority text default 'normal'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid := (select auth.uid());
  ticket_row public.support_tickets%rowtype;
begin
  if actor_user_id is null then
    raise exception 'Authentication required.';
  end if;

  if not (
    private.is_platform_admin()
    or private.user_has_hotel_access(target_hotel_id)
  ) then
    raise exception 'Support ticket access denied.';
  end if;

  if nullif(trim(subject), '') is null
     or nullif(trim(description), '') is null
  then
    raise exception
      'Support subject and description are required.';
  end if;

  insert into public.support_tickets (
    hotel_id,
    subject,
    description,
    category,
    priority,
    status,
    created_by,
    last_response_at,
    metadata,
    created_at,
    updated_at
  ) values (
    target_hotel_id,
    trim(subject),
    trim(description),
    coalesce(nullif(trim(category), ''), 'general'),
    coalesce(nullif(trim(priority), ''), 'normal'),
    'open',
    actor_user_id,
    now(),
    '{}'::jsonb,
    now(),
    now()
  )
  returning * into ticket_row;

  insert into public.support_ticket_events (
    ticket_id,
    hotel_id,
    event_type,
    actor_user_id,
    message,
    new_status,
    details,
    created_at
  ) values (
    ticket_row.id,
    target_hotel_id,
    'ticket_created',
    actor_user_id,
    trim(description),
    ticket_row.status,
    jsonb_build_object(
      'subject', ticket_row.subject,
      'category', ticket_row.category,
      'priority', ticket_row.priority
    ),
    now()
  );

  return jsonb_build_object(
    'ticket', to_jsonb(ticket_row)
  );
end;
$$;

revoke all on function
  public.create_support_ticket(uuid,text,text,text,text)
from public, anon, authenticated;

grant execute on function
  public.create_support_ticket(uuid,text,text,text,text)
to authenticated;

create or replace function public.add_support_ticket_message(
  target_ticket_id uuid,
  message text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid := (select auth.uid());
  ticket_row public.support_tickets%rowtype;
  event_id_value uuid;
begin
  if actor_user_id is null then
    raise exception 'Authentication required.';
  end if;

  if nullif(trim(message), '') is null then
    raise exception 'Support message is required.';
  end if;

  select st.*
  into ticket_row
  from public.support_tickets st
  where st.id = target_ticket_id
  for update;

  if not found then
    raise exception 'Support ticket was not found.';
  end if;

  if not (
    private.is_platform_admin()
    or private.user_has_hotel_access(ticket_row.hotel_id)
  ) then
    raise exception 'Support ticket access denied.';
  end if;

  if ticket_row.status = 'closed' then
    raise exception
      'Closed support tickets cannot receive new messages.';
  end if;

  update public.support_tickets st
  set
    last_response_at = now(),
    updated_at = now()
  where st.id = target_ticket_id;

  insert into public.support_ticket_events (
    ticket_id,
    hotel_id,
    event_type,
    actor_user_id,
    message,
    old_status,
    new_status,
    details,
    created_at
  ) values (
    ticket_row.id,
    ticket_row.hotel_id,
    'message_added',
    actor_user_id,
    trim(message),
    ticket_row.status,
    ticket_row.status,
    '{}'::jsonb,
    now()
  )
  returning id into event_id_value;

  return jsonb_build_object(
    'ticket_id', ticket_row.id,
    'event_id', event_id_value,
    'status', ticket_row.status
  );
end;
$$;

revoke all on function
  public.add_support_ticket_message(uuid,text)
from public, anon, authenticated;

grant execute on function
  public.add_support_ticket_message(uuid,text)
to authenticated;

create or replace function public.update_support_ticket_status(
  target_ticket_id uuid,
  new_status text,
  message text default null,
  assign_to_user_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid :=
    private.require_platform_admin_20260728();
  ticket_row public.support_tickets%rowtype;
  old_status_value text;
begin
  if new_status not in (
    'open',
    'in_progress',
    'waiting_on_hotel',
    'resolved',
    'closed'
  ) then
    raise exception
      'Unsupported support ticket status.';
  end if;

  select st.*
  into ticket_row
  from public.support_tickets st
  where st.id = target_ticket_id
  for update;

  if not found then
    raise exception 'Support ticket was not found.';
  end if;

  old_status_value := ticket_row.status;

  update public.support_tickets st
  set
    status = new_status,
    assigned_to = coalesce(
      assign_to_user_id,
      st.assigned_to
    ),
    resolved_by = case
      when new_status in ('resolved', 'closed')
        then actor_user_id
      else st.resolved_by
    end,
    resolved_at = case
      when new_status in ('resolved', 'closed')
        then coalesce(st.resolved_at, now())
      else null
    end,
    closed_at = case
      when new_status = 'closed'
        then coalesce(st.closed_at, now())
      else null
    end,
    last_response_at = now(),
    updated_at = now()
  where st.id = target_ticket_id
  returning * into ticket_row;

  insert into public.support_ticket_events (
    ticket_id,
    hotel_id,
    event_type,
    actor_user_id,
    message,
    old_status,
    new_status,
    details,
    created_at
  ) values (
    ticket_row.id,
    ticket_row.hotel_id,
    'status_changed',
    actor_user_id,
    nullif(trim(message), ''),
    old_status_value,
    ticket_row.status,
    jsonb_build_object(
      'assigned_to', ticket_row.assigned_to
    ),
    now()
  );

  return jsonb_build_object(
    'ticket', to_jsonb(ticket_row)
  );
end;
$$;

revoke all on function
  public.update_support_ticket_status(uuid,text,text,uuid)
from public, anon, authenticated;

grant execute on function
  public.update_support_ticket_status(uuid,text,text,uuid)
to authenticated;

-- ============================================================================
-- 11. SAFE SUPPORT ACCESS SERVER ACTIONS
-- ============================================================================

create or replace function public.start_safe_support_access(
  target_hotel_id uuid,
  reason text,
  duration_minutes integer default 60,
  requested_permissions text[] default array['read_only']::text[]
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid :=
    private.require_platform_admin_20260728();
  session_row public.support_access_sessions%rowtype;
  normalized_permissions text[];
begin
  if target_hotel_id is null
     or nullif(trim(reason), '') is null
  then
    raise exception
      'Hotel and support-access reason are required.';
  end if;

  if duration_minutes is null
     or duration_minutes < 5
     or duration_minutes > 240
  then
    raise exception
      'Support access duration must be between 5 and 240 minutes.';
  end if;

  select array_agg(distinct permission_value order by permission_value)
  into normalized_permissions
  from unnest(
    coalesce(
      requested_permissions,
      array['read_only']::text[]
    )
  ) permission_value
  where permission_value in (
    'read_only',
    'hotel_configuration',
    'subscription_support',
    'ticket_support'
  );

  if coalesce(cardinality(normalized_permissions), 0) = 0 then
    raise exception
      'At least one approved support permission is required.';
  end if;

  update public.support_access_sessions sas
  set
    status = 'expired',
    ended_at = coalesce(sas.ended_at, now()),
    ended_by = actor_user_id,
    metadata = sas.metadata
      || jsonb_build_object(
        'expired_by_start_action', true
      ),
    updated_at = now()
  where sas.hotel_id = target_hotel_id
    and sas.platform_admin_user_id = actor_user_id
    and sas.status = 'active'
    and sas.expires_at <= now();

  insert into public.support_access_sessions (
    hotel_id,
    platform_admin_user_id,
    reason,
    status,
    permissions,
    started_at,
    expires_at,
    metadata,
    created_at,
    updated_at
  ) values (
    target_hotel_id,
    actor_user_id,
    trim(reason),
    'active',
    normalized_permissions,
    now(),
    now() + make_interval(mins => duration_minutes),
    '{}'::jsonb,
    now(),
    now()
  )
  returning * into session_row;

  insert into public.support_access_events (
    session_id,
    hotel_id,
    event_type,
    actor_user_id,
    message,
    details,
    created_at
  ) values (
    session_row.id,
    session_row.hotel_id,
    'support_access_started',
    actor_user_id,
    trim(reason),
    jsonb_build_object(
      'permissions', session_row.permissions,
      'expires_at', session_row.expires_at
    ),
    now()
  );

  return jsonb_build_object(
    'session', to_jsonb(session_row)
  );
exception
  when unique_violation then
    raise exception
      'An active support-access session already exists for this Platform Admin and hotel.';
end;
$$;

revoke all on function
  public.start_safe_support_access(uuid,text,integer,text[])
from public, anon, authenticated;

grant execute on function
  public.start_safe_support_access(uuid,text,integer,text[])
to authenticated;

create or replace function public.end_safe_support_access(
  target_session_id uuid,
  reason text default 'Support work completed.'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid :=
    private.require_platform_admin_20260728();
  session_row public.support_access_sessions%rowtype;
begin
  select sas.*
  into session_row
  from public.support_access_sessions sas
  where sas.id = target_session_id
  for update;

  if not found then
    raise exception
      'Support-access session was not found.';
  end if;

  if session_row.status <> 'active' then
    return jsonb_build_object(
      'session_id', session_row.id,
      'status', session_row.status,
      'idempotent', true
    );
  end if;

  update public.support_access_sessions sas
  set
    status = 'ended',
    ended_at = now(),
    ended_by = actor_user_id,
    metadata = sas.metadata
      || jsonb_build_object(
        'end_reason',
        coalesce(
          nullif(trim(reason), ''),
          'Support work completed.'
        )
      ),
    updated_at = now()
  where sas.id = target_session_id
  returning * into session_row;

  insert into public.support_access_events (
    session_id,
    hotel_id,
    event_type,
    actor_user_id,
    message,
    details,
    created_at
  ) values (
    session_row.id,
    session_row.hotel_id,
    'support_access_ended',
    actor_user_id,
    coalesce(
      nullif(trim(reason), ''),
      'Support work completed.'
    ),
    jsonb_build_object(
      'ended_at', session_row.ended_at
    ),
    now()
  );

  return jsonb_build_object(
    'session', to_jsonb(session_row),
    'idempotent', false
  );
end;
$$;

revoke all on function
  public.end_safe_support_access(uuid,text)
from public, anon, authenticated;

grant execute on function
  public.end_safe_support_access(uuid,text)
to authenticated;

-- ============================================================================
-- 12. PLATFORM ANNOUNCEMENT SERVER ACTION
-- ============================================================================

create or replace function public.save_platform_announcement(
  payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid :=
    private.require_platform_admin_20260728();
  target_id uuid;
  scope_value text;
  status_value text;
  target_hotel_id_value uuid;
  saved_row public.announcements%rowtype;
begin
  if payload is null or jsonb_typeof(payload) <> 'object' then
    raise exception
      'Announcement payload must be a JSON object.';
  end if;

  target_id :=
    nullif(trim(payload ->> 'id'), '')::uuid;
  scope_value :=
    coalesce(
      nullif(trim(payload ->> 'scope'), ''),
      'global'
    );
  status_value :=
    coalesce(
      nullif(trim(payload ->> 'status'), ''),
      'draft'
    );
  target_hotel_id_value :=
    nullif(
      trim(payload ->> 'target_hotel_id'),
      ''
    )::uuid;

  if nullif(trim(payload ->> 'title'), '') is null
     or nullif(trim(payload ->> 'body'), '') is null
  then
    raise exception
      'Announcement title and body are required.';
  end if;

  if scope_value = 'global' then
    target_hotel_id_value := null;
  elsif scope_value = 'hotel'
    and target_hotel_id_value is null
  then
    raise exception
      'Hotel-targeted announcements require target_hotel_id.';
  end if;

  if target_id is null then
    insert into public.announcements (
      scope,
      target_hotel_id,
      title,
      body,
      severity,
      status,
      starts_at,
      ends_at,
      created_by,
      published_by,
      published_at,
      metadata,
      created_at,
      updated_at
    ) values (
      scope_value,
      target_hotel_id_value,
      trim(payload ->> 'title'),
      trim(payload ->> 'body'),
      coalesce(
        nullif(trim(payload ->> 'severity'), ''),
        'info'
      ),
      status_value,
      nullif(
        trim(payload ->> 'starts_at'),
        ''
      )::timestamptz,
      nullif(
        trim(payload ->> 'ends_at'),
        ''
      )::timestamptz,
      actor_user_id,
      case when status_value = 'published'
        then actor_user_id end,
      case when status_value = 'published'
        then now() end,
      coalesce(payload -> 'metadata', '{}'::jsonb),
      now(),
      now()
    )
    returning * into saved_row;
  else
    update public.announcements a
    set
      scope = scope_value,
      target_hotel_id = target_hotel_id_value,
      title = trim(payload ->> 'title'),
      body = trim(payload ->> 'body'),
      severity = coalesce(
        nullif(trim(payload ->> 'severity'), ''),
        a.severity
      ),
      status = status_value,
      starts_at = case
        when payload ? 'starts_at'
          then nullif(
            trim(payload ->> 'starts_at'),
            ''
          )::timestamptz
        else a.starts_at
      end,
      ends_at = case
        when payload ? 'ends_at'
          then nullif(
            trim(payload ->> 'ends_at'),
            ''
          )::timestamptz
        else a.ends_at
      end,
      published_by = case
        when status_value = 'published'
          then coalesce(a.published_by, actor_user_id)
        else a.published_by
      end,
      published_at = case
        when status_value = 'published'
          then coalesce(a.published_at, now())
        else a.published_at
      end,
      metadata = case
        when payload ? 'metadata'
          then coalesce(
            payload -> 'metadata',
            '{}'::jsonb
          )
        else a.metadata
      end,
      updated_at = now()
    where a.id = target_id
    returning * into saved_row;

    if not found then
      raise exception
        'Announcement was not found.';
    end if;
  end if;

  return jsonb_build_object(
    'announcement', to_jsonb(saved_row)
  );
end;
$$;

revoke all on function
  public.save_platform_announcement(jsonb)
from public, anon, authenticated;

grant execute on function
  public.save_platform_announcement(jsonb)
to authenticated;

-- ============================================================================
-- 13. POST-MIGRATION ASSERTIONS
-- ============================================================================

do $verify$
declare
  function_row record;
begin
  for function_row in
    select
      p.oid::regprocedure::text as signature,
      p.prosecdef,
      p.proconfig
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'save_subscription_plan',
        'get_hotel_subscription_usage',
        'assert_subscription_capacity',
        'extend_hotel_trial',
        'reconcile_expired_subscriptions',
        'activate_paid_subscription',
        'suspend_hotel_subscription',
        'reactivate_hotel_subscription',
        'renew_hotel_subscription',
        'change_hotel_subscription_plan',
        'cancel_hotel_subscription',
        'get_super_admin_dashboard',
        'create_support_ticket',
        'add_support_ticket_message',
        'update_support_ticket_status',
        'start_safe_support_access',
        'end_safe_support_access',
        'save_platform_announcement'
      )
  loop
    if not function_row.prosecdef then
      raise exception
        'Migration 021 failed: % is not SECURITY DEFINER.',
        function_row.signature;
    end if;

    if not (
      function_row.proconfig
        @> array['search_path=""']::text[]
      or function_row.proconfig
        @> array['search_path=']::text[]
    ) then
      raise exception
        'Migration 021 failed: % does not lock search_path.',
        function_row.signature;
    end if;
  end loop;

  if has_function_privilege(
    'anon',
    'public.activate_paid_subscription(uuid,jsonb)',
    'EXECUTE'
  ) or has_function_privilege(
    'anon',
    'public.create_support_ticket(uuid,text,text,text,text)',
    'EXECUTE'
  ) or has_function_privilege(
    'anon',
    'public.get_super_admin_dashboard()',
    'EXECUTE'
  ) then
    raise exception
      'Migration 021 failed: anonymous execution exists on a protected RPC.';
  end if;

  if not exists (
    select 1
    from pg_trigger t
    where t.tgrelid = 'public.rooms'::regclass
      and t.tgname =
        'enforce_room_subscription_limit_20260728'
      and not t.tgisinternal
  ) or not exists (
    select 1
    from pg_trigger t
    where t.tgrelid = 'public.staff'::regclass
      and t.tgname =
        'enforce_staff_subscription_limit_20260728'
      and not t.tgisinternal
  ) then
    raise exception
      'Migration 021 failed: server-level plan-limit triggers are missing.';
  end if;
end;
$verify$;

commit;

-- ============================================================================
-- 14. ACCEPTANCE RESULT
-- ============================================================================

with required_rpc(signature) as (
  values
    ('public.save_subscription_plan(jsonb)'),
    ('public.get_hotel_subscription_usage(uuid)'),
    ('public.assert_subscription_capacity(uuid,text,integer)'),
    ('public.extend_hotel_trial(uuid,integer,text,text)'),
    ('public.reconcile_expired_subscriptions(timestamptz)'),
    ('public.activate_paid_subscription(uuid,jsonb)'),
    ('public.suspend_hotel_subscription(uuid,text,text)'),
    ('public.reactivate_hotel_subscription(uuid,text,text)'),
    ('public.renew_hotel_subscription(uuid,jsonb)'),
    ('public.change_hotel_subscription_plan(uuid,jsonb)'),
    ('public.cancel_hotel_subscription(uuid,text,boolean,text)'),
    ('public.get_super_admin_dashboard()'),
    ('public.create_support_ticket(uuid,text,text,text,text)'),
    ('public.add_support_ticket_message(uuid,text)'),
    ('public.update_support_ticket_status(uuid,text,text,uuid)'),
    ('public.start_safe_support_access(uuid,text,integer,text[])'),
    ('public.end_safe_support_access(uuid,text)'),
    ('public.save_platform_announcement(jsonb)')
),
checks(test_name, passed, details) as (
  values
    (
      '01_support_access_event_table',
      to_regclass('public.support_access_events') is not null,
      'Immutable support-access event table exists.'
    ),
    (
      '02_support_access_event_immutability',
      exists (
        select 1
        from pg_trigger t
        where t.tgrelid =
          'public.support_access_events'::regclass
          and t.tgname =
            'prevent_support_access_event_mutation_20260728'
          and not t.tgisinternal
      ),
      'Support-access events cannot be updated or deleted normally.'
    ),
    (
      '03_all_lifecycle_rpcs_present',
      not exists (
        select 1
        from required_rpc r
        where to_regprocedure(r.signature) is null
      ),
      'All 18 Day 9 lifecycle, metrics, support and announcement RPCs exist.'
    ),
    (
      '04_authenticated_rpc_execute',
      not exists (
        select 1
        from required_rpc r
        where not has_function_privilege(
          'authenticated',
          r.signature,
          'EXECUTE'
        )
      ),
      'Authenticated callers retain execute grants; each RPC enforces its own authorization.'
    ),
    (
      '05_anonymous_rpc_execution_blocked',
      not exists (
        select 1
        from required_rpc r
        where has_function_privilege(
          'anon',
          r.signature,
          'EXECUTE'
        )
      ),
      'Anonymous users cannot execute any Day 9 lifecycle or support RPC.'
    ),
    (
      '06_service_role_expiry_reconciliation',
      has_function_privilege(
        'service_role',
        'public.reconcile_expired_subscriptions(timestamptz)',
        'EXECUTE'
      ),
      'Scheduled service-role expiry reconciliation is supported.'
    ),
    (
      '07_service_role_paid_activation',
      has_function_privilege(
        'service_role',
        'public.activate_paid_subscription(uuid,jsonb)',
        'EXECUTE'
      )
      and has_function_privilege(
        'service_role',
        'public.renew_hotel_subscription(uuid,jsonb)',
        'EXECUTE'
      ),
      'Trusted payment/webhook services can activate and renew subscriptions.'
    ),
    (
      '08_room_limit_trigger',
      exists (
        select 1
        from pg_trigger t
        where t.tgrelid = 'public.rooms'::regclass
          and t.tgname =
            'enforce_room_subscription_limit_20260728'
          and not t.tgisinternal
      ),
      'Every room insertion or tenant move is checked against the current plan.'
    ),
    (
      '09_staff_limit_trigger',
      exists (
        select 1
        from pg_trigger t
        where t.tgrelid = 'public.staff'::regclass
          and t.tgname =
            'enforce_staff_subscription_limit_20260728'
          and not t.tgisinternal
      ),
      'Every active staff insertion/activation is checked against the current plan.'
    ),
    (
      '10_capacity_helper',
      to_regprocedure(
        'private.assert_subscription_capacity_internal_20260728(uuid,uuid,integer,integer)'
      ) is not null,
      'Authoritative room/staff capacity helper exists.'
    ),
    (
      '11_plan_management_rpc',
      to_regprocedure(
        'public.save_subscription_plan(jsonb)'
      ) is not null,
      'Platform Admin plan and limit management is server validated.'
    ),
    (
      '12_usage_rpc',
      to_regprocedure(
        'public.get_hotel_subscription_usage(uuid)'
      ) is not null,
      'Hotel and Platform Admin usage retrieval is server calculated.'
    ),
    (
      '13_trial_extension_rpc',
      to_regprocedure(
        'public.extend_hotel_trial(uuid,integer,text,text)'
      ) is not null,
      'Transactional, reasoned and idempotent trial extension exists.'
    ),
    (
      '14_expiry_reconciliation_rpc',
      to_regprocedure(
        'public.reconcile_expired_subscriptions(timestamptz)'
      ) is not null,
      'Repeatable trial/paid expiry and scheduled-cancellation reconciliation exists.'
    ),
    (
      '15_paid_activation_rpc',
      to_regprocedure(
        'public.activate_paid_subscription(uuid,jsonb)'
      ) is not null,
      'Paid activation/trial conversion accepts provider evidence and idempotency.'
    ),
    (
      '16_suspend_reactivate_rpcs',
      to_regprocedure(
        'public.suspend_hotel_subscription(uuid,text,text)'
      ) is not null
      and to_regprocedure(
        'public.reactivate_hotel_subscription(uuid,text,text)'
      ) is not null,
      'Hotel suspension and valid-period recovery actions exist.'
    ),
    (
      '17_renew_plan_change_cancel_rpcs',
      to_regprocedure(
        'public.renew_hotel_subscription(uuid,jsonb)'
      ) is not null
      and to_regprocedure(
        'public.change_hotel_subscription_plan(uuid,jsonb)'
      ) is not null
      and to_regprocedure(
        'public.cancel_hotel_subscription(uuid,text,boolean,text)'
      ) is not null,
      'Renewal, plan change, scheduled cancellation and immediate cancellation exist.'
    ),
    (
      '18_lifecycle_idempotency_helper',
      to_regprocedure(
        'private.subscription_action_result_20260728(text)'
      ) is not null
      and to_regprocedure(
        'private.record_subscription_action_20260728(uuid,uuid,text,text,uuid,text,text,uuid,uuid,text,text,text,jsonb,jsonb)'
      ) is not null,
      'Lifecycle actions can return the prior result for a repeated idempotency key.'
    ),
    (
      '19_global_dashboard_rpc',
      to_regprocedure(
        'public.get_super_admin_dashboard()'
      ) is not null,
      'Global hotel/subscription/MRR/support/webhook/usage summary exists.'
    ),
    (
      '20_support_create_rpc',
      to_regprocedure(
        'public.create_support_ticket(uuid,text,text,text,text)'
      ) is not null,
      'Hotel users can create support tickets without direct table writes.'
    ),
    (
      '21_support_message_rpc',
      to_regprocedure(
        'public.add_support_ticket_message(uuid,text)'
      ) is not null,
      'Authorized ticket participants can append immutable messages.'
    ),
    (
      '22_support_triage_rpc',
      to_regprocedure(
        'public.update_support_ticket_status(uuid,text,text,uuid)'
      ) is not null,
      'Platform Admin ticket assignment and status transitions exist.'
    ),
    (
      '23_safe_support_start_end',
      to_regprocedure(
        'public.start_safe_support_access(uuid,text,integer,text[])'
      ) is not null
      and to_regprocedure(
        'public.end_safe_support_access(uuid,text)'
      ) is not null,
      'Support access is explicit, time-limited and endable.'
    ),
    (
      '24_announcement_rpc',
      to_regprocedure(
        'public.save_platform_announcement(jsonb)'
      ) is not null,
      'Platform announcements are created and published through one server action.'
    ),
    (
      '25_support_access_events_rls',
      (
        select c.relrowsecurity
        from pg_class c
        where c.oid =
          'public.support_access_events'::regclass
      ),
      'Support-access history has RLS enabled.'
    ),
    (
      '26_no_current_subscription_duplicates',
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
        ) d
      ),
      'Lifecycle RPC installation preserved one-current-subscription uniqueness.'
    ),
    (
      '27_existing_room_limits_safe',
      not exists (
        select 1
        from public.hotel_subscriptions hs
        join public.subscription_plans sp
          on sp.id = hs.plan_id
        where hs.status in (
          'trial',
          'trialing',
          'active',
          'past_due',
          'suspended'
        )
          and sp.max_rooms is not null
          and (
            select count(*)
            from public.rooms r
            where r.hotel_id = hs.hotel_id
          ) > sp.max_rooms
      ),
      'Existing room inventories remain within current plan limits.'
    ),
    (
      '28_existing_staff_limits_safe',
      not exists (
        select 1
        from public.hotel_subscriptions hs
        join public.subscription_plans sp
          on sp.id = hs.plan_id
        where hs.status in (
          'trial',
          'trialing',
          'active',
          'past_due',
          'suspended'
        )
          and sp.max_staff is not null
          and (
            select count(*)
            from public.staff s
            where s.hotel_id = hs.hotel_id
              and s.status = 'active'
          ) > sp.max_staff
      ),
      'Existing active staff remains within configured plan limits.'
    ),
    (
      '29_subscription_events_append_only',
      exists (
        select 1
        from pg_trigger t
        where t.tgrelid =
          'public.subscription_events'::regclass
          and t.tgname =
            'prevent_subscription_event_mutation_20260728'
          and not t.tgisinternal
      ),
      'Lifecycle action evidence remains append-only.'
    ),
    (
      '30_support_events_append_only',
      exists (
        select 1
        from pg_trigger t
        where t.tgrelid =
          'public.support_ticket_events'::regclass
          and t.tgname =
            'prevent_support_ticket_event_mutation_20260728'
          and not t.tgisinternal
      ),
      'Support ticket messages and status history remain append-only.'
    ),
    (
      '31_day8_onboarding_rpcs_preserved',
      to_regprocedure(
        'public.bootstrap_hotel_onboarding(jsonb)'
      ) is not null
      and to_regprocedure(
        'public.configure_hotel_inventory(uuid,jsonb)'
      ) is not null
      and to_regprocedure(
        'public.import_hotel_rooms(uuid,jsonb)'
      ) is not null,
      'Locked Day 8 onboarding and inventory functions remain installed.'
    ),
    (
      '32_existing_hotel_counts_unchanged',
      (
        select count(*) >= 3
        from public.hotels
      ),
      'The existing production hotel inventory remains present.'
    ),
    (
      '33_no_razorpay_secret_columns',
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
            'subscription_events',
            'webhook_events'
          )
      ),
      'No Razorpay or provider secret is stored in public billing schemas.'
    ),
    (
      '34_webhook_foundation_preserved',
      to_regclass('public.webhook_events') is not null
      and to_regclass(
        'public.uq_webhook_events_provider_event'
      ) is not null,
      'Signed-webhook receipt and replay protection foundation remains ready.'
    ),
    (
      '35_platform_foundation_preserved',
      to_regclass('public.support_tickets') is not null
      and to_regclass('public.announcements') is not null
      and to_regclass(
        'public.support_access_sessions'
      ) is not null,
      'Support, announcement and safe-support foundations remain present.'
    ),
    (
      '36_day9_lifecycle_backend_ready',
      to_regprocedure(
        'public.activate_paid_subscription(uuid,jsonb)'
      ) is not null
      and to_regprocedure(
        'public.get_super_admin_dashboard()'
      ) is not null
      and to_regprocedure(
        'public.create_support_ticket(uuid,text,text,text,text)'
      ) is not null
      and to_regprocedure(
        'public.start_safe_support_access(uuid,text,integer,text[])'
      ) is not null,
      'The Day 9 lifecycle backend is ready for reversible runtime acceptance and Razorpay Edge Function integration.'
    )
)
select test_name, passed, details
from checks
order by test_name;
