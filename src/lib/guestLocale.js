const ALLOWED_LOCALES = new Set([
  'en', 'hi', 'mr', 'ta', 'te', 'bn',
  'gu', 'kn', 'ml', 'pa', 'or', 'as',
])

function cleanLocale(value) {
  const locale = String(value || '').trim().toLowerCase()
  return ALLOWED_LOCALES.has(locale) ? locale : ''
}

export function getGuestLocaleStorageKey(hotelSlug = '') {
  const slug = String(hotelSlug || '').trim().toLowerCase() || 'stayqr'
  return `stayqr:guest-locale:${slug}`
}

export function persistGuestLocale(hotelSlug, locale) {
  const safeLocale = cleanLocale(locale)
  if (!safeLocale || typeof window === 'undefined') return safeLocale
  try {
    window.localStorage.setItem(getGuestLocaleStorageKey(hotelSlug), safeLocale)
  } catch {
    // Locale persistence is a convenience only; signed access remains primary.
  }
  return safeLocale
}

export function readPreferredGuestLocale({
  hotelSlug = '',
  enabledLocales = ['en'],
  defaultLocale = 'en',
  currentLocale = '',
} = {}) {
  const enabled = new Set(
    (Array.isArray(enabledLocales) ? enabledLocales : ['en'])
      .map(cleanLocale)
      .filter(Boolean)
  )
  const fallback = enabled.has(cleanLocale(defaultLocale))
    ? cleanLocale(defaultLocale)
    : enabled.values().next().value || 'en'

  if (typeof window === 'undefined') return fallback

  const fromQuery = cleanLocale(new URLSearchParams(window.location.search).get('lang'))
  if (fromQuery && enabled.has(fromQuery)) return fromQuery

  const current = cleanLocale(currentLocale)
  if (current && enabled.has(current)) return current

  try {
    const stored = cleanLocale(
      window.localStorage.getItem(getGuestLocaleStorageKey(hotelSlug))
    )
    if (stored && enabled.has(stored)) return stored
  } catch {
    // Ignore storage restrictions such as private-browser policies.
  }

  const browserLocale = cleanLocale(
    String(window.navigator?.language || '').split('-')[0]
  )
  return browserLocale && enabled.has(browserLocale) ? browserLocale : fallback
}

export function withGuestLocale(path, locale) {
  const safeLocale = cleanLocale(locale)
  if (!safeLocale) return path
  const url = new URL(path, window.location.origin)
  url.searchParams.set('lang', safeLocale)
  return `${url.pathname}${url.search}${url.hash}`
}

export function replaceGuestLocaleInUrl(locale) {
  if (typeof window === 'undefined') return
  const safeLocale = cleanLocale(locale)
  if (!safeLocale) return
  const url = new URL(window.location.href)
  url.searchParams.set('lang', safeLocale)
  window.history.replaceState({}, '', `${url.pathname}${url.search}${url.hash}`)
}
