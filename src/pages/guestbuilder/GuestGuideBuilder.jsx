import { useCallback, useEffect, useMemo, useState } from 'react'
import { getCurrentHotel } from '../../lib/currentHotel'
import {
  GUEST_GUIDE_LOCALES,
  getGuestGuideBuilder,
  getGuestGuideMediaUrl,
  getGuestGuideTranslation,
  makeGuestGuideKey,
  normalizeGuestGuideBuilderPayload,
  publishGuestGuide,
  removeGuestGuideMediaFile,
  saveGuestGuideGreeting,
  saveGuestGuideItem,
  saveGuestGuideMedia,
  saveGuestGuidePaymentProfile,
  saveGuestGuideSection,
  saveGuestGuideSettings,
  saveHotelGuestContent,
  uploadGuestGuideMediaFile,
} from '../../lib/guestGuideBuilder'
import { getDefaultItemCopy, getDefaultSectionCopy } from '../../lib/guestGuideI18n'
import './GuestGuideBuilder.css'

const STEPS = [
  { id: 'brand', number: '1', label: 'Brand & Photos' },
  { id: 'languages', number: '2', label: 'Languages' },
  { id: 'contacts', number: '3', label: 'Contacts & Services' },
  { id: 'rooms', number: '4', label: 'Rooms & Instructions' },
  { id: 'local', number: '5', label: 'Local & Payment' },
  { id: 'publish', number: '6', label: 'Review & Publish' },
]

const CONTACT_PRESETS = [
  {
    key: 'reception_contact',
    sectionKey: 'important_contacts',
    itemType: 'contact',
    actionType: 'call',
    title: 'Reception / Room Service',
    description: 'Call the hotel front desk for assistance.',
    buttonLabel: 'Call now',
    icon: 'phone',
    inputLabel: 'Reception phone number',
    placeholder: '919876543210',
  },
  {
    key: 'whatsapp_contact',
    sectionKey: 'important_contacts',
    itemType: 'contact',
    actionType: 'whatsapp',
    title: 'WhatsApp Reception',
    description: 'Message the hotel for support and service requests.',
    buttonLabel: 'Open WhatsApp',
    icon: 'whatsapp',
    inputLabel: 'WhatsApp number',
    placeholder: '919876543210',
  },
  {
    key: 'hotel_email',
    sectionKey: 'important_contacts',
    itemType: 'contact',
    actionType: 'email',
    title: 'Email Hotel',
    description: 'Send an email to the hotel team.',
    buttonLabel: 'Send email',
    icon: 'email',
    inputLabel: 'Hotel email address',
    placeholder: 'reception@hotel.com',
  },
  {
    key: 'instagram',
    sectionKey: 'stay_connected',
    itemType: 'social',
    actionType: 'url',
    title: 'Instagram',
    description: 'Follow the hotel on Instagram.',
    buttonLabel: 'Follow',
    icon: 'instagram',
    inputLabel: 'Instagram URL',
    placeholder: 'https://www.instagram.com/hotelname',
  },
  {
    key: 'hotel_website',
    sectionKey: 'stay_connected',
    itemType: 'social',
    actionType: 'url',
    title: 'Hotel Website',
    description: 'Visit the official hotel website.',
    buttonLabel: 'Open website',
    icon: 'globe',
    inputLabel: 'Website URL',
    placeholder: 'https://hotelwebsite.com',
  },
  {
    key: 'hotel_location',
    sectionKey: 'stay_connected',
    itemType: 'social',
    actionType: 'maps',
    title: 'Hotel Location',
    description: 'Open the hotel location in Google Maps.',
    buttonLabel: 'Open Maps',
    icon: 'map',
    inputLabel: 'Google Maps URL',
    placeholder: 'https://maps.google.com/...',
  },
]

const LOCAL_PRESETS = [
  {
    key: 'nearby_restaurants',
    title: 'Nearby Restaurants',
    description: 'Help guests discover nearby dining options.',
    icon: 'restaurant',
  },
  {
    key: 'medical_support',
    title: 'Nearby Medical Support',
    description: 'Share a nearby hospital, clinic or pharmacy link.',
    icon: 'medical',
  },
  {
    key: 'nearby_atms',
    title: 'Nearby ATMs',
    description: 'Help guests find nearby ATM services.',
    icon: 'atm',
  },
  {
    key: 'shopping_essentials',
    title: 'Shopping & Essentials',
    description: 'Share nearby stores and shopping options.',
    icon: 'shopping',
  },
  {
    key: 'tourist_places',
    title: 'Tourist Places',
    description: 'Share nearby attractions and experiences.',
    icon: 'map',
  },
  {
    key: 'transport_assistance',
    title: 'Transport Assistance',
    description: 'Help guests contact the hotel for transport.',
    icon: 'taxi',
  },
]

const ROOM_GUIDE_TOPICS = [
  {
    key: 'air_conditioner',
    label: 'Air Conditioner',
    icon: 'snowflake',
    description: 'Explain how to use the AC and remote.',
  },
  {
    key: 'television_remote',
    label: 'Television & Remote',
    icon: 'tv',
    description: 'Explain the TV, set-top box, OTT or casting controls.',
  },
  {
    key: 'hot_water_geyser',
    label: 'Hot Water & Geyser',
    icon: 'shower',
    description: 'Explain the hot-water or geyser process.',
  },
  {
    key: 'bathtub_controls',
    label: 'Bathtub',
    icon: 'shower',
    description: 'Explain bathtub controls and safety.',
  },
  {
    key: 'safe_locker',
    label: 'Safe Locker',
    icon: 'safe',
    description: 'Explain how to lock, open and reset the safe.',
  },
  {
    key: 'custom_room_guide',
    label: 'Other Room Instruction',
    icon: 'sparkles',
    description: 'Add another room-specific instruction.',
  },
]

const MEDIA_PRESETS = [
  { category: 'logo', label: 'Hotel Logo', scope: 'hotel' },
  { category: 'hero', label: 'Hero / Cover Photo', scope: 'hotel' },
  { category: 'property', label: 'Property Photo', scope: 'hotel' },
  { category: 'room', label: 'Room Photo', scope: 'room_type' },
  { category: 'ac_remote', label: 'AC Remote Photo', scope: 'room_type' },
  { category: 'tv_remote', label: 'TV Remote Photo', scope: 'room_type' },
  { category: 'geyser', label: 'Geyser Photo', scope: 'room_type' },
  { category: 'bathtub', label: 'Bathtub Photo', scope: 'room_type' },
  { category: 'safe', label: 'Safe Locker Photo', scope: 'room_type' },
  { category: 'payment_qr', label: 'Payment QR', scope: 'hotel' },
]

const STARTER_ITEMS = [
  {
    sectionKey: 'quick_access',
    itemKey: 'housekeeping',
    itemType: 'quick_action',
    icon: 'housekeeping',
    actionType: 'service',
    actionValue: 'Housekeeping',
    title: 'Housekeeping',
    description: 'Request room cleaning support.',
    buttonLabel: 'Request now',
  },
  {
    sectionKey: 'quick_access',
    itemKey: 'drinking_water',
    itemType: 'quick_action',
    icon: 'water',
    actionType: 'service',
    actionValue: 'Water',
    title: 'Drinking Water',
    description: 'Request drinking water for your room.',
    buttonLabel: 'Request now',
  },
  {
    sectionKey: 'quick_access',
    itemKey: 'fresh_towels',
    itemType: 'quick_action',
    icon: 'towels',
    actionType: 'service',
    actionValue: 'Towel',
    title: 'Fresh Towels',
    description: 'Request additional fresh towels.',
    buttonLabel: 'Request now',
  },
  {
    sectionKey: 'quick_access',
    itemKey: 'food_menu',
    itemType: 'quick_action',
    icon: 'food',
    actionType: 'food',
    actionValue: '',
    title: 'Food Menu',
    description: 'Browse the hotel menu and order food.',
    buttonLabel: 'View menu',
  },
  {
    sectionKey: 'quick_access',
    itemKey: 'checkout_request',
    itemType: 'quick_action',
    icon: 'checkout',
    actionType: 'checkout',
    actionValue: 'Checkout Request',
    title: 'Checkout',
    description: 'Notify reception that you are preparing to check out.',
    buttonLabel: 'Notify reception',
  },
]

function parseInstructionLines(value) {
  return String(value || '')
    .split('\n')
    .map((line) => line.trim())
    .filter(Boolean)
}

function sectionByKey(builder, sectionKey) {
  return builder.sections.find((section) => section.section_key === sectionKey)
}

function translationFor(item, locale, fallbackLocale = 'en') {
  return getGuestGuideTranslation(item?.translations, locale, fallbackLocale)
}

function createInitialRoomGuide() {
  return {
    scope_type: 'hotel',
    room_type_id: '',
    room_id: '',
    topic_key: 'air_conditioner',
    title: 'Air Conditioner',
    description: 'Explain how to use the AC and remote.',
    instructions_text: '',
    is_enabled: true,
  }
}

function createInitialMedia() {
  return {
    category: 'hero',
    scope_type: 'hotel',
    room_type_id: '',
    room_id: '',
    title: '',
    caption: '',
    alt_text: '',
  }
}

function Field({ label, hint, children, wide = false }) {
  return (
    <label className={`simple-field ${wide ? 'wide' : ''}`}>
      <span>{label}</span>
      {children}
      {hint && <small>{hint}</small>}
    </label>
  )
}

function Toggle({ checked, onChange, label, description }) {
  return (
    <label className="simple-toggle-row">
      <input type="checkbox" checked={checked} onChange={onChange} />
      <span>
        <strong>{label}</strong>
        {description && <small>{description}</small>}
      </span>
    </label>
  )
}

export default function GuestGuideBuilder() {
  const [currentHotel, setCurrentHotel] = useState(null)
  const [builder, setBuilder] = useState(normalizeGuestGuideBuilderPayload(null))
  const [loading, setLoading] = useState(true)
  const [busy, setBusy] = useState(false)
  const [activeStep, setActiveStep] = useState('brand')
  const [editingLocale, setEditingLocale] = useState('en')
  const [notice, setNotice] = useState('')
  const [errorMessage, setErrorMessage] = useState('')
  const [settingsDraft, setSettingsDraft] = useState(null)
  const [greetingDrafts, setGreetingDrafts] = useState({})
  const [contactValues, setContactValues] = useState({})
  const [localValues, setLocalValues] = useState({})
  const [roomGuide, setRoomGuide] = useState(createInitialRoomGuide())
  const [mediaDraft, setMediaDraft] = useState(createInitialMedia())
  const [mediaFile, setMediaFile] = useState(null)
  const [paymentDraft, setPaymentDraft] = useState({})
  const [sectionDrafts, setSectionDrafts] = useState({})
  const [publishNote, setPublishNote] = useState('')
  const [contentDraft, setContentDraft] = useState({})
  const [lastSavedArea, setLastSavedArea] = useState('')

  const showError = useCallback((error, fallback) => {
    console.error(fallback, error)
    setErrorMessage(error?.message || fallback)
    setNotice('')
  }, [])

  const showNotice = useCallback((message) => {
    setNotice(message)
    setLastSavedArea(message)
    setErrorMessage('')
    window.setTimeout(() => setNotice(''), 4200)
  }, [])

  const syncDrafts = useCallback((nextBuilder) => {
    const settings = nextBuilder.settings || {}
    setSettingsDraft({
      template_key: 'stayqr_luxury',
      default_locale: settings.default_locale || 'en',
      enabled_locales: Array.isArray(settings.enabled_locales)
        ? settings.enabled_locales
        : ['en'],
      theme: {
        mode: 'dark',
        primary_color: '#0A0A0A',
        accent_color: settings.theme?.accent_color || '#C9A24D',
        surface_color: '#161616',
        text_color: '#F7F5F2',
        heading_font: 'Playfair Display',
        body_font: 'Inter',
        card_radius: 14,
        glass_effect: false,
      },
      branding: {
        ...(settings.branding || {}),
        show_stayqr_branding: settings.branding?.show_stayqr_branding !== false,
        stayqr_label: settings.branding?.stayqr_label || 'Powered by StayQR',
        stayqr_tagline: settings.branding?.stayqr_tagline || 'Smart Digital Hospitality · Scan. Stay. Simplified.',
        offer: {
          enabled: settings.branding?.offer?.enabled !== false,
          badge: settings.branding?.offer?.badge || 'Limited Offer',
          title: settings.branding?.offer?.title || 'Make Your Stay More Rewarding',
          description: settings.branding?.offer?.description || 'Ask reception about today’s guest benefit.',
          button_label: settings.branding?.offer?.button_label || 'View Offer',
          action_type: settings.branding?.offer?.action_type || 'section',
          action_value: settings.branding?.offer?.action_value || 'google_review',
          image_media_id: settings.branding?.offer?.image_media_id || '',
          translations: settings.branding?.offer?.translations || {},
        },
      },
      navigation: {
        ...(settings.navigation || {}),
        sticky_quick_actions: true,
        show_section_numbers: true,
        compact_mobile_hero: true,
        ui_copy: settings.navigation?.ui_copy || {},
      },
    })

    setGreetingDrafts(nextBuilder.greetings || {})
    setContentDraft({
      welcome_kicker: 'Digital Guest Guide',
      welcome_title: currentHotel?.hotel_name || currentHotel?.name || '',
      welcome_message: 'Everything you need during your stay, beautifully simplified.',
      concierge_title: 'Quick Access Concierge',
      concierge_subtitle: 'Tap any card for instant access.',
      amenities_section_title: 'Hotel Facilities',
      private_feedback_title: 'How Was Your Stay?',
      private_feedback_prompt: 'Share private feedback directly with the hotel.',
      review_section_title: 'Review & Rewards',
      review_prompt: 'Your honest review helps future guests.',
      footer_message: 'We hope your stay feels comfortable, safe and memorable.',
      ...(nextBuilder.legacy_content?.[editingLocale] || nextBuilder.legacy_content?.en || {}),
    })

    const nextContacts = {}
    CONTACT_PRESETS.forEach((preset) => {
      const item = nextBuilder.items.find((entry) => entry.item_key === preset.key)
      const translation = translationFor(item, editingLocale)
      nextContacts[preset.key] = {
        value: item?.action_value || '',
        title: translation.title || getDefaultItemCopy(preset.key, editingLocale).title || preset.title,
        description: translation.description || getDefaultItemCopy(preset.key, editingLocale).description || preset.description,
        is_enabled: item?.is_enabled !== false,
      }
    })
    setContactValues(nextContacts)

    const nextLocal = {}
    LOCAL_PRESETS.forEach((preset) => {
      const item = nextBuilder.items.find((entry) => entry.item_key === preset.key)
      const translation = translationFor(item, editingLocale)
      nextLocal[preset.key] = {
        value: item?.action_value || '',
        title: translation.title || getDefaultItemCopy(preset.key, editingLocale).title || preset.title,
        description: translation.description || getDefaultItemCopy(preset.key, editingLocale).description || preset.description,
        is_enabled: item?.is_enabled !== false,
      }
    })
    setLocalValues(nextLocal)

    setPaymentDraft({
      is_enabled: nextBuilder.payment_profile?.is_enabled === true,
      payee_name: nextBuilder.payment_profile?.payee_name || '',
      upi_id: nextBuilder.payment_profile?.upi_id || '',
      qr_media_id: nextBuilder.payment_profile?.qr_media_id || '',
      instructions: nextBuilder.payment_profile?.instructions || '',
      show_outstanding_balance:
        nextBuilder.payment_profile?.show_outstanding_balance !== false,
      require_reception_confirmation:
        nextBuilder.payment_profile?.require_reception_confirmation !== false,
    })

    const nextSections = {}
    nextBuilder.sections.forEach((section) => {
      const translation = translationFor(section, editingLocale)
      const defaults = getDefaultSectionCopy(section.section_key, editingLocale)
      nextSections[section.section_key] = {
        id: section.id,
        section_key: section.section_key,
        section_type: section.section_type,
        sort_order: Number(section.sort_order || 0),
        is_enabled: section.is_enabled !== false,
        title: translation.title || defaults.title || '',
        subtitle: translation.subtitle || defaults.subtitle || '',
        label: translation.label || defaults.label || '',
      }
    })
    setSectionDrafts(nextSections)
  }, [currentHotel, editingLocale])

  const loadBuilder = useCallback(async () => {
    setLoading(true)
    try {
      const hotel = await getCurrentHotel()
      if (!hotel?.id) throw new Error('Select a hotel before opening Guest Guide Setup.')
      setCurrentHotel(hotel)
      const data = normalizeGuestGuideBuilderPayload(
        await getGuestGuideBuilder(hotel.id)
      )
      setBuilder(data)
    } catch (error) {
      showError(error, 'Unable to load the Guest Guide Setup.')
    } finally {
      setLoading(false)
    }
  }, [showError])

  useEffect(() => {
    void loadBuilder()
  }, [loadBuilder])

  useEffect(() => {
    if (loading) return
    syncDrafts(builder)
  }, [builder, editingLocale, loading, syncDrafts])

  const completedContactCount = useMemo(
    () => CONTACT_PRESETS.filter((preset) => contactValues[preset.key]?.value).length,
    [contactValues]
  )

  const completedLocalCount = useMemo(
    () => LOCAL_PRESETS.filter((preset) => localValues[preset.key]?.value).length,
    [localValues]
  )

  const activeMedia = useMemo(
    () => builder.media.filter((media) => media.is_active !== false),
    [builder.media]
  )

  async function refreshBuilder(message = '') {
    const data = normalizeGuestGuideBuilderPayload(
      await getGuestGuideBuilder(currentHotel.id)
    )
    setBuilder(data)
    syncDrafts(data)
    if (message) showNotice(message)
  }

  async function runBusy(action, successMessage) {
    if (busy) return
    setBusy(true)
    try {
      await action()
      await refreshBuilder(successMessage)
    } catch (error) {
      showError(error, successMessage || 'Unable to save changes.')
    } finally {
      setBusy(false)
    }
  }

  async function saveLanguageContent() {
    await runBusy(async () => {
      await saveHotelGuestContent(currentHotel.id, editingLocale, contentDraft)
      await saveGuestGuideSettings(currentHotel.id, settingsDraft)
      const sectionEntries = Object.values(sectionDrafts)
      for (const draft of sectionEntries) {
        await saveGuestGuideSection(currentHotel.id, {
          section_key: draft.section_key,
          section_type: draft.section_type,
          sort_order: draft.sort_order,
          is_enabled: draft.is_enabled,
          settings: {},
          translations: {
            [editingLocale]: {
              label: draft.label,
              title: draft.title,
              subtitle: draft.subtitle,
            },
          },
        })
      }
    }, `${editingLocale.toUpperCase()} guide language saved to draft.`)
  }

  function updateOffer(field, value) {
    setSettingsDraft((current) => ({
      ...current,
      branding: {
        ...current.branding,
        offer: {
          ...current.branding.offer,
          [field]: value,
        },
      },
    }))
  }

  async function saveBrandSettings() {
    await runBusy(
      () => saveGuestGuideSettings(currentHotel.id, settingsDraft),
      'Brand and language settings saved to draft.'
    )
  }

  async function saveGreeting(localeCode) {
    const draft = greetingDrafts[localeCode]
    if (!draft) return

    await runBusy(
      () =>
        saveGuestGuideGreeting(currentHotel.id, {
          locale: localeCode,
          language_name: draft.language_name,
          native_name: draft.native_name,
          neutral_greeting: draft.neutral,
          morning_greeting: draft.morning,
          afternoon_greeting: draft.afternoon,
          evening_greeting: draft.evening,
          night_greeting: draft.night,
          is_enabled: settingsDraft.enabled_locales.includes(localeCode),
          sort_order: draft.sort_order || 0,
        }),
      `${draft.native_name || draft.language_name} greetings saved.`
    )
  }

  function buildItemPayload({
    preset,
    sectionKey,
    itemKey,
    itemType,
    icon,
    actionType,
    actionValue,
    title,
    description,
    buttonLabel,
    scopeType = 'hotel',
    roomTypeId = '',
    roomId = '',
    instructions = [],
    isEnabled = true,
  }) {
    const section = sectionByKey(builder, sectionKey)
    if (!section?.id) throw new Error(`The ${sectionKey} guide section is missing.`)

    const existing = builder.items.find(
      (item) =>
        item.item_key === itemKey &&
        item.scope_type === scopeType &&
        String(item.room_type_id || '') === String(roomTypeId || '') &&
        String(item.room_id || '') === String(roomId || '')
    )

    return {
      section_id: section.id,
      scope_type: scopeType,
      room_type_id: scopeType === 'room_type' ? roomTypeId : null,
      room_id: scopeType === 'room' ? roomId : null,
      item_key: itemKey,
      item_type: itemType,
      icon,
      action_type: actionType,
      action_value: actionValue || null,
      sort_order: Number(existing?.sort_order || preset?.sort_order || 0),
      is_enabled: isEnabled,
      metadata: existing?.metadata || {},
      translations: {
        [editingLocale]: {
          title,
          description,
          instructions,
          button_label: buttonLabel || null,
        },
      },
    }
  }

  async function saveContact(preset) {
    const draft = contactValues[preset.key]
    await runBusy(
      () =>
        saveGuestGuideItem(
          currentHotel.id,
          buildItemPayload({
            preset,
            sectionKey: preset.sectionKey,
            itemKey: preset.key,
            itemType: preset.itemType,
            icon: preset.icon,
            actionType: preset.actionType,
            actionValue: draft.value,
            title: draft.title,
            description: draft.description,
            buttonLabel: preset.buttonLabel,
            isEnabled: draft.is_enabled,
          })
        ),
      `${preset.title} saved.`
    )
  }

  async function saveLocal(preset) {
    const draft = localValues[preset.key]
    const actionType = preset.key === 'transport_assistance' && !/^https?:\/\//i.test(draft.value)
      ? 'call'
      : 'maps'

    await runBusy(
      () =>
        saveGuestGuideItem(
          currentHotel.id,
          buildItemPayload({
            preset,
            sectionKey: 'local_convenience',
            itemKey: preset.key,
            itemType: 'local_convenience',
            icon: preset.icon,
            actionType,
            actionValue: draft.value,
            title: draft.title,
            description: draft.description,
            buttonLabel: actionType === 'call' ? 'Call reception' : 'Open Maps',
            isEnabled: draft.is_enabled,
          })
        ),
      `${preset.title} saved.`
    )
  }

  async function prepareDefaultContent() {
    const missing = STARTER_ITEMS.filter(
      (starter) => !builder.items.some((item) => item.item_key === starter.itemKey)
    )

    if (missing.length === 0) {
      showNotice('Essential guest actions are already prepared.')
      return
    }

    await runBusy(async () => {
      for (const starter of missing) {
        await saveGuestGuideItem(
          currentHotel.id,
          buildItemPayload({
            preset: starter,
            sectionKey: starter.sectionKey,
            itemKey: starter.itemKey,
            itemType: starter.itemType,
            icon: starter.icon,
            actionType: starter.actionType,
            actionValue: starter.actionValue,
            title: starter.title,
            description: starter.description,
            buttonLabel: starter.buttonLabel,
          })
        )
      }
    }, 'Essential guest actions prepared.')
  }

  function selectExistingRoomGuide() {
    const target = builder.items.find(
      (item) =>
        item.item_key === roomGuide.topic_key &&
        item.scope_type === roomGuide.scope_type &&
        String(item.room_type_id || '') === String(roomGuide.room_type_id || '') &&
        String(item.room_id || '') === String(roomGuide.room_id || '')
    )

    const topic = ROOM_GUIDE_TOPICS.find((entry) => entry.key === roomGuide.topic_key)
    const translation = translationFor(target, editingLocale)

    setRoomGuide((current) => ({
      ...current,
      title: translation.title || topic?.label || '',
      description: translation.description || topic?.description || '',
      instructions_text: Array.isArray(translation.instructions)
        ? translation.instructions.join('\n')
        : '',
      is_enabled: target?.is_enabled !== false,
    }))
  }

  useEffect(() => {
    if (!loading) selectExistingRoomGuide()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [
    roomGuide.topic_key,
    roomGuide.scope_type,
    roomGuide.room_type_id,
    roomGuide.room_id,
    editingLocale,
    loading,
  ])

  async function saveRoomGuide() {
    const topic = ROOM_GUIDE_TOPICS.find((entry) => entry.key === roomGuide.topic_key)
    if (roomGuide.scope_type === 'room_type' && !roomGuide.room_type_id) {
      showError(new Error('Select a room type.'), 'Select a room type.')
      return
    }
    if (roomGuide.scope_type === 'room' && !roomGuide.room_id) {
      showError(new Error('Select a room.'), 'Select a room.')
      return
    }

    await runBusy(
      () =>
        saveGuestGuideItem(
          currentHotel.id,
          buildItemPayload({
            sectionKey: 'room_guide',
            itemKey: roomGuide.topic_key,
            itemType: 'instruction',
            icon: topic?.icon || 'sparkles',
            actionType: 'none',
            actionValue: '',
            title: roomGuide.title,
            description: roomGuide.description,
            instructions: parseInstructionLines(roomGuide.instructions_text),
            scopeType: roomGuide.scope_type,
            roomTypeId: roomGuide.room_type_id,
            roomId: roomGuide.room_id,
            isEnabled: roomGuide.is_enabled,
          })
        ),
      `${roomGuide.title || topic?.label || 'Room instruction'} saved.`
    )
  }

  async function uploadMedia() {
    if (!mediaFile) {
      showError(new Error('Choose an image first.'), 'Choose an image first.')
      return
    }
    if (mediaDraft.scope_type === 'room_type' && !mediaDraft.room_type_id) {
      showError(new Error('Select a room type.'), 'Select a room type.')
      return
    }
    if (mediaDraft.scope_type === 'room' && !mediaDraft.room_id) {
      showError(new Error('Select a room.'), 'Select a room.')
      return
    }

    await runBusy(async () => {
      const upload = await uploadGuestGuideMediaFile({
        hotelId: currentHotel.id,
        file: mediaFile,
        scopeType: mediaDraft.scope_type,
        roomTypeId: mediaDraft.room_type_id,
        roomId: mediaDraft.room_id,
        category: mediaDraft.category,
      })

      const sectionKey = mediaDraft.category === 'payment_qr'
        ? 'payment'
        : ['room', 'bathroom', 'property', 'profile', 'hero', 'logo'].includes(mediaDraft.category)
          ? 'room_gallery'
          : 'room_guide'
      const section = sectionByKey(builder, sectionKey)
      const target = mediaDraft.scope_type === 'room_type'
        ? mediaDraft.room_type_id
        : mediaDraft.scope_type === 'room'
          ? mediaDraft.room_id
          : 'hotel'
      const mediaKey = makeGuestGuideKey(
        `${mediaDraft.category}_${target}_${Date.now()}`,
        mediaDraft.category
      )

      await saveGuestGuideMedia(currentHotel.id, {
        section_id: section?.id || null,
        item_id: (() => {
          const categoryToKey = { ac: 'air_conditioner', ac_remote: 'air_conditioner', tv: 'television_remote', tv_remote: 'television_remote', geyser: 'hot_water_geyser', bathtub: 'bathtub_controls', safe: 'safe_locker' }
          const itemKey = categoryToKey[mediaDraft.category]
          if (!itemKey) return null
          const matched = builder.items.find((item) => item.item_key === itemKey && item.scope_type === mediaDraft.scope_type && String(item.room_type_id || '') === String(mediaDraft.room_type_id || '') && String(item.room_id || '') === String(mediaDraft.room_id || ''))
          return matched?.id || null
        })(),
        scope_type: mediaDraft.scope_type,
        room_type_id: mediaDraft.scope_type === 'room_type' ? mediaDraft.room_type_id : null,
        room_id: mediaDraft.scope_type === 'room' ? mediaDraft.room_id : null,
        media_key: mediaKey,
        category: mediaDraft.category,
        object_path: upload.objectPath,
        mime_type: upload.mimeType,
        title: mediaDraft.title || MEDIA_PRESETS.find((entry) => entry.category === mediaDraft.category)?.label || '',
        caption: mediaDraft.caption || '',
        alt_text: mediaDraft.alt_text || mediaDraft.title || 'Hotel guest guide image',
        locale: null,
        sort_order: activeMedia.length * 10,
        is_active: true,
        metadata: {},
      })
    }, 'Photo uploaded to the draft guide.')

    setMediaFile(null)
    setMediaDraft(createInitialMedia())
  }

  async function deleteMedia(media) {
    const confirmed = window.confirm(`Remove ${media.title || media.media_key} from the guest guide?`)
    if (!confirmed) return

    await runBusy(async () => {
      await removeGuestGuideMediaFile(media.object_path)
      await saveGuestGuideMedia(currentHotel.id, {
        section_id: media.section_id,
        item_id: media.item_id,
        scope_type: media.scope_type,
        room_type_id: media.room_type_id,
        room_id: media.room_id,
        media_key: media.media_key,
        category: media.category,
        object_path: media.object_path,
        mime_type: media.mime_type,
        title: media.title,
        caption: media.caption,
        alt_text: media.alt_text,
        locale: media.locale,
        sort_order: media.sort_order,
        is_active: false,
        metadata: media.metadata || {},
      })
    }, 'Photo removed from the draft guide.')
  }

  async function savePayment() {
    await runBusy(
      () => saveGuestGuidePaymentProfile(currentHotel.id, paymentDraft),
      'Payment information saved to draft.'
    )
  }

  async function saveSection(sectionKey) {
    const draft = sectionDrafts[sectionKey]
    if (!draft) return

    await runBusy(
      () =>
        saveGuestGuideSection(currentHotel.id, {
          section_key: draft.section_key,
          section_type: draft.section_type,
          sort_order: draft.sort_order,
          is_enabled: draft.is_enabled,
          settings: {},
          translations: {
            [editingLocale]: {
              label: draft.label,
              title: draft.title,
              subtitle: draft.subtitle,
            },
          },
        }),
      `${draft.title || sectionKey} section saved.`
    )
  }

  async function publishGuide() {
    await runBusy(
      () => publishGuestGuide(currentHotel.id, publishNote || 'Published from Simple Guest Guide Setup'),
      'Guest guide published successfully.'
    )
    setPublishNote('')
  }

  if (loading) {
    return <div className="simple-builder-loading">Loading Guest Guide Setup…</div>
  }

  if (!currentHotel || !settingsDraft) {
    return (
      <section className="simple-builder-page">
        <div className="simple-error">{errorMessage || 'Select a hotel to continue.'}</div>
      </section>
    )
  }

  const publishedVersion = builder.publish_state?.published_version || 0
  const publishStatus = builder.publish_state?.publish_status || 'draft'
  const selectedGreeting = greetingDrafts[editingLocale]
  const essentialPrepared = STARTER_ITEMS.every((starter) =>
    builder.items.some((item) => item.item_key === starter.itemKey)
  )

  return (
    <section className="simple-builder-page">
      <header className="simple-builder-hero">
        <div>
          <p>DAY 14 · GUEST EXPERIENCE</p>
          <h1>Guest Guide Setup</h1>
          <span>
            A simple six-step setup for {currentHotel.hotel_name || currentHotel.name}.
            Guests only see the published version.
          </span>
        </div>
        <div className="simple-publish-status">
          <small>{publishStatus}</small>
          <strong>Version {publishedVersion}</strong>
          <span>Draft revision {builder.publish_state?.draft_revision || 1}</span>
        </div>
      </header>

      {lastSavedArea && !errorMessage && <div className="simple-inline-saved">✓ {lastSavedArea}</div>}

      {(notice || errorMessage) && (
        <div className={`simple-message ${errorMessage ? 'error' : 'success'}`}>
          <span>{errorMessage || notice}</span>
          <button type="button" onClick={() => { setNotice(''); setErrorMessage('') }}>×</button>
        </div>
      )}

      <nav className="simple-steps" aria-label="Guest guide setup steps">
        {STEPS.map((step) => (
          <button
            key={step.id}
            type="button"
            className={activeStep === step.id ? 'active' : ''}
            onClick={() => setActiveStep(step.id)}
          >
            <span>{step.number}</span>
            <strong>{step.label}</strong>
          </button>
        ))}
      </nav>

      <div className="simple-builder-toolbar">
        <label>
          Editing language
          <select value={editingLocale} onChange={(event) => setEditingLocale(event.target.value)}>
            {settingsDraft.enabled_locales.map((localeCode) => {
              const language = GUEST_GUIDE_LOCALES.find((entry) => entry.code === localeCode)
              return (
                <option key={localeCode} value={localeCode}>
                  {language?.nativeName || localeCode}
                </option>
              )
            })}
          </select>
        </label>
        <button type="button" onClick={() => void loadBuilder()} disabled={busy}>Refresh</button>
      </div>

      {activeStep === 'brand' && (
        <div className="simple-step-content">
          <div className="simple-step-heading">
            <p>01 — Brand & Photos</p>
            <h2>Make the guide feel like the hotel</h2>
            <span>StayQR keeps the layout readable and high-contrast. Hotels choose the accent colour and photos.</span>
          </div>

          <div className="simple-two-column">
            <article className="simple-panel">
              <div className="simple-official-brand"><img src="/assets/stayqr-official-logo.png" alt="StayQR — Simplifying check-in" /><div><h3>Official StayQR branding</h3><p>This approved logo is used in the guest guide hero, signature and footer.</p></div></div>
              <div className="simple-form-grid">
                <Field label="Gold / accent colour">
                  <input
                    type="color"
                    value={settingsDraft.theme.accent_color}
                    onChange={(event) =>
                      setSettingsDraft((current) => ({
                        ...current,
                        theme: { ...current.theme, accent_color: event.target.value },
                      }))
                    }
                  />
                </Field>
                <Field label="Template">
                  <input value="StayQR Apex Signature REV5" disabled />
                </Field>
                <Field label="StayQR footer label" wide>
                  <input
                    value={settingsDraft.branding.stayqr_label}
                    onChange={(event) =>
                      setSettingsDraft((current) => ({
                        ...current,
                        branding: { ...current.branding, stayqr_label: event.target.value },
                      }))
                    }
                  />
                </Field>
              </div>
              <Toggle
                checked={settingsDraft.branding.show_stayqr_branding}
                onChange={(event) =>
                  setSettingsDraft((current) => ({
                    ...current,
                    branding: { ...current.branding, show_stayqr_branding: event.target.checked },
                  }))
                }
                label="Show StayQR branding"
                description="Keeps the secure platform attribution in the footer."
              />
              <button className="simple-primary" type="button" onClick={() => void saveBrandSettings()} disabled={busy}>
                Save brand settings
              </button>
            </article>

            <article className="simple-panel simple-offer-editor">
              <h3>Featured offer below the hero</h3>
              <p>This fills the space between the hero buttons and stay overview, like the Apex reference.</p>
              <Toggle
                checked={settingsDraft.branding.offer.enabled !== false}
                onChange={(event) => updateOffer('enabled', event.target.checked)}
                label="Show featured offer"
              />
              <div className="simple-form-grid">
                <Field label="Offer badge"><input value={settingsDraft.branding.offer.badge || ''} onChange={(event) => updateOffer('badge', event.target.value)} /></Field>
                <Field label="Offer title"><input value={settingsDraft.branding.offer.title || ''} onChange={(event) => updateOffer('title', event.target.value)} /></Field>
                <Field label="Offer description" wide><textarea value={settingsDraft.branding.offer.description || ''} onChange={(event) => updateOffer('description', event.target.value)} /></Field>
                <Field label="Button label"><input value={settingsDraft.branding.offer.button_label || ''} onChange={(event) => updateOffer('button_label', event.target.value)} /></Field>
                <Field label="Button action">
                  <select value={settingsDraft.branding.offer.action_type || 'section'} onChange={(event) => updateOffer('action_type', event.target.value)}>
                    <option value="section">Open guide section</option><option value="url">Open website/link</option><option value="whatsapp">Open WhatsApp</option><option value="call">Call</option><option value="payment">Open payment</option>
                  </select>
                </Field>
                <Field label="Section key, URL or number" wide><input value={settingsDraft.branding.offer.action_value || ''} onChange={(event) => updateOffer('action_value', event.target.value)} placeholder="google_review" /></Field>
                <Field label="Optional offer image">
                  <select value={settingsDraft.branding.offer.image_media_id || ''} onChange={(event) => updateOffer('image_media_id', event.target.value)}>
                    <option value="">No image</option>
                    {activeMedia.map((media) => <option key={media.id} value={media.id}>{media.title || media.media_key}</option>)}
                  </select>
                </Field>
              </div>
              <button className="simple-primary" type="button" onClick={() => void saveBrandSettings()} disabled={busy}>Save offer to draft</button>
            </article>

            <article className="simple-panel simple-live-preview">
              <small>Live style preview</small>
              <div style={{ '--preview-accent': settingsDraft.theme.accent_color }}>
                <p>DIGITAL GUEST GUIDE</p>
                <h3>{currentHotel.hotel_name || currentHotel.name}</h3>
                <span>Everything guests need, beautifully simplified.</span>
                <button type="button">Call Reception</button>
              </div>
            </article>
          </div>

          <article className="simple-panel">
            <div className="simple-panel-heading">
              <div>
                <h3>Hotel and room photos</h3>
                <p>Upload logo, cover, property, room and device photos. JPG, PNG or WebP up to 8 MB.</p>
              </div>
            </div>

            <div className="simple-form-grid media-form-grid">
              <Field label="Photo type">
                <select
                  value={mediaDraft.category}
                  onChange={(event) => {
                    const preset = MEDIA_PRESETS.find((entry) => entry.category === event.target.value)
                    setMediaDraft((current) => ({
                      ...current,
                      category: event.target.value,
                      scope_type: preset?.scope || 'hotel',
                      room_type_id: '',
                      room_id: '',
                    }))
                  }}
                >
                  {MEDIA_PRESETS.map((preset) => (
                    <option key={preset.category} value={preset.category}>{preset.label}</option>
                  ))}
                </select>
              </Field>
              <Field label="Used for">
                <select
                  value={mediaDraft.scope_type}
                  onChange={(event) => setMediaDraft((current) => ({
                    ...current,
                    scope_type: event.target.value,
                    room_type_id: '',
                    room_id: '',
                  }))}
                >
                  <option value="hotel">Entire hotel</option>
                  <option value="room_type">A room type</option>
                  <option value="room">One specific room</option>
                </select>
              </Field>
              {mediaDraft.scope_type === 'room_type' && (
                <Field label="Room type">
                  <select value={mediaDraft.room_type_id} onChange={(event) => setMediaDraft((current) => ({ ...current, room_type_id: event.target.value }))}>
                    <option value="">Select room type</option>
                    {builder.room_types.filter((entry) => entry.is_active !== false).map((entry) => (
                      <option key={entry.id} value={entry.id}>{entry.name}</option>
                    ))}
                  </select>
                </Field>
              )}
              {mediaDraft.scope_type === 'room' && (
                <Field label="Room">
                  <select value={mediaDraft.room_id} onChange={(event) => setMediaDraft((current) => ({ ...current, room_id: event.target.value }))}>
                    <option value="">Select room</option>
                    {builder.rooms.filter((entry) => entry.is_active !== false).map((entry) => (
                      <option key={entry.id} value={entry.id}>Room {entry.room_number}</option>
                    ))}
                  </select>
                </Field>
              )}
              <Field label="Title">
                <input value={mediaDraft.title} onChange={(event) => setMediaDraft((current) => ({ ...current, title: event.target.value }))} placeholder="Deluxe Room" />
              </Field>
              <Field label="Choose image" wide>
                <input type="file" accept="image/jpeg,image/png,image/webp" onChange={(event) => setMediaFile(event.target.files?.[0] || null)} />
              </Field>
            </div>
            <button className="simple-primary" type="button" onClick={() => void uploadMedia()} disabled={busy || !mediaFile}>
              Upload photo to draft
            </button>

            {activeMedia.length > 0 && (
              <div className="simple-media-grid">
                {activeMedia.map((media) => (
                  <article key={media.id}>
                    <img src={getGuestGuideMediaUrl(media.object_path)} alt={media.alt_text || media.title || 'Hotel media'} />
                    <div>
                      <strong>{media.title || media.category}</strong>
                      <small>{media.category.replaceAll('_', ' ')}</small>
                      <button type="button" onClick={() => void deleteMedia(media)} disabled={busy}>Remove</button>
                    </div>
                  </article>
                ))}
              </div>
            )}
          </article>
        </div>
      )}

      {activeStep === 'languages' && (
        <div className="simple-step-content">
          <div className="simple-step-heading">
            <p>02 — Languages</p>
            <h2>Choose languages and greetings</h2>
            <span>English is always the fallback. Urdu is not included. Hotels can edit every greeting.</span>
          </div>

          <article className="simple-panel">
            <h3>Languages shown to guests</h3>
            <div className="simple-language-grid">
              {GUEST_GUIDE_LOCALES.map((language) => {
                const mandatory = language.code === 'en'
                const checked = settingsDraft.enabled_locales.includes(language.code)
                return (
                  <label key={language.code}>
                    <input
                      type="checkbox"
                      checked={checked}
                      disabled={mandatory}
                      onChange={(event) => {
                        setSettingsDraft((current) => {
                          const next = event.target.checked
                            ? [...new Set([...current.enabled_locales, language.code])]
                            : current.enabled_locales.filter((code) => code !== language.code)
                          return { ...current, enabled_locales: next }
                        })
                      }}
                    />
                    <span>
                      <strong>{language.nativeName}</strong>
                      <small>{language.label}</small>
                    </span>
                  </label>
                )
              })}
            </div>
            <button className="simple-primary" type="button" onClick={() => void saveBrandSettings()} disabled={busy}>
              Save enabled languages
            </button>
          </article>

          <article className="simple-panel simple-language-content">
            <div className="simple-panel-heading"><div><h3>Translate the complete guest guide</h3><p>System buttons and labels translate automatically. Edit hotel-specific text and section headings for the selected language here.</p></div></div>
            <div className="simple-form-grid">
              <Field label="Hero label"><input value={contentDraft.welcome_kicker || ''} onChange={(event) => setContentDraft((current) => ({ ...current, welcome_kicker: event.target.value }))} /></Field>
              <Field label="Hero title"><input value={contentDraft.welcome_title || ''} onChange={(event) => setContentDraft((current) => ({ ...current, welcome_title: event.target.value }))} /></Field>
              <Field label="Hero message" wide><textarea value={contentDraft.welcome_message || ''} onChange={(event) => setContentDraft((current) => ({ ...current, welcome_message: event.target.value }))} /></Field>
              <Field label="Offer badge"><input value={settingsDraft.branding.offer.translations?.[editingLocale]?.badge || settingsDraft.branding.offer.badge || ''} onChange={(event) => setSettingsDraft((current) => ({ ...current, branding: { ...current.branding, offer: { ...current.branding.offer, translations: { ...(current.branding.offer.translations || {}), [editingLocale]: { ...(current.branding.offer.translations?.[editingLocale] || {}), badge: event.target.value } } } } }))} /></Field>
              <Field label="Offer title"><input value={settingsDraft.branding.offer.translations?.[editingLocale]?.title || settingsDraft.branding.offer.title || ''} onChange={(event) => setSettingsDraft((current) => ({ ...current, branding: { ...current.branding, offer: { ...current.branding.offer, translations: { ...(current.branding.offer.translations || {}), [editingLocale]: { ...(current.branding.offer.translations?.[editingLocale] || {}), title: event.target.value } } } } }))} /></Field>
              <Field label="Offer description" wide><textarea value={settingsDraft.branding.offer.translations?.[editingLocale]?.description || settingsDraft.branding.offer.description || ''} onChange={(event) => setSettingsDraft((current) => ({ ...current, branding: { ...current.branding, offer: { ...current.branding.offer, translations: { ...(current.branding.offer.translations || {}), [editingLocale]: { ...(current.branding.offer.translations?.[editingLocale] || {}), description: event.target.value } } } } }))} /></Field>
              <Field label="Concierge title"><input value={contentDraft.concierge_title || ''} onChange={(event) => setContentDraft((current) => ({ ...current, concierge_title: event.target.value }))} /></Field>
              <Field label="Concierge subtitle"><input value={contentDraft.concierge_subtitle || ''} onChange={(event) => setContentDraft((current) => ({ ...current, concierge_subtitle: event.target.value }))} /></Field>
              <Field label="Feedback title"><input value={contentDraft.private_feedback_title || ''} onChange={(event) => setContentDraft((current) => ({ ...current, private_feedback_title: event.target.value }))} /></Field>
              <Field label="Feedback prompt" wide><textarea value={contentDraft.private_feedback_prompt || ''} onChange={(event) => setContentDraft((current) => ({ ...current, private_feedback_prompt: event.target.value }))} /></Field>
              <Field label="Review title"><input value={contentDraft.review_section_title || ''} onChange={(event) => setContentDraft((current) => ({ ...current, review_section_title: event.target.value }))} /></Field>
              <Field label="Review prompt"><input value={contentDraft.review_prompt || ''} onChange={(event) => setContentDraft((current) => ({ ...current, review_prompt: event.target.value }))} /></Field>
              <Field label="Thank-you message" wide><textarea value={contentDraft.footer_message || ''} onChange={(event) => setContentDraft((current) => ({ ...current, footer_message: event.target.value }))} /></Field>
            </div>
            <details className="simple-translation-sections"><summary>Edit every section heading in {editingLocale.toUpperCase()}</summary><div className="simple-section-list">{builder.sections.slice().sort((a,b) => Number(a.sort_order||0)-Number(b.sort_order||0)).map((section) => { const draft=sectionDrafts[section.section_key]; if(!draft) return null; return <article key={section.id}><strong>{section.section_key.replaceAll('_',' ')}</strong><div><input value={draft.title} onChange={(event) => setSectionDrafts((current) => ({...current,[section.section_key]:{...current[section.section_key],title:event.target.value}}))} placeholder="Section title"/><input value={draft.subtitle} onChange={(event) => setSectionDrafts((current) => ({...current,[section.section_key]:{...current[section.section_key],subtitle:event.target.value}}))} placeholder="Section description"/></div></article>})}</div></details>
            <button className="simple-primary" type="button" onClick={() => void saveLanguageContent()} disabled={busy}>Save complete {editingLocale.toUpperCase()} guide</button>
          </article>

          {selectedGreeting && (
            <article className="simple-panel">
              <div className="simple-panel-heading">
                <div>
                  <h3>{selectedGreeting.native_name || selectedGreeting.language_name} greetings</h3>
                  <p>The guide chooses a greeting using the hotel timezone.</p>
                </div>
              </div>
              <div className="simple-form-grid">
                {[
                  ['neutral', 'General greeting'],
                  ['morning', 'Morning'],
                  ['afternoon', 'Afternoon'],
                  ['evening', 'Evening'],
                  ['night', 'Night'],
                ].map(([key, label]) => (
                  <Field key={key} label={label}>
                    <input
                      value={selectedGreeting[key] || ''}
                      onChange={(event) =>
                        setGreetingDrafts((current) => ({
                          ...current,
                          [editingLocale]: {
                            ...current[editingLocale],
                            [key]: event.target.value,
                          },
                        }))
                      }
                    />
                  </Field>
                ))}
              </div>
              <button className="simple-primary" type="button" onClick={() => void saveGreeting(editingLocale)} disabled={busy}>
                Save {selectedGreeting.native_name || selectedGreeting.language_name} greetings
              </button>
            </article>
          )}
        </div>
      )}

      {activeStep === 'contacts' && (
        <div className="simple-step-content">
          <div className="simple-step-heading">
            <p>03 — Contacts & Services</p>
            <h2>Set up one-tap guest help</h2>
            <span>No technical item keys or action types. Enter the real phone numbers and links.</span>
          </div>

          <article className="simple-panel simple-setup-card">
            <div>
              <h3>Essential guest actions</h3>
              <p>Housekeeping, water, towels, food menu and checkout request.</p>
            </div>
            <button type="button" className="simple-secondary" onClick={() => void prepareDefaultContent()} disabled={busy || essentialPrepared}>
              {essentialPrepared ? 'Essential actions ready' : 'Prepare essential actions'}
            </button>
          </article>

          <div className="simple-contact-list">
            {CONTACT_PRESETS.map((preset) => {
              const draft = contactValues[preset.key] || {}
              return (
                <article className="simple-panel" key={preset.key}>
                  <div className="simple-panel-heading">
                    <div>
                      <h3>{preset.title}</h3>
                      <p>{preset.description}</p>
                    </div>
                    <Toggle
                      checked={draft.is_enabled !== false}
                      onChange={(event) => setContactValues((current) => ({
                        ...current,
                        [preset.key]: { ...current[preset.key], is_enabled: event.target.checked },
                      }))}
                      label="Show"
                    />
                  </div>
                  <div className="simple-form-grid">
                    <Field label={preset.inputLabel} wide>
                      <input
                        value={draft.value || ''}
                        onChange={(event) => setContactValues((current) => ({
                          ...current,
                          [preset.key]: { ...current[preset.key], value: event.target.value },
                        }))}
                        placeholder={preset.placeholder}
                      />
                    </Field>
                    <Field label={`Guest-facing title (${editingLocale.toUpperCase()})`}>
                      <input
                        value={draft.title || ''}
                        onChange={(event) => setContactValues((current) => ({
                          ...current,
                          [preset.key]: { ...current[preset.key], title: event.target.value },
                        }))}
                      />
                    </Field>
                    <Field label="Short description">
                      <input
                        value={draft.description || ''}
                        onChange={(event) => setContactValues((current) => ({
                          ...current,
                          [preset.key]: { ...current[preset.key], description: event.target.value },
                        }))}
                      />
                    </Field>
                  </div>
                  <button className="simple-primary" type="button" onClick={() => void saveContact(preset)} disabled={busy}>
                    Save {preset.title}
                  </button>
                </article>
              )
            })}
          </div>
        </div>
      )}

      {activeStep === 'rooms' && (
        <div className="simple-step-content">
          <div className="simple-step-heading">
            <p>04 — Rooms & Instructions</p>
            <h2>Add room guides without repeating work</h2>
            <span>Hotel-wide instructions apply everywhere. Room-type instructions replace them for that category. A room override has the highest priority.</span>
          </div>

          <article className="simple-panel">
            <div className="simple-scope-explainer">
              <div><strong>1</strong><span>All rooms</span></div>
              <b>→</b>
              <div><strong>2</strong><span>Room type</span></div>
              <b>→</b>
              <div><strong>3</strong><span>Specific room</span></div>
            </div>

            <div className="simple-form-grid">
              <Field label="Where should this instruction apply?">
                <select
                  value={roomGuide.scope_type}
                  onChange={(event) => setRoomGuide((current) => ({
                    ...current,
                    scope_type: event.target.value,
                    room_type_id: '',
                    room_id: '',
                  }))}
                >
                  <option value="hotel">All rooms</option>
                  <option value="room_type">One room type</option>
                  <option value="room">One specific room</option>
                </select>
              </Field>
              <Field label="Instruction topic">
                <select
                  value={roomGuide.topic_key}
                  onChange={(event) => {
                    const topic = ROOM_GUIDE_TOPICS.find((entry) => entry.key === event.target.value)
                    setRoomGuide((current) => ({
                      ...current,
                      topic_key: event.target.value,
                      title: topic?.label || '',
                      description: topic?.description || '',
                      instructions_text: '',
                    }))
                  }}
                >
                  {ROOM_GUIDE_TOPICS.map((topic) => (
                    <option key={topic.key} value={topic.key}>{topic.label}</option>
                  ))}
                </select>
              </Field>
              {roomGuide.scope_type === 'room_type' && (
                <Field label="Room type">
                  <select value={roomGuide.room_type_id} onChange={(event) => setRoomGuide((current) => ({ ...current, room_type_id: event.target.value }))}>
                    <option value="">Select room type</option>
                    {builder.room_types.filter((entry) => entry.is_active !== false).map((entry) => (
                      <option key={entry.id} value={entry.id}>{entry.name}</option>
                    ))}
                  </select>
                </Field>
              )}
              {roomGuide.scope_type === 'room' && (
                <Field label="Room">
                  <select value={roomGuide.room_id} onChange={(event) => setRoomGuide((current) => ({ ...current, room_id: event.target.value }))}>
                    <option value="">Select room</option>
                    {builder.rooms.filter((entry) => entry.is_active !== false).map((entry) => (
                      <option key={entry.id} value={entry.id}>Room {entry.room_number}</option>
                    ))}
                  </select>
                </Field>
              )}
              <Field label={`Title (${editingLocale.toUpperCase()})`}>
                <input value={roomGuide.title} onChange={(event) => setRoomGuide((current) => ({ ...current, title: event.target.value }))} />
              </Field>
              <Field label="Short description">
                <input value={roomGuide.description} onChange={(event) => setRoomGuide((current) => ({ ...current, description: event.target.value }))} />
              </Field>
              <Field label="Instructions — one step per line" wide>
                <textarea
                  value={roomGuide.instructions_text}
                  onChange={(event) => setRoomGuide((current) => ({ ...current, instructions_text: event.target.value }))}
                  placeholder={'Press the Power button.\nSelect Cool mode.\nSet the temperature between 22°C and 24°C.'}
                />
              </Field>
            </div>
            <Toggle
              checked={roomGuide.is_enabled}
              onChange={(event) => setRoomGuide((current) => ({ ...current, is_enabled: event.target.checked }))}
              label="Show this instruction to guests"
            />
            <button className="simple-primary" type="button" onClick={() => void saveRoomGuide()} disabled={busy}>
              Save room instruction
            </button>
          </article>

          <article className="simple-panel simple-note-panel">
            <h3>Photos for a room type or room</h3>
            <p>Use Step 1 · Brand & Photos. Choose “Room Photo”, “AC Remote Photo”, “TV Remote Photo” or another device photo, then select the room type or specific room.</p>
            <button className="simple-secondary" type="button" onClick={() => setActiveStep('brand')}>Go to photos</button>
          </article>
        </div>
      )}

      {activeStep === 'local' && (
        <div className="simple-step-content">
          <div className="simple-step-heading">
            <p>05 — Local & Payment</p>
            <h2>Nearby help and easy payment</h2>
            <span>Local Convenience links are nearby places, not hotel facilities. Manual UPI payments always require hotel confirmation.</span>
          </div>

          <div className="simple-contact-list">
            {LOCAL_PRESETS.map((preset) => {
              const draft = localValues[preset.key] || {}
              return (
                <article className="simple-panel" key={preset.key}>
                  <div className="simple-panel-heading">
                    <div>
                      <h3>{preset.title}</h3>
                      <p>{preset.description}</p>
                    </div>
                    <Toggle
                      checked={draft.is_enabled !== false}
                      onChange={(event) => setLocalValues((current) => ({
                        ...current,
                        [preset.key]: { ...current[preset.key], is_enabled: event.target.checked },
                      }))}
                      label="Show"
                    />
                  </div>
                  <Field label={preset.key === 'transport_assistance' ? 'Maps URL or reception phone' : 'Google Maps URL'} wide>
                    <input
                      value={draft.value || ''}
                      onChange={(event) => setLocalValues((current) => ({
                        ...current,
                        [preset.key]: { ...current[preset.key], value: event.target.value },
                      }))}
                      placeholder="https://www.google.com/maps/search/..."
                    />
                  </Field>
                  <button className="simple-primary" type="button" onClick={() => void saveLocal(preset)} disabled={busy}>
                    Save {preset.title}
                  </button>
                </article>
              )
            })}
          </div>

          <article className="simple-panel">
            <h3>UPI and payment QR</h3>
            <Toggle
              checked={paymentDraft.is_enabled === true}
              onChange={(event) => setPaymentDraft((current) => ({ ...current, is_enabled: event.target.checked }))}
              label="Show payment section"
              description="The guest guide can display the current folio balance, UPI details and QR."
            />
            <div className="simple-form-grid">
              <Field label="Payee name">
                <input value={paymentDraft.payee_name || ''} onChange={(event) => setPaymentDraft((current) => ({ ...current, payee_name: event.target.value }))} />
              </Field>
              <Field label="UPI ID">
                <input value={paymentDraft.upi_id || ''} onChange={(event) => setPaymentDraft((current) => ({ ...current, upi_id: event.target.value }))} placeholder="hotelname@ybl" />
              </Field>
              <Field label="Payment QR">
                <select value={paymentDraft.qr_media_id || ''} onChange={(event) => setPaymentDraft((current) => ({ ...current, qr_media_id: event.target.value }))}>
                  <option value="">No QR selected</option>
                  {activeMedia.filter((media) => media.category === 'payment_qr').map((media) => (
                    <option key={media.id} value={media.id}>{media.title || media.media_key}</option>
                  ))}
                </select>
              </Field>
              <Field label="Instructions" wide>
                <textarea value={paymentDraft.instructions || ''} onChange={(event) => setPaymentDraft((current) => ({ ...current, instructions: event.target.value }))} placeholder="Please confirm payment with reception after completion." />
              </Field>
            </div>
            <Toggle
              checked={paymentDraft.show_outstanding_balance !== false}
              onChange={(event) => setPaymentDraft((current) => ({ ...current, show_outstanding_balance: event.target.checked }))}
              label="Show current StayQR folio balance"
            />
            <Toggle
              checked={paymentDraft.require_reception_confirmation !== false}
              onChange={(event) => setPaymentDraft((current) => ({ ...current, require_reception_confirmation: event.target.checked }))}
              label="Tell guests to confirm manual UPI payment with reception"
            />
            <button className="simple-primary" type="button" onClick={() => void savePayment()} disabled={busy}>
              Save payment information
            </button>
          </article>
        </div>
      )}

      {activeStep === 'publish' && (
        <div className="simple-step-content">
          <div className="simple-step-heading">
            <p>06 — Review & Publish</p>
            <h2>Choose visible sections and publish</h2>
            <span>Draft changes are not visible to guests until you publish a new version.</span>
          </div>

          <article className="simple-panel">
            <div className="simple-panel-heading">
              <div>
                <h3>Guide sections</h3>
                <p>Hide sections that are not relevant to this hotel. Edit titles in the selected language.</p>
              </div>
            </div>
            <div className="simple-section-list">
              {builder.sections
                .slice()
                .sort((a, b) => Number(a.sort_order || 0) - Number(b.sort_order || 0))
                .map((section) => {
                  const draft = sectionDrafts[section.section_key]
                  if (!draft) return null
                  return (
                    <article key={section.id}>
                      <Toggle
                        checked={draft.is_enabled}
                        onChange={(event) => setSectionDrafts((current) => ({
                          ...current,
                          [section.section_key]: { ...current[section.section_key], is_enabled: event.target.checked },
                        }))}
                        label={draft.title || section.section_key.replaceAll('_', ' ')}
                      />
                      <div>
                        <input
                          value={draft.title}
                          onChange={(event) => setSectionDrafts((current) => ({
                            ...current,
                            [section.section_key]: { ...current[section.section_key], title: event.target.value },
                          }))}
                          placeholder="Section title"
                        />
                        <input
                          value={draft.subtitle}
                          onChange={(event) => setSectionDrafts((current) => ({
                            ...current,
                            [section.section_key]: { ...current[section.section_key], subtitle: event.target.value },
                          }))}
                          placeholder="Short description"
                        />
                        <button type="button" onClick={() => void saveSection(section.section_key)} disabled={busy}>Save</button>
                      </div>
                    </article>
                  )
                })}
            </div>
          </article>

          <article className="simple-panel simple-readiness-panel">
            <h3>Setup summary</h3>
            <div>
              <span><strong>{settingsDraft.enabled_locales.length}</strong> languages enabled</span>
              <span><strong>{completedContactCount}</strong> of {CONTACT_PRESETS.length} contact links configured</span>
              <span><strong>{completedLocalCount}</strong> of {LOCAL_PRESETS.length} Local Convenience links configured</span>
              <span><strong>{activeMedia.length}</strong> photos available</span>
              <span><strong>{builder.items.filter((item) => item.item_type === 'instruction').length}</strong> room instructions</span>
            </div>
          </article>

          <article className="simple-panel simple-publish-panel">
            <div>
              <h3>Publish guest guide</h3>
              <p>Publishing creates an immutable version. Existing signed guest links automatically use the latest published version.</p>
            </div>
            <Field label="Version note" wide>
              <input value={publishNote} onChange={(event) => setPublishNote(event.target.value)} placeholder="Updated hotel photos and room instructions" />
            </Field>
            <button className="simple-publish-button" type="button" onClick={() => void publishGuide()} disabled={busy}>
              {busy ? 'Publishing…' : 'Publish Guest Guide'}
            </button>
          </article>
        </div>
      )}
    </section>
  )
}
