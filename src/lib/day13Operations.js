import { supabase } from './supabase'

function requireValue(value, label) {
  if (value === null || value === undefined || value === '') {
    throw new Error(`${label} is required.`)
  }

  return value
}

async function callRpc(name, args) {
  const { data, error } = await supabase.rpc(name, args)

  if (error) {
    throw new Error(error.message || `StayQR could not run ${name}.`)
  }

  return data
}

export function createDay13RequestId(prefix = 'day13') {
  const uuid = globalThis.crypto?.randomUUID?.()
  return `${prefix}-${uuid || `${Date.now()}-${Math.random().toString(16).slice(2)}`}`
}

export async function loadActiveHotelStaff(hotelId) {
  requireValue(hotelId, 'Hotel')

  const { data, error } = await supabase
    .from('staff')
    .select('id, full_name, role, status, disabled_at, auth_user_id')
    .eq('hotel_id', hotelId)
    .eq('status', 'active')
    .is('disabled_at', null)
    .order('full_name', { ascending: true })

  if (error) throw new Error(error.message)

  return data || []
}

export function getRoomInventoryWorkspace(hotelId) {
  return callRpc('get_room_inventory_workspace', { h: requireValue(hotelId, 'Hotel') })
}

export function saveFloor(hotelId, floor) {
  return callRpc('upsert_floor', {
    h: requireValue(hotelId, 'Hotel'),
    floor_id_value: floor.id || null,
    code_value: floor.code,
    name_value: floor.name,
    floor_number_value:
      floor.floor_number === '' || floor.floor_number === null
        ? null
        : Number(floor.floor_number),
    description_value: floor.description || null,
    sort_order_value: Number(floor.sort_order || 0),
    active_value: true,
    request_id_value: floor.requestId || createDay13RequestId('floor'),
  })
}

export function archiveFloor(hotelId, floorId, reason) {
  return callRpc('archive_floor', {
    h: requireValue(hotelId, 'Hotel'),
    floor_id_value: requireValue(floorId, 'Floor'),
    reason_value: requireValue(reason?.trim(), 'Archive reason'),
    request_id_value: createDay13RequestId('archive-floor'),
  })
}

export function saveRoomType(hotelId, roomType) {
  return callRpc('upsert_room_type', {
    h: requireValue(hotelId, 'Hotel'),
    type_id_value: roomType.id || null,
    code_value: roomType.code,
    name_value: roomType.name,
    description_value: roomType.description || null,
    base_occupancy_value: Number(roomType.base_occupancy || 1),
    max_adults_value: Number(roomType.max_adults || 2),
    max_children_value: Number(roomType.max_children || 0),
    max_occupancy_value: Number(roomType.max_occupancy || 2),
    base_rate_value: Number(roomType.base_rate || 0),
    extra_adult_rate_value: Number(roomType.extra_adult_rate || 0),
    extra_child_rate_value: Number(roomType.extra_child_rate || 0),
    sort_order_value: Number(roomType.sort_order || 0),
    active_value: true,
    request_id_value: roomType.requestId || createDay13RequestId('room-type'),
  })
}

export function archiveRoomType(hotelId, roomTypeId, reason) {
  return callRpc('archive_room_type', {
    h: requireValue(hotelId, 'Hotel'),
    type_id_value: requireValue(roomTypeId, 'Room type'),
    reason_value: requireValue(reason?.trim(), 'Archive reason'),
    request_id_value: createDay13RequestId('archive-room-type'),
  })
}

export function saveRoom(hotelId, room) {
  return callRpc('upsert_room', {
    h: requireValue(hotelId, 'Hotel'),
    room_id_value: room.id || null,
    room_number_value: room.room_number,
    floor_id_value: requireValue(room.floor_id, 'Floor'),
    type_id_value: requireValue(room.room_type_id, 'Room type'),
    initial_status_value: room.status || 'available',
    metadata_value: room.metadata || {},
    request_id_value: room.requestId || createDay13RequestId('room'),
  })
}

export function transitionRoomStatus(hotelId, roomId, status, reason, source = 'room_ui') {
  return callRpc('transition_room_status', {
    h: requireValue(hotelId, 'Hotel'),
    room_id_value: requireValue(roomId, 'Room'),
    new_status_value: requireValue(status, 'Status'),
    reason_value: requireValue(reason?.trim(), 'Status reason'),
    source_value: source,
    request_id_value: createDay13RequestId('room-status'),
  })
}

export function archiveRoom(hotelId, roomId, reason) {
  return callRpc('archive_room', {
    h: requireValue(hotelId, 'Hotel'),
    room_id_value: requireValue(roomId, 'Room'),
    reason_value: requireValue(reason?.trim(), 'Archive reason'),
    request_id_value: createDay13RequestId('archive-room'),
  })
}

export function importRooms(hotelId, rows, sourceName = 'Browser CSV import') {
  return callRpc('import_rooms', {
    h: requireValue(hotelId, 'Hotel'),
    rows_value: rows,
    source_name_value: sourceName,
    request_id_value: createDay13RequestId('room-import'),
  })
}

export function getHousekeepingWorkspace(hotelId) {
  return callRpc('get_housekeeping_workspace', {
    target_hotel_id: requireValue(hotelId, 'Hotel'),
  })
}

export function getHousekeepingMobileQueue(hotelId, staffId = null) {
  return callRpc('get_housekeeping_mobile_queue', {
    target_hotel_id: requireValue(hotelId, 'Hotel'),
    target_staff_id: staffId || null,
  })
}

export function createHousekeepingTask(hotelId, values) {
  return callRpc('create_housekeeping_task', {
    target_hotel_id: requireValue(hotelId, 'Hotel'),
    target_room_id: requireValue(values.roomId, 'Room'),
    task_type_value: values.taskType || 'room_cleaning',
    priority_value: values.priority || 'normal',
    due_at_value: values.dueAt || null,
    notes_value: values.notes || null,
    source_type_value: values.sourceType || 'manual',
    source_guest_session_id_value: values.guestSessionId || null,
    request_id_value: createDay13RequestId('housekeeping-create'),
  })
}

export function assignHousekeepingTask(hotelId, taskId, staffId, priority, dueAt) {
  return callRpc('assign_housekeeping_task', {
    target_hotel_id: requireValue(hotelId, 'Hotel'),
    target_task_id: requireValue(taskId, 'Task'),
    target_staff_id: requireValue(staffId, 'Staff'),
    priority_value: priority || 'normal',
    due_at_value: dueAt || null,
    request_id_value: createDay13RequestId('housekeeping-assign'),
  })
}

export function startHousekeepingTask(hotelId, taskId) {
  return callRpc('start_housekeeping_task', {
    target_hotel_id: requireValue(hotelId, 'Hotel'),
    target_task_id: requireValue(taskId, 'Task'),
    request_id_value: createDay13RequestId('housekeeping-start'),
  })
}

export function updateHousekeepingChecklistItem(
  hotelId,
  taskId,
  itemId,
  status,
  notes = ''
) {
  return callRpc('update_housekeeping_checklist_item', {
    target_hotel_id: requireValue(hotelId, 'Hotel'),
    target_task_id: requireValue(taskId, 'Task'),
    target_item_id: requireValue(itemId, 'Checklist item'),
    item_status_value: status,
    notes_value: notes || null,
    request_id_value: createDay13RequestId('housekeeping-item'),
  })
}

export function completeHousekeepingCleaning(hotelId, taskId, notes = '') {
  return callRpc('complete_housekeeping_cleaning', {
    target_hotel_id: requireValue(hotelId, 'Hotel'),
    target_task_id: requireValue(taskId, 'Task'),
    notes_value: notes || null,
    request_id_value: createDay13RequestId('housekeeping-complete'),
  })
}

export function inspectHousekeepingTask(hotelId, taskId, result, notes = '') {
  return callRpc('inspect_housekeeping_task', {
    target_hotel_id: requireValue(hotelId, 'Hotel'),
    target_task_id: requireValue(taskId, 'Task'),
    result_value: result,
    notes_value: notes || null,
    request_id_value: createDay13RequestId('housekeeping-inspect'),
  })
}

export function approveHousekeepingRoomReady(hotelId, taskId, notes = '') {
  return callRpc('approve_housekeeping_room_ready', {
    target_hotel_id: requireValue(hotelId, 'Hotel'),
    target_task_id: requireValue(taskId, 'Task'),
    notes_value: notes || null,
    request_id_value: createDay13RequestId('housekeeping-ready'),
  })
}

export function cancelHousekeepingTask(hotelId, taskId, reason) {
  return callRpc('cancel_housekeeping_task', {
    target_hotel_id: requireValue(hotelId, 'Hotel'),
    target_task_id: requireValue(taskId, 'Task'),
    reason_value: requireValue(reason?.trim(), 'Cancellation reason'),
    request_id_value: createDay13RequestId('housekeeping-cancel'),
  })
}

export function getMaintenanceWorkspace(hotelId) {
  return callRpc('get_maintenance_workspace', {
    target_hotel_id: requireValue(hotelId, 'Hotel'),
  })
}

export function getMaintenanceMobileQueue(hotelId, staffId = null) {
  return callRpc('get_maintenance_mobile_queue', {
    target_hotel_id: requireValue(hotelId, 'Hotel'),
    target_staff_id: staffId || null,
  })
}

export function reportMaintenanceTask(hotelId, values) {
  return callRpc('report_maintenance_task', {
    target_hotel_id: requireValue(hotelId, 'Hotel'),
    target_room_id: requireValue(values.roomId, 'Room'),
    title_value: requireValue(values.title?.trim(), 'Title'),
    description_value: values.description || null,
    category_value: values.category || 'other',
    severity_value: values.severity || 'medium',
    inventory_impact_value: values.inventoryImpact || 'none',
    expected_return_date_value: values.expectedReturnDate || null,
    due_at_value: values.dueAt || null,
    requires_cleaning_value: values.requiresCleaning !== false,
    request_id_value: createDay13RequestId('maintenance-report'),
  })
}

export function assignMaintenanceTask(hotelId, taskId, staffId, dueAt = null) {
  return callRpc('assign_maintenance_task', {
    target_hotel_id: requireValue(hotelId, 'Hotel'),
    target_task_id: requireValue(taskId, 'Task'),
    target_staff_id: requireValue(staffId, 'Staff'),
    due_at_value: dueAt || null,
    request_id_value: createDay13RequestId('maintenance-assign'),
  })
}

export function startMaintenanceTask(hotelId, taskId) {
  return callRpc('start_maintenance_task', {
    target_hotel_id: requireValue(hotelId, 'Hotel'),
    target_task_id: requireValue(taskId, 'Task'),
    request_id_value: createDay13RequestId('maintenance-start'),
  })
}

export function holdMaintenanceTask(hotelId, taskId, reason) {
  return callRpc('hold_maintenance_task', {
    target_hotel_id: requireValue(hotelId, 'Hotel'),
    target_task_id: requireValue(taskId, 'Task'),
    reason_value: requireValue(reason?.trim(), 'Hold reason'),
    request_id_value: createDay13RequestId('maintenance-hold'),
  })
}

export function resolveMaintenanceTask(hotelId, taskId, notes, requiresCleaning) {
  return callRpc('resolve_maintenance_task', {
    target_hotel_id: requireValue(hotelId, 'Hotel'),
    target_task_id: requireValue(taskId, 'Task'),
    resolution_notes_value: requireValue(notes?.trim(), 'Resolution notes'),
    requires_cleaning_value: requiresCleaning !== false,
    request_id_value: createDay13RequestId('maintenance-resolve'),
  })
}

export function verifyMaintenanceTask(hotelId, taskId, notes = '') {
  return callRpc('verify_maintenance_task', {
    target_hotel_id: requireValue(hotelId, 'Hotel'),
    target_task_id: requireValue(taskId, 'Task'),
    verification_notes_value: notes || null,
    request_id_value: createDay13RequestId('maintenance-verify'),
  })
}

export function cancelMaintenanceTask(hotelId, taskId, reason) {
  return callRpc('cancel_maintenance_task', {
    target_hotel_id: requireValue(hotelId, 'Hotel'),
    target_task_id: requireValue(taskId, 'Task'),
    reason_value: requireValue(reason?.trim(), 'Cancellation reason'),
    request_id_value: createDay13RequestId('maintenance-cancel'),
  })
}
