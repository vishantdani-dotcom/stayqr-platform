-- StayQR REV10 staging acceptance: stay-owned checkout / room-move continuity.
-- Read-only. Expected: 14/14 PASS.
with checks as (
  select '01_LEGACY_CHECKOUT_EXISTS' as check_name,
    to_regprocedure('public.checkout_guest_session_day20_legacy(uuid,uuid,numeric,text,numeric,boolean,text,text,text,boolean)') is not null as ok
  union all
  select '02_EXISTING_INVOICE_CHECKOUT_EXISTS',
    to_regprocedure('private.day20_checkout_existing_invoice(uuid,uuid,numeric,text,numeric,boolean,text,text,text,boolean)') is not null
  union all
  select '03_LEGACY_SECURITY_DEFINER',
    exists (select 1 from pg_proc where oid=to_regprocedure('public.checkout_guest_session_day20_legacy(uuid,uuid,numeric,text,numeric,boolean,text,text,text,boolean)') and prosecdef)
  union all
  select '04_EXISTING_SECURITY_DEFINER',
    exists (select 1 from pg_proc where oid=to_regprocedure('private.day20_checkout_existing_invoice(uuid,uuid,numeric,text,numeric,boolean,text,text,text,boolean)') and prosecdef)
  union all
  select '05_STAY_FOLIO_IS_CHARGE_AUTHORITY',
    exists (select 1 from pg_proc where oid=to_regprocedure('public.checkout_guest_session_day20_legacy(uuid,uuid,numeric,text,numeric,boolean,text,text,text,boolean)') and position('checkout_folio.charges_amount' in prosrc)>0 and position('public.folio_items' in prosrc)>0)
  union all
  select '06_CURRENT_ROOM_FOOD_TOTAL_FILTER_REMOVED',
    exists (select 1 from pg_proc where oid=to_regprocedure('public.checkout_guest_session_day20_legacy(uuid,uuid,numeric,text,numeric,boolean,text,text,text,boolean)') and position('fo.room_id = session_row.room_id' in prosrc)=0)
  union all
  select '07_FOOD_ORDERS_ARE_STAY_AWARE',
    exists (select 1 from pg_proc where oid=to_regprocedure('public.checkout_guest_session_day20_legacy(uuid,uuid,numeric,text,numeric,boolean,text,text,text,boolean)') and position('fo.guest_session_id = target_guest_session_id' in prosrc)>0)
  union all
  select '08_INVOICE_LINES_USE_FOLIO_ITEMS',
    exists (select 1 from pg_proc where oid=to_regprocedure('public.checkout_guest_session_day20_legacy(uuid,uuid,numeric,text,numeric,boolean,text,text,text,boolean)') and position('folio_item_id' in prosrc)>0 and position('authoritative_folio' in prosrc)>0)
  union all
  select '09_MANUAL_CHARGES_USE_FOLIO_SOURCE',
    exists (select 1 from pg_proc where oid=to_regprocedure('public.checkout_guest_session_day20_legacy(uuid,uuid,numeric,text,numeric,boolean,text,text,text,boolean)') and position('manual_charges' in prosrc)>0 and position('fi.source_table = ''manual_charges''' in prosrc)>0)
  union all
  select '10_EXISTING_INVOICE_OPEN_ORDER_STAY_AWARE',
    exists (select 1 from pg_proc where oid=to_regprocedure('private.day20_checkout_existing_invoice(uuid,uuid,numeric,text,numeric,boolean,text,text,text,boolean)') and position('fo.guest_session_id = target_guest_session_id' in prosrc)>0)
  union all
  select '11_STAY_ROOM_HISTORY_PRESENT', to_regclass('public.stay_room_history') is not null
  union all
  select '12_FOLIO_ITEM_LINK_PRESENT',
    exists (select 1 from information_schema.columns where table_schema='public' and table_name='invoice_items' and column_name='folio_item_id')
  union all
  select '13_FOOD_SESSION_LINK_PRESENT',
    exists (select 1 from information_schema.columns where table_schema='public' and table_name='food_orders' and column_name='guest_session_id')
  union all
  select '14_ANON_CHECKOUT_NOT_EXECUTABLE',
    not has_function_privilege('anon', 'public.checkout_guest_session(uuid,uuid,numeric,text,numeric,boolean,text,text,text,boolean)', 'EXECUTE')
)
select check_name, case when ok then 'PASS' else 'FAIL' end as status
from checks
order by check_name;
