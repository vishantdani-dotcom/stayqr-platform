begin;

do $$
begin
  if to_regclass('public.subscription_manual_payments') is not null
     and exists (select 1 from public.subscription_manual_payments)
  then
    raise exception 'Refusing rollback because manual payment evidence exists. Preserve the ledger and use a forward corrective migration.';
  end if;
end;
$$;

drop function if exists public.get_manual_subscription_payments(uuid, integer);
drop function if exists public.record_manual_subscription_payment(uuid, jsonb);
drop table if exists public.subscription_manual_payments;

commit;
