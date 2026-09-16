import { NAVIGATE_EVENT } from './bookingCalendar'
import {
  STAYQR_PUSH_NAVIGATION_KEY,
  STAYQR_PUSH_WORKER_URL,
  STAYQR_VAPID_PUBLIC_KEY,
} from './backgroundPushConfig'
import { supabase } from './supabase'

function base64UrlToUint8Array(value) {
  const padding = '='.repeat((4 - (value.length % 4)) % 4)
  const base64 = (value + padding).replace(/-/g, '+').replace(/_/g, '/')
  const raw = window.atob(base64)
  return Uint8Array.from(raw, (char) => char.charCodeAt(0))
}

function isIosDevice() {
  return /iphone|ipad|ipod/i.test(navigator.userAgent || '')
}

function isStandaloneDisplay() {
  return Boolean(
    window.matchMedia?.('(display-mode: standalone)').matches ||
      window.navigator.standalone
  )
}

export function getBackgroundPushEnvironment() {
  const supported = Boolean(
    window.isSecureContext &&
      'serviceWorker' in navigator &&
      'PushManager' in window &&
      'Notification' in window
  )

  return {
    supported,
    permission: supported ? Notification.permission : 'unsupported',
    isIos: isIosDevice(),
    isStandalone: isStandaloneDisplay(),
  }
}

async function getRegistration() {
  if (!('serviceWorker' in navigator)) return null

  const existing = await navigator.serviceWorker.getRegistration('/')
  if (existing) return existing

  return navigator.serviceWorker.register(STAYQR_PUSH_WORKER_URL, {
    scope: '/',
    updateViaCache: 'none',
  })
}

async function getCurrentSubscription() {
  if (!('serviceWorker' in navigator)) return null
  const registration = await navigator.serviceWorker.getRegistration('/')
  if (!registration?.pushManager) return null
  return registration.pushManager.getSubscription()
}

function subscriptionPayload(subscription) {
  const json = subscription?.toJSON?.() || {}
  const keys = json.keys || {}

  if (!json.endpoint || !keys.p256dh || !keys.auth) {
    throw new Error('The browser returned an incomplete push subscription.')
  }

  return {
    endpoint: json.endpoint,
    p256dh: keys.p256dh,
    auth: keys.auth,
    expiration_time: subscription.expirationTime
      ? new Date(subscription.expirationTime).toISOString()
      : null,
  }
}

async function registerSubscriptionWithStayQr(hotelId, subscription) {
  const payload = subscriptionPayload(subscription)
  const environment = getBackgroundPushEnvironment()

  const { data, error } = await supabase.rpc(
    'register_background_push_subscription',
    {
      p_hotel_id: hotelId,
      p_endpoint: payload.endpoint,
      p_p256dh: payload.p256dh,
      p_auth: payload.auth,
      p_expiration_time: payload.expiration_time,
      p_user_agent: navigator.userAgent || null,
      p_platform: environment.isIos
        ? 'ios_web'
        : navigator.userAgentData?.platform || navigator.platform || 'web',
    }
  )

  if (error) throw error
  return data || { enabled: true }
}

export async function getBackgroundPushStatus(hotelId) {
  const environment = getBackgroundPushEnvironment()
  let localSubscription = null

  if (environment.supported) {
    localSubscription = await getCurrentSubscription().catch(() => null)
  }

  if (!hotelId) {
    return {
      ...environment,
      enabled: false,
      activeDevices: 0,
      localSubscription: Boolean(localSubscription),
    }
  }

  const { data, error } = await supabase.rpc(
    'get_background_push_status',
    { p_hotel_id: hotelId }
  )

  if (error) throw error

  return {
    ...environment,
    enabled: Boolean(data?.enabled && localSubscription),
    activeDevices: Number(data?.active_devices || 0),
    localSubscription: Boolean(localSubscription),
  }
}

export async function enableBackgroundPush(hotelId) {
  if (!hotelId) throw new Error('A hotel context is required.')

  const environment = getBackgroundPushEnvironment()
  if (!environment.supported) {
    throw new Error('Background notifications are not supported in this browser.')
  }

  if (environment.isIos && !environment.isStandalone) {
    throw new Error(
      'On iPhone or iPad, add StayQR to the Home Screen and open it from there before enabling notifications.'
    )
  }

  if (!STAYQR_VAPID_PUBLIC_KEY || STAYQR_VAPID_PUBLIC_KEY.startsWith('__')) {
    throw new Error('StayQR background notifications are not configured yet.')
  }

  const permission = await Notification.requestPermission()
  if (permission !== 'granted') {
    throw new Error(
      permission === 'denied'
        ? 'Notifications are blocked for StayQR in this browser. Enable them in browser or system settings.'
        : 'Notification permission was not granted.'
    )
  }

  const registration = await getRegistration()
  if (!registration?.pushManager) {
    throw new Error('The browser could not initialize background notifications.')
  }

  let subscription = await registration.pushManager.getSubscription()

  if (!subscription) {
    subscription = await registration.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: base64UrlToUint8Array(
        STAYQR_VAPID_PUBLIC_KEY
      ),
    })
  }

  await registerSubscriptionWithStayQr(hotelId, subscription)
  return getBackgroundPushStatus(hotelId)
}

export async function syncExistingBackgroundPush(hotelId) {
  if (!hotelId) return null
  const environment = getBackgroundPushEnvironment()
  if (!environment.supported || environment.permission !== 'granted') {
    return null
  }

  const subscription = await getCurrentSubscription()
  if (!subscription) return null
  await registerSubscriptionWithStayQr(hotelId, subscription)
  return subscription
}

export async function disableBackgroundPush(hotelId) {
  const subscription = await getCurrentSubscription()
  if (!subscription) {
    return getBackgroundPushStatus(hotelId)
  }

  const endpoint = subscription.endpoint

  if (hotelId) {
    const { error } = await supabase.rpc(
      'disable_background_push_subscription',
      {
        p_hotel_id: hotelId,
        p_endpoint: endpoint,
      }
    )
    if (error) throw error
  }

  await subscription.unsubscribe().catch(() => false)
  return getBackgroundPushStatus(hotelId)
}

export async function disableCurrentDevicePushBeforeLogout() {
  try {
    const subscription = await getCurrentSubscription()
    if (!subscription?.endpoint) return

    await supabase.rpc('disable_my_background_push_endpoint', {
      p_endpoint: subscription.endpoint,
    })

    await subscription.unsubscribe().catch(() => false)
  } catch (error) {
    console.warn(
      'StayQR background push cleanup was skipped during logout:',
      error?.message || error
    )
  }
}

export async function sendBackgroundPushTest(hotelId) {
  if (!hotelId) throw new Error('A hotel context is required.')
  const subscription = await getCurrentSubscription()
  if (!subscription?.endpoint) {
    throw new Error('Enable background notifications on this device first.')
  }

  const { data, error } = await supabase.functions.invoke(
    'stayqr-background-push',
    {
      body: {
        action: 'test',
        hotel_id: hotelId,
        endpoint: subscription.endpoint,
      },
    }
  )

  if (error) throw error
  if (!data?.ok) {
    throw new Error(data?.error || 'The test notification could not be sent.')
  }
  return data
}

function parsePushNavigation(rawUrl) {
  if (!rawUrl) return null

  try {
    const url = new URL(rawUrl, window.location.origin)
    if (url.origin !== window.location.origin) return null
    if (url.searchParams.get('stayqr_push') !== '1') return null

    const section = String(url.searchParams.get('section') || '').trim()
    if (!section) return null

    const detail = { section }
    const reservationId = url.searchParams.get('reservationId')
    const guestSessionId = url.searchParams.get('guestSessionId')
    const entityId = url.searchParams.get('entityId')
    const initialTab = url.searchParams.get('initialTab')
    const hotelId = url.searchParams.get('hotelId')

    if (hotelId) detail.hotelId = hotelId
    if (reservationId) detail.reservationId = reservationId
    if (guestSessionId) detail.guestSessionId = guestSessionId
    if (entityId) detail.entityId = entityId
    if (initialTab) detail.initialTab = initialTab

    return detail
  } catch {
    return null
  }
}

function storePendingNavigation(detail) {
  if (!detail) return
  try {
    window.sessionStorage.setItem(
      STAYQR_PUSH_NAVIGATION_KEY,
      JSON.stringify(detail)
    )
  } catch {
    // Session storage is optional. The live event still works.
  }
}

function clearPushQueryFromAddressBar() {
  try {
    const url = new URL(window.location.href)
    const keys = [
      'stayqr_push',
      'section',
      'reservationId',
      'guestSessionId',
      'entityId',
      'initialTab',
      'hotelId',
    ]
    let changed = false
    for (const key of keys) {
      if (url.searchParams.has(key)) {
        url.searchParams.delete(key)
        changed = true
      }
    }
    if (changed) {
      window.history.replaceState({}, '', `${url.pathname}${url.search}${url.hash}`)
    }
  } catch {
    // Cosmetic URL cleanup only.
  }
}

export function installBackgroundPushClientBridge() {
  const fromAddressBar = parsePushNavigation(window.location.href)
  if (fromAddressBar) {
    storePendingNavigation(fromAddressBar)
    clearPushQueryFromAddressBar()
  }

  if (!('serviceWorker' in navigator)) return

  navigator.serviceWorker.addEventListener('message', (event) => {
    if (event.data?.type !== 'STAYQR_PUSH_NAVIGATE') return

    const detail = parsePushNavigation(event.data?.url)
    if (!detail) return

    storePendingNavigation(detail)
    window.dispatchEvent(
      new CustomEvent(NAVIGATE_EVENT, { detail })
    )
  })
}

export function consumePendingBackgroundPushNavigation(currentHotelId = null) {
  try {
    const raw = window.sessionStorage.getItem(STAYQR_PUSH_NAVIGATION_KEY)
    if (!raw) return null
    const detail = JSON.parse(raw)
    if (!detail?.section) {
      window.sessionStorage.removeItem(STAYQR_PUSH_NAVIGATION_KEY)
      return null
    }

    const targetHotelId = String(detail.hotelId || '').trim()
    const selectedHotelId = String(currentHotelId || '').trim()
    if (targetHotelId && targetHotelId !== selectedHotelId) {
      // Keep the navigation pending until the user switches to the authorised hotel.
      return null
    }

    window.sessionStorage.removeItem(STAYQR_PUSH_NAVIGATION_KEY)
    return detail
  } catch {
    return null
  }
}
