import fs from 'node:fs';

const read = (p) => fs.readFileSync(p, 'utf8');
const webhook = read('supabase/functions/whatsapp-status-webhook/index.ts');
const migration = read('supabase/migrations/202609050114_whatsapp_status_atomic_persistence_REV1.sql');
const acceptance = read('supabase/staging/202609050114_whatsapp_status_atomic_persistence_ACCEPTANCE_REV1.sql');
const config = read('supabase/config.toml');
const env = read('.env.example');

const checks = [];
const add = (name, ok) => checks.push([name, Boolean(ok)]);

add('raw body is read before signature verification', webhook.includes('const rawBody = await request.text()'));
add('Meta HMAC header is required', webhook.includes('x-hub-signature-256') && webhook.includes('hmacHex'));
add('signature verification precedes service-role client creation', webhook.indexOf('constantTimeEqual(received, expected)') < webhook.indexOf('createClient(supabaseUrl, serviceRoleKey'));
add('invalid signature returns 401', webhook.includes("return json(401, { ok: false, error: 'Invalid Meta webhook signature.' })"));
add('webhook delegates persistence to atomic RPC', webhook.includes("admin.rpc('record_whatsapp_delivery_status'"));
add('webhook no longer directly updates recipient status', !webhook.includes(".from('guest_communication_recipients').update("));
add('webhook no longer directly inserts delivery events', !webhook.includes(".from('guest_communication_events').upsert("));
add('persistence failure throws', webhook.includes("throw new Error('Webhook delivery-state persistence failed.')"));
add('persistence failure returns 503', webhook.includes("return json(503, { ok: false, error: 'Webhook processing failed. Retry later.' })"));
add('200 ack happens only after loop', webhook.indexOf('for (const statusPayload of statuses)') < webhook.lastIndexOf('return json(200'));
add('raw provider failure strings are not persisted', webhook.includes("p_error_message: incoming === 'failed' ? 'Meta reported message failure.' : null"));
add('provider timestamp is bounded', webhook.includes('function providerTimestamp'));
add('RPC uses security definer', migration.includes('security definer'));
add('RPC locks matched recipient', migration.toLowerCase().includes('for update'));
add('late failure downgrade is blocked', migration.includes('successful_state_prevents_failed_downgrade'));
add('failed provider id is terminal', migration.includes('failed_provider_message_is_terminal'));
add('lower-rank delivery status is ignored', migration.includes('lower_rank_status_ignored'));
add('recipient and event writes share one RPC', migration.includes('update public.guest_communication_recipients') && migration.includes('insert into public.guest_communication_events'));
add('event persistence is idempotent', migration.includes('on conflict (recipient_id, event_type) do nothing'));
add('unknown message id is safe', migration.includes("'matched', false"));
add('RPC is service-role-only', migration.includes('to service_role') && migration.includes('from public, anon, authenticated'));
add('acceptance has 12 checks', (acceptance.match(/select '\d{2}_/g) || []).length === 12);
add('webhook gateway JWT verification remains disabled', /\[functions\.whatsapp-status-webhook\]\r?\nverify_jwt\s*=\s*false/.test(config));
add('Meta secret names are documented', ['WHATSAPP_ACCESS_TOKEN=', 'WHATSAPP_APP_SECRET=', 'WHATSAPP_WEBHOOK_VERIFY_TOKEN=', 'WHATSAPP_GRAPH_API_VERSION='].every((x) => env.includes(x)));

let failed = 0;
for (const [name, ok] of checks) {
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}`);
  if (!ok) failed += 1;
}
console.log(`\nREV8 source validation: ${checks.length - failed}/${checks.length} PASS`);
if (failed) process.exit(1);
