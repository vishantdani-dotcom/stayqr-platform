-- StayQR v1.0 Day 20
-- Audit 082 REV1
-- Migration 072 checkout/folio runtime-compatibility acceptance
-- READ ONLY.

with fn as (
  select pg_get_functiondef(
    'public.checkout_guest_session(uuid,uuid,numeric,text,numeric,boolean,text,text,text,boolean)'::regprocedure
  ) as def
),
checks as (
  select 1 seq, 'checkout_function_present'::text check_name,
    to_regprocedure(
      'public.checkout_guest_session(uuid,uuid,numeric,text,numeric,boolean,text,text,text,boolean)'
    ) is not null as passed
  union all
  select 2, 'migration068_marker_retained',
    position('DAY19_R3_CHECKOUT_FOLIO_RECONCILIATION_REV1' in def) > 0 from fn
  union all
  select 3, 'authoritative_paid_merge_retained',
    position('previously_paid := greatest(previously_paid, folio_paid_amount)' in def) > 0 from fn
  union all
  select 4, 'migration069_corrective_marker_present',
    position('DAY19_R3_CHECKOUT_FOLIO_NO_SYNTHETIC_PAYMENT_STATUS_REV1' in def) > 0 from fn
  union all
  select 5, 'synthetic_allocation_removed',
    position('authoritative_paid_remaining' in def) = 0 from fn
  union all
  select 6, 'legacy_payment_status_remains_collection_backed',
    position('Keep legacy payment status tied only to actual payment_collections.' in def) > 0 from fn
)
select
  seq,
  check_name,
  case when passed then 'PASS' else 'FAIL' end as result
from checks
order by seq;
