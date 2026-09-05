import { createClient } from 'npm:@supabase/supabase-js@2.106.2';

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
  });
}

function constantTimeEqual(left: string, right: string) {
  if (left.length !== right.length) return false;
  let difference = 0;
  for (let index = 0; index < left.length; index += 1) {
    difference |= left.charCodeAt(index) ^ right.charCodeAt(index);
  }
  return difference === 0;
}

async function hmacHex(secret: string, rawBody: string) {
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const signature = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(rawBody));
  return [...new Uint8Array(signature)]
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('');
}

function providerTimestamp(value: unknown) {
  const epochSeconds = Number(value);
  if (!Number.isFinite(epochSeconds) || epochSeconds <= 0) return new Date().toISOString();
  const candidate = new Date(epochSeconds * 1000);
  return Number.isNaN(candidate.getTime()) ? new Date().toISOString() : candidate.toISOString();
}

Deno.serve(async (request) => {
  const verifyToken = Deno.env.get('WHATSAPP_WEBHOOK_VERIFY_TOKEN') || '';

  if (request.method === 'GET') {
    const url = new URL(request.url);
    const mode = url.searchParams.get('hub.mode') || '';
    const token = url.searchParams.get('hub.verify_token') || '';
    const challenge = url.searchParams.get('hub.challenge') || '';
    if (mode === 'subscribe' && verifyToken && constantTimeEqual(token, verifyToken)) {
      return new Response(challenge, {
        status: 200,
        headers: { 'Content-Type': 'text/plain', 'Cache-Control': 'no-store' },
      });
    }
    return new Response('Forbidden', { status: 403 });
  }

  if (request.method !== 'POST') {
    return json(405, { ok: false, error: 'Method not allowed.' });
  }

  try {
    const appSecret = Deno.env.get('WHATSAPP_APP_SECRET');
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if (!appSecret || !supabaseUrl || !serviceRoleKey) {
      throw new Error('WhatsApp webhook environment is incomplete.');
    }

    // Meta signature verification MUST happen against the exact raw request body
    // before any service-role client is created or any database work is attempted.
    const rawBody = await request.text();
    const received = (request.headers.get('x-hub-signature-256') || '')
      .replace(/^sha256=/i, '')
      .trim()
      .toLowerCase();
    const expected = await hmacHex(appSecret, rawBody);
    if (!received || !constantTimeEqual(received, expected)) {
      return json(401, { ok: false, error: 'Invalid Meta webhook signature.' });
    }

    let payload: Record<string, unknown>;
    try {
      payload = JSON.parse(rawBody);
    } catch {
      return json(400, { ok: false, error: 'Invalid webhook payload.' });
    }

    const statuses: Array<Record<string, unknown>> = [];
    for (const entry of Array.isArray(payload?.entry) ? payload.entry : []) {
      for (const change of Array.isArray(entry?.changes) ? entry.changes : []) {
        const value = change?.value as Record<string, unknown> | undefined;
        for (const status of Array.isArray(value?.statuses) ? value.statuses : []) {
          statuses.push(status as Record<string, unknown>);
        }
      }
    }

    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    });

    let processed = 0;
    let unmatched = 0;
    let ignored = 0;

    for (const statusPayload of statuses) {
      const providerMessageId = String(statusPayload.id || '').trim();
      const incoming = String(statusPayload.status || '').trim().toLowerCase();
      if (!providerMessageId || !['sent', 'delivered', 'read', 'failed'].includes(incoming)) {
        continue;
      }

      const firstError = Array.isArray(statusPayload.errors)
        ? (statusPayload.errors[0] as Record<string, unknown> | undefined)
        : undefined;
      const errorCode = incoming === 'failed'
        ? String(firstError?.code || 'provider_failed').slice(0, 80)
        : null;

      const { data, error } = await admin.rpc('record_whatsapp_delivery_status', {
        p_provider_message_id: providerMessageId,
        p_status: incoming,
        p_status_at: providerTimestamp(statusPayload.timestamp),
        p_error_code: errorCode,
        // Do not persist raw provider error strings; they may contain echoed user data.
        p_error_message: incoming === 'failed' ? 'Meta reported message failure.' : null,
        p_metadata: {
          source: 'meta_cloud_webhook',
          provider_failure: incoming === 'failed',
        },
      });

      if (error) {
        throw new Error('Webhook delivery-state persistence failed.');
      }

      const result = (data || {}) as Record<string, unknown>;
      if (result.matched === false) {
        unmatched += 1;
      } else if (result.applied === true || result.idempotent === true) {
        processed += 1;
      } else {
        ignored += 1;
      }
    }

    // Meta receives 200 only after all matched status writes completed successfully.
    // Any persistence failure throws above and returns 503 so Meta can retry.
    return json(200, { ok: true, processed, unmatched, ignored });
  } catch (error) {
    console.error(
      'whatsapp-status-webhook error:',
      error instanceof Error ? error.message : String(error),
    );
    return json(503, { ok: false, error: 'Webhook processing failed. Retry later.' });
  }
});
