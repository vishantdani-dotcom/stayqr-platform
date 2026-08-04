-- ============================================================================
-- StayQR v1.0
-- Day 15 Migration 051 REV1
-- Food, Kitchen and Service Operational Schema Foundation
--
-- BASIS
-- Audit 065 live-schema preflight:
--   234 checks
--   Existing data-health suite: 7/7
--   Existing runtime rows:
--     28 food orders
--     46 food order items
--     36 service requests
--     12 dynamic service types
--
-- PURPOSE
-- Install the missing Day 15 data model without deleting legacy columns or
-- requiring the frontend patch first.
--
-- THIS MIGRATION INSTALLS
-- - menu service windows and item tax/preparation metadata
-- - modifier groups, modifier choices and selected modifier snapshots
-- - food order financial/status/idempotency/timestamp metadata
-- - food order immutable events and kitchen ticket identities
-- - service departments, SLA/escalation metadata and assignment compatibility
-- - service immutable events, guest notification history and escalation ledger
-- - tenant-safe constraints, indexes, RLS and data backfills
--
-- COMPATIBILITY
-- - Keeps food_orders.order_status.
-- - Keeps service_requests.assigned_to.
-- - Mirrors assigned_to into assigned_staff_id.
-- - Keeps food_order_items.price as the legacy gross unit amount used by the
--   locked Day 11 folio synchronizer.
--
-- NOT INCLUDED YET
-- Trusted Day 15 workflow RPCs and frontend replacement are installed in the
-- next package after this migration passes.
--
-- RUN WITH
-- Supabase SQL Editor role: postgres
--
-- EXPECTED RESULT
-- 130 rows; every passed value = true.
-- ============================================================================

begin;

set local lock_timeout = '10s';
set local statement_timeout = '300s';

select pg_advisory_xact_lock(
  hashtext('stayqr:202608040051:day15-operational-schema-foundation-rev1')
);

create schema if not exists private;

-- ============================================================================
-- 0. Preconditions
-- ============================================================================

do $preflight$
begin
  if to_regclass('public.hotels') is null
     or to_regclass('public.rooms') is null
     or to_regclass('public.guests') is null
     or to_regclass('public.guest_sessions') is null
     or to_regclass('public.staff') is null
     or to_regclass('public.menu_categories') is null
     or to_regclass('public.menu_items') is null
     or to_regclass('public.food_orders') is null
     or to_regclass('public.food_order_items') is null
     or to_regclass('public.service_request_types') is null
     or to_regclass('public.service_requests') is null
     or to_regclass('public.folio_items') is null
  then
    raise exception
      'Migration 051 stopped: required locked StayQR tables are missing.';
  end if;

  if to_regprocedure('private.user_has_permission(uuid,text)') is null
     or to_regprocedure('private.user_has_any_permission(uuid,text[])') is null
     or to_regprocedure('private.set_updated_at()') is null
     or to_regprocedure('private.day11_resolve_financial_source_session(uuid,uuid,uuid,timestamptz,boolean)') is null
  then
    raise exception
      'Migration 051 stopped: required locked StayQR helper functions are missing.';
  end if;
end;
$preflight$;

-- Existing composite identities used by tenant-safe foreign keys.
create unique index if not exists uq_menu_items_hotel_id_id
on public.menu_items (hotel_id, id);

create unique index if not exists uq_food_orders_hotel_id_id
on public.food_orders (hotel_id, id);

create unique index if not exists uq_food_order_items_hotel_id_id
on public.food_order_items (hotel_id, id);

create unique index if not exists uq_service_requests_hotel_id_id
on public.service_requests (hotel_id, id);

create unique index if not exists uq_staff_hotel_id_id
on public.staff (hotel_id, id);

-- ============================================================================
-- 1. Menu service windows and item tax/availability metadata
-- ============================================================================

alter table public.menu_categories
  add column if not exists service_start_time time,
  add column if not exists service_end_time time;

alter table public.menu_items
  add column if not exists tax_rate numeric(7,4) not null default 0,
  add column if not exists tax_inclusive boolean not null default false,
  add column if not exists preparation_minutes integer not null default 20,
  add column if not exists sort_order integer not null default 0,
  add column if not exists archived_at timestamptz;

alter table public.menu_items
  drop constraint if exists menu_items_day15_tax_rate_check,
  drop constraint if exists menu_items_day15_preparation_minutes_check,
  drop constraint if exists menu_items_day15_sort_order_check;

alter table public.menu_items
  add constraint menu_items_day15_tax_rate_check
    check (tax_rate between 0 and 100) not valid,
  add constraint menu_items_day15_preparation_minutes_check
    check (preparation_minutes between 0 and 1440) not valid,
  add constraint menu_items_day15_sort_order_check
    check (sort_order between -100000 and 100000) not valid;

alter table public.menu_items
  validate constraint menu_items_day15_tax_rate_check;
alter table public.menu_items
  validate constraint menu_items_day15_preparation_minutes_check;
alter table public.menu_items
  validate constraint menu_items_day15_sort_order_check;

create index if not exists idx_menu_items_hotel_available_sort
on public.menu_items (
  hotel_id,
  is_available,
  archived_at,
  sort_order,
  item_name
);

-- ============================================================================
-- 2. Menu modifier configuration
-- ============================================================================

create table if not exists public.menu_item_modifier_groups (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null,
  menu_item_id uuid not null,
  name text not null,
  min_selections integer not null default 0,
  max_selections integer not null default 1,
  is_required boolean not null default false,
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint menu_item_modifier_groups_name_not_blank
    check (length(trim(name)) > 0),
  constraint menu_item_modifier_groups_selection_check
    check (
      min_selections >= 0
      and max_selections >= 1
      and max_selections <= 25
      and min_selections <= max_selections
    ),
  constraint menu_item_modifier_groups_required_check
    check (not is_required or min_selections >= 1),
  constraint menu_item_modifier_groups_hotel_item_fkey
    foreign key (hotel_id, menu_item_id)
    references public.menu_items(hotel_id, id)
    on delete cascade
);

create unique index if not exists uq_menu_item_modifier_groups_hotel_id_id
on public.menu_item_modifier_groups (hotel_id, id);

create unique index if not exists uq_menu_item_modifier_groups_item_name
on public.menu_item_modifier_groups (
  hotel_id,
  menu_item_id,
  lower(trim(name))
);

create index if not exists idx_menu_item_modifier_groups_item_active_sort
on public.menu_item_modifier_groups (
  hotel_id,
  menu_item_id,
  is_active,
  sort_order
);

create table if not exists public.menu_item_modifiers (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null,
  modifier_group_id uuid not null,
  name text not null,
  price_delta numeric(14,2) not null default 0,
  is_available boolean not null default true,
  sort_order integer not null default 0,
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint menu_item_modifiers_name_not_blank
    check (length(trim(name)) > 0),
  constraint menu_item_modifiers_price_delta_check
    check (price_delta >= 0),
  constraint menu_item_modifiers_hotel_group_fkey
    foreign key (hotel_id, modifier_group_id)
    references public.menu_item_modifier_groups(hotel_id, id)
    on delete cascade
);

create unique index if not exists uq_menu_item_modifiers_hotel_id_id
on public.menu_item_modifiers (hotel_id, id);

create unique index if not exists uq_menu_item_modifiers_group_name
on public.menu_item_modifiers (
  hotel_id,
  modifier_group_id,
  lower(trim(name))
);

create index if not exists idx_menu_item_modifiers_group_available_sort
on public.menu_item_modifiers (
  hotel_id,
  modifier_group_id,
  is_available,
  sort_order
);

drop trigger if exists set_menu_item_modifier_groups_updated_at
on public.menu_item_modifier_groups;

create trigger set_menu_item_modifier_groups_updated_at
before update on public.menu_item_modifier_groups
for each row execute function private.set_updated_at();

drop trigger if exists set_menu_item_modifiers_updated_at
on public.menu_item_modifiers;

create trigger set_menu_item_modifiers_updated_at
before update on public.menu_item_modifiers
for each row execute function private.set_updated_at();

-- ============================================================================
-- 3. Food order operational metadata
-- ============================================================================

alter table public.food_orders
  add column if not exists guest_session_id uuid,
  add column if not exists subtotal_amount numeric(14,2),
  add column if not exists modifier_amount numeric(14,2),
  add column if not exists tax_amount numeric(14,2),
  add column if not exists currency_code text,
  add column if not exists idempotency_key text,
  add column if not exists accepted_at timestamptz,
  add column if not exists preparing_at timestamptz,
  add column if not exists ready_at timestamptz,
  add column if not exists out_for_delivery_at timestamptz,
  add column if not exists cancelled_at timestamptz,
  add column if not exists cancelled_by uuid
    references auth.users(id) on delete set null,
  add column if not exists cancellation_reason text,
  add column if not exists folio_item_id uuid
    references public.folio_items(id) on delete set null,
  add column if not exists folio_posted_at timestamptz,
  add column if not exists updated_at timestamptz;

update public.food_orders
set
  subtotal_amount = coalesce(subtotal_amount, total_amount, 0),
  modifier_amount = coalesce(modifier_amount, 0),
  tax_amount = coalesce(tax_amount, 0),
  currency_code = upper(coalesce(nullif(trim(currency_code), ''), 'INR')),
  updated_at = coalesce(updated_at, created_at, now());

alter table public.food_orders
  alter column subtotal_amount set default 0,
  alter column subtotal_amount set not null,
  alter column modifier_amount set default 0,
  alter column modifier_amount set not null,
  alter column tax_amount set default 0,
  alter column tax_amount set not null,
  alter column currency_code set default 'INR',
  alter column currency_code set not null,
  alter column updated_at set default now(),
  alter column updated_at set not null;

-- Safely map existing orders to exactly one stay where Day 11 can prove it.
do $map_food_sessions$
declare
  source_row record;
  mapping_value jsonb;
  mapped_session_id uuid;
begin
  for source_row in
    select fo.id, fo.hotel_id, fo.guest_id, fo.room_id, fo.created_at
    from public.food_orders fo
    where fo.guest_session_id is null
    order by fo.hotel_id, fo.created_at, fo.id
  loop
    mapping_value := private.day11_resolve_financial_source_session(
      source_row.hotel_id,
      source_row.guest_id,
      source_row.room_id,
      source_row.created_at,
      false
    );

    if coalesce((mapping_value ->> 'candidate_count')::integer, 0) = 1 then
      mapped_session_id :=
        nullif(mapping_value ->> 'guest_session_id', '')::uuid;

      update public.food_orders
      set guest_session_id = mapped_session_id
      where id = source_row.id
        and hotel_id = source_row.hotel_id
        and guest_session_id is null;
    end if;
  end loop;
end;
$map_food_sessions$;

do $food_session_fk$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'food_orders_hotel_guest_session_fkey'
      and conrelid = 'public.food_orders'::regclass
  ) then
    alter table public.food_orders
      add constraint food_orders_hotel_guest_session_fkey
      foreign key (hotel_id, guest_session_id)
      references public.guest_sessions(hotel_id, id)
      on delete set null
      not valid;

    alter table public.food_orders
      validate constraint food_orders_hotel_guest_session_fkey;
  end if;
end;
$food_session_fk$;

alter table public.food_orders
  drop constraint if exists food_orders_order_status_check,
  drop constraint if exists food_orders_amounts_check,
  drop constraint if exists food_orders_currency_code_check,
  drop constraint if exists food_orders_idempotency_key_check,
  drop constraint if exists food_orders_cancellation_reason_check;

alter table public.food_orders
  add constraint food_orders_order_status_check
    check (
      order_status in (
        'pending',
        'accepted',
        'preparing',
        'ready',
        'out_for_delivery',
        'delivered',
        'cancelled'
      )
    ) not valid,
  add constraint food_orders_amounts_check
    check (
      subtotal_amount >= 0
      and modifier_amount >= 0
      and tax_amount >= 0
      and total_amount >= 0
      and total_amount = round(
        subtotal_amount + modifier_amount + tax_amount,
        2
      )
    ) not valid,
  add constraint food_orders_currency_code_check
    check (currency_code ~ '^[A-Z]{3}$') not valid,
  add constraint food_orders_idempotency_key_check
    check (
      idempotency_key is null
      or length(trim(idempotency_key)) between 8 and 160
    ) not valid,
  add constraint food_orders_cancellation_reason_check
    check (
      cancellation_reason is null
      or length(trim(cancellation_reason)) between 3 and 500
    ) not valid;

alter table public.food_orders
  validate constraint food_orders_order_status_check;
alter table public.food_orders
  validate constraint food_orders_amounts_check;
alter table public.food_orders
  validate constraint food_orders_currency_code_check;
alter table public.food_orders
  validate constraint food_orders_idempotency_key_check;
alter table public.food_orders
  validate constraint food_orders_cancellation_reason_check;

create unique index if not exists uq_food_orders_hotel_idempotency
on public.food_orders (hotel_id, idempotency_key)
where idempotency_key is not null;

create index if not exists idx_food_orders_hotel_session_created
on public.food_orders (hotel_id, guest_session_id, created_at desc);

create index if not exists idx_food_orders_hotel_status_created
on public.food_orders (hotel_id, order_status, created_at desc);

drop trigger if exists set_food_orders_day15_updated_at
on public.food_orders;

create trigger set_food_orders_day15_updated_at
before update on public.food_orders
for each row execute function private.set_updated_at();

-- ============================================================================
-- 4. Food order item snapshots and selected modifiers
-- ============================================================================

alter table public.food_order_items
  add column if not exists item_name_snapshot text,
  add column if not exists unit_price numeric(14,2),
  add column if not exists modifier_amount numeric(14,2),
  add column if not exists tax_rate numeric(7,4),
  add column if not exists tax_amount numeric(14,2),
  add column if not exists line_total numeric(14,2);

update public.food_order_items foi
set
  item_name_snapshot = coalesce(
    nullif(trim(foi.item_name_snapshot), ''),
    mi.item_name,
    'Menu item'
  ),
  unit_price = coalesce(foi.unit_price, foi.price, 0),
  modifier_amount = coalesce(foi.modifier_amount, 0),
  tax_rate = coalesce(foi.tax_rate, 0),
  tax_amount = coalesce(foi.tax_amount, 0),
  line_total = coalesce(
    foi.line_total,
    round(coalesce(foi.quantity, 0) * coalesce(foi.price, 0), 2)
  )
from public.menu_items mi
where mi.id = foi.menu_item_id
  and mi.hotel_id = foi.hotel_id;

alter table public.food_order_items
  alter column item_name_snapshot set not null,
  alter column unit_price set default 0,
  alter column unit_price set not null,
  alter column modifier_amount set default 0,
  alter column modifier_amount set not null,
  alter column tax_rate set default 0,
  alter column tax_rate set not null,
  alter column tax_amount set default 0,
  alter column tax_amount set not null,
  alter column line_total set default 0,
  alter column line_total set not null;

alter table public.food_order_items
  drop constraint if exists food_order_items_amounts_check,
  drop constraint if exists food_order_items_name_snapshot_check;

alter table public.food_order_items
  add constraint food_order_items_amounts_check
    check (
      quantity between 1 and 100
      and unit_price >= 0
      and modifier_amount >= 0
      and tax_rate between 0 and 100
      and tax_amount >= 0
      and line_total >= 0
      and price >= 0
      and line_total = round(quantity * price, 2)
    ) not valid,
  add constraint food_order_items_name_snapshot_check
    check (length(trim(item_name_snapshot)) > 0) not valid;

alter table public.food_order_items
  validate constraint food_order_items_amounts_check;
alter table public.food_order_items
  validate constraint food_order_items_name_snapshot_check;

create table if not exists public.food_order_item_modifiers (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null,
  food_order_item_id uuid not null,
  modifier_id uuid,
  modifier_name_snapshot text not null,
  price_delta numeric(14,2) not null default 0,
  created_at timestamptz not null default now(),
  constraint food_order_item_modifiers_name_not_blank
    check (length(trim(modifier_name_snapshot)) > 0),
  constraint food_order_item_modifiers_price_delta_check
    check (price_delta >= 0),
  constraint food_order_item_modifiers_hotel_item_fkey
    foreign key (hotel_id, food_order_item_id)
    references public.food_order_items(hotel_id, id)
    on delete cascade,
  constraint food_order_item_modifiers_hotel_modifier_fkey
    foreign key (hotel_id, modifier_id)
    references public.menu_item_modifiers(hotel_id, id)
    on delete set null
);

create unique index if not exists uq_food_order_item_modifiers_item_modifier
on public.food_order_item_modifiers (
  hotel_id,
  food_order_item_id,
  modifier_id
)
where modifier_id is not null;

create index if not exists idx_food_order_item_modifiers_item
on public.food_order_item_modifiers (
  hotel_id,
  food_order_item_id,
  created_at
);

-- ============================================================================
-- 5. Food order event history and KOT identity
-- ============================================================================

create table if not exists public.food_order_events (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null,
  food_order_id uuid not null,
  event_type text not null,
  from_status text,
  to_status text,
  actor_user_id uuid references auth.users(id) on delete set null,
  actor_staff_id uuid,
  estimated_minutes integer,
  message text,
  idempotency_key text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint food_order_events_event_type_not_blank
    check (length(trim(event_type)) > 0),
  constraint food_order_events_idempotency_not_blank
    check (length(trim(idempotency_key)) between 8 and 200),
  constraint food_order_events_estimated_minutes_check
    check (
      estimated_minutes is null
      or estimated_minutes between 0 and 1440
    ),
  constraint food_order_events_metadata_object_check
    check (jsonb_typeof(metadata) = 'object'),
  constraint food_order_events_hotel_order_fkey
    foreign key (hotel_id, food_order_id)
    references public.food_orders(hotel_id, id)
    on delete cascade,
  constraint food_order_events_hotel_staff_fkey
    foreign key (hotel_id, actor_staff_id)
    references public.staff(hotel_id, id)
    on delete set null
);

create unique index if not exists uq_food_order_events_idempotency
on public.food_order_events (
  hotel_id,
  food_order_id,
  idempotency_key
);

create index if not exists idx_food_order_events_order_created
on public.food_order_events (
  hotel_id,
  food_order_id,
  created_at
);

insert into public.food_order_events (
  hotel_id,
  food_order_id,
  event_type,
  from_status,
  to_status,
  idempotency_key,
  metadata,
  created_at
)
select
  fo.hotel_id,
  fo.id,
  'legacy_state_imported',
  null,
  fo.order_status,
  'legacy-state:' || fo.order_status,
  jsonb_build_object(
    'source', 'migration_051',
    'legacy_created_at', fo.created_at
  ),
  coalesce(fo.updated_at, fo.created_at, now())
from public.food_orders fo
on conflict (
  hotel_id,
  food_order_id,
  idempotency_key
) do nothing;

create table if not exists public.kitchen_tickets (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null,
  food_order_id uuid not null,
  ticket_number text not null,
  print_count integer not null default 0,
  first_printed_at timestamptz,
  last_printed_at timestamptz,
  last_printed_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint kitchen_tickets_number_not_blank
    check (length(trim(ticket_number)) > 0),
  constraint kitchen_tickets_print_count_check
    check (print_count >= 0),
  constraint kitchen_tickets_hotel_order_fkey
    foreign key (hotel_id, food_order_id)
    references public.food_orders(hotel_id, id)
    on delete cascade
);

create unique index if not exists uq_kitchen_tickets_hotel_order
on public.kitchen_tickets (hotel_id, food_order_id);

create unique index if not exists uq_kitchen_tickets_hotel_number
on public.kitchen_tickets (hotel_id, ticket_number);

-- ============================================================================
-- 6. Service type departments and SLA defaults
-- ============================================================================

alter table public.service_request_types
  add column if not exists department text,
  add column if not exists sla_minutes integer,
  add column if not exists escalation_minutes integer,
  add column if not exists notification_template jsonb;

update public.service_request_types
set
  department = coalesce(
    nullif(trim(department), ''),
    case
      when lower(code || ' ' || name) ~
        '(housekeep|water|towel|toiletr|blanket|clean)'
        then 'housekeeping'
      when lower(code || ' ' || name) ~
        '(maintenance|repair|electric|plumb|geyser|ac)'
        then 'maintenance'
      when lower(code || ' ' || name) ~ '(laundry)'
        then 'laundry'
      when lower(code || ' ' || name) ~
        '(cab|taxi|transport|tour|travel)'
        then 'transport'
      when lower(code || ' ' || name) ~
        '(checkout|reception|front.desk)'
        then 'front_office'
      else 'guest_services'
    end
  ),
  sla_minutes = coalesce(
    sla_minutes,
    nullif(default_estimated_minutes, 0),
    case
      when lower(code || ' ' || name) ~ '(checkout|maintenance)'
        then 15
      else 30
    end
  ),
  escalation_minutes = coalesce(escalation_minutes, 15),
  notification_template = coalesce(notification_template, '{}'::jsonb);

alter table public.service_request_types
  alter column department set default 'guest_services',
  alter column department set not null,
  alter column sla_minutes set default 30,
  alter column sla_minutes set not null,
  alter column escalation_minutes set default 15,
  alter column escalation_minutes set not null,
  alter column notification_template set default '{}'::jsonb,
  alter column notification_template set not null;

alter table public.service_request_types
  drop constraint if exists service_request_types_department_check,
  drop constraint if exists service_request_types_sla_check,
  drop constraint if exists service_request_types_escalation_check,
  drop constraint if exists service_request_types_notification_object_check;

alter table public.service_request_types
  add constraint service_request_types_department_check
    check (
      department in (
        'front_office',
        'housekeeping',
        'maintenance',
        'restaurant',
        'laundry',
        'transport',
        'guest_services',
        'accounts',
        'management'
      )
    ) not valid,
  add constraint service_request_types_sla_check
    check (sla_minutes between 1 and 1440) not valid,
  add constraint service_request_types_escalation_check
    check (escalation_minutes between 1 and 1440) not valid,
  add constraint service_request_types_notification_object_check
    check (jsonb_typeof(notification_template) = 'object') not valid;

alter table public.service_request_types
  validate constraint service_request_types_department_check;
alter table public.service_request_types
  validate constraint service_request_types_sla_check;
alter table public.service_request_types
  validate constraint service_request_types_escalation_check;
alter table public.service_request_types
  validate constraint service_request_types_notification_object_check;

create index if not exists idx_service_request_types_hotel_department_active
on public.service_request_types (
  hotel_id,
  department,
  guest_visible,
  is_active,
  sort_order
);

-- ============================================================================
-- 7. Service request operational metadata and assignment compatibility
-- ============================================================================

alter table public.service_requests
  add column if not exists guest_session_id uuid,
  add column if not exists department text,
  add column if not exists assigned_staff_id uuid,
  add column if not exists sla_due_at timestamptz,
  add column if not exists escalation_due_at timestamptz,
  add column if not exists escalated_at timestamptz,
  add column if not exists escalation_level integer not null default 0,
  add column if not exists cancelled_at timestamptz,
  add column if not exists cancellation_reason text,
  add column if not exists folio_item_id uuid
    references public.folio_items(id) on delete set null,
  add column if not exists folio_posted_at timestamptz,
  add column if not exists updated_at timestamptz;

update public.service_requests sr
set
  department = coalesce(
    nullif(trim(sr.department), ''),
    srt.department,
    'guest_services'
  ),
  assigned_staff_id = coalesce(
    sr.assigned_staff_id,
    case
      when exists (
        select 1
        from public.staff s
        where s.hotel_id = sr.hotel_id
          and s.id = sr.assigned_to
      ) then sr.assigned_to
      else null
    end
  ),
  sla_due_at = coalesce(
    sr.sla_due_at,
    sr.created_at
      + make_interval(mins => coalesce(srt.sla_minutes, 30))
  ),
  escalation_due_at = coalesce(
    sr.escalation_due_at,
    sr.created_at
      + make_interval(
          mins =>
            coalesce(srt.sla_minutes, 30)
            + coalesce(srt.escalation_minutes, 15)
        )
  ),
  escalation_level = coalesce(sr.escalation_level, 0),
  updated_at = coalesce(sr.updated_at, sr.created_at, now())
from public.service_request_types srt
where srt.id = sr.request_type_id
  and srt.hotel_id = sr.hotel_id;

update public.service_requests
set
  department = coalesce(nullif(trim(department), ''), 'guest_services'),
  sla_due_at = coalesce(sla_due_at, created_at + interval '30 minutes'),
  escalation_due_at = coalesce(
    escalation_due_at,
    created_at + interval '45 minutes'
  ),
  updated_at = coalesce(updated_at, created_at, now())
where request_type_id is null;

alter table public.service_requests
  alter column department set default 'guest_services',
  alter column department set not null,
  alter column updated_at set default now(),
  alter column updated_at set not null;

do $map_service_sessions$
declare
  source_row record;
  mapping_value jsonb;
  mapped_session_id uuid;
begin
  for source_row in
    select sr.id, sr.hotel_id, sr.guest_id, sr.room_id, sr.created_at
    from public.service_requests sr
    where sr.guest_session_id is null
    order by sr.hotel_id, sr.created_at, sr.id
  loop
    mapping_value := private.day11_resolve_financial_source_session(
      source_row.hotel_id,
      source_row.guest_id,
      source_row.room_id,
      source_row.created_at,
      false
    );

    if coalesce((mapping_value ->> 'candidate_count')::integer, 0) = 1 then
      mapped_session_id :=
        nullif(mapping_value ->> 'guest_session_id', '')::uuid;

      update public.service_requests
      set guest_session_id = mapped_session_id
      where id = source_row.id
        and hotel_id = source_row.hotel_id
        and guest_session_id is null;
    end if;
  end loop;
end;
$map_service_sessions$;

do $service_session_fk$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'service_requests_hotel_guest_session_fkey'
      and conrelid = 'public.service_requests'::regclass
  ) then
    alter table public.service_requests
      add constraint service_requests_hotel_guest_session_fkey
      foreign key (hotel_id, guest_session_id)
      references public.guest_sessions(hotel_id, id)
      on delete set null
      not valid;

    alter table public.service_requests
      validate constraint service_requests_hotel_guest_session_fkey;
  end if;
end;
$service_session_fk$;

do $service_staff_fk$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'service_requests_hotel_assigned_staff_fkey'
      and conrelid = 'public.service_requests'::regclass
  ) then
    alter table public.service_requests
      add constraint service_requests_hotel_assigned_staff_fkey
      foreign key (hotel_id, assigned_staff_id)
      references public.staff(hotel_id, id)
      on delete set null
      not valid;

    alter table public.service_requests
      validate constraint service_requests_hotel_assigned_staff_fkey;
  end if;
end;
$service_staff_fk$;

alter table public.service_requests
  drop constraint if exists service_requests_department_check,
  drop constraint if exists service_requests_escalation_level_check,
  drop constraint if exists service_requests_cancellation_reason_check;

alter table public.service_requests
  add constraint service_requests_department_check
    check (
      department in (
        'front_office',
        'housekeeping',
        'maintenance',
        'restaurant',
        'laundry',
        'transport',
        'guest_services',
        'accounts',
        'management'
      )
    ) not valid,
  add constraint service_requests_escalation_level_check
    check (escalation_level between 0 and 10) not valid,
  add constraint service_requests_cancellation_reason_check
    check (
      cancellation_reason is null
      or length(trim(cancellation_reason)) between 3 and 500
    ) not valid;

alter table public.service_requests
  validate constraint service_requests_department_check;
alter table public.service_requests
  validate constraint service_requests_escalation_level_check;
alter table public.service_requests
  validate constraint service_requests_cancellation_reason_check;

create index if not exists idx_service_requests_hotel_department_status
on public.service_requests (
  hotel_id,
  department,
  status,
  created_at desc
);

create index if not exists idx_service_requests_hotel_sla_due
on public.service_requests (
  hotel_id,
  sla_due_at
)
where status in ('pending', 'accepted', 'in_progress', 'escalated');

create index if not exists idx_service_requests_hotel_assigned_status
on public.service_requests (
  hotel_id,
  assigned_staff_id,
  status,
  created_at desc
);

create index if not exists idx_service_requests_hotel_session_created
on public.service_requests (
  hotel_id,
  guest_session_id,
  created_at desc
);

create or replace function private.day15_sync_service_assignment_columns()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
begin
  if new.assigned_staff_id is distinct from old.assigned_staff_id then
    new.assigned_to := new.assigned_staff_id;
  elsif new.assigned_to is distinct from old.assigned_to then
    new.assigned_staff_id := new.assigned_to;
  end if;

  return new;
end;
$function$;

revoke all on function private.day15_sync_service_assignment_columns()
from public, anon, authenticated;

drop trigger if exists sync_service_assignment_columns_day15
on public.service_requests;

create trigger sync_service_assignment_columns_day15
before update of assigned_to, assigned_staff_id
on public.service_requests
for each row execute function
  private.day15_sync_service_assignment_columns();

drop trigger if exists set_service_requests_day15_updated_at
on public.service_requests;

create trigger set_service_requests_day15_updated_at
before update on public.service_requests
for each row execute function private.set_updated_at();

-- ============================================================================
-- 8. Service event, guest-notification and escalation ledgers
-- ============================================================================

create table if not exists public.service_request_events (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null,
  service_request_id uuid not null,
  event_type text not null,
  from_status text,
  to_status text,
  actor_user_id uuid references auth.users(id) on delete set null,
  actor_staff_id uuid,
  assigned_staff_id uuid,
  message text,
  idempotency_key text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint service_request_events_event_type_not_blank
    check (length(trim(event_type)) > 0),
  constraint service_request_events_idempotency_not_blank
    check (length(trim(idempotency_key)) between 8 and 200),
  constraint service_request_events_metadata_object_check
    check (jsonb_typeof(metadata) = 'object'),
  constraint service_request_events_hotel_request_fkey
    foreign key (hotel_id, service_request_id)
    references public.service_requests(hotel_id, id)
    on delete cascade,
  constraint service_request_events_hotel_actor_staff_fkey
    foreign key (hotel_id, actor_staff_id)
    references public.staff(hotel_id, id)
    on delete set null,
  constraint service_request_events_hotel_assigned_staff_fkey
    foreign key (hotel_id, assigned_staff_id)
    references public.staff(hotel_id, id)
    on delete set null
);

create unique index if not exists uq_service_request_events_idempotency
on public.service_request_events (
  hotel_id,
  service_request_id,
  idempotency_key
);

create index if not exists idx_service_request_events_request_created
on public.service_request_events (
  hotel_id,
  service_request_id,
  created_at
);

insert into public.service_request_events (
  hotel_id,
  service_request_id,
  event_type,
  from_status,
  to_status,
  assigned_staff_id,
  idempotency_key,
  metadata,
  created_at
)
select
  sr.hotel_id,
  sr.id,
  'legacy_state_imported',
  null,
  sr.status,
  sr.assigned_staff_id,
  'legacy-state:' || sr.status,
  jsonb_build_object(
    'source', 'migration_051',
    'legacy_created_at', sr.created_at
  ),
  coalesce(sr.updated_at, sr.created_at, now())
from public.service_requests sr
on conflict (
  hotel_id,
  service_request_id,
  idempotency_key
) do nothing;

create table if not exists public.guest_notifications (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null,
  guest_session_id uuid,
  room_id uuid not null,
  guest_id uuid not null,
  source_type text not null,
  source_id uuid not null,
  event_key text not null,
  title text not null,
  message text not null,
  status text not null default 'unread',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  read_at timestamptz,
  constraint guest_notifications_source_type_check
    check (source_type in ('food_order', 'service_request', 'system')),
  constraint guest_notifications_event_key_not_blank
    check (length(trim(event_key)) > 0),
  constraint guest_notifications_title_not_blank
    check (length(trim(title)) > 0),
  constraint guest_notifications_message_not_blank
    check (length(trim(message)) > 0),
  constraint guest_notifications_status_check
    check (status in ('unread', 'read', 'dismissed')),
  constraint guest_notifications_metadata_object_check
    check (jsonb_typeof(metadata) = 'object'),
  constraint guest_notifications_hotel_session_fkey
    foreign key (hotel_id, guest_session_id)
    references public.guest_sessions(hotel_id, id)
    on delete cascade
);

create unique index if not exists uq_guest_notifications_source_event
on public.guest_notifications (
  hotel_id,
  source_type,
  source_id,
  event_key
);

create index if not exists idx_guest_notifications_session_created
on public.guest_notifications (
  hotel_id,
  guest_session_id,
  created_at desc
);

create table if not exists public.service_escalations (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null,
  service_request_id uuid not null,
  escalation_level integer not null,
  reason text not null,
  escalated_at timestamptz not null default now(),
  acknowledged_at timestamptz,
  acknowledged_by uuid references auth.users(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  constraint service_escalations_level_check
    check (escalation_level between 1 and 10),
  constraint service_escalations_reason_not_blank
    check (length(trim(reason)) between 3 and 500),
  constraint service_escalations_metadata_object_check
    check (jsonb_typeof(metadata) = 'object'),
  constraint service_escalations_hotel_request_fkey
    foreign key (hotel_id, service_request_id)
    references public.service_requests(hotel_id, id)
    on delete cascade
);

create unique index if not exists uq_service_escalations_request_level
on public.service_escalations (
  hotel_id,
  service_request_id,
  escalation_level
);

create index if not exists idx_service_escalations_hotel_open
on public.service_escalations (
  hotel_id,
  escalated_at
)
where acknowledged_at is null;

-- ============================================================================
-- 9. RLS, privileges and policies
-- ============================================================================

alter table public.menu_item_modifier_groups enable row level security;
alter table public.menu_item_modifiers enable row level security;
alter table public.food_order_item_modifiers enable row level security;
alter table public.food_order_events enable row level security;
alter table public.kitchen_tickets enable row level security;
alter table public.service_request_events enable row level security;
alter table public.guest_notifications enable row level security;
alter table public.service_escalations enable row level security;

revoke all on
  public.menu_item_modifier_groups,
  public.menu_item_modifiers,
  public.food_order_item_modifiers,
  public.food_order_events,
  public.kitchen_tickets,
  public.service_request_events,
  public.guest_notifications,
  public.service_escalations
from public, anon;

grant select, insert, update, delete
on public.menu_item_modifier_groups,
   public.menu_item_modifiers
to authenticated;

grant select
on public.food_order_item_modifiers,
   public.food_order_events,
   public.kitchen_tickets,
   public.service_request_events,
   public.guest_notifications,
   public.service_escalations
to authenticated;

grant select, insert, update, delete
on public.menu_item_modifier_groups,
   public.menu_item_modifiers,
   public.food_order_item_modifiers,
   public.food_order_events,
   public.kitchen_tickets,
   public.service_request_events,
   public.guest_notifications,
   public.service_escalations
to service_role;

drop policy if exists stayqr_modifier_groups_select
on public.menu_item_modifier_groups;
drop policy if exists stayqr_modifier_groups_insert
on public.menu_item_modifier_groups;
drop policy if exists stayqr_modifier_groups_update
on public.menu_item_modifier_groups;
drop policy if exists stayqr_modifier_groups_delete
on public.menu_item_modifier_groups;

create policy stayqr_modifier_groups_select
on public.menu_item_modifier_groups
for select to authenticated
using (
  private.user_has_any_permission(
    hotel_id,
    array['foodorders.view', 'menu.manage']
  )
);

create policy stayqr_modifier_groups_insert
on public.menu_item_modifier_groups
for insert to authenticated
with check (private.user_has_permission(hotel_id, 'menu.manage'));

create policy stayqr_modifier_groups_update
on public.menu_item_modifier_groups
for update to authenticated
using (private.user_has_permission(hotel_id, 'menu.manage'))
with check (private.user_has_permission(hotel_id, 'menu.manage'));

create policy stayqr_modifier_groups_delete
on public.menu_item_modifier_groups
for delete to authenticated
using (private.user_has_permission(hotel_id, 'menu.manage'));

drop policy if exists stayqr_modifiers_select
on public.menu_item_modifiers;
drop policy if exists stayqr_modifiers_insert
on public.menu_item_modifiers;
drop policy if exists stayqr_modifiers_update
on public.menu_item_modifiers;
drop policy if exists stayqr_modifiers_delete
on public.menu_item_modifiers;

create policy stayqr_modifiers_select
on public.menu_item_modifiers
for select to authenticated
using (
  private.user_has_any_permission(
    hotel_id,
    array['foodorders.view', 'menu.manage']
  )
);

create policy stayqr_modifiers_insert
on public.menu_item_modifiers
for insert to authenticated
with check (private.user_has_permission(hotel_id, 'menu.manage'));

create policy stayqr_modifiers_update
on public.menu_item_modifiers
for update to authenticated
using (private.user_has_permission(hotel_id, 'menu.manage'))
with check (private.user_has_permission(hotel_id, 'menu.manage'));

create policy stayqr_modifiers_delete
on public.menu_item_modifiers
for delete to authenticated
using (private.user_has_permission(hotel_id, 'menu.manage'));

drop policy if exists stayqr_food_item_modifiers_select
on public.food_order_item_modifiers;

create policy stayqr_food_item_modifiers_select
on public.food_order_item_modifiers
for select to authenticated
using (private.user_has_permission(hotel_id, 'foodorders.view'));

drop policy if exists stayqr_food_events_select
on public.food_order_events;

create policy stayqr_food_events_select
on public.food_order_events
for select to authenticated
using (private.user_has_permission(hotel_id, 'foodorders.view'));

drop policy if exists stayqr_kitchen_tickets_select
on public.kitchen_tickets;

create policy stayqr_kitchen_tickets_select
on public.kitchen_tickets
for select to authenticated
using (private.user_has_permission(hotel_id, 'foodorders.view'));

drop policy if exists stayqr_service_events_select
on public.service_request_events;

create policy stayqr_service_events_select
on public.service_request_events
for select to authenticated
using (private.user_has_permission(hotel_id, 'services.view'));

drop policy if exists stayqr_guest_notifications_select
on public.guest_notifications;

create policy stayqr_guest_notifications_select
on public.guest_notifications
for select to authenticated
using (
  private.user_has_any_permission(
    hotel_id,
    array['services.view', 'foodorders.view']
  )
);

drop policy if exists stayqr_service_escalations_select
on public.service_escalations;

create policy stayqr_service_escalations_select
on public.service_escalations
for select to authenticated
using (private.user_has_permission(hotel_id, 'services.view'));

-- ============================================================================
-- 10. Migration acceptance helper
-- ============================================================================

create or replace function private.day15_migration_051_acceptance_rev1()
returns table (
  suite text,
  test_name text,
  passed boolean,
  details text
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  r record;
  v_exists boolean;
  v_count bigint;
begin
  -- Required tables.
  for r in
    select unnest(array[
      'menu_item_modifier_groups',
      'menu_item_modifiers',
      'food_order_item_modifiers',
      'food_order_events',
      'kitchen_tickets',
      'service_request_events',
      'guest_notifications',
      'service_escalations'
    ]) as relation_name
  loop
    v_exists := to_regclass('public.' || r.relation_name) is not null;
    suite := 'A_TABLES';
    test_name := 'table_' || r.relation_name;
    passed := v_exists;
    details := case when v_exists then 'Exists.' else 'Missing.' end;
    return next;
  end loop;

  -- Required columns.
  for r in
    select * from (values
      ('menu_categories','service_start_time'),
      ('menu_categories','service_end_time'),
      ('menu_items','tax_rate'),
      ('menu_items','tax_inclusive'),
      ('menu_items','preparation_minutes'),
      ('menu_items','sort_order'),
      ('menu_items','archived_at'),

      ('food_orders','guest_session_id'),
      ('food_orders','subtotal_amount'),
      ('food_orders','modifier_amount'),
      ('food_orders','tax_amount'),
      ('food_orders','currency_code'),
      ('food_orders','idempotency_key'),
      ('food_orders','accepted_at'),
      ('food_orders','preparing_at'),
      ('food_orders','ready_at'),
      ('food_orders','out_for_delivery_at'),
      ('food_orders','cancelled_at'),
      ('food_orders','cancelled_by'),
      ('food_orders','cancellation_reason'),
      ('food_orders','folio_item_id'),
      ('food_orders','folio_posted_at'),
      ('food_orders','updated_at'),

      ('food_order_items','item_name_snapshot'),
      ('food_order_items','unit_price'),
      ('food_order_items','modifier_amount'),
      ('food_order_items','tax_rate'),
      ('food_order_items','tax_amount'),
      ('food_order_items','line_total'),

      ('service_request_types','department'),
      ('service_request_types','sla_minutes'),
      ('service_request_types','escalation_minutes'),
      ('service_request_types','notification_template'),

      ('service_requests','guest_session_id'),
      ('service_requests','department'),
      ('service_requests','assigned_staff_id'),
      ('service_requests','sla_due_at'),
      ('service_requests','escalation_due_at'),
      ('service_requests','escalated_at'),
      ('service_requests','escalation_level'),
      ('service_requests','cancelled_at'),
      ('service_requests','cancellation_reason'),
      ('service_requests','folio_item_id'),
      ('service_requests','folio_posted_at'),
      ('service_requests','updated_at')
    ) as c(table_name, column_name)
  loop
    select exists (
      select 1
      from information_schema.columns c
      where c.table_schema = 'public'
        and c.table_name = r.table_name
        and c.column_name = r.column_name
    )
    into v_exists;

    suite := 'B_COLUMNS';
    test_name := r.table_name || '_' || r.column_name;
    passed := v_exists;
    details := case when v_exists then 'Exists.' else 'Missing.' end;
    return next;
  end loop;

  -- Indexes.
  for r in
    select unnest(array[
      'uq_menu_items_hotel_id_id',
      'uq_food_orders_hotel_id_id',
      'uq_food_order_items_hotel_id_id',
      'uq_service_requests_hotel_id_id',
      'uq_staff_hotel_id_id',
      'uq_menu_item_modifier_groups_hotel_id_id',
      'uq_menu_item_modifiers_hotel_id_id',
      'uq_food_orders_hotel_idempotency',
      'idx_food_orders_hotel_status_created',
      'idx_food_orders_hotel_session_created',
      'uq_food_order_item_modifiers_item_modifier',
      'uq_food_order_events_idempotency',
      'uq_kitchen_tickets_hotel_order',
      'uq_kitchen_tickets_hotel_number',
      'idx_service_request_types_hotel_department_active',
      'idx_service_requests_hotel_department_status',
      'idx_service_requests_hotel_sla_due',
      'idx_service_requests_hotel_assigned_status',
      'idx_service_requests_hotel_session_created',
      'uq_service_request_events_idempotency',
      'uq_guest_notifications_source_event',
      'uq_service_escalations_request_level'
    ]) as index_name
  loop
    v_exists := to_regclass('public.' || r.index_name) is not null;
    suite := 'C_INDEXES';
    test_name := 'index_' || r.index_name;
    passed := v_exists;
    details := case when v_exists then 'Exists.' else 'Missing.' end;
    return next;
  end loop;

  -- Named constraints.
  for r in
    select unnest(array[
      'menu_items_day15_tax_rate_check',
      'menu_items_day15_preparation_minutes_check',
      'menu_item_modifier_groups_selection_check',
      'menu_item_modifiers_price_delta_check',
      'food_orders_hotel_guest_session_fkey',
      'food_orders_order_status_check',
      'food_orders_amounts_check',
      'food_orders_currency_code_check',
      'food_order_items_amounts_check',
      'food_order_item_modifiers_hotel_item_fkey',
      'food_order_events_hotel_order_fkey',
      'kitchen_tickets_hotel_order_fkey',
      'service_request_types_department_check',
      'service_request_types_sla_check',
      'service_requests_hotel_guest_session_fkey',
      'service_requests_hotel_assigned_staff_fkey',
      'service_requests_department_check',
      'service_request_events_hotel_request_fkey',
      'guest_notifications_hotel_session_fkey',
      'service_escalations_hotel_request_fkey'
    ]) as constraint_name
  loop
    select exists (
      select 1
      from pg_constraint pc
      where pc.conname = r.constraint_name
        and pc.convalidated
    )
    into v_exists;

    suite := 'D_CONSTRAINTS';
    test_name := 'constraint_' || r.constraint_name;
    passed := v_exists;
    details := case when v_exists
      then 'Exists and is validated.'
      else 'Missing or not validated.'
    end;
    return next;
  end loop;

  -- RLS.
  for r in
    select unnest(array[
      'menu_item_modifier_groups',
      'menu_item_modifiers',
      'food_order_item_modifiers',
      'food_order_events',
      'kitchen_tickets',
      'service_request_events',
      'guest_notifications',
      'service_escalations'
    ]) as relation_name
  loop
    select c.relrowsecurity
    into v_exists
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = r.relation_name;

    suite := 'E_RLS';
    test_name := 'rls_' || r.relation_name;
    passed := coalesce(v_exists, false);
    details := case when v_exists then 'Enabled.' else 'Not enabled.' end;
    return next;
  end loop;

  -- Anonymous direct writes blocked.
  for r in
    select unnest(array[
      'menu_item_modifier_groups',
      'menu_item_modifiers',
      'food_order_item_modifiers',
      'food_order_events',
      'kitchen_tickets',
      'service_request_events',
      'guest_notifications',
      'service_escalations'
    ]) as relation_name
  loop
    suite := 'F_PRIVILEGES';
    test_name := 'anon_no_write_' || r.relation_name;
    passed := not (
      has_table_privilege('anon', 'public.' || r.relation_name, 'INSERT')
      or has_table_privilege('anon', 'public.' || r.relation_name, 'UPDATE')
      or has_table_privilege('anon', 'public.' || r.relation_name, 'DELETE')
    );
    details := case when passed
      then 'anon has no direct write privilege.'
      else 'anon retains a direct write privilege.'
    end;
    return next;
  end loop;

  -- Operational ledgers are RPC/service-role write only.
  for r in
    select unnest(array[
      'food_order_item_modifiers',
      'food_order_events',
      'kitchen_tickets',
      'service_request_events',
      'guest_notifications',
      'service_escalations'
    ]) as relation_name
  loop
    suite := 'F_PRIVILEGES';
    test_name := 'authenticated_no_write_' || r.relation_name;
    passed := not (
      has_table_privilege(
        'authenticated',
        'public.' || r.relation_name,
        'INSERT'
      )
      or has_table_privilege(
        'authenticated',
        'public.' || r.relation_name,
        'UPDATE'
      )
      or has_table_privilege(
        'authenticated',
        'public.' || r.relation_name,
        'DELETE'
      )
    );
    details := case when passed
      then 'authenticated has no direct write privilege.'
      else 'authenticated retains a direct write privilege.'
    end;
    return next;
  end loop;

  -- Backfill/data integrity.
  select count(*)
  into v_count
  from public.food_orders
  where subtotal_amount is null
     or modifier_amount is null
     or tax_amount is null
     or currency_code is null
     or updated_at is null;

  suite := 'G_BACKFILL';
  test_name := 'food_order_required_backfill';
  passed := v_count = 0;
  details := format('%s incomplete food order backfill row(s).', v_count);
  return next;

  select count(*)
  into v_count
  from public.food_orders
  where total_amount <> round(
    subtotal_amount + modifier_amount + tax_amount,
    2
  );

  suite := 'G_BACKFILL';
  test_name := 'food_order_total_equation';
  passed := v_count = 0;
  details := format('%s food order total equation mismatch(es).', v_count);
  return next;

  select count(*)
  into v_count
  from public.food_order_items
  where item_name_snapshot is null
     or unit_price is null
     or modifier_amount is null
     or tax_rate is null
     or tax_amount is null
     or line_total is null
     or line_total <> round(quantity * price, 2);

  suite := 'G_BACKFILL';
  test_name := 'food_order_item_snapshot_backfill';
  passed := v_count = 0;
  details := format('%s incomplete food order item snapshot row(s).', v_count);
  return next;

  select count(*)
  into v_count
  from public.service_request_types
  where department is null
     or sla_minutes is null
     or escalation_minutes is null
     or notification_template is null;

  suite := 'G_BACKFILL';
  test_name := 'service_type_operational_defaults';
  passed := v_count = 0;
  details := format('%s incomplete service type default row(s).', v_count);
  return next;

  select count(*)
  into v_count
  from public.service_requests
  where department is null
     or sla_due_at is null
     or escalation_due_at is null
     or updated_at is null;

  suite := 'G_BACKFILL';
  test_name := 'service_request_operational_backfill';
  passed := v_count = 0;
  details := format('%s incomplete service request backfill row(s).', v_count);
  return next;

  select count(*)
  into v_count
  from (
    select hotel_id, food_order_id, idempotency_key
    from public.food_order_events
    group by hotel_id, food_order_id, idempotency_key
    having count(*) > 1
  ) d;

  suite := 'G_BACKFILL';
  test_name := 'food_event_idempotency';
  passed := v_count = 0;
  details := format('%s duplicated food event key group(s).', v_count);
  return next;

  select count(*)
  into v_count
  from (
    select hotel_id, service_request_id, idempotency_key
    from public.service_request_events
    group by hotel_id, service_request_id, idempotency_key
    having count(*) > 1
  ) d;

  suite := 'G_BACKFILL';
  test_name := 'service_event_idempotency';
  passed := v_count = 0;
  details := format('%s duplicated service event key group(s).', v_count);
  return next;

  select count(*)
  into v_count
  from (
    select hotel_id, folio_id, source_table, source_id
    from public.folio_items
    where posting_status = 'posted'
      and source_table in ('food_orders', 'service_requests')
      and source_id is not null
    group by hotel_id, folio_id, source_table, source_id
    having count(*) > 1
  ) d;

  suite := 'H_LOCKED_NON_REGRESSION';
  test_name := 'folio_source_exactly_once';
  passed := v_count = 0;
  details := format('%s duplicate posted folio source group(s).', v_count);
  return next;

  select count(*)
  into v_count
  from public.food_orders
  where order_status not in (
    'pending',
    'accepted',
    'preparing',
    'ready',
    'out_for_delivery',
    'delivered',
    'cancelled'
  );

  suite := 'H_LOCKED_NON_REGRESSION';
  test_name := 'food_status_values';
  passed := v_count = 0;
  details := format('%s unsupported food status row(s).', v_count);
  return next;

  select count(*)
  into v_count
  from public.service_requests
  where status not in (
    'pending',
    'accepted',
    'in_progress',
    'completed',
    'cancelled',
    'escalated'
  );

  suite := 'H_LOCKED_NON_REGRESSION';
  test_name := 'service_status_values';
  passed := v_count = 0;
  details := format('%s unsupported service status row(s).', v_count);
  return next;

  suite := 'H_LOCKED_NON_REGRESSION';
  test_name := 'legacy_food_status_column_retained';
  passed := exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'food_orders'
      and column_name = 'order_status'
  );
  details := 'food_orders.order_status remains available.';
  return next;

  suite := 'H_LOCKED_NON_REGRESSION';
  test_name := 'legacy_service_assignment_retained';
  passed := exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'service_requests'
      and column_name = 'assigned_to'
  );
  details := 'service_requests.assigned_to remains available.';
  return next;

  suite := 'H_LOCKED_NON_REGRESSION';
  test_name := 'migration_051_complete';
  passed := true;
  details :=
    'Day 15 operational schema foundation installed without deleting legacy contracts.';
  return next;
end;
$function$;

revoke all on function private.day15_migration_051_acceptance_rev1()
from public, anon, authenticated;

commit;

select suite, test_name, passed, details
from private.day15_migration_051_acceptance_rev1()
order by suite, test_name;
