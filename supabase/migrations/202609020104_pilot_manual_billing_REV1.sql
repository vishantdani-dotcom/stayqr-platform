begin;

create table if not exists public.subscription_manual_payments (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references public.hotels(id) on delete restrict,
  subscription_id uuid not null references public.hotel_subscriptions(id) on delete restrict,
  plan_id uuid not null references public.subscription_plans(id) on delete restrict,
  status text not null default 'confirmed',
  payment_method text not null,
  payment_reference text not null,
  amount_minor bigint not null,
  currency_code text not null default 'INR',
  billing_cycle text not null,
  paid_at timestamptz not null,
  period_start timestamptz not null,
  period_end timestamptz not null,
  note text,
  recorded_by uuid references auth.users(id) on delete set null,
  idempotency_key text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint subscription_manual_payments_status_check
    check (status = 'confirmed'),
  constraint subscription_manual_payments_method_check
    check (payment_method in ('upi', 'bank_transfer', 'cash', 'other')),
  constraint subscription_manual_payments_reference_check
    check (length(trim(payment_reference)) between 3 and 120),
  constraint subscription_manual_payments_amount_check
    check (amount_minor > 0),
  constraint subscription_manual_payments_currency_check
    check (currency_code ~ '^[A-Z]{3}$'),
  constraint subscription_manual_payments_cycle_check
    check (billing_cycle in ('monthly', 'annual')),
  constraint subscription_manual_payments_period_check
    check (period_end > period_start),
  constraint subscription_manual_payments_note_check
    check (note is null or length(note) <= 1000),
  constraint subscription_manual_payments_idempotency_check
    check (length(trim(idempotency_key)) between 8 and 200),
  constraint subscription_manual_payments_metadata_object
    check (jsonb_typeof(metadata) = 'object')
);

create unique index if not exists uq_subscription_manual_payments_idempotency
  on public.subscription_manual_payments (idempotency_key);

create unique index if not exists uq_subscription_manual_payments_reference
  on public.subscription_manual_payments (payment_method, lower(payment_reference));

create index if not exists idx_subscription_manual_payments_hotel_paid
  on public.subscription_manual_payments (hotel_id, paid_at desc);

create index if not exists idx_subscription_manual_payments_subscription_paid
  on public.subscription_manual_payments (subscription_id, paid_at desc);

alter table public.subscription_manual_payments enable row level security;

drop policy if exists subscription_manual_payments_select_pilot on public.subscription_manual_payments;
create policy subscription_manual_payments_select_pilot
  on public.subscription_manual_payments
  for select
  to authenticated
  using (
    private.is_platform_admin()
    or private.user_has_hotel_access(hotel_id)
  );

drop trigger if exists prevent_subscription_manual_payment_mutation_pilot
  on public.subscription_manual_payments;
create trigger prevent_subscription_manual_payment_mutation_pilot
  before update or delete on public.subscription_manual_payments
  for each row execute function private.prevent_immutable_event_mutation_20260728();

revoke all on table public.subscription_manual_payments from public, anon, authenticated;
grant select on table public.subscription_manual_payments to authenticated;
grant all on table public.subscription_manual_payments to service_role;

create or replace function public.record_manual_subscription_payment(
  p_hotel_id uuid,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_caller_role text := current_setting('request.jwt.claim.role', true);
  v_existing public.subscription_manual_payments%rowtype;
  v_current public.hotel_subscriptions%rowtype;
  v_payment public.subscription_manual_payments%rowtype;
  v_action_key text;
  v_lifecycle_key text;
  v_method text;
  v_reference text;
  v_cycle text;
  v_currency text;
  v_note text;
  v_plan_id uuid;
  v_amount bigint;
  v_paid_at timestamptz;
  v_period_start timestamptz;
  v_period_end timestamptz;
  v_subscription_id uuid;
  v_subscription_result jsonb;
  v_lifecycle_action text;
begin
  if not (
    (v_actor is not null and private.is_platform_admin())
    or v_caller_role = 'service_role'
  ) then
    raise exception 'Platform Admin or service-role access required.';
  end if;

  if p_hotel_id is null
     or p_payload is null
     or jsonb_typeof(p_payload) <> 'object'
  then
    raise exception 'Hotel and manual-payment payload are required.';
  end if;

  v_action_key := nullif(trim(p_payload ->> 'idempotency_key'), '');
  if v_action_key is null or length(v_action_key) not between 8 and 200 then
    raise exception 'A valid manual-payment idempotency key is required.';
  end if;

  select payment.*
  into v_existing
  from public.subscription_manual_payments payment
  where payment.idempotency_key = v_action_key;

  if found then
    return jsonb_build_object(
      'ok', true,
      'idempotent', true,
      'lifecycle_action', 'already_recorded',
      'payment', to_jsonb(v_existing)
    );
  end if;

  v_method := lower(nullif(trim(p_payload ->> 'payment_method'), ''));
  v_reference := nullif(trim(p_payload ->> 'payment_reference'), '');
  v_cycle := lower(coalesce(nullif(trim(p_payload ->> 'billing_cycle'), ''), 'monthly'));
  v_currency := upper(coalesce(nullif(trim(p_payload ->> 'currency_code'), ''), 'INR'));
  v_note := nullif(trim(p_payload ->> 'note'), '');
  v_plan_id := nullif(trim(p_payload ->> 'plan_id'), '')::uuid;
  v_amount := coalesce(nullif(trim(p_payload ->> 'amount_minor'), '')::bigint, 0);
  v_paid_at := coalesce(nullif(trim(p_payload ->> 'paid_at'), '')::timestamptz, now());
  v_period_start := coalesce(nullif(trim(p_payload ->> 'period_start'), '')::timestamptz, now());
  v_period_end := nullif(trim(p_payload ->> 'period_end'), '')::timestamptz;

  if v_method is null or v_method not in ('upi', 'bank_transfer', 'cash', 'other') then
    raise exception 'Payment method must be UPI, bank transfer, cash or other.';
  end if;
  if v_reference is null or length(v_reference) not between 3 and 120 then
    raise exception 'A receipt or payment reference of 3-120 characters is required.';
  end if;
  if v_cycle not in ('monthly', 'annual') then
    raise exception 'Billing cycle must be monthly or annual.';
  end if;
  if v_currency !~ '^[A-Z]{3}$' or v_amount <= 0 then
    raise exception 'A positive paid amount and valid currency are required.';
  end if;
  if v_paid_at > now() + interval '5 minutes' then
    raise exception 'Payment time cannot be in the future.';
  end if;
  if v_period_end is null or v_period_end <= v_period_start then
    raise exception 'A valid paid subscription period is required.';
  end if;
  if v_note is not null and length(v_note) > 1000 then
    raise exception 'Audit note must be 1000 characters or fewer.';
  end if;
  if p_payload ? 'metadata' and jsonb_typeof(p_payload -> 'metadata') <> 'object' then
    raise exception 'Manual-payment metadata must be a JSON object.';
  end if;

  perform h.id
  from public.hotels h
  where h.id = p_hotel_id
  for update;

  if not found then
    raise exception 'Hotel not found.';
  end if;

  perform sp.id
  from public.subscription_plans sp
  where sp.id = v_plan_id
    and sp.status = 'active'
  for share;

  if not found then
    raise exception 'Selected subscription plan is not active.';
  end if;

  perform pg_advisory_xact_lock(
    hashtext('stayqr:pilot-manual-payment:' || p_hotel_id::text)
  );
  perform pg_advisory_xact_lock(
    hashtext('stayqr:pilot-manual-reference:' || v_method || ':' || lower(v_reference))
  );

  if exists (
    select 1
    from public.subscription_manual_payments payment
    where payment.payment_method = v_method
      and lower(payment.payment_reference) = lower(v_reference)
  ) then
    raise exception 'This payment reference has already been recorded.';
  end if;

  select hs.*
  into v_current
  from public.hotel_subscriptions hs
  where hs.hotel_id = p_hotel_id
  order by
    case when hs.status in ('trial', 'trialing', 'active', 'past_due', 'suspended') then 0 else 1 end,
    coalesce(hs.updated_at, hs.created_at) desc,
    hs.id desc
  limit 1
  for update;

  v_lifecycle_key := v_action_key || ':subscription';

  if found and v_current.status in ('active', 'past_due', 'suspended') then
    if v_current.plan_id is distinct from v_plan_id then
      raise exception 'Change the hotel plan first, then record the manual renewal against that plan.';
    end if;

    v_lifecycle_action := 'renewed';
    v_subscription_result := public.renew_hotel_subscription(
      p_hotel_id,
      jsonb_build_object(
        'billing_cycle', v_cycle,
        'amount_minor', v_amount,
        'currency_code', v_currency,
        'provider', 'manual',
        'provider_status', 'active',
        'current_period_start', v_period_start,
        'current_period_end', v_period_end,
        'last_payment_at', v_paid_at,
        'idempotency_key', v_lifecycle_key,
        'provider_metadata', jsonb_build_object(
          'billing_mode', 'pilot_manual',
          'payment_method', v_method,
          'payment_reference', v_reference,
          'payment_status', 'confirmed'
        ),
        'metadata', coalesce(p_payload -> 'metadata', '{}'::jsonb)
          || jsonb_build_object('manual_payment_note', v_note)
      )
    );
  else
    v_lifecycle_action := 'activated';
    v_subscription_result := public.activate_paid_subscription(
      p_hotel_id,
      jsonb_build_object(
        'plan_id', v_plan_id,
        'billing_cycle', v_cycle,
        'amount_minor', v_amount,
        'currency_code', v_currency,
        'provider', 'manual',
        'provider_status', 'active',
        'current_period_start', v_period_start,
        'current_period_end', v_period_end,
        'last_payment_at', v_paid_at,
        'idempotency_key', v_lifecycle_key,
        'provider_metadata', jsonb_build_object(
          'billing_mode', 'pilot_manual',
          'payment_method', v_method,
          'payment_reference', v_reference,
          'payment_status', 'confirmed'
        ),
        'metadata', coalesce(p_payload -> 'metadata', '{}'::jsonb)
          || jsonb_build_object('manual_payment_note', v_note)
      )
    );
  end if;

  v_subscription_id := nullif(v_subscription_result ->> 'subscription_id', '')::uuid;
  if v_subscription_id is null then
    raise exception 'Subscription activation did not return a subscription identifier.';
  end if;

  insert into public.subscription_manual_payments (
    hotel_id,
    subscription_id,
    plan_id,
    status,
    payment_method,
    payment_reference,
    amount_minor,
    currency_code,
    billing_cycle,
    paid_at,
    period_start,
    period_end,
    note,
    recorded_by,
    idempotency_key,
    metadata
  ) values (
    p_hotel_id,
    v_subscription_id,
    v_plan_id,
    'confirmed',
    v_method,
    v_reference,
    v_amount,
    v_currency,
    v_cycle,
    v_paid_at,
    v_period_start,
    v_period_end,
    v_note,
    v_actor,
    v_action_key,
    coalesce(p_payload -> 'metadata', '{}'::jsonb)
      || jsonb_build_object('source', 'super_admin_pilot_manual_billing')
  )
  returning * into v_payment;

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
    idempotency_key,
    details
  ) values (
    p_hotel_id,
    v_subscription_id,
    'manual_payment_recorded',
    'record_manual_subscription_payment',
    v_actor,
    v_current.status,
    'active',
    v_current.plan_id,
    v_plan_id,
    'manual',
    v_action_key || ':payment-event',
    jsonb_build_object(
      'manual_payment_id', v_payment.id,
      'payment_method', v_method,
      'payment_reference', v_reference,
      'amount_minor', v_amount,
      'currency_code', v_currency,
      'billing_cycle', v_cycle,
      'paid_at', v_paid_at,
      'period_start', v_period_start,
      'period_end', v_period_end,
      'lifecycle_action', v_lifecycle_action
    )
  );

  return jsonb_build_object(
    'ok', true,
    'idempotent', false,
    'lifecycle_action', v_lifecycle_action,
    'payment', to_jsonb(v_payment),
    'subscription', v_subscription_result
  );
end;
$$;

revoke all on function public.record_manual_subscription_payment(uuid, jsonb)
  from public, anon;
grant execute on function public.record_manual_subscription_payment(uuid, jsonb)
  to authenticated, service_role;

create or replace function public.get_manual_subscription_payments(
  p_hotel_id uuid default null,
  p_row_limit integer default 100
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_caller_role text := current_setting('request.jwt.claim.role', true);
  v_limit integer := greatest(1, least(coalesce(p_row_limit, 100), 250));
begin
  if v_actor is null and v_caller_role <> 'service_role' then
    raise exception 'Authentication is required.';
  end if;

  if p_hotel_id is null then
    if not (
      (v_actor is not null and private.is_platform_admin())
      or v_caller_role = 'service_role'
    ) then
      raise exception 'Platform Admin access is required for the complete manual-payment ledger.';
    end if;
  elsif not (
    private.user_has_hotel_access(p_hotel_id)
    or private.is_platform_admin()
    or v_caller_role = 'service_role'
  ) then
    raise exception 'Manual-payment ledger access denied.';
  end if;

  return (
    select coalesce(jsonb_agg(to_jsonb(row_data) order by row_data.paid_at desc), '[]'::jsonb)
    from (
      select
        payment.id,
        payment.hotel_id,
        hotel.hotel_name,
        payment.subscription_id,
        payment.plan_id,
        plan.plan_name,
        payment.status,
        payment.payment_method,
        payment.payment_reference,
        payment.amount_minor,
        payment.currency_code,
        payment.billing_cycle,
        payment.paid_at,
        payment.period_start,
        payment.period_end,
        payment.note,
        payment.recorded_by,
        payment.created_at
      from public.subscription_manual_payments payment
      join public.hotels hotel on hotel.id = payment.hotel_id
      join public.subscription_plans plan on plan.id = payment.plan_id
      where p_hotel_id is null or payment.hotel_id = p_hotel_id
      order by payment.paid_at desc, payment.id desc
      limit v_limit
    ) row_data
  );
end;
$$;

revoke all on function public.get_manual_subscription_payments(uuid, integer)
  from public, anon;
grant execute on function public.get_manual_subscription_payments(uuid, integer)
  to authenticated, service_role;

commit;
