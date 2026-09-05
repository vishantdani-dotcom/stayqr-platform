import { createClient } from 'npm:@supabase/supabase-js@2.106.2'

const MAX_IMAGE_BYTES = 5 * 1024 * 1024
const PROVIDER_TIMEOUT_MS = 10000
const SUPPORTED_MIME_TYPES = new Set(['image/jpeg', 'image/png'])

const AADHAAR_REGEX = /\b(\d{4})[\s.-]{0,3}(\d{4})[\s.-]{0,3}(\d{4})\b/g
const DATE_REGEX = /\b([0-3]?\d)\s*[/.-]\s*([01]?\d)\s*[/.-]\s*((?:19|20)\d{2})\b/
const PAN_REGEX = /\b[A-Z]{5}\d{4}[A-Z]\b/i
const PASSPORT_REGEX = /\b[A-Z][0-9]{7}\b/i
const VOTER_REGEX = /\b[A-Z]{3}\d{7}\b/i
const DL_REGEX = /\b[A-Z]{2}[\s-]?\d{2}[\s-]?\d{4}[\s-]?\d{7}\b/i

function configuredOrigins() {
  const values = [Deno.env.get('STAYQR_APP_URL'), Deno.env.get('STAYQR_APP_URLS')]
    .filter(Boolean)
    .flatMap((value) => String(value).split(','))
    .map((value) => value.trim())
    .filter(Boolean)
  return new Set(values.map((value) => {
    try { return new URL(value).origin } catch { return value.replace(/\/$/, '') }
  }))
}

function previewOriginSuffixes() {
  return new Set(
    String(Deno.env.get('STAYQR_PREVIEW_ORIGIN_SUFFIXES') || '')
      .split(',')
      .map((value) => value.trim().toLowerCase())
      .filter(Boolean)
  )
}

function isAllowedOrigin(origin: string, configured: Set<string>) {
  if (configured.has(origin)) return true
  if (!origin) return false
  try {
    const url = new URL(origin)
    if (url.protocol !== 'https:') return false
    const hostname = url.hostname.toLowerCase()
    for (const suffix of previewOriginSuffixes()) {
      if (hostname === suffix || hostname.endsWith(`--${suffix}`)) return true
    }
  } catch {
    return false
  }
  return false
}

function cors(request: Request) {
  const origin = request.headers.get('Origin') || ''
  const configured = configuredOrigins()
  const allowed = isAllowedOrigin(origin, configured)
  const fallback = [...configured][0] || 'null'
  return {
    'Access-Control-Allow-Origin': allowed ? origin : fallback,
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-supabase-api-version',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Max-Age': '86400',
    Vary: 'Origin',
  }
}

function json(request: Request, status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors(request), 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
  })
}

function validUuid(value: unknown) {
  return typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)
}

function normalizeSpace(value: unknown) {
  return String(value || '').replace(/\s+/g, ' ').trim()
}

function titleCaseWords(value: unknown) {
  return normalizeSpace(value)
    .toLowerCase()
    .replace(/\b([a-z])/g, (match) => match.toUpperCase())
}

function isoDateFromMatch(match: RegExpMatchArray | null) {
  if (!match) return ''
  const day = String(match[1]).padStart(2, '0')
  const month = String(match[2]).padStart(2, '0')
  return `${match[3]}-${month}-${day}`
}

function filenameDocumentType(fileName: unknown) {
  const name = String(fileName || '').toLowerCase()
  if (/\b(?:aadhaar|aadhar|adhar)\b/.test(name)) return 'aadhaar'
  if (/\bpan\b/.test(name)) return 'pan'
  if (/passport/.test(name)) return 'passport'
  if (/(?:driving|licen[cs]e|\bdl\b)/.test(name)) return 'driving_licence'
  if (/(?:voter|epic)/.test(name)) return 'voter_id'
  return ''
}

function inferDocumentType(rawText: string, fileName = '') {
  const text = String(rawText || '').toUpperCase()
  const byFileName = filenameDocumentType(fileName)
  if (/PASSPORT|REPUBLIC OF INDIA|P<IND/.test(text) || PASSPORT_REGEX.test(text)) return 'passport'
  if (/INCOME TAX|PERMANENT ACCOUNT NUMBER|\bPAN\b/.test(text) || PAN_REGEX.test(text)) return 'pan'
  if (/DRIVING LICEN[CS]E|TRANSPORT DEPARTMENT|\bDL\s*NO/.test(text) || DL_REGEX.test(text)) return 'driving_licence'
  if (/ELECTION COMMISSION|ELECTOR PHOTO IDENTITY|EPIC/.test(text) || VOTER_REGEX.test(text)) return 'voter_id'

  const aadhaarNumberFound = [...text.matchAll(AADHAAR_REGEX)].length > 0
  const aadhaarTextMarker = /AADHAAR|AADHAR|UNIQUE IDENTIFICATION|GOVERNMENT OF INDIA/.test(text)
  const aadhaarLayoutMarker = /GOVERNMENT OF INDIA/.test(text)
    && /\b(?:DOB|DATE OF BIRTH|YOB)\b/.test(text)
    && /\b(?:MALE|FEMALE)\b/.test(text)
  if ((aadhaarTextMarker && aadhaarNumberFound) || aadhaarLayoutMarker || byFileName === 'aadhaar') return 'aadhaar'
  return byFileName || 'other'
}

function maskSensitiveNumbers(text: string) {
  return String(text || '').replace(AADHAAR_REGEX, (_match, _a, _b, c) => `XXXX XXXX ${c}`)
}

function maskAadhaar(value: unknown) {
  const digits = String(value || '').replace(/\D/g, '')
  return digits.length === 12 ? `XXXX XXXX ${digits.slice(-4)}` : ''
}

function maskPan(value: unknown) {
  const normalized = String(value || '').toUpperCase().replace(/\s+/g, '')
  return /^[A-Z]{5}\d{4}[A-Z]$/.test(normalized)
    ? `${normalized.slice(0, 5)}••••${normalized.slice(-1)}`
    : ''
}

function maskGeneric(value: unknown) {
  const normalized = normalizeSpace(value).replace(/\s+/g, '')
  if (normalized.length < 4) return normalized
  return `${'•'.repeat(Math.min(8, Math.max(4, normalized.length - 4)))}${normalized.slice(-4)}`
}

function lineAfterLabel(lines: string[], pattern: RegExp) {
  for (let index = 0; index < lines.length; index += 1) {
    if (!pattern.test(lines[index])) continue
    const inline = normalizeSpace(lines[index].replace(pattern, '').replace(/^\s*[:.-]\s*/, ''))
    if (inline && !/^[:.-]+$/.test(inline)) return inline
    const next = normalizeSpace(lines[index + 1] || '')
    if (next) return next
  }
  return ''
}

function probableName(lines: string[], documentType: string) {
  if (documentType === 'passport') {
    const surname = lineAfterLabel(lines, /^(?:surname|last name)\s*/i)
    const given = lineAfterLabel(lines, /^(?:given names?|given name|first name)\s*/i)
    if (surname || given) return titleCaseWords(`${given} ${surname}`)
  }
  if (documentType === 'pan') {
    const name = lineAfterLabel(lines, /^(?:name)\s*/i)
    if (name) return titleCaseWords(name)
  }
  if (documentType === 'driving_licence' || documentType === 'voter_id') {
    const name = lineAfterLabel(lines, /^(?:name|holder'?s? name|elector'?s? name)\s*/i)
    if (name) return titleCaseWords(name)
  }

  const rejected = /government|india|aadhaar|uidai|income tax|department|date of birth|dob|male|female|address|year of birth|father|signature|passport|republic|driving|licen[cs]e|election|commission|authority|number|no\.|issue|valid/i
  const candidates = lines
    .map(normalizeSpace)
    .filter((line) => line.length >= 3 && line.length <= 60)
    .filter((line) => /^[A-Za-z][A-Za-z .'-]+$/.test(line))
    .filter((line) => !rejected.test(line))

  if (documentType === 'aadhaar') {
    const dateIndex = lines.findIndex((line) => /\b(?:DOB|YOB|DATE OF BIRTH|YEAR OF BIRTH)\b/i.test(line))
    if (dateIndex > 0) {
      for (let index = dateIndex - 1; index >= Math.max(0, dateIndex - 4); index -= 1) {
        const line = normalizeSpace(lines[index])
        if (/^[A-Za-z][A-Za-z .'-]{2,59}$/.test(line) && !rejected.test(line)) return titleCaseWords(line)
      }
    }
  }
  return candidates.length ? titleCaseWords(candidates[0]) : ''
}

function parseGender(text: string) {
  if (/\bFEMALE\b/i.test(text)) return 'female'
  if (/\bM(?:ALE|ALLE)\b/i.test(text)) return 'male'
  if (/\b(?:TRANSGENDER|THIRD GENDER)\b/i.test(text)) return 'other'
  return ''
}

function extractAddress(lines: string[]) {
  const start = lines.findIndex((line) => /\baddress\b\s*[:-]?/i.test(line))
  if (start < 0) return ''
  const addressLines: string[] = []
  for (let index = start; index < Math.min(lines.length, start + 7); index += 1) {
    const cleaned = normalizeSpace(lines[index]).replace(/^address\s*[:-]?\s*/i, '')
    if (!cleaned) continue
    if (/\b(?:dob|date of birth|male|female|aadhaar|vid|signature)\b/i.test(cleaned)) break
    addressLines.push(cleaned)
  }
  return normalizeSpace(addressLines.join(', ')).slice(0, 240)
}

function extractPostalCode(text: string) {
  return String(text || '').match(/\b[1-9]\d{5}\b/)?.[0] || ''
}

function extractDateOfBirth(lines: string[], text: string) {
  const labelPattern = /\b(?:DOB|DATE OF BIRTH|BIRTH DATE|D\.O\.B\.?|जन्म(?:\s+तिथि)?)\b/i
  for (let index = 0; index < lines.length; index += 1) {
    if (!labelPattern.test(lines[index])) continue
    const sameLine = lines[index].match(DATE_REGEX)
    if (sameLine) return isoDateFromMatch(sameLine)
    const nextLine = String(lines[index + 1] || '').match(DATE_REGEX)
    if (nextLine) return isoDateFromMatch(nextLine)
  }
  return isoDateFromMatch(String(text || '').match(DATE_REGEX))
}

function extractMaskedDocumentNumber(text: string, documentType: string) {
  if (documentType === 'aadhaar') {
    const match = [...text.matchAll(AADHAAR_REGEX)][0]
    return match ? maskAadhaar(match[0]) : ''
  }
  if (documentType === 'pan') {
    const match = text.toUpperCase().match(PAN_REGEX)
    return match ? maskPan(match[0]) : ''
  }
  if (documentType === 'passport') {
    const match = text.toUpperCase().match(PASSPORT_REGEX)
    return match ? maskGeneric(match[0]) : ''
  }
  if (documentType === 'driving_licence') {
    const match = text.toUpperCase().match(DL_REGEX)
    return match ? maskGeneric(match[0]) : ''
  }
  if (documentType === 'voter_id') {
    const match = text.toUpperCase().match(VOTER_REGEX)
    return match ? maskGeneric(match[0]) : ''
  }
  return ''
}

function parseSafeFields(rawText: string, documentType: string) {
  const text = String(rawText || '')
  const lines = text.split(/\r?\n/).map(normalizeSpace).filter(Boolean)
  const indianDocument = ['aadhaar', 'pan', 'voter_id', 'driving_licence'].includes(documentType)
  const fields = {
    full_name: probableName(lines, documentType),
    date_of_birth: extractDateOfBirth(lines, text),
    gender: parseGender(text),
    address_line1: extractAddress(lines),
    postal_code: extractPostalCode(text),
    nationality: indianDocument ? 'India' : documentType === 'passport' && /\bIND\b/.test(text) ? 'India' : '',
    country_of_residence: indianDocument ? 'India' : '',
  }
  return Object.fromEntries(Object.entries(fields).filter(([, value]) => value !== '' && value !== null && value !== undefined))
}

function safeAnalysis(rawText: string, requestedType: string, fileName: string, confidence: number | null, latencyMs: number) {
  const detectedType = inferDocumentType(rawText, fileName)
  const documentType = requestedType && requestedType !== 'auto' ? requestedType : detectedType
  const maskedText = maskSensitiveNumbers(rawText)
  const extractedFields = parseSafeFields(maskedText, documentType)
  const documentNumberMasked = extractMaskedDocumentNumber(rawText, documentType) || null
  const meaningfulKeys = ['full_name', 'date_of_birth', 'gender', 'address_line1', 'postal_code']
  const meaningfulCount = meaningfulKeys.filter((key) => Boolean(extractedFields[key])).length
  const hasExtractedIdentity = meaningfulCount > 0 || Boolean(documentNumberMasked)
  const warnings: string[] = []
  if (!rawText.trim()) warnings.push('No readable text was detected. Retake the photo with better focus and lighting, or enter the fields manually.')
  else if (!hasExtractedIdentity) warnings.push('Text was detected, but StayQR could not confidently map the ID fields. Retake a straighter photo or enter the fields manually.')

  return {
    status: hasExtractedIdentity ? 'extracted' : 'limited',
    method: 'google_cloud_vision_document_text',
    provider: 'google_cloud_vision',
    confidence,
    providerLatencyMs: latencyMs,
    documentType,
    extractedFields,
    documentNumberMasked,
    secureQrDetected: false,
    secureQrSupported: false,
    secureQrPayloadSha256: null,
    rawOcrTextStored: false,
    rawQrPayloadStored: false,
    warnings,
    message: warnings.join(' ') || 'ID details extracted. Review them before completing check-in.',
  }
}

function base64ByteLength(value: string) {
  const clean = value.replace(/\s/g, '')
  const padding = clean.endsWith('==') ? 2 : clean.endsWith('=') ? 1 : 0
  return Math.floor((clean.length * 3) / 4) - padding
}

function averageConfidence(annotation: any) {
  const values: number[] = []
  for (const page of annotation?.pages || []) {
    for (const block of page?.blocks || []) {
      if (Number.isFinite(block?.confidence)) values.push(Number(block.confidence))
    }
  }
  if (!values.length) return null
  return Math.round((values.reduce((sum, value) => sum + value, 0) / values.length) * 100)
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: cors(request) })
  if (request.method !== 'POST') return json(request, 405, { ok: false, error: 'Method not allowed.' })

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')
    const enabled = String(Deno.env.get('ID_OCR_ENABLED') || '').toLowerCase() === 'true'
    const provider = String(Deno.env.get('ID_OCR_PROVIDER') || 'google_vision').toLowerCase()
    const apiKey = Deno.env.get('GOOGLE_CLOUD_VISION_API_KEY')?.trim()
    if (!supabaseUrl || !anonKey) throw new Error('Supabase function environment is incomplete.')
    if (!enabled) return json(request, 503, { ok: false, error: 'ID OCR is not enabled in this environment.' })
    if (provider !== 'google_vision') return json(request, 503, { ok: false, error: 'Configured ID OCR provider is not supported by this release.' })
    if (!apiKey) return json(request, 503, { ok: false, error: 'ID OCR provider credentials are not configured.' })

    const authorization = request.headers.get('Authorization') || ''
    const token = authorization.replace(/^Bearer\s+/i, '').trim()
    if (!token) return json(request, 401, { ok: false, error: 'Authentication is required.' })

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: `Bearer ${token}` } },
      auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    })
    const { data: userData, error: userError } = await userClient.auth.getUser(token)
    if (userError || !userData.user) return json(request, 401, { ok: false, error: 'Your StayQR session is invalid or expired.' })

    const body = await request.json().catch(() => ({}))
    const hotelId = body?.hotel_id
    const fileName = String(body?.file_name || '').slice(0, 160)
    const mimeType = String(body?.mime_type || '').toLowerCase()
    const requestedType = String(body?.requested_document_type || 'auto').toLowerCase()
    const contentBase64 = typeof body?.content_base64 === 'string' ? body.content_base64.replace(/\s/g, '') : ''

    if (!validUuid(hotelId)) return json(request, 400, { ok: false, error: 'Valid hotel_id is required.' })
    if (!SUPPORTED_MIME_TYPES.has(mimeType)) return json(request, 400, { ok: false, error: 'Automatic ID extraction currently supports JPG and PNG images.' })
    if (!contentBase64 || !/^[A-Za-z0-9+/]+={0,2}$/.test(contentBase64)) return json(request, 400, { ok: false, error: 'A valid ID image is required.' })
    if (base64ByteLength(contentBase64) > MAX_IMAGE_BYTES) return json(request, 413, { ok: false, error: 'ID image is too large. Maximum automatic OCR size is 5 MB.' })

    const { data: permissionRows, error: permissionError } = await userClient.rpc('get_my_hotel_permissions', { target_hotel_id: hotelId })
    if (permissionError) throw permissionError
    const permissionSet = new Set((permissionRows || []).map((row: { permission_key?: string }) => row.permission_key))
    if (!permissionSet.has('checkin.manage') && !permissionSet.has('guests.manage')) {
      return json(request, 403, { ok: false, error: 'ID scanning access denied for this hotel.' })
    }

    const providerController = new AbortController()
    const timer = setTimeout(() => providerController.abort(), PROVIDER_TIMEOUT_MS)
    const startedAt = Date.now()
    let providerResponse: Response
    try {
      providerResponse = await fetch(`https://vision.googleapis.com/v1/images:annotate?key=${encodeURIComponent(apiKey)}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          requests: [{
            image: { content: contentBase64 },
            features: [{ type: 'DOCUMENT_TEXT_DETECTION', maxResults: 1 }],
            imageContext: { languageHints: ['en', 'hi'] },
          }],
        }),
        signal: providerController.signal,
      })
    } catch (error) {
      if (error instanceof DOMException && error.name === 'AbortError') {
        return json(request, 504, { ok: false, error: 'ID reading timed out. Please retry or enter the details manually.' })
      }
      return json(request, 502, { ok: false, error: 'ID OCR provider is temporarily unavailable.' })
    } finally {
      clearTimeout(timer)
    }

    if (!providerResponse.ok) {
      return json(request, providerResponse.status >= 500 ? 502 : 503, { ok: false, error: 'ID OCR provider rejected the request. Check the staging provider configuration.' })
    }

    const providerBody = await providerResponse.json().catch(() => ({}))
    const annotation = providerBody?.responses?.[0]
    if (annotation?.error) return json(request, 502, { ok: false, error: 'ID OCR provider could not process this image.' })

    const rawText = String(annotation?.fullTextAnnotation?.text || annotation?.textAnnotations?.[0]?.description || '')
    const latencyMs = Date.now() - startedAt
    const analysis = safeAnalysis(rawText, requestedType, fileName, averageConfidence(annotation?.fullTextAnnotation), latencyMs)

    // Important: raw OCR text and provider response are intentionally not returned or persisted.
    return json(request, 200, { ok: true, analysis })
  } catch {
    return json(request, 500, { ok: false, error: 'Unable to read this ID automatically right now.' })
  }
})
