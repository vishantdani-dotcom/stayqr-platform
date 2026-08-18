import { supabase } from './supabase'

const REQUEST_KEY_PREFIX = 'stayqr:acquisition-request'
const LAST_INTENT_KEY_PREFIX = 'stayqr:acquisition-intent'

function unwrapRpc(data) {
  if (Array.isArray(data)) return data[0] || null
  return data || null
}

function requestStorageKey(userId) {
  return `${REQUEST_KEY_PREFIX}:${userId || 'anonymous'}`
}

function intentStorageKey(userId) {
  return `${LAST_INTENT_KEY_PREFIX}:${userId || 'anonymous'}`
}

export async function fetchPublicSubscriptionPlans() {
  const { data, error } = await supabase.rpc('get_public_subscription_plans')
  if (error) throw error
  return data || []
}

export function getOrCreateAcquisitionRequestId(userId, signature) {
  const key = requestStorageKey(userId)

  try {
    const stored = JSON.parse(window.localStorage.getItem(key) || 'null')
    if (stored?.id && stored.signature === signature) return stored.id
  } catch {
    // Replace malformed browser state with a new request identity.
  }

  const id = crypto.randomUUID()
  window.localStorage.setItem(key, JSON.stringify({ id, signature }))
  return id
}

export function rememberAcquisitionIntent(userId, intentId) {
  if (!intentId) return
  window.localStorage.setItem(intentStorageKey(userId), intentId)
}

export function getRememberedAcquisitionIntent(userId) {
  return window.localStorage.getItem(intentStorageKey(userId))
}

export function resetAcquisitionRequest(userId) {
  window.localStorage.removeItem(requestStorageKey(userId))
}

export async function startSelfServiceTrial(payload) {
  const { data, error } = await supabase.rpc('start_self_service_trial', {
    payload,
  })
  if (error) throw error
  return unwrapRpc(data)
}

export async function createSelfServiceCheckout(payload) {
  const { data, error } = await supabase.functions.invoke(
    'cashfree-create-self-service-checkout',
    { body: payload }
  )

  if (error) {
    const providerMessage = data?.error || error?.context?.error
    const checkoutError = new Error(
      providerMessage || error.message || 'Cashfree checkout could not be created.'
    )
    checkoutError.restartAllowed = Boolean(data?.restart_allowed || data?.intent_id)
    throw checkoutError
  }
  if (!data?.ok) throw new Error(data?.error || 'Cashfree checkout could not be created.')
  return data
}

export async function getMyAcquisitionIntent(intentId = null) {
  const { data, error } = await supabase.rpc('get_my_acquisition_intent', {
    target_intent_id: intentId || null,
  })
  if (error) throw error
  return unwrapRpc(data)
}
