import { supabase } from './supabase'

const HOTEL_SLUG_PATTERN = /^[a-z0-9]+(?:-[a-z0-9]+)*$/
const SIGNED_GUEST_TOKEN_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.[0-9a-f]{64}$/i

function emptyGuestContext() {
  return { hotelSlug: '', accessToken: '' }
}

function safelyDecodePathPart(value) {
  try {
    return decodeURIComponent(value)
  } catch {
    return ''
  }
}

function parseGuestPath(expectedRoot) {
  if (typeof window === 'undefined') {
    return emptyGuestContext()
  }

  const rawParts = window.location.pathname.split('/').filter(Boolean)

  if (rawParts.length !== 3 || rawParts[0] !== expectedRoot) {
    return emptyGuestContext()
  }

  const hotelSlug = safelyDecodePathPart(rawParts[1]).trim().toLowerCase()
  const accessToken = safelyDecodePathPart(rawParts[2]).trim()

  if (
    !hotelSlug ||
    hotelSlug.length > 80 ||
    !HOTEL_SLUG_PATTERN.test(hotelSlug) ||
    !accessToken ||
    accessToken.length > 160 ||
    !SIGNED_GUEST_TOKEN_PATTERN.test(accessToken)
  ) {
    return emptyGuestContext()
  }

  return { hotelSlug, accessToken }
}

export function getGuestAccessContext(root = 'guest') {
  return parseGuestPath(root)
}

function requireGuestAccess(root) {
  const context = parseGuestPath(root)

  if (!context.hotelSlug || !context.accessToken) {
    throw new Error('This StayQR guest link is invalid or incomplete.')
  }

  return context
}

async function callGuestRpc(functionName, args, fallbackMessage) {
  const { data, error } = await supabase.rpc(functionName, args)

  if (error) {
    const message = String(error.message || '').trim()
    throw new Error(message || fallbackMessage)
  }

  return data
}

export async function resolveGuestPortal(root = 'guest') {
  const { hotelSlug, accessToken } = requireGuestAccess(root)

  const data = await callGuestRpc(
    'resolve_guest_portal',
    {
      p_hotel_slug: hotelSlug,
      p_access_token: accessToken,
    },
    'This guest access link is invalid or expired.'
  )

  return data || null
}

export async function getGuestServiceRequests() {
  const { hotelSlug, accessToken } = requireGuestAccess('guest')

  const data = await callGuestRpc(
    'get_guest_service_requests',
    {
      p_hotel_slug: hotelSlug,
      p_access_token: accessToken,
    },
    'Unable to load your service requests.'
  )

  return Array.isArray(data) ? data : []
}

export async function createGuestServiceRequest(requestType) {
  const { hotelSlug, accessToken } = requireGuestAccess('guest')

  return callGuestRpc(
    'create_guest_service_request',
    {
      p_hotel_slug: hotelSlug,
      p_access_token: accessToken,
      p_request_type: requestType,
    },
    'Unable to create the service request.'
  )
}

export async function getGuestMenu() {
  const { hotelSlug, accessToken } = requireGuestAccess('food')

  const data = await callGuestRpc(
    'get_guest_food_menu',
    {
      p_hotel_slug: hotelSlug,
      p_access_token: accessToken,
    },
    'Unable to load the hotel menu.'
  )

  return Array.isArray(data) ? data : []
}

export async function getGuestFoodOrders() {
  const { hotelSlug, accessToken } = requireGuestAccess('food')

  const data = await callGuestRpc(
    'get_guest_food_orders',
    {
      p_hotel_slug: hotelSlug,
      p_access_token: accessToken,
    },
    'Unable to load your food orders.'
  )

  return Array.isArray(data) ? data : []
}

export async function placeGuestFoodOrder(items) {
  const { hotelSlug, accessToken } = requireGuestAccess('food')

  return callGuestRpc(
    'place_guest_food_order',
    {
      p_hotel_slug: hotelSlug,
      p_access_token: accessToken,
      p_items: items,
    },
    'Unable to place the food order.'
  )
}

export async function getGuestAccessLinks(hotelId) {
  if (!hotelId) return []

  const { data, error } = await supabase.rpc('get_guest_access_links', {
    target_hotel_id: hotelId,
  })

  if (error) throw error
  return Array.isArray(data) ? data : []
}

export async function rotateGuestAccessToken({
  hotelId,
  guestSessionId,
  reason = 'Manual QR rotation',
}) {
  const { data, error } = await supabase.rpc('rotate_guest_access_token', {
    target_hotel_id: hotelId,
    target_guest_session_id: guestSessionId,
    rotation_reason: reason,
  })

  if (error) throw error
  return data
}

export async function revokeGuestAccessToken({
  hotelId,
  guestSessionId,
  reason = 'Manual guest access revocation',
}) {
  const { data, error } = await supabase.rpc('revoke_guest_access_token', {
    target_hotel_id: hotelId,
    target_guest_session_id: guestSessionId,
    revocation_reason: reason,
  })

  if (error) throw error
  return data
}
