import { createClient } from 'npm:@supabase/supabase-js@2.106.2';
function getAllowedOrigins() {
  const configured = [
    Deno.env.get('STAYQR_APP_URL'),
    Deno.env.get('STAYQR_APP_URLS')
  ].filter(Boolean).flatMap((value)=>String(value).split(',')).map((value)=>value.trim().replace(/\/$/, '')).filter(Boolean);
  return new Set(configured.map((value)=>{
    try {
      return new URL(value).origin;
    } catch  {
      return value;
    }
  }));
}
function corsHeaders(request) {
  const requestOrigin = request.headers.get('Origin') || '';
  const allowedOrigins = getAllowedOrigins();
  const fallbackOrigin = [
    ...allowedOrigins
  ][0] || requestOrigin || '*';
  const responseOrigin = allowedOrigins.has(requestOrigin) ? requestOrigin : fallbackOrigin;
  return {
    'Access-Control-Allow-Origin': responseOrigin,
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Max-Age': '86400',
    Vary: 'Origin'
  };
}
function json(request, status, body) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders(request),
      'Content-Type': 'application/json',
      'Cache-Control': 'no-store'
    }
  });
}
async function assertPlatformAdmin(adminClient, callerId) {
  const { data, error } = await adminClient.from('platform_admins').select('user_id').eq('user_id', callerId).eq('status', 'active').maybeSingle();
  if (error) throw error;
  if (!data) {
    throw new Error('Platform Admin access is required.');
  }
}
function normalizePhone(value) {
  let digits = value.replace(/\D/g, '');
  if (digits.length === 12 && digits.startsWith('91')) {
    digits = digits.slice(2);
  }
  if (digits.length !== 10) {
    throw new Error('Customer phone must be a valid 10-digit Indian mobile number.');
  }
  return digits;
}
function validateUuid(value, fieldName) {
  const pattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  if (!pattern.test(value)) {
    throw new Error(`${fieldName} must be a valid UUID.`);
  }
  return value;
}
function providerError(body) {
  return {
    message: typeof body.message === 'string' ? body.message : undefined,
    code: typeof body.code === 'string' ? body.code : undefined,
    type: typeof body.type === 'string' ? body.type : undefined
  };
}
function safeProviderMessage(body, status) {
  const error = providerError(body);
  return error.message || error.code || error.type || `Cashfree returned HTTP ${status}.`;
}
function mapLinkStatus(value) {
  const status = String(value || '').trim().toUpperCase();
  if (status === 'PAID') return 'paid';
  if (status === 'PARTIALLY_PAID') return 'partially_paid';
  if (status === 'EXPIRED') return 'expired';
  if (status === 'CANCELLED') return 'cancelled';
  if (status === 'ACTIVE') return 'issued';
  return 'created';
}
Deno.serve(async (request)=>{
  if (request.method === 'OPTIONS') {
    return new Response('ok', {
      headers: corsHeaders(request)
    });
  }
  if (request.method !== 'POST') {
    return json(request, 405, {
      error: 'Method not allowed.'
    });
  }
  let ledgerId = null;
  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const cashfreeClientId = Deno.env.get('CASHFREE_CLIENT_ID');
    const cashfreeClientSecret = Deno.env.get('CASHFREE_CLIENT_SECRET');
    const cashfreeMode = (Deno.env.get('CASHFREE_MODE') || '').trim().toLowerCase();
    const cashfreeApiBaseUrl = (Deno.env.get('CASHFREE_API_BASE_URL') || 'https://sandbox.cashfree.com/pg').replace(/\/$/, '');
    const cashfreeApiVersion = (Deno.env.get('CASHFREE_API_VERSION') || '2025-01-01').trim();
    if (!supabaseUrl || !anonKey || !serviceRoleKey) {
      throw new Error('The Supabase Edge Function environment is incomplete.');
    }
    if (!cashfreeClientId || !cashfreeClientSecret || !cashfreeMode || !cashfreeApiBaseUrl || !cashfreeApiVersion) {
      throw new Error('The Cashfree Edge Function environment is incomplete.');
    }
    if (cashfreeMode === 'test' && !cashfreeApiBaseUrl.includes('sandbox.cashfree.com')) {
      throw new Error('Cashfree test mode must use the sandbox API base URL.');
    }
    const authorization = request.headers.get('Authorization') || '';
    const token = authorization.replace(/^Bearer\s+/i, '').trim();
    if (!token) {
      return json(request, 401, {
        error: 'Authentication is required.'
      });
    }
    const authClient = createClient(supabaseUrl, anonKey, {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
        detectSessionInUrl: false
      }
    });
    const adminClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
        detectSessionInUrl: false
      }
    });
    const { data: { user: caller }, error: callerError } = await authClient.auth.getUser(token);
    if (callerError || !caller) {
      return json(request, 401, {
        error: 'Your StayQR session is invalid or expired.'
      });
    }
    await assertPlatformAdmin(adminClient, caller.id);
    const body = await request.json().catch(()=>({}));
    const hotelId = validateUuid(String(body.hotel_id || '').trim(), 'hotel_id');
    const planId = validateUuid(String(body.plan_id || '').trim(), 'plan_id');
    const billingCycle = body.billing_cycle === 'annual' ? 'annual' : 'monthly';
    const customerName = String(body.customer_name || '').trim();
    const customerEmail = String(body.customer_email || '').trim().toLowerCase();
    const customerPhone = normalizePhone(String(body.customer_phone || ''));
    const expiresInDays = Math.max(1, Math.min(Number.isFinite(Number(body.expires_in_days)) ? Math.trunc(Number(body.expires_in_days)) : 7, 30));
    const requestId = validateUuid(String(body.request_id || crypto.randomUUID()).trim(), 'request_id');
    if (customerName.length < 2 || customerName.length > 100) {
      throw new Error('Customer name must contain between 2 and 100 characters.');
    }
    if (customerEmail && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(customerEmail)) {
      throw new Error('Customer email is invalid.');
    }
    const { data: existingLink, error: existingError } = await adminClient.from('subscription_payment_links').select('id, hotel_id, plan_id, subscription_id, provider, provider_link_id, reference_id, status, billing_cycle, currency_code, amount_minor, provider_url, expires_at, paid_at, failure_reason, created_at').eq('idempotency_key', requestId).maybeSingle();
    if (existingError) throw existingError;
    if (existingLink) {
      return json(request, 200, {
        ok: true,
        idempotent: true,
        payment_link: existingLink
      });
    }
    const { data: hotel, error: hotelError } = await adminClient.from('hotels').select('id, hotel_name, slug, status, subscription_status').eq('id', hotelId).single();
    if (hotelError || !hotel) {
      throw new Error('The selected StayQR hotel was not found.');
    }
    const { data: plan, error: planError } = await adminClient.from('subscription_plans').select('id, plan_name, plan_code, price_monthly, price_annual, currency_code, status').eq('id', planId).eq('status', 'active').single();
    if (planError || !plan) {
      throw new Error('The selected active StayQR subscription plan was not found.');
    }
    const amountMajor = Number(billingCycle === 'annual' ? plan.price_annual : plan.price_monthly);
    const currencyCode = String(plan.currency_code || 'INR').toUpperCase();
    if (!Number.isFinite(amountMajor) || amountMajor <= 0) {
      throw new Error(`The ${billingCycle} price is not configured for this plan.`);
    }
    if (currencyCode !== 'INR') {
      throw new Error('The current Cashfree sandbox integration supports INR plans only.');
    }
    const amountMinor = Math.round(amountMajor * 100);
    const expiryDate = new Date(Date.now() + expiresInDays * 24 * 60 * 60 * 1000);
    const compactRequestId = requestId.replaceAll('-', '');
    const providerReference = `stayqr_${hotelId.slice(0, 8)}_${compactRequestId.slice(0, 24)}`;
    const { data: currentSubscription, error: subscriptionError } = await adminClient.from('hotel_subscriptions').select('id, status, plan_id, billing_mode').eq('hotel_id', hotelId).in('status', [
      'trial',
      'trialing',
      'active',
      'past_due',
      'suspended'
    ]).order('updated_at', {
      ascending: false
    }).limit(1).maybeSingle();
    if (subscriptionError) throw subscriptionError;
    const { data: insertedLedger, error: ledgerError } = await adminClient.from('subscription_payment_links').insert({
      hotel_id: hotelId,
      plan_id: planId,
      subscription_id: currentSubscription?.id || null,
      provider: 'cashfree',
      reference_id: providerReference,
      idempotency_key: requestId,
      status: 'creating',
      billing_cycle: billingCycle,
      currency_code: currencyCode,
      amount_minor: amountMinor,
      customer_name: customerName,
      customer_email: customerEmail || null,
      customer_phone: customerPhone,
      expires_at: expiryDate.toISOString(),
      metadata: {
        source: 'cashfree-create-payment-link',
        cashfree_mode: cashfreeMode,
        cashfree_api_version: cashfreeApiVersion
      },
      created_by: caller.id,
      updated_by: caller.id
    }).select('id').single();
    if (ledgerError || !insertedLedger) {
      throw ledgerError || new Error('Could not create the StayQR payment-link ledger record.');
    }
    ledgerId = insertedLedger.id;
    const returnUrlRaw = Deno.env.get('STAYQR_APP_URL') || [
      ...getAllowedOrigins()
    ][0] || '';
    const linkNotes = {
      stayqr_hotel_id: hotelId,
      stayqr_plan_id: planId,
      stayqr_billing_cycle: billingCycle,
      stayqr_ledger_id: ledgerId
    };
    if (currentSubscription?.id) {
      linkNotes.stayqr_subscription_id = currentSubscription.id;
    }
    const linkMeta = {
      notify_url: `${supabaseUrl}/functions/v1/cashfree-webhook`,
      upi_intent: false
    };
    if (returnUrlRaw) {
      try {
        linkMeta.return_url = new URL(returnUrlRaw).toString();
      } catch  {
      // Ignore an invalid optional return URL. The payment link still works.
      }
    }
    const providerPayload = {
      customer_details: {
        customer_name: customerName,
        customer_phone: customerPhone,
        ...customerEmail ? {
          customer_email: customerEmail
        } : {}
      },
      link_amount: amountMinor / 100,
      link_currency: currencyCode,
      link_id: providerReference,
      link_purpose: `StayQR ${plan.plan_name} ${billingCycle} billing for ${hotel.hotel_name}`,
      link_expiry_time: expiryDate.toISOString(),
      link_partial_payments: false,
      link_auto_reminders: true,
      link_notify: {
        send_email: customerEmail ? body.send_email !== false : false,
        send_sms: body.send_sms === true,
        send_whatsapp: body.send_whatsapp === true
      },
      link_notes: linkNotes,
      link_meta: linkMeta,
      enable_invoice: false
    };
    const providerHeaders = {
      Accept: 'application/json',
      'Content-Type': 'application/json',
      'x-api-version': cashfreeApiVersion,
      'x-client-id': cashfreeClientId,
      'x-client-secret': cashfreeClientSecret,
      'x-request-id': requestId,
      'x-idempotency-key': requestId
    };
    let providerResponse = await fetch(`${cashfreeApiBaseUrl}/links`, {
      method: 'POST',
      headers: providerHeaders,
      body: JSON.stringify(providerPayload),
      signal: AbortSignal.timeout(20000)
    });
    let providerBody = await providerResponse.json().catch(()=>({}));
    // A network retry or dashboard action may have created the same merchant
    // link ID. Resolve that safely by fetching the link instead of creating a
    // duplicate record.
    if (providerResponse.status === 409) {
      const fetchedResponse = await fetch(`${cashfreeApiBaseUrl}/links/${providerReference}`, {
        method: 'GET',
        headers: providerHeaders,
        signal: AbortSignal.timeout(15000)
      });
      if (fetchedResponse.ok) {
        providerResponse = fetchedResponse;
        providerBody = await fetchedResponse.json().catch(()=>({}));
      }
    }
    if (!providerResponse.ok) {
      const failureReason = safeProviderMessage(providerBody, providerResponse.status);
      const providerFailure = providerError(providerBody);
      await adminClient.from('subscription_payment_links').update({
        status: 'failed',
        failed_at: new Date().toISOString(),
        failure_reason: failureReason,
        metadata: {
          source: 'cashfree-create-payment-link',
          cashfree_mode: cashfreeMode,
          cashfree_api_version: cashfreeApiVersion,
          provider_http_status: providerResponse.status,
          provider_error_code: providerFailure.code || null,
          provider_error_type: providerFailure.type || null,
          request_id: requestId
        },
        updated_by: caller.id
      }).eq('id', ledgerId);
      return json(request, 502, {
        ok: false,
        provider: 'cashfree',
        mode: cashfreeMode,
        error: failureReason,
        provider_http_status: providerResponse.status,
        request_id: requestId
      });
    }
    const providerLinkId = String(providerBody.link_id || providerReference);
    const providerUrl = String(providerBody.link_url || '');
    const providerStatus = mapLinkStatus(providerBody.link_status);
    if (!providerUrl) {
      throw new Error('Cashfree created the link but did not return link_url.');
    }
    const { data: savedLink, error: saveError } = await adminClient.from('subscription_payment_links').update({
      provider_link_id: providerLinkId,
      status: providerStatus,
      provider_url: providerUrl,
      expires_at: String(providerBody.link_expiry_time || '') || expiryDate.toISOString(),
      metadata: {
        source: 'cashfree-create-payment-link',
        cashfree_mode: cashfreeMode,
        cashfree_api_version: cashfreeApiVersion,
        cashfree_cf_link_id: providerBody.cf_link_id || null,
        cashfree_link_status: providerBody.link_status || null,
        request_id: requestId
      },
      updated_by: caller.id
    }).eq('id', ledgerId).select('id, hotel_id, plan_id, subscription_id, provider, provider_link_id, reference_id, status, billing_cycle, currency_code, amount_minor, provider_url, expires_at, created_at').single();
    if (saveError || !savedLink) {
      throw saveError || new Error('Cashfree link was created, but StayQR could not save the provider response.');
    }
    const { error: priceMapError } = await adminClient.from('subscription_plan_prices').upsert({
      plan_id: planId,
      provider: 'cashfree',
      billing_cycle: billingCycle,
      currency_code: currencyCode,
      amount_minor: amountMinor,
      provider_plan_id: null,
      status: 'active',
      metadata: {
        source: 'cashfree-payment-link',
        cashfree_mode: cashfreeMode
      },
      created_by: caller.id,
      updated_by: caller.id
    }, {
      onConflict: 'plan_id,provider,billing_cycle,currency_code'
    });
    if (priceMapError) {
      console.error('Cashfree price mapping warning:', priceMapError.message);
    }
    return json(request, 200, {
      ok: true,
      provider: 'cashfree',
      mode: cashfreeMode,
      idempotent: false,
      request_id: requestId,
      payment_link: savedLink
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unexpected Cashfree payment-link error.';
    const status = message.includes('Platform Admin access') ? 403 : message.includes('session is invalid') || message.includes('Authentication is required') ? 401 : 400;
    return json(request, status, {
      ok: false,
      error: message,
      ledger_id: ledgerId
    });
  }
});
