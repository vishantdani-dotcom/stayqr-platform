-- ============================================================================
-- StayQR v1.0
-- Day 13 Migration 041 REV1
-- Maintenance and out-of-order lifecycle
--
-- REQUIRES
-- --------
-- Migration 039 accepted:
--   structural 60/60
--   runtime REV2 30/30
--
-- Migration 040 REV2 accepted:
--   structural 70/70
--   runtime 40/40
--
-- CONTROLLED VD STAY INN BASELINE
-- --------------------------------
-- Rooms: 12
-- Room blocks: 0
-- Maintenance tasks: missing
-- Housekeeping tasks: 14
-- Housekeeping items: 112
-- Housekeeping inspections/events: 0
-- Room status events: 0
-- Room 106: cleaning
-- Day 12 authoritative balance: INR 22,785
--
-- THIS MIGRATION
-- --------------
-- 1. Creates an auditable maintenance task lifecycle.
-- 2. Requires explicit inventory impact:
--      none | maintenance | out_of_order
-- 3. Creates/reuses authoritative room blocks for offline rooms.
-- 4. Prevents an occupied room from being silently removed from inventory.
-- 5. Adds assignment, work start, hold/resume, resolution and verification.
-- 6. Adds immutable maintenance events and SHA-256 verification snapshots.
-- 7. Releases room blocks only after maintenance verification.
-- 8. Supports maintenance -> housekeeping cleaning handoff.
-- 9. Returns a room to available only when no cleaning is required and all
--    active stay/block/housekeeping guards are clear.
-- 10. Adds management workspace and mobile maintenance queue.
--
-- WORKFLOW
-- --------
-- reported -> assigned -> in_progress -> on_hold -> in_progress
--          -> resolved -> verified
--          -> cancelled
--
-- INVENTORY CONTRACT
-- ------------------
-- none:
--   maintenance is recorded but room inventory/status does not change.
--
-- maintenance:
--   room status = maintenance
--   room block type = maintenance
--
-- out_of_order:
--   room status = out_of_order
--   room block type = out_of_order
--
-- Verification:
--   - releases the linked room block;
--   - either sends the room to housekeeping cleaning;
--   - or safely returns it to its previous/available state.
--
-- SAFETY
-- ------
-- - No existing room, block, reservation or stay is changed.
-- - No production maintenance task is fabricated.
-- - No production housekeeping task is inserted.
-- - Room 106 remains cleaning.
-- - Financial state remains unchanged.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 0. Strict preflight
-- ---------------------------------------------------------------------------

do $preflight$
declare
  missing_objects text;
  existing_targets text;
  room_count integer;
  room_block_count integer;
  housekeeping_task_count integer;
  housekeeping_item_count integer;
  room106_status text;
  controlled_balance numeric(14,2);
begin
  select string_agg(object_name, ', ' order by object_name)
  into missing_objects
  from (
    values
      (
        'public.rooms',
        to_regclass('public.rooms') is not null
      ),
      (
        'public.room_blocks',
        to_regclass('public.room_blocks') is not null
      ),
      (
        'public.staff',
        to_regclass('public.staff') is not null
      ),
      (
        'public.housekeeping_tasks',
        to_regclass('public.housekeeping_tasks') is not null
      ),
      (
        'public.housekeeping_task_items',
        to_regclass('public.housekeeping_task_items') is not null
      ),
      (
        'public.room_status_events',
        to_regclass('public.room_status_events') is not null
      ),
      (
        'private.day13_room_commitments(uuid,uuid)',
        to_regprocedure(
          'private.day13_room_commitments(uuid,uuid)'
        ) is not null
      ),
      (
        'private.day13_require_room_manager(uuid)',
        to_regprocedure(
          'private.day13_require_room_manager(uuid)'
        ) is not null
      ),
      (
        'private.day13_hash_json(jsonb)',
        to_regprocedure(
          'private.day13_hash_json(jsonb)'
        ) is not null
      ),
      (
        'public.create_housekeeping_task(uuid,uuid,text,text,timestamptz,text,text,uuid,text)',
        to_regprocedure(
          'public.create_housekeeping_task(uuid,uuid,text,text,timestamptz,text,text,uuid,text)'
        ) is not null
      ),
      (
        'public.transition_room_status(uuid,uuid,text,text,text,text)',
        to_regprocedure(
          'public.transition_room_status(uuid,uuid,text,text,text,text)'
        ) is not null
      ),
      (
        'public.get_available_rooms(uuid,date,date,uuid)',
        to_regprocedure(
          'public.get_available_rooms(uuid,date,date,uuid)'
        ) is not null
      )
  ) required(object_name, object_exists)
  where not object_exists;

  if missing_objects is not null then
    raise exception
      'Migration 041 prerequisites are missing: %',
      missing_objects;
  end if;

  select string_agg(object_name, ', ' order by object_name)
  into existing_targets
  from (
    values
      (
        'public.maintenance_tasks',
        to_regclass('public.maintenance_tasks')
      ),
      (
        'public.maintenance_task_events',
        to_regclass('public.maintenance_task_events')
      ),
      (
        'public.maintenance_verifications',
        to_regclass('public.maintenance_verifications')
      )
  ) targets(object_name, relation_id)
  where relation_id is not null;

  if existing_targets is not null then
    raise exception
      'Migration 041 target objects already exist: %. Do not rerun REV1.',
      existing_targets;
  end if;

  select count(*)
  into room_count
  from public.rooms room
  where room.hotel_id =
    '77d850d0-016d-4155-bc44-a6207d30e7b9'::uuid;

  select count(*)
  into room_block_count
  from public.room_blocks block_record
  where block_record.hotel_id =
    '77d850d0-016d-4155-bc44-a6207d30e7b9'::uuid;

  select count(*)
  into housekeeping_task_count
  from public.housekeeping_tasks task
  where task.hotel_id =
    '77d850d0-016d-4155-bc44-a6207d30e7b9'::uuid;

  select count(*)
  into housekeeping_item_count
  from public.housekeeping_task_items item
  where item.hotel_id =
    '77d850d0-016d-4155-bc44-a6207d30e7b9'::uuid;

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

  if room_count <> 12
     or room_block_count <> 0
     or housekeeping_task_count <> 14
     or housekeeping_item_count <> 112
     or room106_status <> 'cleaning'
     or controlled_balance <> 22785
  then
    raise exception
      'Controlled baseline changed: rooms %, blocks %, housekeeping %, items %, Room106 %, balance %.',
      room_count,
      room_block_count,
      housekeeping_task_count,
      housekeeping_item_count,
      room106_status,
      controlled_balance;
  end if;
end;
$preflight$;

-- ---------------------------------------------------------------------------
-- 1. Maintenance tasks
-- ---------------------------------------------------------------------------

create table public.maintenance_tasks (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null,
  room_id uuid not null,

  task_number text not null,
  title text not null,
  description text,
  category text not null,
  severity text not null,
  status text not null default 'reported',

  inventory_impact text not null default 'none',
  previous_room_status text not null,
  room_block_id uuid,

  assigned_staff_id uuid,
  reported_by uuid not null,
  assigned_by uuid,
  started_by uuid,
  resolved_by uuid,
  verified_by uuid,
  cancelled_by uuid,

  request_id text not null,
  due_at timestamptz,
  expected_return_date date,

  assigned_at timestamptz,
  started_at timestamptz,
  held_at timestamptz,
  hold_reason text,
  resolved_at timestamptz,
  resolution_notes text,
  verified_at timestamptz,
  verification_notes text,
  requires_cleaning boolean not null default true,
  housekeeping_task_id uuid,
  cancelled_at timestamptz,
  cancellation_reason text,

  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid,

  constraint maintenance_tasks_hotel_fkey
    foreign key (hotel_id)
    references public.hotels(id)
    on delete restrict,

  constraint maintenance_tasks_room_fkey
    foreign key (hotel_id, room_id)
    references public.rooms(hotel_id, id)
    on delete restrict,

  constraint maintenance_tasks_room_block_fkey
    foreign key (hotel_id, room_block_id)
    references public.room_blocks(hotel_id, id)
    on delete restrict,

  constraint maintenance_tasks_assigned_staff_fkey
    foreign key (assigned_staff_id)
    references public.staff(id)
    on delete set null,

  constraint maintenance_tasks_reported_by_fkey
    foreign key (reported_by)
    references auth.users(id)
    on delete restrict,

  constraint maintenance_tasks_assigned_by_fkey
    foreign key (assigned_by)
    references auth.users(id)
    on delete set null,

  constraint maintenance_tasks_started_by_fkey
    foreign key (started_by)
    references auth.users(id)
    on delete set null,

  constraint maintenance_tasks_resolved_by_fkey
    foreign key (resolved_by)
    references auth.users(id)
    on delete set null,

  constraint maintenance_tasks_verified_by_fkey
    foreign key (verified_by)
    references auth.users(id)
    on delete set null,

  constraint maintenance_tasks_cancelled_by_fkey
    foreign key (cancelled_by)
    references auth.users(id)
    on delete set null,

  constraint maintenance_tasks_updated_by_fkey
    foreign key (updated_by)
    references auth.users(id)
    on delete set null,

  constraint maintenance_tasks_housekeeping_fkey
    foreign key (hotel_id, housekeeping_task_id)
    references public.housekeeping_tasks(hotel_id, id)
    on delete set null,

  constraint maintenance_tasks_number_check
    check (length(trim(task_number)) > 0),

  constraint maintenance_tasks_title_check
    check (length(trim(title)) > 0),

  constraint maintenance_tasks_category_check
    check (
      category in (
        'electrical',
        'plumbing',
        'hvac',
        'appliance',
        'furniture',
        'structural',
        'safety',
        'pest_control',
        'internet',
        'other'
      )
    ),

  constraint maintenance_tasks_severity_check
    check (
      severity in (
        'low',
        'medium',
        'high',
        'critical'
      )
    ),

  constraint maintenance_tasks_status_check
    check (
      status in (
        'reported',
        'assigned',
        'in_progress',
        'on_hold',
        'resolved',
        'verified',
        'cancelled'
      )
    ),

  constraint maintenance_tasks_impact_check
    check (
      inventory_impact in (
        'none',
        'maintenance',
        'out_of_order'
      )
    ),

  constraint maintenance_tasks_previous_status_check
    check (
      previous_room_status in (
        'available',
        'occupied',
        'cleaning',
        'maintenance',
        'out_of_order'
      )
    ),

  constraint maintenance_tasks_offline_metadata_check
    check (
      inventory_impact = 'none'
      or (
        room_block_id is not null
        and expected_return_date is not null
      )
    ),

  constraint maintenance_tasks_resolved_check
    check (
      status not in (
        'resolved',
        'verified'
      )
      or (
        resolved_at is not null
        and resolved_by is not null
        and nullif(trim(resolution_notes), '') is not null
      )
    ),

  constraint maintenance_tasks_verified_check
    check (
      status <> 'verified'
      or (
        verified_at is not null
        and verified_by is not null
      )
    ),

  constraint maintenance_tasks_cancelled_check
    check (
      status <> 'cancelled'
      or (
        cancelled_at is not null
        and cancelled_by is not null
        and nullif(trim(cancellation_reason), '') is not null
      )
    ),

  constraint maintenance_tasks_metadata_object
    check (jsonb_typeof(metadata) = 'object')
);

create unique index uq_maintenance_tasks_hotel_id_id
  on public.maintenance_tasks(hotel_id, id);

create unique index uq_maintenance_tasks_request
  on public.maintenance_tasks(hotel_id, request_id);

create unique index uq_maintenance_tasks_number
  on public.maintenance_tasks(hotel_id, task_number);

create unique index uq_maintenance_active_offline_room
  on public.maintenance_tasks(hotel_id, room_id)
  where inventory_impact <> 'none'
    and status in (
      'reported',
      'assigned',
      'in_progress',
      'on_hold',
      'resolved'
    );

create index idx_maintenance_tasks_workload
  on public.maintenance_tasks(
    hotel_id,
    assigned_staff_id,
    status,
    severity,
    due_at
  );

create index idx_maintenance_tasks_room_time
  on public.maintenance_tasks(
    hotel_id,
    room_id,
    created_at desc
  );

alter table public.maintenance_tasks
enable row level security;

create policy stayqr_maintenance_tasks_select
on public.maintenance_tasks
for select
to authenticated
using (
  private.user_has_any_permission(
    hotel_id,
    array[
      'rooms.view',
      'rooms.manage',
      'housekeeping.view',
      'housekeeping.manage',
      'hotel.manage'
    ]::text[]
  )
);

-- ---------------------------------------------------------------------------
-- 2. Immutable maintenance events
-- ---------------------------------------------------------------------------

create table public.maintenance_task_events (
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

  constraint maintenance_events_hotel_fkey
    foreign key (hotel_id)
    references public.hotels(id)
    on delete restrict,

  constraint maintenance_events_task_fkey
    foreign key (hotel_id, task_id)
    references public.maintenance_tasks(hotel_id, id)
    on delete restrict,

  constraint maintenance_events_actor_fkey
    foreign key (actor_id)
    references auth.users(id)
    on delete set null,

  constraint maintenance_events_type_check
    check (
      event_type in (
        'reported',
        'assigned',
        'started',
        'held',
        'resumed',
        'resolved',
        'verified',
        'cancelled',
        'room_block_created',
        'room_block_released',
        'housekeeping_handoff'
      )
    ),

  constraint maintenance_events_metadata_object
    check (jsonb_typeof(metadata) = 'object')
);

create unique index uq_maintenance_event_request
  on public.maintenance_task_events(
    hotel_id,
    request_id,
    event_type
  )
  where request_id is not null;

create index idx_maintenance_events_task_time
  on public.maintenance_task_events(
    hotel_id,
    task_id,
    occurred_at desc
  );

alter table public.maintenance_task_events
enable row level security;

create policy stayqr_maintenance_events_select
on public.maintenance_task_events
for select
to authenticated
using (
  private.user_has_any_permission(
    hotel_id,
    array[
      'rooms.view',
      'rooms.manage',
      'housekeeping.view',
      'housekeeping.manage',
      'hotel.manage'
    ]::text[]
  )
);

-- ---------------------------------------------------------------------------
-- 3. Immutable verification evidence
-- ---------------------------------------------------------------------------

create table public.maintenance_verifications (
  id uuid primary key default gen_random_uuid(),
  hotel_id uuid not null,
  task_id uuid not null,

  outcome text not null,
  notes text,
  verified_by uuid not null,
  verified_at timestamptz not null default now(),

  request_id text not null,
  snapshot_json jsonb not null,
  snapshot_hash text not null,

  constraint maintenance_verifications_hotel_fkey
    foreign key (hotel_id)
    references public.hotels(id)
    on delete restrict,

  constraint maintenance_verifications_task_fkey
    foreign key (hotel_id, task_id)
    references public.maintenance_tasks(hotel_id, id)
    on delete restrict,

  constraint maintenance_verifications_actor_fkey
    foreign key (verified_by)
    references auth.users(id)
    on delete restrict,

  constraint maintenance_verifications_outcome_check
    check (
      outcome in (
        'verified',
        'reopened'
      )
    ),

  constraint maintenance_verifications_snapshot_object
    check (jsonb_typeof(snapshot_json) = 'object'),

  constraint maintenance_verifications_hash_check
    check (length(snapshot_hash) = 64)
);

create unique index uq_maintenance_verification_request
  on public.maintenance_verifications(
    hotel_id,
    request_id
  );

create index idx_maintenance_verifications_task_time
  on public.maintenance_verifications(
    hotel_id,
    task_id,
    verified_at desc
  );

alter table public.maintenance_verifications
enable row level security;

create policy stayqr_maintenance_verifications_select
on public.maintenance_verifications
for select
to authenticated
using (
  private.user_has_any_permission(
    hotel_id,
    array[
      'rooms.view',
      'rooms.manage',
      'housekeeping.view',
      'housekeeping.manage',
      'hotel.manage'
    ]::text[]
  )
);

-- ---------------------------------------------------------------------------
-- 4. Helpers
-- ---------------------------------------------------------------------------

create or replace function private.day13_require_maintenance_manager(
  target_hotel_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if target_hotel_id is null then
    raise exception 'Hotel ID is required.';
  end if;

  if not private.user_has_any_permission(
    target_hotel_id,
    array[
      'rooms.manage',
      'housekeeping.manage',
      'hotel.manage',
      'superadmin.manage'
    ]::text[]
  ) then
    raise exception
      'Maintenance management access denied.';
  end if;

  return private.day11_require_current_actor();
end;
$function$;

create or replace function private.day13_maintenance_task_number(
  target_hotel_id uuid
)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  hotel_timezone text;
  business_day date;
  next_sequence integer;
begin
  select hotel.timezone
  into hotel_timezone
  from public.hotels hotel
  where hotel.id = target_hotel_id;

  business_day :=
    (
      now()
      at time zone coalesce(
        hotel_timezone,
        'Asia/Kolkata'
      )
    )::date;

  perform pg_advisory_xact_lock(
    hashtextextended(
      target_hotel_id::text
      || ':maintenance:'
      || business_day::text,
      0
    )
  );

  select count(*) + 1
  into next_sequence
  from public.maintenance_tasks task
  where task.hotel_id = target_hotel_id
    and task.created_at >= business_day::timestamptz
    and task.created_at <
        (business_day + 1)::timestamptz;

  return
    'MNT-'
    || to_char(business_day, 'YYYYMMDD')
    || '-'
    || lpad(next_sequence::text, 4, '0');
end;
$function$;

create or replace function private.day13_insert_maintenance_event(
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
  insert into public.maintenance_task_events (
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
  set request_id = excluded.request_id
  returning id
  into event_id_value;

  return event_id_value;
end;
$function$;

create or replace function private.day13_touch_maintenance_task()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  new.updated_at := now();
  new.updated_by :=
    coalesce(
      private.day11_valid_auth_actor(auth.uid()),
      new.updated_by,
      old.updated_by
    );

  return new;
end;
$function$;

create trigger maintenance_tasks_day13_touch
before update
on public.maintenance_tasks
for each row
execute function private.day13_touch_maintenance_task();

-- ---------------------------------------------------------------------------
-- 5. Report maintenance task
-- ---------------------------------------------------------------------------

create or replace function public.report_maintenance_task(
  target_hotel_id uuid,
  target_room_id uuid,
  title_value text,
  description_value text,
  category_value text,
  severity_value text,
  inventory_impact_value text,
  expected_return_date_value date,
  due_at_value timestamptz,
  requires_cleaning_value boolean,
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
  room_row public.rooms%rowtype;
  task_row public.maintenance_tasks%rowtype;
  block_row public.room_blocks%rowtype;
  commitments jsonb;
  block_type_value text;
begin
  actor_id_value :=
    private.day13_require_maintenance_manager(
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
  from public.maintenance_tasks task
  where task.hotel_id = target_hotel_id
    and task.request_id = request_key;

  if task_row.id is not null then
    return jsonb_build_object(
      'ok', true,
      'idempotent', true,
      'task', to_jsonb(task_row)
    );
  end if;

  if nullif(trim(title_value), '') is null then
    raise exception 'Maintenance title is required.';
  end if;

  if category_value not in (
    'electrical',
    'plumbing',
    'hvac',
    'appliance',
    'furniture',
    'structural',
    'safety',
    'pest_control',
    'internet',
    'other'
  ) then
    raise exception 'Invalid maintenance category.';
  end if;

  if severity_value not in (
    'low',
    'medium',
    'high',
    'critical'
  ) then
    raise exception 'Invalid maintenance severity.';
  end if;

  if inventory_impact_value not in (
    'none',
    'maintenance',
    'out_of_order'
  ) then
    raise exception 'Invalid inventory impact.';
  end if;

  select room.*
  into room_row
  from public.rooms room
  where room.hotel_id = target_hotel_id
    and room.id = target_room_id
  for update;

  if not found then
    raise exception 'Room was not found.';
  end if;

  if not room_row.is_active then
    raise exception
      'Archived room cannot receive a maintenance task.';
  end if;

  commitments :=
    private.day13_room_commitments(
      target_hotel_id,
      target_room_id
    );

  if inventory_impact_value <> 'none'
     and (
       commitments
       ->> 'active_stays'
     )::integer > 0
  then
    raise exception
      'Occupied room cannot be removed from inventory. Move or check out the active stay first.';
  end if;

  if inventory_impact_value <> 'none'
     and (
       expected_return_date_value is null
       or expected_return_date_value <= current_date
     )
  then
    raise exception
      'Offline maintenance requires a future expected return date.';
  end if;

  if inventory_impact_value <> 'none'
     and room_row.status not in (
       'available',
       'cleaning',
       'maintenance',
       'out_of_order'
     )
  then
    raise exception
      'Room status % cannot enter offline maintenance.',
      room_row.status;
  end if;

  if inventory_impact_value <> 'none' then
    block_type_value :=
      case
        when inventory_impact_value =
             'out_of_order'
          then 'out_of_order'
        else 'maintenance'
      end;

    insert into public.room_blocks (
      hotel_id,
      room_id,
      block_type,
      status,
      start_date,
      end_date,
      reason,
      notes,
      created_by,
      updated_by
    )
    values (
      target_hotel_id,
      target_room_id,
      block_type_value,
      'active',
      current_date,
      expected_return_date_value,
      trim(title_value),
      nullif(trim(description_value), ''),
      actor_id_value,
      actor_id_value
    )
    returning *
    into block_row;
  end if;

  insert into public.maintenance_tasks (
    hotel_id,
    room_id,
    task_number,
    title,
    description,
    category,
    severity,
    status,
    inventory_impact,
    previous_room_status,
    room_block_id,
    reported_by,
    request_id,
    due_at,
    expected_return_date,
    requires_cleaning,
    updated_by,
    metadata
  )
  values (
    target_hotel_id,
    target_room_id,
    private.day13_maintenance_task_number(
      target_hotel_id
    ),
    trim(title_value),
    nullif(trim(description_value), ''),
    category_value,
    severity_value,
    'reported',
    inventory_impact_value,
    room_row.status,
    block_row.id,
    actor_id_value,
    request_key,
    due_at_value,
    expected_return_date_value,
    coalesce(requires_cleaning_value, true),
    actor_id_value,
    jsonb_build_object(
      'room_number', room_row.room_number,
      'created_via', 'report_maintenance_task'
    )
  )
  returning *
  into task_row;

  perform private.day13_insert_maintenance_event(
    target_hotel_id,
    task_row.id,
    'reported',
    null,
    task_row.status,
    actor_id_value,
    request_key,
    jsonb_build_object(
      'room_id', target_room_id,
      'room_number', room_row.room_number,
      'severity', severity_value,
      'inventory_impact',
        inventory_impact_value
    )
  );

  if block_row.id is not null then
    perform private.day13_insert_maintenance_event(
      target_hotel_id,
      task_row.id,
      'room_block_created',
      task_row.status,
      task_row.status,
      actor_id_value,
      request_key || ':block',
      jsonb_build_object(
        'room_block_id', block_row.id,
        'block_type', block_row.block_type,
        'start_date', block_row.start_date,
        'end_date', block_row.end_date
      )
    );

    perform public.transition_room_status(
      target_hotel_id,
      target_room_id,
      inventory_impact_value,
      trim(title_value),
      'maintenance',
      request_key || ':room'
    );
  end if;

  select task.*
  into task_row
  from public.maintenance_tasks task
  where task.hotel_id = target_hotel_id
    and task.id = task_row.id;

  return jsonb_build_object(
    'ok', true,
    'idempotent', false,
    'task', to_jsonb(task_row),
    'room_block',
      case
        when block_row.id is null
          then null
        else to_jsonb(block_row)
      end
  );
end;
$function$;

-- ---------------------------------------------------------------------------
-- 6. Assign task
-- ---------------------------------------------------------------------------

create or replace function public.assign_maintenance_task(
  target_hotel_id uuid,
  target_task_id uuid,
  target_staff_id uuid,
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
  task_row public.maintenance_tasks%rowtype;
  staff_row public.staff%rowtype;
  existing_event uuid;
  previous_status_value text;
begin
  actor_id_value :=
    private.day13_require_maintenance_manager(
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
  into existing_event
  from public.maintenance_task_events event_record
  where event_record.hotel_id = target_hotel_id
    and event_record.request_id = request_key
    and event_record.event_type = 'assigned';

  if existing_event is not null then
    select task.*
    into task_row
    from public.maintenance_tasks task
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
      'Assigned maintenance staff is not active in this hotel.';
  end if;

  select task.*
  into task_row
  from public.maintenance_tasks task
  where task.hotel_id = target_hotel_id
    and task.id = target_task_id
  for update;

  if not found then
    raise exception 'Maintenance task was not found.';
  end if;

  if task_row.status not in (
    'reported',
    'assigned',
    'on_hold'
  ) then
    raise exception
      'Maintenance task cannot be assigned from status %.',
      task_row.status;
  end if;

  previous_status_value := task_row.status;

  update public.maintenance_tasks
  set
    assigned_staff_id = target_staff_id,
    status =
      case
        when status = 'reported'
          then 'assigned'
        else status
      end,
    assigned_at = now(),
    assigned_by = actor_id_value,
    due_at = coalesce(
      due_at_value,
      due_at
    ),
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

  perform private.day13_insert_maintenance_event(
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
-- 7. Start / hold / resume
-- ---------------------------------------------------------------------------

create or replace function public.start_maintenance_task(
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
  task_row public.maintenance_tasks%rowtype;
  previous_status_value text;
  existing_event uuid;
begin
  actor_id_value :=
    private.day13_require_maintenance_manager(
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
  into existing_event
  from public.maintenance_task_events event_record
  where event_record.hotel_id = target_hotel_id
    and event_record.request_id = request_key
    and event_record.event_type in (
      'started',
      'resumed'
    );

  if existing_event is not null then
    select task.*
    into task_row
    from public.maintenance_tasks task
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
  from public.maintenance_tasks task
  where task.hotel_id = target_hotel_id
    and task.id = target_task_id
  for update;

  if not found then
    raise exception 'Maintenance task was not found.';
  end if;

  if task_row.assigned_staff_id is null then
    raise exception
      'Maintenance task must be assigned before work starts.';
  end if;

  if task_row.status not in (
    'assigned',
    'on_hold'
  ) then
    raise exception
      'Maintenance task cannot start from status %.',
      task_row.status;
  end if;

  previous_status_value := task_row.status;

  update public.maintenance_tasks
  set
    status = 'in_progress',
    started_at = coalesce(started_at, now()),
    started_by = actor_id_value,
    held_at = null,
    hold_reason = null,
    updated_by = actor_id_value,
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

  perform private.day13_insert_maintenance_event(
    target_hotel_id,
    target_task_id,
    case
      when previous_status_value = 'on_hold'
        then 'resumed'
      else 'started'
    end,
    previous_status_value,
    task_row.status,
    actor_id_value,
    request_key,
    '{}'::jsonb
  );

  return jsonb_build_object(
    'ok', true,
    'idempotent', false,
    'task', to_jsonb(task_row)
  );
end;
$function$;

create or replace function public.hold_maintenance_task(
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
  task_row public.maintenance_tasks%rowtype;
  previous_status_value text;
  existing_event uuid;
begin
  actor_id_value :=
    private.day13_require_maintenance_manager(
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
    raise exception 'Hold reason is required.';
  end if;

  select event_record.id
  into existing_event
  from public.maintenance_task_events event_record
  where event_record.hotel_id = target_hotel_id
    and event_record.request_id = request_key
    and event_record.event_type = 'held';

  if existing_event is not null then
    select task.*
    into task_row
    from public.maintenance_tasks task
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
  from public.maintenance_tasks task
  where task.hotel_id = target_hotel_id
    and task.id = target_task_id
  for update;

  if not found then
    raise exception 'Maintenance task was not found.';
  end if;

  if task_row.status <> 'in_progress' then
    raise exception
      'Only an in-progress maintenance task can be put on hold.';
  end if;

  previous_status_value := task_row.status;

  update public.maintenance_tasks
  set
    status = 'on_hold',
    held_at = now(),
    hold_reason = trim(reason_value),
    updated_by = actor_id_value,
    metadata =
      metadata
      || jsonb_build_object(
        'hold_request_id',
        request_key
      )
  where hotel_id = target_hotel_id
    and id = target_task_id
  returning *
  into task_row;

  perform private.day13_insert_maintenance_event(
    target_hotel_id,
    target_task_id,
    'held',
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
-- 8. Resolve task
-- ---------------------------------------------------------------------------

create or replace function public.resolve_maintenance_task(
  target_hotel_id uuid,
  target_task_id uuid,
  resolution_notes_value text,
  requires_cleaning_value boolean,
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
  task_row public.maintenance_tasks%rowtype;
  previous_status_value text;
  existing_event uuid;
begin
  actor_id_value :=
    private.day13_require_maintenance_manager(
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

  if nullif(trim(resolution_notes_value), '') is null then
    raise exception 'Resolution notes are required.';
  end if;

  select event_record.id
  into existing_event
  from public.maintenance_task_events event_record
  where event_record.hotel_id = target_hotel_id
    and event_record.request_id = request_key
    and event_record.event_type = 'resolved';

  if existing_event is not null then
    select task.*
    into task_row
    from public.maintenance_tasks task
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
  from public.maintenance_tasks task
  where task.hotel_id = target_hotel_id
    and task.id = target_task_id
  for update;

  if not found then
    raise exception 'Maintenance task was not found.';
  end if;

  if task_row.status not in (
    'in_progress',
    'on_hold'
  ) then
    raise exception
      'Maintenance task can resolve only from in_progress or on_hold.';
  end if;

  previous_status_value := task_row.status;

  update public.maintenance_tasks
  set
    status = 'resolved',
    resolved_at = now(),
    resolved_by = actor_id_value,
    resolution_notes =
      trim(resolution_notes_value),
    requires_cleaning =
      coalesce(
        requires_cleaning_value,
        requires_cleaning
      ),
    updated_by = actor_id_value,
    metadata =
      metadata
      || jsonb_build_object(
        'resolve_request_id',
        request_key
      )
  where hotel_id = target_hotel_id
    and id = target_task_id
  returning *
  into task_row;

  perform private.day13_insert_maintenance_event(
    target_hotel_id,
    target_task_id,
    'resolved',
    previous_status_value,
    task_row.status,
    actor_id_value,
    request_key,
    jsonb_build_object(
      'requires_cleaning',
      task_row.requires_cleaning
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
-- 9. Verify task and restore/handoff room
-- ---------------------------------------------------------------------------

create or replace function public.verify_maintenance_task(
  target_hotel_id uuid,
  target_task_id uuid,
  verification_notes_value text,
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
  task_row public.maintenance_tasks%rowtype;
  room_row public.rooms%rowtype;
  block_row public.room_blocks%rowtype;
  verification_row public.maintenance_verifications%rowtype;
  housekeeping_result jsonb;
  housekeeping_task_id_value uuid;
  snapshot_value jsonb;
  previous_status_value text;
  commitments jsonb;
begin
  actor_id_value :=
    private.day13_require_maintenance_manager(
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

  select verification.*
  into verification_row
  from public.maintenance_verifications verification
  where verification.hotel_id = target_hotel_id
    and verification.request_id = request_key;

  if verification_row.id is not null then
    select task.*
    into task_row
    from public.maintenance_tasks task
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
      'room', to_jsonb(room_row),
      'verification',
        to_jsonb(verification_row)
    );
  end if;

  select task.*
  into task_row
  from public.maintenance_tasks task
  where task.hotel_id = target_hotel_id
    and task.id = target_task_id
  for update;

  if not found then
    raise exception 'Maintenance task was not found.';
  end if;

  if task_row.status <> 'resolved' then
    raise exception
      'Maintenance verification requires resolved status.';
  end if;

  select room.*
  into room_row
  from public.rooms room
  where room.hotel_id = target_hotel_id
    and room.id = task_row.room_id
  for update;

  if not found then
    raise exception 'Maintenance room was not found.';
  end if;

  if task_row.room_block_id is not null then
    select block_record.*
    into block_row
    from public.room_blocks block_record
    where block_record.hotel_id =
          target_hotel_id
      and block_record.id =
          task_row.room_block_id
    for update;

    if block_row.id is null then
      raise exception
        'Linked maintenance room block was not found.';
    end if;

    if block_row.status = 'active' then
      update public.room_blocks
      set
        status = 'released',
        released_at = now(),
        released_by = actor_id_value,
        release_reason =
          coalesce(
            nullif(
              trim(verification_notes_value),
              ''
            ),
            'Maintenance verified'
          ),
        updated_by = actor_id_value
      where hotel_id = target_hotel_id
        and id = task_row.room_block_id
      returning *
      into block_row;

      perform private.day13_insert_maintenance_event(
        target_hotel_id,
        target_task_id,
        'room_block_released',
        task_row.status,
        task_row.status,
        actor_id_value,
        request_key || ':block',
        jsonb_build_object(
          'room_block_id', block_row.id,
          'release_reason',
            block_row.release_reason
        )
      );
    end if;
  end if;

  if task_row.inventory_impact <> 'none' then
    if task_row.requires_cleaning then
      perform public.transition_room_status(
        target_hotel_id,
        task_row.room_id,
        'cleaning',
        'Maintenance verified; housekeeping required',
        'maintenance',
        request_key || ':room-cleaning'
      );

      select task.id
      into housekeeping_task_id_value
      from public.housekeeping_tasks task
      where task.hotel_id = target_hotel_id
        and task.room_id = task_row.room_id
        and task.task_type = 'room_cleaning'
        and task.status in (
          'pending',
          'assigned',
          'in_progress',
          'cleaning_complete',
          'inspection_failed',
          'inspected'
        )
      order by task.created_at desc
      limit 1;

      if housekeeping_task_id_value is null then
        housekeeping_result :=
          public.create_housekeeping_task(
            target_hotel_id,
            task_row.room_id,
            'room_cleaning',
            case
              when task_row.severity in (
                'critical',
                'high'
              ) then 'high'
              else 'normal'
            end,
            now() + interval '2 hours',
            'Cleaning after maintenance: '
              || task_row.task_number,
            'maintenance',
            null,
            request_key || ':housekeeping'
          );

        housekeeping_task_id_value :=
          (
            housekeeping_result
            #>> '{task,id}'
          )::uuid;
      end if;

      perform private.day13_insert_maintenance_event(
        target_hotel_id,
        target_task_id,
        'housekeeping_handoff',
        task_row.status,
        task_row.status,
        actor_id_value,
        request_key || ':housekeeping-event',
        jsonb_build_object(
          'housekeeping_task_id',
          housekeeping_task_id_value
        )
      );
    else
      commitments :=
        private.day13_room_commitments(
          target_hotel_id,
          task_row.room_id
        );

      if (
        commitments
        ->> 'active_stays'
      )::integer > 0
      or (
        commitments
        ->> 'active_blocks'
      )::integer > 0
      or (
        commitments
        ->> 'pending_housekeeping'
      )::integer > 0
      then
        raise exception
          'Room cannot return to service while active stay, block or housekeeping work remains.';
      end if;

      perform public.transition_room_status(
        target_hotel_id,
        task_row.room_id,
        case
          when task_row.previous_room_status in (
            'available',
            'cleaning'
          ) then task_row.previous_room_status
          else 'available'
        end,
        'Maintenance verified',
        'maintenance',
        request_key || ':room-ready'
      );
    end if;
  end if;

  snapshot_value :=
    jsonb_build_object(
      'task_id', task_row.id,
      'task_number', task_row.task_number,
      'room_id', task_row.room_id,
      'room_number',
        room_row.room_number,
      'title', task_row.title,
      'category', task_row.category,
      'severity', task_row.severity,
      'inventory_impact',
        task_row.inventory_impact,
      'previous_room_status',
        task_row.previous_room_status,
      'room_block_id',
        task_row.room_block_id,
      'resolution_notes',
        task_row.resolution_notes,
      'requires_cleaning',
        task_row.requires_cleaning,
      'housekeeping_task_id',
        housekeeping_task_id_value,
      'verification_notes',
        nullif(
          trim(verification_notes_value),
          ''
        )
    );

  insert into public.maintenance_verifications (
    hotel_id,
    task_id,
    outcome,
    notes,
    verified_by,
    request_id,
    snapshot_json,
    snapshot_hash
  )
  values (
    target_hotel_id,
    target_task_id,
    'verified',
    nullif(
      trim(verification_notes_value),
      ''
    ),
    actor_id_value,
    request_key,
    snapshot_value,
    private.day13_hash_json(
      snapshot_value
    )
  )
  returning *
  into verification_row;

  previous_status_value := task_row.status;

  update public.maintenance_tasks
  set
    status = 'verified',
    verified_at = now(),
    verified_by = actor_id_value,
    verification_notes =
      nullif(
        trim(verification_notes_value),
        ''
      ),
    housekeeping_task_id =
      housekeeping_task_id_value,
    updated_by = actor_id_value,
    metadata =
      metadata
      || jsonb_build_object(
        'verification_request_id',
        request_key,
        'verification_id',
        verification_row.id
      )
  where hotel_id = target_hotel_id
    and id = target_task_id
  returning *
  into task_row;

  select room.*
  into room_row
  from public.rooms room
  where room.hotel_id = target_hotel_id
    and room.id = task_row.room_id;

  perform private.day13_insert_maintenance_event(
    target_hotel_id,
    target_task_id,
    'verified',
    previous_status_value,
    task_row.status,
    actor_id_value,
    request_key,
    jsonb_build_object(
      'verification_id',
        verification_row.id,
      'snapshot_hash',
        verification_row.snapshot_hash,
      'room_status',
        room_row.status,
      'housekeeping_task_id',
        housekeeping_task_id_value
    )
  );

  return jsonb_build_object(
    'ok', true,
    'idempotent', false,
    'task', to_jsonb(task_row),
    'room', to_jsonb(room_row),
    'room_block',
      case
        when block_row.id is null
          then null
        else to_jsonb(block_row)
      end,
    'verification',
      to_jsonb(verification_row),
    'housekeeping_task_id',
      housekeeping_task_id_value
  );
end;
$function$;

-- ---------------------------------------------------------------------------
-- 10. Cancel task
-- ---------------------------------------------------------------------------

create or replace function public.cancel_maintenance_task(
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
  task_row public.maintenance_tasks%rowtype;
  room_row public.rooms%rowtype;
  block_row public.room_blocks%rowtype;
  previous_status_value text;
  commitments jsonb;
  existing_event uuid;
begin
  actor_id_value :=
    private.day13_require_maintenance_manager(
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
  into existing_event
  from public.maintenance_task_events event_record
  where event_record.hotel_id = target_hotel_id
    and event_record.request_id = request_key
    and event_record.event_type = 'cancelled';

  if existing_event is not null then
    select task.*
    into task_row
    from public.maintenance_tasks task
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
  from public.maintenance_tasks task
  where task.hotel_id = target_hotel_id
    and task.id = target_task_id
  for update;

  if not found then
    raise exception 'Maintenance task was not found.';
  end if;

  if task_row.status in (
    'resolved',
    'verified',
    'cancelled'
  ) then
    raise exception
      'Maintenance task cannot be cancelled from status %.',
      task_row.status;
  end if;

  if task_row.room_block_id is not null then
    update public.room_blocks
    set
      status = 'cancelled',
      released_at = now(),
      released_by = actor_id_value,
      release_reason = trim(reason_value),
      updated_by = actor_id_value
    where hotel_id = target_hotel_id
      and id = task_row.room_block_id
      and status = 'active'
    returning *
    into block_row;
  end if;

  if task_row.inventory_impact <> 'none' then
    commitments :=
      private.day13_room_commitments(
        target_hotel_id,
        task_row.room_id
      );

    if (
      commitments
      ->> 'active_stays'
    )::integer = 0
    and (
      commitments
      ->> 'active_blocks'
    )::integer = 0
    and (
      commitments
      ->> 'pending_housekeeping'
    )::integer = 0
    then
      perform public.transition_room_status(
        target_hotel_id,
        task_row.room_id,
        case
          when task_row.previous_room_status in (
            'available',
            'cleaning'
          ) then task_row.previous_room_status
          else 'available'
        end,
        'Maintenance task cancelled',
        'maintenance',
        request_key || ':room'
      );
    end if;
  end if;

  previous_status_value := task_row.status;

  update public.maintenance_tasks
  set
    status = 'cancelled',
    cancelled_at = now(),
    cancelled_by = actor_id_value,
    cancellation_reason =
      trim(reason_value),
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

  perform private.day13_insert_maintenance_event(
    target_hotel_id,
    target_task_id,
    'cancelled',
    previous_status_value,
    task_row.status,
    actor_id_value,
    request_key,
    jsonb_build_object(
      'reason', trim(reason_value),
      'room_block_id', block_row.id
    )
  );

  select room.*
  into room_row
  from public.rooms room
  where room.hotel_id = target_hotel_id
    and room.id = task_row.room_id;

  return jsonb_build_object(
    'ok', true,
    'idempotent', false,
    'task', to_jsonb(task_row),
    'room', to_jsonb(room_row),
    'room_block',
      case
        when block_row.id is null
          then null
        else to_jsonb(block_row)
      end
  );
end;
$function$;

-- ---------------------------------------------------------------------------
-- 11. Workspace and mobile queue
-- ---------------------------------------------------------------------------

create or replace function public.get_maintenance_workspace(
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
      'rooms.view',
      'rooms.manage',
      'housekeeping.view',
      'housekeeping.manage',
      'hotel.manage'
    ]::text[]
  ) then
    raise exception
      'Maintenance workspace access denied.';
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
                  'room_number',
                    room.room_number,
                  'status', room.status,
                  'floor_id', room.floor_id,
                  'room_type_id',
                    room.room_type_id
                ),
              'staff',
                case
                  when staff.id is null
                    then null
                  else jsonb_build_object(
                    'id', staff.id,
                    'full_name',
                      staff.full_name,
                    'role', staff.role,
                    'status', staff.status
                  )
                end,
              'room_block',
                case
                  when block_record.id is null
                    then null
                  else to_jsonb(block_record)
                end,
              'latest_verification',
                (
                  select to_jsonb(verification)
                  from public.maintenance_verifications verification
                  where verification.hotel_id =
                        task.hotel_id
                    and verification.task_id =
                        task.id
                  order by
                    verification.verified_at desc
                  limit 1
                )
            )
            order by
              case task.severity
                when 'critical' then 1
                when 'high' then 2
                when 'medium' then 3
                else 4
              end,
              task.due_at nulls last,
              task.created_at
          )
          from public.maintenance_tasks task
          join public.rooms room
            on room.hotel_id = task.hotel_id
           and room.id = task.room_id
          left join public.staff staff
            on staff.hotel_id = task.hotel_id
           and staff.id = task.assigned_staff_id
          left join public.room_blocks block_record
            on block_record.hotel_id =
               task.hotel_id
           and block_record.id =
               task.room_block_id
          where task.hotel_id =
                target_hotel_id
        ),
        '[]'::jsonb
      ),
    'workload',
      coalesce(
        (
          select jsonb_agg(
            workload_row
            order by
              workload_row
              ->> 'staff_name'
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
                    'on_hold',
                    'resolved'
                  )
                ),
              'critical_tasks',
                count(task.id) filter (
                  where task.severity =
                        'critical'
                    and task.status in (
                      'assigned',
                      'in_progress',
                      'on_hold',
                      'resolved'
                    )
                ),
              'in_progress_tasks',
                count(task.id) filter (
                  where task.status =
                        'in_progress'
                )
            ) workload_row
            from public.staff staff
            left join public.maintenance_tasks task
              on task.hotel_id =
                 staff.hotel_id
             and task.assigned_staff_id =
                 staff.id
            where staff.hotel_id =
                  target_hotel_id
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
        from public.maintenance_tasks task
        where task.hotel_id =
              target_hotel_id
          and task.assigned_staff_id is null
          and task.status = 'reported'
      ),
    'offline_rooms',
      (
        select count(distinct task.room_id)
        from public.maintenance_tasks task
        where task.hotel_id =
              target_hotel_id
          and task.inventory_impact <>
              'none'
          and task.status in (
            'reported',
            'assigned',
            'in_progress',
            'on_hold',
            'resolved'
          )
      ),
    'active_room_blocks',
      (
        select count(*)
        from public.room_blocks block_record
        where block_record.hotel_id =
              target_hotel_id
          and block_record.status = 'active'
          and block_record.block_type in (
            'maintenance',
            'out_of_order'
          )
      )
  );
end;
$function$;

create or replace function public.get_maintenance_mobile_queue(
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
      'rooms.view',
      'rooms.manage',
      'housekeeping.view',
      'housekeeping.manage',
      'hotel.manage'
    ]::text[]
  ) then
    raise exception
      'Maintenance mobile access denied.';
  end if;

  return coalesce(
    (
      select jsonb_agg(
        jsonb_build_object(
          'task_id', task.id,
          'task_number', task.task_number,
          'room_id', task.room_id,
          'room_number', room.room_number,
          'room_status', room.status,
          'title', task.title,
          'category', task.category,
          'severity', task.severity,
          'status', task.status,
          'inventory_impact',
            task.inventory_impact,
          'due_at', task.due_at,
          'expected_return_date',
            task.expected_return_date,
          'assigned_staff_id',
            task.assigned_staff_id
        )
        order by
          case task.severity
            when 'critical' then 1
            when 'high' then 2
            when 'medium' then 3
            else 4
          end,
          task.due_at nulls last,
          task.created_at
      )
      from public.maintenance_tasks task
      join public.rooms room
        on room.hotel_id = task.hotel_id
       and room.id = task.room_id
      where task.hotel_id =
            target_hotel_id
        and task.status in (
          'reported',
          'assigned',
          'in_progress',
          'on_hold',
          'resolved'
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
-- 12. Housekeeping source extension
-- ---------------------------------------------------------------------------

alter table public.housekeeping_tasks
  drop constraint housekeeping_tasks_source_check;

alter table public.housekeeping_tasks
  add constraint housekeeping_tasks_source_check
    check (
      source_type in (
        'legacy',
        'manual',
        'checkout',
        'room_move',
        'inspection_rework',
        'maintenance'
      )
    );

-- ---------------------------------------------------------------------------
-- 13. RPC-only privilege boundary
-- ---------------------------------------------------------------------------

revoke all
on public.maintenance_tasks,
   public.maintenance_task_events,
   public.maintenance_verifications
from public, anon, authenticated;

grant select
on public.maintenance_tasks,
   public.maintenance_task_events,
   public.maintenance_verifications
to authenticated;

grant all
on public.maintenance_tasks,
   public.maintenance_task_events,
   public.maintenance_verifications
to service_role;

revoke all
on function private.day13_require_maintenance_manager(uuid)
from public, anon, authenticated;

revoke all
on function private.day13_maintenance_task_number(uuid)
from public, anon, authenticated;

revoke all
on function private.day13_insert_maintenance_event(
  uuid,uuid,text,text,text,uuid,text,jsonb
)
from public, anon, authenticated;

grant execute
on function private.day13_require_maintenance_manager(uuid)
to service_role;

grant execute
on function private.day13_maintenance_task_number(uuid)
to service_role;

grant execute
on function private.day13_insert_maintenance_event(
  uuid,uuid,text,text,text,uuid,text,jsonb
)
to service_role;

revoke all
on function public.report_maintenance_task(
  uuid,uuid,text,text,text,text,text,date,timestamptz,boolean,text
)
from public, anon;

revoke all
on function public.assign_maintenance_task(
  uuid,uuid,uuid,timestamptz,text
)
from public, anon;

revoke all
on function public.start_maintenance_task(
  uuid,uuid,text
)
from public, anon;

revoke all
on function public.hold_maintenance_task(
  uuid,uuid,text,text
)
from public, anon;

revoke all
on function public.resolve_maintenance_task(
  uuid,uuid,text,boolean,text
)
from public, anon;

revoke all
on function public.verify_maintenance_task(
  uuid,uuid,text,text
)
from public, anon;

revoke all
on function public.cancel_maintenance_task(
  uuid,uuid,text,text
)
from public, anon;

revoke all
on function public.get_maintenance_workspace(uuid)
from public, anon;

revoke all
on function public.get_maintenance_mobile_queue(uuid,uuid)
from public, anon;

grant execute
on function public.report_maintenance_task(
  uuid,uuid,text,text,text,text,text,date,timestamptz,boolean,text
)
to authenticated, service_role;

grant execute
on function public.assign_maintenance_task(
  uuid,uuid,uuid,timestamptz,text
)
to authenticated, service_role;

grant execute
on function public.start_maintenance_task(
  uuid,uuid,text
)
to authenticated, service_role;

grant execute
on function public.hold_maintenance_task(
  uuid,uuid,text,text
)
to authenticated, service_role;

grant execute
on function public.resolve_maintenance_task(
  uuid,uuid,text,boolean,text
)
to authenticated, service_role;

grant execute
on function public.verify_maintenance_task(
  uuid,uuid,text,text
)
to authenticated, service_role;

grant execute
on function public.cancel_maintenance_task(
  uuid,uuid,text,text
)
to authenticated, service_role;

grant execute
on function public.get_maintenance_workspace(uuid)
to authenticated, service_role;

grant execute
on function public.get_maintenance_mobile_queue(uuid,uuid)
to authenticated, service_role;

comment on table public.maintenance_tasks is
'Auditable Day 13 room maintenance lifecycle with explicit inventory impact and housekeeping handoff.';

comment on table public.maintenance_verifications is
'Immutable maintenance verification snapshots protected by SHA-256.';

comment on function public.report_maintenance_task(
  uuid,uuid,text,text,text,text,text,date,timestamptz,boolean,text
) is
'Reports maintenance and explicitly applies none, maintenance or out-of-order inventory impact.';

comment on function public.verify_maintenance_task(
  uuid,uuid,text,text
) is
'Releases maintenance room block and either creates a housekeeping handoff or safely restores room service.';

commit;
