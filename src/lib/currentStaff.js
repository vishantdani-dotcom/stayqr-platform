import { loadTenantContext } from './tenantContext'

export async function getCurrentStaff() {
  try {
    const context = await loadTenantContext()
    return context?.currentStaff || null
  } catch (error) {
    console.error('Current staff context error:', error)
    return null
  }
}

export function normalizeRole(role) {
  return String(role || '')
    .trim()
    .toLowerCase()
    .replace(/\s+/g, '_')
}

export function formatRole(role) {
  return String(role || 'Staff')
    .replace(/_/g, ' ')
    .replace(/\b\w/g, (char) => char.toUpperCase())
}

const HOTEL_ADMIN_ACCESS = [
  'dashboard',
  'reservations',
  'calendar',
  'operations',
  'rooms',
  'guests',
  'checkin',
  'menu',
  'staff',
  'qr',
  'payments',
  'folios',
  'services',
  'foodorders',
  'charges',
  'housekeeping',
  'maintenance',
  'amenities',
  'hotel',
  'reports',
  'invoices',
  'settings',
  'onboarding',
]

export const ROLE_ACCESS = {
  owner: HOTEL_ADMIN_ACCESS,
  manager: HOTEL_ADMIN_ACCESS,
  reception: [
    'dashboard',
    'reservations',
    'calendar',
    'operations',
    'rooms',
    'guests',
    'checkin',
    'payments',
    'folios',
    'services',
    'invoices',
  ],
  front_desk: [
    'dashboard',
    'reservations',
    'calendar',
    'operations',
    'rooms',
    'guests',
    'checkin',
    'payments',
    'folios',
    'services',
    'invoices',
  ],
  frontdesk: [
    'dashboard',
    'reservations',
    'calendar',
    'operations',
    'rooms',
    'guests',
    'checkin',
    'payments',
    'folios',
    'services',
    'invoices',
  ],
  housekeeping: ['dashboard', 'rooms', 'housekeeping', 'maintenance', 'services'],
  restaurant: ['dashboard', 'menu', 'foodorders'],
  accounts: ['dashboard', 'payments', 'folios', 'charges', 'reports', 'invoices'],
  platform_admin: ['superadmin', ...HOTEL_ADMIN_ACCESS],
  super_admin: ['superadmin', ...HOTEL_ADMIN_ACCESS],
}

const SECTION_PERMISSION = {
  dashboard: 'dashboard.view',
  reservations: 'reservations.view',
  calendar: 'calendar.view',
  operations: 'reservations.view',
  rooms: 'rooms.view',
  guests: 'guests.view',
  checkin: 'checkin.manage',
  menu: 'menu.manage',
  staff: 'staff.view',
  qr: 'hotel.manage',
  payments: 'payments.view',
  folios: 'payments.view',
  services: 'services.view',
  foodorders: 'foodorders.view',
  charges: 'payments.manage',
  housekeeping: 'housekeeping.view',
  maintenance: 'rooms.view',
  amenities: 'hotel.manage',
  hotel: 'hotel.manage',
  reports: 'reports.view',
  invoices: 'invoices.view',
  settings: 'hotel.manage',
  superadmin: 'superadmin.manage',
  onboarding: 'hotel.manage',
}

export function hasPermission(permissions, permissionKey) {
  if (!permissionKey) return false
  return Array.isArray(permissions) && permissions.includes(permissionKey)
}

export function canAccessSection(role, section, permissions = []) {
  const normalizedRole = normalizeRole(role)

  if (['platform_admin', 'super_admin'].includes(normalizedRole)) {
    return (ROLE_ACCESS[normalizedRole] || []).includes(section)
  }

  if (Array.isArray(permissions) && permissions.length > 0) {
    return hasPermission(permissions, SECTION_PERMISSION[section])
  }

  return (ROLE_ACCESS[normalizedRole] || []).includes(section)
}

export function canManageStaff(role, permissions = []) {
  const normalizedRole = normalizeRole(role)

  if (['platform_admin', 'super_admin'].includes(normalizedRole)) return true
  if (permissions.length > 0) return hasPermission(permissions, 'staff.manage')

  return ['owner', 'manager'].includes(normalizedRole)
}
