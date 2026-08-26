import { createClient } from 'npm:@supabase/supabase-js@2.106.2';

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' } });
}
function constantTimeEqual(left: string, right: string) {
  if (left.length !== right.length) return false;
  let difference = 0;
  for (let index = 0; index < left.length; index += 1) difference |= left.charCodeAt(index) ^ right.charCodeAt(index);
  return difference === 0;
}
async function hmacHex(secret: string, rawBody: string) {
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const signature = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(rawBody));
  return [...new Uint8Array(signature)].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}
function statusRank(value: string) {
  return ({ queued: 0, sent: 1, delivered: 2, read: 3 } as Record<string, number>)[value] ?? -1;
}

Deno.serve(async (request) => {
  const verifyToken = Deno.env.get('WHATSAPP_WEBHOOK_VERIFY_TOKEN') || '';
  if (request.method === 'GET') {
    const url = new URL(request.url);
    const mode = url.searchParams.get('hub.mode') || '';
    const token = url.searchParams.get('hub.verify_token') || '';
    const challenge = url.searchParams.get('hub.challenge') || '';
    if (mode === 'subscribe' && verifyToken && constantTimeEqual(token, verifyToken)) {
      return new Response(challenge, { status: 200, headers: { 'Content-Type': 'text/plain', 'Cache-Control': 'no-store' } });
    }
    return new Response('Forbidden', { status: 403 });
  }
  if (request.method !== 'POST') return json(405, { ok: false, error: 'Method not allowed.' });

  try {
    const appSecret = Deno.env.get('WHATSAPP_APP_SECRET');
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if (!appSecret || !supabaseUrl || !serviceRoleKey) throw new Error('WhatsApp webhook environment is incomplete.');
    const rawBody = await request.text();
    const received = (request.headers.get('x-hub-signature-256') || '').replace(/^sha256=/i, '').trim().toLowerCase();
    const expected = await hmacHex(appSecret, rawBody);
    if (!received || !constantTimeEqual(received, expected)) return json(401, { ok: false, error: 'Invalid Meta webhook signature.' });

    const payload = JSON.parse(rawBody);
    const statuses: Array<Record<string, unknown>> = [];
    for (const entry of Array.isArray(payload?.entry) ? payload.entry : []) {
      for (const change of Array.isArray(entry?.changes) ? entry.changes : []) {
        for (const status of Array.isArray(change?.value?.statuses) ? change.value.statuses : []) statuses.push(status);
      }
    }
    const admin = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false } });
    let processed = 0;
    for (const statusPayload of statuses) {
      const providerMessageId = String(statusPayload.id || '').trim();
      const incoming = String(statusPayload.status || '').trim().toLowerCase();
      if (!providerMessageId || !['sent', 'delivered', 'read', 'failed'].includes(incoming)) continue;
      const { data: recipient, error } = await admin
        .from('guest_communication_recipients')
        .select('id,hotel_id,guest_id,campaign_id,status,provider_message_id')
        .eq('provider_message_id', providerMessageId).maybeSingle();
      if (error || !recipient) continue;
      if (incoming !== 'failed' && statusRank(incoming) < statusRank(recipient.status)) continue;

      const timestamp = statusPayload.timestamp ? new Date(Number(statusPayload.timestamp) * 1000).toISOString() : new Date().toISOString();
      const update: Record<string, unknown> = { status: incoming };
      if (incoming === 'sent') update.sent_at = timestamp;
      if (incoming === 'delivered') update.delivered_at = timestamp;
      if (incoming === 'read') update.read_at = timestamp;
      if (incoming === 'failed') {
        const firstError = Array.isArray(statusPayload.errors) ? statusPayload.errors[0] : null;
        update.failed_at = timestamp;
        update.error_code = String(firstError?.code || 'provider_failed').slice(0, 80);
        update.error_message = String(firstError?.title || firstError?.message || 'Meta reported message failure.').slice(0, 500);
      }
      await admin.from('guest_communication_recipients').update(update).eq('id', recipient.id);
      await admin.from('guest_communication_events').upsert({
        hotel_id: recipient.hotel_id, guest_id: recipient.guest_id, campaign_id: recipient.campaign_id,
        recipient_id: recipient.id, channel: 'whatsapp', event_type: incoming,
        provider_message_id: providerMessageId,
        metadata: incoming === 'failed' ? { provider_failure: true } : {},
      }, { onConflict: 'recipient_id,event_type', ignoreDuplicates: true });
      processed += 1;
    }
    return json(200, { ok: true, processed });
  } catch (error) {
    console.error('whatsapp-status-webhook error:', error instanceof Error ? error.message : String(error));
    return json(400, { ok: false, error: 'Webhook processing failed.' });
  }
});
