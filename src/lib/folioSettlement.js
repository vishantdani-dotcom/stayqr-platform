import { supabase } from './supabase'

export const PAYMENT_METHODS = [
  { value: 'cash', label: 'Cash' },
  { value: 'card', label: 'Card' },
  { value: 'upi', label: 'UPI' },
  { value: 'bank_transfer', label: 'Bank transfer' },
  { value: 'payment_link', label: 'Payment link' },
  { value: 'other', label: 'Other' },
]

export function createSettlementRequestId(prefix = 'day11') {
  const randomPart =
    typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function'
      ? crypto.randomUUID()
      : `${Date.now()}-${Math.random().toString(16).slice(2)}`

  return `${prefix}:${randomPart}`
}

function assertResponse(response, label) {
  if (response.error) {
    throw new Error(response.error.message || `${label} failed.`)
  }

  return response.data || []
}

function unique(values) {
  return [...new Set(values.filter(Boolean))]
}

async function loadByIds(table, columns, hotelId, ids) {
  const cleanIds = unique(ids)
  if (!hotelId || cleanIds.length === 0) return []

  return assertResponse(
    await supabase
      .from(table)
      .select(columns)
      .eq('hotel_id', hotelId)
      .in('id', cleanIds),
    `Load ${table}`
  )
}

export async function loadFolioWorkspace(hotelId) {
  if (!hotelId) {
    return {
      folios: [],
      exceptions: [],
      serviceTypes: [],
      serviceRequests: [],
      webhookEvents: [],
      serviceItems: [],
    }
  }

  const [
    folioResponse,
    exceptionResponse,
    serviceTypeResponse,
    serviceRequestResponse,
    webhookResponse,
    serviceItemResponse,
  ] = await Promise.all([
    supabase
      .from('folios')
      .select('*')
      .eq('hotel_id', hotelId)
      .order('updated_at', { ascending: false }),
    supabase
      .from('folio_source_exceptions')
      .select('*')
      .eq('hotel_id', hotelId)
      .order('last_seen_at', { ascending: false }),
    supabase
      .from('service_request_types')
      .select('*')
      .eq('hotel_id', hotelId)
      .order('sort_order', { ascending: true }),
    supabase
      .from('service_requests')
      .select('*')
      .eq('hotel_id', hotelId)
      .order('created_at', { ascending: false })
      .limit(100),
    supabase
      .from('payment_webhook_events')
      .select('*')
      .eq('hotel_id', hotelId)
      .order('received_at', { ascending: false })
      .limit(100),
    supabase
      .from('folio_items')
      .select('id, folio_id, source_id, amount, posting_status, metadata')
      .eq('hotel_id', hotelId)
      .eq('source_table', 'service_requests'),
  ])

  const folios = assertResponse(folioResponse, 'Load folios')
  const exceptions = assertResponse(exceptionResponse, 'Load source exceptions')
  const serviceTypes = assertResponse(serviceTypeResponse, 'Load service pricing')
  const serviceRequests = assertResponse(
    serviceRequestResponse,
    'Load service requests'
  )
  const webhookEvents = assertResponse(webhookResponse, 'Load gateway events')
  const serviceItems = assertResponse(serviceItemResponse, 'Load service charges')

  const guestIds = unique([
    ...folios.map((folio) => folio.guest_id),
    ...serviceRequests.map((request) => request.guest_id),
  ])
  const roomIds = unique([
    ...folios.map((folio) => folio.room_id),
    ...serviceRequests.map((request) => request.room_id),
  ])
  const sessionIds = unique(folios.map((folio) => folio.guest_session_id))

  const [guests, rooms, sessions] = await Promise.all([
    loadByIds(
      'guests',
      'id, full_name, phone, email',
      hotelId,
      guestIds
    ),
    loadByIds(
      'rooms',
      'id, room_number, room_type, status',
      hotelId,
      roomIds
    ),
    loadByIds(
      'guest_sessions',
      'id, status, checkin_time, checkout_time, extended_until, checked_out_at',
      hotelId,
      sessionIds
    ),
  ])

  const guestMap = Object.fromEntries(guests.map((guest) => [guest.id, guest]))
  const roomMap = Object.fromEntries(rooms.map((room) => [room.id, room]))
  const sessionMap = Object.fromEntries(
    sessions.map((session) => [session.id, session])
  )
  const serviceTypeMap = Object.fromEntries(
    serviceTypes.map((type) => [type.id, type])
  )
  const serviceItemMap = Object.fromEntries(
    serviceItems
      .filter((item) => item.posting_status === 'posted')
      .map((item) => [item.source_id, item])
  )
  const exceptionMap = Object.fromEntries(
    exceptions
      .filter((item) => item.status === 'open')
      .map((item) => [`${item.source_table}:${item.source_id}`, item])
  )

  return {
    folios: folios.map((folio) => ({
      ...folio,
      guest: guestMap[folio.guest_id] || null,
      room: roomMap[folio.room_id] || null,
      guestSession: sessionMap[folio.guest_session_id] || null,
    })),
    exceptions,
    serviceTypes,
    serviceRequests: serviceRequests.map((request) => ({
      ...request,
      guest: guestMap[request.guest_id] || null,
      room: roomMap[request.room_id] || null,
      serviceType: serviceTypeMap[request.request_type_id] || null,
      postedItem: serviceItemMap[request.id] || null,
      sourceException:
        exceptionMap[`service_requests:${request.id}`] || null,
    })),
    webhookEvents,
    serviceItems,
  }
}

export async function loadFolioDetails(hotelId, folioId) {
  if (!hotelId || !folioId) return null

  const [
    folioResponse,
    itemResponse,
    collectionResponse,
    discountResponse,
    refundResponse,
    creditResponse,
    adjustmentResponse,
    webhookResponse,
    eventResponse,
  ] = await Promise.all([
    supabase
      .from('folios')
      .select('*')
      .eq('hotel_id', hotelId)
      .eq('id', folioId)
      .single(),
    supabase
      .from('folio_items')
      .select('*')
      .eq('hotel_id', hotelId)
      .eq('folio_id', folioId)
      .order('service_at', { ascending: false }),
    supabase
      .from('folio_collections')
      .select('*')
      .eq('hotel_id', hotelId)
      .eq('folio_id', folioId)
      .order('collected_at', { ascending: false }),
    supabase
      .from('discount_approvals')
      .select('*')
      .eq('hotel_id', hotelId)
      .eq('folio_id', folioId)
      .order('requested_at', { ascending: false }),
    supabase
      .from('refunds')
      .select('*')
      .eq('hotel_id', hotelId)
      .eq('folio_id', folioId)
      .order('requested_at', { ascending: false }),
    supabase
      .from('credit_notes')
      .select('*')
      .eq('hotel_id', hotelId)
      .eq('folio_id', folioId)
      .order('issued_at', { ascending: false }),
    supabase
      .from('folio_adjustments')
      .select('*')
      .eq('hotel_id', hotelId)
      .eq('folio_id', folioId)
      .order('posted_at', { ascending: false }),
    supabase
      .from('payment_webhook_events')
      .select('*')
      .eq('hotel_id', hotelId)
      .eq('folio_id', folioId)
      .order('received_at', { ascending: false }),
    supabase
      .from('folio_events')
      .select('*')
      .eq('hotel_id', hotelId)
      .eq('folio_id', folioId)
      .order('created_at', { ascending: false })
      .limit(200),
  ])

  if (folioResponse.error) {
    throw new Error(folioResponse.error.message || 'Load folio failed.')
  }

  return {
    folio: folioResponse.data,
    items: assertResponse(itemResponse, 'Load folio items'),
    collections: assertResponse(collectionResponse, 'Load collections'),
    discounts: assertResponse(discountResponse, 'Load discounts'),
    refunds: assertResponse(refundResponse, 'Load refunds'),
    creditNotes: assertResponse(creditResponse, 'Load credit notes'),
    adjustments: assertResponse(adjustmentResponse, 'Load adjustments'),
    webhookEvents: assertResponse(webhookResponse, 'Load folio gateway events'),
    events: assertResponse(eventResponse, 'Load folio audit events'),
  }
}

async function invoke(name, args) {
  const { data, error } = await supabase.rpc(name, args)

  if (error) {
    throw new Error(error.message || `${name} failed.`)
  }

  if (data?.ok === false) {
    throw new Error(data.reason || `${name} was rejected.`)
  }

  return data
}

export function postFolioCollection(hotelId, folioId, values, requestId) {
  return invoke('post_folio_collection', {
    target_hotel_id: hotelId,
    target_folio_id: folioId,
    amount_value: Number(values.amount),
    payment_method_value: values.payment_method,
    transaction_reference_value: values.transaction_reference || null,
    provider_value: values.provider || null,
    provider_payment_id_value: values.provider_payment_id || null,
    request_id_value: requestId,
  })
}

export function postFolioSplitCollection(
  hotelId,
  folioId,
  lines,
  requestId
) {
  return invoke('post_folio_split_collection', {
    target_hotel_id: hotelId,
    target_folio_id: folioId,
    collection_lines: lines.map((line) => ({
      amount: Number(line.amount),
      payment_method: line.payment_method,
      transaction_reference: line.transaction_reference || null,
      provider: line.provider || null,
      provider_payment_id: line.provider_payment_id || null,
    })),
    request_id_value: requestId,
  })
}

export function requestFolioDiscount(
  hotelId,
  folioId,
  values,
  requestId
) {
  return invoke('request_folio_discount', {
    target_hotel_id: hotelId,
    target_folio_id: folioId,
    discount_type_value: values.discount_type,
    requested_value_value: Number(values.requested_value),
    reason_value: values.reason,
    request_id_value: requestId,
  })
}

export function reviewFolioDiscount(
  hotelId,
  approvalId,
  approve,
  notes,
  requestId
) {
  return invoke('review_folio_discount', {
    target_hotel_id: hotelId,
    target_approval_id: approvalId,
    approve_value: Boolean(approve),
    review_notes_value: notes || null,
    request_id_value: requestId,
  })
}

export function requestFolioRefund(
  hotelId,
  folioId,
  values,
  requestId
) {
  return invoke('request_folio_refund', {
    target_hotel_id: hotelId,
    target_folio_id: folioId,
    target_collection_id: values.collection_id,
    amount_value: Number(values.amount),
    reason_value: values.reason,
    request_id_value: requestId,
  })
}

export function processFolioRefund(hotelId, refundId, values, requestId) {
  return invoke('process_folio_refund', {
    target_hotel_id: hotelId,
    target_refund_id: refundId,
    provider_refund_id_value: values.provider_refund_id || null,
    transaction_reference_value: values.transaction_reference || null,
    request_id_value: requestId,
  })
}

export function issueFolioCreditNote(
  hotelId,
  folioId,
  values,
  requestId
) {
  return invoke('issue_folio_credit_note', {
    target_hotel_id: hotelId,
    target_folio_id: folioId,
    amount_value: Number(values.amount),
    reason_value: values.reason,
    request_id_value: requestId,
  })
}

export function voidFolioCreditNote(
  hotelId,
  creditNoteId,
  reason,
  requestId
) {
  return invoke('void_folio_credit_note', {
    target_hotel_id: hotelId,
    target_credit_note_id: creditNoteId,
    void_reason_value: reason,
    request_id_value: requestId,
  })
}

export function configureServiceRequestCharge(
  hotelId,
  requestTypeId,
  values,
  requestId
) {
  return invoke('configure_service_request_charge', {
    target_hotel_id: hotelId,
    target_request_type_id: requestTypeId,
    charge_enabled_value: Boolean(values.charge_enabled),
    default_charge_amount_value: values.charge_enabled
      ? Number(values.default_charge_amount)
      : null,
    posting_policy_value: values.charge_posting_policy,
    charge_description_value: values.charge_description || null,
    taxable_value: Boolean(values.charge_taxable),
    request_id_value: requestId,
  })
}

export function postServiceRequestCharge(hotelId, requestId, operationId) {
  return invoke('post_service_request_charge', {
    target_hotel_id: hotelId,
    target_request_id: requestId,
    request_id_value: operationId,
  })
}
