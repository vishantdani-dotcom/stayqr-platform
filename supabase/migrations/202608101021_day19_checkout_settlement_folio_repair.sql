-- ============================================================================
-- StayQR v1.0 — Day 19F P0 repair
-- Prevent checkout settlement payments from being mirrored as new folio charges.
--
-- Root invariant:
--   checkout_settlement is a COLLECTION/settlement event, not a new hotel charge.
--   payment_collections must continue to mirror into folio_collections.
-- ============================================================================

begin;

set local lock_timeout = '10s';
set local statement_timeout = '180s';

select pg_advisory_xact_lock(
  hashtext('stayqr:202608101021:checkout-settlement-folio-repair')
);

do $preflight$
begin
  if to_regprocedure('private.day11_sync_payment(uuid)') is null then
    raise exception 'Day19F repair stopped: private.day11_sync_payment(uuid) is missing.';
  end if;

  if to_regprocedure('private.day11_sync_payment_collection(uuid)') is null then
    raise exception 'Day19F repair stopped: private.day11_sync_payment_collection(uuid) is missing.';
  end if;

  if to_regprocedure('private.day11_payment_sync_trigger()') is null then
    raise exception 'Day19F repair stopped: private.day11_payment_sync_trigger() is missing.';
  end if;

  if to_regprocedure('private.day11_payment_collection_sync_trigger()') is null then
    raise exception 'Day19F repair stopped: private.day11_payment_collection_sync_trigger() is missing.';
  end if;

  -- Do not silently rewrite historical production finance.
  if exists (
    select 1
    from public.folio_items fi
    join public.payments p
      on p.hotel_id = fi.hotel_id
     and p.id = fi.source_id
    where fi.source_table = 'payments'
      and fi.posting_status = 'posted'
      and lower(coalesce(p.payment_type, '')) = 'checkout_settlement'
  ) then
    raise exception
      'Day19F repair stopped: historical posted checkout_settlement folio charge rows exist and require explicit review.';
  end if;
end;
$preflight$;

create or replace function private.day11_payment_sync_trigger()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if tg_op = 'DELETE' then
    update public.folio_items item
    set
      posting_status = 'voided',
      voided_at = coalesce(item.voided_at, now()),
      voided_by = coalesce(item.voided_by, auth.uid()),
      void_reason = coalesce(
        item.void_reason,
        'Legacy payment source row was deleted.'
      ),
      metadata = item.metadata || jsonb_build_object(
        'source_deleted', true,
        'source_deleted_at', now()
      )
    where item.hotel_id = old.hotel_id
      and item.source_table = 'payments'
      and item.source_id = old.id
      and item.posting_status = 'posted';

    update public.folio_collections collection
    set
      status = 'reversed',
      voided_at = coalesce(collection.voided_at, now()),
      voided_by = coalesce(collection.voided_by, auth.uid()),
      void_reason = coalesce(
        collection.void_reason,
        'Legacy payment source row was deleted.'
      ),
      metadata = collection.metadata || jsonb_build_object(
        'source_deleted', true,
        'source_deleted_at', now()
      )
    where collection.hotel_id = old.hotel_id
      and collection.source_table = 'payments'
      and collection.source_id = old.id
      and collection.status = 'posted';

    return old;
  end if;

  -- Day 19F P0:
  -- checkout_settlement is a payment/collection record only.
  -- It must never create a second folio charge for money already represented
  -- by room/food/service/manual folio items.
  if lower(coalesce(new.payment_type, '')) = 'checkout_settlement' then
    update public.folio_items item
    set
      posting_status = 'voided',
      voided_at = coalesce(item.voided_at, now()),
      voided_by = coalesce(item.voided_by, auth.uid()),
      void_reason = coalesce(
        item.void_reason,
        'Checkout settlement is collection-only and must not be a folio charge.'
      ),
      metadata = item.metadata || jsonb_build_object(
        'day19f_checkout_settlement_repair', true,
        'repaired_at', now()
      )
    where item.hotel_id = new.hotel_id
      and item.source_table = 'payments'
      and item.source_id = new.id
      and item.posting_status = 'posted';

    return new;
  end if;

  perform private.day11_sync_payment(new.id);
  return new;
end;
$function$;

create or replace function private.day11_payment_collection_sync_trigger()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  old_payment_type text;
  new_payment_type text;
begin
  if tg_op = 'DELETE' then
    update public.folio_collections collection
    set
      status = 'reversed',
      voided_at = coalesce(collection.voided_at, now()),
      voided_by = coalesce(collection.voided_by, auth.uid()),
      void_reason = coalesce(
        collection.void_reason,
        'Legacy payment_collection source row was deleted.'
      ),
      metadata = collection.metadata || jsonb_build_object(
        'source_deleted', true,
        'source_deleted_at', now()
      )
    where collection.hotel_id = old.hotel_id
      and collection.source_table = 'payment_collections'
      and collection.source_id = old.id
      and collection.status = 'posted';

    select lower(coalesce(p.payment_type, ''))
    into old_payment_type
    from public.payments p
    where p.id = old.payment_id;

    if coalesce(old_payment_type, '') <> 'checkout_settlement' then
      perform private.day11_sync_payment(old.payment_id);
    end if;

    return old;
  end if;

  -- Always mirror the actual money movement into the folio collection ledger.
  perform private.day11_sync_payment_collection(new.id);

  if
    tg_op = 'UPDATE'
    and old.payment_id is distinct from new.payment_id
  then
    select lower(coalesce(p.payment_type, ''))
    into old_payment_type
    from public.payments p
    where p.id = old.payment_id;

    if coalesce(old_payment_type, '') <> 'checkout_settlement' then
      perform private.day11_sync_payment(old.payment_id);
    end if;
  end if;

  select lower(coalesce(p.payment_type, ''))
  into new_payment_type
  from public.payments p
  where p.id = new.payment_id;

  if coalesce(new_payment_type, '') <> 'checkout_settlement' then
    perform private.day11_sync_payment(new.payment_id);
  end if;

  return new;
end;
$function$;

do $verify$
declare
  payment_sync_def text;
  collection_sync_def text;
begin
  select pg_get_functiondef(
    'private.day11_payment_sync_trigger()'::regprocedure
  )
  into payment_sync_def;

  select pg_get_functiondef(
    'private.day11_payment_collection_sync_trigger()'::regprocedure
  )
  into collection_sync_def;

  if payment_sync_def not ilike '%checkout_settlement%' then
    raise exception 'Day19F repair verification failed: payment sync settlement guard missing.';
  end if;

  if collection_sync_def not ilike '%day11_sync_payment_collection(new.id)%' then
    raise exception 'Day19F repair verification failed: collection mirroring was removed.';
  end if;

  if collection_sync_def not ilike '%checkout_settlement%' then
    raise exception 'Day19F repair verification failed: collection trigger settlement guard missing.';
  end if;

  if exists (
    select 1
    from public.folio_items fi
    join public.payments p
      on p.hotel_id = fi.hotel_id
     and p.id = fi.source_id
    where fi.source_table = 'payments'
      and fi.posting_status = 'posted'
      and lower(coalesce(p.payment_type, '')) = 'checkout_settlement'
  ) then
    raise exception 'Day19F repair verification failed: posted settlement-as-charge residue exists.';
  end if;
end;
$verify$;

commit;
