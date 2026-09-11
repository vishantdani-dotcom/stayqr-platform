import { normalizeRole } from './currentStaff'
import { getNotificationCategory } from './notificationPresentation'
import { supabase } from './supabase'

const HOUSEKEEPING_ROLES = new Set(['housekeeping', 'housekeeper'])
const KITCHEN_ROLES = new Set(['restaurant', 'kitchen', 'chef'])
const ACCOUNTS_ROLES = new Set(['accounts', 'accounting'])
const DASHBOARD_ROLES = new Set([
  'owner',
  'manager',
  'reception',
  'front_desk',
  'frontdesk',
  'hotel_admin',
  'admin',
  'platform_admin',
  'super_admin',
  'platform_support',
])

const SERVICE_DEPARTMENTS_BY_ROLE = Object.freeze({
  housekeeping: new Set(['housekeeping', 'maintenance', 'laundry']),
  housekeeper: new Set(['housekeeping', 'maintenance', 'laundry']),
  restaurant: new Set(['restaurant']),
  kitchen: new Set(['restaurant']),
  chef: new Set(['restaurant']),
  accounts: new Set(['accounts']),
  accounting: new Set(['accounts']),
  owner: new Set(['front_office', 'guest_services', 'management', 'transport']),
  manager: new Set(['front_office', 'guest_services', 'management', 'transport']),
  reception: new Set(['front_office', 'guest_services', 'transport']),
  front_desk: new Set(['front_office', 'guest_services', 'transport']),
  frontdesk: new Set(['front_office', 'guest_services', 'transport']),
  hotel_admin: new Set(['front_office', 'guest_services', 'management', 'transport']),
  admin: new Set(['front_office', 'guest_services', 'management', 'transport']),
  platform_admin: new Set(['front_office', 'guest_services', 'management', 'transport']),
  super_admin: new Set(['front_office', 'guest_services', 'management', 'transport']),
  platform_support: new Set(['front_office', 'guest_services', 'management', 'transport']),
})

export function getAccountNotificationSoundKey(role) {
  const normalized = normalizeRole(role)

  if (HOUSEKEEPING_ROLES.has(normalized)) return 'housekeeping'
  if (KITCHEN_ROLES.has(normalized)) return 'kitchen'
  return 'dashboard'
}

export function isDashboardNotificationRole(role) {
  return DASHBOARD_ROLES.has(normalizeRole(role))
}

export function isLocalDepartmentNotification(notification) {
  return Boolean(notification?.metadata?.local_department_event)
}

export function isServiceRequestForRole(request, role) {
  const normalized = normalizeRole(role)
  const department = String(request?.department || '').trim().toLowerCase()
  const allowed = SERVICE_DEPARTMENTS_BY_ROLE[normalized] || new Set()

  return Boolean(department && allowed.has(department))
}

export function createServiceRequestNotification(request) {
  const requestId = String(request?.id || '')
  const requestType = String(request?.request_type || 'Guest service request').trim()
  const details = String(request?.request_details || '').trim()
  const department = String(request?.department || '').trim().toLowerCase()

  return {
    id: `local-service-request:${requestId}`,
    outbox_id: null,
    event_key: 'service_request.created',
    source_type: 'service_request',
    source_id: requestId,
    title: requestType || 'Guest service request',
    message: details || 'A new guest service request was received.',
    severity: 'info',
    status: 'unread',
    business_date: null,
    read_at: null,
    created_at: request?.created_at || new Date().toISOString(),
    metadata: {
      local_department_event: true,
      department,
      guest_id: request?.guest_id || null,
      room_id: request?.room_id || null,
    },
  }
}

export function createKitchenOrderNotification(order) {
  const orderId = String(order?.id || '')
  const roomLabel = order?.room_number || order?.rooms?.room_number || ''

  return {
    id: `local-food-order:${orderId}`,
    outbox_id: null,
    event_key: 'food_order.created',
    source_type: 'food_order',
    source_id: orderId,
    title: 'New food order',
    message: roomLabel
      ? `New guest food order from Room ${roomLabel}.`
      : 'A new guest food order was placed.',
    severity: 'info',
    status: 'unread',
    business_date: null,
    read_at: null,
    created_at: order?.created_at || new Date().toISOString(),
    metadata: {
      local_department_event: true,
      department: 'restaurant',
      guest_session_id: order?.guest_session_id || null,
      room_id: order?.room_id || null,
    },
  }
}

function sourceIdentity(item) {
  const sourceType = String(item?.source_type || '')
    .trim()
    .toLowerCase()
  const sourceId = String(item?.source_id || '').trim()
  const eventKey = String(item?.event_key || '')
    .trim()
    .toLowerCase()

  if (!sourceType || !sourceId) return ''

  return eventKey
    ? `${sourceType}:${sourceId}:${eventKey}`
    : `${sourceType}:${sourceId}`
}

export function mergeNotificationItems(serverItems = [], currentItems = []) {
  const localItems = currentItems.filter(isLocalDepartmentNotification)
  const serverById = new Map()
  const serverSourceKeys = new Set()

  for (const item of serverItems) {
    if (!item?.id || serverById.has(item.id)) continue

    serverById.set(item.id, item)

    const key = sourceIdentity(item)
    if (key) serverSourceKeys.add(key)
  }

  const localById = new Map()

  for (const item of localItems) {
    if (!item?.id) continue

    const key = sourceIdentity(item)
    if (key && serverSourceKeys.has(key)) continue

    if (!localById.has(item.id)) {
      localById.set(item.id, item)
    }
  }

  return [...localById.values(), ...serverById.values()]
    .sort(
      (a, b) =>
        new Date(b?.created_at || 0).getTime() -
        new Date(a?.created_at || 0).getTime()
    )
    .slice(0, 30)
}

function serviceDepartmentsForRole(role) {
  return SERVICE_DEPARTMENTS_BY_ROLE[normalizeRole(role)] || new Set()
}

function allowedNonServiceCategory(category, role) {
  const normalized = normalizeRole(role)

  if (HOUSEKEEPING_ROLES.has(normalized)) {
    return category === 'housekeeping' || category === 'maintenance'
  }

  if (KITCHEN_ROLES.has(normalized)) {
    return category === 'food'
  }

  if (ACCOUNTS_ROLES.has(normalized)) {
    return category === 'payment' || category === 'invoice'
  }

  if (DASHBOARD_ROLES.has(normalized)) {
    return true
  }

  return category === 'general'
}

export async function filterNotificationInboxForRole({
  items = [],
  hotelId,
  role,
}) {
  const normalized = normalizeRole(role)

  // Hotel dashboard roles are the global operational observer.
  // Department accounts remain isolated by the existing filters below.
  if (DASHBOARD_ROLES.has(normalized)) {
    return items
  }

  const serviceItems = items.filter(
    (item) => getNotificationCategory(item) === 'service'
  )
  const serviceIds = [
    ...new Set(serviceItems.map((item) => item?.source_id).filter(Boolean)),
  ]
  const serviceDepartmentById = new Map()

  if (hotelId && serviceIds.length > 0) {
    const allowedDepartments = serviceDepartmentsForRole(normalized)

    if (allowedDepartments.size > 0) {
      const { data, error } = await supabase
        .from('service_requests')
        .select('id, department')
        .eq('hotel_id', hotelId)
        .in('id', serviceIds)

      if (!error) {
        for (const row of data || []) {
          serviceDepartmentById.set(
            String(row.id),
            String(row.department || '').trim().toLowerCase()
          )
        }
      } else {
        // Fail closed: an unverified service request never reaches another department.
        console.warn(
          'StayQR notification department verification failed closed:',
          error.message
        )
      }
    }
  }

  return items.filter((item) => {
    const category = getNotificationCategory(item)

    if (category === 'service') {
      const department =
        serviceDepartmentById.get(String(item?.source_id || '')) || ''

      return serviceDepartmentsForRole(normalized).has(department)
    }

    return allowedNonServiceCategory(category, normalized)
  })
}
