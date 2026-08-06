-- ============================================================================
-- StayQR v1.0
-- Day 9 Migration 024 REV2 — Cashfree-Ready Payment-Link Ledger,
-- Provider Webhook Actions and Super Admin Commercial Control Data
--
-- ACTIVE PROVIDER DECISION
-- Cashfree is the Day 9 launch provider. Razorpay is paused and is not required
-- for this migration or for the upcoming Cashfree Edge Functions.
--
-- PRIMARY OUTCOME
-- Completes the provider-neutral database layer needed by the Day 9 frontend
-- and Razorpay Edge Functions:
--   - auditable payment-link records for hotel SaaS billing;
--   - Platform Admin and hotel-owner read isolation;
--   - trusted service-role webhook lifecycle application;
--   - payment success, failure, suspension, cancellation and recovery actions;
--   - one controlled Super Admin commercial-control RPC for hotels, plans,
--     subscriptions, usage, support tickets, subscription events and webhook
--     status without exposing webhook payloads or secrets.
--
-- PROVIDER BOUNDARY
-- Cashfree credentials and HTTP requests remain inside Edge Functions.
-- The schema remains provider-neutral so Razorpay or PayU can be added later. This migration stores only provider IDs, URLs, statuses and safe
-- metadata. It stores no API key, API secret or webhook secret.
--
-- SAFETY
-- - Run once in Supabase SQL Editor with role: postgres.
-- - Transactional and idempotent.
-- - Does not create a payment link or change any real subscription merely by
--   installing the migration.
-- - Existing Day 8 onboarding and accepted Day 9 lifecycle RPCs are preserved.
--
-- EXPECTED RESULT
-- 24 rows, and every passed value must be true.
-- ============================================================================

begin;

set local lock_timeout = '10s';
set local statement_timeout = '240s';

select pg_advisory_xact_lock(
  hashtext('stayqr:202607280024:provider-payment-links-webhooks-control')
);

-- ============================================================================
-- 0. PRE-MIGRATION ASSERTIONS
-- ============================================================================

do $preflight$
begin
  if to_regclass('public.hotel_subscriptions') is null
     or to_regclass('public.subscription_plans') is null
     or to_regclass('public.subscription_events') is null
     or to_regclass('public.webhook_events') is null
     or to_regclass('public.usage_counters') is null
  then
    raise exception
      'Migration 024 stopped: accepted Day 9 commercial foundation is missing.';
  end if;

  if to_regprocedure(
       'public.activate_paid_subscription(uuid,jsonb)'
     ) is null
     or to_regprocedure(
       'public.renew_hotel_subscription(uuid,jsonb)'
     ) is null
     or to_regprocedure(
       'private.require_platform_admin_20260728()'
     ) is null
     or to_regprocedure(
       'private.record_subscription_action_20260728(uuid,uuid,text,text,uuid,text,text,uuid,uuid,text,text,text,jsonb,jsonb)'
     ) is null
  then
    raise exception
      'Migration 024 stopped: accepted lifecycle helpers are missing.';
  end if;
end;
$preflight$;

-- ============================================================================
-- 1. SUBSCRIPTION PAYMENT-LINK LEDGER
-- ============================================================================

create table if not exists public.subscription_payment_links (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null
    references public.hotels(id) on delete cascade,
  plan_id uuid not null
    references public.subscription_plans(id) on delete restrict,
  subscription_id uuid
    references public.hotel_subscriptions(id) on delete set null,

  provider text not null,
  provider_link_id text,
  reference_id text not null,
  idempotency_key text,

  status text not null default 'creating',
  billing_cycle text not null default 'monthly',
  currency_code text not null default 'INR',
  amount_minor bigint not null,

  provider_url text,
  provider_payment_id text,
  customer_name text,
  customer_email text,
  customer_phone text,

  expires_at timestamptz,
  paid_at timestamptz,
  cancelled_at timestamptz,
  failed_at timestamptz,
  failure_reason text,

  metadata jsonb not null default '{}'::jsonb,
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint subscription_payment_links_provider_not_blank
    check (length(trim(provider)) > 0),
  constraint subscription_payment_links_reference_not_blank
    check (length(trim(reference_id)) > 0),
  constraint subscription_payment_links_status_check
    check (
      status in (
        'creating',
        'created',
        'issued',
        'partially_paid',
        'paid',
        'expired',
        'cancelled',
        'failed'
      )
    ),
  constraint subscription_payment_links_cycle_check
    check (billing_cycle in ('monthly', 'annual', 'one_time')),
  constraint subscription_payment_links_currency_check
    check (currency_code ~ '^[A-Z]{3}$'),
  constraint subscription_payment_links_amount_check
    check (amount_minor > 0),
  constraint subscription_payment_links_metadata_object
    check (jsonb_typeof(metadata) = 'object'),
  constraint subscription_payment_links_paid_contract
    check (
      status <> 'paid'
      or (
        paid_at is not null
        and provider_payment_id is not null
      )
    )
);

create unique index if not exists
  uq_subscription_payment_links_provider_link
on public.subscription_payment_links (
  provider,
  provider_link_id
)
where provider_link_id is not null;

create unique index if not exists
  uq_subscription_payment_links_provider_reference
on public.subscription_payment_links (
  provider,
  reference_id
);

create unique index if not exists
  uq_subscription_payment_links_idempotency
on public.subscription_payment_links (
  idempotency_key
)
where idempotency_key is not null;

create index if not exists
  idx_subscription_payment_links_hotel_created
on public.subscription_payment_links (
  hotel_id,
  created_at desc
);

create index if not exists
  idx_subscription_payment_links_status_expiry
on public.subscription_payment_links (
  status,
  expires_at
);

drop trigger if exists
  set_subscription_payment_links_updated_at
on public.subscription_payment_links;

create trigger set_subscription_payment_links_updated_at
before update on public.subscription_payment_links
for each row execute function private.set_updated_at();

revoke all on public.subscription_payment_links
from public, anon, authenticated;

grant select on public.subscription_payment_links
to authenticated;

alter table public.subscription_payment_links
  enable row level security;

drop policy if exists
  stayqr_subscription_payment_links_select
on public.subscription_payment_links;

create policy stayqr_subscription_payment_links_select
on public.subscription_payment_links
for select to authenticated
using (
  private.is_platform_admin()
  or private.user_has_hotel_access(hotel_id)
);

-- Browser roles cannot write payment-provider records. All writes are made by
-- trusted Edge Functions with the service-role key.
drop policy if exists
  stayqr_subscription_payment_links_platform_insert
on public.subscription_payment_links;

drop policy if exists
  stayqr_subscription_payment_links_platform_update
on public.subscription_payment_links;

drop policy if exists
  stayqr_subscription_payment_links_platform_delete
on public.subscription_payment_links;

-- ============================================================================
-- 2. TRUSTED PROVIDER-WEBHOOK LIFECYCLE ACTION
-- ============================================================================

create or replace function
  public.apply_provider_subscription_event(
    payload jsonb
  )
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_role text :=
    current_setting('request.jwt.claim.role', true);

  event_action text;
  provider_value text;
  provider_event_id_value text;
  idempotency_value text;

  target_hotel_id uuid;
  target_plan_id uuid;
  target_subscription_id uuid;

  billing_cycle_value text;
  currency_value text;
  amount_value bigint;
  period_start_value timestamptz;
  period_end_value timestamptz;
  grace_end_value timestamptz;

  provider_subscription_id_value text;
  provider_payment_link_id_value text;
  provider_payment_id_value text;
  provider_status_value text;

  current_row public.hotel_subscriptions%rowtype;
  old_status_value text;
  result jsonb;
  existing_result jsonb;
begin
  if caller_role <> 'service_role' then
    raise exception
      'Service-role access required for provider webhook application.';
  end if;

  if payload is null or jsonb_typeof(payload) <> 'object' then
    raise exception 'Provider event payload must be a JSON object.';
  end if;

  event_action :=
    lower(nullif(trim(payload ->> 'event_action'), ''));
  provider_value :=
    lower(coalesce(nullif(trim(payload ->> 'provider'), ''), 'manual'));
  provider_event_id_value :=
    nullif(trim(payload ->> 'provider_event_id'), '');
  idempotency_value := case
    when provider_event_id_value is null then
      nullif(trim(payload ->> 'idempotency_key'), '')
    else
      provider_value || ':webhook:' || provider_event_id_value
  end;

  target_hotel_id :=
    nullif(trim(payload ->> 'hotel_id'), '')::uuid;
  target_plan_id :=
    nullif(trim(payload ->> 'plan_id'), '')::uuid;
  target_subscription_id :=
    nullif(trim(payload ->> 'subscription_id'), '')::uuid;

  billing_cycle_value :=
    coalesce(nullif(trim(payload ->> 'billing_cycle'), ''), 'monthly');
  currency_value :=
    upper(coalesce(nullif(trim(payload ->> 'currency_code'), ''), 'INR'));
  amount_value :=
    coalesce(nullif(trim(payload ->> 'amount_minor'), '')::bigint, 0);
  period_start_value :=
    coalesce(
      nullif(trim(payload ->> 'current_period_start'), '')::timestamptz,
      now()
    );
  period_end_value :=
    nullif(trim(payload ->> 'current_period_end'), '')::timestamptz;
  grace_end_value :=
    nullif(trim(payload ->> 'grace_ends_at'), '')::timestamptz;

  provider_subscription_id_value :=
    nullif(trim(payload ->> 'provider_subscription_id'), '');
  provider_payment_link_id_value :=
    nullif(trim(payload ->> 'provider_payment_link_id'), '');
  provider_payment_id_value :=
    nullif(trim(payload ->> 'provider_payment_id'), '');
  provider_status_value :=
    coalesce(
      nullif(trim(payload ->> 'provider_status'), ''),
      event_action
    );

  if event_action not in (
    'payment_succeeded',
    'payment_failed',
    'subscription_suspended',
    'subscription_cancelled',
    'subscription_resumed'
  ) then
    raise exception
      'Unsupported provider event action: %.',
      coalesce(event_action, 'missing');
  end if;

  if target_hotel_id is null then
    raise exception 'Provider event hotel_id is required.';
  end if;

  existing_result :=
    private.subscription_action_result_20260728(idempotency_value);

  if existing_result is not null then
    return existing_result
      || jsonb_build_object('idempotent', true);
  end if;

  select hs.*
  into current_row
  from public.hotel_subscriptions hs
  where hs.hotel_id = target_hotel_id
    and (
      target_subscription_id is null
      or hs.id = target_subscription_id
    )
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

  if event_action in ('payment_succeeded', 'subscription_resumed') then
    target_plan_id := coalesce(target_plan_id, current_row.plan_id);

    if target_plan_id is null
       or period_end_value is null
       or period_end_value <= period_start_value
       or amount_value < 0
    then
      raise exception
        'Successful provider events require plan, valid period and non-negative amount.';
    end if;

    if found
       and current_row.status = 'active'
       and current_row.billing_mode = 'paid'
    then
      return public.renew_hotel_subscription(
        target_hotel_id,
        jsonb_build_object(
          'billing_cycle', billing_cycle_value,
          'currency_code', currency_value,
          'amount_minor', amount_value,
          'provider', provider_value,
          'provider_status', provider_status_value,
          'provider_subscription_id',
            coalesce(
              provider_subscription_id_value,
              current_row.provider_subscription_id
            ),
          'provider_payment_link_id',
            coalesce(
              provider_payment_link_id_value,
              current_row.provider_payment_link_id
            ),
          'current_period_start', period_start_value,
          'current_period_end', period_end_value,
          'last_payment_at', now(),
          'idempotency_key', idempotency_value,
          'provider_event_id', provider_event_id_value,
          'provider_metadata',
            coalesce(payload -> 'provider_metadata', '{}'::jsonb)
              || jsonb_build_object(
                'provider_payment_id',
                provider_payment_id_value
              ),
          'metadata',
            jsonb_build_object(
              'provider_event_action', event_action
            )
        )
      );
    end if;

    return public.activate_paid_subscription(
      target_hotel_id,
      jsonb_build_object(
        'plan_id', target_plan_id,
        'billing_cycle', billing_cycle_value,
        'currency_code', currency_value,
        'amount_minor', amount_value,
        'provider', provider_value,
        'provider_status', provider_status_value,
        'provider_subscription_id',
          provider_subscription_id_value,
        'provider_payment_link_id',
          provider_payment_link_id_value,
        'current_period_start', period_start_value,
        'current_period_end', period_end_value,
        'last_payment_at', now(),
        'idempotency_key', idempotency_value,
        'provider_event_id', provider_event_id_value,
        'provider_metadata',
          coalesce(payload -> 'provider_metadata', '{}'::jsonb)
            || jsonb_build_object(
              'provider_payment_id',
              provider_payment_id_value
            ),
        'metadata',
          jsonb_build_object(
            'provider_event_action', event_action
          )
      )
    );
  end if;

  if not found then
    raise exception
      'No current subscription was found for provider event action %.',
      event_action;
  end if;

  old_status_value := current_row.status;

  perform set_config(
    'stayqr.subscription_event_source',
    'provider_webhook',
    true
  );

  if event_action = 'payment_failed' then
    update public.hotel_subscriptions hs
    set
      status = case
        when hs.status in ('suspended', 'cancelled', 'expired')
          then hs.status
        else 'past_due'
      end,
      provider = provider_value,
      provider_status = provider_status_value,
      provider_subscription_id = coalesce(
        provider_subscription_id_value,
        hs.provider_subscription_id
      ),
      provider_payment_link_id = coalesce(
        provider_payment_link_id_value,
        hs.provider_payment_link_id
      ),
      grace_ends_at = coalesce(
        grace_end_value,
        hs.grace_ends_at,
        now() + interval '3 days'
      ),
      provider_metadata =
        coalesce(hs.provider_metadata, '{}'::jsonb)
        || coalesce(payload -> 'provider_metadata', '{}'::jsonb),
      updated_at = now()
    where hs.id = current_row.id
    returning * into current_row;

    update public.hotels h
    set
      subscription_status = current_row.status,
      updated_at = now()
    where h.id = target_hotel_id;

  elsif event_action = 'subscription_suspended' then
    update public.hotel_subscriptions hs
    set
      status = 'suspended',
      provider = provider_value,
      provider_status = provider_status_value,
      provider_subscription_id = coalesce(
        provider_subscription_id_value,
        hs.provider_subscription_id
      ),
      suspended_at = coalesce(hs.suspended_at, now()),
      provider_metadata =
        coalesce(hs.provider_metadata, '{}'::jsonb)
        || coalesce(payload -> 'provider_metadata', '{}'::jsonb),
      updated_at = now()
    where hs.id = current_row.id
    returning * into current_row;

    update public.hotels h
    set
      status = 'suspended',
      subscription_status = 'suspended',
      updated_at = now()
    where h.id = target_hotel_id;

  elsif event_action = 'subscription_cancelled' then
    update public.hotel_subscriptions hs
    set
      status = 'cancelled',
      provider = provider_value,
      provider_status = provider_status_value,
      provider_subscription_id = coalesce(
        provider_subscription_id_value,
        hs.provider_subscription_id
      ),
      cancelled_at = coalesce(hs.cancelled_at, now()),
      cancellation_reason = coalesce(
        nullif(trim(payload ->> 'reason'), ''),
        hs.cancellation_reason,
        'Provider subscription cancelled.'
      ),
      provider_metadata =
        coalesce(hs.provider_metadata, '{}'::jsonb)
        || coalesce(payload -> 'provider_metadata', '{}'::jsonb),
      updated_at = now()
    where hs.id = current_row.id
    returning * into current_row;

    update public.hotels h
    set
      status = 'suspended',
      subscription_status = 'cancelled',
      updated_at = now()
    where h.id = target_hotel_id;
  end if;

  result := jsonb_build_object(
    'hotel_id', target_hotel_id,
    'subscription_id', current_row.id,
    'event_action', event_action,
    'status', current_row.status,
    'provider', provider_value,
    'provider_event_id', provider_event_id_value,
    'idempotent', false
  );

  return private.record_subscription_action_20260728(
    target_hotel_id,
    current_row.id,
    'provider_' || event_action,
    'provider_webhook',
    null,
    old_status_value,
    current_row.status,
    current_row.plan_id,
    current_row.plan_id,
    provider_value,
    provider_event_id_value,
    idempotency_value,
    jsonb_build_object(
      'provider_status', provider_status_value,
      'provider_payment_id', provider_payment_id_value,
      'safe_metadata',
        coalesce(payload -> 'provider_metadata', '{}'::jsonb)
    ),
    result
  );
end;
$$;

revoke all on function
  public.apply_provider_subscription_event(jsonb)
from public, anon, authenticated;

grant execute on function
  public.apply_provider_subscription_event(jsonb)
to service_role;

-- ============================================================================
-- 3. CONTROLLED SUPER ADMIN COMMERCIAL DATA RPC
-- ============================================================================

create or replace function
  public.get_super_admin_commercial_data(
    row_limit integer default 100
  )
returns jsonb
language plpgsql
security definer
stable
set search_path = ''
as $$
declare
  actor_user_id uuid :=
    private.require_platform_admin_20260728();
  safe_limit integer := greatest(1, least(coalesce(row_limit, 100), 250));
begin
  return jsonb_build_object(
    'generated_at', now(),
    'generated_by', actor_user_id,
    'summary', public.get_super_admin_dashboard(),

    'hotels', (
      select coalesce(
        jsonb_agg(to_jsonb(hotel_row) order by hotel_row.created_at desc),
        '[]'::jsonb
      )
      from (
        select
          h.id,
          h.hotel_name,
          h.slug,
          h.location,
          h.city,
          h.state,
          h.status,
          h.subscription_status,
          h.currency_code,
          h.created_at,
          hs.id as subscription_id,
          hs.plan_id,
          sp.plan_name,
          sp.plan_code,
          hs.status as lifecycle_status,
          hs.billing_mode,
          hs.billing_cycle,
          hs.amount_minor,
          hs.currency_code as subscription_currency,
          hs.provider,
          hs.provider_status,
          hs.provider_subscription_id,
          hs.provider_payment_link_id,
          hs.trial_ends_at,
          hs.current_period_start,
          hs.current_period_end,
          hs.grace_ends_at,
          hs.last_payment_at
        from public.hotels h
        left join lateral (
          select current_hs.*
          from public.hotel_subscriptions current_hs
          where current_hs.hotel_id = h.id
          order by
            case
              when current_hs.status in (
                'trial',
                'trialing',
                'active',
                'past_due',
                'suspended'
              ) then 0
              else 1
            end,
            coalesce(current_hs.updated_at, current_hs.created_at) desc,
            current_hs.id desc
          limit 1
        ) hs on true
        left join public.subscription_plans sp on sp.id = hs.plan_id
        order by h.created_at desc
        limit safe_limit
      ) hotel_row
    ),

    'plans', (
      select coalesce(
        jsonb_agg(to_jsonb(plan_row) order by plan_row.price_monthly, plan_row.plan_name),
        '[]'::jsonb
      )
      from (
        select
          sp.id,
          sp.plan_name,
          sp.plan_code,
          sp.price_monthly,
          sp.price_annual,
          sp.currency_code,
          sp.max_rooms,
          sp.max_staff,
          sp.max_properties,
          sp.max_storage_mb,
          sp.trial_days,
          sp.features,
          sp.is_public,
          sp.status,
          sp.created_at,
          (
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
          ) as current_hotels,
          (
            select coalesce(
              jsonb_agg(
                jsonb_build_object(
                  'provider', spp.provider,
                  'billing_cycle', spp.billing_cycle,
                  'currency_code', spp.currency_code,
                  'amount_minor', spp.amount_minor,
                  'provider_plan_id', spp.provider_plan_id,
                  'status', spp.status
                )
                order by spp.provider, spp.billing_cycle
              ),
              '[]'::jsonb
            )
            from public.subscription_plan_prices spp
            where spp.plan_id = sp.id
          ) as provider_prices
        from public.subscription_plans sp
      ) plan_row
    ),

    'usage', (
      select coalesce(
        jsonb_agg(to_jsonb(usage_row) order by usage_row.hotel_id, usage_row.metric_key),
        '[]'::jsonb
      )
      from (
        select
          uc.hotel_id,
          h.hotel_name,
          uc.metric_key,
          uc.current_value,
          uc.limit_value,
          uc.captured_at
        from public.usage_counters uc
        join public.hotels h on h.id = uc.hotel_id
        order by uc.captured_at desc
        limit safe_limit * 10
      ) usage_row
    ),

    'payment_links', (
      select coalesce(
        jsonb_agg(to_jsonb(link_row) order by link_row.created_at desc),
        '[]'::jsonb
      )
      from (
        select
          spl.id,
          spl.hotel_id,
          h.hotel_name,
          spl.plan_id,
          sp.plan_name,
          spl.subscription_id,
          spl.provider,
          spl.provider_link_id,
          spl.reference_id,
          spl.status,
          spl.billing_cycle,
          spl.currency_code,
          spl.amount_minor,
          spl.provider_url,
          spl.provider_payment_id,
          spl.customer_name,
          spl.customer_email,
          spl.customer_phone,
          spl.expires_at,
          spl.paid_at,
          spl.failure_reason,
          spl.created_at,
          spl.updated_at
        from public.subscription_payment_links spl
        join public.hotels h on h.id = spl.hotel_id
        join public.subscription_plans sp on sp.id = spl.plan_id
        order by spl.created_at desc
        limit safe_limit
      ) link_row
    ),

    'support_tickets', (
      select coalesce(
        jsonb_agg(to_jsonb(ticket_row) order by ticket_row.updated_at desc),
        '[]'::jsonb
      )
      from (
        select
          st.id,
          st.hotel_id,
          h.hotel_name,
          st.subject,
          st.description,
          st.category,
          st.priority,
          st.status,
          st.created_by,
          st.assigned_to,
          st.last_response_at,
          st.resolved_at,
          st.closed_at,
          st.created_at,
          st.updated_at
        from public.support_tickets st
        join public.hotels h on h.id = st.hotel_id
        order by st.updated_at desc
        limit safe_limit
      ) ticket_row
    ),

    'subscription_events', (
      select coalesce(
        jsonb_agg(to_jsonb(event_row) order by event_row.occurred_at desc),
        '[]'::jsonb
      )
      from (
        select
          se.id,
          se.hotel_id,
          h.hotel_name,
          se.subscription_id,
          se.event_type,
          se.event_source,
          se.old_status,
          se.new_status,
          se.old_plan_id,
          se.new_plan_id,
          se.provider,
          se.provider_event_id,
          se.details,
          se.occurred_at
        from public.subscription_events se
        join public.hotels h on h.id = se.hotel_id
        order by se.occurred_at desc
        limit safe_limit
      ) event_row
    ),

    'webhook_events', (
      select coalesce(
        jsonb_agg(to_jsonb(webhook_row) order by webhook_row.received_at desc),
        '[]'::jsonb
      )
      from (
        select
          we.id,
          we.provider,
          we.provider_event_id,
          we.event_type,
          we.processing_status,
          we.signature_valid,
          we.attempts,
          we.last_error,
          we.received_at,
          we.processed_at,
          we.subscription_id,
          we.hotel_id,
          h.hotel_name
        from public.webhook_events we
        left join public.hotels h on h.id = we.hotel_id
        order by we.received_at desc
        limit safe_limit
      ) webhook_row
    )
  );
end;
$$;

revoke all on function
  public.get_super_admin_commercial_data(integer)
from public, anon, authenticated;

grant execute on function
  public.get_super_admin_commercial_data(integer)
to authenticated;

-- ============================================================================
-- 4. POST-MIGRATION ASSERTIONS
-- ============================================================================

do $verify$
begin
  if not (
    select c.relrowsecurity
    from pg_class c
    where c.oid = 'public.subscription_payment_links'::regclass
  ) then
    raise exception
      'Migration 024 failed: payment-link RLS is not enabled.';
  end if;

  if has_table_privilege(
       'anon',
       'public.subscription_payment_links',
       'SELECT'
     )
     or has_table_privilege(
       'anon',
       'public.subscription_payment_links',
       'INSERT'
     )
     or has_function_privilege(
       'anon',
       'public.get_super_admin_commercial_data(integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'public.apply_provider_subscription_event(jsonb)',
       'EXECUTE'
     )
  then
    raise exception
      'Migration 024 failed: an unsafe anonymous/browser grant exists.';
  end if;

  if not has_function_privilege(
       'service_role',
       'public.apply_provider_subscription_event(jsonb)',
       'EXECUTE'
     )
  then
    raise exception
      'Migration 024 failed: service-role webhook action grant is missing.';
  end if;
end;
$verify$;

commit;

-- ============================================================================
-- 5. ACCEPTANCE RESULT
-- ============================================================================

with checks(test_name, passed, details) as (
  values
    (
      '01_payment_link_table',
      to_regclass('public.subscription_payment_links') is not null,
      'Auditable SaaS payment-link ledger exists.'
    ),
    (
      '02_payment_link_rls',
      (
        select c.relrowsecurity
        from pg_class c
        where c.oid = 'public.subscription_payment_links'::regclass
      ),
      'Payment-link ledger has RLS enabled.'
    ),
    (
      '03_payment_link_owner_platform_select',
      exists (
        select 1
        from pg_policies p
        where p.schemaname = 'public'
          and p.tablename = 'subscription_payment_links'
          and p.policyname = 'stayqr_subscription_payment_links_select'
      ),
      'Platform Admin and own-hotel users can read only permitted link records.'
    ),
    (
      '04_anonymous_payment_link_access_blocked',
      not has_table_privilege(
        'anon',
        'public.subscription_payment_links',
        'SELECT'
      )
      and not has_table_privilege(
        'anon',
        'public.subscription_payment_links',
        'INSERT'
      ),
      'Anonymous users cannot read or create SaaS billing links.'
    ),
    (
      '05_browser_payment_link_write_blocked',
      not has_table_privilege(
        'authenticated',
        'public.subscription_payment_links',
        'INSERT'
      )
      and not has_table_privilege(
        'authenticated',
        'public.subscription_payment_links',
        'UPDATE'
      )
      and not has_table_privilege(
        'authenticated',
        'public.subscription_payment_links',
        'DELETE'
      ),
      'Payment-provider records are server-owned.'
    ),
    (
      '06_provider_link_uniqueness',
      to_regclass(
        'public.uq_subscription_payment_links_provider_link'
      ) is not null,
      'The same provider link ID cannot be recorded twice.'
    ),
    (
      '07_provider_reference_uniqueness',
      to_regclass(
        'public.uq_subscription_payment_links_provider_reference'
      ) is not null,
      'Provider reference IDs are unique.'
    ),
    (
      '08_payment_link_idempotency',
      to_regclass(
        'public.uq_subscription_payment_links_idempotency'
      ) is not null,
      'Repeated create-link requests can reuse one result safely.'
    ),
    (
      '09_payment_link_status_contract',
      exists (
        select 1
        from pg_constraint c
        where c.conrelid =
          'public.subscription_payment_links'::regclass
          and c.conname =
            'subscription_payment_links_status_check'
      ),
      'Payment-link lifecycle statuses are constrained.'
    ),
    (
      '10_paid_link_evidence_contract',
      exists (
        select 1
        from pg_constraint c
        where c.conrelid =
          'public.subscription_payment_links'::regclass
          and c.conname =
            'subscription_payment_links_paid_contract'
      ),
      'A paid link requires paid timestamp and provider payment ID.'
    ),
    (
      '11_provider_event_rpc',
      to_regprocedure(
        'public.apply_provider_subscription_event(jsonb)'
      ) is not null,
      'Trusted normalized provider webhook lifecycle RPC exists.'
    ),
    (
      '12_provider_event_service_role',
      has_function_privilege(
        'service_role',
        'public.apply_provider_subscription_event(jsonb)',
        'EXECUTE'
      ),
      'Only trusted server/webhook code can apply provider events.'
    ),
    (
      '13_provider_event_browser_blocked',
      not has_function_privilege(
        'authenticated',
        'public.apply_provider_subscription_event(jsonb)',
        'EXECUTE'
      )
      and not has_function_privilege(
        'anon',
        'public.apply_provider_subscription_event(jsonb)',
        'EXECUTE'
      ),
      'Browser and anonymous callers cannot forge payment events.'
    ),
    (
      '14_provider_event_success_action',
      position(
        'payment_succeeded'
        in pg_get_functiondef(
          'public.apply_provider_subscription_event(jsonb)'::regprocedure
        )
      ) > 0,
      'Successful provider payments activate or renew through accepted lifecycle RPCs.'
    ),
    (
      '15_provider_event_failure_action',
      position(
        'payment_failed'
        in pg_get_functiondef(
          'public.apply_provider_subscription_event(jsonb)'::regprocedure
        )
      ) > 0,
      'Provider payment failure can enter past-due/grace state.'
    ),
    (
      '16_provider_event_cancel_suspend',
      position(
        'subscription_cancelled'
        in pg_get_functiondef(
          'public.apply_provider_subscription_event(jsonb)'::regprocedure
        )
      ) > 0
      and position(
        'subscription_suspended'
        in pg_get_functiondef(
          'public.apply_provider_subscription_event(jsonb)'::regprocedure
        )
      ) > 0,
      'Provider cancellation and suspension actions are supported.'
    ),
    (
      '17_provider_event_idempotency',
      position(
        'subscription_action_result_20260728'
        in pg_get_functiondef(
          'public.apply_provider_subscription_event(jsonb)'::regprocedure
        )
      ) > 0,
      'Repeated provider events return the original lifecycle result.'
    ),
    (
      '18_commercial_control_rpc',
      to_regprocedure(
        'public.get_super_admin_commercial_data(integer)'
      ) is not null,
      'One controlled Super Admin commercial-data RPC exists.'
    ),
    (
      '19_commercial_rpc_authenticated',
      has_function_privilege(
        'authenticated',
        'public.get_super_admin_commercial_data(integer)',
        'EXECUTE'
      ),
      'Authenticated Platform Admin frontend can execute the control RPC.'
    ),
    (
      '20_commercial_rpc_anonymous_blocked',
      not has_function_privilege(
        'anon',
        'public.get_super_admin_commercial_data(integer)',
        'EXECUTE'
      ),
      'Anonymous callers cannot retrieve platform commercial data.'
    ),
    (
      '21_commercial_rpc_safe_webhook_projection',
      position(
        'we.payload'
        in lower(
          pg_get_functiondef(
            'public.get_super_admin_commercial_data(integer)'::regprocedure
          )
        )
      ) = 0
      and position(
        'we.headers'
        in lower(
          pg_get_functiondef(
            'public.get_super_admin_commercial_data(integer)'::regprocedure
          )
        )
      ) = 0,
      'Super Admin response excludes webhook payload and header bodies.'
    ),
    (
      '22_existing_lifecycle_preserved',
      to_regprocedure(
        'public.activate_paid_subscription(uuid,jsonb)'
      ) is not null
      and to_regprocedure(
        'public.renew_hotel_subscription(uuid,jsonb)'
      ) is not null
      and to_regprocedure(
        'public.get_super_admin_dashboard()'
      ) is not null,
      'Accepted Day 9 lifecycle and MRR functions remain installed.'
    ),
    (
      '23_day8_onboarding_preserved',
      to_regprocedure(
        'public.bootstrap_hotel_onboarding(jsonb)'
      ) is not null
      and to_regprocedure(
        'public.import_hotel_rooms(uuid,jsonb)'
      ) is not null,
      'Locked Day 8 onboarding remains installed.'
    ),
    (
      '24_day9_provider_frontend_foundation_ready',
      to_regclass('public.subscription_payment_links') is not null
      and to_regprocedure(
        'public.apply_provider_subscription_event(jsonb)'
      ) is not null
      and to_regprocedure(
        'public.get_super_admin_commercial_data(integer)'
      ) is not null,
      'Database is ready for signed Cashfree Payment Link/webhook Edge Functions and the Day 9 Super Admin frontend.'
    )
)
select test_name, passed, details
from checks
order by test_name;
