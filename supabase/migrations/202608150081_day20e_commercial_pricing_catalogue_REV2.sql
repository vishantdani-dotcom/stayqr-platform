-- StayQR v1.0 — Day 20E Commercial Pricing Catalogue REV2
-- Date: 2026-08-15
--
-- APPROVED PUBLIC CATALOGUE
-- Starter: INR 999/month, INR 9,999/year, max 20 rooms
-- Growth : INR 2,499/month, INR 24,999/year, max 50 rooms
-- Scale  : INR 4,999/month, INR 49,999/year, max 100 rooms
-- Enterprise: custom/off-catalogue; no public checkout row created here.
--
-- REV2 PURPOSE
-- - Works when standard plan rows already exist (Production).
-- - Works when some/all standard plan rows are absent (Staging).
-- - Preserves IDs for existing plans and therefore existing subscriptions.
-- - Treats PREMIUM as the legacy commercial identity of SCALE.
-- - Leaves unrelated/test/custom plans untouched.
-- - Does NOT rename Premium Guest Guide / Premium Dining feature terminology.
-- - Does NOT rewrite historical Cashfree provider price rows.
--
-- SAFE TO RERUN:
-- The standard plan rows and manual monthly/annual price rows converge
-- idempotently to the approved catalogue.

begin;

do $$
declare
  v_starter_id uuid;
  v_growth_id uuid;
  v_scale_id uuid;
  v_count integer;
begin
  ---------------------------------------------------------------------------
  -- 1. STARTER: resolve by code OR name; create only if absent.
  ---------------------------------------------------------------------------
  select count(*)
    into v_count
  from public.subscription_plans
  where upper(trim(plan_code)) = 'STARTER'
     or lower(trim(plan_name)) = 'starter';

  if v_count > 1 then
    raise exception
      'Day20E REV2 preflight failed: multiple Starter candidates exist.';
  end if;

  select id
    into v_starter_id
  from public.subscription_plans
  where upper(trim(plan_code)) = 'STARTER'
     or lower(trim(plan_name)) = 'starter'
  limit 1;

  if v_starter_id is null then
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
      'Starter',
      'STARTER',
      999,
      9999,
      20,
      null,
      1,
      null,
      14,
      'INR',
      '["QR Guest Guide","Rooms","Guests","Service Requests","Basic Reports"]'::jsonb,
      true,
      'active',
      now(),
      now()
    )
    returning id into v_starter_id;
  else
    update public.subscription_plans
    set
      plan_name = 'Starter',
      plan_code = 'STARTER',
      price_monthly = 999,
      price_annual = 9999,
      max_rooms = 20,
      max_properties = 1,
      trial_days = 14,
      currency_code = 'INR',
      features = '["QR Guest Guide","Rooms","Guests","Service Requests","Basic Reports"]'::jsonb,
      is_public = true,
      status = 'active',
      updated_at = now()
    where id = v_starter_id;
  end if;

  ---------------------------------------------------------------------------
  -- 2. GROWTH: resolve by code OR name; create only if absent.
  ---------------------------------------------------------------------------
  select count(*)
    into v_count
  from public.subscription_plans
  where upper(trim(plan_code)) = 'GROWTH'
     or lower(trim(plan_name)) = 'growth';

  if v_count > 1 then
    raise exception
      'Day20E REV2 preflight failed: multiple Growth candidates exist.';
  end if;

  select id
    into v_growth_id
  from public.subscription_plans
  where upper(trim(plan_code)) = 'GROWTH'
     or lower(trim(plan_name)) = 'growth'
  limit 1;

  if v_growth_id is null then
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
      'Growth',
      'GROWTH',
      2499,
      24999,
      50,
      null,
      1,
      null,
      14,
      'INR',
      '["Everything in Starter","Food Orders","Invoices","Housekeeping","Advanced Reports"]'::jsonb,
      true,
      'active',
      now(),
      now()
    )
    returning id into v_growth_id;
  else
    update public.subscription_plans
    set
      plan_name = 'Growth',
      plan_code = 'GROWTH',
      price_monthly = 2499,
      price_annual = 24999,
      max_rooms = 50,
      max_properties = 1,
      trial_days = 14,
      currency_code = 'INR',
      features = '["Everything in Starter","Food Orders","Invoices","Housekeeping","Advanced Reports"]'::jsonb,
      is_public = true,
      status = 'active',
      updated_at = now()
    where id = v_growth_id;
  end if;

  ---------------------------------------------------------------------------
  -- 3. SCALE: resolve legacy PREMIUM or new SCALE by code/name.
  ---------------------------------------------------------------------------
  select count(*)
    into v_count
  from public.subscription_plans
  where upper(trim(plan_code)) in ('PREMIUM','SCALE')
     or lower(trim(plan_name)) in ('premium','scale');

  if v_count > 1 then
    raise exception
      'Day20E REV2 preflight failed: multiple Premium/Scale candidates exist.';
  end if;

  select id
    into v_scale_id
  from public.subscription_plans
  where upper(trim(plan_code)) in ('PREMIUM','SCALE')
     or lower(trim(plan_name)) in ('premium','scale')
  limit 1;

  if v_scale_id is null then
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
      'Scale',
      'SCALE',
      4999,
      49999,
      100,
      null,
      1,
      null,
      14,
      'INR',
      '["Everything in Growth","Multi Staff","OCR","Translation","Priority Support"]'::jsonb,
      true,
      'active',
      now(),
      now()
    )
    returning id into v_scale_id;
  else
    update public.subscription_plans
    set
      plan_name = 'Scale',
      plan_code = 'SCALE',
      price_monthly = 4999,
      price_annual = 49999,
      max_rooms = 100,
      max_properties = 1,
      trial_days = 14,
      currency_code = 'INR',
      features = '["Everything in Growth","Multi Staff","OCR","Translation","Priority Support"]'::jsonb,
      is_public = true,
      status = 'active',
      updated_at = now()
    where id = v_scale_id;
  end if;

  ---------------------------------------------------------------------------
  -- 4. AUTHORITATIVE MANUAL PRICE MAPS.
  -- Uses the existing unique contract:
  -- (plan_id, provider, billing_cycle, currency_code)
  ---------------------------------------------------------------------------

  insert into public.subscription_plan_prices (
    plan_id,
    provider,
    billing_cycle,
    currency_code,
    amount_minor,
    provider_plan_id,
    status,
    metadata,
    created_at,
    updated_at
  )
  values
    (
      v_starter_id, 'manual', 'monthly', 'INR', 99900, null, 'active',
      jsonb_build_object(
        'source','day20e_pricing_rev2',
        'effective_date','2026-08-15',
        'catalogue_role','current'
      ),
      now(), now()
    ),
    (
      v_starter_id, 'manual', 'annual', 'INR', 999900, null, 'active',
      jsonb_build_object(
        'source','day20e_pricing_rev2',
        'effective_date','2026-08-15',
        'catalogue_role','current'
      ),
      now(), now()
    ),
    (
      v_growth_id, 'manual', 'monthly', 'INR', 249900, null, 'active',
      jsonb_build_object(
        'source','day20e_pricing_rev2',
        'effective_date','2026-08-15',
        'catalogue_role','current'
      ),
      now(), now()
    ),
    (
      v_growth_id, 'manual', 'annual', 'INR', 2499900, null, 'active',
      jsonb_build_object(
        'source','day20e_pricing_rev2',
        'effective_date','2026-08-15',
        'catalogue_role','current'
      ),
      now(), now()
    ),
    (
      v_scale_id, 'manual', 'monthly', 'INR', 499900, null, 'active',
      jsonb_build_object(
        'source','day20e_pricing_rev2',
        'effective_date','2026-08-15',
        'catalogue_role','current'
      ),
      now(), now()
    ),
    (
      v_scale_id, 'manual', 'annual', 'INR', 4999900, null, 'active',
      jsonb_build_object(
        'source','day20e_pricing_rev2',
        'effective_date','2026-08-15',
        'catalogue_role','current'
      ),
      now(), now()
    )
  on conflict (
    plan_id,
    provider,
    billing_cycle,
    currency_code
  )
  do update
  set
    amount_minor = excluded.amount_minor,
    status = 'active',
    metadata =
      public.subscription_plan_prices.metadata
      || excluded.metadata,
    updated_at = now();

  ---------------------------------------------------------------------------
  -- 5. FINAL IN-TRANSACTION ASSERTIONS.
  ---------------------------------------------------------------------------

  if (
    select count(*)
    from public.subscription_plans
    where upper(trim(plan_code)) in ('STARTER','GROWTH','SCALE')
  ) <> 3 then
    raise exception
      'Day20E REV2 verification failed: expected exactly three standard catalogue rows.';
  end if;

  if exists (
    select 1
    from public.subscription_plans
    where upper(trim(plan_code)) = 'PREMIUM'
  ) then
    raise exception
      'Day20E REV2 verification failed: legacy PREMIUM commercial plan still exists.';
  end if;

  if not exists (
    select 1
    from public.subscription_plans
    where id = v_starter_id
      and plan_name = 'Starter'
      and plan_code = 'STARTER'
      and price_monthly = 999
      and price_annual = 9999
      and max_rooms = 20
      and max_properties = 1
      and trial_days = 14
      and currency_code = 'INR'
      and is_public = true
      and status = 'active'
  ) then
    raise exception 'Day20E REV2 verification failed for Starter.';
  end if;

  if not exists (
    select 1
    from public.subscription_plans
    where id = v_growth_id
      and plan_name = 'Growth'
      and plan_code = 'GROWTH'
      and price_monthly = 2499
      and price_annual = 24999
      and max_rooms = 50
      and max_properties = 1
      and trial_days = 14
      and currency_code = 'INR'
      and is_public = true
      and status = 'active'
  ) then
    raise exception 'Day20E REV2 verification failed for Growth.';
  end if;

  if not exists (
    select 1
    from public.subscription_plans
    where id = v_scale_id
      and plan_name = 'Scale'
      and plan_code = 'SCALE'
      and price_monthly = 4999
      and price_annual = 49999
      and max_rooms = 100
      and max_properties = 1
      and trial_days = 14
      and currency_code = 'INR'
      and is_public = true
      and status = 'active'
  ) then
    raise exception 'Day20E REV2 verification failed for Scale.';
  end if;

  if (
    select count(*)
    from public.subscription_plan_prices spp
    where spp.plan_id in (v_starter_id, v_growth_id, v_scale_id)
      and spp.provider = 'manual'
      and spp.billing_cycle in ('monthly','annual')
      and spp.currency_code = 'INR'
      and spp.status = 'active'
  ) <> 6 then
    raise exception
      'Day20E REV2 verification failed: expected six active manual monthly/annual price contracts.';
  end if;
end
$$;

commit;
