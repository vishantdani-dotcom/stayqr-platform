-- StayQR v1.0
-- Day 9 Migration 025 REV2
-- Paid-subscription activation FOUND guard + payment-ledger linkage
-- + targeted idempotent repair for the accepted Apex Cashfree sandbox payment.
--
-- Root cause:
-- activate_paid_subscription selected the current subscription and then called
-- PERFORM set_config(...) before IF FOUND. PERFORM overwrote FOUND, so an
-- expired prior subscription incorrectly entered the UPDATE branch with a null
-- row, while the hotel and immutable event were still updated.
--
-- This migration:
-- 1. Captures FOUND immediately in subscription_found.
-- 2. Refuses to record success unless a valid active paid row exists.
-- 3. Links the matching subscription_payment_links row atomically.
-- 4. Repairs the existing Apex transaction without another payment.
-- 5. Preserves the immutable defective event and adds a compensating repair event.
--
-- REV2 fixes the missing function-terminator semicolon in REV1.
-- Safe to rerun. Transactional.

begin;

CREATE OR REPLACE FUNCTION public.activate_paid_subscription(target_hotel_id uuid, payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  subscription_found boolean := false;
  provider_payment_link_value text;
  linked_subscription_id uuid;
  payment_link_found boolean := false;
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
  provider_payment_link_value :=
    nullif(trim(payload ->> 'provider_payment_link_id'), '');
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

  subscription_found := found;

  perform set_config(
    'stayqr.subscription_event_source',
    'activate_paid_subscription',
    true
  );

  if subscription_found then
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

  if subscription_row.id is null
     or subscription_row.status <> 'active'
     or subscription_row.billing_mode <> 'paid'
     or subscription_row.plan_id is distinct from plan_id_value
  then
    raise exception
      'Paid subscription activation did not produce a valid active paid subscription.';
  end if;

  if provider_payment_link_value is not null then
    select spl.subscription_id
    into linked_subscription_id
    from public.subscription_payment_links spl
    where spl.hotel_id = target_hotel_id
      and spl.provider = provider_value
      and spl.provider_link_id = provider_payment_link_value
    limit 1
    for update;

    payment_link_found := found;

    if payment_link_found
       and linked_subscription_id is not null
       and linked_subscription_id <> subscription_row.id
    then
      raise exception
        'Provider payment link is already linked to another subscription.';
    end if;

    if payment_link_found then
      update public.subscription_payment_links spl
      set
        subscription_id = subscription_row.id,
        updated_at = now()
      where spl.hotel_id = target_hotel_id
        and spl.provider = provider_value
        and spl.provider_link_id = provider_payment_link_value;
    end if;
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
$function$;


do $repair$
declare
  target_hotel_id constant uuid :=
    '9e105be7-0d93-4dc9-84c6-f729b53f1368'::uuid;
  target_payment_id constant text := '5114933104179';
  target_link_id constant text :=
    'stayqr_9e105be7_b0540bd4801d4cf2b6e215b2';
  original_provider_event_id constant text :=
    'payment_link:stayqr_9e105be7_b0540bd4801d4cf2b6e215b2:PAID:5114933104179';
  repair_key constant text :=
    'day9:m025:apex-paid-activation-repair:5114933104179';

  link_row public.subscription_payment_links%rowtype;
  subscription_row public.hotel_subscriptions%rowtype;
  prior_subscription_row public.hotel_subscriptions%rowtype;
  subscription_found boolean := false;
  prior_subscription_found boolean := false;
  period_start_value timestamptz;
  period_end_value timestamptz;
begin
  perform pg_advisory_xact_lock(
    hashtext('stayqr:m025:repair:' || target_hotel_id::text)
  );

  select spl.*
  into link_row
  from public.subscription_payment_links spl
  where spl.hotel_id = target_hotel_id
    and spl.provider = 'cashfree'
    and spl.provider_payment_id = target_payment_id
    and spl.provider_link_id = target_link_id
  limit 1
  for update;

  if not found then
    -- The deployment may be applied to another environment where this
    -- exact sandbox transaction does not exist. The function hardening
    -- still applies; the targeted repair is simply skipped.
    return;
  end if;

  if link_row.status <> 'paid'
     or link_row.paid_at is null
     or link_row.plan_id is null
     or link_row.amount_minor <> 499900
     or link_row.currency_code <> 'INR'
     or link_row.billing_cycle <> 'monthly'
  then
    raise exception
      'Migration 025 repair guard failed: Apex payment-link contract does not match the accepted paid transaction.';
  end if;

  if link_row.subscription_id is not null then
    select hs.*
    into subscription_row
    from public.hotel_subscriptions hs
    where hs.id = link_row.subscription_id
      and hs.hotel_id = target_hotel_id
    limit 1
    for update;

    subscription_found := found;
  end if;

  if not subscription_found then
    select hs.*
    into subscription_row
    from public.hotel_subscriptions hs
    where hs.hotel_id = target_hotel_id
      and hs.status = 'active'
      and hs.billing_mode = 'paid'
      and hs.provider = 'cashfree'
      and hs.provider_payment_link_id = target_link_id
    order by
      coalesce(hs.updated_at, hs.created_at) desc,
      hs.id desc
    limit 1
    for update;

    subscription_found := found;
  end if;

  if not subscription_found then
    select hs.*
    into prior_subscription_row
    from public.hotel_subscriptions hs
    where hs.hotel_id = target_hotel_id
    order by
      coalesce(hs.updated_at, hs.created_at) desc,
      hs.id desc
    limit 1
    for update;

    prior_subscription_found := found;

    period_start_value := link_row.paid_at;
    period_end_value := link_row.paid_at + interval '1 month';

    perform set_config(
      'stayqr.subscription_event_source',
      'migration_025_paid_activation_repair',
      true
    );

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
      cancelled_at,
      cancellation_reason,
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
      grace_ends_at,
      suspended_at,
      reactivated_at,
      last_payment_at
    ) values (
      target_hotel_id,
      link_row.plan_id,
      'active',
      period_start_value,
      period_end_value,
      now(),
      null,
      null,
      link_row.paid_at,
      null,
      null,
      jsonb_build_object(
        'source', 'migration_025_paid_activation_repair',
        'repair_key', repair_key,
        'repaired_at', now(),
        'repaired_from_payment_link_id', link_row.id,
        'repaired_from_provider_payment_id', target_payment_id,
        'preserved_prior_subscription_id',
          case
            when prior_subscription_found
              then prior_subscription_row.id
            else null
          end
      ),
      now(),
      'paid',
      link_row.billing_cycle,
      link_row.currency_code,
      link_row.amount_minor,
      'cashfree',
      null,
      null,
      link_row.provider_link_id,
      'PAID',
      coalesce(link_row.metadata, '{}'::jsonb)
        || jsonb_build_object(
          'provider_payment_id', target_payment_id,
          'provider_event_id', original_provider_event_id,
          'repair_key', repair_key
        ),
      period_start_value,
      period_end_value,
      null,
      null,
      null,
      link_row.paid_at
    )
    returning * into subscription_row;

    subscription_found := subscription_row.id is not null;
  end if;

  if not subscription_found
     or subscription_row.status <> 'active'
     or subscription_row.billing_mode <> 'paid'
     or subscription_row.provider <> 'cashfree'
     or subscription_row.plan_id is distinct from link_row.plan_id
     or subscription_row.amount_minor <> link_row.amount_minor
     or subscription_row.current_period_start is null
     or subscription_row.current_period_end is null
     or subscription_row.current_period_end
          <= subscription_row.current_period_start
  then
    raise exception
      'Migration 025 repair failed to establish a valid active paid Apex subscription.';
  end if;

  update public.subscription_payment_links spl
  set
    subscription_id = subscription_row.id,
    updated_at = now()
  where spl.id = link_row.id
    and (
      spl.subscription_id is null
      or spl.subscription_id = subscription_row.id
    );

  if not found then
    raise exception
      'Migration 025 repair refused to relink a payment ledger already linked to another subscription.';
  end if;

  update public.hotels h
  set
    status = 'active',
    subscription_status = 'active',
    updated_at = now()
  where h.id = target_hotel_id;

  perform private.refresh_subscription_usage_internal(target_hotel_id);

  if not exists (
    select 1
    from public.subscription_events se
    where se.idempotency_key = repair_key
  ) then
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
      old_record,
      new_record,
      occurred_at,
      created_at
    ) values (
      target_hotel_id,
      subscription_row.id,
      'paid_subscription_activation_repaired',
      'migration_025',
      null,
      case
        when prior_subscription_found
          then prior_subscription_row.status
        else null
      end,
      subscription_row.status,
      case
        when prior_subscription_found
          then prior_subscription_row.plan_id
        else null
      end,
      subscription_row.plan_id,
      'cashfree',
      original_provider_event_id,
      repair_key,
      jsonb_build_object(
        'reason',
          'Migration 024 activation used FOUND after PERFORM set_config, producing a null activation result for an expired prior subscription.',
        'payment_link_id', link_row.id,
        'provider_link_id', link_row.provider_link_id,
        'provider_payment_id', target_payment_id,
        'amount_minor', link_row.amount_minor,
        'currency_code', link_row.currency_code,
        'billing_cycle', link_row.billing_cycle,
        'repaired_subscription_id', subscription_row.id
      ),
      case
        when prior_subscription_found
          then to_jsonb(prior_subscription_row)
        else null
      end,
      to_jsonb(subscription_row),
      now(),
      now()
    );
  end if;
end;
$repair$;


commit;
