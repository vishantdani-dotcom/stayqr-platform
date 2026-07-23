import { supabase } from './supabase'

const SELECTED_HOTEL_KEY_PREFIX = 'stayqr:selected-hotel-id'
const LEGACY_SELECTED_HOTEL_KEY = SELECTED_HOTEL_KEY_PREFIX

let cachedContext = null
let contextPromise = null

function getStorageKey(userId) {
  return userId
    ? `${SELECTED_HOTEL_KEY_PREFIX}:${userId}`
    : LEGACY_SELECTED_HOTEL_KEY
}

function getStoredHotelId(userId) {
  if (typeof window === 'undefined') return null

  // Never trust the old global key across authenticated users.
  window.localStorage.removeItem(LEGACY_SELECTED_HOTEL_KEY)
  return window.localStorage.getItem(getStorageKey(userId))
}

function storeHotelId(userId, hotelId) {
  if (typeof window === 'undefined') return

  const key = getStorageKey(userId)

  if (hotelId) {
    window.localStorage.setItem(key, hotelId)
  } else {
    window.localStorage.removeItem(key)
  }

  window.localStorage.removeItem(LEGACY_SELECTED_HOTEL_KEY)
}

function clearStoredHotelSelections() {
  if (typeof window === 'undefined') return

  const keysToRemove = []

  for (let index = 0; index < window.localStorage.length; index += 1) {
    const key = window.localStorage.key(index)
    if (key?.startsWith(SELECTED_HOTEL_KEY_PREFIX)) {
      keysToRemove.push(key)
    }
  }

  keysToRemove.forEach((key) => window.localStorage.removeItem(key))
}

function unwrapHotel(value) {
  if (Array.isArray(value)) return value[0] || null
  return value || null
}

function normalizeRoleValue(role) {
  return String(role || '')
    .trim()
    .toLowerCase()
    .replace(/\s+/g, '_')
}

function isOperationalHotel(hotel) {
  return hotel && !['suspended', 'inactive', 'archived'].includes(hotel.status)
}

function getDisplayName({ staff, membership, platformAdmin, user }) {
  return (
    staff?.full_name ||
    membership?.full_name ||
    platformAdmin?.display_name ||
    user?.user_metadata?.full_name ||
    user?.email?.split('@')[0] ||
    'StayQR User'
  )
}

function mergeHotelAccess({ staffRows, membershipRows, platformHotels }) {
  const accessMap = new Map()

  const ensureAccess = (hotel) => {
    if (!hotel?.id) return null

    if (!accessMap.has(hotel.id)) {
      accessMap.set(hotel.id, {
        hotel,
        staff: null,
        membership: null,
      })
    }

    return accessMap.get(hotel.id)
  }

  staffRows.forEach((staff) => {
    const hotel = unwrapHotel(staff.hotels)
    const access = ensureAccess(hotel)
    if (access) access.staff = staff
  })

  membershipRows.forEach((membership) => {
    const hotel = unwrapHotel(membership.hotels)
    const access = ensureAccess(hotel)
    if (access) access.membership = membership
  })

  platformHotels.forEach((hotel) => {
    ensureAccess(hotel)
  })

  return [...accessMap.values()].sort((a, b) =>
    String(a.hotel.hotel_name || '').localeCompare(
      String(b.hotel.hotel_name || '')
    )
  )
}

async function fetchTenantContext() {
  const {
    data: { user },
    error: userError,
  } = await supabase.auth.getUser()

  if (userError) throw userError
  if (!user) return null

  const { data: platformAdmin, error: platformAdminError } = await supabase
    .from('platform_admins')
    .select('user_id, display_name, status')
    .eq('user_id', user.id)
    .eq('status', 'active')
    .maybeSingle()

  if (platformAdminError) throw platformAdminError

  const [staffResult, membershipResult] = await Promise.all([
    supabase
      .from('staff')
      .select(`
        id,
        hotel_id,
        full_name,
        email,
        phone,
        role,
        status,
        auth_user_id,
        hotels (
          id,
          hotel_name,
          location,
          status,
          slug,
          timezone,
          currency_code,
          subscription_status
        )
      `)
      .eq('auth_user_id', user.id)
      .eq('status', 'active'),
    supabase
      .from('hotel_users')
      .select(`
        id,
        hotel_id,
        user_id,
        full_name,
        email,
        role,
        status,
        hotels (
          id,
          hotel_name,
          location,
          status,
          slug,
          timezone,
          currency_code,
          subscription_status
        )
      `)
      .eq('user_id', user.id)
      .eq('status', 'active'),
  ])

  if (staffResult.error) throw staffResult.error
  if (membershipResult.error) throw membershipResult.error

  let platformHotels = []

  if (platformAdmin) {
    const { data, error } = await supabase
      .from('hotels')
      .select(`
        id,
        hotel_name,
        location,
        status,
        slug,
        timezone,
        currency_code,
        subscription_status
      `)
      .order('hotel_name', { ascending: true })

    if (error) throw error
    platformHotels = data || []
  }

  const hotelAccess = mergeHotelAccess({
    staffRows: staffResult.data || [],
    membershipRows: membershipResult.data || [],
    platformHotels,
  })

  const storedHotelId = getStoredHotelId(user.id)
  const storedAccess = hotelAccess.find(
    (access) => access.hotel.id === storedHotelId
  )

  const selectedAccess =
    storedAccess ||
    hotelAccess.find((access) => isOperationalHotel(access.hotel)) ||
    hotelAccess[0] ||
    null

  if (selectedAccess && selectedAccess.hotel.id !== storedHotelId) {
    storeHotelId(user.id, selectedAccess.hotel.id)
  }

  const isPlatformAdmin = Boolean(platformAdmin)
  const selectedHotel = selectedAccess?.hotel || null
  const selectedRole = isPlatformAdmin
    ? 'platform_admin'
    : normalizeRoleValue(
        selectedAccess?.staff?.role || selectedAccess?.membership?.role
      )

  const currentStaff =
    selectedAccess || isPlatformAdmin
      ? {
          id: selectedAccess?.staff?.id || null,
          hotel_id: selectedHotel?.id || null,
          full_name: getDisplayName({
            staff: selectedAccess?.staff,
            membership: selectedAccess?.membership,
            platformAdmin,
            user,
          }),
          email:
            selectedAccess?.staff?.email ||
            selectedAccess?.membership?.email ||
            user.email ||
            null,
          phone: selectedAccess?.staff?.phone || null,
          role: selectedRole,
          department: selectedAccess?.staff?.department || null,
          status: 'active',
          auth_user_id: user.id,
          hotels: selectedHotel,
        }
      : null

  return {
    user,
    isPlatformAdmin,
    platformAdmin: platformAdmin || null,
    hotelAccess,
    hotels: hotelAccess.map((access) => access.hotel),
    selectedHotel,
    selectedHotelId: selectedHotel?.id || null,
    currentStaff,
    currentRole: selectedRole,
    requiresHotelSelection: hotelAccess.length > 1 && !storedAccess,
  }
}

export async function loadTenantContext({ force = false } = {}) {
  if (!force && cachedContext) return cachedContext
  if (!force && contextPromise) return contextPromise

  contextPromise = fetchTenantContext()
    .then((context) => {
      cachedContext = context
      return context
    })
    .finally(() => {
      contextPromise = null
    })

  return contextPromise
}

export function clearTenantContextCache() {
  cachedContext = null
  contextPromise = null
}

export async function selectTenantHotel(hotelId) {
  const context = await loadTenantContext()
  const access = context?.hotelAccess.find(
    (candidate) => candidate.hotel.id === hotelId
  )

  if (!access) {
    throw new Error('You do not have access to the selected hotel.')
  }

  const userId = context?.user?.id
  const previousHotelId = getStoredHotelId(userId)

  storeHotelId(userId, hotelId)
  clearTenantContextCache()

  try {
    const nextContext = await loadTenantContext({ force: true })

    if (nextContext?.selectedHotelId !== hotelId) {
      throw new Error('StayQR could not activate the selected hotel.')
    }

    return nextContext
  } catch (error) {
    storeHotelId(userId, previousHotelId)
    clearTenantContextCache()

    try {
      await loadTenantContext({ force: true })
    } catch (rollbackError) {
      console.error('Tenant selection rollback failed:', rollbackError)
    }

    throw error
  }
}

export function clearSelectedTenantHotel() {
  clearStoredHotelSelections()
  clearTenantContextCache()
}
