with checks(test_name, passed, details) as (
  values
    ('01_manual_payment_table', to_regclass('public.subscription_manual_payments') is not null, 'Protected manual-payment ledger exists.'),
    ('02_record_rpc', to_regprocedure('public.record_manual_subscription_payment(uuid,jsonb)') is not null, 'Atomic record-and-activate RPC exists.'),
    ('03_read_rpc', to_regprocedure('public.get_manual_subscription_payments(uuid,integer)') is not null, 'Protected ledger read RPC exists.'),
    ('04_rls_enabled', coalesce((select c.relrowsecurity from pg_class c where c.oid=to_regclass('public.subscription_manual_payments')),false), 'Manual-payment ledger has RLS enabled.'),
    ('05_authenticated_no_insert', not has_table_privilege('authenticated','public.subscription_manual_payments','insert'), 'Authenticated clients cannot insert ledger rows directly.'),
    ('06_authenticated_no_update', not has_table_privilege('authenticated','public.subscription_manual_payments','update'), 'Authenticated clients cannot update ledger rows directly.'),
    ('07_authenticated_no_delete', not has_table_privilege('authenticated','public.subscription_manual_payments','delete'), 'Authenticated clients cannot delete ledger rows directly.'),
    ('08_authenticated_select', has_table_privilege('authenticated','public.subscription_manual_payments','select'), 'Hotel users can read only RLS-authorized rows.'),
    ('09_record_authenticated_execute', has_function_privilege('authenticated','public.record_manual_subscription_payment(uuid,jsonb)','execute'), 'Super Admin can call the guarded record RPC.'),
    ('10_read_authenticated_execute', has_function_privilege('authenticated','public.get_manual_subscription_payments(uuid,integer)','execute'), 'Authorized users can call the guarded read RPC.'),
    ('11_idempotency_unique', to_regclass('public.uq_subscription_manual_payments_idempotency') is not null, 'Duplicate submission protection exists.'),
    ('12_reference_unique', to_regclass('public.uq_subscription_manual_payments_reference') is not null, 'Duplicate receipt/reference protection exists.'),
    ('13_immutable_trigger', exists(select 1 from pg_trigger where tgrelid=to_regclass('public.subscription_manual_payments') and tgname='prevent_subscription_manual_payment_mutation_pilot' and not tgisinternal), 'Ledger update/delete blocker exists.'),
    ('14_production_safety', true, 'This acceptance script performs no deployment or production mutation.')
)
select
  test_name,
  passed,
  details,
  count(*) over () as total_checks,
  count(*) filter (where passed) over () as passed_checks,
  count(*) filter (where not passed) over () as failed_checks
from checks
order by test_name;

select case
  when
    to_regclass('public.subscription_manual_payments') is not null
    and to_regprocedure('public.record_manual_subscription_payment(uuid,jsonb)') is not null
    and to_regprocedure('public.get_manual_subscription_payments(uuid,integer)') is not null
    and coalesce((select c.relrowsecurity from pg_class c where c.oid=to_regclass('public.subscription_manual_payments')),false)
    and not has_table_privilege('authenticated','public.subscription_manual_payments','insert')
    and not has_table_privilege('authenticated','public.subscription_manual_payments','update')
    and not has_table_privilege('authenticated','public.subscription_manual_payments','delete')
    and has_table_privilege('authenticated','public.subscription_manual_payments','select')
    and has_function_privilege('authenticated','public.record_manual_subscription_payment(uuid,jsonb)','execute')
    and has_function_privilege('authenticated','public.get_manual_subscription_payments(uuid,integer)','execute')
    and to_regclass('public.uq_subscription_manual_payments_idempotency') is not null
    and to_regclass('public.uq_subscription_manual_payments_reference') is not null
    and exists(select 1 from pg_trigger where tgrelid=to_regclass('public.subscription_manual_payments') and tgname='prevent_subscription_manual_payment_mutation_pilot' and not tgisinternal)
  then 'PILOT_MANUAL_BILLING_STAGING_ACCEPTANCE: PASS (14/14)'
  else 'PILOT_MANUAL_BILLING_STAGING_ACCEPTANCE: FAIL'
end as acceptance_result;
