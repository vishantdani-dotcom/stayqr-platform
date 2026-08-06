-- ============================================================================
-- StayQR v1.0
-- Day 13 Migration 040 REV2 FIX
-- Housekeeping assignment, workload, checklist, inspection and room-ready
--
-- REQUIRES
-- --------
-- Migration 039:
--   foundation success
--   structural acceptance 60/60
--   reversible runtime acceptance REV2 30/30
--
-- CONTROLLED VD STAY INN BASELINE
-- --------------------------------
-- Rooms: 12
-- Housekeeping tasks: 14
--   completed: 13
--   pending: 1 (Room 106)
-- Existing tasks assigned: 0
-- Existing checklist/inspection evidence: 0
-- Room 106: cleaning
-- Day 12 authoritative balance: INR 22,785
--
-- THIS MIGRATION
-- --------------
-- 1. Upgrades legacy housekeeping tasks into an auditable workflow.
-- 2. Adds staff assignment, priority, due time and workload reporting.
-- 3. Adds hotel-configurable cleaning-checklist templates.
-- 4. Snapshots checklist items onto every housekeeping task.
-- 5. Adds immutable inspection and task-event evidence.
-- 6. Adds RPC-only create/assign/start/checklist/complete/inspect/ready/cancel.
-- 7. Automatically upgrades checkout/room-move cleaning tasks.
-- 8. Makes room-ready approval the only housekeeping path back to available.
--
-- WORKFLOW
-- --------
-- pending -> assigned -> in_progress -> cleaning_complete
--   -> inspection_failed -> in_progress ...
--   -> inspected -> ready
--
-- Legacy `completed` tasks remain immutable historical rows.
--
-- SAFETY
-- ------
-- - No existing task status is changed.
-- - No existing room status is changed.
-- - Room 106 remains cleaning and pending.
-- - No inspection or event is fabricated for legacy tasks.
-- - No reservation, stay, folio, invoice, receipt or payment is rewritten.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 0. Strict preflight
-- ---------------------------------------------------------------------------

do $preflight$
declare
  missing_objects text;
  existing_targets text;
  task_count integer;
  pending_count integer;
  room106_status text;
  controlled_balance numeric(14,2);
begin
  select string_agg(object_name, ', ' order by object_name)
  into missing_objects
  from (
    values
      (
        'public.housekeeping_tasks',
        to_regclass('public.housekeeping_tasks') is not null
      ),
      (
        'public.rooms',
        to_regclass('public.rooms') is not null
      ),
      (
        'public.staff',
        to_regclass('public.staff') is not null
      ),
      (
        'public.guest_sessions',
        to_regclass('public.guest_sessions') is not null
      ),
      (
        'public.reservations',
        to_regclass('public.reservations') is not null
      ),
      (
        'public.room_status_events',
        to_regclass('public.room_status_events') is not null
      ),
      (
        'private.day13_require_room_manager(uuid)',
        to_regprocedure(
          'private.day13_require_room_manager(uuid)'
        ) is not null
      ),
      (
        'private.day13_room_commitments(uuid,uuid)',
        to_regprocedure(
          'private.day13_room_commitments(uuid,uuid)'
        ) is not null
      ),
      (
        'private.day11_require_current_actor()',
        to_regprocedure(
          'private.day11_require_current_actor()'
        ) is not null
      ),
      (
        'private.user_has_any_permission(uuid,text[])',
        to_regprocedure(
          'private.user_has_any_permission(uuid,text[])'
        ) is not null
      )
  ) required(object_name, object_exists)
  where not object_exists;

  if missing_objects is not null then
    raise exception
      'Migration 040 prerequisites are missing: %',
      missing_objects;
  end if;

  select string_agg(object_name, ', ' order by object_name)
  into existing_targets
  from (
    values
      (
        'public.housekeeping_checklist_templates',
        to_regclass(
          'public.housekeeping_checklist_templates'
        )
      ),
      (
        'public.housekeeping_task_items',
        to_regclass(
          'public.housekeeping_task_items'
        )
      ),
      (
        'public.housekeeping_inspections',
        to_regclass(
          'public.housekeeping_inspections'
        )
      ),
      (
        'public.housekeeping_task_events',
        to_regclass(
          'public.housekeeping_task_events'
        )
      )
  ) targets(object_name, relation_id)
  where relation_id is not null;

  if existing_targets is not null then
    raise exception
      'Migration 040 target objects already exist: %. Do not rerun REV1.',
      existing_targets;
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'housekeeping_tasks'
      and column_name = 'assigned_staff_id'
  ) then
    raise exception
      'Migration 040 task lifecycle columns already exist. Do not rerun REV1.';
  end if;

  select count(*)
  into task_count
  from public.housekeeping_tasks task
  where task.hotel_id =
    '77d850d0-016d-4155-bc44-a6207d30e7b9'::uuid;

  select count(*)
  into pending_count
  from public.housekeeping_tasks task
  where task.hotel_id =
    '77d850d0-016d-4155-bc44-a6207d30e7b9'::uuid
    and coalesce(task.status, 'pending') = 'pending';

  select room.status
  into room106_status
  from public.rooms room
  where room.hotel_id =
    '77d850d0-016d-4155-bc44-a6207d30e7b9'::uuid
    and room.room_number = '106';

  select coalesce(sum(folio.balance_amount), 0)
  into controlled_balance
  from public.folios folio
  where folio.hotel_id =
    '77d850d0-016d-4155-bc44-a6207d30e7b9'::uuid;

  if task_count <> 14
     or pending_count <> 1
     or room106_status <> 'cleaning'
     or controlled_balance <> 22785
  then
    raise exception
      'Controlled baseline changed: tasks %, pending %, Room106 %, balance %.',
      task_count,
      pending_count,
      room106_status,
      controlled_balance;
  end if;
end;
$preflight$;

-- ---------------------------------------------------------------------------
-- 1. Upgrade legacy housekeeping task
-- ---------------------------------------------------------------------------

alter table public.housekeeping_tasks
  add column assigned_staff_id uuid,
  add column priority text not null default 'normal',
  add column source_type text not null default 'manual',
  add column source_guest_session_id uuid,
  add column source_reservation_id uuid,
  add column request_id text,
  add column due_at timestamptz,
  add column assigned_at timestamptz,
  add column assigned_by uuid,
  add column started_at timestamptz,
  add column started_by uuid,
  add column cleaning_completed_at timestamptz,
  add column cleaning_completed_by uuid,
  add column inspected_at timestamptz,
  add column inspected_by uuid,
  add column inspection_status text,
  add column room_ready_at timestamptz,
  add column room_ready_by uuid,
  add column cancelled_at timestamptz,
  add column cancelled_by uuid,
  add column cancellation_reason text,
  add column checklist_version integer not null default 1,
  add column updated_at timestamptz not null default now(),
  add column updated_by uuid,
  add column metadata jsonb not null default '{}'::jsonb;

update public.housekeeping_tasks
set
  status = coalesce(nullif(trim(status), ''), 'pending'),
  task_type =
    coalesce(
      nullif(trim(task_type), ''),
      'room_cleaning'
    ),
  source_type =
    case
      when notes ilike 'Checkout cleaning task%'
        then 'checkout'
      when notes ilike
           'Room cleaning after active stay moved%'
        then 'room_move'
      else 'legacy'
    end,
  cleaning_completed_at =
    case
      when status = 'completed'
        then coalesce(created_at, now())
      else null
    end,
  inspected_at =
    case
      when status = 'completed'
        then coalesce(created_at, now())
      else null
    end,
  inspection_status =
    case
      when status = 'completed'
        then 'passed'
      else null
    end,
  room_ready_at =
    case
      when status = 'completed'
        then coalesce(created_at, now())
      else null
    end,
  updated_at = coalesce(created_at, now());

alter table public.housekeeping_tasks
  alter column status set not null,
  alter column task_type set not null,
  alter column room_id set not null;

create unique index uq_housekeeping_tasks_hotel_id_id
  on public.housekeeping_tasks(hotel_id, id);

create unique index uq_housekeeping_tasks_request
  on public.housekeeping_tasks(hotel_id, request_id)
  where request_id is not null;

create unique index uq_housekeeping_active_room_cleaning
  on public.housekeeping_tasks(
    hotel_id,
    room_id,
    task_type
  )
  where status in (
    'pending',
    'assigned',
    'in_progress',
    'cleaning_complete',
    'inspection_failed',
    'inspected'
  );

create index idx_housekeeping_tasks_workload
  on public.housekeeping_tasks(
    hotel_id,
    assigned_staff_id,
    status,
    priority,
    due_at
  );

alter table public.housekeeping_tasks
  add constraint housekeeping_tasks_assigned_staff_fkey
    foreign key (assigned_staff_id)
    references public.staff(id)
    on delete set null,
  add constraint housekeeping_tasks_source_session_fkey
    foreign key (source_guest_session_id)
    references public.guest_sessions(id)
    on delete set null,
  add constraint housekeeping_tasks_source_reservation_fkey
    foreign key (source_reservation_id)
    references public.reservations(id)
    on delete set null,
  add constraint housekeeping_tasks_assigned_by_fkey
    foreign key (assigned_by)
    references auth.users(id)
    on delete set null,
  add constraint housekeeping_tasks_started_by_fkey
    foreign key (started_by)
    references auth.users(id)
    on delete set null,
  add constraint housekeeping_tasks_cleaned_by_fkey
    foreign key (cleaning_completed_by)
    references auth.users(id)
    on delete set null,
  add constraint housekeeping_tasks_inspected_by_fkey
    foreign key (inspected_by)
    references auth.users(id)
    on delete set null,
  add constraint housekeeping_tasks_ready_by_fkey
    foreign key (room_ready_by)
    references auth.users(id)
    on delete set null,
  add constraint housekeeping_tasks_cancelled_by_fkey
    foreign key (cancelled_by)
    references auth.users(id)
    on delete set null,
  add constraint housekeeping_tasks_updated_by_fkey
    foreign key (updated_by)
    references auth.users(id)
    on delete set null,
  add constraint housekeeping_tasks_status_check
    check (
      status in (
        'pending',
        'assigned',
        'in_progress',
        'cleaning_complete',
        'inspection_failed',
        'inspected',
        'ready',
        'completed',
        'cancelled'
      )
    ),
  add constraint housekeeping_tasks_type_check
    check (
      task_type in (
        'room_cleaning',
        'stayover_cleaning',
        'deep_cleaning',
        'turndown'
      )
    ),
  add constraint housekeeping_tasks_priority_check
    check (
      priority in (
        'low',
        'normal',
        'high',
        'urgent'
      )
    ),
  add constraint housekeeping_tasks_source_check
    check (
      source_type in (
        'legacy',
        'manual',
        'checkout',
        'room_move',
        'inspection_rework'
      )
    ),
  add constraint housekeeping_tasks_inspection_check
    check (
      inspection_status is null
      or inspection_status in (
        'pending',
        'passed',
        'failed'
      )
    ),
  add constraint housekeeping_tasks_checklist_version
    check (checklist_version > 0),
  add constraint housekeeping_tasks_metadata_object
    check (jsonb_typeof(metadata) = 'object');

-- ---------------------------------------------------------------------------
-- 2. Checklist templates
-- ---------------------------------------------------------------------------

create table public.housekeeping_checklist_templates (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null,

  code text not null,
  name text not null,
  task_type text not null,
  version integer not null default 1,
  items jsonb not null,

  is_active boolean not null default true,
  created_by uuid,
  updated_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint housekeeping_templates_hotel_fkey
    foreign key (hotel_id)
    references public.hotels(id)
    on delete restrict,

  constraint housekeeping_templates_created_by_fkey
    foreign key (created_by)
    references auth.users(id)
    on delete set null,

  constraint housekeeping_templates_updated_by_fkey
    foreign key (updated_by)
    references auth.users(id)
    on delete set null,

  constraint housekeeping_templates_code_check
    check (length(trim(code)) > 0),

  constraint housekeeping_templates_name_check
    check (length(trim(name)) > 0),

  constraint housekeeping_templates_type_check
    check (
      task_type in (
        'room_cleaning',
        'stayover_cleaning',
        'deep_cleaning',
        'turndown'
      )
    ),

  constraint housekeeping_templates_version_check
    check (version > 0),

  constraint housekeeping_templates_items_array
    check (
      jsonb_typeof(items) = 'array'
      and jsonb_array_length(items) > 0
    )
);

create unique index uq_housekeeping_template_version
  on public.housekeeping_checklist_templates(
    hotel_id,
    code,
    version
  );

create unique index uq_housekeeping_active_template_type
  on public.housekeeping_checklist_templates(
    hotel_id,
    task_type
  )
  where is_active;

create unique index uq_housekeeping_templates_hotel_id_id
  on public.housekeeping_checklist_templates(
    hotel_id,
    id
  );

alter table public.housekeeping_checklist_templates
enable row level security;

create policy stayqr_housekeeping_templates_select
on public.housekeeping_checklist_templates
for select
to authenticated
using (
  private.user_has_any_permission(
    hotel_id,
    array[
      'housekeeping.view',
      'housekeeping.manage',
      'rooms.view',
      'rooms.manage'
    ]::text[]
  )
);

-- ---------------------------------------------------------------------------
-- 3. Task checklist snapshot
-- ---------------------------------------------------------------------------

create table public.housekeeping_task_items (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null,
  task_id uuid not null,
  template_id uuid,

  item_code text not null,
  label text not null,
  sort_order integer not null default 0,
  is_required boolean not null default true,

  item_status text not null default 'pending',
  completed_at timestamptz,
  completed_by uuid,
  notes text,
  metadata jsonb not null default '{}'::jsonb,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint housekeeping_task_items_hotel_fkey
    foreign key (hotel_id)
    references public.hotels(id)
    on delete restrict,

  constraint housekeeping_task_items_task_fkey
    foreign key (hotel_id, task_id)
    references public.housekeeping_tasks(hotel_id, id)
    on delete cascade,

  constraint housekeeping_task_items_template_fkey
    foreign key (hotel_id, template_id)
    references public.housekeeping_checklist_templates(hotel_id, id)
    on delete set null,

  constraint housekeeping_task_items_actor_fkey
    foreign key (completed_by)
    references auth.users(id)
    on delete set null,

  constraint housekeeping_task_items_code_check
    check (length(trim(item_code)) > 0),

  constraint housekeeping_task_items_label_check
    check (length(trim(label)) > 0),

  constraint housekeeping_task_items_status_check
    check (
      item_status in (
        'pending',
        'completed',
        'failed',
        'not_applicable'
      )
    ),

  constraint housekeeping_task_items_metadata_object
    check (jsonb_typeof(metadata) = 'object')
);

create unique index uq_housekeeping_task_item_code
  on public.housekeeping_task_items(
    hotel_id,
    task_id,
    item_code
  );

create unique index uq_housekeeping_task_items_hotel_id_id
  on public.housekeeping_task_items(
    hotel_id,
    id
  );

create index idx_housekeeping_task_items_task
  on public.housekeeping_task_items(
    hotel_id,
    task_id,
    sort_order
  );

alter table public.housekeeping_task_items
enable row level security;

create policy stayqr_housekeeping_task_items_select
on public.housekeeping_task_items
for select
to authenticated
using (
  private.user_has_any_permission(
    hotel_id,
    array[
      'housekeeping.view',
      'housekeeping.manage',
      'rooms.view',
      'rooms.manage'
    ]::text[]
  )
);

-- ---------------------------------------------------------------------------
-- 4. Immutable inspection evidence
-- ---------------------------------------------------------------------------

create table public.housekeeping_inspections (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null,
  task_id uuid not null,

  result text not null,
  notes text,
  inspected_by uuid not null,
  inspected_at timestamptz not null default now(),

  request_id text not null,
  snapshot_json jsonb not null,
  snapshot_hash text not null,

  constraint housekeeping_inspections_hotel_fkey
    foreign key (hotel_id)
    references public.hotels(id)
    on delete restrict,

  constraint housekeeping_inspections_task_fkey
    foreign key (hotel_id, task_id)
    references public.housekeeping_tasks(hotel_id, id)
    on delete restrict,

  constraint housekeeping_inspections_actor_fkey
    foreign key (inspected_by)
    references auth.users(id)
    on delete restrict,

  constraint housekeeping_inspections_result_check
    check (result in ('passed', 'failed')),

  constraint housekeeping_inspections_snapshot_object
    check (jsonb_typeof(snapshot_json) = 'object'),

  constraint housekeeping_inspections_hash_check
    check (length(snapshot_hash) = 64)
);

create unique index uq_housekeeping_inspection_request
  on public.housekeeping_inspections(
    hotel_id,
    request_id
  );

create index idx_housekeeping_inspections_task_time
  on public.housekeeping_inspections(
    hotel_id,
    task_id,
    inspected_at desc
  );

alter table public.housekeeping_inspections
enable row level security;

create policy stayqr_housekeeping_inspections_select
on public.housekeeping_inspections
for select
to authenticated
using (
  private.user_has_any_permission(
    hotel_id,
    array[
      'housekeeping.view',
      'housekeeping.manage',
      'rooms.view',
      'rooms.manage'
    ]::text[]
  )
);

-- ---------------------------------------------------------------------------
-- 5. Immutable workflow events
-- ---------------------------------------------------------------------------

create table public.housekeeping_task_events (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null,
  task_id uuid not null,

  event_type text not null,
  previous_status text,
  new_status text,

  actor_id uuid,
  request_id text,
  metadata jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now(),

  constraint housekeeping_task_events_hotel_fkey
    foreign key (hotel_id)
    references public.hotels(id)
    on delete restrict,

  constraint housekeeping_task_events_task_fkey
    foreign key (hotel_id, task_id)
    references public.housekeeping_tasks(hotel_id, id)
    on delete restrict,

  constraint housekeeping_task_events_actor_fkey
    foreign key (actor_id)
    references auth.users(id)
    on delete set null,

  constraint housekeeping_task_events_type_check
    check (
      event_type in (
        'created',
        'assigned',
        'started',
        'checklist_updated',
        'cleaning_completed',
        'inspection_passed',
        'inspection_failed',
        'room_ready',
        'cancelled'
      )
    ),

  constraint housekeeping_task_events_metadata_object
    check (jsonb_typeof(metadata) = 'object')
);

create unique index uq_housekeeping_event_request
  on public.housekeeping_task_events(
    hotel_id,
    request_id,
    event_type
  )
  where request_id is not null;

create index idx_housekeeping_events_task_time
  on public.housekeeping_task_events(
    hotel_id,
    task_id,
    occurred_at desc
  );

alter table public.housekeeping_task_events
enable row level security;

create policy stayqr_housekeeping_events_select
on public.housekeeping_task_events
for select
to authenticated
using (
  private.user_has_any_permission(
    hotel_id,
    array[
      'housekeeping.view',
      'housekeeping.manage',
      'rooms.view',
      'rooms.manage'
    ]::text[]
  )
);

-- ---------------------------------------------------------------------------
-- 6. Seed one default checklist per hotel
-- ---------------------------------------------------------------------------

insert into public.housekeeping_checklist_templates (
  hotel_id,
  code,
  name,
  task_type,
  version,
  items,
  is_active
)
select
  hotel.id,
  'STANDARD_ROOM_CLEANING',
  'Standard Room Cleaning',
  'room_cleaning',
  1,
  jsonb_build_array(
    jsonb_build_object(
      'code', 'BED_LINEN',
      'label', 'Replace and inspect bed linen',
      'sort_order', 10,
      'required', true
    ),
    jsonb_build_object(
      'code', 'BATHROOM',
      'label', 'Clean and disinfect bathroom',
      'sort_order', 20,
      'required', true
    ),
    jsonb_build_object(
      'code', 'FLOOR',
      'label', 'Sweep, mop or vacuum floor',
      'sort_order', 30,
      'required', true
    ),
    jsonb_build_object(
      'code', 'DUSTING',
      'label', 'Dust furniture and surfaces',
      'sort_order', 40,
      'required', true
    ),
    jsonb_build_object(
      'code', 'AMENITIES',
      'label', 'Replenish guest amenities',
      'sort_order', 50,
      'required', true
    ),
    jsonb_build_object(
      'code', 'BINS',
      'label', 'Empty and replace waste-bin liners',
      'sort_order', 60,
      'required', true
    ),
    jsonb_build_object(
      'code', 'UTILITIES',
      'label', 'Check lights, AC, water and switches',
      'sort_order', 70,
      'required', true
    ),
    jsonb_build_object(
      'code', 'FINAL_CHECK',
      'label', 'Final odour, key and presentation check',
      'sort_order', 80,
      'required', true
    )
  ),
  true
from public.hotels hotel
where hotel.status = 'active'
on conflict do nothing;

-- Snapshot checklist items for the 14 existing tasks.
insert into public.housekeeping_task_items (
  hotel_id,
  task_id,
  template_id,
  item_code,
  label,
  sort_order,
  is_required,
  item_status,
  completed_at,
  metadata
)
select
  task.hotel_id,
  task.id,
  template.id,
  item.value ->> 'code',
  item.value ->> 'label',
  coalesce(
    (item.value ->> 'sort_order')::integer,
    item.ordinality::integer * 10
  ),
  coalesce(
    (item.value ->> 'required')::boolean,
    true
  ),
  case
    when task.status = 'completed'
      then 'completed'
    else 'pending'
  end,
  case
    when task.status = 'completed'
      then coalesce(task.created_at, now())
    else null
  end,
  jsonb_build_object(
    'legacy_backfill', true,
    'template_version', template.version
  )
from public.housekeeping_tasks task
join public.housekeeping_checklist_templates template
  on template.hotel_id = task.hotel_id
 and template.task_type = task.task_type
 and template.is_active
cross join lateral jsonb_array_elements(
  template.items
) with ordinality item(value, ordinality)
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- 7. Permission and helper functions
-- ---------------------------------------------------------------------------

create or replace function private.day13_require_housekeeping_manager(
  target_hotel_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  actor_id_value uuid;
begin
  if target_hotel_id is null then
    raise exception 'Hotel ID is required.';
  end if;

  if not private.user_has_any_permission(
    target_hotel_id,
    array[
      'housekeeping.manage',
      'rooms.manage',
      'hotel.manage',
      'superadmin.manage'
    ]::text[]
  ) then
    raise exception
      'Housekeeping management access denied.';
  end if;

  actor_id_value :=
    private.day11_require_current_actor();

  return actor_id_value;
end;
$function$;

create or replace function private.day13_hash_json(
  payload jsonb
)
returns text
language sql
immutable
security invoker
set search_path = ''
as $function$
  select encode(
    extensions.digest(
      convert_to(payload::text, 'UTF8'),
      'sha256'
    ),
    'hex'
  );
$function$;

create or replace function private.day13_insert_housekeeping_event(
  target_hotel_id uuid,
  target_task_id uuid,
  event_type_value text,
  previous_status_value text,
  new_status_value text,
  actor_id_value uuid,
  request_id_value text,
  metadata_value jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  event_id_value uuid;
begin
  insert into public.housekeeping_task_events (
    hotel_id,
    task_id,
    event_type,
    previous_status,
    new_status,
    actor_id,
    request_id,
    metadata
  )
  values (
    target_hotel_id,
    target_task_id,
    event_type_value,
    previous_status_value,
    new_status_value,
    actor_id_value,
    nullif(trim(request_id_value), ''),
    coalesce(metadata_value, '{}'::jsonb)
  )
  on conflict (
    hotel_id,
    request_id,
    event_type
  )
  where request_id is not null
  do update
  set request_id =
    excluded.request_id
  returning id
  into event_id_value;

  return event_id_value;
end;
$function$;

-- ---------------------------------------------------------------------------
-- 8. Automatic task preparation and checklist initialization
-- ---------------------------------------------------------------------------

create or replace function private.day13_prepare_housekeeping_task()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  room_row public.rooms%rowtype;
  staff_row public.staff%rowtype;
  latest_session public.guest_sessions%rowtype;
  actor_id_value uuid;
begin
  select room.*
  into room_row
  from public.rooms room
  where room.hotel_id = new.hotel_id
    and room.id = new.room_id;

  if not found then
    raise exception
      'Housekeeping task requires a room in the same hotel.';
  end if;

  if not room_row.is_active then
    raise exception
      'Archived room cannot receive a housekeeping task.';
  end if;

  new.room_number := room_row.room_number;
  new.status :=
    coalesce(
      nullif(trim(new.status), ''),
      'pending'
    );
  new.task_type :=
    coalesce(
      nullif(trim(new.task_type), ''),
      'room_cleaning'
    );
  new.priority :=
    coalesce(
      nullif(trim(new.priority), ''),
      'normal'
    );
  new.updated_at := now();

  actor_id_value :=
    private.day11_valid_auth_actor(auth.uid());

  new.updated_by :=
    coalesce(
      actor_id_value,
      new.updated_by
    );

  if new.source_type = 'manual'
     and new.notes ilike
         'Checkout cleaning task%'
  then
    new.source_type := 'checkout';
  elsif new.source_type = 'manual'
        and new.notes ilike
            'Room cleaning after active stay moved%'
  then
    new.source_type := 'room_move';
  end if;

  if new.source_type in (
    'checkout',
    'room_move'
  )
  and new.source_guest_session_id is null
  then
    select session_record.*
    into latest_session
    from public.guest_sessions session_record
    where session_record.hotel_id =
          new.hotel_id
      and session_record.room_id =
          new.room_id
      and session_record.status =
          'completed'
    order by
      coalesce(
        session_record.checked_out_at,
        session_record.expired_at,
        session_record.created_at
      ) desc
    limit 1;

    if latest_session.id is not null then
      new.source_guest_session_id :=
        latest_session.id;
      new.source_reservation_id :=
        latest_session.reservation_id;
    end if;
  end if;

  if new.assigned_staff_id is not null then
    select staff.*
    into staff_row
    from public.staff staff
    where staff.hotel_id = new.hotel_id
      and staff.id = new.assigned_staff_id
      and staff.status = 'active'
      and staff.disabled_at is null;

    if staff_row.id is null then
      raise exception
        'Assigned housekeeping staff is not active in this hotel.';
    end if;

    new.assigned_to := staff_row.full_name;
    new.assigned_at :=
      coalesce(new.assigned_at, now());
    new.assigned_by :=
      coalesce(new.assigned_by, actor_id_value);

    if new.status = 'pending' then
      new.status := 'assigned';
    end if;
  else
    new.assigned_to := null;
  end if;

  return new;
end;
$function$;

create trigger housekeeping_tasks_day13_prepare
before insert or update
on public.housekeeping_tasks
for each row
execute function private.day13_prepare_housekeeping_task();

create or replace function private.day13_seed_housekeeping_items()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  template_row
    public.housekeeping_checklist_templates%rowtype;
begin
  select template.*
  into template_row
  from public.housekeeping_checklist_templates template
  where template.hotel_id = new.hotel_id
    and template.task_type = new.task_type
    and template.is_active
  order by template.version desc
  limit 1;

  if template_row.id is null then
    raise exception
      'No active housekeeping checklist template exists for task type %.',
      new.task_type;
  end if;

  update public.housekeeping_tasks
  set checklist_version =
    template_row.version
  where hotel_id = new.hotel_id
    and id = new.id;

  insert into public.housekeeping_task_items (
    hotel_id,
    task_id,
    template_id,
    item_code,
    label,
    sort_order,
    is_required,
    metadata
  )
  select
    new.hotel_id,
    new.id,
    template_row.id,
    item.value ->> 'code',
    item.value ->> 'label',
    coalesce(
      (item.value ->> 'sort_order')::integer,
      item.ordinality::integer * 10
    ),
    coalesce(
      (item.value ->> 'required')::boolean,
      true
    ),
    jsonb_build_object(
      'template_version',
      template_row.version
    )
  from jsonb_array_elements(
    template_row.items
  ) with ordinality item(value, ordinality);

  return new;
end;
$function$;

create trigger housekeeping_tasks_day13_seed_items
after insert
on public.housekeeping_tasks
for each row
execute function private.day13_seed_housekeeping_items();

-- ---------------------------------------------------------------------------
-- 9. RPC: create task
-- ---------------------------------------------------------------------------

create or replace function public.create_housekeeping_task(
  target_hotel_id uuid,
  target_room_id uuid,
  task_type_value text,
  priority_value text,
  due_at_value timestamptz,
  notes_value text,
  source_type_value text,
  source_guest_session_id_value uuid,
  request_id_value text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  actor_id_value uuid;
  request_key text;
  task_row public.housekeeping_tasks%rowtype;
begin
  actor_id_value :=
    private.day13_require_housekeeping_manager(
      target_hotel_id
    );

  request_key :=
    nullif(trim(request_id_value), '');

  if request_key is null
     or length(request_key) < 8
  then
    raise exception
      'A request ID of at least eight characters is required.';
  end if;

  select task.*
  into task_row
  from public.housekeeping_tasks task
  where task.hotel_id = target_hotel_id
    and task.request_id = request_key;

  if task_row.id is not null then
    return jsonb_build_object(
      'ok', true,
      'idempotent', true,
      'task', to_jsonb(task_row),
      'items',
        (
          select coalesce(
            jsonb_agg(
              to_jsonb(item)
              order by item.sort_order
            ),
            '[]'::jsonb
          )
          from public.housekeeping_task_items item
          where item.hotel_id = target_hotel_id
            and item.task_id = task_row.id
        )
    );
  end if;

  insert into public.housekeeping_tasks (
    hotel_id,
    room_id,
    task_type,
    status,
    priority,
    due_at,
    notes,
    source_type,
    source_guest_session_id,
    request_id,
    updated_by,
    metadata
  )
  values (
    target_hotel_id,
    target_room_id,
    coalesce(
      nullif(trim(task_type_value), ''),
      'room_cleaning'
    ),
    'pending',
    coalesce(
      nullif(trim(priority_value), ''),
      'normal'
    ),
    due_at_value,
    nullif(trim(notes_value), ''),
    coalesce(
      nullif(trim(source_type_value), ''),
      'manual'
    ),
    source_guest_session_id_value,
    request_key,
    actor_id_value,
    jsonb_build_object(
      'created_via', 'create_housekeeping_task'
    )
  )
  returning *
  into task_row;

  perform private.day13_insert_housekeeping_event(
    target_hotel_id,
    task_row.id,
    'created',
    null,
    task_row.status,
    actor_id_value,
    request_key,
    jsonb_build_object(
      'room_id', task_row.room_id,
      'task_type', task_row.task_type
    )
  );

  return jsonb_build_object(
    'ok', true,
    'idempotent', false,
    'task', to_jsonb(task_row),
    'items',
      (
        select jsonb_agg(
          to_jsonb(item)
          order by item.sort_order
        )
        from public.housekeeping_task_items item
        where item.hotel_id = target_hotel_id
          and item.task_id = task_row.id
      )
  );
end;
$function$;

-- ---------------------------------------------------------------------------
-- 10. RPC: assignment
-- ---------------------------------------------------------------------------

create or replace function public.assign_housekeeping_task(
  target_hotel_id uuid,
  target_task_id uuid,
  target_staff_id uuid,
  priority_value text,
  due_at_value timestamptz,
  request_id_value text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  actor_id_value uuid;
  request_key text;
  task_row public.housekeeping_tasks%rowtype;
  staff_row public.staff%rowtype;
  previous_status_value text;
  existing_event_id uuid;
begin
  actor_id_value :=
    private.day13_require_housekeeping_manager(
      target_hotel_id
    );

  request_key :=
    nullif(trim(request_id_value), '');

  if request_key is null
     or length(request_key) < 8
  then
    raise exception
      'A request ID of at least eight characters is required.';
  end if;

  select event_record.id
  into existing_event_id
  from public.housekeeping_task_events event_record
  where event_record.hotel_id = target_hotel_id
    and event_record.request_id = request_key
    and event_record.event_type = 'assigned';

  if existing_event_id is not null then
    select task.*
    into task_row
    from public.housekeeping_tasks task
    where task.hotel_id = target_hotel_id
      and task.id = target_task_id;

    return jsonb_build_object(
      'ok', true,
      'idempotent', true,
      'task', to_jsonb(task_row)
    );
  end if;

  select staff.*
  into staff_row
  from public.staff staff
  where staff.hotel_id = target_hotel_id
    and staff.id = target_staff_id
    and staff.status = 'active'
    and staff.disabled_at is null;

  if staff_row.id is null then
    raise exception
      'Assigned staff is not active in this hotel.';
  end if;

  select task.*
  into task_row
  from public.housekeeping_tasks task
  where task.hotel_id = target_hotel_id
    and task.id = target_task_id
  for update;

  if not found then
    raise exception 'Housekeeping task was not found.';
  end if;

  if task_row.status not in (
    'pending',
    'assigned',
    'inspection_failed'
  ) then
    raise exception
      'Task cannot be assigned from status %.',
      task_row.status;
  end if;

  previous_status_value := task_row.status;

  update public.housekeeping_tasks
  set
    assigned_staff_id = target_staff_id,
    priority =
      coalesce(
        nullif(trim(priority_value), ''),
        priority
      ),
    due_at = due_at_value,
    assigned_at = now(),
    assigned_by = actor_id_value,
    status =
      case
        when status = 'pending'
          then 'assigned'
        else status
      end,
    updated_by = actor_id_value,
    metadata =
      metadata
      || jsonb_build_object(
        'assignment_request_id',
        request_key
      )
  where hotel_id = target_hotel_id
    and id = target_task_id
  returning *
  into task_row;

  perform private.day13_insert_housekeeping_event(
    target_hotel_id,
    target_task_id,
    'assigned',
    previous_status_value,
    task_row.status,
    actor_id_value,
    request_key,
    jsonb_build_object(
      'staff_id', target_staff_id,
      'staff_name', staff_row.full_name,
      'priority', task_row.priority,
      'due_at', task_row.due_at
    )
  );

  return jsonb_build_object(
    'ok', true,
    'idempotent', false,
    'task', to_jsonb(task_row),
    'staff', to_jsonb(staff_row)
  );
end;
$function$;

-- ---------------------------------------------------------------------------
-- 11. RPC: start work
-- ---------------------------------------------------------------------------

create or replace function public.start_housekeeping_task(
  target_hotel_id uuid,
  target_task_id uuid,
  request_id_value text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  actor_id_value uuid;
  request_key text;
  task_row public.housekeeping_tasks%rowtype;
  room_row public.rooms%rowtype;
  previous_status_value text;
  existing_event_id uuid;
begin
  actor_id_value :=
    private.day13_require_housekeeping_manager(
      target_hotel_id
    );

  request_key :=
    nullif(trim(request_id_value), '');

  if request_key is null
     or length(request_key) < 8
  then
    raise exception
      'A request ID of at least eight characters is required.';
  end if;

  select event_record.id
  into existing_event_id
  from public.housekeeping_task_events event_record
  where event_record.hotel_id = target_hotel_id
    and event_record.request_id = request_key
    and event_record.event_type = 'started';

  if existing_event_id is not null then
    select task.*
    into task_row
    from public.housekeeping_tasks task
    where task.hotel_id = target_hotel_id
      and task.id = target_task_id;

    return jsonb_build_object(
      'ok', true,
      'idempotent', true,
      'task', to_jsonb(task_row)
    );
  end if;

  select task.*
  into task_row
  from public.housekeeping_tasks task
  where task.hotel_id = target_hotel_id
    and task.id = target_task_id
  for update;

  if not found then
    raise exception 'Housekeeping task was not found.';
  end if;

  if task_row.status not in (
    'pending',
    'assigned',
    'inspection_failed'
  ) then
    raise exception
      'Task cannot start from status %.',
      task_row.status;
  end if;

  if task_row.assigned_staff_id is null then
    raise exception
      'Task must be assigned before work starts.';
  end if;

  select room.*
  into room_row
  from public.rooms room
  where room.hotel_id = target_hotel_id
    and room.id = task_row.room_id
  for update;

  if room_row.status in (
    'maintenance',
    'out_of_order'
  ) then
    raise exception
      'Maintenance/out-of-order room cannot start housekeeping.';
  end if;

  if room_row.status = 'occupied'
     and task_row.task_type not in (
       'stayover_cleaning',
       'turndown'
     )
  then
    raise exception
      'Occupied room requires a stayover/turndown task.';
  end if;

  previous_status_value := task_row.status;

  update public.housekeeping_tasks
  set
    status = 'in_progress',
    started_at = coalesce(started_at, now()),
    started_by = actor_id_value,
    updated_by = actor_id_value,
    inspection_status =
      case
        when inspection_status = 'failed'
          then null
        else inspection_status
      end,
    metadata =
      metadata
      || jsonb_build_object(
        'start_request_id',
        request_key
      )
  where hotel_id = target_hotel_id
    and id = target_task_id
  returning *
  into task_row;

  if room_row.status = 'available'
     and task_row.task_type in (
       'room_cleaning',
       'deep_cleaning'
     )
  then
    perform set_config(
      'stayqr.day13_request_id',
      request_key || ':room',
      true
    );

    perform set_config(
      'stayqr.day13_event_source',
      'housekeeping',
      true
    );

    perform set_config(
      'stayqr.day13_status_reason',
      'Housekeeping task started',
      true
    );

    update public.rooms
    set
      status = 'cleaning',
      status_changed_at = now(),
      status_changed_by = actor_id_value,
      updated_by = actor_id_value,
      metadata =
        metadata
        || jsonb_build_object(
          'active_housekeeping_task_id',
          target_task_id
        )
    where hotel_id = target_hotel_id
      and id = task_row.room_id;
  end if;

  perform private.day13_insert_housekeeping_event(
    target_hotel_id,
    target_task_id,
    'started',
    previous_status_value,
    task_row.status,
    actor_id_value,
    request_key,
    jsonb_build_object(
      'room_id', task_row.room_id,
      'assigned_staff_id',
      task_row.assigned_staff_id
    )
  );

  return jsonb_build_object(
    'ok', true,
    'idempotent', false,
    'task', to_jsonb(task_row)
  );
end;
$function$;

-- ---------------------------------------------------------------------------
-- 12. RPC: checklist item
-- ---------------------------------------------------------------------------

create or replace function public.update_housekeeping_checklist_item(
  target_hotel_id uuid,
  target_task_id uuid,
  target_item_id uuid,
  item_status_value text,
  notes_value text,
  request_id_value text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  actor_id_value uuid;
  request_key text;
  task_row public.housekeeping_tasks%rowtype;
  item_row public.housekeeping_task_items%rowtype;
  existing_event_id uuid;
begin
  actor_id_value :=
    private.day13_require_housekeeping_manager(
      target_hotel_id
    );

  request_key :=
    nullif(trim(request_id_value), '');

  if request_key is null
     or length(request_key) < 8
  then
    raise exception
      'A request ID of at least eight characters is required.';
  end if;

  if item_status_value not in (
    'pending',
    'completed',
    'failed',
    'not_applicable'
  ) then
    raise exception 'Invalid checklist item status.';
  end if;

  select event_record.id
  into existing_event_id
  from public.housekeeping_task_events event_record
  where event_record.hotel_id = target_hotel_id
    and event_record.request_id = request_key
    and event_record.event_type =
        'checklist_updated';

  if existing_event_id is not null then
    select item.*
    into item_row
    from public.housekeeping_task_items item
    where item.hotel_id = target_hotel_id
      and item.id = target_item_id;

    return jsonb_build_object(
      'ok', true,
      'idempotent', true,
      'item', to_jsonb(item_row)
    );
  end if;

  select task.*
  into task_row
  from public.housekeeping_tasks task
  where task.hotel_id = target_hotel_id
    and task.id = target_task_id
  for update;

  if not found then
    raise exception 'Housekeeping task was not found.';
  end if;

  if task_row.status not in (
    'assigned',
    'in_progress',
    'inspection_failed'
  ) then
    raise exception
      'Checklist cannot change from task status %.',
      task_row.status;
  end if;

  update public.housekeeping_task_items
  set
    item_status = item_status_value,
    completed_at =
      case
        when item_status_value in (
          'completed',
          'not_applicable'
        ) then now()
        else null
      end,
    completed_by =
      case
        when item_status_value in (
          'completed',
          'not_applicable'
        ) then actor_id_value
        else null
      end,
    notes = nullif(trim(notes_value), ''),
    updated_at = now(),
    metadata =
      metadata
      || jsonb_build_object(
        'last_request_id',
        request_key
      )
  where hotel_id = target_hotel_id
    and task_id = target_task_id
    and id = target_item_id
  returning *
  into item_row;

  if item_row.id is null then
    raise exception
      'Checklist item was not found for this task.';
  end if;

  perform private.day13_insert_housekeeping_event(
    target_hotel_id,
    target_task_id,
    'checklist_updated',
    task_row.status,
    task_row.status,
    actor_id_value,
    request_key,
    jsonb_build_object(
      'item_id', item_row.id,
      'item_code', item_row.item_code,
      'item_status', item_row.item_status
    )
  );

  return jsonb_build_object(
    'ok', true,
    'idempotent', false,
    'item', to_jsonb(item_row)
  );
end;
$function$;

-- ---------------------------------------------------------------------------
-- 13. RPC: cleaning complete
-- ---------------------------------------------------------------------------

create or replace function public.complete_housekeeping_cleaning(
  target_hotel_id uuid,
  target_task_id uuid,
  notes_value text,
  request_id_value text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  actor_id_value uuid;
  request_key text;
  task_row public.housekeeping_tasks%rowtype;
  incomplete_required integer;
  previous_status_value text;
  existing_event_id uuid;
begin
  actor_id_value :=
    private.day13_require_housekeeping_manager(
      target_hotel_id
    );

  request_key :=
    nullif(trim(request_id_value), '');

  if request_key is null
     or length(request_key) < 8
  then
    raise exception
      'A request ID of at least eight characters is required.';
  end if;

  select event_record.id
  into existing_event_id
  from public.housekeeping_task_events event_record
  where event_record.hotel_id = target_hotel_id
    and event_record.request_id = request_key
    and event_record.event_type =
        'cleaning_completed';

  if existing_event_id is not null then
    select task.*
    into task_row
    from public.housekeeping_tasks task
    where task.hotel_id = target_hotel_id
      and task.id = target_task_id;

    return jsonb_build_object(
      'ok', true,
      'idempotent', true,
      'task', to_jsonb(task_row)
    );
  end if;

  select task.*
  into task_row
  from public.housekeeping_tasks task
  where task.hotel_id = target_hotel_id
    and task.id = target_task_id
  for update;

  if not found then
    raise exception 'Housekeeping task was not found.';
  end if;

  if task_row.status <> 'in_progress' then
    raise exception
      'Cleaning can complete only from in_progress status.';
  end if;

  select count(*)
  into incomplete_required
  from public.housekeeping_task_items item
  where item.hotel_id = target_hotel_id
    and item.task_id = target_task_id
    and item.is_required
    and item.item_status not in (
      'completed',
      'not_applicable'
    );

  if incomplete_required > 0 then
    raise exception
      '% required checklist item(s) remain incomplete.',
      incomplete_required;
  end if;

  previous_status_value := task_row.status;

  update public.housekeeping_tasks
  set
    status = 'cleaning_complete',
    cleaning_completed_at = now(),
    cleaning_completed_by = actor_id_value,
    inspection_status = 'pending',
    notes =
      coalesce(
        nullif(trim(notes_value), ''),
        notes
      ),
    updated_by = actor_id_value,
    metadata =
      metadata
      || jsonb_build_object(
        'cleaning_complete_request_id',
        request_key
      )
  where hotel_id = target_hotel_id
    and id = target_task_id
  returning *
  into task_row;

  perform private.day13_insert_housekeeping_event(
    target_hotel_id,
    target_task_id,
    'cleaning_completed',
    previous_status_value,
    task_row.status,
    actor_id_value,
    request_key,
    jsonb_build_object(
      'required_items_complete', true
    )
  );

  return jsonb_build_object(
    'ok', true,
    'idempotent', false,
    'task', to_jsonb(task_row)
  );
end;
$function$;

-- ---------------------------------------------------------------------------
-- 14. RPC: inspect
-- ---------------------------------------------------------------------------

create or replace function public.inspect_housekeeping_task(
  target_hotel_id uuid,
  target_task_id uuid,
  result_value text,
  notes_value text,
  request_id_value text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  actor_id_value uuid;
  request_key text;
  task_row public.housekeeping_tasks%rowtype;
  inspection_row public.housekeeping_inspections%rowtype;
  snapshot_value jsonb;
  previous_status_value text;
begin
  actor_id_value :=
    private.day13_require_housekeeping_manager(
      target_hotel_id
    );

  request_key :=
    nullif(trim(request_id_value), '');

  if request_key is null
     or length(request_key) < 8
  then
    raise exception
      'A request ID of at least eight characters is required.';
  end if;

  if result_value not in (
    'passed',
    'failed'
  ) then
    raise exception
      'Inspection result must be passed or failed.';
  end if;

  select inspection.*
  into inspection_row
  from public.housekeeping_inspections inspection
  where inspection.hotel_id = target_hotel_id
    and inspection.request_id = request_key;

  if inspection_row.id is not null then
    select task.*
    into task_row
    from public.housekeeping_tasks task
    where task.hotel_id = target_hotel_id
      and task.id = target_task_id;

    return jsonb_build_object(
      'ok', true,
      'idempotent', true,
      'inspection', to_jsonb(inspection_row),
      'task', to_jsonb(task_row)
    );
  end if;

  select task.*
  into task_row
  from public.housekeeping_tasks task
  where task.hotel_id = target_hotel_id
    and task.id = target_task_id
  for update;

  if not found then
    raise exception 'Housekeeping task was not found.';
  end if;

  if task_row.status <> 'cleaning_complete' then
    raise exception
      'Inspection requires cleaning_complete status.';
  end if;

  snapshot_value :=
    jsonb_build_object(
      'task_id', task_row.id,
      'room_id', task_row.room_id,
      'room_number', task_row.room_number,
      'task_type', task_row.task_type,
      'assigned_staff_id',
        task_row.assigned_staff_id,
      'cleaning_completed_at',
        task_row.cleaning_completed_at,
      'result', result_value,
      'notes', nullif(trim(notes_value), ''),
      'items',
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', item.id,
              'code', item.item_code,
              'label', item.label,
              'required', item.is_required,
              'status', item.item_status,
              'completed_at', item.completed_at,
              'completed_by', item.completed_by,
              'notes', item.notes
            )
            order by item.sort_order
          )
          from public.housekeeping_task_items item
          where item.hotel_id = target_hotel_id
            and item.task_id = target_task_id
        )
    );

  insert into public.housekeeping_inspections (
    hotel_id,
    task_id,
    result,
    notes,
    inspected_by,
    request_id,
    snapshot_json,
    snapshot_hash
  )
  values (
    target_hotel_id,
    target_task_id,
    result_value,
    nullif(trim(notes_value), ''),
    actor_id_value,
    request_key,
    snapshot_value,
    private.day13_hash_json(
      snapshot_value
    )
  )
  returning *
  into inspection_row;

  previous_status_value := task_row.status;

  update public.housekeeping_tasks
  set
    status =
      case
        when result_value = 'passed'
          then 'inspected'
        else 'inspection_failed'
      end,
    inspected_at = now(),
    inspected_by = actor_id_value,
    inspection_status = result_value,
    updated_by = actor_id_value,
    metadata =
      metadata
      || jsonb_build_object(
        'last_inspection_id',
        inspection_row.id,
        'last_inspection_request_id',
        request_key
      )
  where hotel_id = target_hotel_id
    and id = target_task_id
  returning *
  into task_row;

  perform private.day13_insert_housekeeping_event(
    target_hotel_id,
    target_task_id,
    case
      when result_value = 'passed'
        then 'inspection_passed'
      else 'inspection_failed'
    end,
    previous_status_value,
    task_row.status,
    actor_id_value,
    request_key,
    jsonb_build_object(
      'inspection_id', inspection_row.id,
      'snapshot_hash',
        inspection_row.snapshot_hash
    )
  );

  return jsonb_build_object(
    'ok', true,
    'idempotent', false,
    'inspection', to_jsonb(inspection_row),
    'task', to_jsonb(task_row)
  );
end;
$function$;

-- ---------------------------------------------------------------------------
-- 15. RPC: room-ready approval
-- ---------------------------------------------------------------------------

create or replace function public.approve_housekeeping_room_ready(
  target_hotel_id uuid,
  target_task_id uuid,
  notes_value text,
  request_id_value text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  actor_id_value uuid;
  request_key text;
  task_row public.housekeeping_tasks%rowtype;
  room_row public.rooms%rowtype;
  previous_status_value text;
  commitments jsonb;
  existing_event_id uuid;
begin
  actor_id_value :=
    private.day13_require_housekeeping_manager(
      target_hotel_id
    );

  request_key :=
    nullif(trim(request_id_value), '');

  if request_key is null
     or length(request_key) < 8
  then
    raise exception
      'A request ID of at least eight characters is required.';
  end if;

  select event_record.id
  into existing_event_id
  from public.housekeeping_task_events event_record
  where event_record.hotel_id = target_hotel_id
    and event_record.request_id = request_key
    and event_record.event_type = 'room_ready';

  if existing_event_id is not null then
    select task.*
    into task_row
    from public.housekeeping_tasks task
    where task.hotel_id = target_hotel_id
      and task.id = target_task_id;

    select room.*
    into room_row
    from public.rooms room
    where room.hotel_id = target_hotel_id
      and room.id = task_row.room_id;

    return jsonb_build_object(
      'ok', true,
      'idempotent', true,
      'task', to_jsonb(task_row),
      'room', to_jsonb(room_row)
    );
  end if;

  select task.*
  into task_row
  from public.housekeeping_tasks task
  where task.hotel_id = target_hotel_id
    and task.id = target_task_id
  for update;

  if not found then
    raise exception 'Housekeeping task was not found.';
  end if;

  if task_row.status <> 'inspected'
     or task_row.inspection_status <> 'passed'
  then
    raise exception
      'Room-ready approval requires a passed inspection.';
  end if;

  select room.*
  into room_row
  from public.rooms room
  where room.hotel_id = target_hotel_id
    and room.id = task_row.room_id
  for update;

  if not found then
    raise exception 'Task room was not found.';
  end if;

  if room_row.status <> 'cleaning' then
    raise exception
      'Room-ready approval requires room status cleaning, found %.',
      room_row.status;
  end if;

  commitments :=
    private.day13_room_commitments(
      target_hotel_id,
      room_row.id
    );

  if (
    commitments
    ->> 'active_stays'
  )::integer > 0
  or (
    commitments
    ->> 'active_blocks'
  )::integer > 0
  then
    raise exception
      'Active stay or room block prevents room-ready approval.';
  end if;

  previous_status_value := task_row.status;

  update public.housekeeping_tasks
  set
    status = 'ready',
    room_ready_at = now(),
    room_ready_by = actor_id_value,
    notes =
      coalesce(
        nullif(trim(notes_value), ''),
        notes
      ),
    updated_by = actor_id_value,
    metadata =
      metadata
      || jsonb_build_object(
        'room_ready_request_id',
        request_key
      )
  where hotel_id = target_hotel_id
    and id = target_task_id
  returning *
  into task_row;

  perform set_config(
    'stayqr.day13_request_id',
    request_key || ':room',
    true
  );

  perform set_config(
    'stayqr.day13_event_source',
    'housekeeping',
    true
  );

  perform set_config(
    'stayqr.day13_status_reason',
    'Housekeeping inspection passed and room approved ready',
    true
  );

  update public.rooms
  set
    status = 'available',
    status_changed_at = now(),
    status_changed_by = actor_id_value,
    updated_by = actor_id_value,
    metadata =
      (metadata - 'active_housekeeping_task_id')
      || jsonb_build_object(
        'last_room_ready_task_id',
        target_task_id,
        'last_room_ready_at',
        now()
      )
  where hotel_id = target_hotel_id
    and id = task_row.room_id
  returning *
  into room_row;

  perform private.day13_insert_housekeeping_event(
    target_hotel_id,
    target_task_id,
    'room_ready',
    previous_status_value,
    task_row.status,
    actor_id_value,
    request_key,
    jsonb_build_object(
      'room_id', room_row.id,
      'room_status', room_row.status
    )
  );

  return jsonb_build_object(
    'ok', true,
    'idempotent', false,
    'task', to_jsonb(task_row),
    'room', to_jsonb(room_row)
  );
end;
$function$;

-- ---------------------------------------------------------------------------
-- 16. RPC: cancel task
-- ---------------------------------------------------------------------------

create or replace function public.cancel_housekeeping_task(
  target_hotel_id uuid,
  target_task_id uuid,
  reason_value text,
  request_id_value text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  actor_id_value uuid;
  request_key text;
  task_row public.housekeeping_tasks%rowtype;
  previous_status_value text;
  existing_event_id uuid;
begin
  actor_id_value :=
    private.day13_require_housekeeping_manager(
      target_hotel_id
    );

  request_key :=
    nullif(trim(request_id_value), '');

  if request_key is null
     or length(request_key) < 8
  then
    raise exception
      'A request ID of at least eight characters is required.';
  end if;

  if nullif(trim(reason_value), '') is null then
    raise exception 'Cancellation reason is required.';
  end if;

  select event_record.id
  into existing_event_id
  from public.housekeeping_task_events event_record
  where event_record.hotel_id = target_hotel_id
    and event_record.request_id = request_key
    and event_record.event_type = 'cancelled';

  if existing_event_id is not null then
    select task.*
    into task_row
    from public.housekeeping_tasks task
    where task.hotel_id = target_hotel_id
      and task.id = target_task_id;

    return jsonb_build_object(
      'ok', true,
      'idempotent', true,
      'task', to_jsonb(task_row)
    );
  end if;

  select task.*
  into task_row
  from public.housekeeping_tasks task
  where task.hotel_id = target_hotel_id
    and task.id = target_task_id
  for update;

  if not found then
    raise exception 'Housekeeping task was not found.';
  end if;

  if task_row.status in (
    'ready',
    'completed',
    'cancelled'
  ) then
    raise exception
      'Task cannot be cancelled from status %.',
      task_row.status;
  end if;

  previous_status_value := task_row.status;

  update public.housekeeping_tasks
  set
    status = 'cancelled',
    cancelled_at = now(),
    cancelled_by = actor_id_value,
    cancellation_reason = trim(reason_value),
    updated_by = actor_id_value,
    metadata =
      metadata
      || jsonb_build_object(
        'cancel_request_id',
        request_key
      )
  where hotel_id = target_hotel_id
    and id = target_task_id
  returning *
  into task_row;

  perform private.day13_insert_housekeeping_event(
    target_hotel_id,
    target_task_id,
    'cancelled',
    previous_status_value,
    task_row.status,
    actor_id_value,
    request_key,
    jsonb_build_object(
      'reason', trim(reason_value)
    )
  );

  return jsonb_build_object(
    'ok', true,
    'idempotent', false,
    'task', to_jsonb(task_row)
  );
end;
$function$;

-- ---------------------------------------------------------------------------
-- 17. Read-only workspace/mobile queue
-- ---------------------------------------------------------------------------

create or replace function public.get_housekeeping_workspace(
  target_hotel_id uuid
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
      'housekeeping.view',
      'housekeeping.manage',
      'rooms.view',
      'rooms.manage'
    ]::text[]
  ) then
    raise exception
      'Housekeeping workspace access denied.';
  end if;

  return jsonb_build_object(
    'tasks',
      coalesce(
        (
          select jsonb_agg(
            to_jsonb(task)
            || jsonb_build_object(
              'room',
                jsonb_build_object(
                  'id', room.id,
                  'room_number', room.room_number,
                  'status', room.status,
                  'floor_id', room.floor_id,
                  'room_type_id', room.room_type_id
                ),
              'staff',
                case
                  when staff.id is null then null
                  else jsonb_build_object(
                    'id', staff.id,
                    'full_name', staff.full_name,
                    'role', staff.role,
                    'status', staff.status
                  )
                end,
              'items',
                (
                  select coalesce(
                    jsonb_agg(
                      to_jsonb(item)
                      order by item.sort_order
                    ),
                    '[]'::jsonb
                  )
                  from public.housekeeping_task_items item
                  where item.hotel_id = task.hotel_id
                    and item.task_id = task.id
                ),
              'latest_inspection',
                (
                  select to_jsonb(inspection)
                  from public.housekeeping_inspections inspection
                  where inspection.hotel_id = task.hotel_id
                    and inspection.task_id = task.id
                  order by inspection.inspected_at desc
                  limit 1
                )
            )
            order by
              case task.priority
                when 'urgent' then 1
                when 'high' then 2
                when 'normal' then 3
                else 4
              end,
              task.due_at nulls last,
              task.created_at
          )
          from public.housekeeping_tasks task
          join public.rooms room
            on room.hotel_id = task.hotel_id
           and room.id = task.room_id
          left join public.staff staff
            on staff.hotel_id = task.hotel_id
           and staff.id = task.assigned_staff_id
          where task.hotel_id = target_hotel_id
        ),
        '[]'::jsonb
      ),
    'workload',
      coalesce(
        (
          select jsonb_agg(
            workload_row
            order by
              workload_row ->> 'staff_name'
          )
          from (
            select jsonb_build_object(
              'staff_id', staff.id,
              'staff_name', staff.full_name,
              'role', staff.role,
              'open_tasks',
                count(task.id) filter (
                  where task.status in (
                    'assigned',
                    'in_progress',
                    'cleaning_complete',
                    'inspection_failed',
                    'inspected'
                  )
                ),
              'urgent_tasks',
                count(task.id) filter (
                  where task.priority = 'urgent'
                    and task.status in (
                      'assigned',
                      'in_progress',
                      'cleaning_complete',
                      'inspection_failed',
                      'inspected'
                    )
                ),
              'in_progress_tasks',
                count(task.id) filter (
                  where task.status = 'in_progress'
                ),
              'ready_today',
                count(task.id) filter (
                  where task.status = 'ready'
                    and task.room_ready_at::date =
                        current_date
                )
            ) workload_row
            from public.staff staff
            left join public.housekeeping_tasks task
              on task.hotel_id = staff.hotel_id
             and task.assigned_staff_id = staff.id
            where staff.hotel_id = target_hotel_id
              and staff.status = 'active'
              and staff.disabled_at is null
            group by
              staff.id,
              staff.full_name,
              staff.role
          ) staff_workload
        ),
        '[]'::jsonb
      ),
    'unassigned_open_tasks',
      (
        select count(*)
        from public.housekeeping_tasks task
        where task.hotel_id = target_hotel_id
          and task.assigned_staff_id is null
          and task.status in (
            'pending',
            'inspection_failed'
          )
      ),
    'rooms_waiting_for_ready',
      (
        select count(*)
        from public.rooms room
        where room.hotel_id = target_hotel_id
          and room.status = 'cleaning'
      )
  );
end;
$function$;

create or replace function public.get_housekeeping_mobile_queue(
  target_hotel_id uuid,
  target_staff_id uuid default null
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
      'housekeeping.view',
      'housekeeping.manage',
      'rooms.view',
      'rooms.manage'
    ]::text[]
  ) then
    raise exception
      'Housekeeping mobile access denied.';
  end if;

  return coalesce(
    (
      select jsonb_agg(
        jsonb_build_object(
          'task_id', task.id,
          'room_id', task.room_id,
          'room_number', room.room_number,
          'room_status', room.status,
          'task_type', task.task_type,
          'status', task.status,
          'priority', task.priority,
          'due_at', task.due_at,
          'notes', task.notes,
          'assigned_staff_id',
            task.assigned_staff_id,
          'assigned_to', task.assigned_to,
          'completed_items',
            (
              select count(*)
              from public.housekeeping_task_items item
              where item.hotel_id = task.hotel_id
                and item.task_id = task.id
                and item.item_status in (
                  'completed',
                  'not_applicable'
                )
            ),
          'total_items',
            (
              select count(*)
              from public.housekeeping_task_items item
              where item.hotel_id = task.hotel_id
                and item.task_id = task.id
            )
        )
        order by
          case task.priority
            when 'urgent' then 1
            when 'high' then 2
            when 'normal' then 3
            else 4
          end,
          task.due_at nulls last,
          task.created_at
      )
      from public.housekeeping_tasks task
      join public.rooms room
        on room.hotel_id = task.hotel_id
       and room.id = task.room_id
      where task.hotel_id = target_hotel_id
        and task.status in (
          'pending',
          'assigned',
          'in_progress',
          'cleaning_complete',
          'inspection_failed',
          'inspected'
        )
        and (
          target_staff_id is null
          or task.assigned_staff_id =
             target_staff_id
          or task.assigned_staff_id is null
        )
    ),
    '[]'::jsonb
  );
end;
$function$;

-- ---------------------------------------------------------------------------
-- 18. RPC-only privilege boundary
-- ---------------------------------------------------------------------------

revoke insert, update, delete
on public.housekeeping_tasks
from authenticated;

revoke all
on public.housekeeping_checklist_templates,
   public.housekeeping_task_items,
   public.housekeeping_inspections,
   public.housekeeping_task_events
from public, anon, authenticated;

grant select
on public.housekeeping_checklist_templates,
   public.housekeeping_task_items,
   public.housekeeping_inspections,
   public.housekeeping_task_events
to authenticated;

grant all
on public.housekeeping_checklist_templates,
   public.housekeeping_task_items,
   public.housekeeping_inspections,
   public.housekeeping_task_events
to service_role;

revoke all
on function private.day13_require_housekeeping_manager(uuid)
from public, anon, authenticated;

revoke all
on function private.day13_hash_json(jsonb)
from public, anon, authenticated;

revoke all
on function private.day13_insert_housekeeping_event(
  uuid,uuid,text,text,text,uuid,text,jsonb
)
from public, anon, authenticated;

grant execute
on function private.day13_require_housekeeping_manager(uuid)
to service_role;

grant execute
on function private.day13_hash_json(jsonb)
to service_role;

grant execute
on function private.day13_insert_housekeeping_event(
  uuid,uuid,text,text,text,uuid,text,jsonb
)
to service_role;

revoke all
on function public.create_housekeeping_task(
  uuid,uuid,text,text,timestamptz,text,text,uuid,text
)
from public, anon;

revoke all
on function public.assign_housekeeping_task(
  uuid,uuid,uuid,text,timestamptz,text
)
from public, anon;

revoke all
on function public.start_housekeeping_task(
  uuid,uuid,text
)
from public, anon;

revoke all
on function public.update_housekeeping_checklist_item(
  uuid,uuid,uuid,text,text,text
)
from public, anon;

revoke all
on function public.complete_housekeeping_cleaning(
  uuid,uuid,text,text
)
from public, anon;

revoke all
on function public.inspect_housekeeping_task(
  uuid,uuid,text,text,text
)
from public, anon;

revoke all
on function public.approve_housekeeping_room_ready(
  uuid,uuid,text,text
)
from public, anon;

revoke all
on function public.cancel_housekeeping_task(
  uuid,uuid,text,text
)
from public, anon;

revoke all
on function public.get_housekeeping_workspace(uuid)
from public, anon;

revoke all
on function public.get_housekeeping_mobile_queue(uuid,uuid)
from public, anon;

grant execute
on function public.create_housekeeping_task(
  uuid,uuid,text,text,timestamptz,text,text,uuid,text
)
to authenticated, service_role;

grant execute
on function public.assign_housekeeping_task(
  uuid,uuid,uuid,text,timestamptz,text
)
to authenticated, service_role;

grant execute
on function public.start_housekeeping_task(
  uuid,uuid,text
)
to authenticated, service_role;

grant execute
on function public.update_housekeeping_checklist_item(
  uuid,uuid,uuid,text,text,text
)
to authenticated, service_role;

grant execute
on function public.complete_housekeeping_cleaning(
  uuid,uuid,text,text
)
to authenticated, service_role;

grant execute
on function public.inspect_housekeeping_task(
  uuid,uuid,text,text,text
)
to authenticated, service_role;

grant execute
on function public.approve_housekeeping_room_ready(
  uuid,uuid,text,text
)
to authenticated, service_role;

grant execute
on function public.cancel_housekeeping_task(
  uuid,uuid,text,text
)
to authenticated, service_role;

grant execute
on function public.get_housekeeping_workspace(uuid)
to authenticated, service_role;

grant execute
on function public.get_housekeeping_mobile_queue(uuid,uuid)
to authenticated, service_role;

comment on table public.housekeeping_task_items is
'Immutable checklist snapshot structure with auditable item completion state.';

comment on table public.housekeeping_inspections is
'Immutable passed/failed room inspection snapshots protected by SHA-256.';

comment on function public.approve_housekeeping_room_ready(uuid,uuid,text,text) is
'Only housekeeping workflow path that changes a cleaned inspected room back to available.';

comment on function public.get_housekeeping_mobile_queue(uuid,uuid) is
'Read-only mobile staff queue with room, priority, due time and checklist progress.';

commit;
