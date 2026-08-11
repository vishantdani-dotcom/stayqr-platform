-- ============================================================================
-- StayQR v1.0 — Day 19 R3 corrective repair
-- Migration 069: Do not synthesize legacy payment "paid" state from folio money.
--
-- Context:
--   Migration 068 correctly taught checkout_guest_session to treat the folio's
--   collection_amount as authoritative "previously paid" money.
--
--   However, its compatibility block also temporarily added that authoritative
--   money to payment_collected inside the legacy payments loop. That could make
--   an old payment demand become payment_status='paid'. The existing Day 11
--   payment sync then legitimately attempted to create a fallback folio
--   collection for that newly-paid legacy payment, which the folio overpayment
--   guard correctly rejected because the folio balance was already zero.
--
-- Correct behavior:
--   * Folio money affects checkout previously_paid / amount_to_collect.
--   * Legacy payment_collected remains based ONLY on real payment_collections.
--   * No duplicate/fallback money movement is manufactured from folio money.
--   * Existing Day 11 collection guards remain unchanged.
-- ============================================================================

begin;

set local lock_timeout = '10s';
set local statement_timeout = '180s';

select pg_advisory_xact_lock(
  hashtext('stayqr:202608110069:checkout-folio-no-synthetic-payment-status')
);

do $repair$
declare
  v_oid oid;
  v_def text;
  v_old_decl text :=
    '  authoritative_paid_remaining numeric(12,2) := 0;';
  v_old_assign text :=
    '  authoritative_paid_remaining := previously_paid;';
  v_old_loop text :=
    '    -- Reconcile legacy payment-demand status against money already proven by the folio.' || E'\n' ||
    '    authoritative_paid_remaining := greatest(' || E'\n' ||
    '      round(authoritative_paid_remaining - payment_collected, 2),' || E'\n' ||
    '      0' || E'\n' ||
    '    );' || E'\n' ||
    '    payment_balance := greatest(round(payment_row.amount - payment_collected, 2), 0);' || E'\n' ||
    '    if authoritative_paid_remaining > 0 and payment_balance > 0 then' || E'\n' ||
    '      collection_amount := least(payment_balance, authoritative_paid_remaining);' || E'\n' ||
    '      payment_collected := round(payment_collected + collection_amount, 2);' || E'\n' ||
    '      authoritative_paid_remaining := greatest(' || E'\n' ||
    '        round(authoritative_paid_remaining - collection_amount, 2),' || E'\n' ||
    '        0' || E'\n' ||
    '      );' || E'\n' ||
    '    end if;' || E'\n' ||
    '    payment_balance := greatest(round(payment_row.amount - payment_collected, 2), 0);';
  v_new_loop text :=
    '    -- DAY19_R3_CHECKOUT_FOLIO_NO_SYNTHETIC_PAYMENT_STATUS_REV1' || E'\n' ||
    '    -- Keep legacy payment status tied only to actual payment_collections.' || E'\n' ||
    '    -- Authoritative folio collections already affect previously_paid above.' || E'\n' ||
    '    payment_balance := greatest(round(payment_row.amount - payment_collected, 2), 0);';
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
    raise exception 'Migration 069 stopped: canonical checkout_guest_session signature was not found.';
  end if;

  v_def := pg_get_functiondef(v_oid);

  -- Idempotent rerun.
  if position('DAY19_R3_CHECKOUT_FOLIO_NO_SYNTHETIC_PAYMENT_STATUS_REV1' in v_def) > 0 then
    return;
  end if;

  if position('DAY19_R3_CHECKOUT_FOLIO_RECONCILIATION_REV1' in v_def) = 0 then
    raise exception 'Migration 069 stopped: Migration 068 folio reconciliation marker is missing.';
  end if;

  if position(v_old_loop in v_def) = 0 then
    raise exception 'Migration 069 stopped: Migration 068 synthetic payment-status block was not found.';
  end if;

  -- The variable/assignment are no longer needed once synthetic allocation is removed.
  v_def := replace(v_def, v_old_decl || E'\n', '');
  v_def := replace(v_def, v_old_assign || E'\n', '');
  v_def := replace(v_def, v_old_loop, v_new_loop);

  execute v_def;
end;
$repair$;

comment on function public.checkout_guest_session(
  uuid, uuid, numeric, text, numeric, boolean, text, text, text, boolean
) is
'StayQR checkout. Day19 Migration069: folio collections count as previously paid without synthesizing legacy payment paid state or duplicate folio collections.';

do $verify$
declare
  v_def text;
begin
  select pg_get_functiondef(
    'public.checkout_guest_session(uuid,uuid,numeric,text,numeric,boolean,text,text,text,boolean)'::regprocedure
  )
  into v_def;

  if v_def not like '%DAY19_R3_CHECKOUT_FOLIO_RECONCILIATION_REV1%' then
    raise exception 'Migration 069 verification failed: Migration 068 authoritative folio read is missing.';
  end if;

  if v_def not like '%previously_paid := greatest(previously_paid, folio_paid_amount)%' then
    raise exception 'Migration 069 verification failed: authoritative paid merge is missing.';
  end if;

  if v_def not like '%DAY19_R3_CHECKOUT_FOLIO_NO_SYNTHETIC_PAYMENT_STATUS_REV1%' then
    raise exception 'Migration 069 verification failed: corrective marker missing.';
  end if;

  if v_def like '%authoritative_paid_remaining%' then
    raise exception 'Migration 069 verification failed: synthetic payment-status allocation still exists.';
  end if;
end;
$verify$;

commit;
