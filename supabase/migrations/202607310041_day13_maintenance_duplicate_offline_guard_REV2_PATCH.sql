-- ============================================================================
-- StayQR v1.0
-- Day 13 Migration 041 REV2 PATCH
-- Controlled duplicate offline-maintenance guard
--
-- REQUIRES
-- --------
-- Migration 041 REV1 foundation installed successfully.
-- Migration 041 REV1 structural acceptance passed 70/70.
--
-- WHY THIS PATCH EXISTS
-- ---------------------
-- The REV1 runtime intentionally attempted a second offline-maintenance task
-- for the same room. The authoritative room-allocation exclusion constraint
-- correctly rejected it with SQLSTATE 23P01 before the maintenance-task unique
-- index was reached.
--
-- REV2 hardens the RPC by checking for an existing active offline-maintenance
-- lifecycle while the room row is already locked FOR UPDATE. It returns a
-- controlled application error before attempting a second room block.
--
-- No production data is updated.
-- ============================================================================

begin;

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

  if inventory_impact_value <> 'none'
     and exists (
       select 1
       from public.maintenance_tasks existing_task
       where existing_task.hotel_id = target_hotel_id
         and existing_task.room_id = target_room_id
         and existing_task.inventory_impact <> 'none'
         and existing_task.status in (
           'reported',
           'assigned',
           'in_progress',
           'on_hold',
           'resolved'
         )
     )
  then
    raise exception
      'Room already has an active offline maintenance task.';
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


comment on function public.report_maintenance_task(
  uuid,uuid,text,text,text,text,text,date,timestamptz,boolean,text
) is
'Reports maintenance with explicit inventory impact and rejects a second active offline-maintenance lifecycle before room-block allocation.';

commit;
