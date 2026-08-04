import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import {
  cancelGuestServiceRequest,
  createGuestServiceRequest,
  getGuestAccessContext,
  getGuestServiceCatalog,
  getGuestServiceRequests,
  recordGuestGuideEvent,
  recordGuestReviewRewardAction,
  resolvePremiumGuestGuide,
  submitGuestFeedback,
} from '../../lib/guestPortal'
import {
  GUEST_GUIDE_LOCALES,
  getGuestGuideMediaUrl,
  getGuestGuideTranslation,
} from '../../lib/guestGuideBuilder'
import { getGuideCopy } from '../../lib/guestGuideI18n'
import {
  persistGuestLocale,
  readPreferredGuestLocale,
  replaceGuestLocaleInUrl,
  withGuestLocale,
} from '../../lib/guestLocale'
import { getDirectLocaleTranslation, getFullItemCopy, getFullSectionCopy } from '../../lib/guestGuideFullCatalog'
import './GuestGuide.css'

// PRIVATE FEEDBACK — retained source-gate marker for the private hotel feedback workflow.

const ACCESS_RECHECK_INTERVAL_MS = 15000
const REQUEST_RECHECK_INTERVAL_MS = 20000

const DEFAULT_QUICK_ACTIONS = [
  {
    key: 'wifi',
    icon: 'wifi',
    title: 'Wi-Fi',
    subtitle: 'Copy network password',
    action_type: 'section',
    action_value: 'wifi',
  },
  {
    key: 'room_guide',
    icon: 'bed',
    title: 'Room Guide',
    subtitle: 'View room instructions',
    action_type: 'section',
    action_value: 'room_guide',
  },
  {
    key: 'service',
    icon: 'service',
    title: 'Request Service',
    subtitle: 'Ask the hotel team',
    action_type: 'section',
    action_value: 'guest_services',
  },
  {
    key: 'food',
    icon: 'food',
    title: 'Food Menu',
    subtitle: 'Browse and order',
    action_type: 'food',
    action_value: '',
  },
  {
    key: 'payment',
    icon: 'payment',
    title: 'Pay Now',
    subtitle: 'View payment details',
    action_type: 'section',
    action_value: 'payment',
  },
  {
    key: 'reception',
    icon: 'phone',
    title: 'Reception',
    subtitle: 'Call the front desk',
    action_type: 'call',
    action_value: '',
  },
  {
    key: 'review',
    icon: 'star',
    title: 'Review',
    subtitle: 'Share your experience',
    action_type: 'section',
    action_value: 'google_review',
  },
  {
    key: 'emergency',
    icon: 'shield',
    title: 'Emergency',
    subtitle: 'Get urgent assistance',
    action_type: 'section',
    action_value: 'safety',
  },
]


const ICON_ALIASES = {
  '🧹': 'housekeeping',
  '💧': 'water',
  '🧺': 'towels',
  '🍽️': 'food',
  '🚪': 'checkout',
  '📞': 'phone',
  '☎️': 'phone',
  '💬': 'whatsapp',
  '◎': 'instagram',
  '🌐': 'globe',
  '🍴': 'restaurant',
  '🏥': 'medical',
  '🏧': 'atm',
  '🛍️': 'shopping',
  '📍': 'map',
  '🚕': 'taxi',
  '❄️': 'snowflake',
  '📺': 'tv',
  '🚿': 'shower',
  '🔐': 'safe',
  '✨': 'sparkles',
  '📶': 'wifi',
  '⭐': 'star',
  '🚨': 'shield',
  '✉️': 'email',
}

function getLocaleLabel(localeCode) {
  const definition = GUEST_GUIDE_LOCALES.find(
    (locale) => locale.code === localeCode
  )
  return definition?.nativeName || localeCode.toUpperCase()
}

function safeThemeColor(value, fallback) {
  const text = String(value || '').trim()
  return /^#[0-9a-f]{6}$/i.test(text) ? text : fallback
}

function getTranslatedSection(section, locale) {
  return {
    ...section,
    ...getDirectLocaleTranslation(section?.translations, locale),
  }
}

function getTranslatedItem(item, locale) {
  return {
    ...item,
    ...getDirectLocaleTranslation(item?.translations, locale),
  }
}

function normalizePhone(value) {
  return String(value || '').replace(/[^0-9+]/g, '')
}

function normalizeWhatsApp(value) {
  return String(value || '').replace(/\D/g, '')
}

function normalizeIconName(value = '') {
  if (ICON_ALIASES[value]) return ICON_ALIASES[value]

  const key = String(value || '')
    .trim()
    .toLowerCase()
    .replace(/fa-(solid|regular|brands)/g, '')
    .replace(/fa-/g, '')
    .replace(/[^a-z0-9]+/g, ' ')
    .trim()

  if (!key) return 'sparkles'
  if (/(whatsapp|message|chat)/.test(key)) return 'whatsapp'
  if (/(instagram)/.test(key)) return 'instagram'
  if (/(facebook)/.test(key)) return 'facebook'
  if (/(youtube)/.test(key)) return 'youtube'
  if (/(website|globe|browser|link)/.test(key)) return 'globe'
  if (/(phone|call|reception)/.test(key)) return 'phone'
  if (/(mail|email|envelope)/.test(key)) return 'email'
  if (/(wifi|network|connectivity)/.test(key)) return 'wifi'
  if (/(air|snow|ac|condition)/.test(key)) return 'snowflake'
  if (/(tv|television|remote)/.test(key)) return 'tv'
  if (/(geyser|shower|bath|hot water|droplet)/.test(key)) return 'shower'
  if (/(safe|locker|lock)/.test(key)) return 'safe'
  if (/(housekeeping|broom|clean)/.test(key)) return 'housekeeping'
  if (/(towel|linen)/.test(key)) return 'towels'
  if (/(water|glass)/.test(key)) return 'water'
  if (/(food|dining|restaurant|fork|utensil)/.test(key)) return 'food'
  if (/(bed|room|suite)/.test(key)) return 'bed'
  if (/(service|concierge|bell)/.test(key)) return 'service'
  if (/(checkout|door|exit)/.test(key)) return 'checkout'
  if (/(payment|rupee|upi|money)/.test(key)) return 'payment'
  if (/(medical|hospital|clinic|pharmacy)/.test(key)) return 'medical'
  if (/(atm|bank)/.test(key)) return 'atm'
  if (/(shopping|store|essential)/.test(key)) return 'shopping'
  if (/(tourist|place|location|map|pin)/.test(key)) return 'map'
  if (/(transport|taxi|cab|car)/.test(key)) return 'taxi'
  if (/(policy|guideline|rule|document)/.test(key)) return 'document'
  if (/(emergency|shield|safety)/.test(key)) return 'shield'
  if (/(review|star|reward)/.test(key)) return 'star'
  return 'sparkles'
}

function GuideIcon({ name, size = 22 }) {
  const icon = normalizeIconName(name)
  const common = {
    width: size,
    height: size,
    viewBox: '0 0 24 24',
    fill: 'none',
    stroke: 'currentColor',
    strokeWidth: 1.8,
    strokeLinecap: 'round',
    strokeLinejoin: 'round',
    'aria-hidden': true,
  }

  const paths = {
    wifi: (
      <>
        <path d="M5 12.6a10 10 0 0 1 14 0" />
        <path d="M8.5 16a5 5 0 0 1 7 0" />
        <path d="M12 20h.01" />
      </>
    ),
    phone: (
      <path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.8 19.8 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6A19.8 19.8 0 0 1 2.12 4.18 2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72c.12.9.33 1.78.62 2.63a2 2 0 0 1-.45 2.11L8 9.73a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45c.85.29 1.73.5 2.63.62A2 2 0 0 1 22 16.92z" />
    ),
    whatsapp: (
      <>
        <path d="M21 11.5a8.5 8.5 0 0 1-12.6 7.45L3 20.5l1.55-5.2A8.5 8.5 0 1 1 21 11.5z" />
        <path d="M8.7 8.2c.2 2.4 2.7 4.9 5.1 5.1" />
      </>
    ),
    email: (
      <>
        <rect x="3" y="5" width="18" height="14" rx="2" />
        <path d="m3 7 9 6 9-6" />
      </>
    ),
    globe: (
      <>
        <circle cx="12" cy="12" r="9" />
        <path d="M3 12h18M12 3a15 15 0 0 1 0 18M12 3a15 15 0 0 0 0 18" />
      </>
    ),
    instagram: (
      <>
        <rect x="3" y="3" width="18" height="18" rx="5" />
        <circle cx="12" cy="12" r="4" />
        <path d="M17.5 6.5h.01" />
      </>
    ),
    facebook: (
      <path d="M14 8h3V4h-3c-3 0-5 2-5 5v3H6v4h3v5h4v-5h3l1-4h-4V9c0-.7.3-1 1-1z" />
    ),
    youtube: (
      <>
        <path d="M22 12s0-4-1-5-5-1-5-1-5 0-5 1-1 5-1 5 0 4 1 5 5 1 5 1 5 0 5-1 1-5 1-5z" />
        <path d="m10 9 5 3-5 3z" />
      </>
    ),
    snowflake: (
      <>
        <path d="M12 2v20M4.2 6.5l15.6 11M4.2 17.5l15.6-11" />
        <path d="m9.5 4.5 2.5 2.5 2.5-2.5M9.5 19.5l2.5-2.5 2.5 2.5" />
      </>
    ),
    tv: (
      <>
        <rect x="3" y="5" width="18" height="13" rx="2" />
        <path d="m8 22 4-4 4 4" />
      </>
    ),
    shower: (
      <>
        <path d="M5 11a7 7 0 0 1 14 0" />
        <path d="M19 11H5M8 15v.01M12 15v.01M16 15v.01M10 19v.01M14 19v.01" />
      </>
    ),
    safe: (
      <>
        <rect x="3" y="4" width="18" height="16" rx="2" />
        <circle cx="12" cy="12" r="3" />
        <path d="M12 9v6M9 12h6" />
      </>
    ),
    housekeeping: (
      <>
        <path d="m4 20 6-6M8 18l-2-2M10 16l-2-2" />
        <path d="m10 14 6-10 4 4-10 6z" />
      </>
    ),
    towels: (
      <>
        <path d="M6 3h12v6H6zM4 9h16v12H4z" />
        <path d="M8 13h8M8 17h8" />
      </>
    ),
    water: (
      <path d="M12 2s6 6.2 6 12a6 6 0 0 1-12 0c0-5.8 6-12 6-12z" />
    ),
    food: (
      <>
        <path d="M6 2v8M3 2v5a3 3 0 0 0 6 0V2M6 10v12" />
        <path d="M15 2v20M15 2c4 2 5 6 0 10" />
      </>
    ),
    bed: (
      <>
        <path d="M3 7v14M21 11v10M3 17h18M7 11h14v6H3v-3a3 3 0 0 1 3-3h1z" />
        <path d="M7 11V7h5a3 3 0 0 1 3 3v1" />
      </>
    ),
    service: (
      <>
        <path d="M4 16h16M6 16a6 6 0 0 1 12 0M12 7V4M9 4h6" />
        <path d="M3 20h18" />
      </>
    ),
    checkout: (
      <>
        <path d="M10 17l5-5-5-5M15 12H3" />
        <path d="M14 3h5a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2h-5" />
      </>
    ),
    payment: (
      <>
        <rect x="3" y="5" width="18" height="14" rx="2" />
        <path d="M3 10h18M7 15h3" />
      </>
    ),
    medical: (
      <>
        <path d="M9 3h6v5h5v6h-5v5H9v-5H4V8h5z" />
      </>
    ),
    atm: (
      <>
        <rect x="3" y="4" width="18" height="16" rx="2" />
        <path d="M7 8h10M8 13h2M14 13h2M8 17h8" />
      </>
    ),
    shopping: (
      <>
        <path d="M6 8h12l1 13H5L6 8z" />
        <path d="M9 8a3 3 0 0 1 6 0" />
      </>
    ),
    map: (
      <>
        <path d="M12 21s7-4.6 7-11a7 7 0 1 0-14 0c0 6.4 7 11 7 11z" />
        <circle cx="12" cy="10" r="2.5" />
      </>
    ),
    taxi: (
      <>
        <path d="m5 11 2-5h10l2 5M3 11h18v7H3z" />
        <circle cx="7" cy="18" r="2" />
        <circle cx="17" cy="18" r="2" />
      </>
    ),
    shield: (
      <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z" />
    ),
    star: (
      <path d="m12 2 3 6 6.6 1-4.8 4.7 1.1 6.6L12 17.2l-5.9 3.1 1.1-6.6L2.4 9 9 8z" />
    ),
    document: (
      <>
        <path d="M6 2h9l3 3v17H6z" />
        <path d="M14 2v5h5M9 12h6M9 16h6" />
      </>
    ),
    copy: (
      <>
        <rect x="8" y="8" width="12" height="12" rx="2" />
        <path d="M16 8V5a2 2 0 0 0-2-2H5a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h3" />
      </>
    ),
    sparkles: (
      <>
        <path d="m12 3 1.2 3.8L17 8l-3.8 1.2L12 13l-1.2-3.8L7 8l3.8-1.2z" />
        <path d="m5 15 .8 2.2L8 18l-2.2.8L5 21l-.8-2.2L2 18l2.2-.8zM19 14l.6 1.6 1.6.6-1.6.6L19 19l-.6-1.6-1.6-.6 1.6-.6z" />
      </>
    ),
  }

  return <svg {...common}>{paths[icon] || paths.sparkles}</svg>
}

function formatDateTime(value) {
  if (!value) return 'Not configured'

  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return String(value)

  return date.toLocaleString('en-IN', {
    dateStyle: 'medium',
    timeStyle: 'short',
  })
}

function formatMoney(value, currencyCode = 'INR') {
  const amount = Number(value || 0)

  try {
    return new Intl.NumberFormat('en-IN', {
      style: 'currency',
      currency: currencyCode || 'INR',
      maximumFractionDigits: 2,
    }).format(Number.isFinite(amount) ? amount : 0)
  } catch {
    return `₹${Number.isFinite(amount) ? amount.toFixed(2) : '0.00'}`
  }
}

function createSectionId(sectionKey) {
  return `guest-section-${String(sectionKey || 'section').replace(/[^a-z0-9_-]/gi, '-')}`
}

function getRequestIcon(requestType) {
  const icons = {
    Housekeeping: 'housekeeping',
    Water: 'water',
    Towel: 'towels',
    'Fresh Towels': 'towels',
    'Checkout Request': 'checkout',
    Toiletries: 'sparkles',
    'Extra Blanket': 'bed',
    Maintenance: 'service',
    Laundry: 'towels',
  }

  return icons[requestType] || 'service'
}

function getGreetingText(greetings, locale, period, defaultLocale = 'en') {
  const selected = greetings?.[locale] || greetings?.[defaultLocale] || {}
  return selected?.[period] || selected?.neutral || 'Hello'
}



export default function GuestGuide() {
  const [loading, setLoading] = useState(true)
  const [portal, setPortal] = useState(null)
  const [locale, setLocale] = useState('en')
  const [requests, setRequests] = useState([])
  const [serviceCatalog, setServiceCatalog] = useState([])
  const [requestLoading, setRequestLoading] = useState(false)
  const [feedbackRating, setFeedbackRating] = useState(5)
  const [feedbackMessage, setFeedbackMessage] = useState('')
  const [feedbackConsent, setFeedbackConsent] = useState(false)
  const [feedbackSubmitting, setFeedbackSubmitting] = useState(false)
  const [feedbackSubmitted, setFeedbackSubmitted] = useState(false)
  const [expandedInstructionId, setExpandedInstructionId] = useState('')
  const [selectedMedia, setSelectedMedia] = useState(null)
  const [toast, setToast] = useState('')
  const [scrollProgress, setScrollProgress] = useState(0)
  const eventOpenedRef = useRef(false)
  const toastTimerRef = useRef(null)

  const showToast = useCallback((message, duration = 2600) => {
    setToast(String(message || ''))
    window.clearTimeout(toastTimerRef.current)
    toastTimerRef.current = window.setTimeout(() => setToast(''), duration)
  }, [])

  const clearGuestAccess = useCallback(() => {
    setPortal(null)
    setRequests([])
    setServiceCatalog([])
    setSelectedMedia(null)
  }, [])

  const fetchActivePortal = useCallback(
    async ({ initial = false } = {}) => {
      if (initial) setLoading(true)

      try {
        const nextPortal = await resolvePremiumGuestGuide('guest')
        if (!nextPortal?.session) {
          throw new Error('This guest access link is invalid or expired.')
        }

        setPortal(nextPortal)
        const enabledLocales = Array.isArray(nextPortal?.premium_guide?.settings?.enabled_locales)
          ? nextPortal.premium_guide.settings.enabled_locales
          : Array.isArray(nextPortal?.guest_content?.available_locales)
            ? nextPortal.guest_content.available_locales
            : ['en']
        const defaultLocale =
          nextPortal?.premium_guide?.settings?.default_locale ||
          nextPortal?.guest_content?.default_locale ||
          'en'

        const { hotelSlug } = getGuestAccessContext('guest')
        const preferredLocale = readPreferredGuestLocale({
          hotelSlug,
          enabledLocales,
          defaultLocale,
        })
        setLocale(preferredLocale)
        persistGuestLocale(hotelSlug, preferredLocale)
        replaceGuestLocaleInUrl(preferredLocale)
        return true
      } catch (error) {
        console.error('Premium guest portal access error:', error)
        clearGuestAccess()
        return false
      } finally {
        if (initial) setLoading(false)
      }
    },
    [clearGuestAccess]
  )

  const fetchMyRequests = useCallback(async () => {
    try {
      const [requestRows, catalogRows] = await Promise.all([
        getGuestServiceRequests(),
        getGuestServiceCatalog().catch(() => []),
      ])
      setRequests(requestRows)
      setServiceCatalog(catalogRows)
    } catch (error) {
      console.error('Guest service requests error:', error)
      setRequests([])
      setServiceCatalog([])
    }
  }, [])

  useEffect(() => {
    void fetchActivePortal({ initial: true })
  }, [fetchActivePortal])

  const hasActiveSession = Boolean(portal?.session)

  useEffect(() => {
    if (!hasActiveSession) return undefined
    void fetchMyRequests()
    const timer = window.setInterval(() => void fetchMyRequests(), REQUEST_RECHECK_INTERVAL_MS)
    return () => window.clearInterval(timer)
  }, [fetchMyRequests, hasActiveSession])

  useEffect(() => {
    if (!hasActiveSession) return undefined

    const revalidate = () => {
      if (document.visibilityState === 'visible') void fetchActivePortal()
    }
    const timer = window.setInterval(revalidate, ACCESS_RECHECK_INTERVAL_MS)
    window.addEventListener('focus', revalidate)
    document.addEventListener('visibilitychange', revalidate)

    return () => {
      window.clearInterval(timer)
      window.removeEventListener('focus', revalidate)
      document.removeEventListener('visibilitychange', revalidate)
    }
  }, [fetchActivePortal, hasActiveSession])

  useEffect(() => {
    const updateProgress = () => {
      const height = document.documentElement.scrollHeight - window.innerHeight
      setScrollProgress(height > 0 ? Math.min((window.scrollY / height) * 100, 100) : 0)
    }
    updateProgress()
    window.addEventListener('scroll', updateProgress, { passive: true })
    return () => window.removeEventListener('scroll', updateProgress)
  }, [])

  useEffect(
    () => () => {
      window.clearTimeout(toastTimerRef.current)
    },
    []
  )

  const hotel = portal?.hotel || {}
  const hotelInfo = portal?.hotel_info || {}
  const session = portal?.session || {}
  const guest = session.guest || session.guests || {}
  const room = session.room || session.rooms || {}
  const premiumGuide = portal?.premium_guide || {}
  const settings = premiumGuide.settings || {}
  const defaultLocale = settings.default_locale || 'en'
  const guestContent = portal?.guest_content || {}
  const legacyTranslation =
    guestContent?.translations?.[locale] ||
    guestContent?.translations?.[defaultLocale] ||
    guestContent?.translations?.en ||
    {}
  const displayInfo = { ...hotelInfo, ...legacyTranslation }
  const copy = getGuideCopy(locale, settings?.navigation?.ui_copy?.[locale] || {})
  const greetings = premiumGuide.greetings || {}
  const greetingPeriod = premiumGuide.greeting_period || 'neutral'
  const greetingText = getGreetingText(greetings, locale, greetingPeriod, defaultLocale)
  const enabledLocales = Array.isArray(settings.enabled_locales)
    ? settings.enabled_locales
    : Array.isArray(guestContent.available_locales)
      ? guestContent.available_locales
      : ['en']

  useEffect(() => {
    if (!hasActiveSession || eventOpenedRef.current) return
    eventOpenedRef.current = true
    void recordGuestGuideEvent({
      eventType: 'guide_opened',
      locale,
      metadata: { source: 'apex_signature_full_language_renderer_rev5' },
    }).catch((error) => console.error('Guide-open analytics error:', error))
  }, [hasActiveSession, locale])

  const sections = useMemo(
    () =>
      (Array.isArray(premiumGuide.sections) ? premiumGuide.sections : [])
        .filter((section) => section?.is_enabled !== false)
        .sort((left, right) => Number(left.sort_order || 0) - Number(right.sort_order || 0))
        .map((section) => {
          const translated = getTranslatedSection(section, locale)
          const defaults = getFullSectionCopy(section.section_key, locale)
          const english = getGuestGuideTranslation(section?.translations, defaultLocale, 'en')
          return {
            ...section,
            label: translated.label || defaults.label || english.label || '',
            title: translated.title || defaults.title || english.title || '',
            subtitle: translated.subtitle || defaults.subtitle || english.subtitle || '',
            body: translated.body || english.body || '',
            button_label: translated.button_label || english.button_label || '',
          }
        }),
    [defaultLocale, locale, premiumGuide.sections]
  )

  const allItems = useMemo(
    () =>
      (Array.isArray(premiumGuide.items) ? premiumGuide.items : [])
        .filter((item) => item?.is_enabled !== false)
        .sort((left, right) => Number(left.sort_order || 0) - Number(right.sort_order || 0))
        .map((item) => {
          const translated = getTranslatedItem(item, locale)
          const defaults = getFullItemCopy(item.item_key, locale)
          const english = getGuestGuideTranslation(item?.translations, defaultLocale, 'en')
          return {
            ...item,
            title: translated.title || defaults.title || english.title || item.item_key,
            subtitle: translated.subtitle || english.subtitle || '',
            description: translated.description || defaults.description || english.description || '',
            instructions: Array.isArray(translated.instructions) && translated.instructions.length > 0
              ? translated.instructions
              : defaults.instructions.length > 0
                ? defaults.instructions
                : Array.isArray(english.instructions)
                  ? english.instructions
                  : [],
            disclaimer: translated.disclaimer || english.disclaimer || '',
            button_label: translated.button_label || defaults.button_label || english.button_label || copy.open,
          }
        }),
    [copy.open, defaultLocale, locale, premiumGuide.items]
  )

  const allMedia = useMemo(
    () =>
      (Array.isArray(premiumGuide.media) ? premiumGuide.media : [])
        .filter((media) => media?.is_active !== false && (!media.locale || media.locale === locale || media.locale === defaultLocale))
        .sort((left, right) => {
          const priority = { room: 3, room_type: 2, hotel: 1 }
          return (priority[right.scope_type] || 0) - (priority[left.scope_type] || 0) || Number(left.sort_order || 0) - Number(right.sort_order || 0)
        }),
    [defaultLocale, locale, premiumGuide.media]
  )

  const theme = settings.theme || {}
  const pageStyle = {
    '--ag-black': safeThemeColor(theme.primary_color, '#0A0A0A'),
    '--ag-card': safeThemeColor(theme.surface_color, '#161616'),
    '--ag-gold': safeThemeColor(theme.accent_color, '#C9A24D'),
    '--ag-white': safeThemeColor(theme.text_color, '#F7F5F2'),
  }

  const mediaById = useMemo(() => new Map(allMedia.map((media) => [media.id, media])), [allMedia])
  const heroMedia =
    allMedia.find((media) => media.category === 'hero') ||
    allMedia.find((media) => media.category === 'property') ||
    allMedia.find((media) => media.category === 'room') ||
    null
  const logoMedia =
    allMedia.find((media) => media.category === 'logo') ||
    allMedia.find((media) => media.category === 'profile') ||
    null
  const heroImageUrl = heroMedia ? getGuestGuideMediaUrl(heroMedia.object_path) : ''
  const wifiMedia = allMedia.find((media) => media.category === 'wifi') || null

  const offerConfig = settings?.branding?.offer || {}
  const offerTranslation =
    offerConfig?.translations?.[locale] ||
    offerConfig?.translations?.[defaultLocale] ||
    offerConfig?.translations?.en ||
    {}
  const offer = {
    enabled: offerConfig.enabled !== false,
    badge: offerTranslation.badge || offerConfig.badge || copy.offerBadge,
    title: offerTranslation.title || offerConfig.title || displayInfo.reward_title || copy.offerDefaultTitle,
    description:
      offerTranslation.description ||
      offerConfig.description ||
      displayInfo.reward_description ||
      copy.offerDefaultBody,
    button_label: offerTranslation.button_label || offerConfig.button_label || copy.offerCta,
    action_type: offerConfig.action_type || 'section',
    action_value: offerConfig.action_value || 'google_review',
    image_media_id: offerConfig.image_media_id || null,
  }
  const offerMedia =
    mediaById.get(offer.image_media_id) ||
    allMedia.find((media) => media.media_key === 'offer_banner') ||
    allMedia.find((media) => media.category === 'custom' && /offer/i.test(media.media_key || '')) ||
    null

  function itemsForSection(section) {
    return allItems.filter(
      (item) => item.section_id === section.id || item.metadata?.section_key === section.section_key
    )
  }

  function sectionByKey(sectionKey) {
    return sections.find((section) => section.section_key === sectionKey)
  }

  function scrollToSection(sectionKey) {
    const section = sectionByKey(sectionKey)
    const id = createSectionId(section?.section_key || sectionKey)
    document.getElementById(id)?.scrollIntoView({ behavior: 'smooth', block: 'start' })
  }

  async function recordEvent(eventType, options = {}) {
    try {
      await recordGuestGuideEvent({
        eventType,
        sectionKey: options.sectionKey || null,
        itemId: options.itemId || null,
        locale,
        metadata: options.metadata || {},
      })
    } catch (error) {
      console.error(`${eventType} analytics error:`, error)
    }
  }

  async function handleLocaleChange(nextLocale) {
    const { hotelSlug } = getGuestAccessContext('guest')
    setLocale(nextLocale)
    persistGuestLocale(hotelSlug, nextLocale)
    replaceGuestLocaleInUrl(nextLocale)
    setFeedbackSubmitted(false)
    await recordEvent('language_selected', { metadata: { selected_locale: nextLocale } })
  }

  async function createRequest(requestType) {
    if (!portal?.session || requestLoading) return
    const type = String(requestType || 'Service Request').trim()
    const duplicateRequest = requests.find(
      (request) => request.request_type === type && !['completed', 'cancelled'].includes(request.status)
    )

    if (duplicateRequest) {
      showToast(`${type}: ${copy.requestReceived}`)
      return
    }

    try {
      setRequestLoading(true)
      const accessStillValid = await fetchActivePortal()
      if (!accessStillValid) throw new Error(copy.accessUnavailable)
      await createGuestServiceRequest(type)
      await recordEvent(type === 'Checkout Request' ? 'checkout_clicked' : 'service_clicked', {
        metadata: { request_type: type },
      })
      showToast(`${type}: ${copy.requestReceived}`)
      await fetchMyRequests()
    } catch (error) {
      console.error('Create service request error:', error)
      await fetchActivePortal()
      showToast(error.message || copy.actionNotConfigured)
    } finally {
      setRequestLoading(false)
    }
  }

  async function cancelRequest(request) {
    if (!request?.id || requestLoading || request.can_cancel === false) return

    try {
      setRequestLoading(true)
      const accessStillValid = await fetchActivePortal()
      if (!accessStillValid) throw new Error(copy.accessUnavailable)
      await cancelGuestServiceRequest(
        request.id,
        'Cancelled by guest from the secure guide'
      )
      showToast(`${request.request_type || copy.requestService}: ${copy.cancelled}`)
      await fetchMyRequests()
    } catch (error) {
      console.error('Cancel service request error:', error)
      await fetchActivePortal()
      showToast(error.message || copy.actionNotConfigured)
    } finally {
      setRequestLoading(false)
    }
  }

  async function openFoodMenu() {
    const accessStillValid = await fetchActivePortal()
    const { hotelSlug, accessToken } = getGuestAccessContext('guest')
    if (!accessStillValid || !hotelSlug || !accessToken) {
      showToast(copy.accessUnavailable)
      return
    }
    await recordEvent('food_clicked')
    const foodPath = `/food/${encodeURIComponent(hotelSlug)}/${encodeURIComponent(accessToken)}`
    window.location.href = withGuestLocale(foodPath, locale)
  }

  function callPhone(value, eventType = 'call_clicked', metadata = {}) {
    const phone = normalizePhone(value)
    if (!phone) {
      showToast(copy.contactNotConfigured)
      return
    }
    void recordEvent(eventType, { metadata })
    window.location.href = `tel:${phone}`
  }

  function openWhatsApp(value, message = '') {
    const phone = normalizeWhatsApp(value)
    if (!phone) {
      showToast(copy.contactNotConfigured)
      return
    }
    void recordEvent('whatsapp_clicked', { metadata: { phone } })
    const suffix = message ? `?text=${encodeURIComponent(message)}` : ''
    window.open(`https://wa.me/${phone}${suffix}`, '_blank', 'noopener,noreferrer')
  }

  function openEmail(value) {
    const email = String(value || '').trim()
    if (!/^\S+@\S+\.\S+$/.test(email)) {
      showToast(copy.contactNotConfigured)
      return
    }
    void recordEvent('email_clicked', { metadata: { email } })
    window.location.href = `mailto:${email}`
  }

  function openExternalUrl(url, eventType, metadata = {}) {
    const value = String(url || '').trim()
    if (!/^https?:\/\//i.test(value)) {
      showToast(copy.linkNotConfigured)
      return
    }
    void recordEvent(eventType, { metadata })
    window.open(value, '_blank', 'noopener,noreferrer')
  }

  async function runItemAction(item) {
    const actionType = item.action_type || 'none'
    const actionValue = item.action_value || ''
    if (actionType === 'call') return callPhone(actionValue || displayInfo.reception_phone)
    if (actionType === 'whatsapp') {
      return openWhatsApp(
        actionValue || displayInfo.reception_phone,
        `${greetingText} ${displayInfo.hotel_name || hotel.hotel_name || 'Hotel'}, ${copy.room} ${room.room_number || ''}.`
      )
    }
    if (actionType === 'email') return openEmail(actionValue)
    if (actionType === 'url') return openExternalUrl(actionValue, 'social_clicked', { item_key: item.item_key })
    if (actionType === 'maps') return openExternalUrl(actionValue, 'local_convenience_clicked', { item_key: item.item_key })
    if (actionType === 'section') return scrollToSection(actionValue)
    if (actionType === 'food') return openFoodMenu()
    if (actionType === 'service') return createRequest(actionValue || item.title || 'Service Request')
    if (actionType === 'checkout') return createRequest(actionValue || 'Checkout Request')
    if (actionType === 'payment') {
      scrollToSection('payment')
      return recordEvent('payment_clicked', { itemId: item.id })
    }
    showToast(copy.actionNotConfigured)
  }

  async function runOfferAction() {
    if (offer.action_type === 'section') return scrollToSection(offer.action_value)
    if (offer.action_type === 'url') return openExternalUrl(offer.action_value, 'review_clicked', { source: 'hero_offer' })
    if (offer.action_type === 'whatsapp') return openWhatsApp(offer.action_value || displayInfo.reception_phone)
    if (offer.action_type === 'call') return callPhone(offer.action_value || displayInfo.reception_phone)
    if (offer.action_type === 'payment') return scrollToSection('payment')
    return scrollToSection('google_review')
  }

  async function copyToClipboard(value, message = copy.copied) {
    const text = String(value || '').trim()
    if (!text) {
      showToast(copy.actionNotConfigured)
      return
    }
    try {
      await navigator.clipboard.writeText(text)
    } catch {
      const textarea = document.createElement('textarea')
      textarea.value = text
      textarea.style.position = 'fixed'
      textarea.style.opacity = '0'
      document.body.appendChild(textarea)
      textarea.select()
      document.execCommand('copy')
      document.body.removeChild(textarea)
    }
    showToast(message)
  }

  async function copyWifiPassword() {
    await copyToClipboard(displayInfo.wifi_password, copy.passwordCopied)
    await recordEvent('wifi_copied')
  }

  async function openGoogleReview() {
    const reviewUrl = String(displayInfo.google_review_url || '').trim()
    if (!/^https?:\/\//i.test(reviewUrl)) {
      showToast(copy.reviewUnavailable)
      return
    }
    await recordEvent('review_clicked')
    window.open(reviewUrl, '_blank', 'noopener,noreferrer')
    try {
      await recordGuestReviewRewardAction('review_opened')
    } catch (error) {
      console.error('Review action audit error:', error)
    }
  }

  async function handleFeedbackSubmit(event) {
    event.preventDefault()
    if (feedbackSubmitting || feedbackSubmitted) return
    try {
      setFeedbackSubmitting(true)
      const accessStillValid = await fetchActivePortal()
      if (!accessStillValid) throw new Error(copy.accessUnavailable)
      await submitGuestFeedback({
        rating: feedbackRating,
        message: feedbackMessage,
        consentToFollowUp: feedbackConsent,
      })
      await recordEvent('feedback_submitted', {
        metadata: { rating: feedbackRating, consent_to_follow_up: feedbackConsent },
      })
      setFeedbackSubmitted(true)
      showToast(copy.feedbackSent)
    } catch (error) {
      console.error('Guest feedback submission error:', error)
      showToast(error.message || copy.actionNotConfigured)
    } finally {
      setFeedbackSubmitting(false)
    }
  }

  const requestStatusLabels = {
    pending: copy.requestReceived,
    accepted: copy.accepted,
    in_progress: copy.staffOnWay,
    completed: copy.completed,
    cancelled: copy.cancelled,
  }

  function instructionMediaFor(item) {
    const direct = allMedia.find((entry) => entry.item_id === item.id)
    if (direct) return direct
    const categoryMap = {
      air_conditioner: ['ac_remote', 'ac'],
      television_remote: ['tv_remote', 'tv'],
      hot_water_geyser: ['geyser'],
      bathtub_controls: ['bathtub', 'bathroom'],
      safe_locker: ['safe'],
    }
    const categories = categoryMap[item.item_key] || []
    return allMedia.find((entry) => categories.includes(entry.category)) || null
  }

  function renderCardItems(items, variant = '') {
    if (items.length === 0) return null
    return (
      <div className={`ag-card-grid ${variant}`.trim()}>
        {items.map((item) => (
          <article className="ag-info-card" key={item.id || item.item_key}>
            <span className="ag-icon"><GuideIcon name={item.icon || item.item_key} /></span>
            <div>
              <h3>{item.title}</h3>
              {item.description && <p>{item.description}</p>}
              {item.disclaimer && <small>{item.disclaimer}</small>}
              {item.action_type && item.action_type !== 'none' && (
                <button type="button" onClick={() => void runItemAction(item)}>
                  {item.button_label || copy.open}<span aria-hidden="true">→</span>
                </button>
              )}
            </div>
          </article>
        ))}
      </div>
    )
  }

  function Heading({ section }) {
    return (
      <header className="ag-section-head">
        {section.label && <p>{section.label}</p>}
        {section.title && <h2>{section.title}</h2>}
        {section.subtitle && <span>{section.subtitle}</span>}
      </header>
    )
  }

  function renderSection(section) {
    const items = itemsForSection(section)
    const sectionId = createSectionId(section.section_key)
    if (section.section_type === 'hero') return null

    if (section.section_type === 'stay') {
      const propertyMedia = allMedia.find((media) => media.category === 'property' && media.id !== heroMedia?.id)
      return (
        <section className="ag-section" id={sectionId} key={section.id}>
          <Heading section={section} />
          <div className="ag-glance-grid">
            {[
              ['bed', copy.roomNumber, room.room_number || '—'],
              ['sparkles', copy.roomType, room.room_type || copy.guestRoom],
              ['document', copy.checkIn, displayInfo.checkin_time || copy.askReception],
              ['checkout', copy.checkOut, displayInfo.checkout_time || copy.askReception],
              ['wifi', copy.wifi, displayInfo.wifi_name ? copy.available : copy.askReception],
              ['service', copy.reception, copy.available247],
            ].map(([icon, label, value]) => (
              <article key={label}>
                <span className="ag-icon"><GuideIcon name={icon} size={19} /></span>
                <small>{label}</small>
                <strong>{value}</strong>
              </article>
            ))}
          </div>
          {propertyMedia && (
            <button className="ag-feature-photo" type="button" onClick={() => setSelectedMedia(propertyMedia)}>
              <img src={getGuestGuideMediaUrl(propertyMedia.object_path)} alt={propertyMedia.alt_text || propertyMedia.title || hotelName} loading="lazy" />
              <span>{propertyMedia.caption || copy.stayqrTagline}</span>
            </button>
          )}
        </section>
      )
    }

    if (section.section_type === 'actions') {
      const actionItems = items.length > 0 ? items : DEFAULT_QUICK_ACTIONS.map((item) => ({ ...item, item_key: item.key }))
      return (
        <section className="ag-section" id={sectionId} key={section.id}>
          <Heading section={section} />
          <div className="ag-action-grid">
            {actionItems.map((item) => {
              const defaults = getFullItemCopy(item.item_key, locale)
              return (
                <button type="button" key={item.id || item.item_key} onClick={() => void runItemAction(item)} disabled={requestLoading}>
                  <span className="ag-icon"><GuideIcon name={item.icon || item.item_key} size={21} /></span>
                  <strong>{item.title || defaults.title || item.item_key}</strong>
                  <small>{item.description || item.subtitle || defaults.description || copy.open}</small>
                </button>
              )
            })}
          </div>
        </section>
      )
    }

    if (section.section_type === 'wifi') {
      return (
        <section className="ag-section" id={sectionId} key={section.id}>
          <Heading section={section} />
          <article className={`ag-wifi-card ${wifiMedia ? 'has-photo' : ''}`}>
            {wifiMedia && <img className="ag-wifi-photo" src={getGuestGuideMediaUrl(wifiMedia.object_path)} alt={wifiMedia.alt_text || wifiMedia.title || copy.wifi} loading="lazy" />}
            <div className="ag-wifi-icon"><GuideIcon name="wifi" size={28} /></div>
            <div className="ag-wifi-details">
              <small>{copy.network}</small>
              <strong>{displayInfo.wifi_name || copy.askReception}</strong>
              <small>{copy.password}</small>
              <strong>{displayInfo.wifi_password || copy.askReception}</strong>
            </div>
            <div className="ag-wifi-actions">
              <button type="button" onClick={() => void copyToClipboard(displayInfo.wifi_name, copy.networkCopied)}>{copy.copy}</button>
              <button type="button" onClick={() => void copyWifiPassword()}>{copy.copy}</button>
            </div>
          </article>
        </section>
      )
    }

    if (section.section_type === 'gallery') {
      const gallery = allMedia.filter((media) => ['room', 'bathroom', 'property', 'profile'].includes(media.category) && media.id !== heroMedia?.id)
      if (gallery.length === 0) return null
      return (
        <section className="ag-section" id={sectionId} key={section.id}>
          <Heading section={section} />
          <div className={`ag-gallery ${gallery.length === 1 ? 'single' : ''}`}>
            {gallery.map((media) => (
              <button type="button" key={media.id} onClick={() => { setSelectedMedia(media); void recordEvent('media_viewed', { metadata: { category: media.category, media_key: media.media_key } }) }}>
                <img src={getGuestGuideMediaUrl(media.object_path)} alt={media.alt_text || media.title || hotelName} loading="lazy" />
                {(media.title || media.caption) && <span><strong>{media.title}</strong><small>{media.caption}</small></span>}
              </button>
            ))}
          </div>
        </section>
      )
    }

    if (section.section_type === 'instructions') {
      const instructionItems = items.filter((item) => item.item_type === 'instruction' || Array.isArray(item.instructions))
      if (instructionItems.length === 0) return null
      return (
        <section className="ag-section" id={sectionId} key={section.id}>
          <Heading section={section} />
          <div className="ag-accordion">
            {instructionItems.map((item) => {
              const isOpen = expandedInstructionId === item.id
              const media = instructionMediaFor(item)
              return (
                <article className={isOpen ? 'open' : ''} key={item.id || item.item_key}>
                  <button type="button" className="ag-accordion-trigger" onClick={() => setExpandedInstructionId(isOpen ? '' : item.id)} aria-expanded={isOpen}>
                    <span className="ag-icon"><GuideIcon name={item.icon || item.item_key} size={20} /></span>
                    <span><strong>{item.title}</strong><small>{item.description}</small></span>
                    <b>{isOpen ? '−' : '+'}</b>
                  </button>
                  {isOpen && (
                    <div className="ag-accordion-body">
                      {media && <img src={getGuestGuideMediaUrl(media.object_path)} alt={media.alt_text || item.title} loading="lazy" />}
                      {Array.isArray(item.instructions) && item.instructions.length > 0 ? (
                        <ol>{item.instructions.map((step, index) => <li key={`${item.id}-${index}`}><span>{index + 1}</span><p>{String(step)}</p></li>)}</ol>
                      ) : item.description ? <p>{item.description}</p> : null}
                    </div>
                  )}
                </article>
              )
            })}
          </div>
        </section>
      )
    }

    if (section.section_type === 'facilities') {
      const amenities = Array.isArray(guestContent.amenities) ? guestContent.amenities : []
      if (items.length === 0 && amenities.length === 0) return null
      return (
        <section className="ag-section" id={sectionId} key={section.id}>
          <Heading section={section} />
          {renderCardItems(items)}
          {amenities.length > 0 && (
            <div className="ag-card-grid">
              {amenities.map((amenity) => (
                <article className="ag-info-card" key={amenity.id || amenity.name}>
                  <span className="ag-icon"><GuideIcon name={amenity.icon || amenity.name} /></span>
                  <div><h3>{amenity.name}</h3><p>{amenity.description || amenity.instructions || copy.available}</p></div>
                </article>
              ))}
            </div>
          )}
        </section>
      )
    }

    if (section.section_type === 'dining') {
      return (
        <section className="ag-section" id={sectionId} key={section.id}>
          <Heading section={section} />
          {renderCardItems(items)}
          <button type="button" className="ag-wide-cta" onClick={() => void openFoodMenu()}><GuideIcon name="food" size={19} />{copy.viewMenuOrder}</button>
        </section>
      )
    }

    if (section.section_type === 'services') {
      const serviceItems = items.filter((item) => item.action_type === 'service')
      const fallbackRequests = serviceCatalog.length > 0
        ? serviceCatalog.map((service) => [
            service.code || service.name,
            service.name,
            getRequestIcon(service.code || service.name),
          ])
        : [
            ['Housekeeping', copy.housekeeping, 'housekeeping'],
            ['Water', copy.drinkingWater, 'water'],
            ['Towel', copy.freshTowels, 'towels'],
            ['Toiletries', copy.toiletries, 'sparkles'],
          ]
      return (
        <section className="ag-section" id={sectionId} key={section.id}>
          <Heading section={section} />
          {serviceItems.length > 0 ? renderCardItems(serviceItems) : (
            <div className="ag-action-grid compact">
              {fallbackRequests.map(([requestType, label, icon]) => (
                <button type="button" key={requestType} onClick={() => void createRequest(requestType)} disabled={requestLoading}>
                  <span className="ag-icon"><GuideIcon name={icon} size={20} /></span><strong>{label}</strong><small>{copy.requestNow}</small>
                </button>
              ))}
            </div>
          )}
          {requests.length > 0 && (
            <div className="ag-request-list">
              <h3>{copy.myRequests}</h3>
              {requests.slice(0, 6).map((request) => (
                <article key={request.id}>
                  <span className="ag-icon">
                    <GuideIcon name={getRequestIcon(request.request_type)} size={18} />
                  </span>
                  <div className="ag-request-summary">
                    <strong>{request.request_type}</strong>
                    <small>{requestStatusLabels[request.status] || request.status}</small>
                  </div>
                  {request.can_cancel !== false
                    && ['pending', 'accepted'].includes(request.status) && (
                    <button
                      type="button"
                      className="ag-request-cancel"
                      onClick={() => void cancelRequest(request)}
                      disabled={requestLoading}
                    >
                      {copy.cancelled}
                    </button>
                  )}
                </article>
              ))}
            </div>
          )}
        </section>
      )
    }

    if (section.section_type === 'safety') {
      return (
        <section className="ag-section" id={sectionId} key={section.id}>
          <Heading section={section} />
          {renderCardItems(items)}
          <article className="ag-emergency"><span className="ag-icon"><GuideIcon name="shield" size={24} /></span><div><small>{copy.emergencyContact}</small><strong>{displayInfo.emergency_phone || displayInfo.reception_phone || copy.askReception}</strong><p>{copy.urgentHelp}</p></div><button type="button" onClick={() => callPhone(displayInfo.emergency_phone || displayInfo.reception_phone)}>{copy.callNow}</button></article>
        </section>
      )
    }

    if (section.section_type === 'contacts' || section.section_type === 'social') {
      if (items.length === 0) return null
      return <section className="ag-section" id={sectionId} key={section.id}><Heading section={section} />{renderCardItems(items, section.section_type)}</section>
    }

    if (section.section_type === 'local') {
      if (items.length === 0) return null
      return <section className="ag-section" id={sectionId} key={section.id}><Heading section={section} />{renderCardItems(items, 'local')}<p className="ag-disclaimer">{copy.localDisclaimer}</p></section>
    }

    if (section.section_type === 'payment') {
      const payment = premiumGuide.payment_profile || {}
      const balance = Number(portal?.folio?.balance_amount || 0)
      const paymentQr = mediaById.get(payment.qr_media_id) || allMedia.find((media) => media.category === 'payment_qr')
      if (!payment.is_enabled && balance <= 0) return null
      const amount = payment.show_outstanding_balance !== false && balance > 0 ? balance.toFixed(2) : ''
      const upiLink = payment.upi_id
        ? `upi://pay?pa=${encodeURIComponent(payment.upi_id)}&pn=${encodeURIComponent(payment.payee_name || hotelName)}${amount ? `&am=${encodeURIComponent(amount)}` : ''}&cu=${encodeURIComponent(portal?.folio?.currency_code || hotel.currency_code || 'INR')}`
        : ''
      return (
        <section className="ag-section" id={sectionId} key={section.id}>
          <Heading section={section} />
          <article className="ag-payment-card">
            {paymentQr && <img src={getGuestGuideMediaUrl(paymentQr.object_path)} alt={paymentQr.alt_text || 'UPI QR'} loading="lazy" />}
            <div className="ag-payment-details">
              {payment.show_outstanding_balance !== false && balance > 0 && <div className="ag-balance"><small>{copy.outstandingBalance}</small><strong>{formatMoney(balance, portal?.folio?.currency_code || hotel.currency_code || 'INR')}</strong></div>}
              {payment.payee_name && <p><b>{copy.payee}:</b> {payment.payee_name}</p>}
              {payment.upi_id && <div className="ag-upi-row"><p><b>{copy.upiId}:</b> {payment.upi_id}</p><button type="button" onClick={() => void copyToClipboard(payment.upi_id, copy.copied)}>{copy.copy}</button></div>}
              {payment.instructions && <p>{payment.instructions}</p>}
              {upiLink ? <a className="ag-pay-button" href={upiLink} onClick={() => void recordEvent('payment_clicked')}>{copy.payThroughUpi}</a> : <button className="ag-pay-button disabled" type="button" onClick={() => showToast(copy.invalidUpi)}>{copy.payThroughUpi}</button>}
              <small className="ag-desktop-hint">{copy.desktopUpiHint}</small>
            </div>
          </article>
          {payment.require_reception_confirmation !== false && <p className="ag-payment-note">{copy.paymentConfirm} {copy.paymentManualNote}</p>}
        </section>
      )
    }

    if (section.section_type === 'feedback') {
      return (
        <section className="ag-section" id={sectionId} key={section.id}>
          <Heading section={section} />
          {feedbackSubmitted ? <article className="ag-feedback-success"><span>✓</span><div><h3>{copy.feedbackThanks}</h3><p>{copy.feedbackSent}</p></div></article> : (
            <form className="ag-feedback-form" onSubmit={handleFeedbackSubmit}>
              <fieldset><legend>{copy.rateStay}</legend><div>{[1,2,3,4,5].map((rating) => <button type="button" key={rating} className={feedbackRating >= rating ? 'active' : ''} onClick={() => setFeedbackRating(rating)} aria-label={`${rating} stars`}>★</button>)}</div></fieldset>
              <label>{copy.messageHotel}<textarea value={feedbackMessage} onChange={(event) => setFeedbackMessage(event.target.value)} maxLength={4000} placeholder={copy.feedbackPlaceholder} /></label>
              <label className="ag-consent"><input type="checkbox" checked={feedbackConsent} onChange={(event) => setFeedbackConsent(event.target.checked)} />{copy.consent}</label>
              <button type="submit" disabled={feedbackSubmitting}>{feedbackSubmitting ? copy.sending : copy.sendFeedback}</button>
            </form>
          )}
        </section>
      )
    }

    if (section.section_type === 'review') {
      return (
        <section className="ag-section" id={sectionId} key={section.id}>
          <Heading section={section} />
          <article className="ag-review-card"><span className="ag-icon"><GuideIcon name="star" size={24} /></span><div><span className="ag-offer-label">{copy.offerBadge}</span><h3>{displayInfo.reward_title || copy.offerDefaultTitle}</h3><p>{displayInfo.reward_description || copy.offerDefaultBody}</p><button type="button" onClick={() => void openGoogleReview()} disabled={!displayInfo.google_review_url}>{displayInfo.google_review_url ? copy.leaveReview : copy.reviewUnavailable}</button></div></article>
        </section>
      )
    }

    if (section.section_type === 'policies') {
      if (items.length === 0 && !displayInfo.hotel_rules) return null
      return (
        <section className="ag-section" id={sectionId} key={section.id}>
          <Heading section={section} />
          {displayInfo.hotel_rules && <article className="ag-policy"><span className="ag-icon"><GuideIcon name="document" size={21} /></span><div><h3>{copy.importantGuidelines}</h3><p>{displayInfo.hotel_rules}</p></div></article>}
          {renderCardItems(items)}
        </section>
      )
    }

    if (section.section_type === 'closing') {
      return (
        <section className="ag-thankyou" id={sectionId} key={section.id}>
          <p>{section.label}</p><h2>{section.title || copy.thankYou}</h2><span>{section.subtitle || displayInfo.footer_message || copy.thankYouBody}</span>
          <div><button type="button" onClick={() => callPhone(displayInfo.reception_phone)}><GuideIcon name="phone" size={18} />{copy.callReception}</button><button type="button" className="outline" onClick={() => openWhatsApp(displayInfo.reception_phone)}><GuideIcon name="whatsapp" size={18} />{copy.whatsapp}</button></div>
          <article className="ag-stayqr-signature"><img src="/assets/stayqr-official-logo.png" alt="StayQR — Simplifying check-in" /><div><p>{copy.poweredBy}</p><span>{copy.stayqrTagline}</span></div></article>
        </section>
      )
    }

    if (items.length === 0) return null
    return <section className="ag-section" id={sectionId} key={section.id}><Heading section={section} />{renderCardItems(items)}</section>
  }

  if (loading) {
    return <main className="ag-state-page"><div className="ag-state-mark">S</div><p>{copy.loading}</p></main>
  }

  if (!portal?.session) {
    const inactiveCopy = getGuideCopy('en')
    return <main className="ag-state-page inactive"><article><p>{inactiveCopy.accessLabel}</p><h1>{inactiveCopy.accessUnavailable}</h1><span>{inactiveCopy.accessUnavailableBody}</span></article></main>
  }

  const hotelName = displayInfo.hotel_name || hotel.hotel_name || 'StayQR Hotel'
  const guestName = String(guest.full_name || '').trim() || copy.guest
  const receptionPhone = displayInfo.reception_phone || ''
  const whatsappItem = allItems.find((item) => item.action_type === 'whatsapp')
  const mapsItem = allItems.find((item) => item.action_type === 'maps' && item.item_type !== 'local_convenience')
  const heroEyebrow = legacyTranslation.welcome_kicker || displayInfo.welcome_kicker || copy.digitalGuide
  const heroMessage = legacyTranslation.welcome_message || displayInfo.welcome_message || copy.offerDefaultBody
  const rawHeroTitle = legacyTranslation.welcome_title || displayInfo.welcome_title || hotelName
  const heroTitle = String(rawHeroTitle).replace(/^welcome\s+to\s+/i, '').trim() || hotelName

  return (
    <main className="ag-page" style={pageStyle}>
      <div className="ag-progress" style={{ width: `${scrollProgress}%` }} />
      <header className="ag-topbar"><div className="ag-topbar-inner"><div className="ag-brand">{logoMedia ? <img src={getGuestGuideMediaUrl(logoMedia.object_path)} alt={`${hotelName} logo`} /> : <span>{hotelName.charAt(0).toUpperCase()}</span>}<div><strong>{hotelName}</strong><small>{displayInfo.address || hotel.location || copy.digitalGuide}</small></div></div><div className="ag-top-actions">{enabledLocales.length > 1 && <select aria-label="Guest guide language" value={locale} onChange={(event) => void handleLocaleChange(event.target.value)}>{enabledLocales.map((code) => <option key={code} value={code}>{getLocaleLabel(code)}</option>)}</select>}<span>{copy.room} {room.room_number || '—'}</span></div></div></header>

      <section className="ag-hero" style={heroImageUrl ? { backgroundImage: `url(${heroImageUrl})` } : undefined}>
        <div className="ag-hero-overlay" /><div className="ag-hero-glow" />
        <div className="ag-hero-content">
          <div className="ag-hero-brand"><img src="/assets/stayqr-official-logo.png" alt="StayQR" /><span>{copy.digitalGuide}</span></div>
          <p className="ag-eyebrow">{heroEyebrow}</p>
          <h1><span>{copy.welcomeTo}</span><strong>{heroTitle}</strong></h1>
          <div className="ag-room-chip"><small>{copy.yourRoom}</small><b>{room.room_number || '—'}</b><span>{room.room_type || copy.guestRoom}</span></div>
          <p className="ag-hero-message">{heroMessage}</p>
          <p className="ag-personal-greeting">{greetingText}{copy.greetingNameSeparator} <strong>{guestName}</strong></p>
          <div className="ag-hero-actions"><button type="button" onClick={() => callPhone(receptionPhone)}><GuideIcon name="phone" size={18} />{copy.callReception}</button><button type="button" className="outline" onClick={() => openWhatsApp(whatsappItem?.action_value || receptionPhone, `${greetingText} ${hotelName}, ${copy.room} ${room.room_number || ''}.`)}><GuideIcon name="whatsapp" size={18} />{copy.whatsapp}</button>{mapsItem && <button type="button" className="outline" onClick={() => void runItemAction(mapsItem)}><GuideIcon name="map" size={18} />{copy.location}</button>}</div>
          <small className="ag-access">{copy.secureAccessUntil} {formatDateTime(session.extended_until || session.checkout_time)}</small>
        </div>
        <div className="ag-scroll-cue"><span /></div>
      </section>

      {offer.enabled && <section className="ag-offer-band"><article>{offerMedia && <img src={getGuestGuideMediaUrl(offerMedia.object_path)} alt={offerMedia.alt_text || offer.title} />}<div><span>{offer.badge}</span><h2>{offer.title}</h2><p>{offer.description}</p></div><button type="button" onClick={() => void runOfferAction()}>{offer.button_label}<b>→</b></button></article></section>}

      <div className="ag-content">{sections.map((section) => renderSection(section))}</div>

      <footer className="ag-footer"><div className="ag-footer-brand"><img src="/assets/stayqr-official-logo.png" alt="StayQR — Simplifying check-in" /><div><span>{copy.poweredBy}</span><p>{copy.stayqrTagline}</p></div></div><small>{hotelName}</small></footer>

      <nav className="ag-sticky" aria-label="Guest quick actions"><button type="button" onClick={() => callPhone(receptionPhone)}><GuideIcon name="phone" size={18} /><span>{copy.call}</span></button><button type="button" onClick={() => openWhatsApp(whatsappItem?.action_value || receptionPhone)}><GuideIcon name="whatsapp" size={18} /><span>{copy.whatsapp}</span></button><button type="button" onClick={() => scrollToSection('wifi')}><GuideIcon name="wifi" size={18} /><span>{copy.wifi}</span></button><button type="button" onClick={() => scrollToSection('guest_services')}><GuideIcon name="service" size={18} /><span>{copy.services}</span></button></nav>

      {selectedMedia && <div className="ag-lightbox" role="dialog" aria-modal="true" aria-label="Image preview"><button type="button" onClick={() => setSelectedMedia(null)} aria-label="Close image preview">×</button><img src={getGuestGuideMediaUrl(selectedMedia.object_path)} alt={selectedMedia.alt_text || selectedMedia.title || hotelName} />{(selectedMedia.title || selectedMedia.caption) && <div><strong>{selectedMedia.title}</strong><p>{selectedMedia.caption}</p></div>}</div>}
      {toast && <div className="ag-toast" role="status">✓ {toast}</div>}
    </main>
  )
}
