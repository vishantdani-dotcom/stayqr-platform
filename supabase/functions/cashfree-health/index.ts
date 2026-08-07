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
function getProviderError(body) {
  const message = typeof body.message === 'string' ? body.message : undefined;
  const type = typeof body.type === 'string' ? body.type : undefined;
  const code = typeof body.code === 'string' ? body.code : undefined;
  return {
    message,
    type,
    code
  };
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
      throw new Error('The Supabase Edge Function authentication environment is incomplete.');
    }
    if (!cashfreeClientId || !cashfreeClientSecret || !cashfreeMode || !cashfreeApiBaseUrl || !cashfreeApiVersion) {
      throw new Error('The Cashfree Edge Function environment is incomplete.');
    }
    if (![
      'test',
      'live',
      'production'
    ].includes(cashfreeMode)) {
      throw new Error('CASHFREE_MODE must be test, live or production.');
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
    // Gateway JWT verification is intentionally disabled because StayQR uses
    // asymmetric ES256 signing keys. The bearer token is verified directly
    // with Supabase Auth before any service-role or Cashfree operation.
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
    // Cashfree does not expose a general read-only "who am I" endpoint.
    // Fetching a cryptographically random nonexistent order is a safe
    // authentication probe: valid credentials reach the Orders API and return
    // an order-not-found response, while invalid credentials return 401/403.
    const probeOrderId = `stayqr_health_${crypto.randomUUID().replaceAll('-', '')}`;
    const providerResponse = await fetch(`${cashfreeApiBaseUrl}/orders/${probeOrderId}`, {
      method: 'GET',
      headers: {
        Accept: 'application/json',
        'x-api-version': cashfreeApiVersion,
        'x-client-id': cashfreeClientId,
        'x-client-secret': cashfreeClientSecret,
        'x-request-id': crypto.randomUUID()
      },
      signal: AbortSignal.timeout(15000)
    });
    const providerBody = await providerResponse.json().catch(()=>({}));
    const providerError = getProviderError(providerBody);
    // A successful response or a genuine order-not-found response proves that
    // Cashfree accepted the credentials and API-version headers.
    const orderNotFound = providerResponse.status === 404 && (providerError.code?.toLowerCase().includes('order') || providerError.type?.toLowerCase().includes('invalid') || providerError.message?.toLowerCase().includes('order'));
    if (providerResponse.ok || orderNotFound) {
      return json(request, 200, {
        ok: true,
        provider: 'cashfree',
        mode: cashfreeMode,
        credentials: 'valid',
        provider_connection: 'reachable',
        orders_api_access: true,
        provider_http_status: providerResponse.status,
        authentication_probe: providerResponse.ok ? 'authenticated' : 'authenticated_order_not_found',
        api_version: cashfreeApiVersion,
        caller_user_id: caller.id,
        checked_at: new Date().toISOString()
      });
    }
    const providerMessage = providerError.message || providerError.code || providerError.type || `Cashfree returned HTTP ${providerResponse.status}.`;
    return json(request, 502, {
      ok: false,
      provider: 'cashfree',
      mode: cashfreeMode,
      credentials: [
        401,
        403
      ].includes(providerResponse.status) ? 'rejected' : 'unverified',
      provider_connection: 'reachable',
      orders_api_access: false,
      provider_http_status: providerResponse.status,
      api_version: cashfreeApiVersion,
      error: providerMessage
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unexpected Cashfree health-check error.';
    const status = message.includes('Platform Admin access') ? 403 : message.includes('timeout') || message.includes('timed out') ? 504 : 500;
    return json(request, status, {
      ok: false,
      error: message
    });
  }
});
