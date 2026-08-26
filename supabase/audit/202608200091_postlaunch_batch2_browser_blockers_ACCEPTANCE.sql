-- StayQR Post-Launch Batch B
-- Audit 091: browser blocker closure acceptance

with checks as (
  select 1 as n, 'zero-payment folio guard installed'::text as test,
    position('POSTLAUNCH_BATCH2_ZERO_PAYMENT_FOLIO_GUARD_REV1' in pg_get_functiondef('private.day11_sync_payment(uuid)'::regprocedure)) > 0 as passed
  union all select 2, 'zero payment cannot create fallback collection',
    position('and coalesce(payment_row.amount, 0) > 0' in pg_get_functiondef('private.day11_sync_payment(uuid)'::regprocedure)) > 0
  union all select 3, 'positive amount constraint retained',
    exists (select 1 from pg_constraint c join pg_class t on t.oid=c.conrelid join pg_namespace n on n.oid=t.relnamespace where n.nspname='public' and t.relname='folio_collections' and c.conname='folio_collections_amount_check')
  union all select 4, 'checkout RPC retained',
    to_regprocedure('public.checkout_guest_session(uuid,uuid,numeric,text,numeric,boolean,text,text,text,boolean)') is not null
  union all select 5, 'safe support start RPC retained',
    to_regprocedure('public.start_safe_support_access(uuid,text,integer,text[])') is not null
  union all select 6, 'safe support end RPC retained',
    to_regprocedure('public.end_safe_support_access(uuid,text)') is not null
)
select n, test, passed from checks order by n;

do $accept$
declare v_failed integer;
begin
  with checks as (
    select position('POSTLAUNCH_BATCH2_ZERO_PAYMENT_FOLIO_GUARD_REV1' in pg_get_functiondef('private.day11_sync_payment(uuid)'::regprocedure)) > 0 as passed
    union all select position('and coalesce(payment_row.amount, 0) > 0' in pg_get_functiondef('private.day11_sync_payment(uuid)'::regprocedure)) > 0
    union all select exists (select 1 from pg_constraint c join pg_class t on t.oid=c.conrelid join pg_namespace n on n.oid=t.relnamespace where n.nspname='public' and t.relname='folio_collections' and c.conname='folio_collections_amount_check')
    union all select to_regprocedure('public.checkout_guest_session(uuid,uuid,numeric,text,numeric,boolean,text,text,text,boolean)') is not null
    union all select to_regprocedure('public.start_safe_support_access(uuid,text,integer,text[])') is not null
    union all select to_regprocedure('public.end_safe_support_access(uuid,text)') is not null
  ) select count(*) into v_failed from checks where not passed;
  if v_failed <> 0 then
    raise exception 'POSTLAUNCH_BATCH2_BROWSER_BLOCKERS_DATABASE_ACCEPTANCE: FAIL (% failed)', v_failed;
  end if;
  raise notice 'POSTLAUNCH_BATCH2_BROWSER_BLOCKERS_DATABASE_ACCEPTANCE: PASS (6/6)';
end;
$accept$;
