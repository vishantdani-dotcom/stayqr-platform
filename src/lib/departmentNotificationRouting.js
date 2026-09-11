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

export function isLocalDepartmentNotification(notification) {
  return Boolean(notification?.metadata?.local_department_event)
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

export function mergeNotificationItems(serverItems = [], currentItems = []) {
  const localItems = currentItems.filter(isLocalDepartmentNotification)
  const byId = new Map()

  for (const item of [...localItems, ...serverItems]) {
    if (!item?.id || byId.has(item.id)) continue
    byId.set(item.id, item)
  }

  return [...byId.values()]
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
    return !['food', 'housekeeping', 'maintenance'].includes(category)
  }

  return category === 'general'
}

export async function filterNotificationInboxForRole({
  items = [],
  hotelId,
  role,
}) {
  const normalized = normalizeRole(role)
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
        // Fail closed. A service request whose department cannot be verified
        // must not leak into an unrelated department account.
        console.warn(
          'StayQR notification department check failed closed:',
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
