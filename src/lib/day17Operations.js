import { supabase } from './supabase'

function unwrap(data, fallback) {
  return data ?? fallback
}

export async function getNotificationInbox(hotelId, limit = 50, before = null) {
  const { data, error } = await supabase.rpc('get_notification_inbox', {
    p_hotel_id: hotelId,
    p_limit: limit,
    p_before: before,
  })
  if (error) throw error
  return unwrap(data, { unread_count: 0, items: [] })
}

export async function markInboxNotificationRead(recipientId) {
  const { data, error } = await supabase.rpc('mark_notification_read', {
    p_recipient_id: recipientId,
  })
  if (error) throw error
  return data
}

export async function markInboxAllRead(hotelId) {
  const { data, error } = await supabase.rpc('mark_all_notifications_read', {
    p_hotel_id: hotelId,
  })
  if (error) throw error
  return data
}

export async function saveNotificationPreferences(hotelId, payload) {
  const { data, error } = await supabase.rpc('upsert_notification_preferences', {
    p_hotel_id: hotelId,
    p_payload: payload,
  })
  if (error) throw error
  return data
}

export async function publishNotificationTemplate(hotelId, eventKey, channel, payload) {
  const { data, error } = await supabase.rpc('publish_notification_template', {
    p_hotel_id: hotelId,
    p_event_key: eventKey,
    p_channel: channel,
    p_payload: payload,
  })
  if (error) throw error
  return data
}

export async function getActivityTimeline(hotelId, from, to, filters = {}) {
  const { data, error } = await supabase.rpc('get_activity_timeline', {
    p_hotel_id: hotelId,
    p_from: from || null,
    p_to: to || null,
    p_filters: filters,
  })
  if (error) throw error
  return unwrap(data, { items: [] })
}

export async function getHotelSystemSettings(hotelId) {
  const { data, error } = await supabase.rpc('get_hotel_system_settings', {
    p_hotel_id: hotelId,
  })
  if (error) throw error
  return data || {}
}

export async function updateHotelSystemSettings(hotelId, payload) {
  const { data, error } = await supabase.rpc('update_hotel_system_settings', {
    p_hotel_id: hotelId,
    p_payload: payload,
  })
  if (error) throw error
  return data
}

export async function getSupportWorkspace(hotelId) {
  const { data, error } = await supabase.rpc('get_support_workspace', {
    p_hotel_id: hotelId,
  })
  if (error) throw error
  return unwrap(data, { tickets: [] })
}

export async function getActiveAnnouncements(hotelId) {
  const { data, error } = await supabase.rpc('get_active_announcements', {
    p_hotel_id: hotelId,
  })
  if (error) throw error
  return unwrap(data, [])
}

export async function getEventCatalog() {
  const { data, error } = await supabase
    .from('notification_event_catalog')
    .select('event_key,source_type,audience,severity,default_title,default_body,is_critical,is_active')
    .eq('is_active', true)
    .order('event_key')
  if (error) throw error
  return data || []
}

export async function getHotelTemplates(hotelId) {
  const { data, error } = await supabase
    .from('notification_templates')
    .select('id,hotel_id,event_key,channel,locale,title_template,body_template,status,current_version,published_at,updated_at')
    .or(`hotel_id.eq.${hotelId},hotel_id.is.null`)
    .order('event_key')
    .order('channel')
  if (error) throw error
  return data || []
}

export async function getDeliveryFailures(hotelId) {
  const { data, error } = await supabase
    .from('notification_deliveries')
    .select('id,channel,address_snapshot,rendered_title,status,attempt_count,max_attempts,last_error_code,last_error_message,next_attempt_at,created_at')
    .eq('hotel_id', hotelId)
    .in('status', ['failed', 'retrying'])
    .order('created_at', { ascending: false })
    .limit(100)
  if (error) throw error
  return data || []
}

export async function retryDelivery(deliveryId) {
  const { data, error } = await supabase.rpc('retry_notification_delivery', {
    p_delivery_id: deliveryId,
  })
  if (error) throw error
  return data
}

export async function getEmailAdapters(hotelId) {
  const { data, error } = await supabase
    .from('email_adapter_configs')
    .select('id,hotel_id,adapter_key,provider,from_name,from_email,reply_to_email,endpoint_name,is_enabled,metadata,updated_at')
    .eq('hotel_id', hotelId)
    .order('updated_at', { ascending: false })
  if (error) throw error
  return data || []
}

export async function saveEmailAdapter(hotelId, payload) {
  const { data, error } = await supabase.rpc('upsert_email_adapter_config', {
    p_hotel_id: hotelId,
    p_payload: {
      adapter_key: payload.adapter_key,
      provider: payload.provider,
      from_name: payload.from_name || null,
      from_email: payload.from_email || null,
      reply_to_email: payload.reply_to_email || null,
      endpoint_name: payload.endpoint_name || null,
      is_enabled: Boolean(payload.is_enabled),
      metadata: payload.metadata || {},
    },
  })
  if (error) throw error
  return data
}

export async function getWhatsAppTemplates(hotelId) {
  const { data, error } = await supabase
    .from('whatsapp_templates')
    .select('id,hotel_id,event_key,locale,template_name,body_template,status,updated_at')
    .eq('hotel_id', hotelId)
    .order('updated_at', { ascending: false })
  if (error) throw error
  return data || []
}

export async function saveWhatsAppTemplate(hotelId, payload) {
  const { data, error } = await supabase.rpc(
    'upsert_manual_whatsapp_template',
    {
      p_hotel_id: hotelId,
      p_payload: {
        event_key: payload.event_key,
        locale: payload.locale || 'en',
        template_name: payload.template_name,
        body_template: payload.body_template,
        status: payload.status || 'draft',
      },
    }
  )
  if (error) throw error
  return data
}

export function subscribeToNotificationInbox(hotelId, onChange) {
  if (!hotelId) return () => {}
  const channel = supabase
    .channel(`day17_notification_recipients_${hotelId}_${Date.now()}`)
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'notification_recipients',
        filter: `hotel_id=eq.${hotelId}`,
      },
      onChange
    )
    .subscribe()
  return () => supabase.removeChannel(channel)
}

export function subscribeToNotificationDeliveries(hotelId, onChange) {
  if (!hotelId) return () => {}
  const channel = supabase
    .channel(`day17_notification_deliveries_${hotelId}_${Date.now()}`)
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'notification_deliveries',
        filter: `hotel_id=eq.${hotelId}`,
      },
      onChange
    )
    .subscribe()
  return () => supabase.removeChannel(channel)
}
