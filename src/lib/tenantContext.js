import { supabase } from './supabase'

const SELECTED_HOTEL_KEY = 'stayqr:selected-hotel-id'

let cachedContext = null
let contextPromise = null

function getStoredHotelId() {
  if (typeof window === 'undefined') return null
  return window.localStorage.getItem(SELECTED_HOTEL_KEY)
}

function storeHotelId(hotelId) {
  if (typeof window === 'undefined') return

  if (hotelId) {
    window.localStorage.setItem(SELECTED_HOTEL_KEY, hotelId)
  } else {
    window.localStorage.removeItem(SELECTED_HOTEL_KEY)
  }
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

  const storedHotelId = getStoredHotelId()
  const storedAccess = hotelAccess.find(
    (access) => access.hotel.id === storedHotelId
  )

  const selectedAccess =
    storedAccess ||
    hotelAccess.find((access) => isOperationalHotel(access.hotel)) ||
    hotelAccess[0] ||
    null

  if (selectedAccess && selectedAccess.hotel.id !== storedHotelId) {
    storeHotelId(selectedAccess.hotel.id)
  }

  const isPlatformAdmin = Boolean(platformAdmin)
  const selectedHotel = selectedAccess?.hotel || null
  const selectedRole = isPlatformAdmin
    ? 'platform_admin'
    : normalizeRoleValue(
        selectedAccess?.staff?.role || selectedAccess?.membership?.role
      )

  const currentStaff = selectedAccess || isPlatformAdmin
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
  const isAuthorized = context?.hotelAccess.some(
    (access) => access.hotel.id === hotelId
  )

  if (!isAuthorized) {
    throw new Error('You do not have access to the selected hotel.')
  }

  storeHotelId(hotelId)
  clearTenantContextCache()
  return loadTenantContext({ force: true })
}

export function clearSelectedTenantHotel() {
  storeHotelId(null)
  clearTenantContextCache()
}
