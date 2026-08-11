-- ============================================================================
-- StayQR v1.0 — Day 19 R3 repair
-- Migration 068: Checkout must honor authoritative Folio & Settlement collections.
--
-- Defect:
--   Folio & Settlement can post directly to public.folio_collections / folios.
--   checkout_guest_session historically calculated "previously paid" only from
--   legacy payments/payment_collections. A fully settled folio could therefore
--   appear unpaid at checkout and trigger an attempted duplicate collection.
--
-- Repair:
--   * Preserve all legacy payment/payment_collection compatibility.
--   * Also read the authoritative folio.collection_amount for this guest session.
--   * Use the greater proven paid amount.
--   * Allocate authoritative prior payment across legacy payment demand rows only
--     for status reconciliation; DO NOT create duplicate money-movement rows.
--   * Existing DB over-collection guards remain intact.
-- ============================================================================

begin;

set local lock_timeout = '10s';
set local statement_timeout = '180s';

select pg_advisory_xact_lock(
  hashtext('stayqr:202608110068:checkout-folio-collection-reconciliation')
);

do $repair$
declare
  v_oid oid;
  v_def text;
  v_decl_anchor text := '  amount_remaining numeric(12,2) := 0;';
  v_paid_anchor text := '  ) paid_rows;';
  v_loop_anchor text := '    payment_balance := greatest(round(payment_row.amount - payment_collected, 2), 0);';
  v_pos integer;
begin
  select p.oid
  into v_oid
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'checkout_guest_session'
    and pg_get_function_identity_arguments(p.oid) =
      'target_hotel_id uuid, target_guest_session_id uuid, tax_percent numeric, discount_type text, discount_value numeric, remaining_payment_collected boolean, settlement_payment_method text, settlement_transaction_reference text, invoice_notes text, allow_excess_paid boolean'
  limit 1;

  if v_oid is null then
    raise exception 'Migration 068 stopped: canonical checkout_guest_session signature was not found.';
  end if;

  v_def := pg_get_functiondef(v_oid);

  -- Idempotent rerun.
  if position('DAY19_R3_CHECKOUT_FOLIO_RECONCILIATION_REV1' in v_def) > 0 then
    return;
  end if;

  if position(v_decl_anchor in v_def) = 0 then
    raise exception 'Migration 068 stopped: checkout declaration anchor not found.';
  end if;

  v_def := replace(
    v_def,
    v_decl_anchor,
    v_decl_anchor || E'\n' ||
    '  folio_paid_amount numeric(12,2) := 0;' || E'\n' ||
    '  authoritative_paid_remaining numeric(12,2) := 0;'
  );

  v_pos := position(v_paid_anchor in v_def);
  if v_pos = 0 then
    raise exception 'Migration 068 stopped: previous-payment calculation anchor not found.';
  end if;

  v_def :=
    substring(v_def from 1 for v_pos + length(v_paid_anchor) - 1)
    || E'\n\n'
    || '  -- DAY19_R3_CHECKOUT_FOLIO_RECONCILIATION_REV1' || E'\n'
    || '  -- Folio & Settlement is authoritative for direct/split collections.' || E'\n'
    || '  select coalesce(f.collection_amount, 0)::numeric(12,2)' || E'\n'
    || '  into folio_paid_amount' || E'\n'
    || '  from public.folios f' || E'\n'
    || '  where f.hotel_id = target_hotel_id' || E'\n'
    || '    and f.guest_session_id = target_guest_session_id' || E'\n'
    || '  order by f.created_at desc, f.id desc' || E'\n'
    || '  limit 1;' || E'\n\n'
    || '  folio_paid_amount := coalesce(folio_paid_amount, 0);' || E'\n'
    || '  previously_paid := greatest(previously_paid, folio_paid_amount);' || E'\n'
    || '  authoritative_paid_remaining := previously_paid;'
    || substring(v_def from v_pos + length(v_paid_anchor));

  if position(v_loop_anchor in v_def) = 0 then
    raise exception 'Migration 068 stopped: payment reconciliation loop anchor not found.';
  end if;

  v_def := replace(
    v_def,
    v_loop_anchor,
    '    -- Reconcile legacy payment-demand status against money already proven by the folio.' || E'\n'
    || '    authoritative_paid_remaining := greatest(' || E'\n'
    || '      round(authoritative_paid_remaining - payment_collected, 2),' || E'\n'
    || '      0' || E'\n'
    || '    );' || E'\n'
    || '    payment_balance := greatest(round(payment_row.amount - payment_collected, 2), 0);' || E'\n'
    || '    if authoritative_paid_remaining > 0 and payment_balance > 0 then' || E'\n'
    || '      collection_amount := least(payment_balance, authoritative_paid_remaining);' || E'\n'
    || '      payment_collected := round(payment_collected + collection_amount, 2);' || E'\n'
    || '      authoritative_paid_remaining := greatest(' || E'\n'
    || '        round(authoritative_paid_remaining - collection_amount, 2),' || E'\n'
    || '        0' || E'\n'
    || '      );' || E'\n'
    || '    end if;' || E'\n'
    || '    payment_balance := greatest(round(payment_row.amount - payment_collected, 2), 0);'
  );

  execute v_def;
end;
$repair$;

comment on function public.checkout_guest_session(
  uuid, uuid, numeric, text, numeric, boolean, text, text, text, boolean
) is
'StayQR checkout. Day19 Migration068: honors authoritative folio collections while preserving legacy payment compatibility.';

do $verify$
declare
  v_def text;
begin
  select pg_get_functiondef(
    'public.checkout_guest_session(uuid,uuid,numeric,text,numeric,boolean,text,text,text,boolean)'::regprocedure
  )
  into v_def;

  if v_def not like '%DAY19_R3_CHECKOUT_FOLIO_RECONCILIATION_REV1%' then
    raise exception 'Migration 068 verification failed: repair marker missing.';
  end if;

  if v_def not like '%from public.folios f%' then
    raise exception 'Migration 068 verification failed: authoritative folio read missing.';
  end if;

  if v_def not like '%previously_paid := greatest(previously_paid, folio_paid_amount)%' then
    raise exception 'Migration 068 verification failed: paid reconciliation missing.';
  end if;

  if v_def not like '%authoritative_paid_remaining%' then
    raise exception 'Migration 068 verification failed: payment-demand status reconciliation missing.';
  end if;
end;
$verify$;

commit;
