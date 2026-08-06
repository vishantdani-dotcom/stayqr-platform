-- StayQR v1.0
-- Day 11 Migration 034 REV1
-- Food, manual-charge and service-pricing foundation
--
-- REQUIRES
-- --------
-- Migration 032 REV2 accepted 50/50.
-- Migration 033 REV2 accepted 64/64.
-- Audit 056 REV2 reviewed.
--
-- AUDIT 056 CONTROLLED TRUTH — VD Stay Inn
-- ----------------------------------------
-- Food orders:
--   28 delivered / uniquely mapped / item-reconciled rows
--   ₹11,635 authoritative charge total
--
-- Manual charges:
--   5 source rows / ₹1,300
--   3 uniquely mapped rows / ₹650
--   2 unmatched rows / ₹650
--
-- Service requests:
--   32 completed rows
--   29 uniquely mapped
--   3 unmatched
--   0 pricing columns
--
-- THIS MIGRATION
-- --------------
-- 1. Creates a strict polymorphic source-exception ledger.
-- 2. Adds explicit service pricing configuration to service_request_types.
-- 3. Adds a deterministic source-to-stay resolver.
-- 4. Synchronizes delivered, item-reconciled food orders as folio food charges.
-- 5. Synchronizes uniquely mapped positive manual charges.
-- 6. Records unmatched/ambiguous source rows instead of guessing.
-- 7. Adds explicit manual/on-completion service charge posting.
-- 8. Installs ongoing source synchronization triggers.
-- 9. Performs two idempotent backfill passes.
--
-- DELIBERATE EXCLUSIONS
-- ---------------------
-- - No source table is rewritten.
-- - No collection is synthesized from food/manual payment_status.
-- - No existing service request is automatically charged.
-- - GST, invoices and night audit remain Day 12.
-- - Discounts/refunds/credits remain later Day 11 work packages.

begin;

-- ---------------------------------------------------------------------------
-- 0. Preflight
-- ---------------------------------------------------------------------------

do $preflight$
declare
  missing_objects text;
  existing_objects text;
  existing_source_items bigint;
begin
  select string_agg(object_name, ', ' order by object_name)
  into missing_objects
  from (
    values
      (
        'public.folios',
        to_regclass('public.folios') is not null
      ),
      (
        'public.folio_items',
        to_regclass('public.folio_items') is not null
      ),
      (
        'private.day11_ensure_folio_for_source(uuid,uuid,text)',
        to_regprocedure(
          'private.day11_ensure_folio_for_source(uuid,uuid,text)'
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
      'Migration 034 requires accepted Migrations 032 and 033. Missing: %',
      missing_objects;
  end if;

  select string_agg(object_name, ', ' order by object_name)
  into existing_objects
  from (
    values
      (
        'public.folio_source_exceptions',
        to_regclass('public.folio_source_exceptions')
      )
  ) as target_object(object_name, relation_id)
  where relation_id is not null;

  if existing_objects is not null then
    raise exception
      'Migration 034 preflight found existing target objects: %. Do not rerun REV1.',
      existing_objects;
  end if;

  if exists (
    select 1
    from information_schema.columns column_record
    where column_record.table_schema = 'public'
      and column_record.table_name = 'service_request_types'
      and column_record.column_name in (
        'charge_enabled',
        'default_charge_amount',
        'charge_posting_policy',
        'charge_taxable',
        'charge_description'
      )
  ) then
    raise exception
      'Migration 034 service pricing columns already exist. Do not rerun REV1.';
  end if;

  select count(*)
  into existing_source_items
  from public.folio_items item
  where item.source_table in (
    'food_orders',
    'manual_charges',
    'service_requests'
  );

  if existing_source_items > 0 then
    raise exception
      'Migration 034 source items already exist (% rows). Do not rerun REV1.',
      existing_source_items;
  end if;
end;
$preflight$;

-- ---------------------------------------------------------------------------
-- 1. Source-exception ledger
-- ---------------------------------------------------------------------------

create table public.folio_source_exceptions (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null,
  source_table text not null,
  source_id uuid not null,

  exception_code text not null,
  status text not null default 'open',
  candidate_count integer not null default 0,

  guest_id uuid,
  room_id uuid,
  source_at timestamptz,

  source_snapshot jsonb not null default '{}'::jsonb,
  mapping_snapshot jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,

  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid,

  constraint folio_source_exceptions_source_check
    check (
      source_table in (
        'food_orders',
        'manual_charges',
        'service_requests'
      )
    ),

  constraint folio_source_exceptions_code_check
    check (
      exception_code in (
        'source_unmatched',
        'source_ambiguous',
        'source_not_final',
        'source_amount_invalid',
        'food_items_missing',
        'food_item_total_mismatch',
        'source_deleted'
      )
    ),

  constraint folio_source_exceptions_status_check
    check (status in ('open', 'resolved', 'ignored')),

  constraint folio_source_exceptions_candidate_check
    check (candidate_count >= 0),

  constraint folio_source_exceptions_resolution_check
    check (
      status = 'open'
      or resolved_at is not null
    ),

  constraint folio_source_exceptions_hotel_fkey
    foreign key (hotel_id)
    references public.hotels(id)
    on delete cascade,

  constraint folio_source_exceptions_resolved_by_fkey
    foreign key (resolved_by)
    references auth.users(id)
    on delete set null
);

create unique index uq_folio_source_exceptions_source
  on public.folio_source_exceptions(
    hotel_id,
    source_table,
    source_id
  );

create index idx_folio_source_exceptions_open
  on public.folio_source_exceptions(
    hotel_id,
    status,
    source_table,
    last_seen_at desc
  );

alter table public.folio_source_exceptions
enable row level security;

create policy stayqr_folio_source_exceptions_select
on public.folio_source_exceptions
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

create policy stayqr_folio_source_exceptions_manage
on public.folio_source_exceptions
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

revoke all
on public.folio_source_exceptions
from public, anon;

grant select, insert, update, delete
on public.folio_source_exceptions
to authenticated;

grant all
on public.folio_source_exceptions
to service_role;

-- ---------------------------------------------------------------------------
-- 2. Explicit service pricing contract
-- ---------------------------------------------------------------------------

alter table public.service_request_types
  add column charge_enabled boolean not null default false,
  add column default_charge_amount numeric(14,2),
  add column charge_posting_policy text not null default 'manual',
  add column charge_taxable boolean not null default false,
  add column charge_description text;

alter table public.service_request_types
  add constraint service_request_types_charge_amount_check
    check (
      default_charge_amount is null
      or default_charge_amount > 0
    ),
  add constraint service_request_types_charge_policy_check
    check (
      charge_posting_policy in (
        'manual',
        'on_completion'
      )
    ),
  add constraint service_request_types_charge_enabled_check
    check (
      not charge_enabled
      or default_charge_amount > 0
    );

comment on column public.service_request_types.charge_enabled is
'Explicit hotel configuration gate. Existing service requests are never chargeable while false.';

comment on column public.service_request_types.default_charge_amount is
'Configured service folio charge. No amount is inferred from request completion.';

comment on column public.service_request_types.charge_posting_policy is
'manual requires an explicit RPC call; on_completion posts only after the type is deliberately enabled.';

-- ---------------------------------------------------------------------------
-- 3. Deterministic source-to-stay resolver
-- ---------------------------------------------------------------------------

create or replace function private.day11_resolve_financial_source_session(
  target_hotel_id uuid,
  target_guest_id uuid,
  target_room_id uuid,
  source_at_value timestamptz,
  allow_missing_room boolean default false
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  candidate_count_value integer;
  selected_session_id uuid;
  selected_room_id uuid;
  candidate_snapshot jsonb;
  status_value text;
begin
  with candidates as (
    select
      stay.id as guest_session_id,
      stay.room_id as current_room_id,
      stay.status as stay_status,
      stay.checkin_time,
      case
        when stay.checked_out_at is not null
          then stay.checked_out_at
        when stay.status = 'active'
          then greatest(
            coalesce(
              stay.extended_until,
              stay.checkout_time,
              now()
            ),
            now()
          )
        else coalesce(
          stay.extended_until,
          stay.checkout_time,
          now()
        )
      end as effective_end_at,
      case
        when target_room_id is null
             and allow_missing_room
          then 'source_room_missing'
        when target_room_id = stay.room_id
          then 'current_session_room'
        else 'room_history_segment'
      end as room_match_source
    from public.guest_sessions stay
    where stay.hotel_id = target_hotel_id
      and stay.guest_id = target_guest_id
      and source_at_value >= stay.checkin_time
      and source_at_value <=
        case
          when stay.checked_out_at is not null
            then stay.checked_out_at
          when stay.status = 'active'
            then greatest(
              coalesce(
                stay.extended_until,
                stay.checkout_time,
                now()
              ),
              now()
            )
          else coalesce(
            stay.extended_until,
            stay.checkout_time,
            now()
          )
        end
      and (
        (
          target_room_id is null
          and allow_missing_room
        )
        or target_room_id = stay.room_id
        or exists (
          select 1
          from public.stay_room_history history
          where history.hotel_id = stay.hotel_id
            and history.guest_session_id = stay.id
            and history.room_id = target_room_id
            and source_at_value >= history.segment_start
            and (
              history.segment_end is null
              or source_at_value < history.segment_end
            )
        )
      )
  )
  select
    count(*),
    (
      min(candidate.guest_session_id::text)
    )::uuid,
    (
      min(candidate.current_room_id::text)
    )::uuid,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'guest_session_id',
            candidate.guest_session_id,
          'current_room_id',
            candidate.current_room_id,
          'stay_status',
            candidate.stay_status,
          'checkin_time',
            candidate.checkin_time,
          'effective_end_at',
            candidate.effective_end_at,
          'room_match_source',
            candidate.room_match_source
        )
        order by candidate.checkin_time,
                 candidate.guest_session_id
      ),
      '[]'::jsonb
    )
  into
    candidate_count_value,
    selected_session_id,
    selected_room_id,
    candidate_snapshot
  from candidates candidate;

  if candidate_count_value = 1 then
    status_value := case
      when target_room_id is null
           and allow_missing_room
        then 'unique_guest_time_match_room_missing'
      else 'unique_guest_room_time_match'
    end;
  elsif candidate_count_value > 1 then
    status_value := 'ambiguous';
    selected_session_id := null;
    selected_room_id := null;
  else
    status_value := 'unmatched';
    selected_session_id := null;
    selected_room_id := null;
  end if;

  return jsonb_build_object(
    'candidate_count', candidate_count_value,
    'guest_session_id', selected_session_id,
    'mapped_room_id', selected_room_id,
    'mapping_status', status_value,
    'candidates', candidate_snapshot
  );
end;
$function$;

revoke all on function private.day11_resolve_financial_source_session(
  uuid,
  uuid,
  uuid,
  timestamptz,
  boolean
)
from public, anon, authenticated;

grant execute on function private.day11_resolve_financial_source_session(
  uuid,
  uuid,
  uuid,
  timestamptz,
  boolean
)
to service_role;

-- ---------------------------------------------------------------------------
-- 4. Exception helpers
-- ---------------------------------------------------------------------------

create or replace function private.day11_record_source_exception(
  target_hotel_id uuid,
  source_table_value text,
  source_id_value uuid,
  exception_code_value text,
  candidate_count_value integer,
  guest_id_value uuid,
  room_id_value uuid,
  source_at_value timestamptz,
  source_snapshot_value jsonb,
  mapping_snapshot_value jsonb,
  metadata_value jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  exception_id_value uuid;
begin
  insert into public.folio_source_exceptions (
    hotel_id,
    source_table,
    source_id,
    exception_code,
    status,
    candidate_count,
    guest_id,
    room_id,
    source_at,
    source_snapshot,
    mapping_snapshot,
    metadata
  )
  values (
    target_hotel_id,
    source_table_value,
    source_id_value,
    exception_code_value,
    'open',
    greatest(coalesce(candidate_count_value, 0), 0),
    guest_id_value,
    room_id_value,
    source_at_value,
    coalesce(source_snapshot_value, '{}'::jsonb),
    coalesce(mapping_snapshot_value, '{}'::jsonb),
    coalesce(metadata_value, '{}'::jsonb)
  )
  on conflict (
    hotel_id,
    source_table,
    source_id
  )
  do update
  set
    exception_code = excluded.exception_code,
    status = 'open',
    candidate_count = excluded.candidate_count,
    guest_id = excluded.guest_id,
    room_id = excluded.room_id,
    source_at = excluded.source_at,
    source_snapshot = excluded.source_snapshot,
    mapping_snapshot = excluded.mapping_snapshot,
    metadata =
      public.folio_source_exceptions.metadata
      || excluded.metadata,
    last_seen_at = now(),
    resolved_at = null,
    resolved_by = null
  returning id
  into exception_id_value;

  return exception_id_value;
end;
$function$;

create or replace function private.day11_resolve_source_exception(
  target_hotel_id uuid,
  source_table_value text,
  source_id_value uuid,
  resolution_metadata jsonb default '{}'::jsonb
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  changed_rows integer;
begin
  update public.folio_source_exceptions exception_record
  set
    status = 'resolved',
    resolved_at = now(),
    resolved_by =
      private.day11_valid_auth_actor(auth.uid()),
    last_seen_at = now(),
    metadata =
      exception_record.metadata
      || coalesce(resolution_metadata, '{}'::jsonb)
  where exception_record.hotel_id = target_hotel_id
    and exception_record.source_table = source_table_value
    and exception_record.source_id = source_id_value
    and exception_record.status = 'open';

  get diagnostics changed_rows = row_count;
  return changed_rows > 0;
end;
$function$;

revoke all on function private.day11_record_source_exception(
  uuid,
  text,
  uuid,
  text,
  integer,
  uuid,
  uuid,
  timestamptz,
  jsonb,
  jsonb,
  jsonb
)
from public, anon, authenticated;

revoke all on function private.day11_resolve_source_exception(
  uuid,
  text,
  uuid,
  jsonb
)
from public, anon, authenticated;

grant execute on function private.day11_record_source_exception(
  uuid,
  text,
  uuid,
  text,
  integer,
  uuid,
  uuid,
  timestamptz,
  jsonb,
  jsonb,
  jsonb
)
to service_role;

grant execute on function private.day11_resolve_source_exception(
  uuid,
  text,
  uuid,
  jsonb
)
to service_role;

-- ---------------------------------------------------------------------------
-- 5. Generic source-item void helper
-- ---------------------------------------------------------------------------

create or replace function private.day11_void_source_item(
  target_hotel_id uuid,
  source_table_value text,
  source_id_value uuid,
  reason_value text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  source_item public.folio_items%rowtype;
begin
  select item.*
  into source_item
  from public.folio_items item
  where item.hotel_id = target_hotel_id
    and item.source_table = source_table_value
    and item.source_id = source_id_value
  limit 1;

  if source_item.id is null then
    return false;
  end if;

  if source_item.posting_status = 'posted' then
    update public.folio_items
    set
      posting_status = 'voided',
      voided_at = now(),
      voided_by =
        private.day11_valid_auth_actor(auth.uid()),
      void_reason = coalesce(
        nullif(trim(reason_value), ''),
        'Source is no longer eligible for posting.'
      ),
      metadata = metadata || jsonb_build_object(
        'voided_by_source_sync', true,
        'voided_source_table', source_table_value,
        'voided_source_id', source_id_value
      )
    where hotel_id = target_hotel_id
      and id = source_item.id;

    perform private.write_folio_event(
      target_hotel_id,
      source_item.folio_id,
      'folio.item.voided',
      source_table_value,
      source_id_value,
      to_jsonb(source_item),
      jsonb_build_object(
        'reason', reason_value,
        'source_sync', 'migration_034'
      )
    );
  end if;

  return true;
end;
$function$;

revoke all on function private.day11_void_source_item(
  uuid,
  text,
  uuid,
  text
)
from public, anon, authenticated;

grant execute on function private.day11_void_source_item(
  uuid,
  text,
  uuid,
  text
)
to service_role;

-- ---------------------------------------------------------------------------
-- 6. Food-order synchronization
-- ---------------------------------------------------------------------------

create or replace function private.day11_sync_food_order(
  target_order_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  source_row public.food_orders%rowtype;
  mapping_value jsonb;
  mapped_session_id uuid;
  mapped_room_id uuid;
  candidate_count_value integer;
  item_rows_value integer;
  calculated_amount_value numeric(14,2);
  item_snapshot_value jsonb;
  folio_row public.folios%rowtype;
  existing_item public.folio_items%rowtype;
  item_id_value uuid;
  inserted_value boolean := false;
  exception_code_value text;
begin
  select food_order.*
  into source_row
  from public.food_orders food_order
  where food_order.id = target_order_id;

  if not found then
    return jsonb_build_object(
      'ok', true,
      'skipped', true,
      'reason', 'source_not_found',
      'source_id', target_order_id
    );
  end if;

  select
    count(*),
    coalesce(
      sum(
        coalesce(item.quantity, 0)
        * coalesce(item.price, 0)
      ),
      0
    ),
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'food_order_item_id', item.id,
          'menu_item_id', item.menu_item_id,
          'quantity', item.quantity,
          'price', item.price,
          'line_amount',
            coalesce(item.quantity, 0)
            * coalesce(item.price, 0)
        )
        order by item.id
      ),
      '[]'::jsonb
    )
  into
    item_rows_value,
    calculated_amount_value,
    item_snapshot_value
  from public.food_order_items item
  where item.hotel_id = source_row.hotel_id
    and item.order_id = source_row.id;

  mapping_value :=
    private.day11_resolve_financial_source_session(
      source_row.hotel_id,
      source_row.guest_id,
      source_row.room_id,
      source_row.created_at,
      false
    );

  candidate_count_value :=
    coalesce(
      (mapping_value ->> 'candidate_count')::integer,
      0
    );

  mapped_session_id :=
    nullif(
      mapping_value ->> 'guest_session_id',
      ''
    )::uuid;

  mapped_room_id :=
    nullif(
      mapping_value ->> 'mapped_room_id',
      ''
    )::uuid;

  exception_code_value := case
    when lower(coalesce(source_row.order_status, '')) <> 'delivered'
      then 'source_not_final'
    when source_row.total_amount <= 0
      then 'source_amount_invalid'
    when item_rows_value = 0
      then 'food_items_missing'
    when source_row.total_amount <> calculated_amount_value
      then 'food_item_total_mismatch'
    when candidate_count_value > 1
      then 'source_ambiguous'
    when candidate_count_value = 0
      then 'source_unmatched'
    else null
  end;

  if exception_code_value is not null then
    perform private.day11_void_source_item(
      source_row.hotel_id,
      'food_orders',
      source_row.id,
      'Food order failed authoritative posting eligibility.'
    );

    perform private.day11_record_source_exception(
      source_row.hotel_id,
      'food_orders',
      source_row.id,
      exception_code_value,
      candidate_count_value,
      source_row.guest_id,
      source_row.room_id,
      source_row.created_at,
      to_jsonb(source_row)
        || jsonb_build_object(
          'item_rows', item_rows_value,
          'calculated_item_amount',
            calculated_amount_value,
          'items', item_snapshot_value
        ),
      mapping_value,
      jsonb_build_object(
        'source_sync', 'migration_034'
      )
    );

    return jsonb_build_object(
      'ok', true,
      'skipped', true,
      'reason', exception_code_value,
      'source_id', source_row.id,
      'mapping', mapping_value
    );
  end if;

  folio_row := private.day11_ensure_folio_for_source(
    source_row.hotel_id,
    mapped_session_id,
    'legacy_food_order'
  );

  select item.*
  into existing_item
  from public.folio_items item
  where item.hotel_id = source_row.hotel_id
    and item.source_table = 'food_orders'
    and item.source_id = source_row.id
  limit 1;

  if existing_item.id is null then
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
      source_row.hotel_id,
      folio_row.id,
      'charge',
      'food',
      'Food order '
        || upper(
          substr(
            replace(source_row.id::text, '-', ''),
            1,
            8
          )
        ),
      1,
      source_row.total_amount,
      source_row.total_amount,
      'food_orders',
      source_row.id,
      coalesce(
        source_row.delivered_at,
        source_row.created_at
      ),
      'posted',
      coalesce(
        source_row.delivered_at,
        source_row.created_at
      ),
      null,
      jsonb_build_object(
        'legacy_order_status',
          source_row.order_status,
        'legacy_payment_status',
          source_row.payment_status,
        'legacy_room_id',
          source_row.room_id,
        'mapped_guest_session_id',
          mapped_session_id,
        'mapped_room_id',
          mapped_room_id,
        'item_rows', item_rows_value,
        'calculated_item_amount',
          calculated_amount_value,
        'items', item_snapshot_value,
        'source_sync', 'migration_034'
      )
    )
    returning id
    into item_id_value;

    inserted_value := true;
  else
    update public.folio_items
    set
      folio_id = folio_row.id,
      item_kind = 'charge',
      charge_category = 'food',
      description =
        'Food order '
        || upper(
          substr(
            replace(source_row.id::text, '-', ''),
            1,
            8
          )
        ),
      quantity = 1,
      unit_amount = source_row.total_amount,
      amount = source_row.total_amount,
      service_at = coalesce(
        source_row.delivered_at,
        source_row.created_at
      ),
      posting_status = 'posted',
      voided_at = null,
      voided_by = null,
      void_reason = null,
      metadata = metadata || jsonb_build_object(
        'legacy_order_status',
          source_row.order_status,
        'legacy_payment_status',
          source_row.payment_status,
        'legacy_room_id',
          source_row.room_id,
        'mapped_guest_session_id',
          mapped_session_id,
        'mapped_room_id',
          mapped_room_id,
        'item_rows', item_rows_value,
        'calculated_item_amount',
          calculated_amount_value,
        'items', item_snapshot_value,
        'source_sync', 'migration_034'
      )
    where hotel_id = source_row.hotel_id
      and id = existing_item.id
    returning id
    into item_id_value;

    if existing_item.folio_id <> folio_row.id then
      perform private.recalculate_folio(
        source_row.hotel_id,
        existing_item.folio_id
      );
    end if;
  end if;

  perform private.day11_resolve_source_exception(
    source_row.hotel_id,
    'food_orders',
    source_row.id,
    jsonb_build_object(
      'resolved_by_sync', 'migration_034'
    )
  );

  if inserted_value then
    perform private.write_folio_event(
      source_row.hotel_id,
      folio_row.id,
      'folio.item.posted',
      'food_order',
      source_row.id,
      jsonb_build_object(
        'folio_item_id', item_id_value,
        'amount', source_row.total_amount,
        'charge_category', 'food'
      ),
      jsonb_build_object(
        'source_sync', 'migration_034'
      )
    );
  end if;

  return jsonb_build_object(
    'ok', true,
    'skipped', false,
    'idempotent', not inserted_value,
    'source_id', source_row.id,
    'folio_id', folio_row.id,
    'folio_item_id', item_id_value,
    'amount', source_row.total_amount
  );
end;
$function$;

revoke all on function private.day11_sync_food_order(uuid)
from public, anon, authenticated;

grant execute on function private.day11_sync_food_order(uuid)
to service_role;

-- ---------------------------------------------------------------------------
-- 7. Manual-charge synchronization
-- ---------------------------------------------------------------------------

create or replace function private.day11_sync_manual_charge(
  target_charge_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  source_row public.manual_charges%rowtype;
  mapping_value jsonb;
  mapped_session_id uuid;
  mapped_room_id uuid;
  candidate_count_value integer;
  folio_row public.folios%rowtype;
  existing_item public.folio_items%rowtype;
  item_id_value uuid;
  inserted_value boolean := false;
  exception_code_value text;
begin
  select charge.*
  into source_row
  from public.manual_charges charge
  where charge.id = target_charge_id;

  if not found then
    return jsonb_build_object(
      'ok', true,
      'skipped', true,
      'reason', 'source_not_found',
      'source_id', target_charge_id
    );
  end if;

  mapping_value :=
    private.day11_resolve_financial_source_session(
      source_row.hotel_id,
      source_row.guest_id,
      source_row.room_id,
      source_row.created_at,
      true
    );

  candidate_count_value :=
    coalesce(
      (mapping_value ->> 'candidate_count')::integer,
      0
    );

  mapped_session_id :=
    nullif(
      mapping_value ->> 'guest_session_id',
      ''
    )::uuid;

  mapped_room_id :=
    nullif(
      mapping_value ->> 'mapped_room_id',
      ''
    )::uuid;

  exception_code_value := case
    when source_row.charge_amount <= 0
      then 'source_amount_invalid'
    when candidate_count_value > 1
      then 'source_ambiguous'
    when candidate_count_value = 0
      then 'source_unmatched'
    else null
  end;

  if exception_code_value is not null then
    perform private.day11_void_source_item(
      source_row.hotel_id,
      'manual_charges',
      source_row.id,
      'Manual charge failed authoritative stay mapping.'
    );

    perform private.day11_record_source_exception(
      source_row.hotel_id,
      'manual_charges',
      source_row.id,
      exception_code_value,
      candidate_count_value,
      source_row.guest_id,
      source_row.room_id,
      source_row.created_at,
      to_jsonb(source_row),
      mapping_value,
      jsonb_build_object(
        'source_sync', 'migration_034'
      )
    );

    return jsonb_build_object(
      'ok', true,
      'skipped', true,
      'reason', exception_code_value,
      'source_id', source_row.id,
      'mapping', mapping_value
    );
  end if;

  folio_row := private.day11_ensure_folio_for_source(
    source_row.hotel_id,
    mapped_session_id,
    'legacy_manual_charge'
  );

  select item.*
  into existing_item
  from public.folio_items item
  where item.hotel_id = source_row.hotel_id
    and item.source_table = 'manual_charges'
    and item.source_id = source_row.id
  limit 1;

  if existing_item.id is null then
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
      source_row.hotel_id,
      folio_row.id,
      'charge',
      'manual',
      coalesce(
        nullif(trim(source_row.charge_name), ''),
        'Manual charge'
      ),
      1,
      source_row.charge_amount,
      source_row.charge_amount,
      'manual_charges',
      source_row.id,
      source_row.created_at,
      'posted',
      source_row.created_at,
      null,
      jsonb_build_object(
        'legacy_payment_status',
          source_row.payment_status,
        'legacy_notes',
          source_row.notes,
        'legacy_room_id',
          source_row.room_id,
        'source_room_missing',
          source_row.room_id is null,
        'mapped_guest_session_id',
          mapped_session_id,
        'mapped_room_id',
          mapped_room_id,
        'source_sync', 'migration_034'
      )
    )
    returning id
    into item_id_value;

    inserted_value := true;
  else
    update public.folio_items
    set
      folio_id = folio_row.id,
      item_kind = 'charge',
      charge_category = 'manual',
      description = coalesce(
        nullif(trim(source_row.charge_name), ''),
        'Manual charge'
      ),
      quantity = 1,
      unit_amount = source_row.charge_amount,
      amount = source_row.charge_amount,
      service_at = source_row.created_at,
      posting_status = 'posted',
      voided_at = null,
      voided_by = null,
      void_reason = null,
      metadata = metadata || jsonb_build_object(
        'legacy_payment_status',
          source_row.payment_status,
        'legacy_notes',
          source_row.notes,
        'legacy_room_id',
          source_row.room_id,
        'source_room_missing',
          source_row.room_id is null,
        'mapped_guest_session_id',
          mapped_session_id,
        'mapped_room_id',
          mapped_room_id,
        'source_sync', 'migration_034'
      )
    where hotel_id = source_row.hotel_id
      and id = existing_item.id
    returning id
    into item_id_value;

    if existing_item.folio_id <> folio_row.id then
      perform private.recalculate_folio(
        source_row.hotel_id,
        existing_item.folio_id
      );
    end if;
  end if;

  perform private.day11_resolve_source_exception(
    source_row.hotel_id,
    'manual_charges',
    source_row.id,
    jsonb_build_object(
      'resolved_by_sync', 'migration_034'
    )
  );

  if inserted_value then
    perform private.write_folio_event(
      source_row.hotel_id,
      folio_row.id,
      'folio.item.posted',
      'manual_charge',
      source_row.id,
      jsonb_build_object(
        'folio_item_id', item_id_value,
        'amount', source_row.charge_amount,
        'charge_category', 'manual'
      ),
      jsonb_build_object(
        'source_sync', 'migration_034'
      )
    );
  end if;

  return jsonb_build_object(
    'ok', true,
    'skipped', false,
    'idempotent', not inserted_value,
    'source_id', source_row.id,
    'folio_id', folio_row.id,
    'folio_item_id', item_id_value,
    'amount', source_row.charge_amount
  );
end;
$function$;

revoke all on function private.day11_sync_manual_charge(uuid)
from public, anon, authenticated;

grant execute on function private.day11_sync_manual_charge(uuid)
to service_role;

-- ---------------------------------------------------------------------------
-- 8. Service request mapping readiness
-- ---------------------------------------------------------------------------

create or replace function private.day11_refresh_service_request_mapping(
  target_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  source_row public.service_requests%rowtype;
  mapping_value jsonb;
  candidate_count_value integer;
begin
  select request.*
  into source_row
  from public.service_requests request
  where request.id = target_request_id;

  if not found then
    return jsonb_build_object(
      'ok', true,
      'skipped', true,
      'reason', 'source_not_found',
      'source_id', target_request_id
    );
  end if;

  mapping_value :=
    private.day11_resolve_financial_source_session(
      source_row.hotel_id,
      source_row.guest_id,
      source_row.room_id,
      source_row.created_at,
      false
    );

  candidate_count_value :=
    coalesce(
      (mapping_value ->> 'candidate_count')::integer,
      0
    );

  if candidate_count_value = 1 then
    perform private.day11_resolve_source_exception(
      source_row.hotel_id,
      'service_requests',
      source_row.id,
      jsonb_build_object(
        'mapping_ready', true,
        'resolved_by_sync', 'migration_034'
      )
    );
  else
    perform private.day11_record_source_exception(
      source_row.hotel_id,
      'service_requests',
      source_row.id,
      case
        when candidate_count_value > 1
          then 'source_ambiguous'
        else 'source_unmatched'
      end,
      candidate_count_value,
      source_row.guest_id,
      source_row.room_id,
      source_row.created_at,
      to_jsonb(source_row),
      mapping_value,
      jsonb_build_object(
        'source_sync', 'migration_034',
        'charge_not_posted', true
      )
    );
  end if;

  return jsonb_build_object(
    'ok', true,
    'source_id', source_row.id,
    'mapping', mapping_value
  );
end;
$function$;

revoke all on function private.day11_refresh_service_request_mapping(uuid)
from public, anon, authenticated;

grant execute on function private.day11_refresh_service_request_mapping(uuid)
to service_role;

-- ---------------------------------------------------------------------------
-- 9. Internal service-charge posting
-- ---------------------------------------------------------------------------

create or replace function private.day11_post_service_request_charge(
  target_request_id uuid,
  force_manual boolean default false,
  request_id_value text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  source_row public.service_requests%rowtype;
  type_row public.service_request_types%rowtype;
  mapping_value jsonb;
  candidate_count_value integer;
  mapped_session_id uuid;
  mapped_room_id uuid;
  folio_row public.folios%rowtype;
  existing_item public.folio_items%rowtype;
  item_id_value uuid;
  inserted_value boolean := false;
  amount_value numeric(14,2);
  description_value text;
begin
  select request.*
  into source_row
  from public.service_requests request
  where request.id = target_request_id;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'reason', 'source_not_found',
      'source_id', target_request_id
    );
  end if;

  if source_row.request_type_id is null then
    return jsonb_build_object(
      'ok', false,
      'reason', 'service_type_missing',
      'source_id', source_row.id
    );
  end if;

  select request_type.*
  into type_row
  from public.service_request_types request_type
  where request_type.hotel_id = source_row.hotel_id
    and request_type.id = source_row.request_type_id;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'reason', 'service_type_not_found',
      'source_id', source_row.id
    );
  end if;

  if source_row.status <> 'completed' then
    return jsonb_build_object(
      'ok', false,
      'reason', 'service_not_completed',
      'source_id', source_row.id
    );
  end if;

  if not type_row.charge_enabled then
    return jsonb_build_object(
      'ok', false,
      'reason', 'service_pricing_disabled',
      'source_id', source_row.id
    );
  end if;

  if type_row.default_charge_amount is null
     or type_row.default_charge_amount <= 0
  then
    return jsonb_build_object(
      'ok', false,
      'reason', 'service_amount_invalid',
      'source_id', source_row.id
    );
  end if;

  if
    type_row.charge_posting_policy = 'manual'
    and not force_manual
  then
    return jsonb_build_object(
      'ok', true,
      'skipped', true,
      'reason', 'manual_post_required',
      'source_id', source_row.id
    );
  end if;

  mapping_value :=
    private.day11_resolve_financial_source_session(
      source_row.hotel_id,
      source_row.guest_id,
      source_row.room_id,
      source_row.created_at,
      false
    );

  candidate_count_value :=
    coalesce(
      (mapping_value ->> 'candidate_count')::integer,
      0
    );

  if candidate_count_value <> 1 then
    perform private.day11_record_source_exception(
      source_row.hotel_id,
      'service_requests',
      source_row.id,
      case
        when candidate_count_value > 1
          then 'source_ambiguous'
        else 'source_unmatched'
      end,
      candidate_count_value,
      source_row.guest_id,
      source_row.room_id,
      source_row.created_at,
      to_jsonb(source_row),
      mapping_value,
      jsonb_build_object(
        'service_charge_attempted', true,
        'request_id', request_id_value,
        'source_sync', 'migration_034'
      )
    );

    return jsonb_build_object(
      'ok', false,
      'reason', case
        when candidate_count_value > 1
          then 'source_ambiguous'
        else 'source_unmatched'
      end,
      'source_id', source_row.id,
      'mapping', mapping_value
    );
  end if;

  mapped_session_id :=
    (mapping_value ->> 'guest_session_id')::uuid;

  mapped_room_id :=
    (mapping_value ->> 'mapped_room_id')::uuid;

  amount_value := type_row.default_charge_amount;

  description_value := coalesce(
    nullif(trim(type_row.charge_description), ''),
    nullif(trim(type_row.name), ''),
    'Service charge'
  );

  folio_row := private.day11_ensure_folio_for_source(
    source_row.hotel_id,
    mapped_session_id,
    'service_request_charge'
  );

  select item.*
  into existing_item
  from public.folio_items item
  where item.hotel_id = source_row.hotel_id
    and item.source_table = 'service_requests'
    and item.source_id = source_row.id
  limit 1;

  if existing_item.id is null then
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
      source_row.hotel_id,
      folio_row.id,
      'charge',
      'service',
      description_value,
      1,
      amount_value,
      amount_value,
      'service_requests',
      source_row.id,
      coalesce(
        source_row.completed_at,
        source_row.created_at
      ),
      'posted',
      now(),
      private.day11_valid_auth_actor(auth.uid()),
      jsonb_build_object(
        'request_type_id',
          source_row.request_type_id,
        'request_type_code',
          type_row.code,
        'request_type_name',
          type_row.name,
        'charge_posting_policy',
          type_row.charge_posting_policy,
        'charge_taxable',
          type_row.charge_taxable,
        'mapped_guest_session_id',
          mapped_session_id,
        'mapped_room_id',
          mapped_room_id,
        'request_id',
          request_id_value,
        'source_sync', 'migration_034'
      )
    )
    returning id
    into item_id_value;

    inserted_value := true;
  else
    update public.folio_items
    set
      folio_id = folio_row.id,
      item_kind = 'charge',
      charge_category = 'service',
      description = description_value,
      quantity = 1,
      unit_amount = amount_value,
      amount = amount_value,
      service_at = coalesce(
        source_row.completed_at,
        source_row.created_at
      ),
      posting_status = 'posted',
      voided_at = null,
      voided_by = null,
      void_reason = null,
      metadata = metadata || jsonb_build_object(
        'request_type_id',
          source_row.request_type_id,
        'request_type_code',
          type_row.code,
        'request_type_name',
          type_row.name,
        'charge_posting_policy',
          type_row.charge_posting_policy,
        'charge_taxable',
          type_row.charge_taxable,
        'mapped_guest_session_id',
          mapped_session_id,
        'mapped_room_id',
          mapped_room_id,
        'request_id',
          request_id_value,
        'source_sync', 'migration_034'
      )
    where hotel_id = source_row.hotel_id
      and id = existing_item.id
    returning id
    into item_id_value;

    if existing_item.folio_id <> folio_row.id then
      perform private.recalculate_folio(
        source_row.hotel_id,
        existing_item.folio_id
      );
    end if;
  end if;

  perform private.day11_resolve_source_exception(
    source_row.hotel_id,
    'service_requests',
    source_row.id,
    jsonb_build_object(
      'service_charge_posted', true,
      'request_id', request_id_value
    )
  );

  if inserted_value then
    perform private.write_folio_event(
      source_row.hotel_id,
      folio_row.id,
      'folio.item.posted',
      'service_request',
      source_row.id,
      jsonb_build_object(
        'folio_item_id', item_id_value,
        'amount', amount_value,
        'charge_category', 'service'
      ),
      jsonb_build_object(
        'request_id', request_id_value,
        'source_sync', 'migration_034'
      )
    );
  end if;

  return jsonb_build_object(
    'ok', true,
    'skipped', false,
    'idempotent', not inserted_value,
    'source_id', source_row.id,
    'folio_id', folio_row.id,
    'folio_item_id', item_id_value,
    'amount', amount_value,
    'request_id', request_id_value
  );
end;
$function$;

revoke all on function private.day11_post_service_request_charge(
  uuid,
  boolean,
  text
)
from public, anon, authenticated;

grant execute on function private.day11_post_service_request_charge(
  uuid,
  boolean,
  text
)
to service_role;

-- ---------------------------------------------------------------------------
-- 10. Authorized service pricing and posting RPCs
-- ---------------------------------------------------------------------------

create or replace function public.configure_service_request_charge(
  target_hotel_id uuid,
  target_request_type_id uuid,
  charge_enabled_value boolean,
  default_charge_amount_value numeric default null,
  posting_policy_value text default 'manual',
  charge_description_value text default null,
  taxable_value boolean default false,
  request_id_value text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  updated_type public.service_request_types%rowtype;
  request_record record;
  posted_count integer := 0;
begin
  if not private.user_has_any_permission(
    target_hotel_id,
    array[
      'payments.manage',
      'invoices.manage',
      'checkout.manage'
    ]::text[]
  ) then
    raise exception 'Service charge configuration access denied.';
  end if;

  if posting_policy_value not in (
    'manual',
    'on_completion'
  ) then
    raise exception 'Invalid service charge posting policy.';
  end if;

  if
    charge_enabled_value
    and (
      default_charge_amount_value is null
      or default_charge_amount_value <= 0
    )
  then
    raise exception
      'Enabled service pricing requires a positive default amount.';
  end if;

  update public.service_request_types request_type
  set
    charge_enabled = charge_enabled_value,
    default_charge_amount =
      default_charge_amount_value,
    charge_posting_policy =
      posting_policy_value,
    charge_taxable = taxable_value,
    charge_description =
      nullif(trim(charge_description_value), ''),
    updated_at = now(),
    updated_by =
      private.day11_valid_auth_actor(auth.uid())
  where request_type.hotel_id = target_hotel_id
    and request_type.id = target_request_type_id
  returning request_type.*
  into updated_type;

  if updated_type.id is null then
    raise exception 'Service request type was not found.';
  end if;

  if
    updated_type.charge_enabled
    and updated_type.charge_posting_policy =
      'on_completion'
  then
    for request_record in
      select request.id
      from public.service_requests request
      where request.hotel_id = target_hotel_id
        and request.request_type_id =
          target_request_type_id
        and request.status = 'completed'
      order by request.created_at, request.id
    loop
      if coalesce(
        (
          private.day11_post_service_request_charge(
            request_record.id,
            false,
            request_id_value
          ) ->> 'ok'
        )::boolean,
        false
      ) then
        posted_count := posted_count + 1;
      end if;
    end loop;
  end if;

  return jsonb_build_object(
    'ok', true,
    'request_id', coalesce(
      nullif(trim(request_id_value), ''),
      gen_random_uuid()::text
    ),
    'request_type', to_jsonb(updated_type),
    'completed_requests_processed',
      posted_count
  );
end;
$function$;

create or replace function public.post_service_request_charge(
  target_hotel_id uuid,
  target_request_id uuid,
  request_id_value text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  request_hotel_id uuid;
begin
  if not private.user_has_any_permission(
    target_hotel_id,
    array[
      'payments.manage',
      'invoices.manage',
      'checkout.manage'
    ]::text[]
  ) then
    raise exception 'Service charge posting access denied.';
  end if;

  select request.hotel_id
  into request_hotel_id
  from public.service_requests request
  where request.id = target_request_id;

  if request_hotel_id is null
     or request_hotel_id <> target_hotel_id
  then
    raise exception
      'Service request was not found in the selected hotel.';
  end if;

  return private.day11_post_service_request_charge(
    target_request_id,
    true,
    coalesce(
      nullif(trim(request_id_value), ''),
      gen_random_uuid()::text
    )
  );
end;
$function$;

revoke all on function public.configure_service_request_charge(
  uuid,
  uuid,
  boolean,
  numeric,
  text,
  text,
  boolean,
  text
)
from public, anon;

revoke all on function public.post_service_request_charge(
  uuid,
  uuid,
  text
)
from public, anon;

grant execute on function public.configure_service_request_charge(
  uuid,
  uuid,
  boolean,
  numeric,
  text,
  text,
  boolean,
  text
)
to authenticated, service_role;

grant execute on function public.post_service_request_charge(
  uuid,
  uuid,
  text
)
to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 11. Ongoing source synchronization triggers
-- ---------------------------------------------------------------------------

create or replace function private.day11_food_order_sync_trigger()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if tg_op = 'DELETE' then
    perform private.day11_void_source_item(
      old.hotel_id,
      'food_orders',
      old.id,
      'Legacy food order source row was deleted.'
    );

    perform private.day11_record_source_exception(
      old.hotel_id,
      'food_orders',
      old.id,
      'source_deleted',
      0,
      old.guest_id,
      old.room_id,
      old.created_at,
      to_jsonb(old),
      '{}'::jsonb,
      jsonb_build_object(
        'source_sync', 'migration_034'
      )
    );

    return old;
  end if;

  perform private.day11_sync_food_order(new.id);
  return new;
end;
$function$;

create or replace function private.day11_food_order_item_sync_trigger()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if tg_op = 'DELETE' then
    perform private.day11_sync_food_order(old.order_id);
    return old;
  end if;

  if
    tg_op = 'UPDATE'
    and old.order_id is distinct from new.order_id
  then
    perform private.day11_sync_food_order(old.order_id);
  end if;

  perform private.day11_sync_food_order(new.order_id);
  return new;
end;
$function$;

create or replace function private.day11_manual_charge_sync_trigger()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if tg_op = 'DELETE' then
    perform private.day11_void_source_item(
      old.hotel_id,
      'manual_charges',
      old.id,
      'Legacy manual charge source row was deleted.'
    );

    perform private.day11_record_source_exception(
      old.hotel_id,
      'manual_charges',
      old.id,
      'source_deleted',
      0,
      old.guest_id,
      old.room_id,
      old.created_at,
      to_jsonb(old),
      '{}'::jsonb,
      jsonb_build_object(
        'source_sync', 'migration_034'
      )
    );

    return old;
  end if;

  perform private.day11_sync_manual_charge(new.id);
  return new;
end;
$function$;

create or replace function private.day11_service_request_sync_trigger()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  request_type_row public.service_request_types%rowtype;
begin
  if tg_op = 'DELETE' then
    perform private.day11_void_source_item(
      old.hotel_id,
      'service_requests',
      old.id,
      'Legacy service request source row was deleted.'
    );

    perform private.day11_record_source_exception(
      old.hotel_id,
      'service_requests',
      old.id,
      'source_deleted',
      0,
      old.guest_id,
      old.room_id,
      old.created_at,
      to_jsonb(old),
      '{}'::jsonb,
      jsonb_build_object(
        'source_sync', 'migration_034'
      )
    );

    return old;
  end if;

  perform private.day11_refresh_service_request_mapping(
    new.id
  );

  if
    new.status = 'completed'
    and new.request_type_id is not null
  then
    select request_type.*
    into request_type_row
    from public.service_request_types request_type
    where request_type.hotel_id = new.hotel_id
      and request_type.id = new.request_type_id;

    if
      request_type_row.id is not null
      and request_type_row.charge_enabled
      and request_type_row.charge_posting_policy =
        'on_completion'
    then
      perform private.day11_post_service_request_charge(
        new.id,
        false,
        'service-trigger:' || new.id::text
      );
    end if;
  end if;

  return new;
end;
$function$;

drop trigger if exists food_orders_day11_folio_sync
on public.food_orders;

create trigger food_orders_day11_folio_sync
after insert or update or delete
on public.food_orders
for each row
execute function private.day11_food_order_sync_trigger();

drop trigger if exists food_order_items_day11_folio_sync
on public.food_order_items;

create trigger food_order_items_day11_folio_sync
after insert or update or delete
on public.food_order_items
for each row
execute function private.day11_food_order_item_sync_trigger();

drop trigger if exists manual_charges_day11_folio_sync
on public.manual_charges;

create trigger manual_charges_day11_folio_sync
after insert or update or delete
on public.manual_charges
for each row
execute function private.day11_manual_charge_sync_trigger();

drop trigger if exists service_requests_day11_folio_sync
on public.service_requests;

create trigger service_requests_day11_folio_sync
after insert or update or delete
on public.service_requests
for each row
execute function private.day11_service_request_sync_trigger();

-- ---------------------------------------------------------------------------
-- 12. Authorized reconciliation RPC
-- ---------------------------------------------------------------------------

create or replace function public.reconcile_food_manual_service_sources(
  target_hotel_id uuid,
  request_id_value text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  source_record record;
  food_processed integer := 0;
  manual_processed integer := 0;
  service_processed integer := 0;
  food_items_value integer;
  manual_items_value integer;
  service_items_value integer;
  open_exceptions_value integer;
begin
  if not private.user_has_any_permission(
    target_hotel_id,
    array[
      'payments.manage',
      'invoices.manage',
      'checkout.manage'
    ]::text[]
  ) then
    raise exception 'Financial source reconciliation access denied.';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      'stayqr:day11:migration034:'
      || target_hotel_id::text,
      0
    )
  );

  for source_record in
    select food_order.id
    from public.food_orders food_order
    where food_order.hotel_id = target_hotel_id
    order by food_order.created_at, food_order.id
  loop
    perform private.day11_sync_food_order(
      source_record.id
    );
    food_processed := food_processed + 1;
  end loop;

  for source_record in
    select manual_charge.id
    from public.manual_charges manual_charge
    where manual_charge.hotel_id = target_hotel_id
    order by manual_charge.created_at,
             manual_charge.id
  loop
    perform private.day11_sync_manual_charge(
      source_record.id
    );
    manual_processed := manual_processed + 1;
  end loop;

  for source_record in
    select request.id
    from public.service_requests request
    where request.hotel_id = target_hotel_id
    order by request.created_at, request.id
  loop
    perform private.day11_refresh_service_request_mapping(
      source_record.id
    );

    perform private.day11_post_service_request_charge(
      source_record.id,
      false,
      request_id_value
    );

    service_processed := service_processed + 1;
  end loop;

  select count(*)
  into food_items_value
  from public.folio_items item
  where item.hotel_id = target_hotel_id
    and item.source_table = 'food_orders'
    and item.posting_status = 'posted';

  select count(*)
  into manual_items_value
  from public.folio_items item
  where item.hotel_id = target_hotel_id
    and item.source_table = 'manual_charges'
    and item.posting_status = 'posted';

  select count(*)
  into service_items_value
  from public.folio_items item
  where item.hotel_id = target_hotel_id
    and item.source_table = 'service_requests'
    and item.posting_status = 'posted';

  select count(*)
  into open_exceptions_value
  from public.folio_source_exceptions exception_record
  where exception_record.hotel_id = target_hotel_id
    and exception_record.status = 'open';

  return jsonb_build_object(
    'ok', true,
    'hotel_id', target_hotel_id,
    'request_id', coalesce(
      nullif(trim(request_id_value), ''),
      gen_random_uuid()::text
    ),
    'food_sources_processed', food_processed,
    'manual_sources_processed', manual_processed,
    'service_sources_processed',
      service_processed,
    'posted_food_items', food_items_value,
    'posted_manual_items', manual_items_value,
    'posted_service_items', service_items_value,
    'open_source_exceptions',
      open_exceptions_value,
    'source_sync', 'migration_034'
  );
end;
$function$;

revoke all on function public.reconcile_food_manual_service_sources(
  uuid,
  text
)
from public, anon;

grant execute on function public.reconcile_food_manual_service_sources(
  uuid,
  text
)
to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 13. Initial idempotent backfill
-- ---------------------------------------------------------------------------

do $backfill$
declare
  source_record record;
begin
  -- Pass 1
  for source_record in
    select food_order.id
    from public.food_orders food_order
    order by food_order.hotel_id,
             food_order.created_at,
             food_order.id
  loop
    perform private.day11_sync_food_order(
      source_record.id
    );
  end loop;

  for source_record in
    select manual_charge.id
    from public.manual_charges manual_charge
    order by manual_charge.hotel_id,
             manual_charge.created_at,
             manual_charge.id
  loop
    perform private.day11_sync_manual_charge(
      source_record.id
    );
  end loop;

  for source_record in
    select request.id
    from public.service_requests request
    order by request.hotel_id,
             request.created_at,
             request.id
  loop
    perform private.day11_refresh_service_request_mapping(
      source_record.id
    );
  end loop;

  -- Pass 2 proves charge and exception idempotency.
  for source_record in
    select food_order.id
    from public.food_orders food_order
    order by food_order.hotel_id,
             food_order.created_at,
             food_order.id
  loop
    perform private.day11_sync_food_order(
      source_record.id
    );
  end loop;

  for source_record in
    select manual_charge.id
    from public.manual_charges manual_charge
    order by manual_charge.hotel_id,
             manual_charge.created_at,
             manual_charge.id
  loop
    perform private.day11_sync_manual_charge(
      source_record.id
    );
  end loop;

  for source_record in
    select request.id
    from public.service_requests request
    order by request.hotel_id,
             request.created_at,
             request.id
  loop
    perform private.day11_refresh_service_request_mapping(
      source_record.id
    );
  end loop;
end;
$backfill$;

-- ---------------------------------------------------------------------------
-- 14. Documentation
-- ---------------------------------------------------------------------------

comment on table public.folio_source_exceptions is
'Day 11 strict source-mapping exception ledger. Unmatched and ambiguous financial sources remain visible and unposted instead of being guessed.';

comment on function private.day11_resolve_financial_source_session(
  uuid,
  uuid,
  uuid,
  timestamptz,
  boolean
) is
'Deterministically maps a financial source to exactly one guest session using guest, source time, current room and stay room history.';

comment on function private.day11_sync_food_order(uuid) is
'Posts one delivered, item-reconciled and uniquely mapped food order as one authoritative folio food charge.';

comment on function private.day11_sync_manual_charge(uuid) is
'Posts one positive and uniquely mapped legacy manual charge while preserving missing source room evidence in metadata.';

comment on function public.post_service_request_charge(
  uuid,
  uuid,
  text
) is
'Explicit idempotent service charge posting. Requires completed request, enabled configured price and exact stay mapping.';

commit;
