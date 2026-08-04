import { supabase } from './supabase'

async function callRpc(name, args, fallback) {
  const { data, error } = await supabase.rpc(name, args)
  if (error) throw new Error(error.message || fallback)
  return data
}

export function createRequestId(prefix = 'stayqr') {
  const random = globalThis.crypto?.randomUUID?.()
    || `${Date.now()}-${Math.random().toString(16).slice(2)}`
  return `${prefix}-${random}`
}

export async function updateFoodOrderStatus({
  hotelId,
  orderId,
  status,
  estimatedMinutes = null,
  note = null,
}) {
  return callRpc(
    'update_food_order_status',
    {
      p_hotel_id: hotelId,
      p_order_id: orderId,
      p_status: status,
      p_estimated_minutes:
        estimatedMinutes === '' || estimatedMinutes == null
          ? null
          : Number(estimatedMinutes),
      p_note: note || null,
    },
    'Unable to update the food order.'
  )
}

export async function postFoodOrderToFolio({ hotelId, orderId }) {
  return callRpc(
    'post_food_order_to_folio',
    { p_hotel_id: hotelId, p_order_id: orderId },
    'Unable to post the food order to the folio.'
  )
}

export async function getFoodOrderKot({ hotelId, orderId }) {
  return callRpc(
    'get_food_order_kot',
    { p_hotel_id: hotelId, p_order_id: orderId },
    'Unable to prepare the kitchen ticket.'
  )
}

export async function getFoodOperationsAnalytics({ hotelId, from, to }) {
  return callRpc(
    'get_food_operations_analytics',
    {
      p_hotel_id: hotelId,
      p_from: from,
      p_to: to,
    },
    'Unable to load food analytics.'
  )
}

export async function assignServiceRequest({ hotelId, requestId, staffId }) {
  return callRpc(
    'assign_service_request',
    {
      p_hotel_id: hotelId,
      p_request_id: requestId,
      p_staff_id: staffId || null,
    },
    'Unable to assign the service request.'
  )
}

export async function updateServiceRequestPriority({
  hotelId,
  requestId,
  priority,
}) {
  return callRpc(
    'update_service_request_priority',
    {
      p_hotel_id: hotelId,
      p_request_id: requestId,
      p_priority: priority,
    },
    'Unable to update service priority.'
  )
}

export async function updateServiceRequestStatus({
  hotelId,
  requestId,
  status,
  estimatedMinutes = null,
  note = null,
}) {
  return callRpc(
    'update_service_request_status',
    {
      p_hotel_id: hotelId,
      p_request_id: requestId,
      p_status: status,
      p_estimated_minutes:
        estimatedMinutes === '' || estimatedMinutes == null
          ? null
          : Number(estimatedMinutes),
      p_note: note || null,
    },
    'Unable to update the service request.'
  )
}

export async function escalateOverdueServiceRequests(hotelId) {
  return callRpc(
    'escalate_overdue_service_requests',
    { p_hotel_id: hotelId },
    'Unable to reconcile overdue requests.'
  )
}

export async function getServiceOperationsAnalytics({ hotelId, from, to }) {
  return callRpc(
    'get_service_operations_analytics',
    {
      p_hotel_id: hotelId,
      p_from: from,
      p_to: to,
    },
    'Unable to load service analytics.'
  )
}

export async function loadDay15FoodOrders(hotelId) {
  const { data, error } = await supabase
    .from('food_orders')
    .select(`
      *,
      rooms (room_number),
      guests (full_name),
      food_order_items (
        id,
        quantity,
        price,
        item_name_snapshot,
        unit_price,
        modifier_amount,
        tax_amount,
        line_total,
        food_order_item_modifiers (
          modifier_name_snapshot,
          price_delta
        )
      )
    `)
    .eq('hotel_id', hotelId)
    .order('created_at', { ascending: false })

  if (error) throw error
  return Array.isArray(data) ? data : []
}

export async function loadDay15ServiceRequests(hotelId) {
  const { data, error } = await supabase
    .from('service_requests')
    .select(`
      *,
      guests (full_name, phone),
      rooms (room_number, room_type),
      service_request_types (
        name,
        code,
        department,
        sla_minutes,
        charge_enabled,
        default_charge_amount
      )
    `)
    .eq('hotel_id', hotelId)
    .order('created_at', { ascending: false })

  if (error) throw error
  return Array.isArray(data) ? data : []
}
