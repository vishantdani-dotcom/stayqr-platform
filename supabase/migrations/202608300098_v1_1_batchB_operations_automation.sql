-- ============================================================================
-- StayQR v1.1 — Batch B: Hotel Operations & Automation
-- Migration 098
-- Date: 2026-08-30
--
-- Scope
--   1. Dedicated laundry operations workflow (reuses existing service/folio
--      foundations; does not create a second financial ledger)
--   2. Lost & found custody lifecycle
--   3. Simple consumable inventory with atomic stock movements
--   4. KOT printer profiles + auditable print events on top of Day 15 KOT
--   5. Scheduled report jobs + idempotent report snapshots on top of Day 16
--
-- Safety
--   * Additive and tenant-scoped.
--   * Existing food, service, folio, invoice, housekeeping and report RPCs are
--     not replaced.
--   * Writes are RPC-controlled; authenticated table access is read-only.
--   * No anonymous access is introduced.
-- ============================================================================

begin;

set local lock_timeout = '10s';
set local statement_timeout = '120s';

select pg_advisory_xact_lock(hashtext('stayqr:v1.1:batchB:098'));

-- --------------------------------------------------------------------------
-- 0. Preconditions
-- --------------------------------------------------------------------------
do $preflight$
begin
  if to_regclass('public.hotels') is null
     or to_regclass('public.rooms') is null
     or to_regclass('public.guests') is null
     or to_regclass('public.guest_sessions') is null
     or to_regclass('public.service_requests') is null
     or to_regclass('public.service_request_types') is null
     or to_regclass('public.food_orders') is null
     or to_regclass('public.kitchen_tickets') is null
     or to_regclass('public.staff') is null
  then
    raise exception 'Migration 098: required v1.0 operations foundation is missing.';
  end if;

  if to_regprocedure('private.user_has_any_permission(uuid,text[])') is null
     or to_regprocedure('public.get_food_order_kot(uuid,uuid)') is null
     or to_regprocedure('public.get_report_export_rows(uuid,date,date,text,jsonb)') is null
  then
    raise exception 'Migration 098: required authoritative RPC foundation is missing.';
  end if;
end;
$preflight$;

-- --------------------------------------------------------------------------
-- 1. Laundry operations
-- --------------------------------------------------------------------------
create table if not exists public.laundry_orders (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references public.hotels(id) on delete cascade,
  guest_session_id uuid references public.guest_sessions(id) on delete set null,
  room_id uuid references public.rooms(id) on delete set null,
  guest_id uuid references public.guests(id) on delete set null,
  service_request_id uuid references public.service_requests(id) on delete set null,
  order_number text not null,
  status text not null default 'received'
    check (status in ('received','washing','drying','ironing','ready','delivered','cancelled')),
  priority text not null default 'normal'
    check (priority in ('normal','express')),
  piece_count integer not null default 1 check (piece_count between 1 and 500),
  item_summary text not null check (length(trim(item_summary)) between 2 and 500),
  special_instructions text,
  promised_at timestamptz,
  received_at timestamptz not null default now(),
  ready_at timestamptz,
  delivered_at timestamptz,
  cancelled_at timestamptz,
  cancellation_reason text,
  assigned_staff_id uuid references public.staff(id) on delete set null,
  created_by uuid not null references auth.users(id) on delete restrict,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  constraint laundry_orders_metadata_object check (jsonb_typeof(metadata)='object'),
  constraint laundry_orders_cancel_check check (
    status <> 'cancelled' or (cancelled_at is not null and nullif(trim(cancellation_reason),'') is not null)
  ),
  constraint laundry_orders_ready_check check (status not in ('ready','delivered') or ready_at is not null),
  constraint laundry_orders_delivered_check check (status <> 'delivered' or delivered_at is not null),
  unique (hotel_id, order_number)
);

create index if not exists ix_laundry_orders_hotel_status
  on public.laundry_orders(hotel_id,status,created_at desc);
create index if not exists ix_laundry_orders_guest_session
  on public.laundry_orders(hotel_id,guest_session_id,created_at desc);

-- --------------------------------------------------------------------------
-- 2. Lost & found custody lifecycle
-- --------------------------------------------------------------------------
create table if not exists public.lost_found_items (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references public.hotels(id) on delete cascade,
  item_number text not null,
  item_name text not null check (length(trim(item_name)) between 2 and 160),
  description text,
  found_location text not null check (length(trim(found_location)) between 2 and 200),
  found_at timestamptz not null default now(),
  room_id uuid references public.rooms(id) on delete set null,
  guest_id uuid references public.guests(id) on delete set null,
  status text not null default 'stored'
    check (status in ('stored','matched','claimed','returned','disposed','donated')),
  storage_location text,
  claimant_name text,
  claimant_contact text,
  matched_at timestamptz,
  claimed_at timestamptz,
  closed_at timestamptz,
  closure_note text,
  created_by uuid not null references auth.users(id) on delete restrict,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  constraint lost_found_metadata_object check (jsonb_typeof(metadata)='object'),
  constraint lost_found_claim_check check (
    status not in ('claimed','returned') or (claimed_at is not null and nullif(trim(claimant_name),'') is not null)
  ),
  constraint lost_found_closed_check check (
    status not in ('returned','disposed','donated') or closed_at is not null
  ),
  unique (hotel_id,item_number)
);

create index if not exists ix_lost_found_hotel_status
  on public.lost_found_items(hotel_id,status,found_at desc);

-- --------------------------------------------------------------------------
-- 3. Simple consumable inventory
-- --------------------------------------------------------------------------
create table if not exists public.inventory_items (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references public.hotels(id) on delete cascade,
  sku text not null check (length(trim(sku)) between 2 and 60),
  name text not null check (length(trim(name)) between 2 and 160),
  category text not null default 'general'
    check (category in ('housekeeping','laundry','restaurant','maintenance','front_office','guest_amenity','general')),
  unit text not null default 'unit' check (length(trim(unit)) between 1 and 40),
  quantity_on_hand numeric(14,3) not null default 0 check (quantity_on_hand >= 0),
  reorder_level numeric(14,3) not null default 0 check (reorder_level >= 0),
  unit_cost numeric(14,2) check (unit_cost is null or unit_cost >= 0),
  is_active boolean not null default true,
  created_by uuid not null references auth.users(id) on delete restrict,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  constraint inventory_items_metadata_object check (jsonb_typeof(metadata)='object')
);

create unique index if not exists uq_inventory_items_sku
  on public.inventory_items(hotel_id,lower(sku));
create index if not exists ix_inventory_items_reorder
  on public.inventory_items(hotel_id,is_active,quantity_on_hand,reorder_level);

create table if not exists public.inventory_movements (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references public.hotels(id) on delete cascade,
  inventory_item_id uuid not null references public.inventory_items(id) on delete cascade,
  movement_type text not null
    check (movement_type in ('receive','consume','adjust_in','adjust_out','waste','return')),
  quantity_delta numeric(14,3) not null check (quantity_delta <> 0),
  quantity_before numeric(14,3) not null check (quantity_before >= 0),
  quantity_after numeric(14,3) not null check (quantity_after >= 0),
  reason text not null check (length(trim(reason)) between 2 and 300),
  reference_type text,
  reference_id uuid,
  request_key text not null check (length(trim(request_key)) between 8 and 180),
  actor_user_id uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  constraint inventory_movements_metadata_object check (jsonb_typeof(metadata)='object'),
  unique(hotel_id,request_key)
);

create index if not exists ix_inventory_movements_item
  on public.inventory_movements(hotel_id,inventory_item_id,created_at desc);

-- --------------------------------------------------------------------------
-- 4. KOT printer profiles + print event audit
-- --------------------------------------------------------------------------
create table if not exists public.kitchen_printer_profiles (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references public.hotels(id) on delete cascade,
  name text not null check (length(trim(name)) between 2 and 120),
  station text not null default 'kitchen'
    check (station in ('kitchen','bar','bakery','room_service','other')),
  paper_width_mm integer not null default 80 check (paper_width_mm in (58,80)),
  copies integer not null default 1 check (copies between 1 and 5),
  auto_print boolean not null default false,
  is_default boolean not null default false,
  is_active boolean not null default true,
  created_by uuid not null references auth.users(id) on delete restrict,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  constraint kitchen_printer_profiles_metadata_object check (jsonb_typeof(metadata)='object')
);

create unique index if not exists uq_kitchen_printer_profile_name
  on public.kitchen_printer_profiles(hotel_id,lower(name));
create unique index if not exists uq_kitchen_printer_default
  on public.kitchen_printer_profiles(hotel_id)
  where is_default and is_active;

create table if not exists public.kitchen_print_events (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references public.hotels(id) on delete cascade,
  food_order_id uuid not null references public.food_orders(id) on delete cascade,
  kitchen_ticket_id uuid references public.kitchen_tickets(id) on delete set null,
  printer_profile_id uuid references public.kitchen_printer_profiles(id) on delete set null,
  ticket_number text not null,
  requested_copies integer not null check (requested_copies between 1 and 5),
  actor_user_id uuid not null references auth.users(id) on delete restrict,
  printed_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  constraint kitchen_print_events_metadata_object check (jsonb_typeof(metadata)='object')
);

create index if not exists ix_kitchen_print_events_order
  on public.kitchen_print_events(hotel_id,food_order_id,printed_at desc);

-- --------------------------------------------------------------------------
-- 5. Scheduled report jobs + immutable run snapshots
-- --------------------------------------------------------------------------
create table if not exists public.scheduled_report_jobs (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references public.hotels(id) on delete cascade,
  name text not null check (length(trim(name)) between 2 and 140),
  report_key text not null check (report_key in (
    'occupancy_daily','revenue_daily','revenue_by_category','reservations_by_source',
    'arrivals_departures','payments_by_method','tax_gst_summary','guest_food_service',
    'service_sla','housekeeping','staff_department'
  )),
  frequency text not null default 'daily' check (frequency in ('daily','weekly','monthly')),
  lookback_days integer not null default 1 check (lookback_days between 1 and 367),
  filters jsonb not null default '{}'::jsonb,
  recipients text[] not null default '{}'::text[],
  enabled boolean not null default true,
  next_run_at timestamptz not null,
  last_run_at timestamptz,
  created_by uuid not null references auth.users(id) on delete restrict,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  constraint scheduled_report_jobs_filters_object check (jsonb_typeof(filters)='object'),
  constraint scheduled_report_jobs_metadata_object check (jsonb_typeof(metadata)='object')
);

create index if not exists ix_scheduled_report_jobs_due
  on public.scheduled_report_jobs(hotel_id,enabled,next_run_at);

create table if not exists public.scheduled_report_runs (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null references public.hotels(id) on delete cascade,
  job_id uuid not null references public.scheduled_report_jobs(id) on delete cascade,
  scheduled_for timestamptz not null,
  date_from date not null,
  date_to date not null,
  status text not null default 'generated' check (status in ('generated','failed')),
  row_count integer not null default 0 check (row_count >= 0),
  payload jsonb,
  error_message text,
  generated_by uuid references auth.users(id) on delete set null,
  generated_at timestamptz not null default now(),
  constraint scheduled_report_runs_date_check check (date_to >= date_from),
  constraint scheduled_report_runs_payload_object check (payload is null or jsonb_typeof(payload)='object'),
  unique(job_id,scheduled_for)
);

create index if not exists ix_scheduled_report_runs_job
  on public.scheduled_report_runs(hotel_id,job_id,generated_at desc);

-- --------------------------------------------------------------------------
-- 6. Default foundations for every existing hotel + future hotel trigger
-- --------------------------------------------------------------------------
insert into public.kitchen_printer_profiles(
  hotel_id,name,station,paper_width_mm,copies,auto_print,is_default,is_active,created_by
)
select h.id,'Kitchen Default','kitchen',80,1,false,true,true,
       coalesce((select s.auth_user_id from public.staff s where s.hotel_id=h.id and s.status='active' and s.auth_user_id is not null order by s.created_at limit 1),
                (select u.id from auth.users u order by u.created_at limit 1))
from public.hotels h
where not exists (
  select 1 from public.kitchen_printer_profiles p where p.hotel_id=h.id
)
and exists (select 1 from auth.users);

create or replace function private.v11b_seed_ops_foundations_after_hotel_insert()
returns trigger
language plpgsql
security definer
set search_path=''
as $fn$
declare v_actor uuid;
begin
  select u.id into v_actor from auth.users u order by u.created_at limit 1;
  if v_actor is not null then
    insert into public.kitchen_printer_profiles(
      hotel_id,name,station,paper_width_mm,copies,auto_print,is_default,is_active,created_by
    ) values (new.id,'Kitchen Default','kitchen',80,1,false,true,true,v_actor)
    on conflict do nothing;
  end if;
  return new;
end;
$fn$;

revoke all on function private.v11b_seed_ops_foundations_after_hotel_insert() from public,anon,authenticated;

drop trigger if exists trg_v11b_seed_ops_foundations_after_hotel_insert on public.hotels;
create trigger trg_v11b_seed_ops_foundations_after_hotel_insert
after insert on public.hotels
for each row execute function private.v11b_seed_ops_foundations_after_hotel_insert();

-- --------------------------------------------------------------------------
-- 7. RLS: read-only direct table access, RPC-controlled writes
-- --------------------------------------------------------------------------
alter table public.laundry_orders enable row level security;
alter table public.lost_found_items enable row level security;
alter table public.inventory_items enable row level security;
alter table public.inventory_movements enable row level security;
alter table public.kitchen_printer_profiles enable row level security;
alter table public.kitchen_print_events enable row level security;
alter table public.scheduled_report_jobs enable row level security;
alter table public.scheduled_report_runs enable row level security;

create policy stayqr_v11b_laundry_select on public.laundry_orders for select to authenticated
using (private.user_has_any_permission(hotel_id,array['services.view','services.manage','housekeeping.view','housekeeping.manage','hotel.manage']::text[]));
create policy stayqr_v11b_lost_found_select on public.lost_found_items for select to authenticated
using (private.user_has_any_permission(hotel_id,array['services.view','services.manage','housekeeping.view','housekeeping.manage','hotel.manage']::text[]));
create policy stayqr_v11b_inventory_items_select on public.inventory_items for select to authenticated
using (private.user_has_any_permission(hotel_id,array['housekeeping.view','housekeeping.manage','foodorders.view','foodorders.manage','rooms.view','hotel.manage']::text[]));
create policy stayqr_v11b_inventory_movements_select on public.inventory_movements for select to authenticated
using (private.user_has_any_permission(hotel_id,array['housekeeping.view','housekeeping.manage','foodorders.view','foodorders.manage','rooms.view','hotel.manage']::text[]));
create policy stayqr_v11b_printer_profiles_select on public.kitchen_printer_profiles for select to authenticated
using (private.user_has_any_permission(hotel_id,array['foodorders.view','foodorders.manage','hotel.manage']::text[]));
create policy stayqr_v11b_print_events_select on public.kitchen_print_events for select to authenticated
using (private.user_has_any_permission(hotel_id,array['foodorders.view','foodorders.manage','hotel.manage']::text[]));
create policy stayqr_v11b_report_jobs_select on public.scheduled_report_jobs for select to authenticated
using (private.user_has_any_permission(hotel_id,array['reports.view','hotel.manage']::text[]));
create policy stayqr_v11b_report_runs_select on public.scheduled_report_runs for select to authenticated
using (private.user_has_any_permission(hotel_id,array['reports.view','hotel.manage']::text[]));

-- --------------------------------------------------------------------------
-- 8. Shared access assertion + numbering helpers
-- --------------------------------------------------------------------------
create or replace function private.v11b_require_access(p_hotel_id uuid,p_permissions text[])
returns uuid
language plpgsql
security definer
set search_path=''
as $fn$
declare v_actor uuid := auth.uid();
begin
  if p_hotel_id is null then raise exception 'Hotel is required.'; end if;
  if v_actor is null then raise exception 'Authenticated actor is required.'; end if;
  if not private.user_has_any_permission(p_hotel_id,p_permissions) then
    raise exception 'You do not have permission for this operation.';
  end if;
  return v_actor;
end;
$fn$;

create or replace function private.v11b_next_number(p_hotel_id uuid,p_prefix text,p_table text,p_column text)
returns text
language plpgsql
security definer
set search_path=''
as $fn$
declare v_base text; v_count bigint;
begin
  perform pg_advisory_xact_lock(hashtext('stayqr:v11b:number:'||p_hotel_id::text||':'||p_prefix));
  v_base := upper(p_prefix)||'-'||to_char(current_date,'YYYYMMDD')||'-';
  execute format('select count(*) from public.%I where hotel_id=$1 and %I like $2',p_table,p_column)
    into v_count using p_hotel_id,v_base||'%';
  return v_base||lpad((v_count+1)::text,4,'0');
end;
$fn$;

revoke all on function private.v11b_require_access(uuid,text[]) from public,anon,authenticated;
revoke all on function private.v11b_next_number(uuid,text,text,text) from public,anon,authenticated;

-- --------------------------------------------------------------------------
-- 9. Workspace read RPC
-- --------------------------------------------------------------------------
create or replace function public.get_v11_operations_workspace(p_hotel_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $fn$
declare v_actor uuid;
begin
  v_actor := private.v11b_require_access(
    p_hotel_id,
    array['services.view','services.manage','housekeeping.view','housekeeping.manage','foodorders.view','foodorders.manage','reports.view','rooms.view','hotel.manage']::text[]
  );

  return jsonb_build_object(
    'laundry_orders',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from (select * from public.laundry_orders where hotel_id=p_hotel_id order by created_at desc limit 100) x),'[]'::jsonb),
    'lost_found_items',coalesce((select jsonb_agg(to_jsonb(x) order by x.found_at desc) from (select * from public.lost_found_items where hotel_id=p_hotel_id order by found_at desc limit 100) x),'[]'::jsonb),
    'inventory_items',coalesce((select jsonb_agg(to_jsonb(x) order by x.name) from (select * from public.inventory_items where hotel_id=p_hotel_id order by name limit 300) x),'[]'::jsonb),
    'inventory_movements',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from (select * from public.inventory_movements where hotel_id=p_hotel_id order by created_at desc limit 100) x),'[]'::jsonb),
    'printer_profiles',coalesce((select jsonb_agg(to_jsonb(x) order by x.is_default desc,x.name) from (select * from public.kitchen_printer_profiles where hotel_id=p_hotel_id order by is_default desc,name) x),'[]'::jsonb),
    'print_events',coalesce((select jsonb_agg(to_jsonb(x) order by x.printed_at desc) from (select * from public.kitchen_print_events where hotel_id=p_hotel_id order by printed_at desc limit 100) x),'[]'::jsonb),
    'report_jobs',coalesce((select jsonb_agg(to_jsonb(x) order by x.next_run_at) from (select * from public.scheduled_report_jobs where hotel_id=p_hotel_id order by next_run_at limit 100) x),'[]'::jsonb),
    'report_runs',coalesce((select jsonb_agg(to_jsonb(x) order by x.generated_at desc) from (select * from public.scheduled_report_runs where hotel_id=p_hotel_id order by generated_at desc limit 100) x),'[]'::jsonb),
    'active_stays',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',gs.id,'guest_id',gs.guest_id,'room_id',gs.room_id,
        'guest_name',g.full_name,'room_number',r.room_number,
        'checkout_time',coalesce(gs.extended_until,gs.checkout_time)
      ) order by r.room_number)
      from public.guest_sessions gs
      join public.guests g on g.id=gs.guest_id and g.hotel_id=gs.hotel_id
      join public.rooms r on r.id=gs.room_id and r.hotel_id=gs.hotel_id
      where gs.hotel_id=p_hotel_id and gs.status='active'
    ),'[]'::jsonb),
    'recent_food_orders',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',fo.id,'status',fo.order_status,'total_amount',fo.total_amount,'created_at',fo.created_at,
        'room_number',r.room_number,'guest_name',g.full_name
      ) order by fo.created_at desc)
      from (select * from public.food_orders where hotel_id=p_hotel_id order by created_at desc limit 30) fo
      left join public.rooms r on r.id=fo.room_id and r.hotel_id=fo.hotel_id
      left join public.guests g on g.id=fo.guest_id and g.hotel_id=fo.hotel_id
    ),'[]'::jsonb)
  );
end;
$fn$;

-- --------------------------------------------------------------------------
-- 10. Laundry RPCs
-- --------------------------------------------------------------------------
create or replace function public.create_v11_laundry_order(p_hotel_id uuid,p_payload jsonb)
returns public.laundry_orders
language plpgsql
security definer
set search_path=''
as $fn$
declare v_actor uuid; v_row public.laundry_orders%rowtype; v_session public.guest_sessions%rowtype;
begin
  v_actor := private.v11b_require_access(p_hotel_id,array['services.manage','housekeeping.manage','hotel.manage']::text[]);
  if jsonb_typeof(coalesce(p_payload,'{}'::jsonb)) <> 'object' then raise exception 'Laundry payload must be an object.'; end if;

  if nullif(p_payload->>'guest_session_id','') is not null then
    select * into v_session from public.guest_sessions
    where id=(p_payload->>'guest_session_id')::uuid and hotel_id=p_hotel_id and status='active';
    if v_session.id is null then raise exception 'Active guest stay not found.'; end if;
  end if;

  insert into public.laundry_orders(
    hotel_id,guest_session_id,room_id,guest_id,service_request_id,order_number,status,priority,
    piece_count,item_summary,special_instructions,promised_at,assigned_staff_id,created_by,updated_by,metadata
  ) values (
    p_hotel_id,v_session.id,v_session.room_id,v_session.guest_id,
    nullif(p_payload->>'service_request_id','')::uuid,
    private.v11b_next_number(p_hotel_id,'LDR','laundry_orders','order_number'),
    'received',coalesce(nullif(lower(p_payload->>'priority'),''),'normal'),
    greatest(1,coalesce((p_payload->>'piece_count')::integer,1)),
    trim(coalesce(p_payload->>'item_summary','Laundry items')),
    nullif(trim(p_payload->>'special_instructions'),''),
    nullif(p_payload->>'promised_at','')::timestamptz,
    nullif(p_payload->>'assigned_staff_id','')::uuid,
    v_actor,v_actor,coalesce(p_payload->'metadata','{}'::jsonb)
  ) returning * into v_row;
  return v_row;
end;
$fn$;

create or replace function public.update_v11_laundry_status(p_hotel_id uuid,p_order_id uuid,p_status text,p_note text default null)
returns public.laundry_orders
language plpgsql
security definer
set search_path=''
as $fn$
declare v_actor uuid; v_row public.laundry_orders%rowtype; v_status text := lower(trim(coalesce(p_status,'')));
begin
  v_actor := private.v11b_require_access(p_hotel_id,array['services.manage','housekeeping.manage','hotel.manage']::text[]);
  if v_status not in ('received','washing','drying','ironing','ready','delivered','cancelled') then raise exception 'Unsupported laundry status.'; end if;
  update public.laundry_orders set
    status=v_status,
    ready_at=case when v_status in ('ready','delivered') then coalesce(ready_at,now()) else ready_at end,
    delivered_at=case when v_status='delivered' then coalesce(delivered_at,now()) else delivered_at end,
    cancelled_at=case when v_status='cancelled' then coalesce(cancelled_at,now()) else cancelled_at end,
    cancellation_reason=case when v_status='cancelled' then coalesce(nullif(trim(p_note),''),'Cancelled by hotel') else cancellation_reason end,
    updated_by=v_actor,updated_at=now(),
    metadata=case when nullif(trim(p_note),'') is null then metadata else metadata||jsonb_build_object('last_note',trim(p_note)) end
  where id=p_order_id and hotel_id=p_hotel_id
  returning * into v_row;
  if v_row.id is null then raise exception 'Laundry order not found.'; end if;
  return v_row;
end;
$fn$;

-- --------------------------------------------------------------------------
-- 11. Lost & found RPCs
-- --------------------------------------------------------------------------
create or replace function public.create_v11_lost_found_item(p_hotel_id uuid,p_payload jsonb)
returns public.lost_found_items
language plpgsql
security definer
set search_path=''
as $fn$
declare v_actor uuid; v_row public.lost_found_items%rowtype;
begin
  v_actor := private.v11b_require_access(p_hotel_id,array['services.manage','housekeeping.manage','hotel.manage']::text[]);
  insert into public.lost_found_items(
    hotel_id,item_number,item_name,description,found_location,found_at,room_id,guest_id,status,storage_location,
    created_by,updated_by,metadata
  ) values (
    p_hotel_id,private.v11b_next_number(p_hotel_id,'LF','lost_found_items','item_number'),
    trim(coalesce(p_payload->>'item_name','')),nullif(trim(p_payload->>'description'),''),
    trim(coalesce(p_payload->>'found_location','')),
    coalesce(nullif(p_payload->>'found_at','')::timestamptz,now()),
    nullif(p_payload->>'room_id','')::uuid,nullif(p_payload->>'guest_id','')::uuid,
    'stored',nullif(trim(p_payload->>'storage_location'),''),v_actor,v_actor,coalesce(p_payload->'metadata','{}'::jsonb)
  ) returning * into v_row;
  return v_row;
end;
$fn$;

create or replace function public.transition_v11_lost_found_item(
  p_hotel_id uuid,p_item_id uuid,p_status text,p_payload jsonb default '{}'::jsonb
)
returns public.lost_found_items
language plpgsql
security definer
set search_path=''
as $fn$
declare v_actor uuid; v_row public.lost_found_items%rowtype; v_status text := lower(trim(coalesce(p_status,'')));
begin
  v_actor := private.v11b_require_access(p_hotel_id,array['services.manage','housekeeping.manage','hotel.manage']::text[]);
  if v_status not in ('stored','matched','claimed','returned','disposed','donated') then raise exception 'Unsupported lost-and-found status.'; end if;
  update public.lost_found_items set
    status=v_status,
    guest_id=coalesce(nullif(p_payload->>'guest_id','')::uuid,guest_id),
    claimant_name=case when v_status in ('claimed','returned') then coalesce(nullif(trim(p_payload->>'claimant_name'),''),claimant_name) else claimant_name end,
    claimant_contact=coalesce(nullif(trim(p_payload->>'claimant_contact'),''),claimant_contact),
    matched_at=case when v_status='matched' then coalesce(matched_at,now()) else matched_at end,
    claimed_at=case when v_status in ('claimed','returned') then coalesce(claimed_at,now()) else claimed_at end,
    closed_at=case when v_status in ('returned','disposed','donated') then coalesce(closed_at,now()) else closed_at end,
    closure_note=case when v_status in ('returned','disposed','donated') then coalesce(nullif(trim(p_payload->>'note'),''),closure_note,'Closed') else closure_note end,
    updated_by=v_actor,updated_at=now()
  where id=p_item_id and hotel_id=p_hotel_id
  returning * into v_row;
  if v_row.id is null then raise exception 'Lost-and-found item not found.'; end if;
  return v_row;
end;
$fn$;

-- --------------------------------------------------------------------------
-- 12. Inventory RPCs
-- --------------------------------------------------------------------------
create or replace function public.upsert_v11_inventory_item(p_hotel_id uuid,p_payload jsonb)
returns public.inventory_items
language plpgsql
security definer
set search_path=''
as $fn$
declare v_actor uuid; v_id uuid; v_row public.inventory_items%rowtype;
begin
  v_actor := private.v11b_require_access(p_hotel_id,array['housekeeping.manage','foodorders.manage','hotel.manage']::text[]);
  v_id := nullif(p_payload->>'id','')::uuid;
  if v_id is null then
    insert into public.inventory_items(
      hotel_id,sku,name,category,unit,quantity_on_hand,reorder_level,unit_cost,is_active,created_by,updated_by,metadata
    ) values (
      p_hotel_id,trim(p_payload->>'sku'),trim(p_payload->>'name'),coalesce(nullif(lower(p_payload->>'category'),''),'general'),
      coalesce(nullif(trim(p_payload->>'unit'),''),'unit'),greatest(0,coalesce((p_payload->>'quantity_on_hand')::numeric,0)),
      greatest(0,coalesce((p_payload->>'reorder_level')::numeric,0)),nullif(p_payload->>'unit_cost','')::numeric,
      coalesce((p_payload->>'is_active')::boolean,true),v_actor,v_actor,coalesce(p_payload->'metadata','{}'::jsonb)
    ) returning * into v_row;
  else
    update public.inventory_items set
      sku=coalesce(nullif(trim(p_payload->>'sku'),''),sku),name=coalesce(nullif(trim(p_payload->>'name'),''),name),
      category=coalesce(nullif(lower(p_payload->>'category'),''),category),unit=coalesce(nullif(trim(p_payload->>'unit'),''),unit),
      reorder_level=coalesce(nullif(p_payload->>'reorder_level','')::numeric,reorder_level),
      unit_cost=case when p_payload ? 'unit_cost' then nullif(p_payload->>'unit_cost','')::numeric else unit_cost end,
      is_active=coalesce(nullif(p_payload->>'is_active','')::boolean,is_active),updated_by=v_actor,updated_at=now()
    where id=v_id and hotel_id=p_hotel_id returning * into v_row;
    if v_row.id is null then raise exception 'Inventory item not found.'; end if;
  end if;
  return v_row;
end;
$fn$;

create or replace function public.post_v11_inventory_movement(
  p_hotel_id uuid,p_item_id uuid,p_movement_type text,p_quantity numeric,p_reason text,p_request_key text
)
returns public.inventory_movements
language plpgsql
security definer
set search_path=''
as $fn$
declare v_actor uuid; v_item public.inventory_items%rowtype; v_existing public.inventory_movements%rowtype; v_delta numeric; v_after numeric; v_row public.inventory_movements%rowtype; v_type text:=lower(trim(coalesce(p_movement_type,'')));
begin
  v_actor := private.v11b_require_access(p_hotel_id,array['housekeeping.manage','foodorders.manage','hotel.manage']::text[]);
  if length(trim(coalesce(p_request_key,''))) < 8 then raise exception 'Inventory movement request key is required.'; end if;
  select * into v_existing from public.inventory_movements where hotel_id=p_hotel_id and request_key=p_request_key;
  if v_existing.id is not null then return v_existing; end if;
  if v_type not in ('receive','consume','adjust_in','adjust_out','waste','return') then raise exception 'Unsupported inventory movement.'; end if;
  if coalesce(p_quantity,0) <= 0 then raise exception 'Movement quantity must be greater than zero.'; end if;
  select * into v_item from public.inventory_items where id=p_item_id and hotel_id=p_hotel_id for update;
  if v_item.id is null then raise exception 'Inventory item not found.'; end if;
  v_delta := case when v_type in ('receive','adjust_in','return') then p_quantity else -p_quantity end;
  v_after := v_item.quantity_on_hand + v_delta;
  if v_after < 0 then raise exception 'Inventory movement would create negative stock.'; end if;
  update public.inventory_items set quantity_on_hand=v_after,updated_by=v_actor,updated_at=now() where id=v_item.id;
  insert into public.inventory_movements(
    hotel_id,inventory_item_id,movement_type,quantity_delta,quantity_before,quantity_after,reason,request_key,actor_user_id
  ) values (p_hotel_id,v_item.id,v_type,v_delta,v_item.quantity_on_hand,v_after,trim(p_reason),trim(p_request_key),v_actor)
  returning * into v_row;
  return v_row;
end;
$fn$;

-- --------------------------------------------------------------------------
-- 13. KOT printer RPCs
-- --------------------------------------------------------------------------
create or replace function public.upsert_v11_kitchen_printer_profile(p_hotel_id uuid,p_payload jsonb)
returns public.kitchen_printer_profiles
language plpgsql
security definer
set search_path=''
as $fn$
declare v_actor uuid; v_id uuid; v_default boolean; v_row public.kitchen_printer_profiles%rowtype;
begin
  v_actor := private.v11b_require_access(p_hotel_id,array['foodorders.manage','hotel.manage']::text[]);
  v_id := nullif(p_payload->>'id','')::uuid;
  if v_id is null and nullif(trim(p_payload->>'name'),'') is not null then
    select kp.id into v_id from public.kitchen_printer_profiles kp
    where kp.hotel_id=p_hotel_id and lower(trim(kp.name))=lower(trim(p_payload->>'name'))
    limit 1;
  end if;
  v_default := coalesce((p_payload->>'is_default')::boolean,false);
  if v_default then update public.kitchen_printer_profiles set is_default=false,updated_by=v_actor,updated_at=now() where hotel_id=p_hotel_id; end if;
  if v_id is null then
    insert into public.kitchen_printer_profiles(
      hotel_id,name,station,paper_width_mm,copies,auto_print,is_default,is_active,created_by,updated_by
    ) values (
      p_hotel_id,trim(p_payload->>'name'),coalesce(nullif(lower(p_payload->>'station'),''),'kitchen'),
      coalesce((p_payload->>'paper_width_mm')::integer,80),coalesce((p_payload->>'copies')::integer,1),
      coalesce((p_payload->>'auto_print')::boolean,false),v_default,coalesce((p_payload->>'is_active')::boolean,true),v_actor,v_actor
    ) returning * into v_row;
  else
    update public.kitchen_printer_profiles set
      name=coalesce(nullif(trim(p_payload->>'name'),''),name),station=coalesce(nullif(lower(p_payload->>'station'),''),station),
      paper_width_mm=coalesce(nullif(p_payload->>'paper_width_mm','')::integer,paper_width_mm),copies=coalesce(nullif(p_payload->>'copies','')::integer,copies),
      auto_print=coalesce(nullif(p_payload->>'auto_print','')::boolean,auto_print),is_default=v_default,
      is_active=coalesce(nullif(p_payload->>'is_active','')::boolean,is_active),updated_by=v_actor,updated_at=now()
    where id=v_id and hotel_id=p_hotel_id returning * into v_row;
    if v_row.id is null then raise exception 'Kitchen printer profile not found.'; end if;
  end if;
  return v_row;
end;
$fn$;

create or replace function public.prepare_v11_kot_print(p_hotel_id uuid,p_order_id uuid,p_printer_profile_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path=''
as $fn$
declare v_actor uuid; v_profile public.kitchen_printer_profiles%rowtype; v_ticket jsonb; v_ticket_id uuid; v_event public.kitchen_print_events%rowtype;
begin
  v_actor := private.v11b_require_access(p_hotel_id,array['foodorders.view','foodorders.manage','hotel.manage']::text[]);
  if p_printer_profile_id is null then
    select * into v_profile from public.kitchen_printer_profiles where hotel_id=p_hotel_id and is_active order by is_default desc,created_at limit 1;
  else
    select * into v_profile from public.kitchen_printer_profiles where id=p_printer_profile_id and hotel_id=p_hotel_id and is_active;
  end if;
  if v_profile.id is null then raise exception 'Active kitchen printer profile not found.'; end if;
  v_ticket := public.get_food_order_kot(p_hotel_id,p_order_id);
  select kt.id into v_ticket_id from public.kitchen_tickets kt where kt.hotel_id=p_hotel_id and kt.food_order_id=p_order_id limit 1;
  insert into public.kitchen_print_events(
    hotel_id,food_order_id,kitchen_ticket_id,printer_profile_id,ticket_number,requested_copies,actor_user_id,
    metadata
  ) values (
    p_hotel_id,p_order_id,v_ticket_id,v_profile.id,v_ticket->>'ticket_number',v_profile.copies,v_actor,
    jsonb_build_object('paper_width_mm',v_profile.paper_width_mm,'station',v_profile.station)
  ) returning * into v_event;
  return jsonb_build_object('ticket',v_ticket,'printer_profile',to_jsonb(v_profile),'print_event',to_jsonb(v_event));
end;
$fn$;

-- --------------------------------------------------------------------------
-- 14. Scheduled report RPCs
-- --------------------------------------------------------------------------
create or replace function public.upsert_v11_scheduled_report_job(p_hotel_id uuid,p_payload jsonb)
returns public.scheduled_report_jobs
language plpgsql
security definer
set search_path=''
as $fn$
declare v_actor uuid; v_id uuid; v_row public.scheduled_report_jobs%rowtype;
begin
  v_actor := private.v11b_require_access(p_hotel_id,array['reports.view','hotel.manage']::text[]);
  v_id := nullif(p_payload->>'id','')::uuid;
  if v_id is null then
    insert into public.scheduled_report_jobs(
      hotel_id,name,report_key,frequency,lookback_days,filters,recipients,enabled,next_run_at,created_by,updated_by,metadata
    ) values (
      p_hotel_id,trim(p_payload->>'name'),lower(trim(p_payload->>'report_key')),coalesce(nullif(lower(p_payload->>'frequency'),''),'daily'),
      coalesce((p_payload->>'lookback_days')::integer,1),coalesce(p_payload->'filters','{}'::jsonb),
      case when jsonb_typeof(p_payload->'recipients')='array' then array(select jsonb_array_elements_text(p_payload->'recipients')) else '{}'::text[] end,
      coalesce((p_payload->>'enabled')::boolean,true),coalesce(nullif(p_payload->>'next_run_at','')::timestamptz,now()),v_actor,v_actor,
      coalesce(p_payload->'metadata','{}'::jsonb)
    ) returning * into v_row;
  else
    update public.scheduled_report_jobs set
      name=coalesce(nullif(trim(p_payload->>'name'),''),name),report_key=coalesce(nullif(lower(p_payload->>'report_key'),''),report_key),
      frequency=coalesce(nullif(lower(p_payload->>'frequency'),''),frequency),lookback_days=coalesce(nullif(p_payload->>'lookback_days','')::integer,lookback_days),
      filters=coalesce(p_payload->'filters',filters),
      recipients=case when jsonb_typeof(p_payload->'recipients')='array' then array(select jsonb_array_elements_text(p_payload->'recipients')) else recipients end,
      enabled=coalesce(nullif(p_payload->>'enabled','')::boolean,enabled),next_run_at=coalesce(nullif(p_payload->>'next_run_at','')::timestamptz,next_run_at),
      updated_by=v_actor,updated_at=now()
    where id=v_id and hotel_id=p_hotel_id returning * into v_row;
    if v_row.id is null then raise exception 'Scheduled report job not found.'; end if;
  end if;
  return v_row;
end;
$fn$;

create or replace function public.run_due_v11_scheduled_reports(p_hotel_id uuid,p_force boolean default false)
returns jsonb
language plpgsql
security definer
set search_path=''
as $fn$
declare v_actor uuid; v_job public.scheduled_report_jobs%rowtype; v_payload jsonb; v_date_to date; v_date_from date; v_error text; v_processed integer:=0; v_generated integer:=0; v_failed integer:=0; v_scheduled timestamptz; v_timezone text; v_local_today date;
begin
  v_actor := private.v11b_require_access(p_hotel_id,array['reports.view','hotel.manage']::text[]);
  select coalesce(nullif(trim(h.timezone),''),'Asia/Kolkata') into v_timezone from public.hotels h where h.id=p_hotel_id;
  if v_timezone is null then raise exception 'Hotel timezone not found.'; end if;
  v_local_today := (now() at time zone v_timezone)::date;
  for v_job in
    select * from public.scheduled_report_jobs
    where hotel_id=p_hotel_id and enabled and (p_force or next_run_at<=now())
    order by next_run_at,id
    limit 25
    for update skip locked
  loop
    v_processed := v_processed+1;
    v_scheduled := v_job.next_run_at;
    if exists(select 1 from public.scheduled_report_runs where job_id=v_job.id and scheduled_for=v_scheduled) then
      update public.scheduled_report_jobs set
        next_run_at=case v_job.frequency when 'daily' then v_scheduled+interval '1 day' when 'weekly' then v_scheduled+interval '7 days' else v_scheduled+interval '1 month' end,
        updated_by=v_actor,updated_at=now()
      where id=v_job.id;
      continue;
    end if;
    v_date_to := v_local_today;
    v_date_from := v_date_to-(v_job.lookback_days-1);
    begin
      v_payload := public.get_report_export_rows(p_hotel_id,v_date_from,v_date_to,v_job.report_key,v_job.filters);
      insert into public.scheduled_report_runs(hotel_id,job_id,scheduled_for,date_from,date_to,status,row_count,payload,generated_by)
      values (p_hotel_id,v_job.id,v_scheduled,v_date_from,v_date_to,'generated',jsonb_array_length(coalesce(v_payload->'rows','[]'::jsonb)),v_payload,v_actor);
      v_generated := v_generated+1;
      v_error := null;
    exception when others then
      get stacked diagnostics v_error = message_text;
      insert into public.scheduled_report_runs(hotel_id,job_id,scheduled_for,date_from,date_to,status,row_count,error_message,generated_by)
      values (p_hotel_id,v_job.id,v_scheduled,v_date_from,v_date_to,'failed',0,left(v_error,1000),v_actor);
      v_failed := v_failed+1;
    end;
    update public.scheduled_report_jobs set
      last_run_at=now(),
      next_run_at=case v_job.frequency when 'daily' then v_scheduled+interval '1 day' when 'weekly' then v_scheduled+interval '7 days' else v_scheduled+interval '1 month' end,
      updated_by=v_actor,updated_at=now()
    where id=v_job.id;
  end loop;
  return jsonb_build_object('processed',v_processed,'generated',v_generated,'failed',v_failed);
end;
$fn$;

-- --------------------------------------------------------------------------
-- 15. Privilege hardening
-- --------------------------------------------------------------------------
revoke all on table public.laundry_orders from public,anon;
revoke all on table public.lost_found_items from public,anon;
revoke all on table public.inventory_items from public,anon;
revoke all on table public.inventory_movements from public,anon;
revoke all on table public.kitchen_printer_profiles from public,anon;
revoke all on table public.kitchen_print_events from public,anon;
revoke all on table public.scheduled_report_jobs from public,anon;
revoke all on table public.scheduled_report_runs from public,anon;

revoke insert,update,delete on table public.laundry_orders from authenticated;
revoke insert,update,delete on table public.lost_found_items from authenticated;
revoke insert,update,delete on table public.inventory_items from authenticated;
revoke insert,update,delete on table public.inventory_movements from authenticated;
revoke insert,update,delete on table public.kitchen_printer_profiles from authenticated;
revoke insert,update,delete on table public.kitchen_print_events from authenticated;
revoke insert,update,delete on table public.scheduled_report_jobs from authenticated;
revoke insert,update,delete on table public.scheduled_report_runs from authenticated;

grant select on table public.laundry_orders,public.lost_found_items,public.inventory_items,public.inventory_movements,
  public.kitchen_printer_profiles,public.kitchen_print_events,public.scheduled_report_jobs,public.scheduled_report_runs to authenticated;

grant all on table public.laundry_orders,public.lost_found_items,public.inventory_items,public.inventory_movements,
  public.kitchen_printer_profiles,public.kitchen_print_events,public.scheduled_report_jobs,public.scheduled_report_runs to service_role;

revoke all on function public.get_v11_operations_workspace(uuid) from public,anon;
revoke all on function public.create_v11_laundry_order(uuid,jsonb) from public,anon;
revoke all on function public.update_v11_laundry_status(uuid,uuid,text,text) from public,anon;
revoke all on function public.create_v11_lost_found_item(uuid,jsonb) from public,anon;
revoke all on function public.transition_v11_lost_found_item(uuid,uuid,text,jsonb) from public,anon;
revoke all on function public.upsert_v11_inventory_item(uuid,jsonb) from public,anon;
revoke all on function public.post_v11_inventory_movement(uuid,uuid,text,numeric,text,text) from public,anon;
revoke all on function public.upsert_v11_kitchen_printer_profile(uuid,jsonb) from public,anon;
revoke all on function public.prepare_v11_kot_print(uuid,uuid,uuid) from public,anon;
revoke all on function public.upsert_v11_scheduled_report_job(uuid,jsonb) from public,anon;
revoke all on function public.run_due_v11_scheduled_reports(uuid,boolean) from public,anon;

grant execute on function public.get_v11_operations_workspace(uuid) to authenticated,service_role;
grant execute on function public.create_v11_laundry_order(uuid,jsonb) to authenticated,service_role;
grant execute on function public.update_v11_laundry_status(uuid,uuid,text,text) to authenticated,service_role;
grant execute on function public.create_v11_lost_found_item(uuid,jsonb) to authenticated,service_role;
grant execute on function public.transition_v11_lost_found_item(uuid,uuid,text,jsonb) to authenticated,service_role;
grant execute on function public.upsert_v11_inventory_item(uuid,jsonb) to authenticated,service_role;
grant execute on function public.post_v11_inventory_movement(uuid,uuid,text,numeric,text,text) to authenticated,service_role;
grant execute on function public.upsert_v11_kitchen_printer_profile(uuid,jsonb) to authenticated,service_role;
grant execute on function public.prepare_v11_kot_print(uuid,uuid,uuid) to authenticated,service_role;
grant execute on function public.upsert_v11_scheduled_report_job(uuid,jsonb) to authenticated,service_role;
grant execute on function public.run_due_v11_scheduled_reports(uuid,boolean) to authenticated,service_role;

commit;
