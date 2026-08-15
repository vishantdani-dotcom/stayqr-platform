-- StayQR Day 20E Commercial Pricing Catalogue — Acceptance REV2
-- READ ONLY

-- RESULT 1: Standard plan contract + attached subscriptions.
with expected(
  plan_code,
  plan_name,
  price_monthly,
  price_annual,
  max_rooms
) as (
  values
    ('STARTER'::text, 'Starter'::text, 999::numeric, 9999::numeric, 20::integer),
    ('GROWTH'::text,  'Growth'::text, 2499::numeric, 24999::numeric, 50::integer),
    ('SCALE'::text,   'Scale'::text, 4999::numeric, 49999::numeric, 100::integer)
)
select
  e.plan_code,
  sp.id,
  sp.plan_name,
  sp.price_monthly,
  sp.price_annual,
  sp.max_rooms,
  sp.max_properties,
  sp.trial_days,
  sp.currency_code,
  sp.is_public,
  sp.status,
  count(hs.id) as hotel_subscription_count,
  (
    sp.id is not null
    and sp.plan_name = e.plan_name
    and sp.price_monthly = e.price_monthly
    and sp.price_annual = e.price_annual
    and sp.max_rooms = e.max_rooms
    and sp.max_properties = 1
    and sp.trial_days = 14
    and sp.currency_code = 'INR'
    and sp.is_public = true
    and sp.status = 'active'
  ) as plan_pass
from expected e
left join public.subscription_plans sp
  on upper(trim(sp.plan_code)) = e.plan_code
left join public.hotel_subscriptions hs
  on hs.plan_id = sp.id
group by
  e.plan_code, e.plan_name, e.price_monthly, e.price_annual, e.max_rooms,
  sp.id, sp.plan_name, sp.price_monthly, sp.price_annual,
  sp.max_rooms, sp.max_properties, sp.trial_days, sp.currency_code,
  sp.is_public, sp.status
order by
  case e.plan_code when 'STARTER' then 1 when 'GROWTH' then 2 else 3 end;

-- EXPECTED: exactly 3 rows; plan_pass = true for all.

-- RESULT 2: Legacy Premium commercial plan removed.
select
  count(*) filter (where upper(trim(plan_code)) = 'PREMIUM') as premium_plan_rows,
  count(*) filter (where upper(trim(plan_code)) = 'SCALE') as scale_plan_rows
from public.subscription_plans;

-- EXPECTED: premium_plan_rows = 0; scale_plan_rows = 1.

-- RESULT 3: Authoritative current manual prices.
select
  upper(trim(sp.plan_code)) as plan_code,
  spp.billing_cycle,
  spp.amount_minor,
  spp.currency_code,
  spp.provider,
  spp.status,
  spp.metadata
from public.subscription_plans sp
join public.subscription_plan_prices spp
  on spp.plan_id = sp.id
where upper(trim(sp.plan_code)) in ('STARTER','GROWTH','SCALE')
  and spp.provider = 'manual'
  and spp.billing_cycle in ('monthly','annual')
  and spp.currency_code = 'INR'
  and spp.status = 'active'
order by
  case upper(trim(sp.plan_code))
    when 'STARTER' then 1
    when 'GROWTH' then 2
    else 3
  end,
  case spp.billing_cycle when 'monthly' then 1 else 2 end;

-- EXPECTED:
-- STARTER monthly  99900
-- STARTER annual   999900
-- GROWTH  monthly  249900
-- GROWTH  annual   2499900
-- SCALE   monthly  499900
-- SCALE   annual   4999900

-- RESULT 4: Existing subscription referential integrity.
select
  count(*) as orphan_hotel_subscriptions
from public.hotel_subscriptions hs
left join public.subscription_plans sp
  on sp.id = hs.plan_id
where sp.id is null;

-- EXPECTED: 0.

-- RESULT 5: Informational only — unrelated/custom/test plans remain untouched.
select
  id,
  plan_name,
  plan_code,
  price_monthly,
  price_annual,
  max_rooms,
  status,
  is_public
from public.subscription_plans
where upper(trim(plan_code)) not in ('STARTER','GROWTH','SCALE')
order by created_at, plan_name;

-- EXPECTED: zero or more rows are acceptable.
