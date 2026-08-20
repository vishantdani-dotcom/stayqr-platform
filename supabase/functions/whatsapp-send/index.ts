import { createClient } from 'npm:@supabase/supabase-js@2.106.2';

function getAllowedOrigins() {
  const configured = [Deno.env.get('STAYQR_APP_URL'), Deno.env.get('STAYQR_APP_URLS')]
    .filter(Boolean)
    .flatMap((value) => String(value).split(','))
    .map((value) => value.trim().replace(/\/$/, ''))
    .filter(Boolean);
  return new Set(configured.map((value) => {
    try { return new URL(value).origin; } catch { return value; }
  }));
}

function corsHeaders(request: Request) {
  const requestOrigin = request.headers.get('Origin') || '';
  const allowed = getAllowedOrigins();
  const fallback = [...allowed][0] || requestOrigin || '*';
  return {
    'Access-Control-Allow-Origin': allowed.has(requestOrigin) ? requestOrigin : fallback,
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Max-Age': '86400',
    Vary: 'Origin',
  };
}

function json(request: Request, status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders(request), 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
  });
}

function uuid(value: unknown, label: string) {
  const text = String(value || '').trim();
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(text)) {
    throw new Error(`${label} must be a valid UUID.`);
  }
  return text;
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders(request) });
  if (request.method !== 'POST') return json(request, 405, { ok: false, error: 'Method not allowed.' });

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if (!supabaseUrl || !anonKey || !serviceRoleKey) throw new Error('Supabase function environment is incomplete.');

    const authHeader = request.headers.get('Authorization') || '';
    const token = authHeader.replace(/^Bearer\s+/i, '').trim();
    if (!token) return json(request, 401, { ok: false, error: 'Authentication is required.' });

    const authClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: `Bearer ${token}` } },
      auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    });
    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    });
    const { data: { user }, error: userError } = await authClient.auth.getUser(token);
    if (userError || !user) return json(request, 401, { ok: false, error: 'Your StayQR session is invalid or expired.' });

    const body = await request.json().catch(() => ({}));
    const recipientId = uuid(body.recipient_id, 'recipient_id');
    const { data: recipient, error: recipientError } = await admin
      .from('guest_communication_recipients')
      .select('id,hotel_id,campaign_id,guest_id,phone_e164,consent_id,status,provider_message_id,idempotency_key,attempt_count')
      .eq('id', recipientId).single();
    if (recipientError || !recipient) throw new Error('Campaign recipient was not found.');

    // Permission check is intentionally user-context and tenant-scoped.
    const { data: permissionRows, error: permissionError } = await authClient.rpc('get_my_hotel_permissions', {
      target_hotel_id: recipient.hotel_id,
    });
    if (permissionError) throw permissionError;
    const permissionSet = new Set((permissionRows || []).map((row: { permission_key?: string }) => row.permission_key));
    if (!permissionSet.has('guests.manage')) throw new Error('Guest communication management access denied.');

    if (['sent', 'delivered', 'read'].includes(recipient.status)) {
      return json(request, 200, { ok: true, idempotent: true, status: recipient.status, provider_message_id: recipient.provider_message_id });
    }

    const { data: campaign, error: campaignError } = await admin
      .from('guest_communication_campaigns')
      .select('id,hotel_id,purpose,provider_mode,provider_template_name,provider_template_language,status')
      .eq('id', recipient.campaign_id).eq('hotel_id', recipient.hotel_id).single();
    if (campaignError || !campaign) throw new Error('WhatsApp campaign was not found.');
    if (campaign.provider_mode !== 'meta_cloud') throw new Error('This campaign is not configured for Meta Cloud delivery.');
    if (!campaign.provider_template_name) throw new Error('An approved Meta WhatsApp template is required.');
    if (!recipient.phone_e164) throw new Error('Recipient phone number is invalid.');

    const { data: providerProfile, error: providerProfileError } = await admin
      .from('hotel_whatsapp_provider_profiles')
      .select('hotel_id,provider,phone_number_id,status')
      .eq('hotel_id', recipient.hotel_id).eq('provider', 'meta_cloud').eq('status', 'active').maybeSingle();
    if (providerProfileError) throw providerProfileError;
    if (!providerProfile?.phone_number_id) throw new Error('This hotel does not have an active hotel-owned Meta Cloud sender configured.');

    const { data: approvedTemplate, error: templateError } = await admin
      .from('whatsapp_templates')
      .select('id,template_name,locale,provider_name,provider_status,provider_language,status')
      .eq('hotel_id', recipient.hotel_id)
      .eq('template_name', campaign.provider_template_name)
      .eq('status', 'published')
      .eq('provider_name', 'meta_cloud')
      .eq('provider_status', 'approved')
      .limit(1).maybeSingle();
    if (templateError) throw templateError;
    if (!approvedTemplate) throw new Error('The selected WhatsApp template no longer has confirmed Meta approval for this hotel.');
    const approvedLanguage = approvedTemplate.provider_language || approvedTemplate.locale || 'en';
    if (approvedLanguage !== (campaign.provider_template_language || 'en')) {
      throw new Error('The campaign template language no longer matches the provider-approved template.');
    }

    const requiredPurpose = campaign.purpose === 'marketing' ? 'whatsapp_marketing' : 'whatsapp_transactional';
    const { data: consent, error: consentError } = await admin
      .from('guest_consents').select('id')
      .eq('hotel_id', recipient.hotel_id).eq('guest_id', recipient.guest_id)
      .eq('purpose', requiredPurpose).eq('status', 'granted').is('revoked_at', null)
      .order('captured_at', { ascending: false }).limit(1).maybeSingle();
    if (consentError) throw consentError;
    if (!consent) {
      await admin.from('guest_communication_recipients').update({
        status: 'suppressed', error_code: 'consent_revoked', error_message: 'Stored WhatsApp consent is no longer active.',
      }).eq('id', recipient.id);
      await admin.from('guest_communication_events').upsert({
        hotel_id: recipient.hotel_id, guest_id: recipient.guest_id, campaign_id: recipient.campaign_id,
        recipient_id: recipient.id, channel: 'whatsapp', event_type: 'suppressed', actor_user_id: user.id,
        metadata: { reason: 'consent_revoked_before_send' },
      }, { onConflict: 'recipient_id,event_type', ignoreDuplicates: true });
      return json(request, 409, { ok: false, error: 'Stored WhatsApp consent is no longer active.' });
    }

    const { data: suppression, error: suppressionError } = await admin
      .from('guest_communication_suppressions').select('id')
      .eq('hotel_id', recipient.hotel_id).eq('guest_id', recipient.guest_id)
      .eq('channel', 'whatsapp').eq('active', true).limit(1).maybeSingle();
    if (suppressionError) throw suppressionError;
    if (suppression) {
      await admin.from('guest_communication_recipients').update({
        status: 'suppressed', error_code: 'guest_suppressed', error_message: 'WhatsApp is suppressed for this guest.',
      }).eq('id', recipient.id);
      await admin.from('guest_communication_events').upsert({
        hotel_id: recipient.hotel_id, guest_id: recipient.guest_id, campaign_id: recipient.campaign_id,
        recipient_id: recipient.id, channel: 'whatsapp', event_type: 'suppressed', actor_user_id: user.id,
        metadata: { reason: 'active_suppression_before_send' },
      }, { onConflict: 'recipient_id,event_type', ignoreDuplicates: true });
      return json(request, 409, { ok: false, error: 'WhatsApp is suppressed for this guest.' });
    }

    if ((Deno.env.get('WHATSAPP_AUTOMATION_ENABLED') || '').trim().toLowerCase() !== 'true') {
      return json(request, 409, { ok: false, error: 'Automated WhatsApp delivery is disabled. Prepare campaigns safely, then enable the production provider after approval.' });
    }

    const accessToken = Deno.env.get('WHATSAPP_ACCESS_TOKEN');
    const phoneNumberId = providerProfile.phone_number_id;
    const graphVersion = Deno.env.get('WHATSAPP_GRAPH_API_VERSION');
    if (!accessToken || !graphVersion) throw new Error('WhatsApp Meta Cloud provider credentials are incomplete.');
    if (!/^v\d+\.\d+$/.test(graphVersion)) throw new Error('WHATSAPP_GRAPH_API_VERSION must look like vXX.X.');

    const { data: locked, error: lockError } = await admin
      .from('guest_communication_recipients')
      .update({
        status: 'queued', queued_at: new Date().toISOString(), error_code: null, error_message: null,
        attempt_count: Number(recipient.attempt_count || 0) + 1, last_attempt_at: new Date().toISOString(),
      })
      .eq('id', recipient.id).in('status', ['eligible', 'failed']).select('id').maybeSingle();
    if (lockError) throw lockError;
    if (!locked) return json(request, 200, { ok: true, idempotent: true, status: recipient.status });

    await admin.from('guest_communication_events').upsert({
      hotel_id: recipient.hotel_id,
      guest_id: recipient.guest_id,
      campaign_id: recipient.campaign_id,
      recipient_id: recipient.id,
      channel: 'whatsapp',
      event_type: 'queued',
      actor_user_id: user.id,
      metadata: { idempotency_key: recipient.idempotency_key, attempt: Number(recipient.attempt_count || 0) + 1 },
    }, { onConflict: 'recipient_id,event_type', ignoreDuplicates: true });

    let providerResponse: Response;
    let providerBody: Record<string, unknown> = {};
    try {
      providerResponse = await fetch(`https://graph.facebook.com/${graphVersion}/${phoneNumberId}/messages`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({
          messaging_product: 'whatsapp',
          recipient_type: 'individual',
          to: recipient.phone_e164.replace(/\D/g, ''),
          type: 'template',
          template: {
            name: campaign.provider_template_name,
            language: { code: campaign.provider_template_language || 'en' },
          },
        }),
      });
      providerBody = await providerResponse.json().catch(() => ({}));

      if (!providerResponse.ok) {
        const providerError = providerBody?.error as Record<string, unknown> | undefined;
        const message = String(providerError?.message || `Meta WhatsApp returned HTTP ${providerResponse.status}.`).slice(0, 500);
        const code = String(providerError?.code || providerResponse.status).slice(0, 80);
        throw Object.assign(new Error(message), { providerCode: code, providerHttpStatus: providerResponse.status });
      }

      const providerMessageId = String((providerBody?.messages as Array<Record<string, unknown>> | undefined)?.[0]?.id || '').trim();
      if (!providerMessageId) {
        throw Object.assign(new Error('Meta WhatsApp did not return a message ID.'), { providerCode: 'missing_message_id' });
      }

      const sentAt = new Date().toISOString();
      await admin.from('guest_communication_recipients').update({
        status: 'sent', provider_message_id: providerMessageId, sent_at: sentAt, failed_at: null,
      }).eq('id', recipient.id);
      await admin.from('guest_communication_events').upsert({
        hotel_id: recipient.hotel_id, guest_id: recipient.guest_id, campaign_id: recipient.campaign_id,
        recipient_id: recipient.id, channel: 'whatsapp', event_type: 'sent', actor_user_id: user.id,
        provider_message_id: providerMessageId, metadata: { template: campaign.provider_template_name },
      }, { onConflict: 'recipient_id,event_type', ignoreDuplicates: true });

      await admin.from('guest_communication_campaigns').update({
        status: 'sending',
        started_at: new Date().toISOString(),
      }).eq('id', campaign.id).eq('hotel_id', recipient.hotel_id).eq('status', 'ready');

      const { count: pendingCount } = await admin
        .from('guest_communication_recipients')
        .select('id', { head: true, count: 'exact' })
        .eq('campaign_id', campaign.id)
        .in('status', ['eligible', 'failed', 'queued']);
      if ((pendingCount || 0) === 0) {
        await admin.from('guest_communication_campaigns').update({
          status: 'completed', completed_at: new Date().toISOString(),
        }).eq('id', campaign.id).eq('hotel_id', recipient.hotel_id);
      }

      return json(request, 200, { ok: true, idempotent: false, status: 'sent', provider_message_id: providerMessageId });
    } catch (providerError) {
      const failureMessage = String(providerError instanceof Error ? providerError.message : 'Meta WhatsApp delivery failed.').slice(0, 500);
      const providerCode = String((providerError as { providerCode?: unknown })?.providerCode || 'provider_request_failed').slice(0, 80);
      const providerHttpStatus = Number((providerError as { providerHttpStatus?: unknown })?.providerHttpStatus || 0) || null;
      const failedAt = new Date().toISOString();
      await admin.from('guest_communication_recipients').update({
        status: 'failed', failed_at: failedAt, error_code: providerCode, error_message: failureMessage,
      }).eq('id', recipient.id);
      await admin.from('guest_communication_events').upsert({
        hotel_id: recipient.hotel_id, guest_id: recipient.guest_id, campaign_id: recipient.campaign_id,
        recipient_id: recipient.id, channel: 'whatsapp', event_type: 'failed', actor_user_id: user.id,
        metadata: { provider_http_status: providerHttpStatus, message: failureMessage },
      }, { onConflict: 'recipient_id,event_type', ignoreDuplicates: true });
      return json(request, 502, { ok: false, error: failureMessage });
    }
  } catch (error) {
    console.error('whatsapp-send error:', error instanceof Error ? error.message : String(error));
    return json(request, 400, { ok: false, error: error instanceof Error ? error.message : 'WhatsApp delivery failed.' });
  }
});
