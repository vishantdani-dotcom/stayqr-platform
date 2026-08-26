import { supabase } from './supabase'

function errorMessage(error, fallback) {
  return (
    error?.message ||
    error?.error_description ||
    error?.details ||
    fallback ||
    'StayQR could not complete the commercial action.'
  )
}

async function rpc(name, args = {}, fallback) {
  const { data, error } = await supabase.rpc(name, args)
  if (error) throw new Error(errorMessage(error, fallback))
  return data
}

export function createActionKey(prefix = 'day9') {
  const uuid = globalThis.crypto?.randomUUID?.()
  const fallback = `${Date.now()}-${Math.random().toString(16).slice(2)}`
  return `${prefix}:${uuid || fallback}`
}

export async function getCommercialData(rowLimit = 100) {
  const data = await rpc(
    'get_super_admin_commercial_data',
    { row_limit: rowLimit },
    'Commercial control data could not be loaded.'
  )

  return {
    generated_at: data?.generated_at || null,
    generated_by: data?.generated_by || null,
    summary: data?.summary || {},
    hotels: Array.isArray(data?.hotels) ? data.hotels : [],
    plans: Array.isArray(data?.plans) ? data.plans : [],
    usage: Array.isArray(data?.usage) ? data.usage : [],
    payment_links: Array.isArray(data?.payment_links)
      ? data.payment_links
      : [],
    support_tickets: Array.isArray(data?.support_tickets)
      ? data.support_tickets
      : [],
    subscription_events: Array.isArray(data?.subscription_events)
      ? data.subscription_events
      : [],
    webhook_events: Array.isArray(data?.webhook_events)
      ? data.webhook_events
      : [],
  }
}

export function getPostlaunchBatch2PlatformMetrics() {
  return rpc(
    'get_postlaunch_batch2_platform_metrics',
    {},
    'Platform metrics could not be loaded.'
  )
}

export function saveSubscriptionPlan(payload) {
  return rpc(
    'save_subscription_plan',
    { payload },
    'The subscription plan could not be saved.'
  )
}

export function getHotelUsage(hotelId) {
  return rpc(
    'get_hotel_subscription_usage',
    { target_hotel_id: hotelId },
    'Hotel usage could not be refreshed.'
  )
}

export function extendTrial(hotelId, extensionDays, reason, actionKey) {
  return rpc(
    'extend_hotel_trial',
    {
      target_hotel_id: hotelId,
      extension_days: Number(extensionDays),
      reason,
      action_idempotency_key: actionKey,
    },
    'The hotel trial could not be extended.'
  )
}

export function suspendSubscription(hotelId, reason, actionKey) {
  return rpc(
    'suspend_hotel_subscription',
    {
      target_hotel_id: hotelId,
      reason,
      action_idempotency_key: actionKey,
    },
    'The subscription could not be suspended.'
  )
}

export function reactivateSubscription(hotelId, reason, actionKey) {
  return rpc(
    'reactivate_hotel_subscription',
    {
      target_hotel_id: hotelId,
      reason,
      action_idempotency_key: actionKey,
    },
    'The subscription could not be reactivated.'
  )
}

export function changeSubscriptionPlan(hotelId, payload) {
  return rpc(
    'change_hotel_subscription_plan',
    { target_hotel_id: hotelId, payload },
    'The hotel plan could not be changed.'
  )
}

export function renewSubscription(hotelId, payload) {
  return rpc(
    'renew_hotel_subscription',
    { target_hotel_id: hotelId, payload },
    'The subscription could not be renewed.'
  )
}

export function cancelSubscription(
  hotelId,
  reason,
  immediate,
  actionKey
) {
  return rpc(
    'cancel_hotel_subscription',
    {
      target_hotel_id: hotelId,
      reason,
      immediate: Boolean(immediate),
      action_idempotency_key: actionKey,
    },
    'The subscription could not be cancelled.'
  )
}

export function reconcileExpiredSubscriptions(asOf = new Date().toISOString()) {
  return rpc(
    'reconcile_expired_subscriptions',
    { as_of: asOf },
    'Subscription expiry reconciliation failed.'
  )
}

export async function createCashfreePaymentLink(body) {
  const { data, error } = await supabase.functions.invoke(
    'cashfree-create-payment-link',
    { body }
  )

  if (error) {
    let message = errorMessage(
      error,
      'Cashfree could not create the payment link.'
    )

    const response = error?.context
    if (response && typeof response.json === 'function') {
      try {
        const providerError = await response.json()
        message = providerError?.error || message
      } catch {
        // Keep the safe fallback message when the provider response is not JSON.
      }
    }

    throw new Error(message)
  }

  if (!data?.ok || !data?.payment_link) {
    throw new Error(data?.error || 'Cashfree returned an incomplete response.')
  }

  return data
}

export function createSupportTicket(
  hotelId,
  subject,
  description,
  category,
  priority
) {
  return rpc(
    'create_support_ticket',
    {
      target_hotel_id: hotelId,
      subject,
      description,
      category,
      priority,
    },
    'The support ticket could not be created.'
  )
}

export function addSupportMessage(ticketId, message) {
  return rpc(
    'add_support_ticket_message',
    { target_ticket_id: ticketId, message },
    'The support message could not be added.'
  )
}

export function updateSupportTicketStatus(
  ticketId,
  status,
  message,
  assignToUserId = null
) {
  return rpc(
    'update_support_ticket_status',
    {
      target_ticket_id: ticketId,
      new_status: status,
      message: message || null,
      assign_to_user_id: assignToUserId || null,
    },
    'The support ticket could not be updated.'
  )
}

export function startSafeSupportAccess(
  hotelId,
  reason,
  durationMinutes,
  permissions
) {
  return rpc(
    'start_safe_support_access',
    {
      target_hotel_id: hotelId,
      reason,
      duration_minutes: Number(durationMinutes),
      requested_permissions: permissions,
    },
    'Safe support access could not be started.'
  )
}

export function endSafeSupportAccess(sessionId, reason) {
  return rpc(
    'end_safe_support_access',
    { target_session_id: sessionId, reason },
    'Safe support access could not be ended.'
  )
}

export function savePlatformAnnouncement(payload) {
  return rpc(
    'save_platform_announcement',
    { payload },
    'The announcement could not be saved.'
  )
}

export async function getActiveSupportSessions() {
  const { data, error } = await supabase
    .from('support_access_sessions')
    .select(
      'id, hotel_id, platform_admin_user_id, reason, status, permissions, started_at, expires_at, ended_at, created_at'
    )
    .in('status', ['active'])
    .order('started_at', { ascending: false })
    .limit(100)

  if (error) {
    throw new Error(errorMessage(error, 'Support sessions could not be loaded.'))
  }

  return data || []
}

export async function getPlatformAnnouncements() {
  const { data, error } = await supabase
    .from('announcements')
    .select(
      'id, scope, target_hotel_id, title, body, severity, status, starts_at, ends_at, published_at, created_at, updated_at'
    )
    .order('created_at', { ascending: false })
    .limit(100)

  if (error) {
    throw new Error(errorMessage(error, 'Announcements could not be loaded.'))
  }

  return data || []
}
