import { supabase } from './supabase'

const RELEASE =
  import.meta.env.VITE_APP_RELEASE ||
  import.meta.env.VITE_COMMIT_REF ||
  'unversioned'

const ENVIRONMENT =
  import.meta.env.VITE_APP_ENV ||
  import.meta.env.MODE ||
  'development'

const recentFingerprints = new Map()
const monitoringContext = {
  hotelId: null,
  userId: null,
  role: null,
}

let monitoringInstalled = false

function safeRoute() {
  const pathname = window.location.pathname

  if (pathname.startsWith('/guest/')) return '/guest/:token'
  if (pathname.startsWith('/food/')) return '/food/:token'
  if (pathname.startsWith('/invoice/verify/')) return '/invoice/verify/:token'
  if (pathname.startsWith('/auth/')) return pathname.slice(0, 160)

  return pathname.slice(0, 160) || '/app'
}

function sanitizeText(value, maxLength = 500) {
  let text = String(value || '')

  text = text
    .replace(/bearer\s+[a-z0-9._~+/-]+/gi, 'Bearer [REDACTED]')
    .replace(
      /[a-z0-9_-]{20,}\.[a-z0-9_-]{20,}\.[a-z0-9_-]{10,}/gi,
      '[REDACTED_JWT]'
    )
    .replace(/\/(?:guest|food)\/[a-z0-9_-]{8,}/gi, (match) =>
      match.toLowerCase().startsWith('/food/')
        ? '/food/:token'
        : '/guest/:token'
    )
    .replace(
      /\/invoice\/verify\/[a-z0-9_-]{8,}/gi,
      '/invoice/verify/:token'
    )
    .replace(
      /[a-z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-z0-9.-]+\.[a-z]{2,}/gi,
      '[REDACTED_EMAIL]'
    )
    .replace(/(?:\+?\d[\s().-]*){10,15}/g, '[REDACTED_PHONE]')
    .replace(
      /(anon[_-]?key|service[_-]?role|api[_-]?key|password|secret)\s*[:=]\s*[^,\s;]+/gi,
      '$1=[REDACTED]'
    )

  return text.slice(0, Math.max(1, Math.min(maxLength, 4000)))
}

function stackFrameCount(error) {
  if (!error?.stack) return 0

  return String(error.stack)
    .split('\n')
    .filter(Boolean)
    .slice(0, 200)
    .length
}

function createIncidentId(scope = 'client') {
  const safeScope = String(scope)
    .replace(/[^a-z0-9:_-]/gi, '-')
    .slice(0, 36)

  return `d18-${safeScope || 'client'}-${Date.now().toString(36)}-${Math.random()
    .toString(36)
    .slice(2, 8)}`
}

function createRequestId() {
  if (globalThis.crypto?.randomUUID) {
    return globalThis.crypto.randomUUID()
  }

  return `req-${Date.now().toString(36)}-${Math.random()
    .toString(36)
    .slice(2, 10)}`
}

function normalizeError(error, fallbackMessage) {
  if (error instanceof Error) {
    return {
      errorName: sanitizeText(error.name || 'Error', 80),
      message: sanitizeText(error.message || fallbackMessage || 'Unknown error'),
      stackFrames: stackFrameCount(error),
    }
  }

  if (typeof error === 'string') {
    return {
      errorName: 'Error',
      message: sanitizeText(error || fallbackMessage || 'Unknown error'),
      stackFrames: 0,
    }
  }

  return {
    errorName: sanitizeText(error?.name || 'Error', 80),
    message: sanitizeText(
      error?.message || fallbackMessage || 'Unknown operational error'
    ),
    stackFrames: 0,
  }
}

function buildPayload(input = {}) {
  const normalized = normalizeError(input.error, input.message)
  const scope = sanitizeText(input.scope || 'application', 100)
  const route = sanitizeText(input.route || safeRoute(), 200)

  return {
    source: 'client',
    environment: ENVIRONMENT,
    severity: ['info', 'warning', 'error', 'critical'].includes(input.severity)
      ? input.severity
      : 'error',
    event_name: sanitizeText(input.eventName || 'client.error', 100),
    error_name: sanitizeText(input.errorName || normalized.errorName, 100),
    error_code: sanitizeText(input.errorCode || '', 100) || null,
    message: sanitizeText(input.message || normalized.message, 1000),
    route,
    scope,
    component: sanitizeText(input.component || '', 120) || null,
    incident_id: sanitizeText(
      input.incidentId || createIncidentId(scope),
      96
    ),
    request_id: sanitizeText(input.requestId || createRequestId(), 96),
    release: sanitizeText(RELEASE, 96),
    context: {
      online: navigator.onLine,
      visibility_state: document.visibilityState,
      viewport: `${window.innerWidth}x${window.innerHeight}`,
      stack_frames: Number.isFinite(input.stackFrames)
        ? input.stackFrames
        : normalized.stackFrames,
      network_type: sanitizeText(
        navigator.connection?.effectiveType || '',
        32
      ) || null,
      retryable: Boolean(input.retryable),
    },
  }
}

async function resolveHotelId() {
  if (monitoringContext.hotelId) return monitoringContext.hotelId

  const {
    data: { session },
  } = await supabase.auth.getSession()

  const userId = monitoringContext.userId || session?.user?.id
  if (!userId) return null

  return window.localStorage.getItem(`stayqr:selected-hotel-id:${userId}`)
}

function fingerprintFor(payload) {
  return [
    payload.environment,
    payload.event_name,
    payload.error_name,
    payload.error_code || '',
    payload.route,
    payload.scope,
    payload.component || '',
    payload.message.slice(0, 180),
  ].join('|')
}

export function setMonitoringContext({
  hotelId = null,
  userId = null,
  role = null,
} = {}) {
  monitoringContext.hotelId = hotelId || null
  monitoringContext.userId = userId || null
  monitoringContext.role = role || null
}

export async function reportOperationalError(input = {}) {
  const payload = buildPayload(input)
  const fingerprint = fingerprintFor(payload)
  const now = Date.now()
  const previous = recentFingerprints.get(fingerprint)

  console.error('[StayQR operational]', {
    ...payload,
    actor_role: monitoringContext.role,
  })

  if (previous && now - previous < 5000) {
    return {
      recorded: false,
      deduplicated_locally: true,
      incident_id: payload.incident_id,
    }
  }

  recentFingerprints.set(fingerprint, now)

  if (!navigator.onLine) {
    return {
      recorded: false,
      offline: true,
      incident_id: payload.incident_id,
    }
  }

  try {
    const hotelId = await resolveHotelId()

    if (!hotelId) {
      return {
        recorded: false,
        missing_hotel_context: true,
        incident_id: payload.incident_id,
      }
    }

    const { data, error } = await supabase.rpc('report_operational_error', {
      p_hotel_id: hotelId,
      p_payload: payload,
    })

    if (error) {
      console.warn('[StayQR monitoring transport]', {
        code: error.code || 'UNKNOWN',
        incident_id: payload.incident_id,
      })

      return {
        recorded: false,
        transport_error: true,
        incident_id: payload.incident_id,
      }
    }

    return {
      recorded: true,
      ...data,
    }
  } catch (transportError) {
    console.warn('[StayQR monitoring transport]', {
      error_name: transportError?.name || 'Error',
      incident_id: payload.incident_id,
    })

    return {
      recorded: false,
      transport_error: true,
      incident_id: payload.incident_id,
    }
  }
}

export function installOperationalMonitoring() {
  if (monitoringInstalled) return
  monitoringInstalled = true

  window.addEventListener('error', (event) => {
    void reportOperationalError({
      error: event.error,
      message: event.message,
      eventName: 'window.error',
      scope: 'window',
      component: event.filename ? 'browser-runtime' : 'application',
      severity: 'error',
    })
  })

  window.addEventListener('unhandledrejection', (event) => {
    void reportOperationalError({
      error: event.reason,
      message: 'Unhandled promise rejection',
      eventName: 'window.unhandledrejection',
      scope: 'promise',
      component: 'browser-runtime',
      severity: 'error',
      retryable: true,
    })
  })

  window.addEventListener('stayqr:client-error', (event) => {
    const detail = event.detail || {}

    void reportOperationalError({
      message: detail.message || 'React error boundary contained a failure.',
      errorName: detail.errorName || 'Error',
      eventName: 'react.error_boundary',
      incidentId: detail.incidentId,
      route: detail.route,
      scope: detail.scope,
      component: detail.component || 'AppErrorBoundary',
      stackFrames: detail.stackFrames,
      severity: 'error',
      retryable: true,
    })
  })
}

export async function getOperationalDiagnostics(hotelId, filters = {}) {
  const { data, error } = await supabase.rpc('get_operational_diagnostics', {
    p_hotel_id: hotelId,
    p_from: filters.from || null,
    p_to: filters.to || null,
    p_limit: filters.limit || 50,
    p_status: filters.status || null,
    p_severity: filters.severity || null,
    p_source: filters.source || null,
    p_search: filters.search || null,
  })

  if (error) throw error

  return data || {
    health_status: 'unknown',
    summary: {},
    items: [],
    query_health: {},
    delivery_health: {},
  }
}

export async function setOperationalIncidentStatus(
  hotelId,
  eventId,
  status,
  note = null
) {
  const { data, error } = await supabase.rpc(
    'set_operational_incident_status',
    {
      p_hotel_id: hotelId,
      p_event_id: eventId,
      p_status: status,
      p_note: note,
    }
  )

  if (error) throw error
  return data
}
