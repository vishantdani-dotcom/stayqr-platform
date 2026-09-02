begin;

select set_config('request.jwt.claim.role', 'service_role', true);

do $$
declare
  v_hotel_id uuid;
  v_plan_id uuid;
  v_amount_minor bigint;
  v_result jsonb;
  v_payment_id uuid;
  v_subscription_id uuid;
  v_reference text := 'STAGING-ROLLBACK-SMOKE-20260902';
  v_action_key text := 'pilot-manual-billing:staging-rollback-smoke:20260902';
begin
  select h.id
  into v_hotel_id
  from public.hotels h
  where h.hotel_name = '20E Test Hotel'
     or h.slug ilike '%20e%test%'
  order by (h.hotel_name = '20E Test Hotel') desc, h.created_at desc
  limit 1;

  if v_hotel_id is null then
    raise exception 'The dedicated staging smoke-test hotel was not found.';
  end if;

  select hs.plan_id
  into v_plan_id
  from public.hotel_subscriptions hs
  join public.subscription_plans sp on sp.id = hs.plan_id and sp.status = 'active'
  where hs.hotel_id = v_hotel_id
  order by
    case when hs.status in ('trial', 'trialing', 'active', 'past_due', 'suspended') then 0 else 1 end,
    coalesce(hs.updated_at, hs.created_at) desc,
    hs.id desc
  limit 1;

  if v_plan_id is null then
    select sp.id
    into v_plan_id
    from public.subscription_plans sp
    where sp.status = 'active'
    order by sp.is_public desc, sp.price_monthly, sp.id
    limit 1;
  end if;

  if v_plan_id is null then
    raise exception 'No active staging subscription plan was found.';
  end if;

  select greatest(coalesce(round(sp.price_monthly * 100)::bigint, 100), 1)
  into v_amount_minor
  from public.subscription_plans sp
  where sp.id = v_plan_id;

  if exists (
    select 1
    from public.subscription_manual_payments payment
    where payment.idempotency_key = v_action_key
       or lower(payment.payment_reference) = lower(v_reference)
  ) then
    raise exception 'The rollback smoke-test identifiers unexpectedly already exist.';
  end if;

  v_result := public.record_manual_subscription_payment(
    v_hotel_id,
    jsonb_build_object(
      'plan_id', v_plan_id,
      'billing_cycle', 'monthly',
      'amount_minor', v_amount_minor,
      'currency_code', 'INR',
      'payment_method', 'other',
      'payment_reference', v_reference,
      'paid_at', now(),
      'period_start', now(),
      'period_end', now() + interval '30 days',
      'note', 'Transactional staging smoke test; rolled back immediately.',
      'idempotency_key', v_action_key,
      'metadata', jsonb_build_object('staging_transactional_smoke', true)
    )
  );

  if coalesce((v_result ->> 'ok')::boolean, false) is not true then
    raise exception 'Manual-payment RPC did not return ok=true.';
  end if;

  v_payment_id := nullif(v_result #>> '{payment,id}', '')::uuid;
  v_subscription_id := nullif(v_result #>> '{subscription,subscription_id}', '')::uuid;

  if v_payment_id is null or v_subscription_id is null then
    raise exception 'Manual-payment RPC returned incomplete identifiers.';
  end if;

  if not exists (
    select 1
    from public.subscription_manual_payments payment
    where payment.id = v_payment_id
      and payment.hotel_id = v_hotel_id
      and payment.subscription_id = v_subscription_id
      and payment.status = 'confirmed'
  ) then
    raise exception 'Confirmed manual-payment evidence was not written.';
  end if;

  if not exists (
    select 1
    from public.hotel_subscriptions hs
    where hs.id = v_subscription_id
      and hs.hotel_id = v_hotel_id
      and hs.status = 'active'
      and hs.billing_mode = 'paid'
      and hs.provider = 'manual'
  ) then
    raise exception 'The staging subscription was not activated or renewed correctly.';
  end if;

  if not exists (
    select 1
    from public.subscription_events event
    where event.hotel_id = v_hotel_id
      and event.subscription_id = v_subscription_id
      and event.event_type = 'manual_payment_recorded'
      and event.idempotency_key = v_action_key || ':payment-event'
  ) then
    raise exception 'Immutable manual-payment lifecycle evidence was not written.';
  end if;
end;
$$;

rollback;
