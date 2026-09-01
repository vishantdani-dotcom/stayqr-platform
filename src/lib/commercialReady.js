import { supabase } from './supabase'

function message(error, fallback) {
  return error?.message || error?.details || fallback
}
export async function loadCommercialReadyWorkspace(hotelId) {
  const { data, error } = await supabase.rpc('get_commercial_ready_workspace', {
    p_hotel_id: hotelId,
  })
  if (error) throw new Error(message(error, 'Commercial-ready workspace could not be loaded.'))
  return data || {}
}

export async function submitOwnerBillingAction({
  hotelId,
  action,
  planId = null,
  billingCycle = null,
  reason,
}) {
  const idempotencyKey = `owner:${action}:${globalThis.crypto?.randomUUID?.() || `${Date.now()}-${Math.random()}`}`
  const { data, error } = await supabase.rpc('request_owner_subscription_action', {
    p_hotel_id: hotelId,
    p_action: action,
    p_plan_id: planId,
    p_billing_cycle: billingCycle,
    p_reason: reason,
    p_idempotency_key: idempotencyKey,
  })
  if (error) throw new Error(message(error, 'The billing request could not be recorded.'))
  return data
}

export async function invokeCashfreeRecurring(body) {
  const { data, error } = await supabase.functions.invoke('cashfree-recurring', { body })
  if (error) {
    let failure = message(error, 'Cashfree recurring billing could not be reached.')
    try {
      const payload = await error.context?.clone?.().json()
      failure = payload?.error || failure
    } catch {
      // Preserve the safe Functions error.
    }
    throw new Error(failure)
  }
  if (!data?.ok) throw new Error(data?.error || 'Cashfree recurring billing failed.')
  return data
}

export async function requestUidaiOnlineAuthentication({
  hotelId,
  guestId,
  guestSessionId = null,
  aadhaarNumber,
  mode = 'otp',
  otp = null,
  requestId = null,
}) {
  const { data, error } = await supabase.functions.invoke('uidai-online-auth', {
    body: {
      hotel_id: hotelId,
      guest_id: guestId,
      guest_session_id: guestSessionId,
      aadhaar_number: aadhaarNumber,
      auth_mode: mode,
      otp,
      request_id: requestId,
    },
  })
  if (error) {
    let failure = message(error, 'UIDAI online authentication could not be reached.')
    try {
      const payload = await error.context?.clone?.().json()
      failure = payload?.error || failure
    } catch {
      // Preserve the safe Functions error.
    }
    throw new Error(failure)
  }
  if (!data?.ok) throw new Error(data?.error || 'UIDAI online authentication failed.')
  return data
}
