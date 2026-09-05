import { createClient } from 'npm:@supabase/supabase-js@2.106.2'

const MAX_IMAGE_BYTES = 5 * 1024 * 1024
const OCR_SPACE_FREE_MAX_IMAGE_BYTES = 1 * 1024 * 1024
const PROVIDER_TIMEOUT_MS = 12000
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

const NAME_NOISE_RE = /government|govt\.?|india|bharat|aadhaar|aadhar|uidai|unique identification|income tax|department|date of birth|dob|male|female|address|year of birth|father|mother|signature|passport|republic|driving|licen[cs]e|election|commission|authority|number|no\.|issue|issued|valid|verified|verify|download|document|identity|support|update|updated|enrolment|enrollment|vid\b|help|www\.|http|toll\s*free/i
const ADDRESS_NOISE_RE = /documents?\s+to\s+support|identity\s+and\s+address|should\s+be\s+updated|update\s+your|downloaded|digitally\s+signed|authentication|verification|government\s+of\s+india|unique\s+identification|aadhaar\s+is|mera\s+aadhaar|www\.|uidai\.gov/i
const ADDRESS_LABEL_RE = /^(?:address|पता)\s*[:.-]\s*/i
const ADDRESS_RELATION_RE = /^(?:c\/?o|s\/?o|d\/?o|w\/?o)\b/i
const ADDRESS_SIGNAL_RE = /\b(?:road|rd\.?|street|st\.?|lane|nagar|colony|sector|ward|village|gaon|taluka|tehsil|district|dist\.?|state|near|opp(?:osite)?|behind|apartment|flat|house|plot|floor|post|po\b|p\.o\.|pin(?:code)?|maharashtra|madhya pradesh|uttar pradesh|delhi|karnataka|tamil nadu|telangana|gujarat|rajasthan|punjab|haryana|bihar|odisha|west bengal|kerala|goa)\b/i

function looksLikePersonName(value: unknown) {
  const line = normalizeSpace(value)
  if (line.length < 3 || line.length > 60) return false
  if (!/^[A-Za-z][A-Za-z .'-]+$/.test(line)) return false
  if (NAME_NOISE_RE.test(line)) return false
  const tokens = line.split(/\s+/).filter(Boolean)
  if (tokens.length >= 2) return true
  return tokens.length === 1 && tokens[0].length >= 4
}

function probableName(lines: string[], documentType: string) {
  if (documentType === 'passport') {
    const surname = lineAfterLabel(lines, /^(?:surname|last name)\s*/i)
    const given = lineAfterLabel(lines, /^(?:given names?|given name|first name)\s*/i)
    const combined = normalizeSpace(`${given} ${surname}`)
    if (looksLikePersonName(combined)) return titleCaseWords(combined)
  }
  if (documentType === 'pan') {
    const name = lineAfterLabel(lines, /^(?:name)\s*/i)
    if (looksLikePersonName(name)) return titleCaseWords(name)
  }
  if (documentType === 'driving_licence' || documentType === 'voter_id') {
    const name = lineAfterLabel(lines, /^(?:name|holder'?s? name|elector'?s? name)\s*/i)
    if (looksLikePersonName(name)) return titleCaseWords(name)
  }

  if (documentType === 'aadhaar') {
    const dateIndex = lines.findIndex((line) => /\b(?:DOB|YOB|DATE OF BIRTH|YEAR OF BIRTH|जन्म(?:\s+तिथि)?)\b/i.test(line))
    if (dateIndex > 0) {
      const scored: Array<{ line: string; score: number }> = []
      for (let index = Math.max(0, dateIndex - 6); index < dateIndex; index += 1) {
        const line = normalizeSpace(lines[index])
        if (!looksLikePersonName(line)) continue
        const distance = dateIndex - index
        const tokenCount = line.split(/\s+/).filter(Boolean).length
        let score = 20 - (distance * 2)
        if (tokenCount >= 2) score += 8
        if (tokenCount >= 3) score += 2
        scored.push({ line, score })
      }
      scored.sort((a, b) => b.score - a.score)
      if (scored[0]) return titleCaseWords(scored[0].line)
    }
  }

  const candidate = lines.map(normalizeSpace).find(looksLikePersonName)
  return candidate ? titleCaseWords(candidate) : ''
}

function parseGender(text: string) {
  if (/\bFEMALE\b/i.test(text)) return 'female'
  if (/\bM(?:ALE|ALLE)\b/i.test(text)) return 'male'
  if (/\b(?:TRANSGENDER|THIRD GENDER)\b/i.test(text)) return 'other'
  return ''
}

function extractAddress(lines: string[]) {
  let start = lines.findIndex((line) => ADDRESS_LABEL_RE.test(normalizeSpace(line)))
  let explicitLabel = start >= 0
  if (start < 0) {
    start = lines.findIndex((line) => ADDRESS_RELATION_RE.test(normalizeSpace(line)))
    explicitLabel = false
  }
  if (start < 0) return ''

  const addressLines: string[] = []
  for (let index = start; index < Math.min(lines.length, start + 8); index += 1) {
    let cleaned = normalizeSpace(lines[index])
    if (index === start && explicitLabel) cleaned = cleaned.replace(ADDRESS_LABEL_RE, '')
    if (!cleaned) continue
    if (ADDRESS_NOISE_RE.test(cleaned)) break
    if (/\b(?:dob|date of birth|male|female|aadhaar|vid|signature|verified|verify)\b/i.test(cleaned)) break
    if (/^\d{4}[\s.-]?\d{4}[\s.-]?\d{4}$/.test(cleaned.replace(/X/gi, '0'))) break
    addressLines.push(cleaned)
  }

  const combined = normalizeSpace(addressLines.join(', ')).slice(0, 240)
  if (combined.length < 10 || ADDRESS_NOISE_RE.test(combined)) return ''
  const hasPostalCode = /\b[1-9]\d{5}\b/.test(combined)
  const hasAddressSignal = ADDRESS_SIGNAL_RE.test(combined) || ADDRESS_RELATION_RE.test(combined)
  if (!hasPostalCode && !hasAddressSignal && addressLines.length < 2) return ''
  return combined
}

function extractPostalCode(text: string) {
  return String(text || '').match(/\b[1-9]\d{5}\b/)?.[0] || ''
}

function validIsoDate(value: string) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(String(value || ''))) return ''
  const [year, month, day] = value.split('-').map(Number)
  const date = new Date(Date.UTC(year, month - 1, day))
  if (date.getUTCFullYear() !== year || date.getUTCMonth() !== month - 1 || date.getUTCDate() !== day) return ''
  const nowYear = new Date().getUTCFullYear()
  if (year < 1900 || year > nowYear) return ''
  return value
}

function extractDateOfBirth(lines: string[], text: string) {
  const labelPattern = /\b(?:DOB|DATE OF BIRTH|BIRTH DATE|D\.O\.B\.?|जन्म(?:\s+तिथि)?)\b/i
  for (let index = 0; index < lines.length; index += 1) {
    if (!labelPattern.test(lines[index])) continue
    const sameLine = validIsoDate(isoDateFromMatch(lines[index].match(DATE_REGEX)))
    if (sameLine) return sameLine
    const nextLine = validIsoDate(isoDateFromMatch(String(lines[index + 1] || '').match(DATE_REGEX)))
    if (nextLine) return nextLine
  }
  return validIsoDate(isoDateFromMatch(String(text || '').match(DATE_REGEX)))
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
  const address = extractAddress(lines)
  const indianDocument = ['aadhaar', 'pan', 'voter_id', 'driving_licence'].includes(documentType)
  const fields = {
    full_name: probableName(lines, documentType),
    date_of_birth: extractDateOfBirth(lines, text),
    gender: parseGender(text),
    address_line1: address,
    postal_code: address ? extractPostalCode(address) : '',
    nationality: indianDocument ? 'India' : documentType === 'passport' && /\bIND\b/.test(text) ? 'India' : '',
    country_of_residence: indianDocument ? 'India' : '',
  }
  return Object.fromEntries(Object.entries(fields).filter(([, value]) => value !== '' && value !== null && value !== undefined))
}

function extractionQuality(documentType: string, fields: Record<string, unknown>, documentNumberMasked: string | null) {
  let score = 0
  const reasons: string[] = []
  if (documentNumberMasked) score += 25; else reasons.push('document number not confidently detected')
  if (fields.full_name) score += 25; else reasons.push('name needs review')
  if (fields.date_of_birth) score += 20; else reasons.push('date of birth needs review')
  if (fields.gender) score += 10
  if (fields.address_line1) score += 10
  if (fields.postal_code) score += 10
  const coreReady = documentType === 'aadhaar'
    ? Boolean(documentNumberMasked && fields.full_name && fields.date_of_birth)
    : Boolean(documentNumberMasked || fields.full_name)
  return { score: Math.min(100, score), reviewRequired: !coreReady || score < 60, reasons }
}

function safeAnalysis(rawText: string, requestedType: string, fileName: string, confidence: number | null, latencyMs: number, provider: string) {
  const detectedType = inferDocumentType(rawText, fileName)
  const documentType = requestedType && requestedType !== 'auto' ? requestedType : detectedType
  const maskedText = maskSensitiveNumbers(rawText)
  const extractedFields = parseSafeFields(maskedText, documentType)
  const documentNumberMasked = extractMaskedDocumentNumber(rawText, documentType) || null
  const quality = extractionQuality(documentType, extractedFields, documentNumberMasked)
  const warnings: string[] = []
  if (!rawText.trim()) warnings.push('No readable text was detected. Retake the photo with better focus and lighting, or enter the fields manually.')
  else if (quality.reviewRequired) warnings.push('Some ID fields could not be mapped confidently. Review the extracted details and complete any missing fields manually.')
  return {
    status: quality.reviewRequired ? 'review_required' : 'extracted',
    method: provider === 'ocr_space' ? 'ocr_space_engine_2' : 'google_cloud_vision_document_text',
    provider: provider === 'ocr_space' ? 'ocr_space' : 'google_cloud_vision',
    confidence,
    qualityScore: quality.score,
    reviewRequired: quality.reviewRequired,
    qualityReasons: quality.reasons,
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

type ProviderResult = {
  provider: string
  rawText: string
  confidence: number | null
  latencyMs: number
}

async function runProviderOcr(
  providerName: string,
  contentBase64: string,
  mimeType: string,
  googleApiKey?: string,
  ocrSpaceApiKey?: string,
): Promise<ProviderResult> {
  if (providerName === 'ocr_space' && !ocrSpaceApiKey) throw new Error('provider_unavailable')
  if (providerName === 'google_vision' && !googleApiKey) throw new Error('provider_unavailable')
  if (providerName === 'ocr_space' && base64ByteLength(contentBase64) > OCR_SPACE_FREE_MAX_IMAGE_BYTES) {
    throw new Error('ocr_space_image_too_large')
  }

  const controller = new AbortController()
  const timer = setTimeout(() => controller.abort(), PROVIDER_TIMEOUT_MS)
  const startedAt = Date.now()
  try {
    let response: Response
    if (providerName === 'ocr_space') {
      const form = new URLSearchParams()
      form.set('base64Image', `data:${mimeType};base64,${contentBase64}`)
      form.set('language', 'eng')
      form.set('OCREngine', '2')
      form.set('scale', 'true')
      form.set('detectOrientation', 'true')
      form.set('isOverlayRequired', 'false')
      response = await fetch('https://api.ocr.space/parse/image', {
        method: 'POST',
        headers: { apikey: ocrSpaceApiKey!, 'Content-Type': 'application/x-www-form-urlencoded' },
        body: form.toString(),
        signal: controller.signal,
      })
    } else {
      response = await fetch(`https://vision.googleapis.com/v1/images:annotate?key=${encodeURIComponent(googleApiKey!)}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          requests: [{
            image: { content: contentBase64 },
            features: [{ type: 'DOCUMENT_TEXT_DETECTION', maxResults: 1 }],
            imageContext: { languageHints: ['en', 'hi'] },
          }],
        }),
        signal: controller.signal,
      })
    }

    if (!response.ok) throw new Error('provider_rejected')
    const body = await response.json().catch(() => ({}))
    let rawText = ''
    let confidence: number | null = null
    if (providerName === 'ocr_space') {
      if (body?.IsErroredOnProcessing) throw new Error('provider_processing_failed')
      rawText = String(body?.ParsedResults?.[0]?.ParsedText || '')
    } else {
      const annotation = body?.responses?.[0]
      if (annotation?.error) throw new Error('provider_processing_failed')
      rawText = String(annotation?.fullTextAnnotation?.text || annotation?.textAnnotations?.[0]?.description || '')
      confidence = averageConfidence(annotation?.fullTextAnnotation)
    }
    return { provider: providerName, rawText, confidence, latencyMs: Date.now() - startedAt }
  } finally {
    clearTimeout(timer)
  }
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: cors(request) })
  if (request.method !== 'POST') return json(request, 405, { ok: false, error: 'Method not allowed.' })

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')
    const enabled = String(Deno.env.get('ID_OCR_ENABLED') || '').toLowerCase() === 'true'
    const provider = String(Deno.env.get('ID_OCR_PROVIDER') || 'ocr_space').toLowerCase()
    const googleApiKey = Deno.env.get('GOOGLE_CLOUD_VISION_API_KEY')?.trim()
    const ocrSpaceApiKey = Deno.env.get('OCR_SPACE_API_KEY')?.trim()
    if (!supabaseUrl || !anonKey) throw new Error('Supabase function environment is incomplete.')
    if (!enabled) return json(request, 503, { ok: false, error: 'ID OCR is not enabled in this environment.' })
    if (!['google_vision', 'ocr_space'].includes(provider)) return json(request, 503, { ok: false, error: 'Configured ID OCR provider is not supported by this release.' })
    if (!googleApiKey && !ocrSpaceApiKey) return json(request, 503, { ok: false, error: 'No ID OCR provider is configured.' })

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

    const providers: string[] = []
    const addProvider = (value: string) => {
      if (!providers.includes(value)) providers.push(value)
    }
    addProvider(provider)
    if (provider === 'ocr_space' && googleApiKey) addProvider('google_vision')
    if (provider === 'google_vision' && ocrSpaceApiKey) addProvider('ocr_space')

    const candidates: any[] = []
    const attemptedProviders: string[] = []
    for (const providerName of providers) {
      attemptedProviders.push(providerName)
      try {
        const result = await runProviderOcr(providerName, contentBase64, mimeType, googleApiKey, ocrSpaceApiKey)
        const analysis = safeAnalysis(result.rawText, requestedType, fileName, result.confidence, result.latencyMs, providerName)
        candidates.push(analysis)
        if (!analysis.reviewRequired && Number(analysis.qualityScore || 0) >= 70) break
      } catch (error) {
        if (error instanceof DOMException && error.name === 'AbortError') continue
        continue
      }
    }

    if (!candidates.length) {
      return json(request, 502, { ok: false, error: 'StayQR could not read this ID with the configured OCR providers. Retake the photo or enter the details manually.' })
    }

    candidates.sort((a, b) => {
      const qualityDelta = Number(b.qualityScore || 0) - Number(a.qualityScore || 0)
      if (qualityDelta !== 0) return qualityDelta
      return Number(b.confidence || 0) - Number(a.confidence || 0)
    })
    const analysis = candidates[0]
    analysis.fallbackUsed = analysis.provider !== (provider === 'ocr_space' ? 'ocr_space' : 'google_cloud_vision')
    analysis.providersTried = attemptedProviders.map((item) => item === 'google_vision' ? 'google_cloud_vision' : item)

    // Important: raw OCR text and provider response are intentionally not returned or persisted.
    return json(request, 200, { ok: true, analysis })
  } catch {
    return json(request, 500, { ok: false, error: 'Unable to read this ID automatically right now.' })
  }
})
