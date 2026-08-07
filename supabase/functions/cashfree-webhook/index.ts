import { createClient } from 'npm:@supabase/supabase-js@2.106.2';
function json(status, body) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'Content-Type': 'application/json',
      'Cache-Control': 'no-store'
    }
  });
}
function asObject(value) {
  return value && typeof value === 'object' && !Array.isArray(value) ? value : {};
}
function stringValue(value) {
  return value === null || value === undefined ? '' : String(value).trim();
}
function safeDate(value) {
  const raw = stringValue(value);
  if (!raw) return new Date();
  const parsed = new Date(raw);
  return Number.isNaN(parsed.getTime()) ? new Date() : parsed;
}
function addBillingPeriod(start, billingCycle) {
  const end = new Date(start);
  if (billingCycle === 'annual') {
    end.setUTCFullYear(end.getUTCFullYear() + 1);
  } else {
    end.setUTCMonth(end.getUTCMonth() + 1);
  }
  return end;
}
function constantTimeEqual(left, right) {
  const leftBytes = new TextEncoder().encode(left);
  const rightBytes = new TextEncoder().encode(right);
  if (leftBytes.length !== rightBytes.length) return false;
  let difference = 0;
  for(let index = 0; index < leftBytes.length; index += 1){
    difference |= leftBytes[index] ^ rightBytes[index];
  }
  return difference === 0;
}
async function hmacBase64(secret, value) {
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(secret), {
    name: 'HMAC',
    hash: 'SHA-256'
  }, false, [
    'sign'
  ]);
  const signature = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(value));
  const bytes = new Uint8Array(signature);
  let binary = '';
  for (const byte of bytes){
    binary += String.fromCharCode(byte);
  }
  return btoa(binary);
}
async function sha256Hex(value) {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
  return [
    ...new Uint8Array(digest)
  ].map((byte)=>byte.toString(16).padStart(2, '0')).join('');
}
function parseRawPayload(rawBody, contentType) {
  try {
    return asObject(JSON.parse(rawBody));
  } catch  {
    // Older Payment Link webhook documentation mentions form-data delivery.
    // Preserve the exact raw body for signature verification, then support a
    // URL-encoded wrapper as a compatibility fallback.
    if (contentType.includes('application/x-www-form-urlencoded') || rawBody.includes('=')) {
      const params = new URLSearchParams(rawBody);
      const payloadValue = params.get('payload') || params.get('data') || params.get('event');
      if (payloadValue) {
        try {
          return asObject(JSON.parse(payloadValue));
        } catch  {
        // Continue to the flat-object fallback below.
        }
      }
      return Object.fromEntries(params.entries());
    }
    throw new Error('Cashfree webhook body is not valid JSON.');
  }
}
function buildProviderEventId(payload, payloadHash) {
  const data = asObject(payload.data);
  const order = asObject(data.order);
  const linkId = stringValue(data.link_id);
  const status = stringValue(data.link_status).toUpperCase();
  const transactionId = stringValue(order.transaction_id) || stringValue(order.order_id);
  const eventTime = stringValue(payload.event_time);
  const identity = [
    'payment_link',
    linkId || stringValue(data.cf_link_id),
    status || stringValue(payload.type),
    transactionId || eventTime || payloadHash.slice(0, 24)
  ].map((value)=>value.replace(/[^a-zA-Z0-9_.:-]/g, '_')).filter(Boolean).join(':');
  return identity || `payload:${payloadHash}`;
}
async function findPaymentLink(adminClient, linkId) {
  const selection = [
    'id',
    'hotel_id',
    'plan_id',
    'subscription_id',
    'provider',
    'provider_link_id',
    'reference_id',
    'status',
    'billing_cycle',
    'currency_code',
    'amount_minor',
    'provider_payment_id',
    'provider_url',
    'expires_at',
    'paid_at',
    'cancelled_at',
    'failed_at',
    'failure_reason',
    'metadata'
  ].join(',');
  const byProviderId = await adminClient.from('subscription_payment_links').select(selection).eq('provider', 'cashfree').eq('provider_link_id', linkId).maybeSingle();
  if (byProviderId.error) throw byProviderId.error;
  if (byProviderId.data) return byProviderId.data;
  const byReference = await adminClient.from('subscription_payment_links').select(selection).eq('provider', 'cashfree').eq('reference_id', linkId).maybeSingle();
  if (byReference.error) throw byReference.error;
  return byReference.data;
}
async function markWebhook(adminClient, webhookId, values) {
  const { error } = await adminClient.from('webhook_events').update({
    ...values,
    updated_at: new Date().toISOString()
  }).eq('id', webhookId);
  if (error) throw error;
}
Deno.serve(async (request)=>{
  if (request.method !== 'POST') {
    return json(405, {
      ok: false,
      error: 'Method not allowed.'
    });
  }
  const receivedAt = new Date();
  let webhookId = null;
  let providerEventId = null;
  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const cashfreeClientSecret = Deno.env.get('CASHFREE_CLIENT_SECRET');
    if (!supabaseUrl || !serviceRoleKey || !cashfreeClientSecret) {
      throw new Error('The Cashfree webhook environment is incomplete.');
    }
    const timestamp = stringValue(request.headers.get('x-webhook-timestamp'));
    const receivedSignature = stringValue(request.headers.get('x-webhook-signature'));
    const contentType = stringValue(request.headers.get('content-type')).toLowerCase();
    const rawBody = await request.text();
    const payloadHash = await sha256Hex(rawBody);
    if (!timestamp || !receivedSignature || !rawBody) {
      return json(400, {
        ok: false,
        error: 'Cashfree webhook signature, timestamp and body are required.'
      });
    }
    const expectedSignature = await hmacBase64(cashfreeClientSecret, `${timestamp}${rawBody}`);
    if (!constantTimeEqual(expectedSignature, receivedSignature)) {
      return json(401, {
        ok: false,
        error: 'Cashfree webhook signature is invalid.'
      });
    }
    const payload = parseRawPayload(rawBody, contentType);
    const eventType = stringValue(payload.type) || 'UNKNOWN_CASHFREE_EVENT';
    providerEventId = buildProviderEventId(payload, payloadHash);
    const adminClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
        detectSessionInUrl: false
      }
    });
    const { data: existingEvent, error: existingError } = await adminClient.from('webhook_events').select('id, processing_status, attempts, hotel_id, subscription_id, processed_at').eq('provider', 'cashfree').eq('provider_event_id', providerEventId).maybeSingle();
    if (existingError) throw existingError;
    if (existingEvent && [
      'processed',
      'ignored'
    ].includes(existingEvent.processing_status)) {
      return json(200, {
        ok: true,
        provider: 'cashfree',
        idempotent: true,
        provider_event_id: providerEventId,
        processing_status: existingEvent.processing_status
      });
    }
    const safeHeaders = {
      content_type: contentType || null,
      x_webhook_timestamp: timestamp,
      x_webhook_version: request.headers.get('x-webhook-version'),
      x_webhook_attempt: request.headers.get('x-webhook-attempt')
    };
    if (existingEvent) {
      webhookId = existingEvent.id;
      await markWebhook(adminClient, webhookId, {
        processing_status: 'processing',
        signature_valid: true,
        payload_hash: payloadHash,
        payload,
        headers: safeHeaders,
        attempts: Number(existingEvent.attempts || 0) + 1,
        last_error: null,
        processing_started_at: new Date().toISOString(),
        next_retry_at: null
      });
    } else {
      const { data: insertedEvent, error: insertError } = await adminClient.from('webhook_events').insert({
        provider: 'cashfree',
        provider_event_id: providerEventId,
        event_type: eventType,
        processing_status: 'processing',
        signature_valid: true,
        payload_hash: payloadHash,
        payload,
        headers: safeHeaders,
        attempts: 1,
        received_at: receivedAt.toISOString(),
        processing_started_at: new Date().toISOString(),
        metadata: {
          cashfree_event_time: stringValue(payload.event_time) || null,
          cashfree_version: payload.version ?? null
        }
      }).select('id').single();
      if (insertError || !insertedEvent) {
        // Another delivery may have inserted the same unique provider event.
        if (insertError?.code === '23505') {
          const { data: racedEvent, error: raceError } = await adminClient.from('webhook_events').select('id, processing_status').eq('provider', 'cashfree').eq('provider_event_id', providerEventId).single();
          if (raceError) throw raceError;
          return json(200, {
            ok: true,
            provider: 'cashfree',
            idempotent: true,
            provider_event_id: providerEventId,
            processing_status: racedEvent.processing_status
          });
        }
        throw insertError || new Error('Could not create the webhook ledger record.');
      }
      webhookId = insertedEvent.id;
    }
    if (eventType !== 'PAYMENT_LINK_EVENT') {
      await markWebhook(adminClient, webhookId, {
        processing_status: 'ignored',
        processed_at: new Date().toISOString(),
        metadata: {
          cashfree_event_time: stringValue(payload.event_time) || null,
          ignored_reason: 'Only PAYMENT_LINK_EVENT is handled by this endpoint.'
        }
      });
      return json(200, {
        ok: true,
        provider: 'cashfree',
        ignored: true,
        provider_event_id: providerEventId,
        event_type: eventType
      });
    }
    const data = asObject(payload.data);
    const order = asObject(data.order);
    const linkId = stringValue(data.link_id);
    const linkStatus = stringValue(data.link_status).toUpperCase();
    if (!linkId || !linkStatus) {
      throw new Error('Cashfree Payment Link webhook is missing link_id or link_status.');
    }
    const paymentLink = await findPaymentLink(adminClient, linkId);
    // Cashfree's dashboard test can send a valid signed sample that does not
    // correspond to a real StayQR link. Acknowledge it safely.
    if (!paymentLink) {
      await markWebhook(adminClient, webhookId, {
        processing_status: 'ignored',
        processed_at: new Date().toISOString(),
        metadata: {
          ignored_reason: 'No matching StayQR Cashfree payment link was found.',
          cashfree_link_id: linkId,
          cashfree_link_status: linkStatus
        }
      });
      return json(200, {
        ok: true,
        provider: 'cashfree',
        ignored: true,
        provider_event_id: providerEventId,
        link_id: linkId
      });
    }
    const eventDate = safeDate(payload.event_time);
    const existingMetadata = asObject(paymentLink.metadata);
    const transactionId = stringValue(order.transaction_id) || stringValue(order.order_id) || stringValue(data.cf_link_id);
    const paidAmountMinor = Math.round(Number(data.link_amount_paid || 0) * 100);
    const currencyCode = stringValue(data.link_currency).toUpperCase();
    const commonMetadata = {
      ...existingMetadata,
      last_cashfree_webhook_id: webhookId,
      last_cashfree_event_id: providerEventId,
      last_cashfree_event_time: eventDate.toISOString(),
      cashfree_link_status: linkStatus,
      cashfree_cf_link_id: data.cf_link_id ?? null,
      cashfree_order_id: order.order_id ?? null,
      cashfree_transaction_id: order.transaction_id ?? null
    };
    if (linkStatus === 'PAID') {
      if (currencyCode && currencyCode !== paymentLink.currency_code) {
        throw new Error('Cashfree paid-link currency does not match the StayQR ledger.');
      }
      if (!Number.isFinite(paidAmountMinor) || paidAmountMinor < Number(paymentLink.amount_minor)) {
        throw new Error('Cashfree paid amount is lower than the StayQR payment-link amount.');
      }
      const { error: linkUpdateError } = await adminClient.from('subscription_payment_links').update({
        status: 'paid',
        provider_payment_id: transactionId,
        paid_at: eventDate.toISOString(),
        failed_at: null,
        failure_reason: null,
        metadata: commonMetadata,
        updated_at: new Date().toISOString()
      }).eq('id', paymentLink.id);
      if (linkUpdateError) throw linkUpdateError;
      const periodStart = eventDate;
      const periodEnd = addBillingPeriod(periodStart, paymentLink.billing_cycle);
      const { data: lifecycleResult, error: lifecycleError } = await adminClient.rpc('apply_provider_subscription_event', {
        payload: {
          event_action: 'payment_succeeded',
          provider: 'cashfree',
          provider_event_id: providerEventId,
          hotel_id: paymentLink.hotel_id,
          plan_id: paymentLink.plan_id,
          subscription_id: paymentLink.subscription_id,
          billing_cycle: paymentLink.billing_cycle,
          currency_code: paymentLink.currency_code,
          amount_minor: paymentLink.amount_minor,
          provider_payment_link_id: linkId,
          provider_payment_id: transactionId,
          provider_status: linkStatus,
          current_period_start: periodStart.toISOString(),
          current_period_end: periodEnd.toISOString(),
          provider_metadata: {
            cashfree_cf_link_id: data.cf_link_id ?? null,
            cashfree_order_id: order.order_id ?? null,
            cashfree_transaction_id: order.transaction_id ?? null,
            cashfree_link_amount_paid_minor: paidAmountMinor,
            webhook_id: webhookId
          }
        }
      });
      if (lifecycleError) throw lifecycleError;
      await markWebhook(adminClient, webhookId, {
        processing_status: 'processed',
        processed_at: new Date().toISOString(),
        hotel_id: paymentLink.hotel_id,
        subscription_id: lifecycleResult?.subscription_id || paymentLink.subscription_id || null,
        metadata: {
          cashfree_link_id: linkId,
          cashfree_link_status: linkStatus,
          ledger_id: paymentLink.id,
          lifecycle_result: lifecycleResult
        }
      });
      return json(200, {
        ok: true,
        provider: 'cashfree',
        idempotent: false,
        processed: true,
        provider_event_id: providerEventId,
        link_status: linkStatus,
        hotel_id: paymentLink.hotel_id,
        subscription_id: lifecycleResult?.subscription_id || paymentLink.subscription_id || null
      });
    }
    if (linkStatus === 'PARTIALLY_PAID') {
      const { error } = await adminClient.from('subscription_payment_links').update({
        status: 'partially_paid',
        metadata: {
          ...commonMetadata,
          cashfree_link_amount_paid_minor: paidAmountMinor
        },
        updated_at: new Date().toISOString()
      }).eq('id', paymentLink.id);
      if (error) throw error;
    } else if (linkStatus === 'EXPIRED') {
      const { error } = await adminClient.from('subscription_payment_links').update({
        status: 'expired',
        metadata: commonMetadata,
        updated_at: new Date().toISOString()
      }).eq('id', paymentLink.id);
      if (error) throw error;
    } else if (linkStatus === 'CANCELLED') {
      const { error } = await adminClient.from('subscription_payment_links').update({
        status: 'cancelled',
        cancelled_at: eventDate.toISOString(),
        metadata: commonMetadata,
        updated_at: new Date().toISOString()
      }).eq('id', paymentLink.id);
      if (error) throw error;
    } else {
      await markWebhook(adminClient, webhookId, {
        processing_status: 'ignored',
        processed_at: new Date().toISOString(),
        hotel_id: paymentLink.hotel_id,
        subscription_id: paymentLink.subscription_id,
        metadata: {
          ignored_reason: 'Unsupported Cashfree Payment Link status.',
          cashfree_link_id: linkId,
          cashfree_link_status: linkStatus,
          ledger_id: paymentLink.id
        }
      });
      return json(200, {
        ok: true,
        provider: 'cashfree',
        ignored: true,
        provider_event_id: providerEventId,
        link_status: linkStatus
      });
    }
    await markWebhook(adminClient, webhookId, {
      processing_status: 'processed',
      processed_at: new Date().toISOString(),
      hotel_id: paymentLink.hotel_id,
      subscription_id: paymentLink.subscription_id,
      metadata: {
        cashfree_link_id: linkId,
        cashfree_link_status: linkStatus,
        ledger_id: paymentLink.id
      }
    });
    return json(200, {
      ok: true,
      provider: 'cashfree',
      idempotent: false,
      processed: true,
      provider_event_id: providerEventId,
      link_status: linkStatus,
      hotel_id: paymentLink.hotel_id
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unexpected Cashfree webhook error.';
    if (webhookId) {
      try {
        const supabaseUrl = Deno.env.get('SUPABASE_URL');
        const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
        if (supabaseUrl && serviceRoleKey) {
          const adminClient = createClient(supabaseUrl, serviceRoleKey, {
            auth: {
              autoRefreshToken: false,
              persistSession: false,
              detectSessionInUrl: false
            }
          });
          await markWebhook(adminClient, webhookId, {
            processing_status: 'failed',
            last_error: message,
            next_retry_at: new Date(Date.now() + 5 * 60 * 1000).toISOString()
          });
        }
      } catch (ledgerError) {
        console.error('Could not update failed webhook ledger:', ledgerError);
      }
    }
    return json(500, {
      ok: false,
      provider: 'cashfree',
      provider_event_id: providerEventId,
      error: message
    });
  }
});
