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
  'rooms',
  'guests',
  'checkin',
  'menu',
  'staff',
  'qr',
  'payments',
  'services',
  'foodorders',
  'charges',
  'housekeeping',
  'amenities',
  'hotel',
  'reports',
  'invoices',
  'settings',
]

export const ROLE_ACCESS = {
  owner: HOTEL_ADMIN_ACCESS,
  manager: HOTEL_ADMIN_ACCESS,

  reception: [
    'dashboard',
    'reservations',
    'calendar',
    'rooms',
    'guests',
    'checkin',
    'payments',
    'services',
    'invoices',
  ],

  front_desk: [
    'dashboard',
    'reservations',
    'calendar',
    'rooms',
    'guests',
    'checkin',
    'payments',
    'services',
    'invoices',
  ],

  frontdesk: [
    'dashboard',
    'reservations',
    'calendar',
    'rooms',
    'guests',
    'checkin',
    'payments',
    'services',
    'invoices',
  ],

  housekeeping: ['dashboard', 'rooms', 'housekeeping', 'services'],

  restaurant: ['dashboard', 'menu', 'foodorders'],

  accounts: ['dashboard', 'payments', 'charges', 'reports', 'invoices'],

  platform_admin: ['superadmin', ...HOTEL_ADMIN_ACCESS],

  // Compatibility only. New platform administrators use platform_admins and
  // resolve to `platform_admin`, not a hotel-level super_admin membership.
  super_admin: ['superadmin', ...HOTEL_ADMIN_ACCESS],
}

export function canAccessSection(role, section) {
  const normalizedRole = normalizeRole(role)
  const allowed = ROLE_ACCESS[normalizedRole] || []
  return allowed.includes(section)
}

export function canManageStaff(role) {
  const normalizedRole = normalizeRole(role)
  return ['owner', 'manager', 'platform_admin', 'super_admin'].includes(
    normalizedRole
  )
}
