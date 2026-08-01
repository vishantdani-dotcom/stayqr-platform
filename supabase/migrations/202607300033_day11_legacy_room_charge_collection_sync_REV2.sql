-- StayQR v1.0
-- Day 11 Migration 033 REV2
-- Legacy room-charge and collection synchronization
-- REV2 sanitizes legacy actor UUIDs before auth.users foreign keys.
--
-- REQUIRES
-- --------
-- Migration 032 REV2 accepted 50/50.
--
-- AUDIT 054 CONTROLLED TRUTH — VD Stay Inn
-- ----------------------------------------
-- - payments: 40 rows / ₹209,975
-- - paid payments: 37
-- - pending payments: 3 / ₹10,500
-- - payment_collections: 15 rows / ₹150,532
-- - paid payments without collection rows: 23 / ₹48,943
-- - invoices: 25 rows, unchanged by this migration
--
-- THIS MIGRATION
-- --------------
-- 1. Creates/reuses one authoritative folio per guest session.
-- 2. Synchronizes every legacy payments row as one authoritative folio charge.
-- 3. Synchronizes payment_collections one-to-one as immutable collections.
-- 4. Creates compatibility collection evidence only when a legacy payment is
--    already marked paid but has no collection rows.
-- 5. Installs ongoing payment/collection synchronization triggers.
-- 6. Preserves legacy source tables without rewriting them.
--
-- NOT INCLUDED YET
-- ----------------
-- - food_orders and food_order_items;
-- - manual_charges;
-- - service charge catalog/posting;
-- - discounts, refunds or credit-note workflows;
-- - invoice/GST/night-audit work.
--
-- Those remain bounded follow-up Day 11 packages.

begin;

-- ---------------------------------------------------------------------------
-- 0. Preflight
-- ---------------------------------------------------------------------------

do $preflight$
declare
  missing_objects text;
  existing_sync_rows bigint;
begin
  select string_agg(object_name, ', ' order by object_name)
  into missing_objects
  from (
    values
      ('public.folios', to_regclass('public.folios')),
      ('public.folio_items', to_regclass('public.folio_items')),
      ('public.folio_collections', to_regclass('public.folio_collections')),
      ('public.folio_events', to_regclass('public.folio_events'))
  ) as required_object(object_name, relation_id)
  where relation_id is null;

  if missing_objects is not null then
    raise exception
      'Migration 033 requires Migration 032 REV2. Missing: %',
      missing_objects;
  end if;

  if exists (
    select 1
    from public.payments payment
    where payment.amount <= 0
  ) then
    raise exception
      'Migration 033 found a non-positive legacy payment amount.';
  end if;

  if exists (
    select 1
    from public.payment_collections collection
    where collection.amount <= 0
  ) then
    raise exception
      'Migration 033 found a non-positive collection amount.';
  end if;

  -- Payments without guest_session_id are not safe to assign to a folio.
  -- They are skipped by the source adapter rather than blocking every tenant.

  select count(*)
  into existing_sync_rows
  from public.folio_items item
  where item.source_table = 'payments';

  if existing_sync_rows > 0 then
    raise exception
      'Migration 033 source items already exist (% rows). Do not rerun REV1.',
      existing_sync_rows;
  end if;
end;
$preflight$;

-- A payment source must belong to exactly one folio, even if a legacy row is
-- accidentally reassigned later.
create unique index uq_folio_items_global_source
  on public.folio_items(
    hotel_id,
    source_table,
    source_id
  )
  where source_table is not null
    and source_id is not null;

-- ---------------------------------------------------------------------------
-- 1. Source normalization helpers
-- ---------------------------------------------------------------------------

create or replace function private.day11_normalize_payment_method(
  payment_method_value text
)
returns text
language sql
immutable
security invoker
set search_path = ''
as $function$
  select case
    when normalized in ('cash') then 'cash'
    when normalized in (
      'card',
      'credit_card',
      'debit_card',
      'creditcard',
      'debitcard'
    ) then 'card'
    when normalized in ('upi', 'gpay', 'google_pay', 'phonepe', 'paytm')
      then 'upi'
    when normalized in (
      'bank',
      'bank_transfer',
      'banktransfer',
      'net_banking',
      'netbanking',
      'neft',
      'rtgs',
      'imps'
    ) then 'bank_transfer'
    when normalized in (
      'payment_link',
      'paymentlink',
      'cashfree',
      'razorpay',
      'gateway',
      'online'
    ) then 'payment_link'
    else 'other'
  end
  from (
    select lower(
      regexp_replace(
        coalesce(trim(payment_method_value), ''),
        '[^a-zA-Z0-9]+',
        '_',
        'g'
      )
    ) as normalized
  ) source;
$function$;

create or replace function private.day11_payment_charge_category(
  payment_type_value text
)
returns text
language sql
immutable
security invoker
set search_path = ''
as $function$
  select case
    when lower(coalesce(payment_type_value, '')) in (
      'room',
      'room_charge',
      'roomcharge'
    ) then 'room'
    when lower(coalesce(payment_type_value, '')) in (
      'food',
      'food_charge',
      'foodcharge'
    ) then 'food'
    when lower(coalesce(payment_type_value, '')) in (
      'service',
      'service_charge',
      'servicecharge'
    ) then 'service'
    when lower(coalesce(payment_type_value, '')) in (
      'manual',
      'manual_charge',
      'manualcharge'
    ) then 'manual'
    else 'other'
  end;
$function$;


create or replace function private.day11_valid_auth_actor(
  candidate_actor_id uuid
)
returns uuid
language sql
stable
security definer
set search_path = ''
as $function$
  select case
    when candidate_actor_id is null then null::uuid
    when exists (
      select 1
      from auth.users auth_user
      where auth_user.id = candidate_actor_id
    ) then candidate_actor_id
    else null::uuid
  end;
$function$;

revoke all on function private.day11_normalize_payment_method(text)
from public, anon, authenticated;

revoke all on function private.day11_payment_charge_category(text)
from public, anon, authenticated;

revoke all on function private.day11_valid_auth_actor(uuid)
from public, anon, authenticated;

grant execute on function private.day11_normalize_payment_method(text)
to service_role;

grant execute on function private.day11_payment_charge_category(text)
to service_role;

grant execute on function private.day11_valid_auth_actor(uuid)
to service_role;

-- ---------------------------------------------------------------------------
-- 2. Internal folio ensure/reuse without client permission dependence
-- ---------------------------------------------------------------------------

create or replace function private.day11_ensure_folio_for_source(
  target_hotel_id uuid,
  target_guest_session_id uuid,
  source_value text
)
returns public.folios
language plpgsql
security definer
set search_path = ''
as $function$
declare
  folio_row public.folios%rowtype;
  stay_row public.guest_sessions%rowtype;
  hotel_row public.hotels%rowtype;
  generated_id uuid := gen_random_uuid();
begin
  perform pg_advisory_xact_lock(
    hashtextextended(
      'stayqr:day11-source-folio:'
      || target_hotel_id::text
      || ':'
      || target_guest_session_id::text,
      0
    )
  );

  select folio.*
  into folio_row
  from public.folios folio
  where folio.hotel_id = target_hotel_id
    and folio.guest_session_id = target_guest_session_id
  limit 1;

  if folio_row.id is not null then
    return folio_row;
  end if;

  select stay.*
  into stay_row
  from public.guest_sessions stay
  where stay.hotel_id = target_hotel_id
    and stay.id = target_guest_session_id
  for share;

  if not found then
    raise exception
      'Guest session % was not found for hotel %.',
      target_guest_session_id,
      target_hotel_id;
  end if;

  if stay_row.guest_id is null then
    raise exception
      'Guest session % has no guest.',
      target_guest_session_id;
  end if;

  select hotel.*
  into strict hotel_row
  from public.hotels hotel
  where hotel.id = target_hotel_id;

  insert into public.folios (
    id,
    hotel_id,
    folio_number,
    guest_session_id,
    reservation_id,
    reservation_room_id,
    guest_id,
    room_id,
    status,
    currency_code,
    opened_by,
    opened_at,
    metadata
  )
  values (
    generated_id,
    target_hotel_id,
    'FOL-'
      || to_char(
        coalesce(stay_row.checkin_time, now())
          at time zone coalesce(hotel_row.timezone, 'Asia/Kolkata'),
        'YYYYMMDD'
      )
      || '-'
      || upper(substr(replace(generated_id::text, '-', ''), 1, 8)),
    target_guest_session_id,
    stay_row.reservation_id,
    stay_row.reservation_room_id,
    stay_row.guest_id,
    stay_row.room_id,
    'open',
    coalesce(hotel_row.currency_code, 'INR'),
    auth.uid(),
    coalesce(stay_row.checkin_time, now()),
    jsonb_build_object(
      'source', coalesce(source_value, 'legacy_financial_sync'),
      'day', 11,
      'migration', '033',
      'legacy_backfill', true
    )
  )
  returning *
  into folio_row;

  perform private.write_folio_event(
    target_hotel_id,
    folio_row.id,
    'folio.opened',
    'guest_session',
    target_guest_session_id,
    to_jsonb(folio_row),
    jsonb_build_object(
      'source', coalesce(source_value, 'legacy_financial_sync'),
      'migration', '033'
    )
  );

  return folio_row;
end;
$function$;

revoke all on function private.day11_ensure_folio_for_source(
  uuid,
  uuid,
  text
)
from public, anon, authenticated;

grant execute on function private.day11_ensure_folio_for_source(
  uuid,
  uuid,
  text
)
to service_role;

-- ---------------------------------------------------------------------------
-- 3. Synchronize one legacy collection
-- ---------------------------------------------------------------------------

create or replace function private.day11_sync_payment_collection(
  target_collection_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  collection_row public.payment_collections%rowtype;
  payment_row public.payments%rowtype;
  folio_row public.folios%rowtype;
  guest_session_id_value uuid;
  existing_collection_id uuid;
  normalized_method text;
begin
  select collection.*
  into collection_row
  from public.payment_collections collection
  where collection.id = target_collection_id;

  if not found then
    return jsonb_build_object(
      'ok', true,
      'skipped', true,
      'reason', 'collection_not_found',
      'collection_id', target_collection_id
    );
  end if;

  select payment.*
  into strict payment_row
  from public.payments payment
  where payment.hotel_id = collection_row.hotel_id
    and payment.id = collection_row.payment_id;

  guest_session_id_value :=
    coalesce(
      collection_row.guest_session_id,
      payment_row.guest_session_id
    );

  if guest_session_id_value is null then
    return jsonb_build_object(
      'ok', true,
      'skipped', true,
      'reason', 'guest_session_missing',
      'collection_id', target_collection_id
    );
  end if;

  folio_row := private.day11_ensure_folio_for_source(
    collection_row.hotel_id,
    guest_session_id_value,
    'legacy_payment_collection'
  );

  normalized_method :=
    private.day11_normalize_payment_method(
      collection_row.payment_method
    );

  select folio_collection.id
  into existing_collection_id
  from public.folio_collections folio_collection
  where folio_collection.hotel_id = collection_row.hotel_id
    and folio_collection.source_table = 'payment_collections'
    and folio_collection.source_id = collection_row.id
  limit 1;

  if existing_collection_id is null then
    insert into public.folio_collections (
      hotel_id,
      folio_id,
      collection_group_id,
      amount,
      payment_method,
      status,
      transaction_reference,
      source_table,
      source_id,
      idempotency_key,
      collected_at,
      collected_by,
      metadata
    )
    values (
      collection_row.hotel_id,
      folio_row.id,
      collection_row.payment_id,
      collection_row.amount,
      normalized_method,
      'posted',
      collection_row.transaction_reference,
      'payment_collections',
      collection_row.id,
      'legacy-payment-collection:' || collection_row.id::text,
      coalesce(
        collection_row.collected_at,
        collection_row.created_at,
        now()
      ),
      private.day11_valid_auth_actor(
        collection_row.collected_by
      ),
      jsonb_build_object(
        'legacy_collected_by', collection_row.collected_by,
        'legacy_payment_id', collection_row.payment_id,
        'legacy_guest_id', collection_row.guest_id,
        'legacy_room_id', collection_row.room_id,
        'legacy_invoice_id', collection_row.invoice_id,
        'legacy_reservation_id', collection_row.reservation_id,
        'legacy_reservation_payment_id',
          collection_row.reservation_payment_id,
        'source_sync', 'migration_033',
        'legacy_paid_fallback', false
      )
    )
    returning id
    into existing_collection_id;
  else
    update public.folio_collections
    set
      folio_id = folio_row.id,
      collection_group_id = collection_row.payment_id,
      amount = collection_row.amount,
      payment_method = normalized_method,
      status = 'posted',
      transaction_reference = collection_row.transaction_reference,
      collected_at = coalesce(
        collection_row.collected_at,
        collection_row.created_at,
        collected_at
      ),
      collected_by = private.day11_valid_auth_actor(
        collection_row.collected_by
      ),
      voided_at = null,
      voided_by = null,
      void_reason = null,
      metadata = metadata || jsonb_build_object(
        'legacy_collected_by', collection_row.collected_by,
        'legacy_payment_id', collection_row.payment_id,
        'legacy_guest_id', collection_row.guest_id,
        'legacy_room_id', collection_row.room_id,
        'legacy_invoice_id', collection_row.invoice_id,
        'legacy_reservation_id', collection_row.reservation_id,
        'legacy_reservation_payment_id',
          collection_row.reservation_payment_id,
        'source_sync', 'migration_033',
        'legacy_paid_fallback', false
      )
    where hotel_id = collection_row.hotel_id
      and id = existing_collection_id;
  end if;

  -- Real collection history replaces any synthesized paid-payment fallback.
  update public.folio_collections fallback
  set
    status = 'reversed',
    voided_at = coalesce(fallback.voided_at, now()),
    voided_by = coalesce(fallback.voided_by, auth.uid()),
    void_reason = coalesce(
      fallback.void_reason,
      'Replaced by authoritative legacy payment_collection rows.'
    ),
    metadata = fallback.metadata || jsonb_build_object(
      'reversed_by_collection_id', collection_row.id,
      'reversed_by_sync', 'migration_033'
    )
  where fallback.hotel_id = collection_row.hotel_id
    and fallback.source_table = 'payments'
    and fallback.source_id = collection_row.payment_id
    and fallback.status = 'posted'
    and coalesce(
      (fallback.metadata ->> 'legacy_paid_fallback')::boolean,
      false
    );

  return jsonb_build_object(
    'ok', true,
    'skipped', false,
    'collection_id', collection_row.id,
    'folio_collection_id', existing_collection_id,
    'folio_id', folio_row.id,
    'guest_session_id', guest_session_id_value
  );
end;
$function$;

revoke all on function private.day11_sync_payment_collection(uuid)
from public, anon, authenticated;

grant execute on function private.day11_sync_payment_collection(uuid)
to service_role;

-- ---------------------------------------------------------------------------
-- 4. Synchronize one legacy payment/charge
-- ---------------------------------------------------------------------------

create or replace function private.day11_sync_payment(
  target_payment_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  payment_row public.payments%rowtype;
  folio_row public.folios%rowtype;
  existing_item_id uuid;
  existing_fallback_id uuid;
  actual_collection_count integer;
  category_value text;
  normalized_method text;
  collection_record record;
begin
  select payment.*
  into payment_row
  from public.payments payment
  where payment.id = target_payment_id;

  if not found then
    return jsonb_build_object(
      'ok', true,
      'skipped', true,
      'reason', 'payment_not_found',
      'payment_id', target_payment_id
    );
  end if;

  if payment_row.guest_session_id is null then
    return jsonb_build_object(
      'ok', true,
      'skipped', true,
      'reason', 'guest_session_missing',
      'payment_id', target_payment_id
    );
  end if;

  folio_row := private.day11_ensure_folio_for_source(
    payment_row.hotel_id,
    payment_row.guest_session_id,
    'legacy_payment'
  );

  category_value :=
    private.day11_payment_charge_category(payment_row.payment_type);

  normalized_method :=
    private.day11_normalize_payment_method(
      payment_row.payment_method
    );

  select item.id
  into existing_item_id
  from public.folio_items item
  where item.hotel_id = payment_row.hotel_id
    and item.source_table = 'payments'
    and item.source_id = payment_row.id
  limit 1;

  if existing_item_id is null then
    insert into public.folio_items (
      hotel_id,
      folio_id,
      item_kind,
      charge_category,
      description,
      quantity,
      unit_amount,
      amount,
      source_table,
      source_id,
      service_at,
      posting_status,
      posted_at,
      posted_by,
      metadata
    )
    values (
      payment_row.hotel_id,
      folio_row.id,
      'charge',
      category_value,
      coalesce(
        nullif(trim(payment_row.notes), ''),
        nullif(trim(payment_row.payment_notes), ''),
        case
          when category_value = 'room'
          then 'Room charge'
          else initcap(category_value) || ' charge'
        end
      ),
      1,
      payment_row.amount,
      payment_row.amount,
      'payments',
      payment_row.id,
      coalesce(payment_row.created_at, now()),
      'posted',
      coalesce(payment_row.created_at, now()),
      private.day11_valid_auth_actor(
        payment_row.collected_by
      ),
      jsonb_build_object(
        'legacy_collected_by', payment_row.collected_by,
        'legacy_payment_type', payment_row.payment_type,
        'legacy_payment_status', payment_row.payment_status,
        'legacy_payment_method', payment_row.payment_method,
        'legacy_invoice_id', payment_row.invoice_id,
        'legacy_reservation_id', payment_row.reservation_id,
        'legacy_reservation_room_id',
          payment_row.reservation_room_id,
        'source_sync', 'migration_033'
      )
    )
    returning id
    into existing_item_id;
  else
    update public.folio_items
    set
      folio_id = folio_row.id,
      charge_category = category_value,
      description = coalesce(
        nullif(trim(payment_row.notes), ''),
        nullif(trim(payment_row.payment_notes), ''),
        case
          when category_value = 'room'
          then 'Room charge'
          else initcap(category_value) || ' charge'
        end
      ),
      quantity = 1,
      unit_amount = payment_row.amount,
      amount = payment_row.amount,
      service_at = coalesce(payment_row.created_at, service_at),
      posting_status = 'posted',
      voided_at = null,
      voided_by = null,
      void_reason = null,
      metadata = metadata || jsonb_build_object(
        'legacy_collected_by', payment_row.collected_by,
        'legacy_payment_type', payment_row.payment_type,
        'legacy_payment_status', payment_row.payment_status,
        'legacy_payment_method', payment_row.payment_method,
        'legacy_invoice_id', payment_row.invoice_id,
        'legacy_reservation_id', payment_row.reservation_id,
        'legacy_reservation_room_id',
          payment_row.reservation_room_id,
        'source_sync', 'migration_033'
      )
    where hotel_id = payment_row.hotel_id
      and id = existing_item_id;
  end if;

  actual_collection_count := 0;

  for collection_record in
    select collection.id
    from public.payment_collections collection
    where collection.hotel_id = payment_row.hotel_id
      and collection.payment_id = payment_row.id
    order by collection.collected_at, collection.created_at, collection.id
  loop
    actual_collection_count := actual_collection_count + 1;
    perform private.day11_sync_payment_collection(
      collection_record.id
    );
  end loop;

  select collection.id
  into existing_fallback_id
  from public.folio_collections collection
  where collection.hotel_id = payment_row.hotel_id
    and collection.source_table = 'payments'
    and collection.source_id = payment_row.id
  limit 1;

  if
    lower(coalesce(payment_row.payment_status, 'pending')) = 'paid'
    and actual_collection_count = 0
  then
    if existing_fallback_id is null then
      insert into public.folio_collections (
        hotel_id,
        folio_id,
        collection_group_id,
        amount,
        payment_method,
        status,
        transaction_reference,
        provider,
        provider_payment_id,
        source_table,
        source_id,
        idempotency_key,
        collected_at,
        collected_by,
        metadata
      )
      values (
        payment_row.hotel_id,
        folio_row.id,
        payment_row.id,
        payment_row.amount,
        normalized_method,
        'posted',
        payment_row.transaction_reference,
        case
          when payment_row.razorpay_payment_id is not null
          then 'razorpay'
          else null
        end,
        payment_row.razorpay_payment_id,
        'payments',
        payment_row.id,
        'legacy-paid-payment:' || payment_row.id::text,
        coalesce(
          payment_row.paid_at,
          payment_row.created_at,
          now()
        ),
        private.day11_valid_auth_actor(
          payment_row.collected_by
        ),
        jsonb_build_object(
          'legacy_collected_by', payment_row.collected_by,
          'legacy_paid_fallback', true,
          'compatibility_reason',
            'Legacy payment is marked paid without payment_collection history.',
          'legacy_payment_status', payment_row.payment_status,
          'legacy_invoice_id', payment_row.invoice_id,
          'source_sync', 'migration_033'
        )
      )
      returning id
      into existing_fallback_id;
    else
      update public.folio_collections
      set
        folio_id = folio_row.id,
        collection_group_id = payment_row.id,
        amount = payment_row.amount,
        payment_method = normalized_method,
        status = 'posted',
        transaction_reference = payment_row.transaction_reference,
        provider = case
          when payment_row.razorpay_payment_id is not null
          then 'razorpay'
          else provider
        end,
        provider_payment_id = coalesce(
          payment_row.razorpay_payment_id,
          provider_payment_id
        ),
        collected_at = coalesce(
          payment_row.paid_at,
          payment_row.created_at,
          collected_at
        ),
        collected_by = private.day11_valid_auth_actor(
          payment_row.collected_by
        ),
        voided_at = null,
        voided_by = null,
        void_reason = null,
        metadata = metadata || jsonb_build_object(
          'legacy_collected_by', payment_row.collected_by,
          'legacy_paid_fallback', true,
          'compatibility_reason',
            'Legacy payment is marked paid without payment_collection history.',
          'legacy_payment_status', payment_row.payment_status,
          'legacy_invoice_id', payment_row.invoice_id,
          'source_sync', 'migration_033'
        )
      where hotel_id = payment_row.hotel_id
        and id = existing_fallback_id;
    end if;
  elsif existing_fallback_id is not null then
    update public.folio_collections
    set
      status = 'reversed',
      voided_at = coalesce(voided_at, now()),
      voided_by = coalesce(voided_by, auth.uid()),
      void_reason = coalesce(
        void_reason,
        case
          when actual_collection_count > 0
          then 'Replaced by authoritative payment_collection history.'
          else 'Legacy payment is no longer marked paid.'
        end
      ),
      metadata = metadata || jsonb_build_object(
        'reversed_by_sync', 'migration_033',
        'actual_collection_count', actual_collection_count,
        'legacy_payment_status', payment_row.payment_status
      )
    where hotel_id = payment_row.hotel_id
      and id = existing_fallback_id
      and status = 'posted';
  end if;

  return jsonb_build_object(
    'ok', true,
    'skipped', false,
    'payment_id', payment_row.id,
    'folio_id', folio_row.id,
    'folio_item_id', existing_item_id,
    'actual_collection_count', actual_collection_count,
    'fallback_collection_id', existing_fallback_id
  );
end;
$function$;

revoke all on function private.day11_sync_payment(uuid)
from public, anon, authenticated;

grant execute on function private.day11_sync_payment(uuid)
to service_role;

-- ---------------------------------------------------------------------------
-- 5. Ongoing legacy-source trigger synchronization
-- ---------------------------------------------------------------------------

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

    perform private.day11_sync_payment(old.payment_id);
    return old;
  end if;

  perform private.day11_sync_payment_collection(new.id);

  if
    tg_op = 'UPDATE'
    and old.payment_id is distinct from new.payment_id
  then
    perform private.day11_sync_payment(old.payment_id);
  end if;

  perform private.day11_sync_payment(new.payment_id);
  return new;
end;
$function$;

drop trigger if exists payments_day11_folio_sync
on public.payments;

create trigger payments_day11_folio_sync
after insert or update or delete
on public.payments
for each row
execute function private.day11_payment_sync_trigger();

drop trigger if exists payment_collections_day11_folio_sync
on public.payment_collections;

create trigger payment_collections_day11_folio_sync
after insert or update or delete
on public.payment_collections
for each row
execute function private.day11_payment_collection_sync_trigger();

-- ---------------------------------------------------------------------------
-- 6. Authorized reconciliation RPC
-- ---------------------------------------------------------------------------

create or replace function public.reconcile_legacy_payment_folios(
  target_hotel_id uuid,
  request_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  payment_record record;
  payment_count integer := 0;
  folio_count integer;
  item_count integer;
  collection_count integer;
  result_value jsonb;
begin
  if not private.user_has_any_permission(
    target_hotel_id,
    array[
      'payments.manage',
      'invoices.manage',
      'checkout.manage'
    ]::text[]
  ) then
    raise exception 'Legacy financial reconciliation access denied.';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      'stayqr:day11-reconcile:'
      || target_hotel_id::text,
      0
    )
  );

  for payment_record in
    select payment.id
    from public.payments payment
    where payment.hotel_id = target_hotel_id
      and payment.guest_session_id is not null
    order by payment.created_at, payment.id
  loop
    perform private.day11_sync_payment(payment_record.id);
    payment_count := payment_count + 1;
  end loop;

  select count(*)
  into folio_count
  from public.folios folio
  where folio.hotel_id = target_hotel_id
    and exists (
      select 1
      from public.payments payment
      where payment.hotel_id = target_hotel_id
        and payment.guest_session_id = folio.guest_session_id
    );

  select count(*)
  into item_count
  from public.folio_items item
  where item.hotel_id = target_hotel_id
    and item.source_table = 'payments';

  select count(*)
  into collection_count
  from public.folio_collections collection
  where collection.hotel_id = target_hotel_id
    and collection.source_table in (
      'payments',
      'payment_collections'
    );

  result_value := jsonb_build_object(
    'ok', true,
    'hotel_id', target_hotel_id,
    'request_id', coalesce(
      nullif(trim(request_id), ''),
      gen_random_uuid()::text
    ),
    'payments_processed', payment_count,
    'folios', folio_count,
    'folio_items', item_count,
    'folio_collections', collection_count,
    'source_sync', 'migration_033'
  );

  return result_value;
end;
$function$;

revoke all on function public.reconcile_legacy_payment_folios(
  uuid,
  text
)
from public, anon;

grant execute on function public.reconcile_legacy_payment_folios(
  uuid,
  text
)
to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 7. Initial backfill — all existing linked legacy payment rows
-- ---------------------------------------------------------------------------

do $backfill$
declare
  payment_record record;
begin
  for payment_record in
    select payment.id
    from public.payments payment
    where payment.guest_session_id is not null
    order by payment.hotel_id, payment.created_at, payment.id
  loop
    perform private.day11_sync_payment(payment_record.id);
  end loop;

  -- A second complete pass proves source uniqueness/idempotent reconciliation
  -- without adding any duplicate folio, item or collection row.
  for payment_record in
    select payment.id
    from public.payments payment
    where payment.guest_session_id is not null
    order by payment.hotel_id, payment.created_at, payment.id
  loop
    perform private.day11_sync_payment(payment_record.id);
  end loop;
end;
$backfill$;

-- ---------------------------------------------------------------------------
-- 8. Documentation
-- ---------------------------------------------------------------------------

comment on function private.day11_valid_auth_actor(uuid) is
'Returns a candidate legacy actor only when it still exists in auth.users; stale UUIDs become NULL in constrained actor columns and remain preserved in source metadata.';

comment on function private.day11_sync_payment(uuid) is
'Synchronizes one legacy payments charge into an authoritative folio and preserves legacy paid state with compatibility collection evidence when collection history is absent.';

comment on function private.day11_sync_payment_collection(uuid) is
'Synchronizes one payment_collections row one-to-one and reverses any synthesized paid-payment fallback for the same payment.';

comment on function public.reconcile_legacy_payment_folios(uuid, text) is
'Authorized idempotent reconciliation of all linked legacy payment and collection sources for one hotel.';

comment on index public.uq_folio_items_global_source is
'Guarantees a legacy charge source belongs to exactly one authoritative folio.';

commit;
