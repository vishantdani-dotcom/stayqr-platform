-- StayQR v1.0
-- Day 11 Migration 032 REV2
-- Authoritative folio, collections and settlement foundation
-- REV2 fixes composite-key creation order for folio_collections.
--
-- AUDIT 054 BASIS
-- ---------------
-- Current production truth:
-- - 40 payment/charge rows
-- - 15 payment collection rows
-- - 25 legacy invoices
-- - 15 legacy invoice-equation mismatches
-- - no direct financial FK orphans
-- - no authoritative folio/refund/credit/discount/webhook tables
--
-- THIS MIGRATION
-- --------------
-- Creates the authoritative Day 11 financial kernel only.
--
-- It does NOT:
-- - backfill legacy payments, collections, food orders or invoices;
-- - rewrite any existing payment or invoice row;
-- - issue an invoice;
-- - calculate GST;
-- - perform checkout;
-- - process a real refund;
-- - call a payment gateway.
--
-- Those are subsequent bounded Day 11 migrations after this foundation passes.

begin;


-- REV1 failed inside this explicit transaction and should have rolled back.
-- Stop safely if a partial Day 11 schema was created manually or by a
-- separately executed statement.
do $preflight$
declare
  existing_objects text;
begin
  select string_agg(object_name, ', ' order by object_name)
  into existing_objects
  from (
    values
      ('public.folios', to_regclass('public.folios')),
      ('public.folio_items', to_regclass('public.folio_items')),
      ('public.folio_collections', to_regclass('public.folio_collections')),
      ('public.discount_approvals', to_regclass('public.discount_approvals')),
      ('public.refunds', to_regclass('public.refunds')),
      ('public.credit_notes', to_regclass('public.credit_notes')),
      ('public.folio_adjustments', to_regclass('public.folio_adjustments')),
      ('public.payment_webhook_events', to_regclass('public.payment_webhook_events')),
      ('public.folio_events', to_regclass('public.folio_events'))
  ) as object_state(object_name, relation_id)
  where relation_id is not null;

  if existing_objects is not null then
    raise exception
      'Migration 032 REV2 preflight detected existing Day 11 tables: %. Do not drop them manually; inspect the previous transaction state first.',
      existing_objects;
  end if;
end;
$preflight$;


-- ---------------------------------------------------------------------------
-- 1. Authoritative folio header
-- ---------------------------------------------------------------------------

create table public.folios (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null,
  folio_number text not null,
  guest_session_id uuid not null,
  reservation_id uuid,
  reservation_room_id uuid,
  guest_id uuid not null,
  room_id uuid,
  status text not null default 'open',
  currency_code text not null default 'INR',

  charges_amount numeric(14,2) not null default 0,
  discount_amount numeric(14,2) not null default 0,
  tax_amount numeric(14,2) not null default 0,
  collection_amount numeric(14,2) not null default 0,
  refund_amount numeric(14,2) not null default 0,
  credit_amount numeric(14,2) not null default 0,
  balance_amount numeric(14,2) not null default 0,

  opened_at timestamptz not null default now(),
  opened_by uuid,
  settled_at timestamptz,
  settled_by uuid,
  voided_at timestamptz,
  voided_by uuid,
  void_reason text,

  lock_version bigint not null default 0,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint folios_status_check
    check (status in ('open', 'settled', 'voided')),

  constraint folios_currency_check
    check (currency_code ~ '^[A-Z]{3}$'),

  constraint folios_amounts_nonnegative
    check (
      charges_amount >= 0
      and discount_amount >= 0
      and tax_amount >= 0
      and collection_amount >= 0
      and refund_amount >= 0
      and credit_amount >= 0
    ),

  constraint folios_balance_equation_check
    check (
      balance_amount =
        charges_amount
        - discount_amount
        + tax_amount
        - collection_amount
        + refund_amount
        - credit_amount
    ),

  constraint folios_settled_check
    check (
      status <> 'settled'
      or (
        settled_at is not null
        and balance_amount = 0
      )
    ),

  constraint folios_voided_check
    check (
      status <> 'voided'
      or (
        voided_at is not null
        and nullif(trim(void_reason), '') is not null
      )
    ),

  constraint folios_hotel_fkey
    foreign key (hotel_id)
    references public.hotels(id)
    on delete restrict,

  constraint folios_guest_session_fkey
    foreign key (hotel_id, guest_session_id)
    references public.guest_sessions(hotel_id, id)
    on delete restrict,

  constraint folios_reservation_fkey
    foreign key (hotel_id, reservation_id)
    references public.reservations(hotel_id, id)
    on delete restrict,

  constraint folios_reservation_room_fkey
    foreign key (hotel_id, reservation_room_id)
    references public.reservation_rooms(hotel_id, id)
    on delete restrict,

  constraint folios_guest_fkey
    foreign key (hotel_id, guest_id)
    references public.guests(hotel_id, id)
    on delete restrict,

  constraint folios_room_fkey
    foreign key (hotel_id, room_id)
    references public.rooms(hotel_id, id)
    on delete restrict,

  constraint folios_opened_by_fkey
    foreign key (opened_by)
    references auth.users(id)
    on delete set null,

  constraint folios_settled_by_fkey
    foreign key (settled_by)
    references auth.users(id)
    on delete set null,

  constraint folios_voided_by_fkey
    foreign key (voided_by)
    references auth.users(id)
    on delete set null
);

create unique index uq_folios_hotel_id_id
  on public.folios(hotel_id, id);

create unique index uq_folios_hotel_number
  on public.folios(hotel_id, folio_number);

create unique index uq_folios_hotel_guest_session
  on public.folios(hotel_id, guest_session_id);

create index idx_folios_hotel_status_updated
  on public.folios(hotel_id, status, updated_at desc);

create index idx_folios_hotel_guest
  on public.folios(hotel_id, guest_id, opened_at desc);

-- ---------------------------------------------------------------------------
-- 2. Authoritative folio items
-- ---------------------------------------------------------------------------

create table public.folio_items (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null,
  folio_id uuid not null,

  item_kind text not null,
  charge_category text,
  description text not null,
  quantity numeric(12,3) not null default 1,
  unit_amount numeric(14,2) not null default 0,
  amount numeric(14,2) not null,

  source_table text,
  source_id uuid,
  service_at timestamptz not null default now(),

  posting_status text not null default 'posted',
  posted_at timestamptz not null default now(),
  posted_by uuid,
  voided_at timestamptz,
  voided_by uuid,
  void_reason text,

  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint folio_items_kind_check
    check (item_kind in ('charge', 'tax')),

  constraint folio_items_category_check
    check (
      charge_category is null
      or charge_category in (
        'room',
        'food',
        'service',
        'manual',
        'other'
      )
    ),

  constraint folio_items_amount_check
    check (
      quantity > 0
      and unit_amount >= 0
      and amount >= 0
    ),

  constraint folio_items_status_check
    check (posting_status in ('posted', 'voided')),

  constraint folio_items_voided_check
    check (
      posting_status <> 'voided'
      or (
        voided_at is not null
        and nullif(trim(void_reason), '') is not null
      )
    ),

  constraint folio_items_hotel_fkey
    foreign key (hotel_id)
    references public.hotels(id)
    on delete restrict,

  constraint folio_items_folio_fkey
    foreign key (hotel_id, folio_id)
    references public.folios(hotel_id, id)
    on delete cascade,

  constraint folio_items_posted_by_fkey
    foreign key (posted_by)
    references auth.users(id)
    on delete set null,

  constraint folio_items_voided_by_fkey
    foreign key (voided_by)
    references auth.users(id)
    on delete set null
);

create index idx_folio_items_folio_posted
  on public.folio_items(
    hotel_id,
    folio_id,
    posting_status,
    service_at
  );

create unique index uq_folio_items_source
  on public.folio_items(
    hotel_id,
    folio_id,
    item_kind,
    source_table,
    source_id
  )
  where source_table is not null
    and source_id is not null;

-- ---------------------------------------------------------------------------
-- 3. Immutable collection history
-- ---------------------------------------------------------------------------

create table public.folio_collections (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null,
  folio_id uuid not null,

  collection_group_id uuid not null default gen_random_uuid(),
  amount numeric(14,2) not null,
  payment_method text not null,
  status text not null default 'posted',

  transaction_reference text,
  provider text,
  provider_payment_id text,
  provider_event_id text,

  source_table text,
  source_id uuid,
  idempotency_key text,

  collected_at timestamptz not null default now(),
  collected_by uuid,
  voided_at timestamptz,
  voided_by uuid,
  void_reason text,

  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),

  constraint folio_collections_amount_check
    check (amount > 0),

  constraint folio_collections_method_check
    check (
      payment_method in (
        'cash',
        'card',
        'upi',
        'bank_transfer',
        'payment_link',
        'other'
      )
    ),

  constraint folio_collections_status_check
    check (status in ('posted', 'voided', 'reversed')),

  constraint folio_collections_voided_check
    check (
      status = 'posted'
      or (
        voided_at is not null
        and nullif(trim(void_reason), '') is not null
      )
    ),

  constraint folio_collections_hotel_fkey
    foreign key (hotel_id)
    references public.hotels(id)
    on delete restrict,

  constraint folio_collections_folio_fkey
    foreign key (hotel_id, folio_id)
    references public.folios(hotel_id, id)
    on delete restrict,

  constraint folio_collections_collected_by_fkey
    foreign key (collected_by)
    references auth.users(id)
    on delete set null,

  constraint folio_collections_voided_by_fkey
    foreign key (voided_by)
    references auth.users(id)
    on delete set null,

  -- Required before refunds and webhook events can reference
  -- (hotel_id, folio_collection_id).
  constraint uq_folio_collections_hotel_id_id
    unique (hotel_id, id)
);

create index idx_folio_collections_folio_time
  on public.folio_collections(
    hotel_id,
    folio_id,
    collected_at desc
  );

create index idx_folio_collections_group
  on public.folio_collections(
    hotel_id,
    collection_group_id
  );

create unique index uq_folio_collections_idempotency
  on public.folio_collections(hotel_id, idempotency_key)
  where idempotency_key is not null;

create unique index uq_folio_collections_source
  on public.folio_collections(
    hotel_id,
    source_table,
    source_id
  )
  where source_table is not null
    and source_id is not null;

-- ---------------------------------------------------------------------------
-- 4. Discount approval workflow
-- ---------------------------------------------------------------------------

create table public.discount_approvals (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null,
  folio_id uuid not null,

  discount_type text not null,
  requested_value numeric(14,4) not null,
  requested_amount numeric(14,2) not null,
  reason text not null,

  status text not null default 'pending',
  requested_by uuid,
  requested_at timestamptz not null default now(),
  reviewed_by uuid,
  reviewed_at timestamptz,
  review_notes text,

  idempotency_key text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint discount_approvals_type_check
    check (discount_type in ('fixed', 'percentage')),

  constraint discount_approvals_amount_check
    check (
      requested_value > 0
      and requested_amount > 0
      and (
        discount_type <> 'percentage'
        or requested_value <= 100
      )
    ),

  constraint discount_approvals_reason_check
    check (nullif(trim(reason), '') is not null),

  constraint discount_approvals_status_check
    check (
      status in (
        'pending',
        'approved',
        'rejected',
        'cancelled'
      )
    ),

  constraint discount_approvals_review_check
    check (
      status = 'pending'
      or (
        reviewed_at is not null
        and reviewed_by is not null
      )
    ),

  constraint discount_approvals_hotel_fkey
    foreign key (hotel_id)
    references public.hotels(id)
    on delete restrict,

  constraint discount_approvals_folio_fkey
    foreign key (hotel_id, folio_id)
    references public.folios(hotel_id, id)
    on delete restrict,

  constraint discount_approvals_requested_by_fkey
    foreign key (requested_by)
    references auth.users(id)
    on delete set null,

  constraint discount_approvals_reviewed_by_fkey
    foreign key (reviewed_by)
    references auth.users(id)
    on delete set null
);

create unique index uq_discount_approvals_request
  on public.discount_approvals(hotel_id, idempotency_key);

create index idx_discount_approvals_pending
  on public.discount_approvals(
    hotel_id,
    status,
    requested_at
  );

-- ---------------------------------------------------------------------------
-- 5. Refund and credit-note records
-- ---------------------------------------------------------------------------

create table public.refunds (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null,
  folio_id uuid not null,
  folio_collection_id uuid,

  amount numeric(14,2) not null,
  payment_method text not null,
  status text not null default 'pending',
  reason text not null,

  transaction_reference text,
  provider text,
  provider_refund_id text,

  idempotency_key text not null,
  requested_at timestamptz not null default now(),
  requested_by uuid,
  processed_at timestamptz,
  processed_by uuid,
  failure_reason text,

  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint refunds_amount_check
    check (amount > 0),

  constraint refunds_method_check
    check (
      payment_method in (
        'cash',
        'card',
        'upi',
        'bank_transfer',
        'payment_link',
        'other'
      )
    ),

  constraint refunds_status_check
    check (
      status in (
        'pending',
        'processed',
        'failed',
        'cancelled'
      )
    ),

  constraint refunds_reason_check
    check (nullif(trim(reason), '') is not null),

  constraint refunds_processed_check
    check (
      status <> 'processed'
      or (
        processed_at is not null
        and processed_by is not null
      )
    ),

  constraint refunds_hotel_fkey
    foreign key (hotel_id)
    references public.hotels(id)
    on delete restrict,

  constraint refunds_folio_fkey
    foreign key (hotel_id, folio_id)
    references public.folios(hotel_id, id)
    on delete restrict,

  constraint refunds_collection_fkey
    foreign key (hotel_id, folio_collection_id)
    references public.folio_collections(hotel_id, id)
    on delete restrict,

  constraint refunds_requested_by_fkey
    foreign key (requested_by)
    references auth.users(id)
    on delete set null,

  constraint refunds_processed_by_fkey
    foreign key (processed_by)
    references auth.users(id)
    on delete set null
);

create unique index uq_refunds_hotel_id_id
  on public.refunds(hotel_id, id);

create unique index uq_refunds_request
  on public.refunds(hotel_id, idempotency_key);

create index idx_refunds_folio_status
  on public.refunds(hotel_id, folio_id, status);

create table public.credit_notes (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null,
  folio_id uuid not null,

  credit_note_number text not null,
  amount numeric(14,2) not null,
  status text not null default 'issued',
  reason text not null,

  idempotency_key text not null,
  issued_at timestamptz not null default now(),
  issued_by uuid,
  voided_at timestamptz,
  voided_by uuid,
  void_reason text,

  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint credit_notes_amount_check
    check (amount > 0),

  constraint credit_notes_status_check
    check (status in ('draft', 'issued', 'voided')),

  constraint credit_notes_reason_check
    check (nullif(trim(reason), '') is not null),

  constraint credit_notes_voided_check
    check (
      status <> 'voided'
      or (
        voided_at is not null
        and nullif(trim(void_reason), '') is not null
      )
    ),

  constraint credit_notes_hotel_fkey
    foreign key (hotel_id)
    references public.hotels(id)
    on delete restrict,

  constraint credit_notes_folio_fkey
    foreign key (hotel_id, folio_id)
    references public.folios(hotel_id, id)
    on delete restrict,

  constraint credit_notes_issued_by_fkey
    foreign key (issued_by)
    references auth.users(id)
    on delete set null,

  constraint credit_notes_voided_by_fkey
    foreign key (voided_by)
    references auth.users(id)
    on delete set null
);

create unique index uq_credit_notes_hotel_id_id
  on public.credit_notes(hotel_id, id);

create unique index uq_credit_notes_hotel_number
  on public.credit_notes(hotel_id, credit_note_number);

create unique index uq_credit_notes_request
  on public.credit_notes(hotel_id, idempotency_key);

-- ---------------------------------------------------------------------------
-- 6. Signed adjustments in the folio equation
-- ---------------------------------------------------------------------------

create table public.folio_adjustments (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null,
  folio_id uuid not null,

  adjustment_type text not null,
  amount numeric(14,2) not null,
  balance_effect numeric(14,2) not null,
  status text not null default 'posted',
  reason text not null,

  approval_id uuid,
  refund_id uuid,
  credit_note_id uuid,

  idempotency_key text not null,
  posted_at timestamptz not null default now(),
  posted_by uuid,
  voided_at timestamptz,
  voided_by uuid,
  void_reason text,

  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),

  constraint folio_adjustments_type_check
    check (
      adjustment_type in (
        'discount',
        'refund',
        'credit_note',
        'writeoff'
      )
    ),

  constraint folio_adjustments_amount_check
    check (amount > 0),

  constraint folio_adjustments_effect_check
    check (
      (
        adjustment_type = 'refund'
        and balance_effect = amount
      )
      or (
        adjustment_type in (
          'discount',
          'credit_note',
          'writeoff'
        )
        and balance_effect = -amount
      )
    ),

  constraint folio_adjustments_status_check
    check (status in ('posted', 'voided')),

  constraint folio_adjustments_voided_check
    check (
      status <> 'voided'
      or (
        voided_at is not null
        and nullif(trim(void_reason), '') is not null
      )
    ),

  constraint folio_adjustments_reason_check
    check (nullif(trim(reason), '') is not null),

  constraint folio_adjustments_hotel_fkey
    foreign key (hotel_id)
    references public.hotels(id)
    on delete restrict,

  constraint folio_adjustments_folio_fkey
    foreign key (hotel_id, folio_id)
    references public.folios(hotel_id, id)
    on delete restrict,

  constraint folio_adjustments_approval_fkey
    foreign key (approval_id)
    references public.discount_approvals(id)
    on delete restrict,

  constraint folio_adjustments_refund_fkey
    foreign key (hotel_id, refund_id)
    references public.refunds(hotel_id, id)
    on delete restrict,

  constraint folio_adjustments_credit_note_fkey
    foreign key (hotel_id, credit_note_id)
    references public.credit_notes(hotel_id, id)
    on delete restrict,

  constraint folio_adjustments_posted_by_fkey
    foreign key (posted_by)
    references auth.users(id)
    on delete set null,

  constraint folio_adjustments_voided_by_fkey
    foreign key (voided_by)
    references auth.users(id)
    on delete set null
);

create index idx_folio_adjustments_folio_status
  on public.folio_adjustments(
    hotel_id,
    folio_id,
    status,
    posted_at
  );

create unique index uq_folio_adjustments_request
  on public.folio_adjustments(hotel_id, idempotency_key);

-- ---------------------------------------------------------------------------
-- 7. Provider-neutral webhook reconciliation ledger
-- ---------------------------------------------------------------------------

create table public.payment_webhook_events (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid,
  provider text not null,
  provider_event_id text not null,
  event_type text not null,

  signature_valid boolean not null default false,
  payload_hash text not null,
  event_status text not null default 'received',
  processing_attempts integer not null default 0,

  received_at timestamptz not null default now(),
  processed_at timestamptz,
  last_error text,

  folio_id uuid,
  folio_collection_id uuid,
  refund_id uuid,

  safe_metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint payment_webhook_events_provider_check
    check (nullif(trim(provider), '') is not null),

  constraint payment_webhook_events_event_check
    check (
      nullif(trim(provider_event_id), '') is not null
      and nullif(trim(event_type), '') is not null
      and nullif(trim(payload_hash), '') is not null
    ),

  constraint payment_webhook_events_status_check
    check (
      event_status in (
        'received',
        'processed',
        'ignored',
        'failed'
      )
    ),

  constraint payment_webhook_events_attempts_check
    check (processing_attempts >= 0),

  constraint payment_webhook_events_hotel_fkey
    foreign key (hotel_id)
    references public.hotels(id)
    on delete restrict,

  constraint payment_webhook_events_folio_fkey
    foreign key (hotel_id, folio_id)
    references public.folios(hotel_id, id)
    on delete restrict,

  constraint payment_webhook_events_collection_fkey
    foreign key (hotel_id, folio_collection_id)
    references public.folio_collections(hotel_id, id)
    on delete restrict,

  constraint payment_webhook_events_refund_fkey
    foreign key (hotel_id, refund_id)
    references public.refunds(hotel_id, id)
    on delete restrict
);

create unique index uq_payment_webhook_provider_event
  on public.payment_webhook_events(
    provider,
    provider_event_id
  );

create index idx_payment_webhook_status_received
  on public.payment_webhook_events(
    event_status,
    received_at
  );

-- ---------------------------------------------------------------------------
-- 8. Immutable folio event ledger
-- ---------------------------------------------------------------------------

create table public.folio_events (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null,
  folio_id uuid not null,
  event_type text not null,
  entity_type text,
  entity_id uuid,
  actor_id uuid,
  event_snapshot jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),

  constraint folio_events_type_check
    check (nullif(trim(event_type), '') is not null),

  constraint folio_events_hotel_fkey
    foreign key (hotel_id)
    references public.hotels(id)
    on delete restrict,

  constraint folio_events_folio_fkey
    foreign key (hotel_id, folio_id)
    references public.folios(hotel_id, id)
    on delete restrict,

  constraint folio_events_actor_fkey
    foreign key (actor_id)
    references auth.users(id)
    on delete set null
);

create index idx_folio_events_folio_time
  on public.folio_events(
    hotel_id,
    folio_id,
    created_at
  );

-- Composite collection identity is declared inside the table before child FKs.

-- ---------------------------------------------------------------------------
-- 9. Update timestamp helper
-- ---------------------------------------------------------------------------

create or replace function private.day11_set_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
begin
  new.updated_at := now();
  return new;
end;
$function$;

create trigger folios_set_updated_at
before update on public.folios
for each row
execute function private.day11_set_updated_at();

create trigger folio_items_set_updated_at
before update on public.folio_items
for each row
execute function private.day11_set_updated_at();

create trigger discount_approvals_set_updated_at
before update on public.discount_approvals
for each row
execute function private.day11_set_updated_at();

create trigger refunds_set_updated_at
before update on public.refunds
for each row
execute function private.day11_set_updated_at();

create trigger credit_notes_set_updated_at
before update on public.credit_notes
for each row
execute function private.day11_set_updated_at();

create trigger payment_webhook_events_set_updated_at
before update on public.payment_webhook_events
for each row
execute function private.day11_set_updated_at();

-- ---------------------------------------------------------------------------
-- 10. Authoritative folio equation
-- ---------------------------------------------------------------------------

create or replace function private.recalculate_folio(
  target_hotel_id uuid,
  target_folio_id uuid
)
returns public.folios
language plpgsql
security definer
set search_path = ''
as $function$
declare
  folio_row public.folios%rowtype;
  charges_value numeric(14,2);
  discount_value numeric(14,2);
  tax_value numeric(14,2);
  collection_value numeric(14,2);
  refund_value numeric(14,2);
  credit_value numeric(14,2);
  balance_value numeric(14,2);
begin
  select folio.*
  into folio_row
  from public.folios folio
  where folio.hotel_id = target_hotel_id
    and folio.id = target_folio_id
  for update;

  if not found then
    raise exception 'Folio was not found.';
  end if;

  select
    coalesce(
      sum(item.amount) filter (
        where item.posting_status = 'posted'
          and item.item_kind = 'charge'
      ),
      0
    ),
    coalesce(
      sum(item.amount) filter (
        where item.posting_status = 'posted'
          and item.item_kind = 'tax'
      ),
      0
    )
  into charges_value, tax_value
  from public.folio_items item
  where item.hotel_id = target_hotel_id
    and item.folio_id = target_folio_id;

  select coalesce(sum(collection.amount), 0)
  into collection_value
  from public.folio_collections collection
  where collection.hotel_id = target_hotel_id
    and collection.folio_id = target_folio_id
    and collection.status = 'posted';

  select
    coalesce(
      sum(adjustment.amount) filter (
        where adjustment.status = 'posted'
          and adjustment.adjustment_type = 'discount'
      ),
      0
    ),
    coalesce(
      sum(adjustment.amount) filter (
        where adjustment.status = 'posted'
          and adjustment.adjustment_type = 'refund'
      ),
      0
    ),
    coalesce(
      sum(adjustment.amount) filter (
        where adjustment.status = 'posted'
          and adjustment.adjustment_type in (
            'credit_note',
            'writeoff'
          )
      ),
      0
    )
  into discount_value, refund_value, credit_value
  from public.folio_adjustments adjustment
  where adjustment.hotel_id = target_hotel_id
    and adjustment.folio_id = target_folio_id;

  balance_value :=
    charges_value
    - discount_value
    + tax_value
    - collection_value
    + refund_value
    - credit_value;

  update public.folios
  set
    charges_amount = charges_value,
    discount_amount = discount_value,
    tax_amount = tax_value,
    collection_amount = collection_value,
    refund_amount = refund_value,
    credit_amount = credit_value,
    balance_amount = balance_value,
    lock_version = lock_version + 1
  where hotel_id = target_hotel_id
    and id = target_folio_id
  returning *
  into folio_row;

  return folio_row;
end;
$function$;

revoke all on function private.recalculate_folio(uuid, uuid)
from public, anon, authenticated;

grant execute on function private.recalculate_folio(uuid, uuid)
to service_role;

create or replace function private.recalculate_folio_from_child()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  hotel_id_value uuid;
  folio_id_value uuid;
begin
  hotel_id_value :=
    coalesce(new.hotel_id, old.hotel_id);
  folio_id_value :=
    coalesce(new.folio_id, old.folio_id);

  perform private.recalculate_folio(
    hotel_id_value,
    folio_id_value
  );

  return coalesce(new, old);
end;
$function$;

create trigger folio_items_recalculate
after insert or update or delete
on public.folio_items
for each row
execute function private.recalculate_folio_from_child();

create trigger folio_collections_recalculate
after insert or update or delete
on public.folio_collections
for each row
execute function private.recalculate_folio_from_child();

create trigger folio_adjustments_recalculate
after insert or update or delete
on public.folio_adjustments
for each row
execute function private.recalculate_folio_from_child();

-- ---------------------------------------------------------------------------
-- 11. Event helper
-- ---------------------------------------------------------------------------

create or replace function private.write_folio_event(
  target_hotel_id uuid,
  target_folio_id uuid,
  event_type_value text,
  entity_type_value text default null,
  entity_id_value uuid default null,
  snapshot_value jsonb default '{}'::jsonb,
  metadata_value jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  event_id_value uuid;
begin
  insert into public.folio_events (
    hotel_id,
    folio_id,
    event_type,
    entity_type,
    entity_id,
    actor_id,
    event_snapshot,
    metadata
  )
  values (
    target_hotel_id,
    target_folio_id,
    event_type_value,
    entity_type_value,
    entity_id_value,
    auth.uid(),
    coalesce(snapshot_value, '{}'::jsonb),
    coalesce(metadata_value, '{}'::jsonb)
  )
  returning id into event_id_value;

  return event_id_value;
end;
$function$;

revoke all on function private.write_folio_event(
  uuid,
  uuid,
  text,
  text,
  uuid,
  jsonb,
  jsonb
)
from public, anon, authenticated;

grant execute on function private.write_folio_event(
  uuid,
  uuid,
  text,
  text,
  uuid,
  jsonb,
  jsonb
)
to service_role;

-- ---------------------------------------------------------------------------
-- 12. Ensure/reuse one authoritative folio per stay
-- ---------------------------------------------------------------------------

create or replace function public.ensure_guest_folio(
  target_hotel_id uuid,
  target_guest_session_id uuid,
  request_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  existing_folio public.folios%rowtype;
  stay_row public.guest_sessions%rowtype;
  hotel_row public.hotels%rowtype;
  generated_id uuid := gen_random_uuid();
  request_id_value text;
begin
  if not private.user_has_any_permission(
    target_hotel_id,
    array[
      'payments.manage',
      'invoices.manage',
      'checkout.manage'
    ]::text[]
  ) then
    raise exception 'Folio management access denied.';
  end if;

  request_id_value :=
    coalesce(
      nullif(trim(request_id), ''),
      generated_id::text
    );

  perform pg_advisory_xact_lock(
    hashtextextended(
      'stayqr:folio:'
      || target_hotel_id::text
      || ':'
      || target_guest_session_id::text,
      0
    )
  );

  select folio.*
  into existing_folio
  from public.folios folio
  where folio.hotel_id = target_hotel_id
    and folio.guest_session_id = target_guest_session_id
  limit 1;

  if existing_folio.id is not null then
    return to_jsonb(existing_folio)
      || jsonb_build_object(
        'ok', true,
        'idempotent', true,
        'request_id', request_id_value
      );
  end if;

  select stay.*
  into stay_row
  from public.guest_sessions stay
  where stay.hotel_id = target_hotel_id
    and stay.id = target_guest_session_id
  for share;

  if not found then
    raise exception 'Guest session was not found.';
  end if;

  if stay_row.guest_id is null then
    raise exception 'Guest session has no guest.';
  end if;

  select hotel.*
  into hotel_row
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
    metadata
  )
  values (
    generated_id,
    target_hotel_id,
    'FOL-'
      || to_char(
        now() at time zone hotel_row.timezone,
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
    jsonb_build_object(
      'source', 'ensure_guest_folio',
      'request_id', request_id_value,
      'day', 11
    )
  )
  returning *
  into existing_folio;

  perform private.write_folio_event(
    target_hotel_id,
    existing_folio.id,
    'folio.opened',
    'guest_session',
    target_guest_session_id,
    to_jsonb(existing_folio),
    jsonb_build_object(
      'request_id', request_id_value
    )
  );

  return to_jsonb(existing_folio)
    || jsonb_build_object(
      'ok', true,
      'idempotent', false,
      'request_id', request_id_value
    );
end;
$function$;

revoke all on function public.ensure_guest_folio(uuid, uuid, text)
from public, anon;

grant execute on function public.ensure_guest_folio(uuid, uuid, text)
to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 13. Authoritative snapshot RPC
-- ---------------------------------------------------------------------------

create or replace function public.get_guest_folio_snapshot(
  target_hotel_id uuid,
  target_folio_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  result_value jsonb;
begin
  if not private.user_has_any_permission(
    target_hotel_id,
    array[
      'payments.view',
      'payments.manage',
      'invoices.view',
      'invoices.manage',
      'checkout.manage'
    ]::text[]
  ) then
    raise exception 'Folio view access denied.';
  end if;

  select jsonb_build_object(
    'folio', to_jsonb(folio),
    'items', coalesce((
      select jsonb_agg(
        to_jsonb(item)
        order by item.service_at, item.created_at, item.id
      )
      from public.folio_items item
      where item.hotel_id = folio.hotel_id
        and item.folio_id = folio.id
    ), '[]'::jsonb),
    'collections', coalesce((
      select jsonb_agg(
        to_jsonb(collection)
        order by collection.collected_at, collection.id
      )
      from public.folio_collections collection
      where collection.hotel_id = folio.hotel_id
        and collection.folio_id = folio.id
    ), '[]'::jsonb),
    'adjustments', coalesce((
      select jsonb_agg(
        to_jsonb(adjustment)
        order by adjustment.posted_at, adjustment.id
      )
      from public.folio_adjustments adjustment
      where adjustment.hotel_id = folio.hotel_id
        and adjustment.folio_id = folio.id
    ), '[]'::jsonb),
    'discount_approvals', coalesce((
      select jsonb_agg(
        to_jsonb(approval)
        order by approval.requested_at, approval.id
      )
      from public.discount_approvals approval
      where approval.hotel_id = folio.hotel_id
        and approval.folio_id = folio.id
    ), '[]'::jsonb),
    'refunds', coalesce((
      select jsonb_agg(
        to_jsonb(refund)
        order by refund.requested_at, refund.id
      )
      from public.refunds refund
      where refund.hotel_id = folio.hotel_id
        and refund.folio_id = folio.id
    ), '[]'::jsonb),
    'credit_notes', coalesce((
      select jsonb_agg(
        to_jsonb(credit)
        order by credit.issued_at, credit.id
      )
      from public.credit_notes credit
      where credit.hotel_id = folio.hotel_id
        and credit.folio_id = folio.id
    ), '[]'::jsonb),
    'events', coalesce((
      select jsonb_agg(
        to_jsonb(event_record)
        order by event_record.created_at, event_record.id
      )
      from public.folio_events event_record
      where event_record.hotel_id = folio.hotel_id
        and event_record.folio_id = folio.id
    ), '[]'::jsonb),
    'equation', jsonb_build_object(
      'charges', folio.charges_amount,
      'discounts', folio.discount_amount,
      'taxes', folio.tax_amount,
      'collections', folio.collection_amount,
      'refunds', folio.refund_amount,
      'credits', folio.credit_amount,
      'balance', folio.balance_amount,
      'formula',
        'charges - discounts + taxes - collections + refunds - credits = balance'
    )
  )
  into result_value
  from public.folios folio
  where folio.hotel_id = target_hotel_id
    and folio.id = target_folio_id;

  if result_value is null then
    raise exception 'Folio was not found.';
  end if;

  return result_value;
end;
$function$;

revoke all on function public.get_guest_folio_snapshot(uuid, uuid)
from public, anon;

grant execute on function public.get_guest_folio_snapshot(uuid, uuid)
to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 14. RLS
-- ---------------------------------------------------------------------------

alter table public.folios enable row level security;
alter table public.folio_items enable row level security;
alter table public.folio_collections enable row level security;
alter table public.discount_approvals enable row level security;
alter table public.refunds enable row level security;
alter table public.credit_notes enable row level security;
alter table public.folio_adjustments enable row level security;
alter table public.payment_webhook_events enable row level security;
alter table public.folio_events enable row level security;

create policy stayqr_folios_select
on public.folios
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

create policy stayqr_folios_manage
on public.folios
for all
to authenticated
using (
  private.user_has_any_permission(
    hotel_id,
    array[
      'payments.manage',
      'invoices.manage',
      'checkout.manage'
    ]::text[]
  )
)
with check (
  private.user_has_any_permission(
    hotel_id,
    array[
      'payments.manage',
      'invoices.manage',
      'checkout.manage'
    ]::text[]
  )
);

create policy stayqr_folio_items_select
on public.folio_items
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

create policy stayqr_folio_items_manage
on public.folio_items
for all
to authenticated
using (
  private.user_has_any_permission(
    hotel_id,
    array[
      'payments.manage',
      'invoices.manage',
      'checkout.manage'
    ]::text[]
  )
)
with check (
  private.user_has_any_permission(
    hotel_id,
    array[
      'payments.manage',
      'invoices.manage',
      'checkout.manage'
    ]::text[]
  )
);

create policy stayqr_folio_collections_select
on public.folio_collections
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

create policy stayqr_folio_collections_manage
on public.folio_collections
for all
to authenticated
using (
  private.user_has_any_permission(
    hotel_id,
    array[
      'payments.manage',
      'invoices.manage',
      'checkout.manage'
    ]::text[]
  )
)
with check (
  private.user_has_any_permission(
    hotel_id,
    array[
      'payments.manage',
      'invoices.manage',
      'checkout.manage'
    ]::text[]
  )
);

create policy stayqr_discount_approvals_select
on public.discount_approvals
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

create policy stayqr_discount_approvals_manage
on public.discount_approvals
for all
to authenticated
using (
  private.user_has_any_permission(
    hotel_id,
    array[
      'payments.manage',
      'invoices.manage',
      'checkout.manage'
    ]::text[]
  )
)
with check (
  private.user_has_any_permission(
    hotel_id,
    array[
      'payments.manage',
      'invoices.manage',
      'checkout.manage'
    ]::text[]
  )
);

create policy stayqr_refunds_select
on public.refunds
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

create policy stayqr_refunds_manage
on public.refunds
for all
to authenticated
using (
  private.user_has_any_permission(
    hotel_id,
    array[
      'payments.manage',
      'invoices.manage',
      'checkout.manage'
    ]::text[]
  )
)
with check (
  private.user_has_any_permission(
    hotel_id,
    array[
      'payments.manage',
      'invoices.manage',
      'checkout.manage'
    ]::text[]
  )
);

create policy stayqr_credit_notes_select
on public.credit_notes
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

create policy stayqr_credit_notes_manage
on public.credit_notes
for all
to authenticated
using (
  private.user_has_any_permission(
    hotel_id,
    array[
      'payments.manage',
      'invoices.manage',
      'checkout.manage'
    ]::text[]
  )
)
with check (
  private.user_has_any_permission(
    hotel_id,
    array[
      'payments.manage',
      'invoices.manage',
      'checkout.manage'
    ]::text[]
  )
);

create policy stayqr_folio_adjustments_select
on public.folio_adjustments
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

create policy stayqr_folio_adjustments_manage
on public.folio_adjustments
for all
to authenticated
using (
  private.user_has_any_permission(
    hotel_id,
    array[
      'payments.manage',
      'invoices.manage',
      'checkout.manage'
    ]::text[]
  )
)
with check (
  private.user_has_any_permission(
    hotel_id,
    array[
      'payments.manage',
      'invoices.manage',
      'checkout.manage'
    ]::text[]
  )
);

create policy stayqr_payment_webhooks_select
on public.payment_webhook_events
for select
to authenticated
using (
  hotel_id is not null
  and private.user_has_any_permission(
    hotel_id,
    array[
      'payments.view',
      'payments.manage',
      'invoices.view',
      'invoices.manage'
    ]::text[]
  )
);

create policy stayqr_payment_webhooks_manage
on public.payment_webhook_events
for all
to service_role
using (true)
with check (true);

create policy stayqr_folio_events_select
on public.folio_events
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

-- Immutable event ledger: authenticated users receive SELECT only.
-- Event insertion occurs through security-definer server functions.

-- ---------------------------------------------------------------------------
-- 15. Grants
-- ---------------------------------------------------------------------------

revoke all on public.folios from public, anon;
revoke all on public.folio_items from public, anon;
revoke all on public.folio_collections from public, anon;
revoke all on public.discount_approvals from public, anon;
revoke all on public.refunds from public, anon;
revoke all on public.credit_notes from public, anon;
revoke all on public.folio_adjustments from public, anon;
revoke all on public.payment_webhook_events from public, anon;
revoke all on public.folio_events from public, anon;

grant select, insert, update, delete
on public.folios,
   public.folio_items,
   public.folio_collections,
   public.discount_approvals,
   public.refunds,
   public.credit_notes,
   public.folio_adjustments
to authenticated;

grant select
on public.payment_webhook_events,
   public.folio_events
to authenticated;

grant all
on public.folios,
   public.folio_items,
   public.folio_collections,
   public.discount_approvals,
   public.refunds,
   public.credit_notes,
   public.folio_adjustments,
   public.payment_webhook_events,
   public.folio_events
to service_role;

comment on table public.folios is
'Day 11 authoritative stay folio header. Summary columns are maintained from posted folio items, collections and signed adjustments.';

comment on table public.folio_items is
'Day 11 authoritative charge/tax line ledger with idempotent legacy source linkage.';

comment on constraint uq_folio_collections_hotel_id_id on public.folio_collections is
'Hotel-scoped collection identity required by refund and webhook foreign keys.';

comment on table public.folio_collections is
'Day 11 immutable collection history supporting partial, split and multi-method settlement groups.';

comment on table public.folio_adjustments is
'Day 11 signed balance effects: discount/credit/writeoff decrease balance; refund increases balance.';

comment on function private.recalculate_folio(uuid, uuid) is
'Day 11 authoritative equation: charges - discounts + taxes - collections + refunds - credits = balance.';

comment on function public.ensure_guest_folio(uuid, uuid, text) is
'Creates or safely reuses the one authoritative folio for a guest session. Does not backfill legacy charge sources.';

comment on function public.get_guest_folio_snapshot(uuid, uuid) is
'Returns the authoritative Day 11 folio header, line items, collections, adjustments, approvals, refunds, credits, events and reconciliation equation.';

commit;
