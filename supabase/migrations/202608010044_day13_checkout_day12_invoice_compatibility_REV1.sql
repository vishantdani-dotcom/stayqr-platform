-- ============================================================================
-- StayQR v1.0
-- Day 13 Migration 044 REV1
-- Day 5 Atomic Checkout -> Day 12 Financial-Year Invoice Compatibility
--
-- INCIDENT
-- The accepted Day 5 checkout_guest_session RPC inserts public.invoices using
-- the original invoice schema. Day 12 Migration 036 later made
-- financial_year_start, financial_year_label, invoice_date and currency_code
-- NOT NULL. The browser checkout therefore stopped at invoice INSERT with:
--   null value in column "financial_year_start" of relation "invoices"
--
-- OUTCOME
-- 1. Only the legacy atomic checkout insert path is adapted.
-- 2. A Day 11 folio is ensured/reused for the stay.
-- 3. Day 12 financial-year numbering replaces the old random invoice number.
-- 4. Required Day 12 invoice identity/snapshot fields are populated.
-- 5. After the checkout event is written, invoice lines are normalized and the
--    paid invoice receives an immutable snapshot, hash, verification identity
--    and invoice event.
-- 6. The existing checkout_guest_session signature and frontend remain intact.
-- 7. Installing this migration does not update any existing operational row.
--
-- RUN WITH
-- Supabase SQL Editor role: postgres
--
-- EXPECTED RESULT
-- 24 rows; every passed value = true.
-- ============================================================================

begin;

set local lock_timeout = '10s';
set local statement_timeout = '180s';

select pg_advisory_xact_lock(
  hashtext('stayqr:202608010044:checkout-day12-invoice-compatibility')
);

-- --------------------------------------------------------------------------
-- 0. Preconditions
-- --------------------------------------------------------------------------

do $preflight$
begin
  if to_regclass('public.invoices') is null
     or to_regclass('public.invoice_items') is null
     or to_regclass('public.invoice_verifications') is null
     or to_regclass('public.invoice_events') is null
     or to_regclass('public.reservation_checkout_events') is null
     or to_regclass('public.folios') is null
  then
    raise exception
      'Migration 044 stopped: required Day 11/12 checkout and invoice tables are missing.';
  end if;

  if to_regprocedure(
       'public.checkout_guest_session(uuid,uuid,numeric,text,numeric,boolean,text,text,text,boolean)'
     ) is null
     or to_regprocedure(
       'private.day11_ensure_folio_for_source(uuid,uuid,text)'
     ) is null
     or to_regprocedure(
       'private.day12_next_invoice_number(uuid,timestamp with time zone)'
     ) is null
     or to_regprocedure(
       'private.day12_build_invoice_snapshot(uuid,uuid,timestamp with time zone,uuid)'
     ) is null
     or to_regprocedure(
       'private.day12_hash_snapshot(jsonb)'
     ) is null
  then
    raise exception
      'Migration 044 stopped: required accepted Day 5/11/12 functions are missing.';
  end if;

  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'invoices'
      and column_name = 'financial_year_start'
      and is_nullable = 'NO'
  ) then
    raise exception
      'Migration 044 stopped: Day 12 financial-year invoice contract is not installed.';
  end if;
end;
$preflight$;

-- --------------------------------------------------------------------------
-- 1. Prepare only the original atomic-checkout invoice INSERT.
--    Authoritative Day 12 issue_folio_invoice inserts already provide all of
--    these fields and pass through unchanged.
-- --------------------------------------------------------------------------

create or replace function private.day13_prepare_atomic_checkout_invoice()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  hotel_row public.hotels%rowtype;
  folio_row public.folios%rowtype;
  number_value jsonb;
  settings_snapshot_value jsonb := '{}'::jsonb;
  seller_snapshot_value jsonb := '{}'::jsonb;
  buyer_snapshot_value jsonb := '{}'::jsonb;
  issue_at_value timestamptz;
begin
  -- Day 12-native issuance is already complete and must remain untouched.
  if new.financial_year_start is not null
     and nullif(trim(new.financial_year_label), '') is not null
     and new.invoice_date is not null
     and nullif(trim(new.currency_code), '') is not null
  then
    return new;
  end if;

  -- Limit compatibility handling to the old paid atomic checkout shape.
  if new.guest_session_id is null
     or new.folio_id is not null
     or lower(coalesce(new.invoice_status, '')) <> 'paid'
     or lower(coalesce(new.payment_status, '')) <> 'paid'
     or new.finalized_at is not null
  then
    return new;
  end if;

  select hotel.*
  into strict hotel_row
  from public.hotels hotel
  where hotel.id = new.hotel_id;

  folio_row := private.day11_ensure_folio_for_source(
    new.hotel_id,
    new.guest_session_id,
    'checkout_guest_session_day13_compatibility'
  );

  issue_at_value := coalesce(
    new.settled_at,
    new.checkout_time,
    new.created_at,
    now()
  );

  number_value := private.day12_next_invoice_number(
    new.hotel_id,
    issue_at_value
  );

  select coalesce(
    (
      select to_jsonb(setting)
      from public.hotel_settings setting
      where setting.hotel_id = new.hotel_id
    ),
    '{}'::jsonb
  )
  into settings_snapshot_value;

  seller_snapshot_value :=
    to_jsonb(hotel_row)
    || jsonb_build_object(
      'settings', settings_snapshot_value
    );

  select coalesce(
    (
      select to_jsonb(guest)
      from public.guests guest
      where guest.hotel_id = new.hotel_id
        and guest.id = new.guest_id
    ),
    '{}'::jsonb
  )
  into buyer_snapshot_value;

  new.folio_id := folio_row.id;
  new.invoice_number := number_value ->> 'invoice_number';
  new.invoice_origin := 'authoritative';
  new.idempotency_key := coalesce(
    nullif(trim(new.idempotency_key), ''),
    'stayqr:checkout:' || new.guest_session_id::text
  );

  new.financial_year_start :=
    (number_value ->> 'financial_year_start')::integer;
  new.financial_year_label :=
    number_value ->> 'financial_year_label';
  new.invoice_date :=
    (issue_at_value at time zone coalesce(hotel_row.timezone, 'Asia/Kolkata'))::date;
  new.currency_code :=
    coalesce(nullif(trim(hotel_row.currency_code), ''), 'INR');

  if coalesce(new.seller_snapshot, '{}'::jsonb) = '{}'::jsonb then
    new.seller_snapshot := seller_snapshot_value;
  end if;

  if coalesce(new.buyer_snapshot, '{}'::jsonb) = '{}'::jsonb then
    new.buyer_snapshot := buyer_snapshot_value;
  end if;

  new.tax_mode := case
    when coalesce(new.tax_amount, 0) > 0
      then 'legacy_unclassified'
    else 'exempt'
  end;

  new.taxable_amount := greatest(
    round(
      coalesce(new.subtotal_amount, 0)
      - coalesce(new.discount_amount, 0),
      2
    ),
    0
  );

  new.metadata :=
    coalesce(new.metadata, '{}'::jsonb)
    || jsonb_build_object(
      'source', 'checkout_guest_session',
      'compatibility_migration', '044',
      'day13_checkout_compatibility', true,
      'original_invoice_number', new.invoice_number,
      'folio_id', folio_row.id
    );

  new.updated_at := now();
  return new;
end;
$function$;

revoke all on function
  private.day13_prepare_atomic_checkout_invoice()
from public, anon, authenticated;

drop trigger if exists
  invoices_day13_prepare_atomic_checkout
on public.invoices;

create trigger invoices_day13_prepare_atomic_checkout
before insert
on public.invoices
for each row
execute function private.day13_prepare_atomic_checkout_invoice();

-- --------------------------------------------------------------------------
-- 2. Finalize the compatibility invoice only after the atomic checkout has
--    created all invoice lines and its checkout event. Any failure here rolls
--    back the entire checkout transaction.
-- --------------------------------------------------------------------------

create or replace function private.day13_finalize_atomic_checkout_invoice()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  invoice_row public.invoices%rowtype;
  finalized_at_value timestamptz;
  verification_token_value uuid := gen_random_uuid();
  snapshot_value jsonb;
  snapshot_hash_value text;
  actor_id_value uuid;
begin
  if new.invoice_id is null then
    return new;
  end if;

  select invoice.*
  into invoice_row
  from public.invoices invoice
  where invoice.hotel_id = new.hotel_id
    and invoice.id = new.invoice_id
  for update;

  if not found
     or invoice_row.finalized_at is not null
     or coalesce(
       (invoice_row.metadata ->> 'day13_checkout_compatibility')::boolean,
       false
     ) is not true
  then
    return new;
  end if;

  -- Give old checkout lines deterministic Day 12 line identities and source
  -- snapshots before the invoice becomes immutable.
  with numbered as (
    select
      item.id,
      row_number() over (
        order by item.created_at, item.id
      )::integer as line_number_value
    from public.invoice_items item
    where item.hotel_id = new.hotel_id
      and item.invoice_id = new.invoice_id
  )
  update public.invoice_items item
  set
    line_number = numbered.line_number_value,
    taxable_amount = greatest(coalesce(item.amount, 0), 0),
    tax_rate_percent = greatest(
      least(coalesce(invoice_row.tax_percent, 0), 100),
      0
    ),
    snapshot_json = jsonb_build_object(
      'schema', 'stayqr.invoice.line.snapshot',
      'version', 1,
      'source', 'checkout_guest_session',
      'invoice_id', item.invoice_id,
      'line_number', numbered.line_number_value,
      'item_type', item.item_type,
      'description', item.description,
      'quantity', item.quantity,
      'unit_price', item.unit_price,
      'amount', item.amount,
      'source_id', item.source_id
    ),
    metadata = coalesce(item.metadata, '{}'::jsonb)
      || jsonb_build_object(
        'compatibility_migration', '044',
        'day13_checkout_compatibility', true
      ),
    updated_at = now()
  from numbered
  where item.id = numbered.id;

  finalized_at_value := coalesce(
    new.checked_out_at,
    invoice_row.checkout_time,
    now()
  );

  actor_id_value :=
    private.day11_valid_auth_actor(new.checked_out_by);

  snapshot_value := private.day12_build_invoice_snapshot(
    new.hotel_id,
    new.invoice_id,
    finalized_at_value,
    verification_token_value
  );

  snapshot_hash_value :=
    private.day12_hash_snapshot(snapshot_value);

  update public.invoices
  set
    snapshot_json = snapshot_value,
    snapshot_hash = snapshot_hash_value,
    verification_token = verification_token_value,
    finalized_at = finalized_at_value,
    finalized_by = actor_id_value,
    metadata = metadata
      || jsonb_build_object(
        'immutable', true,
        'snapshot_hash', snapshot_hash_value,
        'finalized_by_migration', '044'
      )
  where hotel_id = new.hotel_id
    and id = new.invoice_id;

  insert into public.invoice_verifications (
    hotel_id,
    invoice_id,
    verification_token,
    snapshot_hash,
    status,
    metadata
  )
  values (
    new.hotel_id,
    new.invoice_id,
    verification_token_value,
    snapshot_hash_value,
    'active',
    jsonb_build_object(
      'authoritative', true,
      'source', 'checkout_guest_session',
      'migration', '044'
    )
  )
  on conflict (hotel_id, invoice_id) do nothing;

  insert into public.invoice_events (
    hotel_id,
    invoice_id,
    event_type,
    actor_id,
    event_snapshot,
    metadata
  )
  values (
    new.hotel_id,
    new.invoice_id,
    'invoice.issued',
    actor_id_value,
    snapshot_value,
    jsonb_build_object(
      'source', 'checkout_guest_session',
      'checkout_event_id', new.id,
      'migration', '044'
    )
  );

  return new;
end;
$function$;

revoke all on function
  private.day13_finalize_atomic_checkout_invoice()
from public, anon, authenticated;

drop trigger if exists
  reservation_checkout_events_day13_finalize_invoice
on public.reservation_checkout_events;

create trigger reservation_checkout_events_day13_finalize_invoice
after insert
on public.reservation_checkout_events
for each row
execute function private.day13_finalize_atomic_checkout_invoice();

commit;

-- --------------------------------------------------------------------------
-- 3. Read-only structural acceptance
-- --------------------------------------------------------------------------

with checks(test_order, test_name, passed, details) as (
  select 1, '01_prepare_function_exists',
    to_regprocedure('private.day13_prepare_atomic_checkout_invoice()') is not null,
    'Atomic-checkout invoice preparation function exists.'

  union all select 2, '02_finalize_function_exists',
    to_regprocedure('private.day13_finalize_atomic_checkout_invoice()') is not null,
    'Atomic-checkout invoice finalization function exists.'

  union all select 3, '03_prepare_trigger_exists',
    exists (
      select 1 from pg_trigger
      where tgname = 'invoices_day13_prepare_atomic_checkout'
        and tgrelid = 'public.invoices'::regclass
        and not tgisinternal
    ),
    'Invoice preparation trigger exists.'

  union all select 4, '04_finalize_trigger_exists',
    exists (
      select 1 from pg_trigger
      where tgname = 'reservation_checkout_events_day13_finalize_invoice'
        and tgrelid = 'public.reservation_checkout_events'::regclass
        and not tgisinternal
    ),
    'Checkout-event finalization trigger exists.'

  union all select 5, '05_prepare_trigger_enabled',
    exists (
      select 1 from pg_trigger
      where tgname = 'invoices_day13_prepare_atomic_checkout'
        and tgenabled <> 'D'
    ),
    'Invoice preparation trigger is enabled.'

  union all select 6, '06_finalize_trigger_enabled',
    exists (
      select 1 from pg_trigger
      where tgname = 'reservation_checkout_events_day13_finalize_invoice'
        and tgenabled <> 'D'
    ),
    'Checkout-event finalization trigger is enabled.'

  union all select 7, '07_prepare_security_definer',
    coalesce((select prosecdef from pg_proc where oid = 'private.day13_prepare_atomic_checkout_invoice()'::regprocedure), false),
    'Preparation function uses SECURITY DEFINER.'

  union all select 8, '08_finalize_security_definer',
    coalesce((select prosecdef from pg_proc where oid = 'private.day13_finalize_atomic_checkout_invoice()'::regprocedure), false),
    'Finalization function uses SECURITY DEFINER.'

  union all select 9, '09_prepare_private_from_authenticated',
    not has_function_privilege('authenticated','private.day13_prepare_atomic_checkout_invoice()','EXECUTE'),
    'Authenticated browsers cannot invoke the trigger function directly.'

  union all select 10, '10_finalize_private_from_authenticated',
    not has_function_privilege('authenticated','private.day13_finalize_atomic_checkout_invoice()','EXECUTE'),
    'Authenticated browsers cannot invoke the finalizer directly.'

  union all select 11, '11_prepare_private_from_anon',
    not has_function_privilege('anon','private.day13_prepare_atomic_checkout_invoice()','EXECUTE'),
    'Anonymous users cannot invoke the preparation function.'

  union all select 12, '12_finalize_private_from_anon',
    not has_function_privilege('anon','private.day13_finalize_atomic_checkout_invoice()','EXECUTE'),
    'Anonymous users cannot invoke the finalization function.'

  union all select 13, '13_accepted_checkout_signature_preserved',
    to_regprocedure('public.checkout_guest_session(uuid,uuid,numeric,text,numeric,boolean,text,text,text,boolean)') is not null,
    'Frontend checkout RPC signature remains unchanged.'

  union all select 14, '14_folio_ensure_dependency_present',
    position('day11_ensure_folio_for_source' in pg_get_functiondef('private.day13_prepare_atomic_checkout_invoice()'::regprocedure)) > 0,
    'Compatibility path ensures/reuses the Day 11 folio.'

  union all select 15, '15_financial_number_dependency_present',
    position('day12_next_invoice_number' in pg_get_functiondef('private.day13_prepare_atomic_checkout_invoice()'::regprocedure)) > 0,
    'Compatibility path uses Day 12 financial-year numbering.'

  union all select 16, '16_authoritative_origin_present',
    position('authoritative' in pg_get_functiondef('private.day13_prepare_atomic_checkout_invoice()'::regprocedure)) > 0,
    'Prepared checkout invoice is classified as authoritative.'

  union all select 17, '17_snapshot_builder_dependency_present',
    position('day12_build_invoice_snapshot' in pg_get_functiondef('private.day13_finalize_atomic_checkout_invoice()'::regprocedure)) > 0,
    'Finalizer builds the Day 12 immutable snapshot.'

  union all select 18, '18_snapshot_hash_dependency_present',
    position('day12_hash_snapshot' in pg_get_functiondef('private.day13_finalize_atomic_checkout_invoice()'::regprocedure)) > 0,
    'Finalizer hashes the immutable snapshot.'

  union all select 19, '19_verification_ledger_present',
    position('invoice_verifications' in pg_get_functiondef('private.day13_finalize_atomic_checkout_invoice()'::regprocedure)) > 0,
    'Finalizer creates invoice verification identity.'

  union all select 20, '20_invoice_event_ledger_present',
    position('invoice_events' in pg_get_functiondef('private.day13_finalize_atomic_checkout_invoice()'::regprocedure)) > 0,
    'Finalizer creates an immutable invoice event.'

  union all select 21, '21_financial_year_not_null_retained',
    exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name='invoices'
        and column_name='financial_year_start' and is_nullable='NO'
    ),
    'Day 12 NOT NULL financial-year contract remains enforced.'

  union all select 22, '22_invoice_date_not_null_retained',
    exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name='invoices'
        and column_name='invoice_date' and is_nullable='NO'
    ),
    'Day 12 NOT NULL invoice-date contract remains enforced.'

  union all select 23, '23_currency_not_null_retained',
    exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name='invoices'
        and column_name='currency_code' and is_nullable='NO'
    ),
    'Day 12 NOT NULL currency contract remains enforced.'

  union all select 24, '24_day12_immutability_trigger_retained',
    exists (
      select 1 from pg_trigger
      where tgname='invoices_day12_immutable'
        and tgrelid='public.invoices'::regclass
        and not tgisinternal
        and tgenabled <> 'D'
    ),
    'Day 12 finalized-invoice immutability remains active.'
)
select test_name, passed, details
from checks
order by test_order;
