-- Generated from reviewed production contracts; see scripts/lib/pilot-checkout-compatibility.mjs.
-- Supports known flat staging and routed production shapes only. No historical data correction.
-- Apply only to the explicitly approved environment; do NOT blanket-push old migrations 105/106.
begin;
set local lock_timeout = '10s';
set local statement_timeout = '180s';
select pg_advisory_xact_lock(hashtext('stayqr:202609030107:checkout-compatibility'));
create temporary table pilot_checkout_security_snapshot on commit drop as
  select p.oid, p.proacl, p.proowner, p.proconfig, p.prosecdef, pg_get_expr(p.proargdefaults,0) as defaults
  from pg_proc p where p.oid in (select to_regprocedure(s) from (values
    ('public.checkout_guest_session(uuid,uuid,numeric,text,numeric,boolean,text,text,text,boolean)'),
    ('public.checkout_guest_session_day20_legacy(uuid,uuid,numeric,text,numeric,boolean,text,text,text,boolean)'),
    ('private.day20_checkout_existing_invoice(uuid,uuid,numeric,text,numeric,boolean,text,text,text,boolean)'),
    ('private.pilot_prepare_checkout_folio(uuid,uuid,numeric,numeric,numeric,numeric,text)')) as targets(s));
do $preflight$
begin
  if to_regprocedure('public.checkout_guest_session(uuid,uuid,numeric,text,numeric,boolean,text,text,text,boolean)') is null then raise exception 'Checkout entry point missing.'; end if;
  if exists (select 1 from pg_proc where oid = to_regprocedure('public.checkout_guest_session(uuid,uuid,numeric,text,numeric,boolean,text,text,text,boolean)')
    and md5(trim(replace(prosrc,chr(13),''))) not in ('5b4bddb16807fdbf367581c4961fd576','466547a632e6519971e05956a3455962')) then
    raise exception 'Unknown checkout predecessor: public.checkout_guest_session. No changes applied.';
  end if;
  if exists (select 1 from pg_proc where oid = to_regprocedure('public.checkout_guest_session_day20_legacy(uuid,uuid,numeric,text,numeric,boolean,text,text,text,boolean)')
    and md5(trim(replace(prosrc,chr(13),''))) not in ('46ed2c2cb6410a7bde162875dde7330a','5ff027801e7db8e992f1c96fbfa22830')) then
    raise exception 'Unknown checkout predecessor: public.checkout_guest_session_day20_legacy. No changes applied.';
  end if;
  if exists (select 1 from pg_proc where oid = to_regprocedure('private.day20_checkout_existing_invoice(uuid,uuid,numeric,text,numeric,boolean,text,text,text,boolean)')
    and md5(trim(replace(prosrc,chr(13),''))) not in ('08cc27441bcb7d12f671cb990a782728','035653f307fd4a9c5202b5d7395a2536')) then
    raise exception 'Unknown checkout predecessor: private.day20_checkout_existing_invoice. No changes applied.';
  end if;
  if exists (select 1 from pg_proc where oid = to_regprocedure('private.pilot_prepare_checkout_folio(uuid,uuid,numeric,numeric,numeric,numeric,text)')
    and md5(trim(replace(prosrc,chr(13),''))) not in ('fbc510db81bf08b1aa85690d51333018')) then
    raise exception 'Unknown checkout predecessor: private.pilot_prepare_checkout_folio. No changes applied.';
  end if;
  if exists (select 1 from pilot_checkout_security_snapshot where not prosecdef
    or proowner <> 'postgres'::regrole or proconfig is distinct from array['search_path=""']) then
    raise exception 'Unexpected checkout security contract. No changes applied.';
  end if;
  if (to_regprocedure('public.checkout_guest_session_day20_legacy(uuid,uuid,numeric,text,numeric,boolean,text,text,text,boolean)') is null) <> (to_regprocedure('private.day20_checkout_existing_invoice(uuid,uuid,numeric,text,numeric,boolean,text,text,text,boolean)') is null) then
    raise exception 'Incomplete routed checkout predecessor.';
  end if;
end;
$preflight$;

CREATE OR REPLACE FUNCTION private.pilot_prepare_checkout_folio(target_hotel_id uuid, target_guest_session_id uuid, expected_subtotal numeric, expected_tax numeric, expected_discount numeric, expected_paid numeric, reason_value text)
 RETURNS folios
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
CREATE OR REPLACE FUNCTION private.day20_checkout_existing_invoice(target_hotel_id uuid, target_guest_session_id uuid, tax_percent numeric DEFAULT 0, discount_type text DEFAULT 'fixed'::text, discount_value numeric DEFAULT 0, remaining_payment_collected boolean DEFAULT false, settlement_payment_method text DEFAULT 'cash'::text, settlement_transaction_reference text DEFAULT NULL::text, invoice_notes text DEFAULT NULL::text, allow_excess_paid boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  session_row public.guest_sessions%rowtype;
  room_row public.rooms%rowtype;
  guest_row public.guests%rowtype;
  invoice_row public.invoices%rowtype;
  folio_row public.folios%rowtype;
  existing_event public.reservation_checkout_events%rowtype;

  actor_id uuid := auth.uid();
  stay_end timestamptz := now();

  stay_hours integer;
  stay_nights integer;

  requested_tax numeric(12,2);
  requested_discount numeric(12,2);
  normalized_discount_type text;

  invoice_total numeric(12,2);
  issued_gross_subtotal numeric(14,2);
  net_collection numeric(12,2);
  live_pending numeric(12,2);
  live_excess numeric(12,2);

  housekeeping_task_id uuid;
  reservation_snapshot jsonb;
  checkout_snapshot jsonb;
  open_food_count integer := 0;
begin

  perform private.assert_reservation_write_access(target_hotel_id);

  if target_guest_session_id is null then
    raise exception 'Guest session is required.';
  end if;


  -- ----------------------------------------------------------
  -- Lock and validate stay
  -- ----------------------------------------------------------

  select gs.*
  into session_row
  from public.guest_sessions gs
  where gs.hotel_id = target_hotel_id
    and gs.id = target_guest_session_id
  for update;

  if not found then
    raise exception 'Guest stay not found.';
  end if;


  -- ----------------------------------------------------------
  -- Idempotent already-checked-out protection
  -- ----------------------------------------------------------

  select event.*
  into existing_event
  from public.reservation_checkout_events event
  where event.hotel_id = target_hotel_id
    and event.guest_session_id = target_guest_session_id
  order by event.checked_out_at desc
  limit 1;

  if existing_event.id is not null then
    select inv.*
    into invoice_row
    from public.invoices inv
    where inv.hotel_id = target_hotel_id
      and inv.id = existing_event.invoice_id
    limit 1;

    return jsonb_build_object(
      'success', true,
      'already_checked_out', true,
      'existing_invoice_reused', true,
      'grand_total', invoice_row.total_amount,
      'previously_paid', coalesce((existing_event.settlement_snapshot ->> 'authoritative_net_collection')::numeric,
        (existing_event.settlement_snapshot ->> 'previously_paid')::numeric, 0),
      'amount_collected_at_checkout', 0,
      'room_number', existing_event.settlement_snapshot ->> 'room_number',
      'reservation_id', existing_event.reservation_id,
      'reservation_room_id', existing_event.reservation_room_id,
      'housekeeping_task_id', existing_event.settlement_snapshot ->> 'housekeeping_task_id',
      'invoice_id', existing_event.invoice_id,
      'invoice_number', invoice_row.invoice_number,
      'guest_session_id', target_guest_session_id,
      'room_id', existing_event.room_id,
      'stay_status', 'completed'
    );
  end if;


  if session_row.status <> 'active' then
    raise exception 'Only an active guest stay can be checked out.';
  end if;

  if session_row.checkin_time is null then
    raise exception 'Guest check-in time is missing.';
  end if;


  -- ----------------------------------------------------------
  -- Room + guest
  -- ----------------------------------------------------------

  select rm.*
  into room_row
  from public.rooms rm
  where rm.hotel_id = target_hotel_id
    and rm.id = session_row.room_id
  for update;

  if not found then
    raise exception 'Stay room not found.';
  end if;


  select g.*
  into guest_row
  from public.guests g
  where g.hotel_id = target_hotel_id
    and g.id = session_row.guest_id;

  if not found then
    raise exception 'Stay guest not found.';
  end if;


  -- ----------------------------------------------------------
  -- Existing authoritative invoice
  -- ----------------------------------------------------------

  select inv.*
  into invoice_row
  from public.invoices inv
  where inv.hotel_id = target_hotel_id
    and inv.guest_session_id = target_guest_session_id
  order by inv.created_at
  limit 1
  for update;

  if not found then
    raise exception
      'Existing-invoice checkout path called without an invoice.';
  end if;


  if invoice_row.folio_id is null then
    raise exception
      'Existing invoice % has no authoritative folio.',
      coalesce(invoice_row.invoice_number, invoice_row.id::text);
  end if;


  if invoice_row.finalized_at is null then
    raise exception
      'Existing invoice % is not finalized.',
      coalesce(invoice_row.invoice_number, invoice_row.id::text);
  end if;


  -- ----------------------------------------------------------
  -- Prevent UI bill from disagreeing with immutable invoice
  -- ----------------------------------------------------------

  requested_tax :=
    round(coalesce(tax_percent, 0)::numeric, 2);

  requested_discount :=
    round(coalesce(discount_value, 0)::numeric, 2);

  normalized_discount_type :=
    lower(trim(coalesce(discount_type, 'fixed')));


  if requested_tax <>
     round(coalesce(invoice_row.tax_percent, 0)::numeric, 2)
  then
    raise exception
      'Existing invoice % uses tax % percent. Refresh checkout and use the issued invoice tax.',
      invoice_row.invoice_number,
      invoice_row.tax_percent;
  end if;


  if normalized_discount_type <>
     lower(trim(coalesce(invoice_row.discount_type, 'fixed')))
  then
    raise exception
      'Existing invoice % uses a different discount type. Refresh checkout.',
      invoice_row.invoice_number;
  end if;


  if requested_discount <>
     round(coalesce(invoice_row.discount_value, 0)::numeric, 2)
  then
    raise exception
      'Existing invoice % uses discount value %. Refresh checkout.',
      invoice_row.invoice_number,
      invoice_row.discount_value;
  end if;


  -- ----------------------------------------------------------
  -- Open food orders still block checkout
  -- ----------------------------------------------------------

  select count(*)::integer
  into open_food_count
  from public.food_orders fo
  where fo.hotel_id = target_hotel_id
    and fo.guest_id = session_row.guest_id
    and fo.room_id = session_row.room_id
    and fo.created_at >= session_row.checkin_time
    and fo.order_status in (
      'pending',
      'accepted',
      'preparing',
      'out_for_delivery'
    );

  if open_food_count > 0 then
    raise exception
      '% food order(s) are still active. Complete or cancel them before checkout.',
      open_food_count;
  end if;


  -- ----------------------------------------------------------
  -- AUTHORITATIVE SETTLEMENT
  --
  -- Same principle used by the Day 12 finance engine:
  --
  -- net collection = folio collections - refunds
  --
  -- Do NOT trust stale invoice.pending_amount here.
  -- ----------------------------------------------------------

  select f.*
  into folio_row
  from public.folios f
  where f.hotel_id = target_hotel_id
    and f.id = invoice_row.folio_id
  for update;

  if not found then
    raise exception
      'Authoritative folio for invoice % was not found.',
      invoice_row.invoice_number;
  end if;


  invoice_total :=
    round(coalesce(invoice_row.total_amount, 0)::numeric, 2);

  net_collection :=
    greatest(
      round(
        coalesce(folio_row.collection_amount, 0)
        -
        coalesce(folio_row.refund_amount, 0),
        2
      ),
      0
    );

  live_pending :=
    greatest(
      round(invoice_total - net_collection, 2),
      0
    );

  live_excess :=
    greatest(
      round(net_collection - invoice_total, 2),
      0
    );


  if live_pending > 0 then
    raise exception
      'Existing invoice % still has an authoritative folio balance of %. Settle it before checkout.',
      invoice_row.invoice_number,
      live_pending;
  end if;


  if live_excess > 0
     and not coalesce(allow_excess_paid, false)
  then
    raise exception
      'Authoritative folio collections exceed invoice % by %. Verify refund or adjustment before checkout.',
      invoice_row.invoice_number,
      live_excess;
  end if;


  -- PILOT_ROUTED_CHECKOUT_COMPATIBILITY_REV1
  -- Preserve the issued invoice and prove that its SAME-STAY ledger agrees.
  -- Day13 checkout invoices store gross subtotal; native Day12 folio invoices
  -- store the post-discount taxable subtotal. Never subtract the discount twice.
  if invoice_row.metadata ->> 'day13_checkout_compatibility' = 'true' then
    issued_gross_subtotal := invoice_row.subtotal_amount;
  elsif invoice_row.invoice_origin = 'authoritative' and invoice_row.metadata ->> 'source' = 'folio' then
    issued_gross_subtotal := invoice_row.subtotal_amount + invoice_row.discount_amount;
  else
    raise exception 'Unknown issued invoice accounting format. Review Folio & Settlement before checkout.';
  end if;
  if folio_row.guest_session_id is distinct from target_guest_session_id
     or folio_row.status = 'voided'
     or invoice_row.subtotal_amount is null or invoice_row.tax_amount is null
     or invoice_row.discount_amount is null or invoice_row.total_amount is null
     or invoice_row.total_amount <> issued_gross_subtotal + invoice_row.tax_amount - invoice_row.discount_amount
     or folio_row.charges_amount <> issued_gross_subtotal then
    raise exception 'Issued invoice and same-stay folio charges differ. Review Folio & Settlement before checkout.';
  end if;
  if folio_row.refund_amount = 0 and folio_row.credit_amount = 0 then
    folio_row := private.pilot_prepare_checkout_folio(
      target_hotel_id, target_guest_session_id, issued_gross_subtotal,
      invoice_row.tax_amount, invoice_row.discount_amount, folio_row.collection_amount, invoice_notes);
  end if;
  -- Existing reconciled refunds remain valid. Credits, excess funds or conflicting
  -- adjustments require their own workflow; this checkout never invents a collection.
  if folio_row.id <> invoice_row.folio_id or folio_row.balance_amount <> 0
     or folio_row.charges_amount <> issued_gross_subtotal
     or folio_row.tax_amount <> invoice_row.tax_amount
     or folio_row.discount_amount <> invoice_row.discount_amount
     or folio_row.credit_amount <> 0
     or folio_row.collection_amount - folio_row.refund_amount <> invoice_total then
    raise exception 'Issued invoice and live folio do not reconcile. Review refunds, credits or adjustments before checkout.';
  end if;

  -- ----------------------------------------------------------
  -- Stay duration
  -- ----------------------------------------------------------

  stay_hours :=
    greatest(
      1,
      ceil(
        extract(epoch from (stay_end - session_row.checkin_time))
        / 3600.0
      )::integer
    );

  stay_nights :=
    greatest(
      1,
      ceil(stay_hours / 24.0)::integer
    );


  -- ----------------------------------------------------------
  -- Mark delivered/manual operational charges paid.
  -- No NEW collection is created here.
  -- ----------------------------------------------------------

  update public.food_orders
  set payment_status = 'paid'
  where hotel_id = target_hotel_id
    and guest_id = session_row.guest_id
    and room_id = session_row.room_id
    and order_status = 'delivered'
    and created_at >= session_row.checkin_time;


  update public.manual_charges
  set payment_status = 'paid'
  where hotel_id = target_hotel_id
    and guest_id = session_row.guest_id
    and room_id = session_row.room_id
    and created_at >= session_row.checkin_time;


  -- Verify operational triggers did not synthesize collections or alter invoice evidence.
  if not exists (select 1 from public.folios f where f.hotel_id = target_hotel_id
      and f.id = invoice_row.folio_id and f.guest_session_id = target_guest_session_id
      and f.balance_amount = 0 and f.charges_amount = folio_row.charges_amount
      and f.tax_amount = folio_row.tax_amount and f.discount_amount = folio_row.discount_amount
      and f.collection_amount = folio_row.collection_amount
      and f.refund_amount = folio_row.refund_amount and f.credit_amount = folio_row.credit_amount)
     or not exists (select 1 from public.invoices i where i.hotel_id = target_hotel_id
       and i.id = invoice_row.id and to_jsonb(i) = to_jsonb(invoice_row)) then
    raise exception 'Issued invoice or settlement evidence changed during checkout. No changes saved.';
  end if;

  -- ----------------------------------------------------------
  -- Complete stay
  -- ----------------------------------------------------------

  update public.guest_sessions
  set
    status = 'completed',
    expired_at = stay_end,
    checked_out_at = stay_end,
    checked_out_by = actor_id
  where hotel_id = target_hotel_id
    and id = target_guest_session_id
    and status = 'active';

  if not found then
    raise exception
      'Checkout lost its active-stay lock. Refresh and try again.';
  end if;


  -- ----------------------------------------------------------
  -- Release inventory
  -- ----------------------------------------------------------

  update public.room_inventory_allocations
  set
    status = 'released',
    released_at = stay_end,
    updated_at = stay_end
  where hotel_id = target_hotel_id
    and status = 'active'
    and (
      reservation_room_id = session_row.reservation_room_id
      or guest_session_id = target_guest_session_id
    );


  -- ----------------------------------------------------------
  -- Post-checkout room state
  -- ----------------------------------------------------------

  update public.rooms
  set status = 'cleaning'
  where hotel_id = target_hotel_id
    and id = session_row.room_id
    and status = 'occupied';


  -- ----------------------------------------------------------
  -- Housekeeping
  -- ----------------------------------------------------------

  select task.id
  into housekeeping_task_id
  from public.housekeeping_tasks task
  where task.hotel_id = target_hotel_id
    and task.room_id = session_row.room_id
    and task.task_type = 'room_cleaning'
    and task.status in ('pending', 'in_progress')
  order by task.created_at
  limit 1
  for update;


  if housekeeping_task_id is null then

    insert into public.housekeeping_tasks (
      hotel_id,
      room_id,
      room_number,
      task_type,
      status,
      notes
    )
    values (
      target_hotel_id,
      session_row.room_id,
      room_row.room_number,
      'room_cleaning',
      'pending',
      format(
        'Checkout cleaning task for existing invoice %s',
        invoice_row.invoice_number
      )
    )
    returning id into housekeeping_task_id;

  end if;


  -- ----------------------------------------------------------
  -- Settle folio only when its authoritative balance is zero
  -- ----------------------------------------------------------

  if coalesce(folio_row.balance_amount, 0) = 0
     and folio_row.status = 'open'
  then

    update public.folios
    set
      status = 'settled',
      settled_at = coalesce(settled_at, stay_end),
      settled_by = coalesce(settled_by, actor_id)
    where hotel_id = target_hotel_id
      and id = folio_row.id
      and status = 'open'
      and balance_amount = 0;

  end if;


  -- ----------------------------------------------------------
  -- Reservation snapshot
  -- ----------------------------------------------------------

  if session_row.reservation_id is not null then

    reservation_snapshot :=
      private.build_reservation_json(
        target_hotel_id,
        session_row.reservation_id
      );

  end if;


  -- ----------------------------------------------------------
  -- Checkout settlement snapshot
  --
  -- Existing immutable invoice is REUSED.
  -- amount_collected_at_checkout = 0
  -- ----------------------------------------------------------

  checkout_snapshot :=
    jsonb_build_object(
      'invoice_id', invoice_row.id,
      'invoice_number', invoice_row.invoice_number,
      'existing_invoice_reused', true,

      'hotel_id', target_hotel_id,
      'guest_session_id', target_guest_session_id,
      'reservation_id', session_row.reservation_id,
      'reservation_room_id', session_row.reservation_room_id,

      'room_id', session_row.room_id,
      'room_number', room_row.room_number,

      'guest_id', session_row.guest_id,
      'guest_name', guest_row.full_name,

      'checkin_time', session_row.checkin_time,
      'checkout_time', stay_end,
      'stay_hours', stay_hours,
      'stay_nights', stay_nights,

      'room_amount', invoice_row.room_amount,
      'food_amount', invoice_row.food_amount,
      'manual_amount', invoice_row.manual_amount,
      'service_amount', invoice_row.service_amount,

      'subtotal', invoice_row.subtotal_amount,
      'tax_percent', invoice_row.tax_percent,
      'tax_amount', invoice_row.tax_amount,

      'discount_type', invoice_row.discount_type,
      'discount_value', invoice_row.discount_value,
      'discount_amount', invoice_row.discount_amount,

      'grand_total', invoice_total,

      'authoritative_net_collection', net_collection,
      'remaining_to_collect', live_pending,
      'amount_collected_at_checkout', 0,

      'housekeeping_task_id', housekeeping_task_id,
      'reservation', reservation_snapshot
    );


  -- ----------------------------------------------------------
  -- Authoritative checkout event
  -- ----------------------------------------------------------

  insert into public.reservation_checkout_events (
    hotel_id,
    guest_session_id,
    reservation_id,
    reservation_room_id,
    room_id,
    guest_id,
    invoice_id,
    checked_out_by,
    checked_out_at,
    settlement_snapshot,
    metadata
  )
  values (
    target_hotel_id,
    target_guest_session_id,
    session_row.reservation_id,
    session_row.reservation_room_id,
    session_row.room_id,
    session_row.guest_id,
    invoice_row.id,
    actor_id,
    stay_end,
    checkout_snapshot,
    jsonb_build_object(
      'source', 'day20_existing_immutable_invoice_checkout',
      'existing_invoice_reused', true,
      'additional_collection_created', false,
      'payment_method',
        lower(trim(coalesce(settlement_payment_method, 'cash'))),
      'transaction_reference',
        nullif(
          trim(
            coalesce(settlement_transaction_reference, '')
          ),
          ''
        )
    )
  );


  -- ----------------------------------------------------------
  -- Activity log
  -- ----------------------------------------------------------

  if session_row.reservation_id is not null then

    perform private.write_activity_log(
      target_hotel_id,
      'reservation.room_checkout_completed',
      'reservation',
      session_row.reservation_id,

      format(
        'Room %s checkout completed using existing invoice %s.',
        room_row.room_number,
        invoice_row.invoice_number
      ),

      null,
      reservation_snapshot,

      jsonb_build_object(
        'reservation_room_id',
          session_row.reservation_room_id,
        'guest_session_id',
          target_guest_session_id,
        'invoice_id',
          invoice_row.id,
        'existing_invoice_reused',
          true,
        'housekeeping_task_id',
          housekeeping_task_id,
        'grand_total',
          invoice_total,
        'authoritative_net_collection',
          net_collection,
        'amount_collected_at_checkout',
          0
      )
    );

  end if;


  -- ----------------------------------------------------------
  -- SUCCESS
  -- ----------------------------------------------------------

  return jsonb_build_object(
    'success', true,

    'existing_invoice_reused', true,

    'invoice_id', invoice_row.id,
    'invoice_number', invoice_row.invoice_number,

    'guest_session_id', target_guest_session_id,
    'reservation_id', session_row.reservation_id,
    'reservation_room_id', session_row.reservation_room_id,

    'room_id', session_row.room_id,
    'room_number', room_row.room_number,

    'housekeeping_task_id', housekeeping_task_id,

    'grand_total', invoice_total,
    'previously_paid', net_collection,
    'remaining_to_collect', live_pending,
    'amount_collected_at_checkout', 0,

    'room_status', 'cleaning',
    'stay_status', 'completed',

    'reservation', reservation_snapshot
  );

end;
$function$;
CREATE OR REPLACE FUNCTION public.checkout_guest_session_day20_legacy(target_hotel_id uuid, target_guest_session_id uuid, tax_percent numeric DEFAULT 0, discount_type text DEFAULT 'fixed'::text, discount_value numeric DEFAULT 0, remaining_payment_collected boolean DEFAULT false, settlement_payment_method text DEFAULT 'cash'::text, settlement_transaction_reference text DEFAULT NULL::text, invoice_notes text DEFAULT NULL::text, allow_excess_paid boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  session_row public.guest_sessions%rowtype;
  checkout_folio public.folios%rowtype;
  room_row public.rooms%rowtype;
  guest_row public.guests%rowtype;
  existing_event public.reservation_checkout_events%rowtype;
  existing_invoice public.invoices%rowtype;
  payment_row public.payments%rowtype;
  stay_end timestamptz := now();
  stay_hours integer;
  stay_nights integer;
  safe_tax_percent numeric(12,2);
  safe_discount_value numeric(12,2);
  room_amount numeric(12,2) := 0;
  food_amount numeric(12,2) := 0;
  manual_amount numeric(12,2) := 0;
  service_amount numeric(12,2) := 0;
  subtotal numeric(12,2) := 0;
  tax_amount numeric(12,2) := 0;
  discount_amount numeric(12,2) := 0;
  grand_total numeric(12,2) := 0;
  previously_paid numeric(12,2) := 0;
  amount_to_collect numeric(12,2) := 0;
  excess_paid numeric(12,2) := 0;
  amount_remaining numeric(12,2) := 0;
  folio_paid_amount numeric(12,2) := 0;

  payment_collected numeric(12,2) := 0;
  payment_balance numeric(12,2) := 0;
  collection_amount numeric(12,2) := 0;
  created_invoice_id uuid;
  created_invoice_number text;
  settlement_payment_id uuid;
  housekeeping_task_id uuid;
  reservation_snapshot jsonb;
  checkout_snapshot jsonb;
  open_food_count integer := 0;
  food_order_count integer := 0;
  food_item_count integer := 0;
  actor_id uuid := auth.uid();
begin
  perform private.assert_reservation_write_access(target_hotel_id);

  if target_guest_session_id is null then
    raise exception 'Guest session is required.';
  end if;

  safe_tax_percent := round(coalesce(tax_percent, 0)::numeric, 2);
  safe_discount_value := round(coalesce(discount_value, 0)::numeric, 2);
  discount_type := lower(trim(coalesce(discount_type, 'fixed')));
  settlement_payment_method := lower(trim(coalesce(settlement_payment_method, 'cash')));

  if safe_tax_percent < 0 or safe_tax_percent > 100 then
    raise exception 'Tax percentage must be between 0 and 100.';
  end if;

  if discount_type not in ('fixed', 'percentage') then
    raise exception 'Discount type must be fixed or percentage.';
  end if;

  if safe_discount_value < 0 then
    raise exception 'Discount value cannot be negative.';
  end if;

  if discount_type = 'percentage' and safe_discount_value > 100 then
    raise exception 'Discount percentage cannot exceed 100%%.';
  end if;

  if settlement_payment_method not in ('cash', 'upi', 'card', 'bank_transfer', 'other') then
    raise exception 'Unsupported settlement payment method.';
  end if;

  if settlement_payment_method in ('upi', 'card', 'bank_transfer')
     and length(trim(coalesce(settlement_transaction_reference, ''))) = 0
  then
    raise exception 'A transaction/reference number is required for this payment method.';
  end if;

  select gs.*
  into session_row
  from public.guest_sessions gs
  where gs.hotel_id = target_hotel_id
    and gs.id = target_guest_session_id
  for update;

  if not found then
    raise exception 'Guest stay not found.';
  end if;

  select event.*
  into existing_event
  from public.reservation_checkout_events event
  where event.hotel_id = target_hotel_id
    and event.guest_session_id = target_guest_session_id
  limit 1;

  if existing_event.id is not null then
    select inv.* into existing_invoice
    from public.invoices inv
    where inv.id = existing_event.invoice_id;

    raise exception 'This stay is already checked out. Invoice: %',
      coalesce(existing_invoice.invoice_number, existing_event.invoice_id::text);
  end if;

  if session_row.status <> 'active' then
    raise exception 'Only an active guest stay can be checked out.';
  end if;

  if session_row.checkin_time is null then
    raise exception 'Guest check-in time is missing.';
  end if;

  select rm.* into room_row
  from public.rooms rm
  where rm.hotel_id = target_hotel_id
    and rm.id = session_row.room_id
  for update;

  if not found then raise exception 'Stay room not found.'; end if;

  select g.* into guest_row
  from public.guests g
  where g.hotel_id = target_hotel_id
    and g.id = session_row.guest_id
  for update;

  if not found then raise exception 'Stay guest not found.'; end if;

  select inv.* into existing_invoice
  from public.invoices inv
  where inv.hotel_id = target_hotel_id
    and inv.guest_session_id = target_guest_session_id
  order by inv.created_at
  limit 1
  for update;

  -- DAY20_EXISTING_IMMUTABLE_INVOICE_REUSE_REV1
  -- An existing invoice is valid. It is verified and reused below instead
  -- of creating a second financial document for the same stay.

  select count(*)::integer
  into open_food_count
  from public.food_orders fo
  where fo.hotel_id = target_hotel_id
    and fo.guest_id = session_row.guest_id
    and fo.room_id = session_row.room_id
    and fo.created_at >= session_row.checkin_time
    and fo.order_status in ('pending', 'accepted', 'preparing', 'out_for_delivery');

  if open_food_count > 0 then
    raise exception '% food order(s) are still active. Complete or cancel them before checkout.', open_food_count;
  end if;

  stay_hours := greatest(
    1,
    ceil(extract(epoch from (stay_end - session_row.checkin_time)) / 3600.0)::integer
  );
  stay_nights := greatest(1, ceil(stay_hours / 24.0)::integer);

  -- Reservation-linked payments are exact. Legacy/direct stays fall back to
  -- same hotel + guest + room + stay window.
  select coalesce(sum(p.amount), 0)::numeric(12,2)
  into room_amount
  from public.payments p
  where p.hotel_id = target_hotel_id
    and p.guest_id = session_row.guest_id
    and p.room_id = session_row.room_id
    and p.payment_type = 'room_charge'
    and (
      p.guest_session_id = target_guest_session_id
      or (
        p.guest_session_id is null
        and p.created_at >= session_row.checkin_time
      )
    );

  select
    coalesce(sum(fo.total_amount), 0)::numeric(12,2),
    count(*)::integer
  into food_amount, food_order_count
  from public.food_orders fo
  where fo.hotel_id = target_hotel_id
    and fo.guest_id = session_row.guest_id
    and fo.room_id = session_row.room_id
    and fo.order_status = 'delivered'
    and fo.created_at >= session_row.checkin_time;

  select coalesce(sum(foi.quantity), 0)::integer
  into food_item_count
  from public.food_orders fo
  join public.food_order_items foi
    on foi.order_id = fo.id
  where fo.hotel_id = target_hotel_id
    and fo.guest_id = session_row.guest_id
    and fo.room_id = session_row.room_id
    and fo.order_status = 'delivered'
    and fo.created_at >= session_row.checkin_time;

  select coalesce(sum(mc.charge_amount), 0)::numeric(12,2)
  into manual_amount
  from public.manual_charges mc
  where mc.hotel_id = target_hotel_id
    and mc.guest_id = session_row.guest_id
    and mc.room_id = session_row.room_id
    and mc.created_at >= session_row.checkin_time;

  -- service_requests currently has no mandatory monetary column. Reading via
  -- to_jsonb preserves compatibility if a charge field is added later.
  select coalesce(sum(
    coalesce(
      nullif(to_jsonb(sr)->>'service_amount', '')::numeric,
      nullif(to_jsonb(sr)->>'charge_amount', '')::numeric,
      nullif(to_jsonb(sr)->>'amount', '')::numeric,
      0
    )
  ), 0)::numeric(12,2)
  into service_amount
  from public.service_requests sr
  where sr.hotel_id = target_hotel_id
    and sr.guest_id = session_row.guest_id
    and sr.room_id = session_row.room_id
    and sr.status = 'completed'
    and sr.created_at >= session_row.checkin_time;

  subtotal := round(room_amount + food_amount + manual_amount + service_amount, 2);
  tax_amount := round(subtotal * safe_tax_percent / 100.0, 2);

  if discount_type = 'percentage' then
    discount_amount := round((subtotal + tax_amount) * safe_discount_value / 100.0, 2);
  else
    discount_amount := safe_discount_value;
  end if;

  discount_amount := least(subtotal + tax_amount, discount_amount);
  grand_total := greatest(round(subtotal + tax_amount - discount_amount, 2), 0);

  if existing_invoice.id is not null then
    if
      abs(coalesce(existing_invoice.room_amount, 0) - room_amount) > 0.01
      or abs(coalesce(existing_invoice.food_amount, 0) - food_amount) > 0.01
      or abs(coalesce(existing_invoice.manual_amount, 0) - manual_amount) > 0.01
      or abs(coalesce(existing_invoice.service_amount, 0) - service_amount) > 0.01
    then
      raise exception
        'Existing immutable invoice no longer matches current stay charges. Reconcile the folio before checkout.';
    end if;

    -- PILOT_ROUTED_CHECKOUT_COMPATIBILITY_REV1: direct legacy calls reuse the guarded issued-invoice path.
    return private.day20_checkout_existing_invoice(
      target_hotel_id, target_guest_session_id, tax_percent, discount_type, discount_value,
      remaining_payment_collected, settlement_payment_method, settlement_transaction_reference,
      invoice_notes, allow_excess_paid);

    room_amount := coalesce(existing_invoice.room_amount, 0);
    food_amount := coalesce(existing_invoice.food_amount, 0);
    manual_amount := coalesce(existing_invoice.manual_amount, 0);
    service_amount := coalesce(existing_invoice.service_amount, 0);

    subtotal := coalesce(
      existing_invoice.subtotal_amount,
      round(room_amount + food_amount + manual_amount + service_amount, 2)
    );

    safe_tax_percent := coalesce(existing_invoice.tax_percent, 0);
    tax_amount := coalesce(existing_invoice.tax_amount, 0);

    discount_type := coalesce(existing_invoice.discount_type, discount_type);
    safe_discount_value := coalesce(existing_invoice.discount_value, 0);
    discount_amount := coalesce(existing_invoice.discount_amount, 0);

    grand_total := coalesce(
      existing_invoice.total_amount,
      greatest(round(subtotal + tax_amount - discount_amount, 2), 0)
    );

    stay_hours := coalesce(existing_invoice.stay_hours, stay_hours);
    stay_nights := coalesce(existing_invoice.stay_nights, stay_nights);
    food_order_count := coalesce(existing_invoice.food_order_count, food_order_count);
    food_item_count := coalesce(existing_invoice.food_item_count, food_item_count);
  end if;

  select coalesce(sum(paid_amount_value), 0)::numeric(12,2)
  into previously_paid
  from (
    select pc.amount as paid_amount_value
    from public.payment_collections pc
    join public.payments p
      on p.hotel_id = pc.hotel_id
     and p.id = pc.payment_id
    where pc.hotel_id = target_hotel_id
      and p.guest_id = session_row.guest_id
      and p.room_id = session_row.room_id
      and (
        p.guest_session_id = target_guest_session_id
        or (
          p.guest_session_id is null
          and p.created_at >= session_row.checkin_time
        )
      )

    union all

    select p.amount
    from public.payments p
    where p.hotel_id = target_hotel_id
      and p.guest_id = session_row.guest_id
      and p.room_id = session_row.room_id
      and p.payment_status = 'paid'
      and (
        p.guest_session_id = target_guest_session_id
        or (
          p.guest_session_id is null
          and p.created_at >= session_row.checkin_time
        )
      )
      and not exists (
        select 1
        from public.payment_collections pc
        where pc.hotel_id = p.hotel_id
          and pc.payment_id = p.id
      )
  ) paid_rows;

  -- DAY19_R3_CHECKOUT_FOLIO_RECONCILIATION_REV1
  -- Folio & Settlement is authoritative for direct/split collections.
  select coalesce(f.collection_amount, 0)::numeric(12,2)
  into folio_paid_amount
  from public.folios f
  where f.hotel_id = target_hotel_id
    and f.guest_session_id = target_guest_session_id
  order by f.created_at desc, f.id desc
  limit 1;

  folio_paid_amount := coalesce(folio_paid_amount, 0);
  previously_paid := greatest(previously_paid, folio_paid_amount);


  amount_to_collect := greatest(round(grand_total - previously_paid, 2), 0);
  excess_paid := greatest(round(previously_paid - grand_total, 2), 0);

  if amount_to_collect > 0 and not coalesce(remaining_payment_collected, false) then
    raise exception 'Confirm collection of the remaining amount before checkout.';
  end if;

  if excess_paid > 0 and not coalesce(allow_excess_paid, false) then
    raise exception 'Previous payments exceed the final bill by %. Verify refund/adjustment before checkout.', excess_paid;
  end if;


  -- PILOT_CHECKOUT_FOLIO_CONSISTENCY_REV1
  checkout_folio := private.pilot_prepare_checkout_folio(
    target_hotel_id, target_guest_session_id, subtotal, tax_amount,
    discount_amount, previously_paid, invoice_notes);

  if existing_invoice.id is null then
    created_invoice_number := format(
    'INV-%s-%s',
    to_char(stay_end at time zone 'UTC', 'YYYYMMDD'),
    upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8))
  );

  insert into public.invoices (
    hotel_id,
    guest_session_id,
    room_id,
    guest_id,
    invoice_number,
    room_amount,
    food_amount,
    manual_amount,
    service_amount,
    subtotal_amount,
    tax_percent,
    tax_amount,
    discount_type,
    discount_value,
    discount_amount,
    previous_paid_amount,
    amount_to_collect,
    total_amount,
    payment_status,
    invoice_status,
    paid_amount,
    pending_amount,
    settled_at,
    checkin_time,
    checkout_time,
    stay_hours,
    stay_nights,
    food_order_count,
    food_item_count,
    invoice_notes
  ) values (
    target_hotel_id,
    target_guest_session_id,
    session_row.room_id,
    session_row.guest_id,
    created_invoice_number,
    room_amount,
    food_amount,
    manual_amount,
    service_amount,
    subtotal,
    safe_tax_percent,
    tax_amount,
    discount_type,
    safe_discount_value,
    discount_amount,
    previously_paid,
    amount_to_collect,
    grand_total,
    'paid',
    'paid',
    grand_total,
    0,
    stay_end,
    session_row.checkin_time,
    stay_end,
    stay_hours,
    stay_nights,
    food_order_count,
    food_item_count,
    nullif(trim(coalesce(invoice_notes, '')), '')
  ) returning id, invoice_number into created_invoice_id, created_invoice_number;

  if room_amount > 0 then
    insert into public.invoice_items (
      invoice_id, hotel_id, guest_id, room_id,
      item_type, description, quantity, unit_price, amount, source_id
    ) values (
      created_invoice_id,
      target_hotel_id,
      session_row.guest_id,
      session_row.room_id,
      'room',
      format('%s · %s night(s)', coalesce(room_row.room_type, 'Hotel Room'), stay_nights),
      stay_nights,
      case when stay_nights > 0 then round(room_amount / stay_nights, 2) else room_amount end,
      room_amount,
      target_guest_session_id
    );
  end if;

  insert into public.invoice_items (
    invoice_id, hotel_id, guest_id, room_id,
    item_type, description, quantity, unit_price, amount, source_id
  )
  select
    created_invoice_id,
    target_hotel_id,
    session_row.guest_id,
    session_row.room_id,
    'food',
    coalesce(mi.item_name, 'Food Item'),
    foi.quantity,
    foi.price,
    round(foi.quantity * foi.price, 2),
    fo.id
  from public.food_orders fo
  join public.food_order_items foi
    on foi.order_id = fo.id
  left join public.menu_items mi
    on mi.id = foi.menu_item_id
  where fo.hotel_id = target_hotel_id
    and fo.guest_id = session_row.guest_id
    and fo.room_id = session_row.room_id
    and fo.order_status = 'delivered'
    and fo.created_at >= session_row.checkin_time
    and foi.quantity > 0
    and foi.price > 0;

  insert into public.invoice_items (
    invoice_id, hotel_id, guest_id, room_id,
    item_type, description, quantity, unit_price, amount, source_id
  )
  select
    created_invoice_id,
    target_hotel_id,
    session_row.guest_id,
    session_row.room_id,
    'manual_charge',
    coalesce(mc.charge_name, 'Additional Charge'),
    1,
    mc.charge_amount,
    mc.charge_amount,
    mc.id
  from public.manual_charges mc
  where mc.hotel_id = target_hotel_id
    and mc.guest_id = session_row.guest_id
    and mc.room_id = session_row.room_id
    and mc.created_at >= session_row.checkin_time
    and mc.charge_amount > 0;

  if service_amount > 0 then
    insert into public.invoice_items (
      invoice_id, hotel_id, guest_id, room_id,
      item_type, description, quantity, unit_price, amount, source_id
    ) values (
      created_invoice_id,
      target_hotel_id,
      session_row.guest_id,
      session_row.room_id,
      'service',
      'Completed hotel services',
      1,
      service_amount,
      service_amount,
      null
    );
  end if;

  if tax_amount > 0 then
    insert into public.invoice_items (
      invoice_id, hotel_id, guest_id, room_id,
      item_type, description, quantity, unit_price, amount, source_id
    ) values (
      created_invoice_id,
      target_hotel_id,
      session_row.guest_id,
      session_row.room_id,
      'tax',
      format('Tax %s%%', safe_tax_percent),
      1,
      tax_amount,
      tax_amount,
      null
    );
  end if;

  if discount_amount > 0 then
    insert into public.invoice_items (
      invoice_id, hotel_id, guest_id, room_id,
      item_type, description, quantity, unit_price, amount, source_id
    ) values (
      created_invoice_id,
      target_hotel_id,
      session_row.guest_id,
      session_row.room_id,
      'discount',
      case
        when discount_type = 'percentage' then format('Discount %s%%', safe_discount_value)
        else 'Fixed Discount'
      end,
      1,
      -discount_amount,
      -discount_amount,
      null
    );
  end if;

  else
    created_invoice_id := existing_invoice.id;
    created_invoice_number := coalesce(
      existing_invoice.invoice_number,
      existing_invoice.id::text
    );
  end if;

  -- Record the newly collected balance against existing payment demands first.
  amount_remaining := amount_to_collect;

  for payment_row in
    select p.*
    from public.payments p
    where p.hotel_id = target_hotel_id
      and p.guest_id = session_row.guest_id
      and p.room_id = session_row.room_id
      and (
        p.guest_session_id = target_guest_session_id
        or (
          p.guest_session_id is null
          and p.created_at >= session_row.checkin_time
        )
      )
    order by p.created_at, p.id
    for update
  loop
    select coalesce(sum(pc.amount), 0)::numeric(12,2)
    into payment_collected
    from public.payment_collections pc
    where pc.hotel_id = target_hotel_id
      and pc.payment_id = payment_row.id;

    -- DAY19_R3_CHECKOUT_FOLIO_NO_SYNTHETIC_PAYMENT_STATUS_REV1
    -- Keep legacy payment status tied only to actual payment_collections.
    -- Authoritative folio collections already affect previously_paid above.
    payment_balance := greatest(round(payment_row.amount - payment_collected, 2), 0);
    collection_amount := least(amount_remaining, payment_balance);

    if collection_amount > 0 then
      insert into public.payment_collections (
        hotel_id,
        payment_id,
        guest_id,
        room_id,
        amount,
        payment_method,
        transaction_reference,
        notes,
        collected_by,
        collected_at,
        guest_session_id,
        reservation_id,
        invoice_id
      ) values (
        target_hotel_id,
        payment_row.id,
        session_row.guest_id,
        session_row.room_id,
        collection_amount,
        settlement_payment_method,
        nullif(trim(coalesce(settlement_transaction_reference, '')), ''),
        'Final checkout settlement collected by StayQR',
        actor_id,
        stay_end,
        target_guest_session_id,
        session_row.reservation_id,
        created_invoice_id
      );

      amount_remaining := round(amount_remaining - collection_amount, 2);
      payment_collected := round(payment_collected + collection_amount, 2);
    end if;

    update public.payments
    set
      invoice_id = created_invoice_id,
      payment_status = case
        when payment_collected >= payment_row.amount then 'paid'
        when payment_collected > 0 then 'partial'
        else payment_row.payment_status
      end,
      payment_method = case
        when collection_amount > 0 then settlement_payment_method
        else payment_method
      end,
      transaction_reference = case
        when collection_amount > 0 then nullif(trim(coalesce(settlement_transaction_reference, '')), '')
        else transaction_reference
      end,
      paid_at = case
        when payment_collected >= payment_row.amount then stay_end
        else paid_at
      end
    where hotel_id = target_hotel_id
      and id = payment_row.id;
  end loop;

  -- Charges without an existing demand receive one exact settlement demand.
  if amount_remaining > 0 then
    insert into public.payments (
      hotel_id,
      guest_id,
      room_id,
      amount,
      payment_type,
      payment_status,
      notes,
      payment_method,
      transaction_reference,
      paid_at,
      collected_by,
      payment_notes,
      invoice_id,
      guest_session_id,
      reservation_id,
      reservation_room_id
    ) values (
      target_hotel_id,
      session_row.guest_id,
      session_row.room_id,
      amount_remaining,
      'checkout_settlement',
      'paid',
      format('Final checkout settlement for %s', created_invoice_number),
      settlement_payment_method,
      nullif(trim(coalesce(settlement_transaction_reference, '')), ''),
      stay_end,
      actor_id,
      'Created atomically during final checkout',
      created_invoice_id,
      target_guest_session_id,
      session_row.reservation_id,
      session_row.reservation_room_id
    ) returning id into settlement_payment_id;

    insert into public.payment_collections (
      hotel_id,
      payment_id,
      guest_id,
      room_id,
      amount,
      payment_method,
      transaction_reference,
      notes,
      collected_by,
      collected_at,
      guest_session_id,
      reservation_id,
      invoice_id
    ) values (
      target_hotel_id,
      settlement_payment_id,
      session_row.guest_id,
      session_row.room_id,
      amount_remaining,
      settlement_payment_method,
      nullif(trim(coalesce(settlement_transaction_reference, '')), ''),
      'Final checkout settlement collected by StayQR',
      actor_id,
      stay_end,
      target_guest_session_id,
      session_row.reservation_id,
      created_invoice_id
    );

    amount_remaining := 0;
  end if;

  update public.payment_collections pc
  set invoice_id = created_invoice_id
  from public.payments p
  where p.hotel_id = target_hotel_id
    and p.id = pc.payment_id
    and pc.hotel_id = target_hotel_id
    and p.guest_id = session_row.guest_id
    and p.room_id = session_row.room_id
    and (
      p.guest_session_id = target_guest_session_id
      or (
        p.guest_session_id is null
        and p.created_at >= session_row.checkin_time
      )
    );

  update public.food_orders
  set payment_status = 'paid'
  where hotel_id = target_hotel_id
    and guest_id = session_row.guest_id
    and room_id = session_row.room_id
    and order_status = 'delivered'
    and created_at >= session_row.checkin_time;

  update public.manual_charges
  set payment_status = 'paid'
  where hotel_id = target_hotel_id
    and guest_id = session_row.guest_id
    and room_id = session_row.room_id
    and created_at >= session_row.checkin_time;


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

  update public.guest_sessions
  set
    status = 'completed',
    expired_at = stay_end,
    checked_out_at = stay_end,
    checked_out_by = actor_id
  where hotel_id = target_hotel_id
    and id = target_guest_session_id
    and status = 'active';

  if not found then
    raise exception 'Checkout lost its active-stay lock. Refresh and try again.';
  end if;

  -- Release the active inventory ledger entry so an early checkout does not
  -- keep the room unavailable until the original departure date.
  update public.room_inventory_allocations
  set
    status = 'released',
    released_at = stay_end,
    updated_at = stay_end
  where hotel_id = target_hotel_id
    and status = 'active'
    and (
      reservation_room_id = session_row.reservation_room_id
      or guest_session_id = target_guest_session_id
    );

  -- The Day 5 guest-session trigger advances linked reservation records and
  -- changes occupied rooms to cleaning. Direct stays are handled here too.
  update public.rooms
  set status = 'cleaning'
  where hotel_id = target_hotel_id
    and id = session_row.room_id
    and status = 'occupied';

  select task.id into housekeeping_task_id
  from public.housekeeping_tasks task
  where task.hotel_id = target_hotel_id
    and task.room_id = session_row.room_id
    and task.task_type = 'room_cleaning'
    and task.status in ('pending', 'in_progress')
  order by task.created_at
  limit 1
  for update;

  if housekeeping_task_id is null then
    insert into public.housekeeping_tasks (
      hotel_id,
      room_id,
      room_number,
      task_type,
      status,
      notes
    ) values (
      target_hotel_id,
      session_row.room_id,
      room_row.room_number,
      'room_cleaning',
      'pending',
      format('Checkout cleaning task for invoice %s', created_invoice_number)
    ) returning id into housekeeping_task_id;
  end if;

  if session_row.reservation_id is not null then
    reservation_snapshot := private.build_reservation_json(
      target_hotel_id,
      session_row.reservation_id
    );
  end if;

  checkout_snapshot := jsonb_build_object(
    'invoice_id', created_invoice_id,
    'invoice_number', created_invoice_number,
    'hotel_id', target_hotel_id,
    'guest_session_id', target_guest_session_id,
    'reservation_id', session_row.reservation_id,
    'reservation_room_id', session_row.reservation_room_id,
    'room_id', session_row.room_id,
    'room_number', room_row.room_number,
    'guest_id', session_row.guest_id,
    'guest_name', guest_row.full_name,
    'checkin_time', session_row.checkin_time,
    'checkout_time', stay_end,
    'stay_hours', stay_hours,
    'stay_nights', stay_nights,
    'room_amount', room_amount,
    'food_amount', food_amount,
    'manual_amount', manual_amount,
    'service_amount', service_amount,
    'subtotal', subtotal,
    'tax_percent', safe_tax_percent,
    'tax_amount', tax_amount,
    'discount_type', discount_type,
    'discount_value', safe_discount_value,
    'discount_amount', discount_amount,
    'grand_total', grand_total,
    'previously_paid', previously_paid,
    'amount_collected_at_checkout', amount_to_collect,
    'excess_paid', excess_paid,
    'housekeeping_task_id', housekeeping_task_id,
    'reservation', reservation_snapshot
  );

  insert into public.reservation_checkout_events (
    hotel_id,
    guest_session_id,
    reservation_id,
    reservation_room_id,
    room_id,
    guest_id,
    invoice_id,
    checked_out_by,
    checked_out_at,
    settlement_snapshot,
    metadata
  ) values (
    target_hotel_id,
    target_guest_session_id,
    session_row.reservation_id,
    session_row.reservation_room_id,
    session_row.room_id,
    session_row.guest_id,
    created_invoice_id,
    actor_id,
    stay_end,
    checkout_snapshot,
    jsonb_build_object(
      'payment_method', settlement_payment_method,
      'transaction_reference', nullif(trim(coalesce(settlement_transaction_reference, '')), '')
    )
  );

  if session_row.reservation_id is not null then
    perform private.write_activity_log(
      target_hotel_id,
      'reservation.room_checkout_completed',
      'reservation',
      session_row.reservation_id,
      format('Room %s checkout completed with invoice %s.', room_row.room_number, created_invoice_number),
      null,
      reservation_snapshot,
      jsonb_build_object(
        'reservation_room_id', session_row.reservation_room_id,
        'guest_session_id', target_guest_session_id,
        'invoice_id', created_invoice_id,
        'housekeeping_task_id', housekeeping_task_id,
        'grand_total', grand_total,
        'amount_collected_at_checkout', amount_to_collect
      )
    );
  end if;

  return jsonb_build_object(
    'success', true,
    'invoice_id', created_invoice_id,
    'invoice_number', created_invoice_number,
    'guest_session_id', target_guest_session_id,
    'reservation_id', session_row.reservation_id,
    'reservation_room_id', session_row.reservation_room_id,
    'room_id', session_row.room_id,
    'room_number', room_row.room_number,
    'housekeeping_task_id', housekeeping_task_id,
    'grand_total', grand_total,
    'previously_paid', previously_paid,
    'amount_collected_at_checkout', amount_to_collect,
    'room_status', 'cleaning',
    'stay_status', 'completed',
    'reservation', reservation_snapshot
  );
end;
$function$;
CREATE OR REPLACE FUNCTION public.checkout_guest_session(target_hotel_id uuid, target_guest_session_id uuid, tax_percent numeric DEFAULT 0, discount_type text DEFAULT 'fixed'::text, discount_value numeric DEFAULT 0, remaining_payment_collected boolean DEFAULT false, settlement_payment_method text DEFAULT 'cash'::text, settlement_transaction_reference text DEFAULT NULL::text, invoice_notes text DEFAULT NULL::text, allow_excess_paid boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  existing_invoice_id uuid;
begin

  perform private.assert_reservation_write_access(
    target_hotel_id
  );


  select inv.id
  into existing_invoice_id
  from public.invoices inv
  where inv.hotel_id = target_hotel_id
    and inv.guest_session_id = target_guest_session_id
  order by inv.created_at
  limit 1;


  if existing_invoice_id is not null then

    return private.day20_checkout_existing_invoice(
      target_hotel_id,
      target_guest_session_id,
      tax_percent,
      discount_type,
      discount_value,
      remaining_payment_collected,
      settlement_payment_method,
      settlement_transaction_reference,
      invoice_notes,
      allow_excess_paid
    );

  end if;


  return public.checkout_guest_session_day20_legacy(
    target_hotel_id,
    target_guest_session_id,
    tax_percent,
    discount_type,
    discount_value,
    remaining_payment_collected,
    settlement_payment_method,
    settlement_transaction_reference,
    invoice_notes,
    allow_excess_paid
  );

end;
$function$;

-- Existing function grants remain exactly as captured; new delegates get least privilege.
do $security$
declare target record;
begin
  for target in select * from (values
    ('public.checkout_guest_session(uuid,uuid,numeric,text,numeric,boolean,text,text,text,boolean)'),
    ('public.checkout_guest_session_day20_legacy(uuid,uuid,numeric,text,numeric,boolean,text,text,text,boolean)'),
    ('private.day20_checkout_existing_invoice(uuid,uuid,numeric,text,numeric,boolean,text,text,text,boolean)'),
    ('private.pilot_prepare_checkout_folio(uuid,uuid,numeric,numeric,numeric,numeric,text)')) as targets(s) loop
    if not exists (select 1 from pilot_checkout_security_snapshot where oid = to_regprocedure(target.s)) then
      execute format('revoke all on function %s from public, anon, authenticated, service_role', target.s);
      if target.s = 'public.checkout_guest_session_day20_legacy(uuid,uuid,numeric,text,numeric,boolean,text,text,text,boolean)' then
        execute format('grant execute on function %s to authenticated, service_role', target.s);
      end if;
    end if;
  end loop;
  if exists (select 1 from pilot_checkout_security_snapshot old join pg_proc p on p.oid=old.oid
    where p.proacl is distinct from old.proacl or p.proowner <> old.proowner
      or p.proconfig is distinct from old.proconfig or p.prosecdef <> old.prosecdef
      or pg_get_expr(p.proargdefaults,0) is distinct from old.defaults) then
    raise exception 'Checkout permissions, ownership, defaults or search path changed; rolling back.';
  end if;
  if has_function_privilege('anon', 'private.pilot_prepare_checkout_folio(uuid,uuid,numeric,numeric,numeric,numeric,text)', 'EXECUTE')
    or has_function_privilege('authenticated', 'private.pilot_prepare_checkout_folio(uuid,uuid,numeric,numeric,numeric,numeric,text)', 'EXECUTE')
    or has_function_privilege('authenticated', 'private.day20_checkout_existing_invoice(uuid,uuid,numeric,text,numeric,boolean,text,text,text,boolean)', 'EXECUTE') then
    raise exception 'Private checkout helpers must not be browser-callable.';
  end if;
end;
$security$;
commit;
