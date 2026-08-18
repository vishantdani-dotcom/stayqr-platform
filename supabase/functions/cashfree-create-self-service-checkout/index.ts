import { createClient } from 'npm:@supabase/supabase-js@2.106.2'

function configuredOrigins() {
  return [Deno.env.get('STAYQR_APP_URL'), Deno.env.get('STAYQR_APP_URLS')]
    .filter(Boolean)
    .flatMap((value) => String(value).split(','))
    .map((value) => value.trim().replace(/\/$/, ''))
    .filter(Boolean)
}

function getAllowedOrigins() {
  return new Set(configuredOrigins().map((value) => {
    try {
      return new URL(value).origin
    } catch {
      return value
    }
  }))
}

function corsHeaders(request: Request) {
  const requestOrigin = request.headers.get('Origin') || ''
  const allowedOrigins = getAllowedOrigins()
  const fallbackOrigin = [...allowedOrigins][0] || requestOrigin || '*'
  const responseOrigin = allowedOrigins.has(requestOrigin) ? requestOrigin : fallbackOrigin

  return {
    'Access-Control-Allow-Origin': responseOrigin,
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Max-Age': '86400',
    Vary: 'Origin',
  }
}

function json(request: Request, status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders(request),
      'Content-Type': 'application/json',
      'Cache-Control': 'no-store',
    },
  })
}

function validateUuid(value: string, fieldName: string) {
  const pattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
  if (!pattern.test(value)) throw new Error(`${fieldName} must be a valid UUID.`)
  return value
}

function normalizePhone(value: string) {
  let digits = value.replace(/\D/g, '')
  if (digits.length === 12 && digits.startsWith('91')) digits = digits.slice(2)
  if (digits.length !== 10) {
    throw new Error('Enter a valid 10-digit Indian mobile number.')
  }
  return digits
}

function cleanText(value: unknown, fieldName: string, min: number, max: number) {
  const cleaned = String(value || '').trim()
  if (cleaned.length < min || cleaned.length > max) {
    throw new Error(`${fieldName} must contain between ${min} and ${max} characters.`)
  }
  return cleaned
}

function providerError(body: Record<string, unknown>) {
  return {
    message: typeof body.message === 'string' ? body.message : undefined,
    code: typeof body.code === 'string' ? body.code : undefined,
    type: typeof body.type === 'string' ? body.type : undefined,
  }
}

function safeProviderMessage(body: Record<string, unknown>, status: number) {
  const error = providerError(body)
  return error.message || error.code || error.type || `Cashfree returned HTTP ${status}.`
}

function mapLinkStatus(value: unknown) {
  const status = String(value || '').trim().toUpperCase()
  if (status === 'PARTIALLY_PAID') return 'partially_paid'
  if (status === 'EXPIRED') return 'expired'
  if (status === 'CANCELLED') return 'cancelled'
  if (status === 'PAID') return 'paid'
  if (status === 'ACTIVE') return 'issued'
  return 'creating'
}

function safeAppUrl() {
  const candidate = configuredOrigins()[0] || ''
  try {
    return new URL(candidate).origin
  } catch {
    return ''
  }
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders(request) })
  }

  if (request.method !== 'POST') {
    return json(request, 405, { ok: false, error: 'Method not allowed.' })
  }

  let intentId: string | null = null

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
    const cashfreeClientId = Deno.env.get('CASHFREE_CLIENT_ID')
    const cashfreeClientSecret = Deno.env.get('CASHFREE_CLIENT_SECRET')
    const cashfreeMode = (Deno.env.get('CASHFREE_MODE') || '').trim().toLowerCase()
    const cashfreeApiBaseUrl = (Deno.env.get('CASHFREE_API_BASE_URL') || 'https://sandbox.cashfree.com/pg').replace(/\/$/, '')
    const cashfreeApiVersion = (Deno.env.get('CASHFREE_API_VERSION') || '2025-01-01').trim()

    if (!supabaseUrl || !anonKey || !serviceRoleKey) {
      throw new Error('The Supabase Edge Function environment is incomplete.')
    }
    if (!cashfreeClientId || !cashfreeClientSecret || !cashfreeMode) {
      throw new Error('The Cashfree Edge Function environment is incomplete.')
    }
    if (!['test', 'live', 'production'].includes(cashfreeMode)) {
      throw new Error('CASHFREE_MODE must be test, live or production.')
    }
    if (cashfreeMode === 'test' && !cashfreeApiBaseUrl.includes('sandbox.cashfree.com')) {
      throw new Error('Cashfree test mode must use the sandbox API base URL.')
    }

    const token = (request.headers.get('Authorization') || '')
      .replace(/^Bearer\s+/i, '')
      .trim()

    if (!token) {
      return json(request, 401, { ok: false, error: 'Authentication is required.' })
    }

    const authClient = createClient(supabaseUrl, anonKey, {
      auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false },
    })
    const adminClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false },
    })

    const { data: { user: caller }, error: callerError } = await authClient.auth.getUser(token)
    if (callerError || !caller?.email) {
      return json(request, 401, { ok: false, error: 'Your StayQR session is invalid or expired.' })
    }

    const body = await request.json().catch(() => ({}))
    const requestId = validateUuid(String(body.request_id || crypto.randomUUID()).trim(), 'request_id')
    intentId = requestId
    const planId = validateUuid(String(body.plan_id || '').trim(), 'plan_id')
    const billingCycle = body.billing_cycle === 'annual' ? 'annual' : 'monthly'
    const hotelName = cleanText(body.hotel_name, 'Hotel name', 2, 160)
    const ownerName = cleanText(body.owner_name, 'Owner name', 2, 120)
    const customerPhone = normalizePhone(String(body.phone || ''))
    const customerEmail = caller.email.trim().toLowerCase()
    const expiresInDays = 2

    const { data: existingIntent, error: existingError } = await adminClient
      .from('self_service_acquisition_intents')
      .select('id, owner_user_id, status, provider_url, expires_at, failure_reason, plan_id, billing_cycle, amount_minor, currency_code')
      .eq('id', requestId)
      .maybeSingle()

    if (existingError) throw existingError
    let resumeIntent = false
    if (existingIntent) {
      if (existingIntent.owner_user_id !== caller.id) {
        return json(request, 403, { ok: false, error: 'This checkout request belongs to another account.' })
      }
      if (existingIntent.plan_id !== planId || existingIntent.billing_cycle !== billingCycle) {
        return json(request, 409, { ok: false, error: 'This checkout request does not match the selected plan.' })
      }
      if (existingIntent.provider_url || ['paid', 'provisioning', 'completed'].includes(existingIntent.status)) {
        return json(request, 200, {
          ok: true,
          idempotent: true,
          intent: existingIntent,
        })
      }
      if (['failed', 'expired', 'cancelled', 'partially_paid'].includes(existingIntent.status)) {
        return json(request, 409, {
          ok: false,
          restart_allowed: existingIntent.status !== 'partially_paid',
          intent: existingIntent,
          error: existingIntent.status === 'partially_paid'
            ? 'This checkout has a partial payment and requires StayQR support.'
            : 'This checkout can no longer be used. Start a new checkout.',
        })
      }
      resumeIntent = true
    }

    const { data: existingStaff, error: staffError } = await adminClient
      .from('staff')
      .select('id')
      .eq('auth_user_id', caller.id)
      .in('status', ['active', 'invited'])
      .limit(1)
      .maybeSingle()

    if (staffError) throw staffError
    if (existingStaff) {
      return json(request, 409, {
        ok: false,
        error: 'This account already has hotel access. Manage plan changes from the hotel account.',
      })
    }

    const { data: plan, error: planError } = await adminClient
      .from('subscription_plans')
      .select('id, plan_code, plan_name, price_monthly, price_annual, currency_code, status, is_public')
      .eq('id', planId)
      .eq('status', 'active')
      .eq('is_public', true)
      .single()

    if (planError || !plan) {
      throw new Error('The selected public StayQR subscription plan is unavailable.')
    }

    const amountMajor = Number(billingCycle === 'annual' ? plan.price_annual : plan.price_monthly)
    const currencyCode = String(plan.currency_code || 'INR').toUpperCase()
    if (!Number.isFinite(amountMajor) || amountMajor <= 0) {
      throw new Error(`The ${billingCycle} price is not configured for this plan.`)
    }
    if (currencyCode !== 'INR') {
      throw new Error('The current Cashfree checkout supports INR plans only.')
    }

    const amountMinor = Math.round(amountMajor * 100)
    if (
      existingIntent &&
      (
        Number(existingIntent.amount_minor) !== amountMinor ||
        String(existingIntent.currency_code || '').toUpperCase() !== currencyCode
      )
    ) {
      return json(request, 409, {
        ok: false,
        error: 'The server price changed after this checkout started. Start a new checkout.',
        restart_allowed: true,
        intent: existingIntent,
      })
    }

    const expiryDate = new Date(
      existingIntent?.expires_at || Date.now() + expiresInDays * 24 * 60 * 60 * 1000
    )
    const compactRequestId = requestId.replaceAll('-', '')
    const providerReference = `stayqr_acq_${compactRequestId.slice(0, 28)}`
    const appUrl = safeAppUrl()

    if (!resumeIntent) {
      const { error: intentError } = await adminClient
        .from('self_service_acquisition_intents')
        .insert({
          id: requestId,
          owner_user_id: caller.id,
          plan_id: plan.id,
          acquisition_mode: 'paid',
          billing_cycle: billingCycle,
          status: 'creating',
          provider: 'cashfree',
          reference_id: providerReference,
          amount_minor: amountMinor,
          currency_code: currencyCode,
          hotel_name: hotelName,
          owner_name: ownerName,
          contact_email: customerEmail,
          customer_phone: customerPhone,
          expires_at: expiryDate.toISOString(),
          metadata: {
            source: 'cashfree-create-self-service-checkout',
            cashfree_mode: cashfreeMode,
            cashfree_api_version: cashfreeApiVersion,
          },
        })

      if (intentError) throw intentError
    }

    const linkMeta: Record<string, unknown> = {
      notify_url: `${supabaseUrl}/functions/v1/cashfree-webhook`,
      upi_intent: false,
    }
    if (appUrl) {
      linkMeta.return_url = `${appUrl}/checkout/success?intent=${requestId}`
    }

    const providerPayload = {
      customer_details: {
        customer_name: ownerName,
        customer_email: customerEmail,
        customer_phone: customerPhone,
      },
      link_amount: amountMinor / 100,
      link_currency: currencyCode,
      link_id: providerReference,
      link_purpose: `StayQR ${plan.plan_name} ${billingCycle} plan for ${hotelName}`,
      link_expiry_time: expiryDate.toISOString(),
      link_partial_payments: false,
      link_auto_reminders: true,
      link_notify: { send_email: true, send_sms: false, send_whatsapp: false },
      link_notes: {
        stayqr_acquisition_intent_id: requestId,
        stayqr_plan_id: plan.id,
        stayqr_billing_cycle: billingCycle,
      },
      link_meta: linkMeta,
      enable_invoice: false,
    }

    const providerHeaders = {
      Accept: 'application/json',
      'Content-Type': 'application/json',
      'x-api-version': cashfreeApiVersion,
      'x-client-id': cashfreeClientId,
      'x-client-secret': cashfreeClientSecret,
      'x-request-id': requestId,
      'x-idempotency-key': requestId,
    }

    let providerResponse = await fetch(`${cashfreeApiBaseUrl}/links`, {
      method: 'POST',
      headers: providerHeaders,
      body: JSON.stringify(providerPayload),
      signal: AbortSignal.timeout(20000),
    })
    let providerBody = await providerResponse.json().catch(() => ({}))

    if (providerResponse.status === 409) {
      const fetchedResponse = await fetch(`${cashfreeApiBaseUrl}/links/${providerReference}`, {
        method: 'GET',
        headers: providerHeaders,
        signal: AbortSignal.timeout(15000),
      })
      if (fetchedResponse.ok) {
        providerResponse = fetchedResponse
        providerBody = await fetchedResponse.json().catch(() => ({}))
      }
    }

    if (!providerResponse.ok) {
      const failureReason = safeProviderMessage(providerBody, providerResponse.status)
      const providerFailure = providerError(providerBody)
      await adminClient
        .from('self_service_acquisition_intents')
        .update({
          status: 'failed',
          failure_reason: failureReason,
          metadata: {
            source: 'cashfree-create-self-service-checkout',
            cashfree_mode: cashfreeMode,
            provider_http_status: providerResponse.status,
            provider_error_code: providerFailure.code || null,
            provider_error_type: providerFailure.type || null,
          },
          updated_at: new Date().toISOString(),
        })
        .eq('id', requestId)

      return json(request, 502, {
        ok: false,
        provider: 'cashfree',
        error: failureReason,
        intent_id: requestId,
        restart_allowed: true,
      })
    }

    const providerLinkId = String(providerBody.link_id || providerReference)
    const providerUrl = String(providerBody.link_url || '')
    if (!providerUrl) throw new Error('Cashfree created the checkout but did not return a payment URL.')

    const { data: savedIntent, error: saveError } = await adminClient
      .from('self_service_acquisition_intents')
      .update({
        provider_link_id: providerLinkId,
        provider_url: providerUrl,
        status: mapLinkStatus(providerBody.link_status),
        expires_at: String(providerBody.link_expiry_time || '') || expiryDate.toISOString(),
        metadata: {
          source: 'cashfree-create-self-service-checkout',
          cashfree_mode: cashfreeMode,
          cashfree_api_version: cashfreeApiVersion,
          cashfree_cf_link_id: providerBody.cf_link_id || null,
          cashfree_link_status: providerBody.link_status || null,
        },
        updated_at: new Date().toISOString(),
      })
      .eq('id', requestId)
      .select('id, status, provider_url, expires_at, plan_id, billing_cycle, amount_minor, currency_code')
      .single()

    if (saveError || !savedIntent) {
      throw saveError || new Error('Cashfree checkout was created but StayQR could not save it.')
    }

    return json(request, 200, {
      ok: true,
      provider: 'cashfree',
      mode: cashfreeMode,
      idempotent: resumeIntent,
      intent: savedIntent,
    })
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unexpected Cashfree checkout error.'

    if (intentId) {
      try {
        const supabaseUrl = Deno.env.get('SUPABASE_URL')
        const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
        if (supabaseUrl && serviceRoleKey) {
          const adminClient = createClient(supabaseUrl, serviceRoleKey, {
            auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false },
          })
          await adminClient
            .from('self_service_acquisition_intents')
            .update({ status: 'failed', failure_reason: message, updated_at: new Date().toISOString() })
            .eq('id', intentId)
            .eq('status', 'creating')
        }
      } catch (ledgerError) {
        console.error('Could not update failed acquisition intent:', ledgerError)
      }
    }

    const status = message.includes('session is invalid') || message.includes('Authentication is required')
      ? 401
      : 400
    return json(request, status, { ok: false, error: message, intent_id: intentId })
  }
})
