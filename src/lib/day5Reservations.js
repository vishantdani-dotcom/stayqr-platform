import { supabase } from './supabase'

function throwIfError(error) {
  if (error) throw error
}

function throwIfRejected(data, fallbackMessage) {
  if (!data || typeof data !== 'object') return
  if (data.success !== false && data.ok !== false) return

  throw new Error(
    data.reason || data.message || data.error || fallbackMessage
  )
}

export async function checkInReservationRoom({
  hotelId,
  reservationId,
  reservationRoomId,
  expectedUpdatedAt = null,
}) {
  const { data, error } = await supabase.rpc('check_in_reservation_room', {
    target_hotel_id: hotelId,
    target_reservation_id: reservationId,
    target_reservation_room_id: reservationRoomId,
    expected_reservation_updated_at: expectedUpdatedAt || null,
  })

  throwIfError(error)
  throwIfRejected(data, 'StayQR could not complete the reservation check-in.')
  return data
}

export async function getReservationOperations({
  hotelId,
  businessDate,
  upcomingDays = 7,
}) {
  const { data, error } = await supabase.rpc('get_reservation_operations', {
    target_hotel_id: hotelId,
    target_date: businessDate || null,
    upcoming_days: Number(upcomingDays) || 7,
  })

  throwIfError(error)
  return (
    data || {
      today_arrivals: [],
      upcoming_arrivals: [],
      today_departures: [],
      in_house: [],
      unallocated_arrivals: [],
      overdue_arrivals: [],
    }
  )
}

export async function getReservationConfirmation(hotelId, reservationId) {
  const { data, error } = await supabase.rpc('get_reservation_confirmation', {
    target_hotel_id: hotelId,
    target_reservation_id: reservationId,
  })

  throwIfError(error)
  return data
}

export async function addReservationRoom({
  hotelId,
  reservationId,
  payload,
  expectedUpdatedAt = null,
}) {
  const { data, error } = await supabase.rpc('add_reservation_room', {
    target_hotel_id: hotelId,
    target_reservation_id: reservationId,
    room_payload: payload,
    expected_updated_at: expectedUpdatedAt || null,
  })

  throwIfError(error)
  throwIfRejected(data, 'StayQR could not add the reservation room.')
  return data
}

export async function removeReservationRoom({
  hotelId,
  reservationId,
  reservationRoomId,
  expectedUpdatedAt = null,
}) {
  const { data, error } = await supabase.rpc('remove_reservation_room', {
    target_hotel_id: hotelId,
    target_reservation_id: reservationId,
    target_reservation_room_id: reservationRoomId,
    expected_updated_at: expectedUpdatedAt || null,
  })

  throwIfError(error)
  throwIfRejected(data, 'StayQR could not remove the reservation room.')
  return data
}

export async function checkoutGuestSession({
  hotelId,
  guestSessionId,
  taxPercent = 0,
  discountType = 'fixed',
  discountValue = 0,
  remainingPaymentCollected = false,
  settlementPaymentMethod = 'cash',
  settlementTransactionReference = null,
  invoiceNotes = null,
  allowExcessPaid = false,
}) {
  const { data, error } = await supabase.rpc('checkout_guest_session', {
    target_hotel_id: hotelId,
    target_guest_session_id: guestSessionId,
    tax_percent: Number(taxPercent) || 0,
    discount_type: discountType || 'fixed',
    discount_value: Number(discountValue) || 0,
    remaining_payment_collected: Boolean(remainingPaymentCollected),
    settlement_payment_method: settlementPaymentMethod || 'cash',
    settlement_transaction_reference:
      settlementTransactionReference?.trim() || null,
    invoice_notes: invoiceNotes?.trim() || null,
    allow_excess_paid: Boolean(allowExcessPaid),
  })

  throwIfError(error)
  throwIfRejected(data, 'StayQR could not complete the final checkout.')
  return data
}
