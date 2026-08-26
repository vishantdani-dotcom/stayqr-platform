-- StayQR post-launch Batch 1 database acceptance.
-- Run after 202608180083_postlaunch_batch1_acquisition_search.sql.
-- Exact terminal gate: 16 rows, every passed value = true, then
-- NOTICE: POSTLAUNCH_BATCH1_DATABASE_ACCEPTANCE: PASS (16/16)

begin;

create temporary table postlaunch_batch1_acceptance (
  gate_no integer primary key,
  gate_name text not null,
  passed boolean not null,
  evidence text not null
) on commit drop;

insert into postlaunch_batch1_acceptance values
  (1, 'acquisition ledger exists',
    to_regclass('public.self_service_acquisition_intents') is not null,
    coalesce(to_regclass('public.self_service_acquisition_intents')::text, 'missing')),
  (2, 'acquisition ledger has RLS',
    coalesce((select c.relrowsecurity from pg_catalog.pg_class c where c.oid = to_regclass('public.self_service_acquisition_intents')), false),
    coalesce((select c.relrowsecurity::text from pg_catalog.pg_class c where c.oid = to_regclass('public.self_service_acquisition_intents')), 'missing')),
  (3, 'authenticated ledger is read-only',
    has_table_privilege('authenticated', 'public.self_service_acquisition_intents', 'SELECT')
      and not has_table_privilege('authenticated', 'public.self_service_acquisition_intents', 'INSERT')
      and not has_table_privilege('authenticated', 'public.self_service_acquisition_intents', 'UPDATE')
      and not has_table_privilege('authenticated', 'public.self_service_acquisition_intents', 'DELETE'),
    'SELECT only'),
  (4, 'public plan catalogue is public',
    has_function_privilege('anon', 'public.get_public_subscription_plans()', 'EXECUTE')
      and has_function_privilege('authenticated', 'public.get_public_subscription_plans()', 'EXECUTE'),
    'anon + authenticated execute'),
  (5, 'intent recovery requires authentication',
    not has_function_privilege('anon', 'public.get_my_acquisition_intent(uuid)', 'EXECUTE')
      and has_function_privilege('authenticated', 'public.get_my_acquisition_intent(uuid)', 'EXECUTE'),
    'authenticated only'),
  (6, 'trial start requires authentication',
    not has_function_privilege('anon', 'public.start_self_service_trial(jsonb)', 'EXECUTE')
      and has_function_privilege('authenticated', 'public.start_self_service_trial(jsonb)', 'EXECUTE'),
    'authenticated only'),
  (7, 'paid finalizer is service-role only',
    not has_function_privilege('anon', 'public.finalize_self_service_acquisition(uuid,jsonb)', 'EXECUTE')
      and not has_function_privilege('authenticated', 'public.finalize_self_service_acquisition(uuid,jsonb)', 'EXECUTE')
      and has_function_privilege('service_role', 'public.finalize_self_service_acquisition(uuid,jsonb)', 'EXECUTE'),
    'service_role only'),
  (8, 'hotel search requires authentication',
    not has_function_privilege('anon', 'public.search_hotel_workspace(uuid,text,integer)', 'EXECUTE')
      and has_function_privilege('authenticated', 'public.search_hotel_workspace(uuid,text,integer)', 'EXECUTE'),
    'authenticated only'),
  (9, 'three public production plans exist',
    (select count(*) = 3 from public.subscription_plans where status = 'active' and is_public = true),
    (select count(*)::text from public.subscription_plans where status = 'active' and is_public = true)),
  (10, 'Starter prices match published catalogue',
    exists (select 1 from public.subscription_plans where plan_code = 'STARTER' and price_monthly = 999 and price_annual = 9999 and status = 'active' and is_public = true),
    'INR 999 monthly / 9999 annual'),
  (11, 'Growth prices match published catalogue',
    exists (select 1 from public.subscription_plans where plan_code = 'GROWTH' and price_monthly = 2499 and price_annual = 24999 and status = 'active' and is_public = true),
    'INR 2499 monthly / 24999 annual'),
  (12, 'Scale prices match published catalogue',
    exists (select 1 from public.subscription_plans where plan_code = 'SCALE' and price_monthly = 4999 and price_annual = 49999 and status = 'active' and is_public = true),
    'INR 4999 monthly / 49999 annual'),
  (13, 'public plans provide a 14-day trial',
    not exists (select 1 from public.subscription_plans where status = 'active' and is_public = true and trial_days <> 14),
    'all public plan trial_days = 14'),
  (14, 'acquisition provider identity is unique',
    to_regclass('public.uq_self_service_acquisition_provider_link') is not null
      and to_regclass('public.uq_self_service_acquisition_reference') is not null,
    'provider link + reference unique indexes'),
  (15, 'owner-scoped acquisition policy exists',
    exists (
      select 1
      from pg_catalog.pg_policies p
      where p.schemaname = 'public'
        and p.tablename = 'self_service_acquisition_intents'
        and p.policyname = 'stayqr_self_service_acquisition_select'
        and 'authenticated' = any(p.roles)
    ),
    'stayqr_self_service_acquisition_select'),
  (16, 'KYC metadata deletion is server-owned',
    not has_function_privilege('anon', 'public.soft_delete_guest_document(uuid,uuid)', 'EXECUTE')
      and has_function_privilege('authenticated', 'public.soft_delete_guest_document(uuid,uuid)', 'EXECUTE'),
    'authenticated permission-checked RPC');

select gate_no, gate_name, passed, evidence
from postlaunch_batch1_acceptance
order by gate_no;

do $$
declare
  passed_count integer;
begin
  select count(*) filter (where passed) into passed_count
  from postlaunch_batch1_acceptance;

  if passed_count <> 16 then
    raise exception 'POSTLAUNCH_BATCH1_DATABASE_ACCEPTANCE: FAIL (%/16)', passed_count;
  end if;

  raise notice 'POSTLAUNCH_BATCH1_DATABASE_ACCEPTANCE: PASS (16/16)';
end;
$$;

rollback;
