import { supabase } from './supabase'

async function rpc(name, args, fallback) {
  const { data, error } = await supabase.rpc(name, args)
  if (error) throw new Error(error.message || fallback)
  return data
}

export function v11bRequestKey(prefix = 'v11b') {
  const id = globalThis.crypto?.randomUUID?.() || `${Date.now()}-${Math.random().toString(16).slice(2)}`
  return `${prefix}-${id}`
}

export function loadOperationsAutomation(hotelId) {
  return rpc('get_v11_operations_workspace', { p_hotel_id: hotelId }, 'Unable to load operations automation.')
}

export function createLaundryOrder(hotelId, payload) {
  return rpc('create_v11_laundry_order', { p_hotel_id: hotelId, p_payload: payload }, 'Unable to create laundry order.')
}

export function updateLaundryStatus(hotelId, orderId, status, note = null) {
  return rpc('update_v11_laundry_status', {
    p_hotel_id: hotelId,
    p_order_id: orderId,
    p_status: status,
    p_note: note,
  }, 'Unable to update laundry order.')
}

export function createLostFoundItem(hotelId, payload) {
  return rpc('create_v11_lost_found_item', { p_hotel_id: hotelId, p_payload: payload }, 'Unable to record lost-and-found item.')
}

export function transitionLostFoundItem(hotelId, itemId, status, payload = {}) {
  return rpc('transition_v11_lost_found_item', {
    p_hotel_id: hotelId,
    p_item_id: itemId,
    p_status: status,
    p_payload: payload,
  }, 'Unable to update lost-and-found item.')
}

export function upsertInventoryItem(hotelId, payload) {
  return rpc('upsert_v11_inventory_item', { p_hotel_id: hotelId, p_payload: payload }, 'Unable to save inventory item.')
}

export function postInventoryMovement(hotelId, itemId, movementType, quantity, reason) {
  return rpc('post_v11_inventory_movement', {
    p_hotel_id: hotelId,
    p_item_id: itemId,
    p_movement_type: movementType,
    p_quantity: Number(quantity),
    p_reason: reason,
    p_request_key: v11bRequestKey('stock'),
  }, 'Unable to post inventory movement.')
}

export function upsertKitchenPrinterProfile(hotelId, payload) {
  return rpc('upsert_v11_kitchen_printer_profile', { p_hotel_id: hotelId, p_payload: payload }, 'Unable to save kitchen printer profile.')
}

export function prepareKotPrint(hotelId, orderId, printerProfileId = null) {
  return rpc('prepare_v11_kot_print', {
    p_hotel_id: hotelId,
    p_order_id: orderId,
    p_printer_profile_id: printerProfileId || null,
  }, 'Unable to prepare KOT print.')
}

export function upsertScheduledReportJob(hotelId, payload) {
  return rpc('upsert_v11_scheduled_report_job', { p_hotel_id: hotelId, p_payload: payload }, 'Unable to save scheduled report.')
}

export function runDueScheduledReports(hotelId, force = false) {
  return rpc('run_due_v11_scheduled_reports', { p_hotel_id: hotelId, p_force: Boolean(force) }, 'Unable to run scheduled reports.')
}
