-- Forward-only checkout/folio consistency. Apply to staging first.
-- No historical invoice, payment or folio rows are updated by this migration.
begin;
set local lock_timeout = '10s';
set local statement_timeout = '180s';
select pg_advisory_xact_lock(hashtext('stayqr:202609030106:checkout-folio'));

create or replace function private.pilot_prepare_checkout_folio(
  target_hotel_id uuid, target_guest_session_id uuid,
  expected_subtotal numeric, expected_tax numeric, expected_discount numeric,
  expected_paid numeric, reason_value text
) returns public.folios
language plpgsql security definer set search_path = ''
as $function$
declare
  folio_row public.folios%rowtype;
  actor_id_value uuid;
  delta_value numeric(14,2);
  approval_result jsonb;
  request_key text := 'checkout-discount:' || target_guest_session_id::text;
begin
  -- Private helper, not a second public checkout/discount API.
  perform private.assert_reservation_write_access(target_hotel_id);
  actor_id_value := private.day11_require_current_actor();
  if expected_subtotal is null or expected_tax is null or expected_discount is null
     or expected_paid is null or least(expected_subtotal, expected_tax, expected_discount, expected_paid) < 0
     or expected_discount > expected_subtotal + expected_tax then
    raise exception 'Invalid checkout folio totals.';
  end if;
  if not exists (select 1 from public.guest_sessions
    where hotel_id = target_hotel_id and id = target_guest_session_id and status = 'active') then
    raise exception 'Checkout requires an active same-hotel stay.';
  end if;
  folio_row := private.day11_ensure_folio_for_source(
    target_hotel_id, target_guest_session_id, 'pilot_checkout_folio_consistency');
  select * into strict folio_row from public.folios
    where hotel_id = target_hotel_id and id = folio_row.id for update;

  -- Preserve existing ledger evidence; never overwrite charges or adjustments.
  if folio_row.status = 'voided' or folio_row.charges_amount <> expected_subtotal
     or folio_row.collection_amount <> expected_paid
     or folio_row.refund_amount <> 0 or folio_row.credit_amount <> 0 then
    raise exception 'Checkout and folio charges/collections differ. Review Folio & Settlement before checkout.';
  end if;
  if folio_row.tax_amount > expected_tax or folio_row.discount_amount > expected_discount then
    raise exception 'Checkout tax/discount is below amounts already posted. Enter matching totals or review Folio & Settlement.';
  end if;

  -- Checkout tax must be in the same ledger before collections are mirrored.
  delta_value := expected_tax - folio_row.tax_amount;
  if delta_value > 0 then
    insert into public.folio_items (
      hotel_id, folio_id, item_kind, description, quantity, unit_amount, amount,
      source_table, source_id, posted_by, metadata
    ) values (
      target_hotel_id, folio_row.id, 'tax', 'Checkout tax', 1, delta_value, delta_value,
      'checkout_tax', target_guest_session_id, actor_id_value,
      jsonb_build_object('source', 'checkout_guest_session', 'expected_tax', expected_tax, 'migration', '106')
    );
    perform private.write_folio_event(target_hotel_id, folio_row.id, 'folio.checkout_tax.posted',
      'guest_session', target_guest_session_id,
      jsonb_build_object('amount', delta_value, 'expected_tax', expected_tax),
      jsonb_build_object('migration', '106'));
  end if;

  -- A checkout discount is the desired TOTAL, not an additional discount.
  -- Existing RPCs enforce permissions, actor identity, approval and limits.
  delta_value := expected_discount - folio_row.discount_amount;
  if delta_value > 0 then
    if nullif(trim(reason_value), '') is null then
      raise exception 'A reason in invoice notes is required for the checkout discount.';
    end if;
    approval_result := public.request_folio_discount(target_hotel_id, folio_row.id,
      'fixed', delta_value, reason_value, request_key);
    perform public.review_folio_discount(target_hotel_id,
      (approval_result -> 'approval' ->> 'id')::uuid, true,
      'Discount confirmed by the checkout actor; requested total ' || expected_discount::text,
      request_key || ':approve');
  end if;

  select * into strict folio_row from public.folios
    where hotel_id = target_hotel_id and id = folio_row.id;
  if folio_row.tax_amount <> expected_tax or folio_row.discount_amount <> expected_discount
     or folio_row.balance_amount <> expected_subtotal + expected_tax - expected_discount - expected_paid then
    raise exception 'Checkout folio reconciliation failed. No checkout changes were saved.';
  end if;
  return folio_row;
end;
$function$;
revoke all on function private.pilot_prepare_checkout_folio(uuid,uuid,numeric,numeric,numeric,numeric,text)
  from public, anon, authenticated;

do $migration$
declare
  target_oid oid := to_regprocedure('public.checkout_guest_session(uuid,uuid,numeric,text,numeric,boolean,text,text,text,boolean)');
  original_definition text;
  patched_definition text;
  original_acl aclitem[];
  original_owner oid;
  original_config text[];
  declaration_anchor constant text := '  session_row public.guest_sessions%rowtype;';
  prepare_anchor constant text := '  created_invoice_number := format(';
  finish_anchor constant text := '  update public.guest_sessions';
  prepare_block constant text := $block$
  -- PILOT_CHECKOUT_FOLIO_CONSISTENCY_REV1
  checkout_folio := private.pilot_prepare_checkout_folio(
    target_hotel_id, target_guest_session_id, subtotal, tax_amount,
    discount_amount, previously_paid, invoice_notes);

$block$;
  finish_block constant text := $block$
  -- The invoice claims no pending amount: prove the live ledger agrees.
  select * into strict checkout_folio from public.folios
    where hotel_id = target_hotel_id and guest_session_id = target_guest_session_id
    for update;
  if checkout_folio.balance_amount <> 0
     or checkout_folio.charges_amount <> subtotal
     or checkout_folio.tax_amount <> tax_amount
     or checkout_folio.discount_amount <> discount_amount
     or checkout_folio.collection_amount <> grand_total
     or not exists (select 1 from public.invoices i
       where i.hotel_id = target_hotel_id and i.id = created_invoice_id
         and i.folio_id = checkout_folio.id and i.pending_amount = 0
         and i.total_amount = grand_total) then
    raise exception 'Final checkout and folio do not reconcile. No checkout changes were saved.';
  end if;

$block$;
  anchor_value text;
begin
  if target_oid is null then raise exception 'Required checkout function is missing.'; end if;
  select pg_get_functiondef(p.oid), p.proacl, p.proowner, p.proconfig
    into original_definition, original_acl, original_owner, original_config
    from pg_proc p where p.oid = target_oid and p.prosecdef;
  if original_definition is null then raise exception 'Checkout security-definer contract is missing.'; end if;
  if position('PILOT_CHECKOUT_FOLIO_CONSISTENCY_REV1' in original_definition) > 0 then
    raise notice 'Checkout folio correction is already applied.';
    return;
  end if;
  if position('DAY19_R3_CHECKOUT_FOLIO_NO_SYNTHETIC_PAYMENT_STATUS_REV1' in original_definition) = 0
     or position('returning id, invoice_number into created_invoice_id, created_invoice_number' in original_definition) = 0 then
    raise exception 'Required checkout predecessor corrections are missing.';
  end if;
  foreach anchor_value in array array[declaration_anchor, prepare_anchor, finish_anchor] loop
    if (length(original_definition) - length(replace(original_definition, anchor_value, ''))) / length(anchor_value) <> 1 then
      raise exception 'Unknown checkout shape: expected one anchor %. No changes applied.', anchor_value;
    end if;
  end loop;
  patched_definition := replace(original_definition, declaration_anchor,
    declaration_anchor || E'\n  checkout_folio public.folios%rowtype;');
  patched_definition := replace(patched_definition, prepare_anchor, prepare_block || prepare_anchor);
  patched_definition := replace(patched_definition, finish_anchor, finish_block || finish_anchor);
  execute patched_definition;
  if exists (select 1 from pg_proc p where p.oid = target_oid
    and (p.proacl is distinct from original_acl or p.proowner <> original_owner
      or p.proconfig is distinct from original_config or not p.prosecdef)) then
    raise exception 'Checkout security contract changed; rolling back.';
  end if;
end;
$migration$;
commit;
