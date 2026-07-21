import { supabase } from './supabase'

function throwIfError(error) {
  if (error) throw error
}

export async function getReservationConfiguration(hotelId) {
  const [roomTypesResult, ratePlansResult] = await Promise.all([
    supabase
      .from('room_types')
      .select(
        'id, hotel_id, name, code, description, base_occupancy, max_adults, max_children, max_occupancy, base_rate, is_active, sort_order'
      )
      .eq('hotel_id', hotelId)
      .eq('is_active', true)
      .order('sort_order', { ascending: true })
      .order('name', { ascending: true }),
    supabase
      .from('rate_plans')
      .select(
        'id, hotel_id, room_type_id, name, code, description, meal_plan, currency_code, base_rate, extra_adult_rate, extra_child_rate, minimum_stay, maximum_stay, cancellation_policy, is_refundable, is_active, priority'
      )
      .eq('hotel_id', hotelId)
      .eq('is_active', true)
      .order('priority', { ascending: true })
      .order('name', { ascending: true }),
  ])

  throwIfError(roomTypesResult.error)
  throwIfError(ratePlansResult.error)

  return {
    roomTypes: roomTypesResult.data || [],
    ratePlans: ratePlansResult.data || [],
  }
}

export async function listReservations({
  hotelId,
  status = null,
  search = null,
  arrivalFrom = null,
  arrivalTo = null,
  limit = 50,
  offset = 0,
}) {
  const { data, error } = await supabase.rpc('get_reservations', {
    target_hotel_id: hotelId,
    status_filter: status || null,
    search_text: search || null,
    arrival_from: arrivalFrom || null,
    arrival_to: arrivalTo || null,
    page_limit: limit,
    page_offset: offset,
  })

  throwIfError(error)
  return data || { items: [], total_count: 0, limit, offset }
}

export async function getReservationDetails(hotelId, reservationId) {
  const { data, error } = await supabase.rpc('get_reservation_details', {
    target_hotel_id: hotelId,
    target_reservation_id: reservationId,
  })

  throwIfError(error)
  return data
}

export async function searchGuests(hotelId, searchText, limit = 20) {
  const { data, error } = await supabase.rpc('search_reservation_guests', {
    target_hotel_id: hotelId,
    search_text: searchText || null,
    result_limit: limit,
  })

  throwIfError(error)
  return data || []
}

export async function getAvailableRooms({
  hotelId,
  arrivalDate,
  departureDate,
  roomTypeId = null,
  excludeReservationId = null,
}) {
  const { data, error } = await supabase.rpc(
    'get_reservation_available_rooms',
    {
      target_hotel_id: hotelId,
      target_arrival_date: arrivalDate,
      target_departure_date: departureDate,
      target_room_type_id: roomTypeId || null,
      exclude_reservation_id: excludeReservationId || null,
    }
  )

  throwIfError(error)
  return data || []
}

export async function getRateQuote({
  hotelId,
  ratePlanId,
  arrivalDate,
  departureDate,
  adults = 1,
  children = 0,
}) {
  const { data, error } = await supabase.rpc(
    'get_reservation_rate_quote',
    {
      target_hotel_id: hotelId,
      target_rate_plan_id: ratePlanId,
      target_arrival_date: arrivalDate,
      target_departure_date: departureDate,
      target_adults: Number(adults),
      target_children: Number(children),
    }
  )

  throwIfError(error)
  return data
}

export async function createReservation(hotelId, payload) {
  const { data, error } = await supabase.rpc('create_reservation', {
    target_hotel_id: hotelId,
    reservation_payload: payload,
  })

  throwIfError(error)
  return data
}

export async function updateReservation({
  hotelId,
  reservationId,
  payload,
  expectedUpdatedAt,
}) {
  const { data, error } = await supabase.rpc('update_reservation', {
    target_hotel_id: hotelId,
    target_reservation_id: reservationId,
    reservation_payload: payload,
    expected_updated_at: expectedUpdatedAt || null,
  })

  throwIfError(error)
  return data
}

export async function changeReservationStatus({
  hotelId,
  reservationId,
  status,
  reason = null,
}) {
  const { data, error } = await supabase.rpc(
    'change_reservation_status',
    {
      target_hotel_id: hotelId,
      target_reservation_id: reservationId,
      target_status: status,
      reason: reason || null,
    }
  )

  throwIfError(error)
  return data
}

export async function getReservationActivity(hotelId, reservationId) {
  const { data, error } = await supabase
    .from('activity_logs')
    .select(
      'id, action, actor_role, description, before_data, after_data, metadata, actor_user_id, created_at'
    )
    .eq('hotel_id', hotelId)
    .eq('entity_type', 'reservation')
    .eq('entity_id', reservationId)
    .order('created_at', { ascending: false })

  throwIfError(error)
  return data || []
}
