import { createClient } from '@supabase/supabase-js'
import webpush from 'web-push'

type JsonRecord = Record<string, unknown>

type WebhookPayload = {
  type?: string
  table?: string
  schema?: string
  record?: JsonRecord | null
  old_record?: JsonRecord | null
}

// Foreground StayQR notification routing is already resolved into
// public.notification_recipients. Background Push consumes that authoritative
// recipient decision and never recomputes department/role routing.

function env(name: string) {
  return String(Deno.env.get(name) || '').trim()
}

function normalizeRole(value: unknown) {
  return String(value || '')
    .trim()
    .toLowerCase()
    .replace(/\s+/g, '_')
}

function corsHeaders(request: Request) {
  const origin = request.headers.get('Origin') || ''
  const allowed =
    origin === 'https://app.stayqr.in' ||
    /^https:\/\/[^/]+\.netlify\.app$/i.test(origin) ||
    /^http:\/\/localhost(?::\d+)?$/i.test(origin)

  return {
    'Access-Control-Allow-Origin': allowed ? origin : 'https://app.stayqr.in',
    'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info, x-stayqr-push-secret',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Cache-Control': 'no-store',
    'Vary': 'Origin',
  }
}

function json(request: Request, status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders(request),
      'Content-Type': 'application/json; charset=utf-8',
    },
  })
}

function notificationDestination(sourceType: string, eventKey: string, sourceId: string, metadata: JsonRecord, hotelId: string) {
  const value = `${sourceType} ${eventKey}`.toLowerCase()
  const params = new URLSearchParams({ stayqr_push: '1' })
  if (hotelId) params.set('hotelId', hotelId)

  if (value.includes('reservation')) {
    params.set('section', 'reservations')
    if (sourceId) params.set('reservationId', sourceId)
  } else if (value.includes('payment')) {
    params.set('section', 'payments')
  } else if (value.includes('invoice')) {
    params.set('section', 'invoices')
  } else if (value.includes('service')) {
    params.set('section', 'services')
  } else if (value.includes('food')) {
    params.set('section', 'foodorders')
  } else if (value.includes('housekeeping')) {
    params.set('section', 'housekeeping')
  } else if (value.includes('maintenance')) {
    params.set('section', 'maintenance')
  } else if (value.includes('room')) {
    params.set('section', 'rooms')
  } else if (value.includes('checkout') || value.includes('checkin') || value.includes('guest')) {
    params.set('section', 'guests')
    const guestSessionId = String(
      metadata.guest_session_id || metadata.guestSessionId || sourceId || ''
    ).trim()
    if (guestSessionId) params.set('guestSessionId', guestSessionId)
  } else if (value.includes('support')) {
    params.set('section', 'operationscenter')
    params.set('initialTab', 'support')
  } else {
    params.set('section', 'operationscenter')
    params.set('initialTab', 'notifications')
  }

  if (sourceId) params.set('entityId', sourceId)
  return `/?${params.toString()}`
}

function configureWebPush() {
  const publicKey = env('STAYQR_VAPID_PUBLIC_KEY')
  const privateKey = env('STAYQR_VAPID_PRIVATE_KEY')
  const subject = env('STAYQR_VAPID_SUBJECT') || 'mailto:support@stayqr.in'

  if (!publicKey || !privateKey) {
    throw new Error('StayQR Web Push VAPID secrets are not configured.')
  }

  webpush.setVapidDetails(subject, publicKey, privateKey)
}

async function authorizeUser(admin: ReturnType<typeof createClient>, token: string) {
  if (!token) return null
  const { data, error } = await admin.auth.getUser(token)
  if (error || !data?.user?.id) return null
  return data.user
}

async function sendOnePush(
  admin: ReturnType<typeof createClient>,
  subscription: any,
  payload: JsonRecord,
  recipientId: string | null,
  logDelivery: boolean,
) {
  let deliveryId: string | null = null

  if (subscription.expiration_time) {
    const expiresAt = new Date(subscription.expiration_time).getTime()
    if (Number.isFinite(expiresAt) && expiresAt <= Date.now()) {
      await admin
        .from('background_push_subscriptions')
        .update({
          is_active: false,
          last_error_code: 'subscription_expired',
          updated_at: new Date().toISOString(),
        })
        .eq('id', subscription.id)
      return { skipped: true, expired: true }
    }
  }

  if (logDelivery && recipientId) {
    const { data: inserted, error: insertError } = await admin
      .from('background_push_deliveries')
      .insert({
        recipient_id: recipientId,
        subscription_id: subscription.id,
        hotel_id: subscription.hotel_id,
        user_id: subscription.user_id,
        status: 'prepared',
      })
      .select('id')
      .maybeSingle()

    if (insertError) {
      if (insertError.code === '23505') return { skipped: true, duplicate: true }
      throw insertError
    }
    deliveryId = inserted?.id || null
  }

  try {
    const result = await webpush.sendNotification(
      {
        endpoint: subscription.endpoint,
        keys: {
          p256dh: subscription.p256dh,
          auth: subscription.auth_secret,
        },
      },
      JSON.stringify(payload),
      {
        TTL: 120,
        urgency: 'high',
      }
    )

    await admin
      .from('background_push_subscriptions')
      .update({
        failure_count: 0,
        last_success_at: new Date().toISOString(),
        last_error_code: null,
        updated_at: new Date().toISOString(),
      })
      .eq('id', subscription.id)

    if (deliveryId) {
      await admin
        .from('background_push_deliveries')
        .update({
          status: 'sent',
          http_status: Number(result?.statusCode || 201),
          sent_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        })
        .eq('id', deliveryId)
    }

    return { sent: true }
  } catch (error: any) {
    const statusCode = Number(error?.statusCode || 0) || null
    const gone = statusCode === 404 || statusCode === 410
    const nextFailures = Number(subscription.failure_count || 0) + 1

    await admin
      .from('background_push_subscriptions')
      .update({
        is_active: gone || nextFailures >= 5 ? false : subscription.is_active,
        failure_count: nextFailures,
        last_failure_at: new Date().toISOString(),
        last_error_code: gone ? 'subscription_gone' : `push_http_${statusCode || 'error'}`,
        updated_at: new Date().toISOString(),
      })
      .eq('id', subscription.id)

    if (deliveryId) {
      await admin
        .from('background_push_deliveries')
        .update({
          status: 'failed',
          http_status: statusCode,
          error_code: gone ? 'subscription_gone' : 'push_failed',
          updated_at: new Date().toISOString(),
        })
        .eq('id', deliveryId)
    }

    return { sent: false, statusCode }
  }
}

async function handleTest(request: Request, admin: ReturnType<typeof createClient>, token: string, body: JsonRecord) {
  const user = await authorizeUser(admin, token)
  if (!user) return json(request, 401, { ok: false, error: 'Authentication required.' })

  const hotelId = String(body.hotel_id || '').trim()
  const endpoint = String(body.endpoint || '').trim()
  if (!hotelId || !endpoint) {
    return json(request, 400, { ok: false, error: 'Hotel and device subscription are required.' })
  }

  const { data: staff } = await admin
    .from('staff')
    .select('id')
    .eq('hotel_id', hotelId)
    .eq('auth_user_id', user.id)
    .eq('status', 'active')
    .maybeSingle()

  if (!staff) return json(request, 403, { ok: false, error: 'Hotel staff access required.' })

  const { data: subscription } = await admin
    .from('background_push_subscriptions')
    .select('*')
    .eq('hotel_id', hotelId)
    .eq('user_id', user.id)
    .eq('endpoint', endpoint)
    .eq('is_active', true)
    .maybeSingle()

  if (!subscription) {
    return json(request, 404, { ok: false, error: 'This device is not enabled for background notifications.' })
  }

  configureWebPush()
  const outcome = await sendOnePush(
    admin,
    subscription,
    {
      title: 'StayQR background notifications',
      body: 'This device can receive StayQR alerts while the app is in the background.',
      tag: `stayqr-test-${user.id}`,
      renotify: true,
      data: {
        url: `/?stayqr_push=1&section=profile&hotelId=${encodeURIComponent(hotelId)}`,
        test: true,
      },
    },
    null,
    false,
  )

  return json(request, outcome.sent ? 200 : 502, {
    ok: Boolean(outcome.sent),
    error: outcome.sent ? null : 'The browser push service rejected the test notification.',
  })
}

Deno.serve(async (request: Request) => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders(request) })
  }
  if (request.method !== 'POST') {
    return json(request, 405, { ok: false, error: 'Method not allowed.' })
  }

  const supabaseUrl = env('SUPABASE_URL')
  const serviceRoleKey = env('SUPABASE_SERVICE_ROLE_KEY')
  if (!supabaseUrl || !serviceRoleKey) {
    return json(request, 503, { ok: false, error: 'StayQR push service is unavailable.' })
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  })
  const token = (request.headers.get('Authorization') || '')
    .replace(/^Bearer\s+/i, '')
    .trim()

  try {
    const body = (await request.json().catch(() => ({}))) as JsonRecord

    if (body.action === 'test') {
      return await handleTest(request, admin, token, body)
    }

    const webhookSecret = env('STAYQR_PUSH_WEBHOOK_SECRET')
    const suppliedWebhookSecret = String(
      request.headers.get('x-stayqr-push-secret') || ''
    ).trim()

    if (!webhookSecret || suppliedWebhookSecret !== webhookSecret) {
      return json(request, 401, { ok: false, error: 'Webhook authorization failed.' })
    }

    const webhook = body as WebhookPayload
    if (
      webhook.type !== 'INSERT' ||
      webhook.schema !== 'public' ||
      webhook.table !== 'notification_recipients' ||
      !webhook.record?.id
    ) {
      return json(request, 202, { ok: true, skipped: true, reason: 'unsupported_event' })
    }

    const recipientId = String(webhook.record.id)
    const { data: recipient, error: recipientError } = await admin
      .from('notification_recipients')
      .select('id,outbox_id,hotel_id,user_id,title,message,severity,metadata,created_at')
      .eq('id', recipientId)
      .maybeSingle()

    if (recipientError) throw recipientError
    if (!recipient) {
      return json(request, 202, { ok: true, skipped: true, reason: 'recipient_not_found' })
    }

    const { data: outbox, error: outboxError } = await admin
      .from('notification_outbox')
      .select('id,hotel_id,event_key,source_type,source_id')
      .eq('id', recipient.outbox_id)
      .eq('hotel_id', recipient.hotel_id)
      .maybeSingle()

    if (outboxError) throw outboxError
    if (!outbox) {
      return json(request, 202, { ok: true, skipped: true, reason: 'outbox_not_found' })
    }

    // The locked foreground notification system already decided the exact user
    // recipient. Background Push must not create a second routing policy here.
    // We only verify that the bound user still has active access to this hotel.
    const { data: staff, error: staffError } = await admin
      .from('staff')
      .select('id,status')
      .eq('hotel_id', recipient.hotel_id)
      .eq('auth_user_id', recipient.user_id)
      .eq('status', 'active')
      .maybeSingle()

    if (staffError) throw staffError
    if (!staff) {
      return json(request, 202, { ok: true, skipped: true, reason: 'inactive_staff' })
    }

    const { data: subscriptions, error: subscriptionError } = await admin
      .from('background_push_subscriptions')
      .select('*')
      .eq('hotel_id', recipient.hotel_id)
      .eq('user_id', recipient.user_id)
      .eq('is_active', true)

    if (subscriptionError) throw subscriptionError
    if (!subscriptions?.length) {
      return json(request, 202, { ok: true, skipped: true, reason: 'no_active_devices' })
    }

    configureWebPush()

    const metadata = recipient.metadata && typeof recipient.metadata === 'object'
      ? recipient.metadata as JsonRecord
      : {}
    const url = notificationDestination(
      String(outbox.source_type || ''),
      String(outbox.event_key || ''),
      String(outbox.source_id || ''),
      metadata,
      String(recipient.hotel_id || ''),
    )

    const pushPayload = {
      title: String(recipient.title || 'StayQR'),
      body: String(recipient.message || 'New hotel activity'),
      tag: `stayqr-${recipient.id}`,
      renotify: true,
      requireInteraction: recipient.severity === 'critical',
      data: {
        url,
        recipient_id: recipient.id,
        hotel_id: recipient.hotel_id,
        event_key: outbox.event_key,
        source_type: outbox.source_type,
        source_id: outbox.source_id,
      },
    }

    const outcomes = []
    for (const subscription of subscriptions) {
      outcomes.push(
        await sendOnePush(
          admin,
          subscription,
          pushPayload,
          recipient.id,
          true,
        )
      )
    }

    return json(request, 200, {
      ok: true,
      attempted: subscriptions.length,
      sent: outcomes.filter((item) => item.sent).length,
      skipped: outcomes.filter((item) => item.skipped).length,
    })
  } catch (error) {
    console.error(
      'stayqr-background-push error:',
      error instanceof Error ? error.message : String(error)
    )
    return json(request, 500, {
      ok: false,
      error: 'StayQR could not deliver the background notification.',
    })
  }
})
