import { supabase } from './supabase'

async function rpc(name, args, fallback) {
  const { data, error } = await supabase.rpc(name, args)
  if (error) throw new Error(error.message || fallback)
  return data
}

export function loadV11cPlatformWorkspace(hotelId) {
  return rpc(
    'get_v11c_platform_workspace',
    { p_hotel_id: hotelId },
    'Unable to load the V1.1-C platform workspace.'
  )
}

export function saveV11cWhatsAppSettings(hotelId, payload) {
  return rpc(
    'upsert_v11c_whatsapp_channel_settings',
    { p_hotel_id: hotelId, p_payload: payload },
    'Unable to save WhatsApp channel settings.'
  )
}

export function loadV11cMultiPropertyOverview() {
  return rpc(
    'get_v11c_multi_property_overview',
    {},
    'Unable to load the authorized multi-property overview.'
  )
}
