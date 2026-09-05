const SOURCE_DESTINATIONS = [
  { match: ['reservation'], section: 'reservations', detailKey: 'reservationId' },
  { match: ['payment'], section: 'payments' },
  { match: ['invoice'], section: 'invoices' },
  { match: ['service_request', 'service'], section: 'services' },
  { match: ['food_order', 'food'], section: 'foodorders' },
  { match: ['housekeeping'], section: 'housekeeping' },
  { match: ['maintenance'], section: 'maintenance' },
  { match: ['room'], section: 'rooms' },
  { match: ['checkout', 'checkin', 'guest'], section: 'guests', detailKey: 'guestSessionId' },
  { match: ['support'], section: 'operationscenter', detail: { initialTab: 'support' } },
]

export function getNotificationCategory(notificationOrType) {
  const raw = typeof notificationOrType === 'string'
    ? notificationOrType
    : `${notificationOrType?.source_type || ''} ${notificationOrType?.event_key || ''}`
  const value = String(raw || '').toLowerCase()

  if (value.includes('payment')) return 'payment'
  if (value.includes('food')) return 'food'
  if (value.includes('service')) return 'service'
  if (value.includes('housekeeping')) return 'housekeeping'
  if (value.includes('maintenance')) return 'maintenance'
  if (value.includes('reservation')) return 'reservation'
  if (value.includes('checkout') || value.includes('checkin') || value.includes('guest')) return 'guest'
  if (value.includes('invoice')) return 'invoice'
  if (value.includes('room')) return 'room'
  if (value.includes('support')) return 'support'
  return 'general'
}

export function getNotificationTone(notification) {
  const severity = String(notification?.severity || '').toLowerCase()
  const eventKey = String(notification?.event_key || '').toLowerCase()

  if (severity === 'critical' || severity === 'error') return 'critical'
  if (severity === 'warning' || severity === 'warn') return 'warning'
  if (
    severity === 'success' ||
    eventKey.includes('completed') ||
    eventKey.includes('paid') ||
    eventKey.includes('checked_out') ||
    eventKey.includes('resolved')
  ) return 'success'
  return 'info'
}

export function getNotificationDestination(notification) {
  const sourceType = String(notification?.source_type || '').toLowerCase()
  const eventKey = String(notification?.event_key || '').toLowerCase()
  const haystack = `${sourceType} ${eventKey}`
  const metadata = notification?.metadata && typeof notification.metadata === 'object'
    ? notification.metadata
    : {}

  const rule = SOURCE_DESTINATIONS.find((item) => item.match.some((token) => haystack.includes(token)))
  if (!rule) return { section: 'operationscenter', detail: { initialTab: 'notifications' } }

  const detail = { ...(rule.detail || {}) }
  if (rule.detailKey) {
    const value = rule.detailKey === 'guestSessionId'
      ? metadata.guest_session_id || metadata.guestSessionId || notification?.source_id
      : notification?.source_id
    if (value) detail[rule.detailKey] = value
  }

  return { section: rule.section, detail }
}

export function getNotificationCategoryLabel(notification) {
  const category = getNotificationCategory(notification)
  const labels = {
    payment: 'Payment',
    food: 'Food order',
    service: 'Service request',
    housekeeping: 'Housekeeping',
    maintenance: 'Maintenance',
    reservation: 'Reservation',
    guest: 'Guest stay',
    invoice: 'Invoice',
    room: 'Room',
    support: 'Support',
    general: 'Hotel activity',
  }
  return labels[category] || labels.general
}

export function timeAgo(dateValue) {
  if (!dateValue) return ''

  const timestamp = new Date(dateValue).getTime()
  if (!Number.isFinite(timestamp)) return ''

  const diffMs = Math.max(0, Date.now() - timestamp)
  const diffSec = Math.floor(diffMs / 1000)
  const diffMin = Math.floor(diffSec / 60)
  const diffHr = Math.floor(diffMin / 60)
  const diffDay = Math.floor(diffHr / 24)

  if (diffSec < 30) return 'Just now'
  if (diffMin < 1) return `${diffSec}s ago`
  if (diffMin < 60) return `${diffMin}m ago`
  if (diffHr < 24) return `${diffHr}h ago`
  if (diffDay < 7) return `${diffDay}d ago`

  return new Date(timestamp).toLocaleDateString('en-IN', {
    day: 'numeric',
    month: 'short',
  })
}
