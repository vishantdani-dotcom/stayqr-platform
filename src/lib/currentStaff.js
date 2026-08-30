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
  'media',
  'hotel',
  'guidebuilder',
  'reports',
  'operationscenter',
  'invoices',
  'settings',
  'onboarding',
  'revenue',
  'opsautomation',
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
    'revenue',
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
    'revenue',
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
    'revenue',
  ],
  housekeeping: ['dashboard', 'rooms', 'housekeeping', 'maintenance', 'services', 'opsautomation'],
  restaurant: ['dashboard', 'menu', 'foodorders', 'opsautomation'],
  accounts: ['dashboard', 'payments', 'folios', 'charges', 'reports', 'invoices', 'operationscenter', 'revenue', 'opsautomation'],
  platform_admin: ['superadmin'],
  super_admin: ['superadmin'],
}


const PLATFORM_SUPPORT_SECTION_ACCESS = {
  read_only: ['dashboard'],
  hotel_configuration: ['dashboard', 'rooms', 'qr', 'menu', 'amenities', 'media', 'hotel', 'guidebuilder'],
  subscription_support: ['dashboard', 'payments', 'folios', 'reports', 'invoices'],
  ticket_support: ['dashboard', 'services', 'operationscenter'],
}

function canAccessPlatformSupportSection(section, permissions = []) {
  if (section === 'superadmin') return false

  return (permissions || []).some((permission) =>
    (PLATFORM_SUPPORT_SECTION_ACCESS[permission] || []).includes(section)
  )
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
  media: 'hotel.manage',
  hotel: 'hotel.manage',
  guidebuilder: 'hotel.manage',
  reports: 'reports.view',
  revenue: 'reservations.view',
  opsautomation: 'hotel.manage',
  invoices: 'invoices.view',
  settings: 'hotel.manage',
  operationscenter: 'hotel.manage',
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

  if (normalizedRole === 'platform_support') {
    return canAccessPlatformSupportSection(section, permissions)
  }

  if (Array.isArray(permissions) && permissions.length > 0) {
    if (section === 'opsautomation') {
      return permissions.some((permission) =>
        [
          'services.view',
          'services.manage',
          'housekeeping.view',
          'housekeeping.manage',
          'foodorders.view',
          'foodorders.manage',
          'reports.view',
          'rooms.view',
          'hotel.manage',
        ].includes(permission)
      )
    }

    if (section === 'revenue') {
      return permissions.some((permission) =>
        [
          'reservations.view',
          'reservations.manage',
          'payments.view',
          'payments.manage',
          'reports.view',
          'hotel.manage',
        ].includes(permission)
      )
    }

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
