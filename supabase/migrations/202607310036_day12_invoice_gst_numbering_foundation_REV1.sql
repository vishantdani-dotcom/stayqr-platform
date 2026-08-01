-- ============================================================================
-- StayQR v1.0
-- Day 12 Migration 036 REV1
-- Immutable invoice, GST registry, financial-year numbering and QR
-- verification foundation
--
-- REQUIRES
-- --------
-- Day 11 final Audit 057 accepted 100/100.
-- Combined Audit 058 reviewed.
--
-- CONTROLLED AUDIT 058 TRUTH — VD STAY INN
-- ----------------------------------------
-- invoices: 25
--   draft: 18
--   issued: 3
--   paid: 4
-- invoice_items: 16
-- duplicate invoice-number groups: 0
-- legacy invoice total: INR 63,658
-- legacy paid amount: INR 20,771
-- legacy pending amount: INR 6,025
--
-- THIS MIGRATION
-- --------------
-- 1. Preserves all existing invoice and invoice-item source values.
-- 2. Classifies existing invoices as legacy.
-- 3. Adds financial-year, tax-breakup, seller/buyer snapshot, immutable
--    snapshot/hash and verification fields.
-- 4. Adds hotel tax-rate registry.
-- 5. Adds public invoice-verification records and immutable invoice events.
-- 6. Locks the seven existing issued/paid legacy invoices using exact
--    cryptographic snapshots.
-- 7. Installs financial-year sequence and snapshot helpers.
-- 8. Revokes direct authenticated invoice/tax/sequence writes.
--
-- NOT INCLUDED YET
-- ----------------
-- - No tax rate is invented or inserted.
-- - No new authoritative invoice is issued.
-- - No folio tax is posted.
-- - No receipt, cashier shift or night audit is created.
-- - These are the next bounded Day 12 migrations/runtime gates.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 0. Strict preflight
-- ---------------------------------------------------------------------------

do $preflight$
declare
  missing_objects text;
  conflicting_columns text;
  target_invoice_count bigint;
  target_item_count bigint;
begin
  select string_agg(object_name, ', ' order by object_name)
  into missing_objects
  from (
    values
      ('public.invoices', to_regclass('public.invoices') is not null),
      ('public.invoice_items', to_regclass('public.invoice_items') is not null),
      (
        'public.invoice_number_sequences',
        to_regclass('public.invoice_number_sequences') is not null
      ),
      ('public.folios', to_regclass('public.folios') is not null),
      ('public.folio_items', to_regclass('public.folio_items') is not null),
      (
        'private.user_has_any_permission(uuid,text[])',
        to_regprocedure(
          'private.user_has_any_permission(uuid,text[])'
        ) is not null
      ),
      (
        'private.day11_valid_auth_actor(uuid)',
        to_regprocedure(
          'private.day11_valid_auth_actor(uuid)'
        ) is not null
      )
  ) as required_object(object_name, object_exists)
  where not object_exists;

  if missing_objects is not null then
    raise exception
      'Migration 036 prerequisites are missing: %',
      missing_objects;
  end if;

  if to_regclass('public.tax_rates') is not null
     or to_regclass('public.invoice_verifications') is not null
     or to_regclass('public.invoice_events') is not null
  then
    raise exception
      'Migration 036 target tables already exist. Do not rerun REV1.';
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
          'folio_id',
          'invoice_origin',
          'financial_year_start',
          'financial_year_label',
          'invoice_date',
          'currency_code',
          'seller_snapshot',
          'buyer_snapshot',
          'tax_mode',
          'taxable_amount',
          'cgst_amount',
          'sgst_amount',
          'igst_amount',
          'cess_amount',
          'snapshot_version',
          'snapshot_json',
          'snapshot_hash',
          'verification_token',
          'finalized_at',
          'finalized_by',
          'metadata',
          'updated_at'
        )
      )
      or (
        column_record.table_name = 'invoice_items'
        and column_record.column_name in (
          'folio_item_id',
          'line_number',
          'hsn_sac_code',
          'taxable_amount',
          'tax_rate_percent',
          'cgst_amount',
          'sgst_amount',
          'igst_amount',
          'cess_amount',
          'snapshot_json',
          'metadata',
          'updated_at'
        )
      )
    );

  if conflicting_columns is not null then
    raise exception
      'Migration 036 target columns already exist: %',
      conflicting_columns;
  end if;

  select count(*)
  into target_invoice_count
  from public.invoices
  where hotel_id =
    '77d850d0-016d-4155-bc44-a6207d30e7b9'::uuid;

  select count(*)
  into target_item_count
  from public.invoice_items
  where hotel_id =
    '77d850d0-016d-4155-bc44-a6207d30e7b9'::uuid;

  if target_invoice_count <> 25
     or target_item_count <> 16
  then
    raise exception
      'Audit 058 controlled source changed. Expected 25 invoices / 16 items; found % / %.',
      target_invoice_count,
      target_item_count;
  end if;
end;
$preflight$;

-- ---------------------------------------------------------------------------
-- 1. Tax-rate registry
-- ---------------------------------------------------------------------------

create table public.tax_rates (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null,

  code text not null,
  name text not null,
  charge_category text not null,
  hsn_sac_code text,

  rate_percent numeric(7,4) not null,
  cess_percent numeric(7,4) not null default 0,

  valid_from date not null,
  valid_to date,
  is_active boolean not null default true,

  created_by uuid,
  updated_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,

  constraint tax_rates_hotel_fkey
    foreign key (hotel_id)
    references public.hotels(id)
    on delete cascade,

  constraint tax_rates_created_by_fkey
    foreign key (created_by)
    references auth.users(id)
    on delete set null,

  constraint tax_rates_updated_by_fkey
    foreign key (updated_by)
    references auth.users(id)
    on delete set null,

  constraint tax_rates_code_not_blank
    check (
      length(trim(code)) between 1 and 40
    ),

  constraint tax_rates_name_not_blank
    check (
      length(trim(name)) between 1 and 120
    ),

  constraint tax_rates_category_check
    check (
      charge_category in (
        'room',
        'food',
        'service',
        'manual',
        'other'
      )
    ),

  constraint tax_rates_rate_check
    check (
      rate_percent >= 0
      and rate_percent <= 100
      and cess_percent >= 0
      and cess_percent <= 100
    ),

  constraint tax_rates_period_check
    check (
      valid_to is null
      or valid_to >= valid_from
    )
);

create unique index uq_tax_rates_hotel_code_start
  on public.tax_rates(
    hotel_id,
    lower(code),
    valid_from
  );

create index idx_tax_rates_active_lookup
  on public.tax_rates(
    hotel_id,
    charge_category,
    is_active,
    valid_from,
    valid_to
  );

alter table public.tax_rates
enable row level security;

create policy stayqr_tax_rates_select
on public.tax_rates
for select
to authenticated
using (
  private.user_has_any_permission(
    hotel_id,
    array[
      'payments.view',
      'payments.manage',
      'invoices.view',
      'invoices.manage',
      'checkout.manage'
    ]::text[]
  )
);

create policy stayqr_tax_rates_manage
on public.tax_rates
for all
to authenticated
using (
  private.user_has_any_permission(
    hotel_id,
    array[
      'invoices.manage',
      'checkout.manage'
    ]::text[]
  )
)
with check (
  private.user_has_any_permission(
    hotel_id,
    array[
      'invoices.manage',
      'checkout.manage'
    ]::text[]
  )
);

-- ---------------------------------------------------------------------------
-- 2. Invoice foundation columns
-- ---------------------------------------------------------------------------

alter table public.invoices
  add column folio_id uuid,
  add column invoice_origin text,
  add column financial_year_start integer,
  add column financial_year_label text,
  add column invoice_date date,
  add column currency_code text,
  add column seller_snapshot jsonb not null default '{}'::jsonb,
  add column buyer_snapshot jsonb not null default '{}'::jsonb,
  add column tax_mode text not null default 'unconfigured',
  add column taxable_amount numeric(14,2) not null default 0,
  add column cgst_amount numeric(14,2) not null default 0,
  add column sgst_amount numeric(14,2) not null default 0,
  add column igst_amount numeric(14,2) not null default 0,
  add column cess_amount numeric(14,2) not null default 0,
  add column snapshot_version integer not null default 1,
  add column snapshot_json jsonb,
  add column snapshot_hash text,
  add column verification_token uuid,
  add column finalized_at timestamptz,
  add column finalized_by uuid,
  add column metadata jsonb not null default '{}'::jsonb,
  add column updated_at timestamptz not null default now();

alter table public.invoices
  add constraint invoices_folio_fkey
    foreign key (folio_id)
    references public.folios(id)
    on delete restrict,

  add constraint invoices_finalized_by_fkey
    foreign key (finalized_by)
    references auth.users(id)
    on delete set null,

  add constraint invoices_origin_check
    check (
      invoice_origin in (
        'legacy',
        'authoritative'
      )
    ),

  add constraint invoices_financial_year_check
    check (
      financial_year_start between 2000 and 9999
    ),

  add constraint invoices_tax_mode_check
    check (
      tax_mode in (
        'unconfigured',
        'exempt',
        'intra_state',
        'inter_state',
        'legacy_unclassified'
      )
    ),

  add constraint invoices_tax_amounts_check
    check (
      taxable_amount >= 0
      and cgst_amount >= 0
      and sgst_amount >= 0
      and igst_amount >= 0
      and cess_amount >= 0
    ),

  add constraint invoices_snapshot_version_check
    check (snapshot_version >= 1),

  add constraint invoices_finalization_check
    check (
      finalized_at is null
      or (
        snapshot_json is not null
        and snapshot_hash is not null
        and verification_token is not null
      )
    );

create unique index uq_invoices_verification_token
  on public.invoices(verification_token)
  where verification_token is not null;

create unique index uq_authoritative_final_invoice_per_folio
  on public.invoices(hotel_id, folio_id)
  where invoice_origin = 'authoritative'
    and finalized_at is not null
    and folio_id is not null;

create index idx_invoices_hotel_financial_year
  on public.invoices(
    hotel_id,
    financial_year_start,
    invoice_date desc
  );

create index idx_invoices_hotel_folio
  on public.invoices(hotel_id, folio_id)
  where folio_id is not null;

-- ---------------------------------------------------------------------------
-- 3. Immutable line snapshot fields
-- ---------------------------------------------------------------------------

alter table public.invoice_items
  add column folio_item_id uuid,
  add column line_number integer,
  add column hsn_sac_code text,
  add column taxable_amount numeric(14,2) not null default 0,
  add column tax_rate_percent numeric(7,4) not null default 0,
  add column cgst_amount numeric(14,2) not null default 0,
  add column sgst_amount numeric(14,2) not null default 0,
  add column igst_amount numeric(14,2) not null default 0,
  add column cess_amount numeric(14,2) not null default 0,
  add column snapshot_json jsonb not null default '{}'::jsonb,
  add column metadata jsonb not null default '{}'::jsonb,
  add column updated_at timestamptz not null default now();

alter table public.invoice_items
  add constraint invoice_items_folio_item_fkey
    foreign key (folio_item_id)
    references public.folio_items(id)
    on delete restrict,

  add constraint invoice_items_line_number_check
    check (
      line_number is null
      or line_number >= 1
    ),

  add constraint invoice_items_tax_amounts_check
    check (
      taxable_amount >= 0
      and tax_rate_percent >= 0
      and tax_rate_percent <= 100
      and cgst_amount >= 0
      and sgst_amount >= 0
      and igst_amount >= 0
      and cess_amount >= 0
    );

create unique index uq_invoice_items_line_number
  on public.invoice_items(invoice_id, line_number)
  where line_number is not null;

create unique index uq_invoice_items_folio_item
  on public.invoice_items(invoice_id, folio_item_id)
  where folio_item_id is not null;

-- ---------------------------------------------------------------------------
-- 4. Verification and event ledgers
-- ---------------------------------------------------------------------------

create table public.invoice_verifications (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null,
  invoice_id uuid not null,
  verification_token uuid not null,
  snapshot_hash text not null,
  status text not null default 'active',
  verified_count bigint not null default 0,
  last_verified_at timestamptz,
  created_at timestamptz not null default now(),
  revoked_at timestamptz,
  revoked_by uuid,
  revoke_reason text,
  metadata jsonb not null default '{}'::jsonb,

  constraint invoice_verifications_hotel_fkey
    foreign key (hotel_id)
    references public.hotels(id)
    on delete cascade,

  constraint invoice_verifications_invoice_fkey
    foreign key (invoice_id)
    references public.invoices(id)
    on delete restrict,

  constraint invoice_verifications_revoked_by_fkey
    foreign key (revoked_by)
    references auth.users(id)
    on delete set null,

  constraint invoice_verifications_status_check
    check (
      status in ('active', 'revoked')
    ),

  constraint invoice_verifications_count_check
    check (verified_count >= 0),

  constraint invoice_verifications_revoke_check
    check (
      status = 'active'
      or (
        revoked_at is not null
        and nullif(trim(revoke_reason), '') is not null
      )
    )
);

create unique index uq_invoice_verifications_invoice
  on public.invoice_verifications(hotel_id, invoice_id);

create unique index uq_invoice_verifications_token
  on public.invoice_verifications(verification_token);

create table public.invoice_events (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null,
  invoice_id uuid not null,
  event_type text not null,
  actor_id uuid,
  event_snapshot jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),

  constraint invoice_events_hotel_fkey
    foreign key (hotel_id)
    references public.hotels(id)
    on delete cascade,

  constraint invoice_events_invoice_fkey
    foreign key (invoice_id)
    references public.invoices(id)
    on delete restrict,

  constraint invoice_events_actor_fkey
    foreign key (actor_id)
    references auth.users(id)
    on delete set null,

  constraint invoice_events_type_not_blank
    check (
      length(trim(event_type)) between 1 and 100
    )
);

create index idx_invoice_events_invoice_created
  on public.invoice_events(
    hotel_id,
    invoice_id,
    created_at desc
  );

alter table public.invoice_verifications
enable row level security;

alter table public.invoice_events
enable row level security;

create policy stayqr_invoice_verifications_select
on public.invoice_verifications
for select
to authenticated
using (
  private.user_has_any_permission(
    hotel_id,
    array[
      'invoices.view',
      'invoices.manage',
      'checkout.manage'
    ]::text[]
  )
);

create policy stayqr_invoice_events_select
on public.invoice_events
for select
to authenticated
using (
  private.user_has_any_permission(
    hotel_id,
    array[
      'invoices.view',
      'invoices.manage',
      'checkout.manage'
    ]::text[]
  )
);

-- ---------------------------------------------------------------------------
-- 5. Financial-year and snapshot helpers
-- ---------------------------------------------------------------------------

create or replace function private.day12_financial_year_start(
  occurred_at_value timestamptz,
  timezone_value text
)
returns integer
language sql
stable
security invoker
set search_path = ''
as $function$
  select case
    when extract(
      month from (
        coalesce(occurred_at_value, now())
        at time zone coalesce(
          nullif(trim(timezone_value), ''),
          'Asia/Kolkata'
        )
      )
    ) >= 4
    then extract(
      year from (
        coalesce(occurred_at_value, now())
        at time zone coalesce(
          nullif(trim(timezone_value), ''),
          'Asia/Kolkata'
        )
      )
    )::integer
    else extract(
      year from (
        coalesce(occurred_at_value, now())
        at time zone coalesce(
          nullif(trim(timezone_value), ''),
          'Asia/Kolkata'
        )
      )
    )::integer - 1
  end;
$function$;

create or replace function private.day12_financial_year_label(
  financial_year_start_value integer
)
returns text
language sql
immutable
security invoker
set search_path = ''
as $function$
  select
    financial_year_start_value::text
    || '-'
    || right(
      (financial_year_start_value + 1)::text,
      2
    );
$function$;

create or replace function private.day12_hash_snapshot(
  snapshot_value jsonb
)
returns text
language sql
immutable
security invoker
set search_path = ''
as $function$
  select encode(
    extensions.digest(
      convert_to(
        coalesce(snapshot_value, '{}'::jsonb)::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );
$function$;

create or replace function private.day12_build_invoice_snapshot(
  target_hotel_id uuid,
  target_invoice_id uuid,
  finalized_at_override timestamptz default null,
  verification_token_override uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  invoice_row public.invoices%rowtype;
  hotel_snapshot_value jsonb;
  guest_snapshot_value jsonb;
  folio_snapshot_value jsonb;
  item_snapshot_value jsonb;
  finalized_value timestamptz;
  token_value uuid;
begin
  select invoice.*
  into invoice_row
  from public.invoices invoice
  where invoice.hotel_id = target_hotel_id
    and invoice.id = target_invoice_id;

  if not found then
    raise exception 'Invoice was not found.';
  end if;

  finalized_value :=
    coalesce(finalized_at_override, invoice_row.finalized_at);

  token_value :=
    coalesce(
      verification_token_override,
      invoice_row.verification_token
    );

  select
    to_jsonb(hotel)
    || jsonb_build_object(
      'settings',
      coalesce(
        (
          select to_jsonb(setting)
          from public.hotel_settings setting
          where setting.hotel_id = hotel.id
        ),
        '{}'::jsonb
      )
    )
  into hotel_snapshot_value
  from public.hotels hotel
  where hotel.id = target_hotel_id;

  select coalesce(
    (
      select to_jsonb(guest)
      from public.guests guest
      where guest.id = invoice_row.guest_id
    ),
    '{}'::jsonb
  )
  into guest_snapshot_value;

  select coalesce(
    (
      select to_jsonb(folio)
      from public.folios folio
      where folio.hotel_id = target_hotel_id
        and folio.id = invoice_row.folio_id
    ),
    '{}'::jsonb
  )
  into folio_snapshot_value;

  select coalesce(
    jsonb_agg(
      to_jsonb(item)
      order by
        item.line_number nulls last,
        item.created_at,
        item.id
    ),
    '[]'::jsonb
  )
  into item_snapshot_value
  from public.invoice_items item
  where item.hotel_id = target_hotel_id
    and item.invoice_id = target_invoice_id;

  return jsonb_build_object(
    'schema', 'stayqr.invoice.snapshot',
    'version', invoice_row.snapshot_version,
    'invoice',
      (
        to_jsonb(invoice_row)
        - 'snapshot_json'
        - 'snapshot_hash'
      )
      || jsonb_build_object(
        'finalized_at', finalized_value,
        'verification_token', token_value
      ),
    'items', item_snapshot_value,
    'seller', coalesce(
      invoice_row.seller_snapshot,
      hotel_snapshot_value
    ),
    'buyer', coalesce(
      invoice_row.buyer_snapshot,
      guest_snapshot_value
    ),
    'folio', folio_snapshot_value,
    'captured_at', finalized_value
  );
end;
$function$;

create or replace function private.day12_next_invoice_number(
  target_hotel_id uuid,
  occurred_at_value timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  hotel_row public.hotels%rowtype;
  sequence_row public.invoice_number_sequences%rowtype;
  financial_year_start_value integer;
  financial_year_label_value text;
  next_number_value bigint;
  generated_number text;
begin
  select hotel.*
  into hotel_row
  from public.hotels hotel
  where hotel.id = target_hotel_id;

  if not found then
    raise exception 'Hotel was not found.';
  end if;

  financial_year_start_value :=
    private.day12_financial_year_start(
      occurred_at_value,
      hotel_row.timezone
    );

  financial_year_label_value :=
    private.day12_financial_year_label(
      financial_year_start_value
    );

  perform pg_advisory_xact_lock(
    hashtextextended(
      'stayqr:invoice-sequence:'
      || target_hotel_id::text
      || ':'
      || financial_year_start_value::text,
      0
    )
  );

  insert into public.invoice_number_sequences (
    hotel_id,
    sequence_year,
    prefix,
    last_number,
    padding,
    reset_annually,
    updated_by
  )
  values (
    target_hotel_id,
    financial_year_start_value,
    'INV',
    0,
    6,
    true,
    private.day11_valid_auth_actor(auth.uid())
  )
  on conflict (hotel_id, sequence_year)
  do nothing;

  update public.invoice_number_sequences
  set
    last_number = last_number + 1,
    updated_at = now(),
    updated_by =
      private.day11_valid_auth_actor(auth.uid())
  where hotel_id = target_hotel_id
    and sequence_year = financial_year_start_value
  returning *
  into sequence_row;

  next_number_value := sequence_row.last_number;

  generated_number :=
    trim(sequence_row.prefix)
    || '/'
    || financial_year_label_value
    || '/'
    || lpad(
      next_number_value::text,
      sequence_row.padding,
      '0'
    );

  return jsonb_build_object(
    'invoice_number', generated_number,
    'financial_year_start',
      financial_year_start_value,
    'financial_year_label',
      financial_year_label_value,
    'sequence_number', next_number_value,
    'prefix', sequence_row.prefix,
    'padding', sequence_row.padding
  );
end;
$function$;

-- ---------------------------------------------------------------------------
-- 6. Immutability triggers
-- ---------------------------------------------------------------------------

create or replace function private.day12_lock_finalized_invoice()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if tg_op = 'DELETE' then
    if old.finalized_at is not null then
      raise exception
        'Finalized invoices are immutable and cannot be deleted.';
    end if;

    return old;
  end if;

  if old.finalized_at is not null then
    if to_jsonb(new) is distinct from to_jsonb(old) then
      raise exception
        'Finalized invoices are immutable. Use a credit note or cancellation workflow.';
    end if;

    return new;
  end if;

  if new.finalized_at is not null then
    if new.snapshot_json is null
       or nullif(trim(new.snapshot_hash), '') is null
       or new.verification_token is null
    then
      raise exception
        'Invoice finalization requires snapshot, hash and verification token.';
    end if;

    if new.snapshot_hash <>
      private.day12_hash_snapshot(new.snapshot_json)
    then
      raise exception
        'Invoice snapshot hash does not match the immutable snapshot.';
    end if;
  end if;

  new.updated_at := now();
  return new;
end;
$function$;

create or replace function private.day12_lock_finalized_invoice_items()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  target_invoice_id uuid;
  finalized_value timestamptz;
begin
  target_invoice_id :=
    coalesce(new.invoice_id, old.invoice_id);

  select invoice.finalized_at
  into finalized_value
  from public.invoices invoice
  where invoice.id = target_invoice_id;

  if finalized_value is not null then
    raise exception
      'Finalized invoice lines are immutable.';
  end if;

  if tg_op <> 'DELETE' then
    new.updated_at := now();
    return new;
  end if;

  return old;
end;
$function$;

create trigger invoices_day12_immutable
before update or delete
on public.invoices
for each row
execute function private.day12_lock_finalized_invoice();

create trigger invoice_items_day12_immutable
before insert or update or delete
on public.invoice_items
for each row
execute function private.day12_lock_finalized_invoice_items();

-- ---------------------------------------------------------------------------
-- 7. Public verification and authenticated snapshot reads
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
  where hotel.id = verification_row.hotel_id;

  update public.invoice_verifications
  set
    verified_count = verified_count + 1,
    last_verified_at = now()
  where id = verification_row.id;

  return jsonb_build_object(
    'verified',
      invoice_row.snapshot_hash =
        verification_row.snapshot_hash
      and invoice_row.snapshot_hash =
        private.day12_hash_snapshot(
          invoice_row.snapshot_json
        ),
    'invoice_number', invoice_row.invoice_number,
    'invoice_date', invoice_row.invoice_date,
    'financial_year',
      invoice_row.financial_year_label,
    'hotel_name', hotel_name_value,
    'invoice_status', invoice_row.invoice_status,
    'currency_code', invoice_row.currency_code,
    'taxable_amount', invoice_row.taxable_amount,
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

create or replace function public.get_invoice_snapshot(
  target_hotel_id uuid,
  target_invoice_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  invoice_row public.invoices%rowtype;
begin
  if not private.user_has_any_permission(
    target_hotel_id,
    array[
      'invoices.view',
      'invoices.manage',
      'checkout.manage'
    ]::text[]
  ) then
    raise exception 'Invoice access denied.';
  end if;

  select invoice.*
  into invoice_row
  from public.invoices invoice
  where invoice.hotel_id = target_hotel_id
    and invoice.id = target_invoice_id;

  if not found then
    raise exception 'Invoice was not found.';
  end if;

  return jsonb_build_object(
    'invoice', to_jsonb(invoice_row),
    'snapshot', invoice_row.snapshot_json,
    'snapshot_hash', invoice_row.snapshot_hash,
    'verification_token',
      invoice_row.verification_token,
    'events',
      coalesce(
        (
          select jsonb_agg(
            to_jsonb(event_record)
            order by event_record.created_at,
                     event_record.id
          )
          from public.invoice_events event_record
          where event_record.hotel_id =
                target_hotel_id
            and event_record.invoice_id =
                target_invoice_id
        ),
        '[]'::jsonb
      )
  );
end;
$function$;

create or replace function public.upsert_tax_rate(
  target_hotel_id uuid,
  target_tax_rate_id uuid,
  code_value text,
  name_value text,
  charge_category_value text,
  hsn_sac_code_value text,
  rate_percent_value numeric,
  cess_percent_value numeric,
  valid_from_value date,
  valid_to_value date,
  active_value boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  tax_rate_row public.tax_rates%rowtype;
  normalized_code text;
  normalized_name text;
begin
  if not private.user_has_any_permission(
    target_hotel_id,
    array[
      'invoices.manage',
      'checkout.manage'
    ]::text[]
  ) then
    raise exception 'Tax configuration access denied.';
  end if;

  normalized_code := upper(trim(coalesce(code_value, '')));
  normalized_name := trim(coalesce(name_value, ''));

  if normalized_code = ''
     or normalized_name = ''
  then
    raise exception 'Tax code and name are required.';
  end if;

  if charge_category_value not in (
    'room',
    'food',
    'service',
    'manual',
    'other'
  ) then
    raise exception 'Tax charge category is invalid.';
  end if;

  if rate_percent_value < 0
     or rate_percent_value > 100
     or coalesce(cess_percent_value, 0) < 0
     or coalesce(cess_percent_value, 0) > 100
  then
    raise exception 'Tax rates must be between 0 and 100.';
  end if;

  if valid_from_value is null
     or (
       valid_to_value is not null
       and valid_to_value < valid_from_value
     )
  then
    raise exception 'Tax validity period is invalid.';
  end if;

  if target_tax_rate_id is null then
    insert into public.tax_rates (
      hotel_id,
      code,
      name,
      charge_category,
      hsn_sac_code,
      rate_percent,
      cess_percent,
      valid_from,
      valid_to,
      is_active,
      created_by,
      updated_by
    )
    values (
      target_hotel_id,
      normalized_code,
      normalized_name,
      charge_category_value,
      nullif(trim(hsn_sac_code_value), ''),
      rate_percent_value,
      coalesce(cess_percent_value, 0),
      valid_from_value,
      valid_to_value,
      active_value,
      private.day11_valid_auth_actor(auth.uid()),
      private.day11_valid_auth_actor(auth.uid())
    )
    returning *
    into tax_rate_row;
  else
    update public.tax_rates
    set
      code = normalized_code,
      name = normalized_name,
      charge_category = charge_category_value,
      hsn_sac_code =
        nullif(trim(hsn_sac_code_value), ''),
      rate_percent = rate_percent_value,
      cess_percent =
        coalesce(cess_percent_value, 0),
      valid_from = valid_from_value,
      valid_to = valid_to_value,
      is_active = active_value,
      updated_by =
        private.day11_valid_auth_actor(auth.uid()),
      updated_at = now()
    where hotel_id = target_hotel_id
      and id = target_tax_rate_id
    returning *
    into tax_rate_row;

    if tax_rate_row.id is null then
      raise exception 'Tax rate was not found.';
    end if;
  end if;

  return jsonb_build_object(
    'ok', true,
    'tax_rate', to_jsonb(tax_rate_row)
  );
end;
$function$;

-- ---------------------------------------------------------------------------
-- 8. Legacy metadata and financial-year backfill
-- ---------------------------------------------------------------------------

update public.invoices invoice
set
  invoice_origin = 'legacy',
  financial_year_start =
    private.day12_financial_year_start(
      coalesce(invoice.created_at, now()),
      hotel.timezone
    ),
  financial_year_label =
    private.day12_financial_year_label(
      private.day12_financial_year_start(
        coalesce(invoice.created_at, now()),
        hotel.timezone
      )
    ),
  invoice_date =
    (
      coalesce(invoice.created_at, now())
      at time zone hotel.timezone
    )::date,
  currency_code = hotel.currency_code,
  seller_snapshot =
    to_jsonb(hotel)
    || jsonb_build_object(
      'settings',
        coalesce(
          (
            select to_jsonb(setting)
            from public.hotel_settings setting
            where setting.hotel_id = hotel.id
          ),
          '{}'::jsonb
        )
    ),
  buyer_snapshot =
    coalesce(
      (
        select to_jsonb(guest)
        from public.guests guest
        where guest.id = invoice.guest_id
      ),
      '{}'::jsonb
    ),
  tax_mode =
    case
      when coalesce(invoice.tax_amount, 0) > 0
        then 'legacy_unclassified'
      else 'unconfigured'
    end,
  taxable_amount =
    greatest(
      coalesce(
        nullif(invoice.subtotal_amount, 0),
        invoice.total_amount - invoice.tax_amount,
        invoice.total_amount,
        0
      ),
      0
    ),
  metadata =
    invoice.metadata
    || jsonb_build_object(
      'migration', '036',
      'legacy_preserved', true,
      'legacy_status',
        invoice.invoice_status,
      'legacy_payment_status',
        invoice.payment_status
    ),
  updated_at = now()
from public.hotels hotel
where hotel.id = invoice.hotel_id;

alter table public.invoices
  alter column invoice_origin
    set default 'authoritative',
  alter column invoice_origin
    set not null,
  alter column financial_year_start
    set not null,
  alter column financial_year_label
    set not null,
  alter column invoice_date
    set not null,
  alter column currency_code
    set not null;

-- Assign deterministic legacy line numbers without modifying legacy amounts.
with numbered_items as (
  select
    item.id,
    row_number() over (
      partition by item.invoice_id
      order by item.created_at, item.id
    )::integer as generated_line_number
  from public.invoice_items item
)
update public.invoice_items item
set
  line_number =
    numbered.generated_line_number,
  taxable_amount =
    case
      when item.item_type = 'tax'
        then 0
      else greatest(
        coalesce(item.amount, 0),
        0
      )
    end,
  snapshot_json = to_jsonb(item),
  metadata =
    item.metadata
    || jsonb_build_object(
      'migration', '036',
      'legacy_preserved', true
    ),
  updated_at = now()
from numbered_items numbered
where numbered.id = item.id;

-- ---------------------------------------------------------------------------
-- 9. Lock all existing issued/paid legacy invoices exactly as they stand
-- ---------------------------------------------------------------------------

do $legacy_lock$
declare
  source_invoice record;
  finalized_value timestamptz;
  token_value uuid;
  snapshot_value jsonb;
  hash_value text;
begin
  for source_invoice in
    select
      invoice.id,
      invoice.hotel_id,
      invoice.created_at
    from public.invoices invoice
    where invoice.invoice_origin = 'legacy'
      and invoice.invoice_status in (
        'issued',
        'paid'
      )
      and invoice.finalized_at is null
    order by invoice.created_at, invoice.id
  loop
    finalized_value :=
      coalesce(source_invoice.created_at, now());

    token_value := gen_random_uuid();

    snapshot_value :=
      private.day12_build_invoice_snapshot(
        source_invoice.hotel_id,
        source_invoice.id,
        finalized_value,
        token_value
      );

    hash_value :=
      private.day12_hash_snapshot(snapshot_value);

    update public.invoices
    set
      snapshot_json = snapshot_value,
      snapshot_hash = hash_value,
      verification_token = token_value,
      finalized_at = finalized_value,
      finalized_by = null,
      metadata = metadata || jsonb_build_object(
        'legacy_locked_by_migration', '036'
      )
    where hotel_id = source_invoice.hotel_id
      and id = source_invoice.id;

    insert into public.invoice_verifications (
      hotel_id,
      invoice_id,
      verification_token,
      snapshot_hash,
      status,
      created_at,
      metadata
    )
    values (
      source_invoice.hotel_id,
      source_invoice.id,
      token_value,
      hash_value,
      'active',
      finalized_value,
      jsonb_build_object(
        'legacy_snapshot', true,
        'migration', '036'
      )
    );

    insert into public.invoice_events (
      hotel_id,
      invoice_id,
      event_type,
      actor_id,
      event_snapshot,
      metadata,
      created_at
    )
    values (
      source_invoice.hotel_id,
      source_invoice.id,
      'invoice.legacy_snapshot_locked',
      null,
      snapshot_value,
      jsonb_build_object(
        'snapshot_hash', hash_value,
        'migration', '036'
      ),
      finalized_value
    );
  end loop;
end;
$legacy_lock$;

-- ---------------------------------------------------------------------------
-- 10. Privilege boundary
-- ---------------------------------------------------------------------------

revoke insert, update, delete
on public.invoices
from public, anon, authenticated;

revoke insert, update, delete
on public.invoice_items
from public, anon, authenticated;

revoke insert, update, delete
on public.invoice_number_sequences
from public, anon, authenticated;

revoke all
on public.tax_rates
from public, anon, authenticated;

grant select
on public.tax_rates
to authenticated;

grant all
on public.tax_rates
to service_role;

revoke all
on public.invoice_verifications
from public, anon, authenticated;

grant select
on public.invoice_verifications
to authenticated;

grant all
on public.invoice_verifications
to service_role;

revoke all
on public.invoice_events
from public, anon, authenticated;

grant select
on public.invoice_events
to authenticated;

grant all
on public.invoice_events
to service_role;

revoke all on function private.day12_financial_year_start(
  timestamptz,
  text
)
from public, anon, authenticated;

revoke all on function private.day12_financial_year_label(integer)
from public, anon, authenticated;

revoke all on function private.day12_hash_snapshot(jsonb)
from public, anon, authenticated;

revoke all on function private.day12_build_invoice_snapshot(
  uuid,
  uuid,
  timestamptz,
  uuid
)
from public, anon, authenticated;

revoke all on function private.day12_next_invoice_number(
  uuid,
  timestamptz
)
from public, anon, authenticated;

grant execute on function private.day12_financial_year_start(
  timestamptz,
  text
)
to service_role;

grant execute on function private.day12_financial_year_label(integer)
to service_role;

grant execute on function private.day12_hash_snapshot(jsonb)
to service_role;

grant execute on function private.day12_build_invoice_snapshot(
  uuid,
  uuid,
  timestamptz,
  uuid
)
to service_role;

grant execute on function private.day12_next_invoice_number(
  uuid,
  timestamptz
)
to service_role;

revoke all on function public.verify_invoice(uuid)
from public;

grant execute on function public.verify_invoice(uuid)
to anon, authenticated, service_role;

revoke all on function public.get_invoice_snapshot(uuid, uuid)
from public, anon;

grant execute on function public.get_invoice_snapshot(uuid, uuid)
to authenticated, service_role;

revoke all on function public.upsert_tax_rate(
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  numeric,
  numeric,
  date,
  date,
  boolean
)
from public, anon;

grant execute on function public.upsert_tax_rate(
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  numeric,
  numeric,
  date,
  date,
  boolean
)
to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 11. Documentation
-- ---------------------------------------------------------------------------

comment on table public.tax_rates is
'Hotel-scoped GST/tax registry. Migration 036 inserts no rates; all tax configuration is explicit.';

comment on table public.invoice_verifications is
'Public QR verification identity for immutable finalized invoice snapshots.';

comment on table public.invoice_events is
'Immutable invoice lifecycle evidence. Final invoices themselves cannot be edited or deleted.';

comment on function private.day12_next_invoice_number(uuid, timestamptz) is
'Concurrency-safe Indian financial-year invoice number allocator using the existing invoice_number_sequences table.';

comment on function public.verify_invoice(uuid) is
'Public limited-data invoice verification endpoint. It never exposes the private buyer or line snapshot.';

commit;
