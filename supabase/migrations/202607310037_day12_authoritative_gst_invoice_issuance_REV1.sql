-- ============================================================================
-- StayQR v1.0
-- Day 12 Migration 037 REV1
-- Authoritative GST invoice preview and issuance
--
-- REQUIRES
-- --------
-- Migration 036 accepted 70/70.
--
-- THIS MIGRATION
-- --------------
-- 1. Adds explicit GST identity, place-of-supply, tax-source and
--    idempotency fields.
-- 2. Adds a deterministic folio invoice preview engine.
-- 3. Adds an RPC-only final invoice issuance workflow.
-- 4. Allocates an Indian financial-year invoice number exactly once.
-- 5. Applies explicit hotel tax rates per charge category.
-- 6. Allocates approved folio discount proportionally across charge lines.
-- 7. Posts one authoritative tax item to the folio.
-- 8. Produces immutable invoice lines, snapshot, SHA-256 hash and QR token.
-- 9. Rejects duplicate final invoices and duplicate request IDs.
--
-- SAFETY
-- ------
-- - Installs contracts only.
-- - Creates no tax rate.
-- - Issues no real invoice during migration.
-- - Changes no Day 11 folio total.
-- - Existing 25 legacy invoices and 16 legacy items remain unchanged.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 0. Preflight
-- ---------------------------------------------------------------------------

do $preflight$
declare
  missing_objects text;
  conflicting_columns text;
begin
  select string_agg(object_name, ', ' order by object_name)
  into missing_objects
  from (
    values
      (
        'public.tax_rates',
        to_regclass('public.tax_rates') is not null
      ),
      (
        'public.invoice_verifications',
        to_regclass('public.invoice_verifications') is not null
      ),
      (
        'public.invoice_events',
        to_regclass('public.invoice_events') is not null
      ),
      (
        'private.day12_next_invoice_number(uuid,timestamptz)',
        to_regprocedure(
          'private.day12_next_invoice_number(uuid,timestamp with time zone)'
        ) is not null
      ),
      (
        'private.day12_build_invoice_snapshot(uuid,uuid,timestamptz,uuid)',
        to_regprocedure(
          'private.day12_build_invoice_snapshot(uuid,uuid,timestamp with time zone,uuid)'
        ) is not null
      ),
      (
        'private.day11_require_current_actor()',
        to_regprocedure(
          'private.day11_require_current_actor()'
        ) is not null
      ),
      (
        'private.recalculate_folio(uuid,uuid)',
        to_regprocedure(
          'private.recalculate_folio(uuid,uuid)'
        ) is not null
      )
  ) required(object_name, object_exists)
  where not object_exists;

  if missing_objects is not null then
    raise exception
      'Migration 037 prerequisites are missing: %',
      missing_objects;
  end if;

  select string_agg(
    column_record.table_name || '.' || column_record.column_name,
    ', '
    order by column_record.table_name, column_record.column_name
  )
  into conflicting_columns
  from information_schema.columns column_record
  where column_record.table_schema = 'public'
    and (
      (
        column_record.table_name = 'invoices'
        and column_record.column_name in (
          'idempotency_key',
          'tax_folio_item_id',
          'seller_gstin',
          'buyer_gstin',
          'place_of_supply',
          'place_of_supply_code',
          'other_amount'
        )
      )
      or (
        column_record.table_name = 'invoice_items'
        and column_record.column_name =
          'tax_rate_id'
      )
    );

  if conflicting_columns is not null then
    raise exception
      'Migration 037 target columns already exist: %',
      conflicting_columns;
  end if;

  if to_regprocedure(
    'public.preview_folio_invoice(uuid,uuid,text,date)'
  ) is not null
     or to_regprocedure(
       'public.issue_folio_invoice(uuid,uuid,text,date,text)'
     ) is not null
  then
    raise exception
      'Migration 037 RPCs already exist. Do not rerun REV1.';
  end if;

  if (
    select count(*)
    from public.invoices
    where hotel_id =
      '77d850d0-016d-4155-bc44-a6207d30e7b9'::uuid
  ) <> 25 then
    raise exception
      'Controlled invoice source changed after Migration 036.';
  end if;

  if (
    select count(*)
    from public.invoices
    where hotel_id =
      '77d850d0-016d-4155-bc44-a6207d30e7b9'::uuid
      and finalized_at is not null
  ) <> 7 then
    raise exception
      'Controlled finalized invoice count changed after Migration 036.';
  end if;
end;
$preflight$;

-- ---------------------------------------------------------------------------
-- 1. Explicit authoritative invoice fields
-- ---------------------------------------------------------------------------

alter table public.invoices
  add column idempotency_key text,
  add column tax_folio_item_id uuid,
  add column seller_gstin text,
  add column buyer_gstin text,
  add column place_of_supply text,
  add column place_of_supply_code text,
  add column other_amount numeric(14,2) not null default 0;

alter table public.invoices
  add constraint invoices_tax_folio_item_fkey
    foreign key (tax_folio_item_id)
    references public.folio_items(id)
    on delete restrict,

  add constraint invoices_idempotency_key_check
    check (
      idempotency_key is null
      or length(trim(idempotency_key))
        between 8 and 200
    ),

  add constraint invoices_gstin_format_check
    check (
      (
        seller_gstin is null
        or seller_gstin ~
          '^[0-9]{2}[A-Z0-9]{13}$'
      )
      and (
        buyer_gstin is null
        or buyer_gstin ~
          '^[0-9]{2}[A-Z0-9]{13}$'
      )
    ),

  add constraint invoices_place_of_supply_code_check
    check (
      place_of_supply_code is null
      or place_of_supply_code ~
        '^[0-9]{2}$'
    );

create unique index uq_authoritative_invoice_idempotency
  on public.invoices(
    hotel_id,
    idempotency_key
  )
  where invoice_origin = 'authoritative'
    and idempotency_key is not null;

create unique index uq_invoice_tax_folio_item
  on public.invoices(
    hotel_id,
    tax_folio_item_id
  )
  where tax_folio_item_id is not null;

alter table public.invoice_items
  add column tax_rate_id uuid;

alter table public.invoice_items
  add constraint invoice_items_tax_rate_fkey
    foreign key (tax_rate_id)
    references public.tax_rates(id)
    on delete restrict;

create index idx_invoice_items_tax_rate
  on public.invoice_items(
    hotel_id,
    tax_rate_id
  )
  where tax_rate_id is not null;

-- ---------------------------------------------------------------------------
-- 2. Private preview engine
-- ---------------------------------------------------------------------------

create or replace function private.day12_preview_folio_invoice(
  target_hotel_id uuid,
  target_folio_id uuid,
  supply_mode_value text,
  invoice_date_value date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  folio_row public.folios%rowtype;
  hotel_row public.hotels%rowtype;
  stay_row public.guest_sessions%rowtype;
  guest_snapshot_value jsonb;
  settings_snapshot_value jsonb;

  source_record record;

  charge_count integer;
  current_line integer := 0;

  gross_charges_value numeric(14,2);
  discount_value numeric(14,2);
  allocated_discount_value numeric(14,2) := 0;
  line_discount_value numeric(14,2);
  line_taxable_value numeric(14,2);

  base_tax_value numeric(14,2);
  cgst_value numeric(14,2);
  sgst_value numeric(14,2);
  igst_value numeric(14,2);
  cess_value numeric(14,2);
  line_total_value numeric(14,2);

  room_amount_value numeric(14,2) := 0;
  food_amount_value numeric(14,2) := 0;
  service_amount_value numeric(14,2) := 0;
  manual_amount_value numeric(14,2) := 0;
  other_amount_value numeric(14,2) := 0;

  taxable_total_value numeric(14,2) := 0;
  cgst_total_value numeric(14,2) := 0;
  sgst_total_value numeric(14,2) := 0;
  igst_total_value numeric(14,2) := 0;
  cess_total_value numeric(14,2) := 0;
  tax_total_value numeric(14,2) := 0;
  invoice_total_value numeric(14,2) := 0;

  net_collection_value numeric(14,2);
  paid_value numeric(14,2);
  pending_value numeric(14,2);

  selected_rate_count integer;
  selected_rate_id uuid;
  selected_rate_percent numeric(7,4);
  selected_cess_percent numeric(7,4);
  selected_hsn_sac_code text;

  lines_value jsonb := '[]'::jsonb;
  tax_breakup_value jsonb := '{}'::jsonb;

  seller_gstin_value text;
  buyer_gstin_value text;
  seller_state_value text;
  buyer_state_value text;
  seller_state_code_value text;
  buyer_state_code_value text;
begin
  if supply_mode_value not in (
    'exempt',
    'intra_state',
    'inter_state'
  ) then
    raise exception
      'Supply mode must be exempt, intra_state or inter_state.';
  end if;

  if invoice_date_value is null then
    raise exception 'Invoice date is required.';
  end if;

  select folio.*
  into folio_row
  from public.folios folio
  where folio.hotel_id = target_hotel_id
    and folio.id = target_folio_id;

  if not found then
    raise exception 'Folio was not found.';
  end if;

  if folio_row.status = 'voided' then
    raise exception 'A voided folio cannot be invoiced.';
  end if;

  if folio_row.charges_amount <= 0 then
    raise exception 'Folio has no posted charge.';
  end if;

  if folio_row.credit_amount > 0
     or folio_row.refund_amount > 0
  then
    raise exception
      'Final invoice must precede credit-note or refund activity.';
  end if;

  if exists (
    select 1
    from public.invoices invoice
    where invoice.hotel_id = target_hotel_id
      and invoice.folio_id = target_folio_id
      and invoice.invoice_origin =
        'authoritative'
      and invoice.finalized_at is not null
  ) then
    raise exception
      'A final authoritative invoice already exists for this folio.';
  end if;

  select hotel.*
  into hotel_row
  from public.hotels hotel
  where hotel.id = target_hotel_id;

  if not found then
    raise exception 'Hotel was not found.';
  end if;

  select stay.*
  into stay_row
  from public.guest_sessions stay
  where stay.hotel_id = target_hotel_id
    and stay.id = folio_row.guest_session_id;

  if not found then
    raise exception 'Guest session was not found.';
  end if;

  select coalesce(
    (
      select to_jsonb(setting)
      from public.hotel_settings setting
      where setting.hotel_id = target_hotel_id
    ),
    '{}'::jsonb
  )
  into settings_snapshot_value;

  select coalesce(
    (
      select to_jsonb(guest)
      from public.guests guest
      where guest.hotel_id = target_hotel_id
        and guest.id = folio_row.guest_id
    ),
    '{}'::jsonb
  )
  into guest_snapshot_value;

  seller_gstin_value :=
    upper(
      nullif(
        regexp_replace(
          coalesce(
            hotel_row.gst_number,
            settings_snapshot_value
              ->> 'tax_registration_number',
            ''
          ),
          '\s+',
          '',
          'g'
        ),
        ''
      )
    );

  buyer_gstin_value :=
    upper(
      nullif(
        regexp_replace(
          coalesce(
            guest_snapshot_value ->> 'gst_number',
            guest_snapshot_value ->> 'gstin',
            ''
          ),
          '\s+',
          '',
          'g'
        ),
        ''
      )
    );

  seller_state_value :=
    nullif(trim(hotel_row.state), '');

  seller_state_code_value :=
    case
      when seller_gstin_value is not null
        then left(seller_gstin_value, 2)
      else null
    end;

  buyer_state_value :=
    coalesce(
      nullif(
        trim(
          guest_snapshot_value ->> 'state'
        ),
        ''
      ),
      seller_state_value
    );

  buyer_state_code_value :=
    case
      when buyer_gstin_value is not null
        then left(buyer_gstin_value, 2)
      when supply_mode_value = 'intra_state'
        then seller_state_code_value
      else null
    end;

  if seller_gstin_value is not null
     and seller_gstin_value !~
       '^[0-9]{2}[A-Z0-9]{13}$'
  then
    raise exception 'Hotel GSTIN format is invalid.';
  end if;

  if buyer_gstin_value is not null
     and buyer_gstin_value !~
       '^[0-9]{2}[A-Z0-9]{13}$'
  then
    raise exception 'Buyer GSTIN format is invalid.';
  end if;

  select
    count(*),
    coalesce(sum(item.amount), 0)
  into
    charge_count,
    gross_charges_value
  from public.folio_items item
  where item.hotel_id = target_hotel_id
    and item.folio_id = target_folio_id
    and item.posting_status = 'posted'
    and item.item_kind = 'charge';

  if charge_count = 0
     or gross_charges_value <= 0
  then
    raise exception
      'No posted charge items are available.';
  end if;

  discount_value := folio_row.discount_amount;

  if discount_value > gross_charges_value then
    raise exception
      'Folio discount exceeds posted charges.';
  end if;

  for source_record in
    select
      item.id,
      item.charge_category,
      item.description,
      item.quantity,
      item.unit_amount,
      item.amount,
      item.service_at,
      item.metadata,
      row_number() over (
        order by item.service_at,
                 item.created_at,
                 item.id
      )::integer as line_number
    from public.folio_items item
    where item.hotel_id = target_hotel_id
      and item.folio_id = target_folio_id
      and item.posting_status = 'posted'
      and item.item_kind = 'charge'
    order by item.service_at,
             item.created_at,
             item.id
  loop
    current_line := current_line + 1;

    if current_line = charge_count then
      line_discount_value :=
        discount_value
        - allocated_discount_value;
    else
      line_discount_value :=
        round(
          discount_value
          * source_record.amount
          / gross_charges_value,
          2
        );

      allocated_discount_value :=
        allocated_discount_value
        + line_discount_value;
    end if;

    line_taxable_value :=
      greatest(
        source_record.amount
        - line_discount_value,
        0
      );

    selected_rate_id := null;
    selected_rate_count := 0;
    selected_rate_percent := 0;
    selected_cess_percent := 0;
    selected_hsn_sac_code := null;
    base_tax_value := 0;
    cgst_value := 0;
    sgst_value := 0;
    igst_value := 0;
    cess_value := 0;

    if supply_mode_value <> 'exempt' then
      select
        count(*),
        (
          min(tax_rate.id::text)
        )::uuid
      into
        selected_rate_count,
        selected_rate_id
      from public.tax_rates tax_rate
      where tax_rate.hotel_id =
            target_hotel_id
        and tax_rate.charge_category =
            coalesce(
              source_record.charge_category,
              'other'
            )
        and tax_rate.is_active
        and invoice_date_value >=
            tax_rate.valid_from
        and (
          tax_rate.valid_to is null
          or invoice_date_value <=
             tax_rate.valid_to
        );

      if selected_rate_count <> 1 then
        raise exception
          'Exactly one active tax rate is required for category %. Found %.',
          coalesce(
            source_record.charge_category,
            'other'
          ),
          selected_rate_count;
      end if;

      select
        tax_rate.rate_percent,
        tax_rate.cess_percent,
        tax_rate.hsn_sac_code
      into
        selected_rate_percent,
        selected_cess_percent,
        selected_hsn_sac_code
      from public.tax_rates tax_rate
      where tax_rate.hotel_id =
            target_hotel_id
        and tax_rate.id =
            selected_rate_id;

      base_tax_value :=
        round(
          line_taxable_value
          * selected_rate_percent
          / 100,
          2
        );

      cess_value :=
        round(
          line_taxable_value
          * selected_cess_percent
          / 100,
          2
        );

      if supply_mode_value = 'intra_state' then
        cgst_value :=
          round(base_tax_value / 2, 2);

        sgst_value :=
          base_tax_value - cgst_value;
      else
        igst_value := base_tax_value;
      end if;
    end if;

    line_total_value :=
      line_taxable_value
      + cgst_value
      + sgst_value
      + igst_value
      + cess_value;

    taxable_total_value :=
      taxable_total_value
      + line_taxable_value;

    cgst_total_value :=
      cgst_total_value + cgst_value;

    sgst_total_value :=
      sgst_total_value + sgst_value;

    igst_total_value :=
      igst_total_value + igst_value;

    cess_total_value :=
      cess_total_value + cess_value;

    case coalesce(
      source_record.charge_category,
      'other'
    )
      when 'room' then
        room_amount_value :=
          room_amount_value
          + source_record.amount;
      when 'food' then
        food_amount_value :=
          food_amount_value
          + source_record.amount;
      when 'service' then
        service_amount_value :=
          service_amount_value
          + source_record.amount;
      when 'manual' then
        manual_amount_value :=
          manual_amount_value
          + source_record.amount;
      else
        other_amount_value :=
          other_amount_value
          + source_record.amount;
    end case;

    lines_value :=
      lines_value
      || jsonb_build_array(
        jsonb_build_object(
          'line_number',
            source_record.line_number,
          'folio_item_id',
            source_record.id,
          'item_type',
            case
              when source_record.charge_category =
                   'manual'
                then 'manual_charge'
              when source_record.charge_category in (
                'room',
                'food',
                'service'
              )
                then source_record.charge_category
              else 'other'
            end,
          'charge_category',
            coalesce(
              source_record.charge_category,
              'other'
            ),
          'description',
            source_record.description,
          'quantity',
            source_record.quantity,
          'unit_price',
            source_record.unit_amount,
          'gross_amount',
            source_record.amount,
          'discount_amount',
            line_discount_value,
          'taxable_amount',
            line_taxable_value,
          'tax_rate_id',
            selected_rate_id,
          'tax_rate_percent',
            coalesce(
              selected_rate_percent,
              0
            ),
          'cess_rate_percent',
            coalesce(
              selected_cess_percent,
              0
            ),
          'hsn_sac_code',
            selected_hsn_sac_code,
          'cgst_amount',
            cgst_value,
          'sgst_amount',
            sgst_value,
          'igst_amount',
            igst_value,
          'cess_amount',
            cess_value,
          'line_total',
            line_total_value,
          'service_at',
            source_record.service_at,
          'source_metadata',
            source_record.metadata
        )
      );
  end loop;

  tax_total_value :=
    cgst_total_value
    + sgst_total_value
    + igst_total_value
    + cess_total_value;

  invoice_total_value :=
    taxable_total_value
    + tax_total_value;

  net_collection_value :=
    greatest(
      folio_row.collection_amount
      - folio_row.refund_amount,
      0
    );

  paid_value :=
    least(
      net_collection_value,
      invoice_total_value
    );

  pending_value :=
    greatest(
      invoice_total_value
      - paid_value,
      0
    );

  tax_breakup_value :=
    jsonb_build_object(
      'taxable_amount',
        taxable_total_value,
      'cgst_amount',
        cgst_total_value,
      'sgst_amount',
        sgst_total_value,
      'igst_amount',
        igst_total_value,
      'cess_amount',
        cess_total_value,
      'tax_amount',
        tax_total_value
    );

  return jsonb_build_object(
    'hotel_id', target_hotel_id,
    'folio_id', target_folio_id,
    'guest_session_id',
      folio_row.guest_session_id,
    'guest_id', folio_row.guest_id,
    'room_id', folio_row.room_id,
    'invoice_date', invoice_date_value,
    'supply_mode', supply_mode_value,
    'currency_code', folio_row.currency_code,
    'seller_gstin', seller_gstin_value,
    'buyer_gstin', buyer_gstin_value,
    'place_of_supply', buyer_state_value,
    'place_of_supply_code',
      buyer_state_code_value,
    'seller_state', seller_state_value,
    'seller_state_code',
      seller_state_code_value,
    'gross_charges', gross_charges_value,
    'discount_amount', discount_value,
    'room_amount', room_amount_value,
    'food_amount', food_amount_value,
    'service_amount', service_amount_value,
    'manual_amount', manual_amount_value,
    'other_amount', other_amount_value,
    'taxable_amount', taxable_total_value,
    'tax_breakup', tax_breakup_value,
    'invoice_total', invoice_total_value,
    'net_collection', net_collection_value,
    'paid_amount', paid_value,
    'pending_amount', pending_value,
    'payment_status',
      case
        when pending_value = 0
          then 'paid'
        when paid_value > 0
          then 'partially_paid'
        else 'pending'
      end,
    'invoice_status',
      case
        when pending_value = 0
          then 'paid'
        when paid_value > 0
          then 'partially_paid'
        else 'issued'
      end,
    'checkin_time', stay_row.checkin_time,
    'checkout_time',
      coalesce(
        stay_row.extended_until,
        stay_row.checkout_time
      ),
    'stay_hours',
      greatest(
        ceil(
          extract(
            epoch from (
              coalesce(
                stay_row.extended_until,
                stay_row.checkout_time
              )
              - stay_row.checkin_time
            )
          ) / 3600
        )::integer,
        0
      ),
    'stay_nights',
      greatest(
        ceil(
          extract(
            epoch from (
              coalesce(
                stay_row.extended_until,
                stay_row.checkout_time
              )
              - stay_row.checkin_time
            )
          ) / 86400
        )::integer,
        0
      ),
    'seller_snapshot',
      to_jsonb(hotel_row)
      || jsonb_build_object(
        'settings',
          settings_snapshot_value
      ),
    'buyer_snapshot',
      guest_snapshot_value,
    'lines', lines_value
  );
end;
$function$;

-- ---------------------------------------------------------------------------
-- 3. Authorized preview RPC
-- ---------------------------------------------------------------------------

create or replace function public.preview_folio_invoice(
  target_hotel_id uuid,
  target_folio_id uuid,
  supply_mode_value text,
  invoice_date_value date default current_date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  if not private.user_has_any_permission(
    target_hotel_id,
    array[
      'invoices.view',
      'invoices.manage',
      'checkout.manage'
    ]::text[]
  ) then
    raise exception 'Invoice preview access denied.';
  end if;

  return private.day12_preview_folio_invoice(
    target_hotel_id,
    target_folio_id,
    supply_mode_value,
    invoice_date_value
  );
end;
$function$;

-- ---------------------------------------------------------------------------
-- 4. Authorized final invoice issuance
-- ---------------------------------------------------------------------------

create or replace function public.issue_folio_invoice(
  target_hotel_id uuid,
  target_folio_id uuid,
  supply_mode_value text,
  invoice_date_value date,
  request_id_value text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  actor_id_value uuid;
  normalized_request_id text;

  folio_row public.folios%rowtype;
  preview_value jsonb;
  number_value jsonb;
  invoice_row public.invoices%rowtype;
  existing_invoice public.invoices%rowtype;

  line_record record;
  line_snapshot jsonb;

  invoice_id_value uuid := gen_random_uuid();
  verification_token_value uuid := gen_random_uuid();
  finalized_at_value timestamptz := now();

  tax_item_id_value uuid;
  tax_total_value numeric(14,2);

  snapshot_value jsonb;
  snapshot_hash_value text;

  invoice_status_value text;
  payment_status_value text;
begin
  actor_id_value :=
    private.day11_require_current_actor();

  normalized_request_id :=
    nullif(trim(request_id_value), '');

  if normalized_request_id is null
     or length(normalized_request_id) < 8
  then
    raise exception
      'A request ID of at least eight characters is required.';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      'stayqr:issue-folio-invoice:'
      || target_hotel_id::text
      || ':'
      || target_folio_id::text,
      0
    )
  );

  select invoice.*
  into existing_invoice
  from public.invoices invoice
  where invoice.hotel_id = target_hotel_id
    and invoice.invoice_origin =
      'authoritative'
    and invoice.idempotency_key =
      normalized_request_id
  limit 1;

  if existing_invoice.id is not null then
    if existing_invoice.folio_id <>
       target_folio_id
    then
      raise exception
        'Request ID is already used for another folio.';
    end if;

    return jsonb_build_object(
      'ok', true,
      'idempotent', true,
      'invoice_id', existing_invoice.id,
      'invoice_number',
        existing_invoice.invoice_number,
      'verification_token',
        existing_invoice.verification_token,
      'snapshot_hash',
        existing_invoice.snapshot_hash,
      'tax_amount',
        existing_invoice.tax_amount,
      'total_amount',
        existing_invoice.total_amount,
      'pending_amount',
        existing_invoice.pending_amount,
      'invoice_status',
        existing_invoice.invoice_status
    );
  end if;

  select folio.*
  into folio_row
  from public.folios folio
  where folio.hotel_id = target_hotel_id
    and folio.id = target_folio_id
  for update;

  if not found then
    raise exception 'Folio was not found.';
  end if;

  if exists (
    select 1
    from public.invoices invoice
    where invoice.hotel_id =
          target_hotel_id
      and invoice.folio_id =
          target_folio_id
      and invoice.invoice_origin =
          'authoritative'
      and invoice.finalized_at is not null
  ) then
    raise exception
      'A final authoritative invoice already exists for this folio.';
  end if;

  preview_value :=
    private.day12_preview_folio_invoice(
      target_hotel_id,
      target_folio_id,
      supply_mode_value,
      invoice_date_value
    );

  number_value :=
    private.day12_next_invoice_number(
      target_hotel_id,
      (
        invoice_date_value::timestamp
        at time zone 'Asia/Kolkata'
      )
    );

  tax_total_value :=
    (
      preview_value
      #>> '{tax_breakup,tax_amount}'
    )::numeric;

  invoice_status_value :=
    preview_value ->> 'invoice_status';

  payment_status_value :=
    preview_value ->> 'payment_status';

  insert into public.invoices (
    id,
    hotel_id,
    folio_id,
    guest_session_id,
    guest_id,
    room_id,

    invoice_number,
    invoice_origin,
    idempotency_key,

    financial_year_start,
    financial_year_label,
    invoice_date,
    currency_code,

    seller_snapshot,
    buyer_snapshot,
    seller_gstin,
    buyer_gstin,
    place_of_supply,
    place_of_supply_code,

    tax_mode,
    room_amount,
    food_amount,
    service_amount,
    manual_amount,
    other_amount,
    discount_type,
    discount_value,
    discount_amount,
    subtotal_amount,
    taxable_amount,
    tax_percent,
    tax_amount,
    cgst_amount,
    sgst_amount,
    igst_amount,
    cess_amount,
    total_amount,

    paid_amount,
    previous_paid_amount,
    pending_amount,
    amount_to_collect,
    payment_status,
    invoice_status,

    checkin_time,
    checkout_time,
    stay_hours,
    stay_nights,

    invoice_notes,
    metadata,
    created_at,
    updated_at
  )
  values (
    invoice_id_value,
    target_hotel_id,
    target_folio_id,
    folio_row.guest_session_id,
    folio_row.guest_id,
    folio_row.room_id,

    number_value ->> 'invoice_number',
    'authoritative',
    normalized_request_id,

    (
      number_value
      ->> 'financial_year_start'
    )::integer,
    number_value
      ->> 'financial_year_label',
    invoice_date_value,
    preview_value ->> 'currency_code',

    preview_value -> 'seller_snapshot',
    preview_value -> 'buyer_snapshot',
    preview_value ->> 'seller_gstin',
    preview_value ->> 'buyer_gstin',
    preview_value ->> 'place_of_supply',
    preview_value ->> 'place_of_supply_code',

    supply_mode_value,
    (
      preview_value
      ->> 'room_amount'
    )::numeric,
    (
      preview_value
      ->> 'food_amount'
    )::numeric,
    (
      preview_value
      ->> 'service_amount'
    )::numeric,
    (
      preview_value
      ->> 'manual_amount'
    )::numeric,
    (
      preview_value
      ->> 'other_amount'
    )::numeric,
    'fixed',
    (
      preview_value
      ->> 'discount_amount'
    )::numeric,
    (
      preview_value
      ->> 'discount_amount'
    )::numeric,
    (
      preview_value
      ->> 'taxable_amount'
    )::numeric,
    (
      preview_value
      ->> 'taxable_amount'
    )::numeric,
    case
      when (
        preview_value
        ->> 'taxable_amount'
      )::numeric > 0
      then round(
        tax_total_value
        * 100
        / (
          preview_value
          ->> 'taxable_amount'
        )::numeric,
        4
      )
      else 0
    end,
    tax_total_value,
    (
      preview_value
      #>> '{tax_breakup,cgst_amount}'
    )::numeric,
    (
      preview_value
      #>> '{tax_breakup,sgst_amount}'
    )::numeric,
    (
      preview_value
      #>> '{tax_breakup,igst_amount}'
    )::numeric,
    (
      preview_value
      #>> '{tax_breakup,cess_amount}'
    )::numeric,
    (
      preview_value
      ->> 'invoice_total'
    )::numeric,

    (
      preview_value
      ->> 'paid_amount'
    )::numeric,
    (
      preview_value
      ->> 'paid_amount'
    )::numeric,
    (
      preview_value
      ->> 'pending_amount'
    )::numeric,
    (
      preview_value
      ->> 'pending_amount'
    )::numeric,
    payment_status_value,
    invoice_status_value,

    (
      preview_value
      ->> 'checkin_time'
    )::timestamptz,
    (
      preview_value
      ->> 'checkout_time'
    )::timestamptz,
    (
      preview_value
      ->> 'stay_hours'
    )::integer,
    (
      preview_value
      ->> 'stay_nights'
    )::integer,

    'Authoritative invoice issued from folio '
      || folio_row.folio_number,
    jsonb_build_object(
      'source', 'folio',
      'request_id', normalized_request_id,
      'migration', '037',
      'preview', preview_value
    ),
    finalized_at_value,
    finalized_at_value
  )
  returning *
  into invoice_row;

  if tax_total_value > 0 then
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
      target_hotel_id,
      target_folio_id,
      'tax',
      null,
      'GST for invoice '
        || invoice_row.invoice_number,
      1,
      tax_total_value,
      tax_total_value,
      'invoices',
      invoice_id_value,
      finalized_at_value,
      'posted',
      finalized_at_value,
      actor_id_value,
      jsonb_build_object(
        'invoice_id', invoice_id_value,
        'invoice_number',
          invoice_row.invoice_number,
        'tax_mode', supply_mode_value,
        'tax_breakup',
          preview_value -> 'tax_breakup',
        'request_id', normalized_request_id,
        'source_sync', 'migration_037'
      )
    )
    returning id
    into tax_item_id_value;
  end if;

  for line_record in
    select
      value as line_value
    from jsonb_array_elements(
      preview_value -> 'lines'
    )
  loop
    line_snapshot :=
      line_record.line_value
      || jsonb_build_object(
        'invoice_id', invoice_id_value,
        'invoice_number',
          invoice_row.invoice_number
      );

    insert into public.invoice_items (
      invoice_id,
      hotel_id,
      guest_id,
      room_id,
      item_type,
      description,
      quantity,
      unit_price,
      amount,
      source_id,
      folio_item_id,
      line_number,
      hsn_sac_code,
      taxable_amount,
      tax_rate_id,
      tax_rate_percent,
      cgst_amount,
      sgst_amount,
      igst_amount,
      cess_amount,
      snapshot_json,
      metadata,
      created_at,
      updated_at
    )
    values (
      invoice_id_value,
      target_hotel_id,
      folio_row.guest_id,
      folio_row.room_id,
      line_record.line_value
        ->> 'item_type',
      line_record.line_value
        ->> 'description',
      (
        line_record.line_value
        ->> 'quantity'
      )::numeric,
      (
        line_record.line_value
        ->> 'unit_price'
      )::numeric,
      (
        line_record.line_value
        ->> 'line_total'
      )::numeric,
      (
        line_record.line_value
        ->> 'folio_item_id'
      )::uuid,
      (
        line_record.line_value
        ->> 'folio_item_id'
      )::uuid,
      (
        line_record.line_value
        ->> 'line_number'
      )::integer,
      line_record.line_value
        ->> 'hsn_sac_code',
      (
        line_record.line_value
        ->> 'taxable_amount'
      )::numeric,
      nullif(
        line_record.line_value
          ->> 'tax_rate_id',
        ''
      )::uuid,
      (
        line_record.line_value
        ->> 'tax_rate_percent'
      )::numeric,
      (
        line_record.line_value
        ->> 'cgst_amount'
      )::numeric,
      (
        line_record.line_value
        ->> 'sgst_amount'
      )::numeric,
      (
        line_record.line_value
        ->> 'igst_amount'
      )::numeric,
      (
        line_record.line_value
        ->> 'cess_amount'
      )::numeric,
      line_snapshot,
      jsonb_build_object(
        'gross_amount',
          (
            line_record.line_value
            ->> 'gross_amount'
          )::numeric,
        'discount_amount',
          (
            line_record.line_value
            ->> 'discount_amount'
          )::numeric,
        'charge_category',
          line_record.line_value
            ->> 'charge_category',
        'request_id',
          normalized_request_id,
        'source_sync',
          'migration_037'
      ),
      finalized_at_value,
      finalized_at_value
    );
  end loop;

  update public.invoices
  set
    tax_folio_item_id = tax_item_id_value
  where hotel_id = target_hotel_id
    and id = invoice_id_value;

  snapshot_value :=
    private.day12_build_invoice_snapshot(
      target_hotel_id,
      invoice_id_value,
      finalized_at_value,
      verification_token_value
    );

  snapshot_hash_value :=
    private.day12_hash_snapshot(
      snapshot_value
    );

  update public.invoices
  set
    snapshot_json = snapshot_value,
    snapshot_hash = snapshot_hash_value,
    verification_token =
      verification_token_value,
    finalized_at = finalized_at_value,
    finalized_by = actor_id_value,
    metadata =
      metadata
      || jsonb_build_object(
        'immutable', true,
        'snapshot_hash',
          snapshot_hash_value
      )
  where hotel_id = target_hotel_id
    and id = invoice_id_value
  returning *
  into invoice_row;

  insert into public.invoice_verifications (
    hotel_id,
    invoice_id,
    verification_token,
    snapshot_hash,
    status,
    metadata
  )
  values (
    target_hotel_id,
    invoice_id_value,
    verification_token_value,
    snapshot_hash_value,
    'active',
    jsonb_build_object(
      'authoritative', true,
      'request_id', normalized_request_id,
      'migration', '037'
    )
  );

  insert into public.invoice_events (
    hotel_id,
    invoice_id,
    event_type,
    actor_id,
    event_snapshot,
    metadata
  )
  values (
    target_hotel_id,
    invoice_id_value,
    'invoice.issued',
    actor_id_value,
    snapshot_value,
    jsonb_build_object(
      'request_id', normalized_request_id,
      'invoice_number',
        invoice_row.invoice_number,
      'tax_folio_item_id',
        tax_item_id_value,
      'migration', '037'
    )
  );

  return jsonb_build_object(
    'ok', true,
    'idempotent', false,
    'invoice_id', invoice_row.id,
    'invoice_number',
      invoice_row.invoice_number,
    'financial_year',
      invoice_row.financial_year_label,
    'verification_token',
      invoice_row.verification_token,
    'snapshot_hash',
      invoice_row.snapshot_hash,
    'tax_folio_item_id',
      invoice_row.tax_folio_item_id,
    'taxable_amount',
      invoice_row.taxable_amount,
    'cgst_amount',
      invoice_row.cgst_amount,
    'sgst_amount',
      invoice_row.sgst_amount,
    'igst_amount',
      invoice_row.igst_amount,
    'cess_amount',
      invoice_row.cess_amount,
    'tax_amount',
      invoice_row.tax_amount,
    'total_amount',
      invoice_row.total_amount,
    'paid_amount',
      invoice_row.paid_amount,
    'pending_amount',
      invoice_row.pending_amount,
    'invoice_status',
      invoice_row.invoice_status,
    'request_id', normalized_request_id
  );
end;
$function$;

-- ---------------------------------------------------------------------------
-- 5. Replace public verification with GST/place-of-supply detail
-- ---------------------------------------------------------------------------

create or replace function public.verify_invoice(
  verification_token_value uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  verification_row public.invoice_verifications%rowtype;
  invoice_row public.invoices%rowtype;
  hotel_name_value text;
  hash_valid boolean;
begin
  select verification.*
  into verification_row
  from public.invoice_verifications verification
  where verification.verification_token =
        verification_token_value
    and verification.status = 'active';

  if not found then
    return jsonb_build_object(
      'verified', false,
      'reason', 'verification_not_found'
    );
  end if;

  select invoice.*
  into invoice_row
  from public.invoices invoice
  where invoice.hotel_id =
        verification_row.hotel_id
    and invoice.id =
        verification_row.invoice_id;

  select hotel.hotel_name
  into hotel_name_value
  from public.hotels hotel
  where hotel.id =
        verification_row.hotel_id;

  hash_valid :=
    invoice_row.snapshot_hash =
      verification_row.snapshot_hash
    and invoice_row.snapshot_hash =
      private.day12_hash_snapshot(
        invoice_row.snapshot_json
      );

  update public.invoice_verifications
  set
    verified_count = verified_count + 1,
    last_verified_at = now()
  where id = verification_row.id;

  return jsonb_build_object(
    'verified', hash_valid,
    'invoice_number', invoice_row.invoice_number,
    'invoice_date', invoice_row.invoice_date,
    'financial_year',
      invoice_row.financial_year_label,
    'hotel_name', hotel_name_value,
    'invoice_status', invoice_row.invoice_status,
    'currency_code', invoice_row.currency_code,
    'seller_gstin', invoice_row.seller_gstin,
    'buyer_gstin', invoice_row.buyer_gstin,
    'place_of_supply',
      invoice_row.place_of_supply,
    'place_of_supply_code',
      invoice_row.place_of_supply_code,
    'tax_mode', invoice_row.tax_mode,
    'taxable_amount',
      invoice_row.taxable_amount,
    'tax_amount', invoice_row.tax_amount,
    'cgst_amount', invoice_row.cgst_amount,
    'sgst_amount', invoice_row.sgst_amount,
    'igst_amount', invoice_row.igst_amount,
    'cess_amount', invoice_row.cess_amount,
    'total_amount', invoice_row.total_amount,
    'snapshot_hash', invoice_row.snapshot_hash,
    'finalized_at', invoice_row.finalized_at
  );
end;
$function$;

-- ---------------------------------------------------------------------------
-- 6. Permissions
-- ---------------------------------------------------------------------------

revoke all on function private.day12_preview_folio_invoice(
  uuid,
  uuid,
  text,
  date
)
from public, anon, authenticated;

grant execute on function private.day12_preview_folio_invoice(
  uuid,
  uuid,
  text,
  date
)
to service_role;

revoke all on function public.preview_folio_invoice(
  uuid,
  uuid,
  text,
  date
)
from public, anon;

grant execute on function public.preview_folio_invoice(
  uuid,
  uuid,
  text,
  date
)
to authenticated, service_role;

revoke all on function public.issue_folio_invoice(
  uuid,
  uuid,
  text,
  date,
  text
)
from public, anon;

grant execute on function public.issue_folio_invoice(
  uuid,
  uuid,
  text,
  date,
  text
)
to authenticated, service_role;

revoke all on function public.verify_invoice(uuid)
from public;

grant execute on function public.verify_invoice(uuid)
to anon, authenticated, service_role;

comment on function public.preview_folio_invoice(
  uuid,
  uuid,
  text,
  date
) is
'Read-only deterministic invoice preview. Tax rates must be explicit; no tax or invoice row is written.';

comment on function public.issue_folio_invoice(
  uuid,
  uuid,
  text,
  date,
  text
) is
'RPC-only idempotent authoritative invoice issuance with financial-year numbering, tax folio posting, immutable snapshot and QR verification.';

commit;
