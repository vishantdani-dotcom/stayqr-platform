-- StayQR v1.0 Day 20
-- Migration 072 REV1
-- Migration 069 runtime compatibility repair
--
-- Context:
--   Day19 Migration 069 is correct in intent, but its removal of two lines from
--   pg_get_functiondef() included a required trailing LF. Production's stored
--   function representation did not match that exact newline shape, so the
--   final verifier detected authoritative_paid_remaining and rolled the whole
--   transaction back.
--
-- Purpose:
--   Apply the same accepted Day19 correction using representation-tolerant
--   replacements while preserving the already-accepted Migration 068 folio
--   reconciliation behavior.
--
-- Safety:
--   * Forward-only Day 20 migration.
--   * No hotel/guest/reservation/payment/folio business rows are modified.
--   * Fails closed on an unknown checkout function shape.
--   * Idempotent on Staging where the Day19 correction already exists.

begin;

set local lock_timeout = '10s';
set local statement_timeout = '180s';

select pg_advisory_xact_lock(
  hashtext('stayqr:202608120072:checkout-folio-no-synthetic-runtime-compat')
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
    raise exception 'Migration 072 stopped: canonical checkout_guest_session signature was not found.';
  end if;

  v_def := pg_get_functiondef(v_oid);

  if position('DAY19_R3_CHECKOUT_FOLIO_RECONCILIATION_REV1' in v_def) = 0 then
    raise exception 'Migration 072 stopped: Migration 068 folio reconciliation marker is missing.';
  end if;

  -- Staging / already-correct runtime: accept idempotently.
  if position('DAY19_R3_CHECKOUT_FOLIO_NO_SYNTHETIC_PAYMENT_STATUS_REV1' in v_def) > 0
     and position('authoritative_paid_remaining' in v_def) = 0 then
    return;
  end if;

  -- Production after Migration 068: require the known synthetic block.
  if position(v_old_loop in v_def) = 0 then
    raise exception 'Migration 072 stopped: expected Migration 068 synthetic payment-status block was not found.';
  end if;

  -- Representation-tolerant repair: do not require a trailing newline.
  v_def := replace(v_def, v_old_decl, '');
  v_def := replace(v_def, v_old_assign, '');
  v_def := replace(v_def, v_old_loop, v_new_loop);

  if position('authoritative_paid_remaining' in v_def) > 0 then
    raise exception 'Migration 072 stopped: authoritative_paid_remaining remains after repair.';
  end if;

  if position('DAY19_R3_CHECKOUT_FOLIO_NO_SYNTHETIC_PAYMENT_STATUS_REV1' in v_def) = 0 then
    raise exception 'Migration 072 stopped: corrective marker was not installed.';
  end if;

  execute v_def;
end;
$repair$;

comment on function public.checkout_guest_session(
  uuid, uuid, numeric, text, numeric, boolean, text, text, text, boolean
) is
'StayQR checkout. Day20 Migration072 runtime-compatible application of Day19 Migration069: folio collections count as previously paid without synthesizing legacy payment paid state or duplicate folio collections.';

do $verify$
declare
  v_def text;
begin
  select pg_get_functiondef(
    'public.checkout_guest_session(uuid,uuid,numeric,text,numeric,boolean,text,text,text,boolean)'::regprocedure
  )
  into v_def;

  if v_def not like '%DAY19_R3_CHECKOUT_FOLIO_RECONCILIATION_REV1%' then
    raise exception 'Migration 072 verification failed: Migration 068 authoritative folio read is missing.';
  end if;

  if v_def not like '%previously_paid := greatest(previously_paid, folio_paid_amount)%' then
    raise exception 'Migration 072 verification failed: authoritative paid merge is missing.';
  end if;

  if v_def not like '%DAY19_R3_CHECKOUT_FOLIO_NO_SYNTHETIC_PAYMENT_STATUS_REV1%' then
    raise exception 'Migration 072 verification failed: corrective marker missing.';
  end if;

  if v_def like '%authoritative_paid_remaining%' then
    raise exception 'Migration 072 verification failed: synthetic payment-status allocation still exists.';
  end if;
end;
$verify$;

commit;

select
  'M072_POSTCOMMIT'::text as suite,
  (
    position(
      'DAY19_R3_CHECKOUT_FOLIO_NO_SYNTHETIC_PAYMENT_STATUS_REV1'
      in pg_get_functiondef(
        'public.checkout_guest_session(uuid,uuid,numeric,text,numeric,boolean,text,text,text,boolean)'::regprocedure
      )
    ) > 0
    and position(
      'authoritative_paid_remaining'
      in pg_get_functiondef(
        'public.checkout_guest_session(uuid,uuid,numeric,text,numeric,boolean,text,text,text,boolean)'::regprocedure
      )
    ) = 0
  ) as passed,
  'Migration 068 folio reconciliation retained; synthetic legacy payment-status allocation absent.'::text as details;
