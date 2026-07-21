import { supabase } from './supabase'

export const CALENDAR_INVALIDATION_EVENT = 'stayqr:calendar-invalidated'
export const NAVIGATE_EVENT = 'stayqr:navigate'

function throwIfError(error) {
  if (error) throw error
}

export function notifyCalendarInvalidated(detail = {}) {
  window.dispatchEvent(
    new CustomEvent(CALENDAR_INVALIDATION_EVENT, { detail })
  )
}

export function navigateToSection(section, detail = {}) {
  window.dispatchEvent(
    new CustomEvent(NAVIGATE_EVENT, {
      detail: { section, ...detail },
    })
  )
}

export async function getBookingCalendar({
  hotelId,
  rangeStart,
  rangeEnd,
  roomTypeId = null,
  reservationStatuses = null,
  blockStatuses = ['active'],
  limit = 24,
  offset = 0,
}) {
  const { data, error } = await supabase.rpc('get_booking_calendar', {
    target_hotel_id: hotelId,
    range_start: rangeStart,
    range_end: rangeEnd,
    room_type_filter: roomTypeId || null,
    reservation_status_filter:
      reservationStatuses?.length > 0 ? reservationStatuses : null,
    block_status_filter: blockStatuses?.length > 0 ? blockStatuses : null,
    page_limit: limit,
    page_offset: offset,
  })

  throwIfError(error)
  return (
    data || {
      rooms: [],
      events: [],
      unallocated_reservations: [],
      pagination: {
        total_rooms: 0,
        limit,
        offset,
        has_previous: false,
        has_next: false,
      },
    }
  )
}

export async function moveReservationOnCalendar({
  hotelId,
  reservationId,
  reservationRoomId,
  roomId,
  arrivalDate,
  expectedUpdatedAt,
}) {
  const { data, error } = await supabase.rpc(
    'move_reservation_on_calendar',
    {
      target_hotel_id: hotelId,
      target_reservation_id: reservationId,
      target_reservation_room_id: reservationRoomId,
      target_room_id: roomId,
      target_arrival_date: arrivalDate,
      expected_updated_at: expectedUpdatedAt || null,
    }
  )

  throwIfError(error)
  notifyCalendarInvalidated({
    reason: 'reservation_moved',
    reservationId,
  })
  return data
}

export async function createCalendarRoomBlock(hotelId, payload) {
  const { data, error } = await supabase.rpc(
    'create_calendar_room_block',
    {
      target_hotel_id: hotelId,
      block_payload: payload,
    }
  )

  throwIfError(error)
  notifyCalendarInvalidated({ reason: 'room_block_created' })
  return data
}

export async function updateCalendarRoomBlock({
  hotelId,
  roomBlockId,
  payload,
  expectedUpdatedAt,
}) {
  const { data, error } = await supabase.rpc(
    'update_calendar_room_block',
    {
      target_hotel_id: hotelId,
      target_room_block_id: roomBlockId,
      block_payload: payload,
      expected_updated_at: expectedUpdatedAt || null,
    }
  )

  throwIfError(error)
  notifyCalendarInvalidated({ reason: 'room_block_updated' })
  return data
}

export async function changeCalendarRoomBlockStatus({
  hotelId,
  roomBlockId,
  status,
  reason,
}) {
  const { data, error } = await supabase.rpc(
    'change_calendar_room_block_status',
    {
      target_hotel_id: hotelId,
      target_room_block_id: roomBlockId,
      target_status: status,
      reason,
    }
  )

  throwIfError(error)
  notifyCalendarInvalidated({
    reason: `room_block_${status}`,
  })
  return data
}

export async function getCalendarRoomBlockDetails(hotelId, roomBlockId) {
  const { data, error } = await supabase.rpc(
    'get_calendar_room_block_details',
    {
      target_hotel_id: hotelId,
      target_room_block_id: roomBlockId,
    }
  )

  throwIfError(error)
  return data
}
