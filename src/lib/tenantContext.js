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
        phone_verified_at,
        avatar_path,
        role,
        status,
        auth_user_id,
        hotels (
          id,
          hotel_name,
          logo_url,
          cover_url,
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
          logo_url,
          cover_url,
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
  let supportAccessSessions = []

  if (platformAdmin) {
    const [hotelsResult, supportResult] = await Promise.all([
      supabase
        .from('hotels')
        .select(`
          id,
          hotel_name,
          logo_url,
          cover_url,
          location,
          status,
          slug,
          timezone,
          currency_code,
          subscription_status
        `)
        .order('hotel_name', { ascending: true }),
      supabase
        .from('support_access_sessions')
        .select('id, hotel_id, platform_admin_user_id, reason, status, permissions, started_at, expires_at, ended_at')
        .eq('platform_admin_user_id', user.id)
        .eq('status', 'active')
        .gt('expires_at', new Date().toISOString())
        .order('started_at', { ascending: false }),
    ])

    if (hotelsResult.error) throw hotelsResult.error
    if (supportResult.error) throw supportResult.error

    platformHotels = hotelsResult.data || []
    supportAccessSessions = supportResult.data || []
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
  const isPlatformAdmin = Boolean(platformAdmin)
  const activeSupportSession = isPlatformAdmin
    ? supportAccessSessions.find((session) => session.hotel_id === storedHotelId) || null
    : null

  const selectedAccess = isPlatformAdmin
    ? activeSupportSession
      ? storedAccess || null
      : null
    : storedAccess ||
      hotelAccess.find((access) => isOperationalHotel(access.hotel)) ||
      hotelAccess[0] ||
      null

  if (isPlatformAdmin && storedHotelId && !activeSupportSession) {
    storeHotelId(user.id, null)
  } else if (!isPlatformAdmin && selectedAccess && selectedAccess.hotel.id !== storedHotelId) {
    storeHotelId(user.id, selectedAccess.hotel.id)
  }

  const selectedHotel = selectedAccess?.hotel || null
  const isPlatformSupportMode = Boolean(isPlatformAdmin && activeSupportSession && selectedHotel)
  const selectedRole = isPlatformAdmin
    ? isPlatformSupportMode
      ? 'platform_support'
      : 'platform_admin'
    : normalizeRoleValue(
        selectedAccess?.staff?.role || selectedAccess?.membership?.role
      )

  let permissions = isPlatformSupportMode
    ? activeSupportSession.permissions || ['read_only']
    : []

  if (selectedHotel?.id && !isPlatformAdmin) {
    const { data: permissionRows, error: permissionError } = await supabase.rpc(
      'get_my_hotel_permissions',
      { target_hotel_id: selectedHotel.id }
    )

    if (permissionError && !['42883', 'PGRST202'].includes(permissionError.code)) {
      throw permissionError
    }

    permissions = (permissionRows || [])
      .map((row) => row.permission_key)
      .filter(Boolean)
  }

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
          phone_verified_at: selectedAccess?.staff?.phone_verified_at || null,
          avatar_path: selectedAccess?.staff?.avatar_path || null,
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
    supportAccessSessions,
    activeSupportSession,
    isPlatformSupportMode,
    selectedHotel,
    selectedHotelId: selectedHotel?.id || null,
    currentStaff,
    currentRole: selectedRole,
    permissions,
    requiresHotelSelection: !isPlatformAdmin && hotelAccess.length > 1 && !storedAccess,
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
  const context = await loadTenantContext({ force: true })
  const access = context?.hotelAccess.find(
    (candidate) => candidate.hotel.id === hotelId
  )

  if (!access) {
    throw new Error('You do not have access to the selected hotel.')
  }

  if (context?.isPlatformAdmin) {
    const activeSession = context.supportAccessSessions?.find(
      (session) => session.hotel_id === hotelId
    )

    if (!activeSession) {
      throw new Error('Start an audited View as Hotel session from Super Admin before entering this hotel.')
    }
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

    if (context?.isPlatformAdmin && !nextContext?.isPlatformSupportMode) {
      throw new Error('StayQR could not confirm the audited View as Hotel session.')
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
