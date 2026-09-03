-- STAGING ONLY: reconcile exactly one previously diagnosed test folio.
-- Preserve the immutable invoice; create no payment or collection.
begin;
set local lock_timeout = '10s';
set local statement_timeout = '30s';
select set_config('request.jwt.claim.sub', 'fe46129f-afe4-4d2d-b3fc-e8cbf95d9aae', true);
select set_config('request.jwt.claims', '{"sub":"fe46129f-afe4-4d2d-b3fc-e8cbf95d9aae","role":"authenticated"}', true);
set local role authenticated;
do $reconcile$
declare
  hotel_id_value constant uuid := 'c6f16ea5-dcb0-40c3-a483-e628a5ea177c';
  invoice_id_value constant uuid := '33a7254a-dd6a-408c-ab01-f47a8d3bf49f';
  folio_id_value constant uuid := '82c01592-4241-4abc-9ff0-70631bbd62da';
  session_id_value constant uuid := 'e50ee898-1edd-44f2-b2de-bbbc78de8a95';
  invoice_before public.invoices%rowtype;
  invoice_after public.invoices%rowtype;
  folio_row public.folios%rowtype;
  approval_result jsonb;
  request_key constant text := 'reconcile:20ET-INV-2026-27-000011:106';
begin
  select * into strict invoice_before from public.invoices
    where hotel_id = hotel_id_value and id = invoice_id_value for share;
  select * into strict folio_row from public.folios
    where hotel_id = hotel_id_value and id = folio_id_value for update;
  if invoice_before.invoice_number <> '20ET-INV/2026-27/000011'
     or invoice_before.folio_id <> folio_id_value
     or invoice_before.guest_session_id <> session_id_value
     or invoice_before.subtotal_amount <> 2500 or invoice_before.discount_amount <> 2500
     or invoice_before.total_amount <> 0 or invoice_before.paid_amount <> 0 or invoice_before.pending_amount <> 0
     or invoice_before.finalized_at is null or nullif(invoice_before.snapshot_hash, '') is null
     or folio_row.guest_session_id <> session_id_value or folio_row.status <> 'open'
     or folio_row.charges_amount <> 2500 or folio_row.discount_amount <> 0
     or folio_row.tax_amount <> 0 or folio_row.collection_amount <> 0
     or folio_row.refund_amount <> 0 or folio_row.credit_amount <> 0 or folio_row.balance_amount <> 2500
     or exists (select 1 from public.folio_adjustments where hotel_id = hotel_id_value and folio_id = folio_id_value)
     or exists (select 1 from public.payment_collections where hotel_id = hotel_id_value and guest_session_id = session_id_value)
     or exists (select 1 from public.folio_collections where hotel_id = hotel_id_value and folio_id = folio_id_value)
     or not exists (select 1 from public.reservation_checkout_events e where e.hotel_id = hotel_id_value
       and e.guest_session_id = session_id_value and e.invoice_id = invoice_id_value
       and (e.settlement_snapshot ->> 'discount_amount')::numeric = 2500
       and (e.settlement_snapshot ->> 'grand_total')::numeric = 0
       and (e.settlement_snapshot ->> 'amount_collected_at_checkout')::numeric = 0) then
    raise exception 'Labelled staging fixture no longer matches the approved diagnosis. No reconciliation applied.';
  end if;
  approval_result := public.request_folio_discount(hotel_id_value, folio_id_value, 'fixed', 2500,
    'STAGING TEST RECONCILIATION - mirror the complimentary discount already locked in 20ET-INV/2026-27/000011; no money collected.',
    request_key);
  perform public.review_folio_discount(hotel_id_value,
    (approval_result -> 'approval' ->> 'id')::uuid, true,
    'User-approved staging-only correction after read-only diagnosis on 3 September 2026.', request_key || ':approve');
  select * into strict folio_row from public.folios
    where hotel_id = hotel_id_value and id = folio_id_value;
  select * into strict invoice_after from public.invoices
    where hotel_id = hotel_id_value and id = invoice_id_value;
  if folio_row.status <> 'settled' or folio_row.discount_amount <> 2500 or folio_row.balance_amount <> 0
     or (select count(*) from public.folio_adjustments where hotel_id = hotel_id_value and folio_id = folio_id_value
       and adjustment_type = 'discount' and amount = 2500 and status = 'posted') <> 1
     or (select count(*) from public.discount_approvals where hotel_id = hotel_id_value and folio_id = folio_id_value
       and requested_amount = 2500 and status = 'approved' and reviewed_by is not null) <> 1
     or invoice_after is distinct from invoice_before
     or exists (select 1 from public.payment_collections where hotel_id = hotel_id_value and guest_session_id = session_id_value)
     or exists (select 1 from public.folio_collections where hotel_id = hotel_id_value and folio_id = folio_id_value) then
    raise exception 'Post-reconciliation invariants failed; transaction rolled back.';
  end if;
end;
$reconcile$;
commit;

begin read only;
select jsonb_build_object(
  'invoice_number', i.invoice_number, 'invoice_unchanged_total', i.total_amount,
  'invoice_unchanged_pending', i.pending_amount, 'invoice_snapshot_hash_present', nullif(i.snapshot_hash, '') is not null,
  'folio_status', f.status, 'folio_discount', f.discount_amount, 'folio_balance', f.balance_amount,
  'approved_adjustments', (select count(*) from public.folio_adjustments a where a.hotel_id = i.hotel_id and a.folio_id = f.id and a.status = 'posted'),
  'payment_collections', (select count(*) from public.payment_collections p where p.hotel_id = i.hotel_id and p.guest_session_id = i.guest_session_id),
  'folio_collections', (select count(*) from public.folio_collections c where c.hotel_id = i.hotel_id and c.folio_id = f.id)
) as reconciliation
from public.invoices i join public.folios f on f.hotel_id = i.hotel_id and f.id = i.folio_id
where i.hotel_id = 'c6f16ea5-dcb0-40c3-a483-e628a5ea177c' and i.id = '33a7254a-dd6a-408c-ab01-f47a8d3bf49f';
rollback;
