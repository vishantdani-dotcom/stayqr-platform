import { supabase } from './supabase'

function assertRpc(result, label) {
  if (result.error) {
    throw new Error(result.error.message || `${label} failed.`)
  }

  if (result.data?.ok === false) {
    throw new Error(result.data.reason || `${label} failed.`)
  }

  return result.data
}

export function createV11RequestId(prefix = 'v11') {
  const randomPart =
    typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function'
      ? crypto.randomUUID()
      : `${Date.now()}-${Math.random().toString(16).slice(2)}`

  return `${prefix}:${randomPart}`
}

export async function loadRevenueGrowthWorkspace(hotelId) {
  return assertRpc(
    await supabase.rpc('get_v11_revenue_workspace', {
      p_hotel_id: hotelId,
    }),
    'Load Revenue Growth workspace'
  )
}

export async function savePublicBookingSettings(hotelId, payload) {
  return assertRpc(
    await supabase.rpc('upsert_v11_public_booking_settings', {
      p_hotel_id: hotelId,
      p_payload: payload,
    }),
    'Save direct booking settings'
  )
}

export async function saveCorporateAccount(hotelId, payload) {
  return assertRpc(
    await supabase.rpc('upsert_v11_corporate_account', {
      p_hotel_id: hotelId,
      p_payload: payload,
    }),
    'Save corporate account'
  )
}

export async function saveCorporateRate(hotelId, payload) {
  return assertRpc(
    await supabase.rpc('upsert_v11_corporate_rate', {
      p_hotel_id: hotelId,
      p_payload: payload,
    }),
    'Save corporate rate'
  )
}

export async function createStayMovePlan({
  hotelId,
  guestSessionId,
  targetRoomId,
  plannedDate,
  notes,
}) {
  return assertRpc(
    await supabase.rpc('create_v11_stay_move_plan', {
      p_hotel_id: hotelId,
      p_guest_session_id: guestSessionId,
      p_to_room_id: targetRoomId,
      p_planned_date: plannedDate,
      p_notes: notes || null,
    }),
    'Create split-stay move plan'
  )
}

export async function cancelStayMovePlan(hotelId, planId) {
  return assertRpc(
    await supabase.rpc('cancel_v11_stay_move_plan', {
      p_hotel_id: hotelId,
      p_plan_id: planId,
    }),
    'Cancel split-stay move plan'
  )
}

export async function verifyStayMovePlan(hotelId, planId) {
  return assertRpc(
    await supabase.rpc('verify_v11_stay_move_plan', {
      p_hotel_id: hotelId,
      p_plan_id: planId,
    }),
    'Verify split-stay move plan'
  )
}

export async function replaceFolioSplitPlan(hotelId, folioId, shares) {
  return assertRpc(
    await supabase.rpc('replace_v11_folio_split_plan', {
      p_hotel_id: hotelId,
      p_folio_id: folioId,
      p_shares: shares,
    }),
    'Save split-bill plan'
  )
}

export async function postSplitShareCollection({
  hotelId,
  shareId,
  amount,
  paymentMethod,
  transactionReference,
  requestId,
}) {
  return assertRpc(
    await supabase.rpc('post_v11_split_share_collection', {
      p_hotel_id: hotelId,
      p_share_id: shareId,
      p_amount: Number(amount),
      p_payment_method: paymentMethod,
      p_transaction_reference: transactionReference || null,
      p_request_id: requestId || createV11RequestId('split-share'),
    }),
    'Post split-bill collection'
  )
}

export async function saveAccountingProfile(hotelId, payload) {
  return assertRpc(
    await supabase.rpc('upsert_v11_accounting_profile', {
      p_hotel_id: hotelId,
      p_payload: payload,
    }),
    'Save accounting export profile'
  )
}

export async function generateV11AccountingExport({
  hotelId,
  profileId,
  dateFrom,
  dateTo,
  requestId,
}) {
  return assertRpc(
    await supabase.rpc('generate_v11_accounting_export', {
      p_hotel_id: hotelId,
      p_profile_id: profileId,
      p_date_from: dateFrom,
      p_date_to: dateTo,
      p_request_id: requestId || createV11RequestId('accounting-export'),
    }),
    'Generate accounting export'
  )
}

export async function loadPublicBookingHotel(hotelSlug) {
  return assertRpc(
    await supabase.rpc('get_public_booking_hotel', {
      p_hotel_slug: hotelSlug,
    }),
    'Load hotel booking page'
  )
}

export async function loadPublicBookingOptions({
  hotelSlug,
  arrivalDate,
  departureDate,
  adults,
  children,
  corporateCode,
}) {
  return assertRpc(
    await supabase.rpc('get_public_booking_options', {
      p_hotel_slug: hotelSlug,
      p_arrival_date: arrivalDate,
      p_departure_date: departureDate,
      p_adults: Number(adults),
      p_children: Number(children),
      p_corporate_code: corporateCode?.trim() || null,
    }),
    'Check room availability'
  )
}

export async function createPublicBooking({ hotelSlug, requestId, payload }) {
  return assertRpc(
    await supabase.rpc('create_public_booking', {
      p_hotel_slug: hotelSlug,
      p_request_id: requestId,
      p_payload: payload,
    }),
    'Create direct booking'
  )
}

export function downloadAccountingExport(exportRecord) {
  if (!exportRecord?.csv_content) {
    throw new Error('Accounting export has no CSV content.')
  }

  const blob = new Blob([exportRecord.csv_content], {
    type: exportRecord.content_type || 'text/csv;charset=utf-8',
  })
  const url = URL.createObjectURL(blob)
  const anchor = document.createElement('a')
  anchor.href = url
  anchor.download = exportRecord.file_name || 'stayqr-accounting.csv'
  document.body.appendChild(anchor)
  anchor.click()
  anchor.remove()
  URL.revokeObjectURL(url)
}
