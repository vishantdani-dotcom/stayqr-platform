import { supabase } from './supabase'

const ONBOARDING_REQUEST_KEY_PREFIX = 'stayqr:onboarding-request'
const ONBOARDING_DRAFT_KEY_PREFIX = 'stayqr:onboarding-draft'

function getScopedKey(prefix, userId) {
  return `${prefix}:${userId || 'anonymous'}`
}

export function getOrCreateOnboardingRequestId(userId) {
  const key = getScopedKey(ONBOARDING_REQUEST_KEY_PREFIX, userId)
  const stored = window.localStorage.getItem(key)

  if (stored) return stored

  const requestId = crypto.randomUUID()
  window.localStorage.setItem(key, requestId)
  return requestId
}

export function resetOnboardingRequestId(userId) {
  window.localStorage.removeItem(
    getScopedKey(ONBOARDING_REQUEST_KEY_PREFIX, userId)
  )
}

export function saveOnboardingDraft(userId, draft) {
  window.localStorage.setItem(
    getScopedKey(ONBOARDING_DRAFT_KEY_PREFIX, userId),
    JSON.stringify(draft)
  )
}

export function loadOnboardingDraft(userId) {
  const raw = window.localStorage.getItem(
    getScopedKey(ONBOARDING_DRAFT_KEY_PREFIX, userId)
  )

  if (!raw) return null

  try {
    return JSON.parse(raw)
  } catch {
    return null
  }
}

export function clearOnboardingDraft(userId) {
  window.localStorage.removeItem(
    getScopedKey(ONBOARDING_DRAFT_KEY_PREFIX, userId)
  )
}

function unwrapRpc(data) {
  if (Array.isArray(data)) return data[0] || null
  return data || null
}

function throwIfError(error) {
  if (error) throw error
}

export async function fetchActiveSubscriptionPlans() {
  const { data, error } = await supabase
    .from('subscription_plans')
    .select(
      'id, plan_name, price_monthly, max_rooms, features, status'
    )
    .eq('status', 'active')
    .order('price_monthly', { ascending: true })

  throwIfError(error)
  return data || []
}

export async function bootstrapHotel(payload) {
  const { data, error } = await supabase.rpc(
    'bootstrap_hotel_onboarding',
    { payload }
  )

  throwIfError(error)
  return unwrapRpc(data)
}

export async function configureHotelInventory(hotelId, payload) {
  const { data, error } = await supabase.rpc(
    'configure_hotel_inventory',
    {
      target_hotel_id: hotelId,
      payload,
    }
  )

  throwIfError(error)
  return unwrapRpc(data)
}

export async function importHotelRooms(hotelId, payload) {
  const { data, error } = await supabase.rpc('import_hotel_rooms', {
    target_hotel_id: hotelId,
    payload,
  })

  throwIfError(error)
  return unwrapRpc(data)
}

export async function seedHotelConfigurationDefaults(hotelId) {
  const { data, error } = await supabase.rpc(
    'seed_hotel_configuration_defaults',
    { target_hotel_id: hotelId }
  )

  throwIfError(error)
  return unwrapRpc(data)
}

export async function getHotelOnboardingReadiness(hotelId) {
  const { data, error } = await supabase.rpc(
    'get_hotel_onboarding_readiness',
    { target_hotel_id: hotelId }
  )

  throwIfError(error)
  return unwrapRpc(data)
}

export async function refreshHotelOnboardingReadiness(hotelId) {
  const { data, error } = await supabase.rpc(
    'refresh_hotel_onboarding_readiness',
    { target_hotel_id: hotelId }
  )

  throwIfError(error)
  return unwrapRpc(data)
}

export async function saveHotelOnboardingStep(
  hotelId,
  step,
  payload
) {
  const { data, error } = await supabase.rpc(
    'save_hotel_onboarding_step',
    {
      target_hotel_id: hotelId,
      target_step: step,
      step_payload: payload,
    }
  )

  throwIfError(error)
  return unwrapRpc(data)
}

export async function fetchHotelSetupSnapshot(hotelId) {
  if (!hotelId) return null

  const [
    hotelResult,
    infoResult,
    settingsResult,
    onboardingResult,
    floorsResult,
    roomTypesResult,
    ratePlansResult,
    roomsResult,
    amenitiesResult,
    requestTypesResult,
    categoriesResult,
    menuItemsResult,
    invoiceResult,
    subscriptionResult,
  ] = await Promise.all([
    supabase
      .from('hotels')
      .select(
        'id, hotel_name, owner_name, email, phone, address, city, state, location, website, gst_number, slug, timezone, currency_code, subscription_status, status'
      )
      .eq('id', hotelId)
      .single(),
    supabase
      .from('hotel_info')
      .select('*')
      .eq('hotel_id', hotelId)
      .maybeSingle(),
    supabase
      .from('hotel_settings')
      .select('*')
      .eq('hotel_id', hotelId)
      .maybeSingle(),
    supabase
      .from('hotel_onboarding')
      .select('*')
      .eq('hotel_id', hotelId)
      .maybeSingle(),
    supabase
      .from('floors')
      .select('*')
      .eq('hotel_id', hotelId)
      .order('sort_order', { ascending: true }),
    supabase
      .from('room_types')
      .select('*')
      .eq('hotel_id', hotelId)
      .order('sort_order', { ascending: true }),
    supabase
      .from('rate_plans')
      .select('*')
      .eq('hotel_id', hotelId)
      .order('priority', { ascending: true }),
    supabase
      .from('rooms')
      .select('id, room_number, room_type, room_type_id, floor_id, status')
      .eq('hotel_id', hotelId)
      .order('room_number', { ascending: true }),
    supabase
      .from('amenities')
      .select('*')
      .eq('hotel_id', hotelId)
      .order('sort_order', { ascending: true }),
    supabase
      .from('service_request_types')
      .select('*')
      .eq('hotel_id', hotelId)
      .order('sort_order', { ascending: true }),
    supabase
      .from('menu_categories')
      .select('*')
      .eq('hotel_id', hotelId)
      .order('sort_order', { ascending: true }),
    supabase
      .from('menu_items')
      .select('*')
      .eq('hotel_id', hotelId)
      .order('item_name', { ascending: true }),
    supabase
      .from('invoice_number_sequences')
      .select('*')
      .eq('hotel_id', hotelId)
      .order('sequence_year', { ascending: false })
      .limit(1)
      .maybeSingle(),
    supabase
      .from('hotel_subscriptions')
      .select(
        '*, subscription_plans (id, plan_name, price_monthly, max_rooms)'
      )
      .eq('hotel_id', hotelId)
      .in('status', ['trial', 'trialing', 'active', 'past_due'])
      .order('created_at', { ascending: false })
      .limit(1)
      .maybeSingle(),
  ])

  const results = [
    hotelResult,
    infoResult,
    settingsResult,
    onboardingResult,
    floorsResult,
    roomTypesResult,
    ratePlansResult,
    roomsResult,
    amenitiesResult,
    requestTypesResult,
    categoriesResult,
    menuItemsResult,
    invoiceResult,
    subscriptionResult,
  ]

  const firstError = results.find((result) => result.error)?.error
  throwIfError(firstError)

  return {
    hotel: hotelResult.data,
    hotelInfo: infoResult.data,
    settings: settingsResult.data,
    onboarding: onboardingResult.data,
    floors: floorsResult.data || [],
    roomTypes: roomTypesResult.data || [],
    ratePlans: ratePlansResult.data || [],
    rooms: roomsResult.data || [],
    amenities: amenitiesResult.data || [],
    requestTypes: requestTypesResult.data || [],
    menuCategories: categoriesResult.data || [],
    menuItems: menuItemsResult.data || [],
    invoiceSequence: invoiceResult.data,
    subscription: subscriptionResult.data,
  }
}

export async function updateHotelBasics(hotelId, values) {
  const hotelPayload = {
    hotel_name: values.hotel_name.trim(),
    owner_name: values.owner_name.trim() || null,
    email: values.contact_email.trim().toLowerCase(),
    phone: values.phone.trim() || null,
    address: values.address.trim() || null,
    city: values.city.trim() || null,
    state: values.state.trim() || null,
    location:
      values.location.trim() ||
      [values.city.trim(), values.state.trim()].filter(Boolean).join(', ') ||
      null,
    website: values.website.trim() || null,
    gst_number: values.tax_registration_number.trim() || null,
    timezone: values.timezone,
    currency_code: values.currency_code.toUpperCase(),
  }

  const settingsPayload = {
    legal_name: values.hotel_name.trim(),
    tax_registration_number:
      values.tax_registration_number.trim() || null,
    default_tax_percent: Number(values.default_tax_percent || 0),
    prices_include_tax: Boolean(values.prices_include_tax),
    checkin_time: values.checkin_time,
    checkout_time: values.checkout_time,
    cancellation_policy: values.cancellation_policy.trim() || null,
    house_rules: values.house_rules.trim() || null,
    terms_and_conditions:
      values.terms_and_conditions.trim() || null,
    invoice_notes: values.invoice_notes.trim() || null,
  }

  const infoPayload = {
    hotel_name: values.hotel_name.trim(),
    address: hotelPayload.address || hotelPayload.location,
    reception_phone: hotelPayload.phone,
    emergency_phone: hotelPayload.phone,
    checkin_time: formatTimeForDisplay(values.checkin_time),
    checkout_time: formatTimeForDisplay(values.checkout_time),
    hotel_rules: settingsPayload.house_rules,
  }

  const [hotelResult, settingsResult, infoResult] = await Promise.all([
    supabase.from('hotels').update(hotelPayload).eq('id', hotelId),
    supabase
      .from('hotel_settings')
      .update(settingsPayload)
      .eq('hotel_id', hotelId),
    supabase.from('hotel_info').update(infoPayload).eq('hotel_id', hotelId),
  ])

  throwIfError(hotelResult.error || settingsResult.error || infoResult.error)
}

export async function addMenuItem(hotelId, values) {
  const { data, error } = await supabase
    .from('menu_items')
    .insert({
      hotel_id: hotelId,
      category_id: values.category_id,
      category: values.category_name,
      item_name: values.item_name.trim(),
      description: values.description.trim() || null,
      price: Number(values.price),
      is_available: true,
    })
    .select('*')
    .single()

  throwIfError(error)
  return data
}

export async function updateAmenity(hotelId, amenityId, patch) {
  const { error } = await supabase
    .from('amenities')
    .update(patch)
    .eq('hotel_id', hotelId)
    .eq('id', amenityId)

  throwIfError(error)
}

export async function addAmenity(hotelId, values) {
  const code = normalizeCode(values.code || values.name)
  const { data, error } = await supabase
    .from('amenities')
    .insert({
      hotel_id: hotelId,
      name: values.name.trim(),
      code,
      category: values.category.trim() || 'general',
      description: values.description.trim() || null,
      icon: values.icon.trim() || null,
      guest_visible: true,
      is_active: true,
    })
    .select('*')
    .single()

  throwIfError(error)
  return data
}

export async function updateRequestType(hotelId, requestTypeId, patch) {
  const { error } = await supabase
    .from('service_request_types')
    .update(patch)
    .eq('hotel_id', hotelId)
    .eq('id', requestTypeId)

  throwIfError(error)
}

export async function addRequestType(hotelId, values) {
  const code = normalizeCode(values.code || values.name)
  const { data, error } = await supabase
    .from('service_request_types')
    .insert({
      hotel_id: hotelId,
      name: values.name.trim(),
      code,
      description: values.description.trim() || null,
      default_priority: values.default_priority || 'normal',
      default_estimated_minutes:
        values.default_estimated_minutes === ''
          ? null
          : Number(values.default_estimated_minutes),
      guest_visible: true,
      is_active: true,
    })
    .select('*')
    .single()

  throwIfError(error)
  return data
}

export function parseRoomsCsv(csvText) {
  const lines = String(csvText || '')
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean)

  if (lines.length < 2) {
    throw new Error('Add a header row and at least one room row.')
  }

  const headers = splitCsvLine(lines[0]).map((header) =>
    header.trim().toLowerCase()
  )

  const required = ['room_number', 'room_type_code', 'floor_code']
  const missing = required.filter((column) => !headers.includes(column))

  if (missing.length > 0) {
    throw new Error(`CSV is missing: ${missing.join(', ')}`)
  }

  return lines.slice(1).map((line, index) => {
    const values = splitCsvLine(line)
    const row = Object.fromEntries(
      headers.map((header, columnIndex) => [
        header,
        String(values[columnIndex] || '').trim(),
      ])
    )

    if (!row.room_number || !row.room_type_code || !row.floor_code) {
      throw new Error(`CSV row ${index + 2} is incomplete.`)
    }

    return {
      room_number: row.room_number,
      room_type_code: row.room_type_code.toUpperCase(),
      floor_code: row.floor_code.toUpperCase(),
      status: (row.status || 'available').toLowerCase(),
    }
  })
}

function splitCsvLine(line) {
  const values = []
  let current = ''
  let quoted = false

  for (let index = 0; index < line.length; index += 1) {
    const char = line[index]
    const next = line[index + 1]

    if (char === '"' && quoted && next === '"') {
      current += '"'
      index += 1
    } else if (char === '"') {
      quoted = !quoted
    } else if (char === ',' && !quoted) {
      values.push(current)
      current = ''
    } else {
      current += char
    }
  }

  values.push(current)
  return values
}

function normalizeCode(value) {
  return String(value || '')
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 48)
}

function formatTimeForDisplay(value) {
  const [hoursText, minutesText = '00'] = String(value || '00:00').split(':')
  const hours = Number(hoursText)
  const suffix = hours >= 12 ? 'PM' : 'AM'
  const displayHours = hours % 12 || 12
  return `${displayHours}:${minutesText.slice(0, 2)} ${suffix}`
}
