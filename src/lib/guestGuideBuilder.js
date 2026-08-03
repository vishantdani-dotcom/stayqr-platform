import { supabase } from './supabase'

export const GUEST_GUIDE_BUCKET = 'guest-guide-media'

export const GUEST_GUIDE_LOCALES = [
  { code: 'en', label: 'English', nativeName: 'English' },
  { code: 'hi', label: 'Hindi', nativeName: 'हिन्दी' },
  { code: 'mr', label: 'Marathi', nativeName: 'मराठी' },
  { code: 'ta', label: 'Tamil', nativeName: 'தமிழ்' },
  { code: 'te', label: 'Telugu', nativeName: 'తెలుగు' },
  { code: 'bn', label: 'Bengali', nativeName: 'বাংলা' },
  { code: 'gu', label: 'Gujarati', nativeName: 'ગુજરાતી' },
  { code: 'kn', label: 'Kannada', nativeName: 'ಕನ್ನಡ' },
  { code: 'ml', label: 'Malayalam', nativeName: 'മലയാളം' },
  { code: 'pa', label: 'Punjabi', nativeName: 'ਪੰਜਾਬੀ' },
  { code: 'or', label: 'Odia', nativeName: 'ଓଡ଼ିଆ' },
  { code: 'as', label: 'Assamese', nativeName: 'অসমীয়া' },
]

export const GUEST_GUIDE_SECTION_TYPES = [
  'hero',
  'stay',
  'actions',
  'wifi',
  'gallery',
  'instructions',
  'facilities',
  'dining',
  'services',
  'safety',
  'contacts',
  'social',
  'local',
  'payment',
  'feedback',
  'review',
  'policies',
  'closing',
  'custom',
]

export const GUEST_GUIDE_ITEM_TYPES = [
  'quick_action',
  'instruction',
  'facility',
  'contact',
  'social',
  'local_convenience',
  'policy',
  'dining',
  'safety',
  'custom',
]

export const GUEST_GUIDE_ACTION_TYPES = [
  'none',
  'call',
  'whatsapp',
  'email',
  'url',
  'maps',
  'section',
  'food',
  'service',
  'payment',
  'checkout',
]

export const GUEST_GUIDE_MEDIA_CATEGORIES = [
  'logo',
  'profile',
  'hero',
  'property',
  'room',
  'bathroom',
  'facility',
  'dining',
  'ac',
  'ac_remote',
  'tv',
  'tv_remote',
  'geyser',
  'bathtub',
  'safe',
  'wifi',
  'payment_qr',
  'emergency',
  'policy',
  'custom',
]

export const GUEST_GUIDE_SCOPE_TYPES = ['hotel', 'room_type', 'room']

const ALLOWED_IMAGE_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp'])
const MAX_MEDIA_BYTES = 8 * 1024 * 1024

function requireHotelId(hotelId) {
  const value = String(hotelId || '').trim()
  if (!value) throw new Error('A hotel must be selected before editing the guest guide.')
  return value
}

function cleanFileName(fileName) {
  const normalized = String(fileName || 'image')
    .normalize('NFKD')
    .replace(/[^a-zA-Z0-9._-]+/g, '-')
    .replace(/-+/g, '-')
    .replace(/^-|-$/g, '')
    .toLowerCase()

  return normalized || 'image'
}

function cleanKey(value, fallback = 'item') {
  const normalized = String(value || '')
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '')
    .slice(0, 90)

  const safe = normalized || fallback
  return /^[a-z]/.test(safe) ? safe : `item_${safe}`
}

function randomSuffix() {
  if (globalThis.crypto?.randomUUID) {
    return globalThis.crypto.randomUUID().replace(/-/g, '').slice(0, 12)
  }

  return `${Date.now()}${Math.random().toString(16).slice(2, 8)}`
}

async function callBuilderRpc(functionName, args, fallbackMessage) {
  const { data, error } = await supabase.rpc(functionName, args)

  if (error) {
    const message = String(error.message || '').trim()
    throw new Error(message || fallbackMessage)
  }

  return data
}

export async function getGuestGuideBuilder(hotelId) {
  return callBuilderRpc(
    'get_guest_guide_builder',
    { p_hotel_id: requireHotelId(hotelId) },
    'Unable to load the Guest Guide Builder.'
  )
}


export async function getHotelGuestContent(hotelId, locale = 'en') {
  return callBuilderRpc(
    'get_hotel_guest_content',
    {
      p_hotel_id: requireHotelId(hotelId),
      p_locale: String(locale || 'en').trim() || 'en',
    },
    'Unable to load hotel guest-guide content.'
  )
}

export async function saveHotelGuestContent(hotelId, locale = 'en', content = {}) {
  return callBuilderRpc(
    'upsert_hotel_guest_content',
    {
      p_hotel_id: requireHotelId(hotelId),
      p_locale: String(locale || 'en').trim() || 'en',
      p_content: content || {},
    },
    'Unable to save hotel guest-guide content.'
  )
}

export async function saveGuestGuideSettings(hotelId, payload) {
  return callBuilderRpc(
    'upsert_guest_guide_settings',
    {
      p_hotel_id: requireHotelId(hotelId),
      p_payload: payload || {},
    },
    'Unable to save guest-guide settings.'
  )
}

export async function saveGuestGuideSection(hotelId, payload) {
  return callBuilderRpc(
    'upsert_guest_guide_section',
    {
      p_hotel_id: requireHotelId(hotelId),
      p_payload: payload || {},
    },
    'Unable to save the guest-guide section.'
  )
}

export async function saveGuestGuideItem(hotelId, payload) {
  return callBuilderRpc(
    'upsert_guest_guide_item',
    {
      p_hotel_id: requireHotelId(hotelId),
      p_payload: payload || {},
    },
    'Unable to save the guest-guide item.'
  )
}

export async function saveGuestGuideMedia(hotelId, payload) {
  return callBuilderRpc(
    'upsert_guest_guide_media',
    {
      p_hotel_id: requireHotelId(hotelId),
      p_payload: payload || {},
    },
    'Unable to save guest-guide media.'
  )
}

export async function saveGuestGuideGreeting(hotelId, payload) {
  return callBuilderRpc(
    'upsert_guest_guide_greeting',
    {
      p_hotel_id: requireHotelId(hotelId),
      p_payload: payload || {},
    },
    'Unable to save the language greeting.'
  )
}

export async function saveGuestGuidePaymentProfile(hotelId, payload) {
  return callBuilderRpc(
    'upsert_guest_guide_payment_profile',
    {
      p_hotel_id: requireHotelId(hotelId),
      p_payload: payload || {},
    },
    'Unable to save the payment profile.'
  )
}

export async function publishGuestGuide(hotelId, publishNote = '') {
  return callBuilderRpc(
    'publish_guest_guide',
    {
      p_hotel_id: requireHotelId(hotelId),
      p_publish_note: String(publishNote || '').trim() || null,
    },
    'Unable to publish the guest guide.'
  )
}

export function buildGuestGuideObjectPath({
  hotelId,
  scopeType = 'hotel',
  roomTypeId = '',
  roomId = '',
  category = 'custom',
  fileName = 'image',
}) {
  const tenantId = requireHotelId(hotelId)
  const scope = GUEST_GUIDE_SCOPE_TYPES.includes(scopeType) ? scopeType : 'hotel'
  const target =
    scope === 'room_type'
      ? String(roomTypeId || '').trim()
      : scope === 'room'
        ? String(roomId || '').trim()
        : 'hotel'

  if (scope !== 'hotel' && !target) {
    throw new Error(`Select a ${scope === 'room' ? 'room' : 'room type'} for this media file.`)
  }

  const safeCategory = cleanKey(category, 'custom')
  const safeFile = cleanFileName(fileName)
  return `${tenantId}/${scope}/${target}/${safeCategory}/${Date.now()}-${randomSuffix()}-${safeFile}`
}

export async function uploadGuestGuideMediaFile({
  hotelId,
  file,
  scopeType = 'hotel',
  roomTypeId = '',
  roomId = '',
  category = 'custom',
}) {
  if (!(file instanceof File)) {
    throw new Error('Choose an image before uploading.')
  }

  if (!ALLOWED_IMAGE_TYPES.has(file.type)) {
    throw new Error('Guest-guide images must be JPG, PNG or WebP.')
  }

  if (file.size <= 0 || file.size > MAX_MEDIA_BYTES) {
    throw new Error('Guest-guide images must be smaller than 8 MB.')
  }

  const objectPath = buildGuestGuideObjectPath({
    hotelId,
    scopeType,
    roomTypeId,
    roomId,
    category,
    fileName: file.name,
  })

  const { error } = await supabase.storage
    .from(GUEST_GUIDE_BUCKET)
    .upload(objectPath, file, {
      cacheControl: '3600',
      contentType: file.type,
      upsert: false,
    })

  if (error) throw error

  return {
    bucketId: GUEST_GUIDE_BUCKET,
    objectPath,
    mimeType: file.type,
    publicUrl: getGuestGuideMediaUrl(objectPath),
  }
}

export async function removeGuestGuideMediaFile(objectPath) {
  const path = String(objectPath || '').trim()
  if (!path) return

  const { error } = await supabase.storage.from(GUEST_GUIDE_BUCKET).remove([path])
  if (error) throw error
}

export function getGuestGuideMediaUrl(objectPath) {
  const path = String(objectPath || '').trim()
  if (!path) return ''

  const { data } = supabase.storage.from(GUEST_GUIDE_BUCKET).getPublicUrl(path)
  return data?.publicUrl || ''
}

export function makeGuestGuideKey(value, fallback = 'item') {
  return cleanKey(value, fallback)
}

export function getLocaleDefinition(localeCode) {
  return GUEST_GUIDE_LOCALES.find((locale) => locale.code === localeCode) || null
}

export function getGuestGuideTranslation(translations, locale, fallbackLocale = 'en') {
  if (!translations || typeof translations !== 'object') return {}
  return translations[locale] || translations[fallbackLocale] || {}
}

export function normalizeGuestGuideBuilderPayload(data) {
  const payload = data && typeof data === 'object' ? data : {}

  return {
    ...payload,
    settings: payload.settings || {},
    sections: Array.isArray(payload.sections) ? payload.sections : [],
    items: Array.isArray(payload.items) ? payload.items : [],
    media: Array.isArray(payload.media) ? payload.media : [],
    greetings: payload.greetings || {},
    payment_profile: payload.payment_profile || {},
    legacy_content: payload.legacy_content || {},
    room_types: Array.isArray(payload.room_types) ? payload.room_types : [],
    rooms: Array.isArray(payload.rooms) ? payload.rooms : [],
    versions: Array.isArray(payload.versions) ? payload.versions : [],
    publish_state: payload.publish_state || {},
  }
}
