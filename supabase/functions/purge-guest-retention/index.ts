import { createClient } from 'npm:@supabase/supabase-js@2.106.2';

function response(status: number, body: unknown) {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' } });
}
function uuid(value: unknown, label: string) {
  const text = String(value || '').trim();
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(text)) throw new Error(`${label} must be a valid UUID.`);
  return text;
}

Deno.serve(async (request) => {
  if (request.method !== 'POST') return response(405, { ok: false, error: 'Method not allowed.' });
  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if (!supabaseUrl || !anonKey || !serviceRoleKey) throw new Error('Supabase function environment is incomplete.');
    const token = (request.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '').trim();
    if (!token) return response(401, { ok: false, error: 'Authentication is required.' });
    const authClient = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: `Bearer ${token}` } }, auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false } });
    const admin = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false } });
    const { data: { user }, error: userError } = await authClient.auth.getUser(token);
    if (userError || !user) return response(401, { ok: false, error: 'Your StayQR session is invalid or expired.' });
    const body = await request.json().catch(() => ({}));
    const hotelId = uuid(body.hotel_id, 'hotel_id');
    const limit = Math.max(1, Math.min(Number(body.limit || 50), 100));
    const { data: due, error: dueError } = await authClient.rpc('get_guest_documents_due_for_retention', { target_hotel_id: hotelId, result_limit: limit });
    if (dueError) throw dueError;
    const outcomes = [];
    for (const item of due || []) {
      try {
        await authClient.rpc('audit_guest_document_access', { target_hotel_id: hotelId, target_document_id: item.id, target_action: 'retention_purge', target_reason: 'retention_window_elapsed' });
        const { error: metaError } = await authClient.rpc('soft_delete_guest_document', { target_hotel_id: hotelId, target_document_id: item.id });
        if (metaError) throw metaError;
        const { error: storageError } = await admin.storage.from(item.storage_bucket || 'guest-documents').remove([item.storage_path]);
        if (storageError) throw storageError;
        outcomes.push({ id: item.id, status: 'purged' });
      } catch (itemError) {
        outcomes.push({ id: item.id, status: 'failed', error: itemError instanceof Error ? itemError.message : 'purge_failed' });
      }
    }
    return response(200, { ok: true, reviewed: outcomes.length, purged: outcomes.filter((item) => item.status === 'purged').length, outcomes });
  } catch (error) {
    console.error('purge-guest-retention error:', error instanceof Error ? error.message : String(error));
    return response(400, { ok: false, error: error instanceof Error ? error.message : 'Retention purge failed.' });
  }
});
