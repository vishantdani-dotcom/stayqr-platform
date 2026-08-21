import { createClient } from 'npm:@supabase/supabase-js@2.106.2'
import { DOMParser } from 'npm:@xmldom/xmldom@0.8.10'
import { SignedXml } from 'npm:xml-crypto@6.1.2'

const UIDAI_OFFLINE_CERT_URL = 'https://uidai.gov.in/images/uidai_offline_publickey_2026.cer'
const MAX_XML_BYTES = 512 * 1024

function allowedOrigins() {
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
  const configured = allowedOrigins()
  const allowed = isAllowedOrigin(origin, configured)
  const fallback = [...configured][0] || 'null'

  return {
    'Access-Control-Allow-Origin': allowed ? origin : fallback,
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-supabase-api-version',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Max-Age': '86400',
    'Vary': 'Origin',
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

function derToPem(bytes: Uint8Array) {
  let binary = ''
  for (const byte of bytes) binary += String.fromCharCode(byte)
  const b64 = btoa(binary)
  const lines = b64.match(/.{1,64}/g)?.join('\n') || b64
  return `-----BEGIN CERTIFICATE-----\n${lines}\n-----END CERTIFICATE-----`
}

async function sha256Hex(value: string | Uint8Array) {
  const bytes = typeof value === 'string' ? new TextEncoder().encode(value) : value
  const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', bytes))
  return [...digest].map((value) => value.toString(16).padStart(2, '0')).join('')
}

async function loadCertificatePem() {
  const configured = Deno.env.get('UIDAI_OFFLINE_CERT_PEM')?.trim()
  if (configured) return { pem: configured.replace(/\\n/g, '\n'), source: 'environment' }

  const response = await fetch(UIDAI_OFFLINE_CERT_URL, {
    headers: { 'User-Agent': 'StayQR Aadhaar Offline Verification/1.0' },
  })
  if (!response.ok) throw new Error(`UIDAI certificate download failed with HTTP ${response.status}.`)
  const bytes = new Uint8Array(await response.arrayBuffer())
  if (bytes.length < 256 || bytes.length > 16384) throw new Error('UIDAI certificate response was not a valid certificate size.')
  return { pem: derToPem(bytes), source: UIDAI_OFFLINE_CERT_URL }
}

function firstElementByLocalName(document: Document, localName: string) {
  const all = document.getElementsByTagName('*')
  for (let index = 0; index < all.length; index += 1) {
    if (all[index].localName === localName || all[index].nodeName.split(':').pop() === localName) return all[index]
  }
  return null
}

function compactAddress(poa: Element | null) {
  if (!poa) return null
  const parts = ['house', 'street', 'loc', 'vtc', 'po', 'subdist', 'dist', 'state', 'pc', 'country']
    .map((key) => poa.getAttribute(key)?.trim())
    .filter(Boolean)
  return parts.join(', ') || null
}

function parseVerifiedFields(document: Document) {
  const root = document.documentElement
  const poi = firstElementByLocalName(document, 'Poi')
  const poa = firstElementByLocalName(document, 'Poa')
  const compact = root?.localName === 'OKY' || root?.nodeName === 'OKY'

  if (compact) {
    return {
      name: root.getAttribute('n') || null,
      dob: root.getAttribute('d') || null,
      gender: root.getAttribute('g') || null,
      address: root.getAttribute('a') || null,
    }
  }

  return {
    name: poi?.getAttribute('name') || null,
    dob: poi?.getAttribute('dob') || null,
    gender: poi?.getAttribute('gender') || null,
    address: compactAddress(poa),
    state: poa?.getAttribute('state') || null,
    district: poa?.getAttribute('dist') || null,
    postal_code: poa?.getAttribute('pc') || null,
    country: poa?.getAttribute('country') || null,
  }
}

function maskedReference(document: Document) {
  const root = document.documentElement
  const reference = root?.getAttribute('referenceId') || root?.getAttribute('r') || ''
  const digits = reference.replace(/\D/g, '')
  return digits.length >= 4 ? `****${digits.slice(-4)}` : null
}

function sourceVersion(document: Document) {
  const root = document.documentElement
  return root?.getAttribute('version') || root?.getAttribute('v') || root?.namespaceURI || 'uidai-offline'
}

function verifyXmlSignature(xml: string, document: Document, certificatePem: string) {
  const signature = firstElementByLocalName(document, 'Signature')
  if (!signature) throw new Error('The Aadhaar Offline XML does not contain a digital signature.')
  const verifier = new SignedXml({ publicCert: certificatePem })
  verifier.loadSignature(signature)
  const valid = verifier.checkSignature(xml)
  if (!valid) {
    const detail = verifier.validationErrors?.[0]
    throw new Error(detail ? `UIDAI digital signature validation failed: ${detail}` : 'UIDAI digital signature validation failed.')
  }
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: cors(request) })
  if (request.method !== 'POST') return json(request, 405, { error: 'Method not allowed.' })

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
    if (!supabaseUrl || !anonKey || !serviceRoleKey) throw new Error('Supabase Edge Function environment is incomplete.')

    const authorization = request.headers.get('Authorization') || ''
    const token = authorization.replace(/^Bearer\s+/i, '').trim()
    if (!token) return json(request, 401, { error: 'Authentication is required.' })

    const userClient = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: `Bearer ${token}` } } })
    const adminClient = createClient(supabaseUrl, serviceRoleKey)
    const { data: userData, error: userError } = await userClient.auth.getUser(token)
    if (userError || !userData.user) return json(request, 401, { error: 'StayQR session could not be verified.' })

    const body = await request.json()
    const hotelId = body?.hotel_id
    const guestId = body?.guest_id
    const guestSessionId = body?.guest_session_id || null
    const guestDocumentId = body?.guest_document_id || null
    const xml = typeof body?.xml === 'string' ? body.xml.trim() : ''

    if (!validUuid(hotelId) || !validUuid(guestId)) return json(request, 400, { error: 'Valid hotel_id and guest_id are required.' })
    if (guestSessionId && !validUuid(guestSessionId)) return json(request, 400, { error: 'guest_session_id is invalid.' })
    if (guestDocumentId && !validUuid(guestDocumentId)) return json(request, 400, { error: 'guest_document_id is invalid.' })
    const xmlBytes = new TextEncoder().encode(xml)
    if (!xml || xmlBytes.length > MAX_XML_BYTES) return json(request, 400, { error: 'Aadhaar Offline XML must be present and no larger than 512 KB.' })
    if (/<!DOCTYPE|<!ENTITY/i.test(xml)) return json(request, 400, { error: 'XML with DTD or entity declarations is not accepted.' })

    const { data: permissionRows, error: permissionError } = await userClient.rpc('get_my_hotel_permissions', { target_hotel_id: hotelId })
    if (permissionError) throw permissionError
    const permissionSet = new Set((permissionRows || []).map((row: { permission_key?: string }) => row.permission_key))
    if (!permissionSet.has('guests.manage') && !permissionSet.has('checkin.manage')) {
      return json(request, 403, { error: 'Guest identity verification access denied.' })
    }

    const { data: guest, error: guestError } = await userClient.from('guests').select('id').eq('hotel_id', hotelId).eq('id', guestId).maybeSingle()
    if (guestError) throw guestError
    if (!guest) return json(request, 404, { error: 'Guest not found in this hotel.' })

    const { data: consent, error: consentError } = await userClient.from('guest_consents')
      .select('id').eq('hotel_id', hotelId).eq('guest_id', guestId)
      .eq('purpose', 'aadhaar_offline_verification').eq('status', 'granted').is('revoked_at', null)
      .order('captured_at', { ascending: false }).limit(1).maybeSingle()
    if (consentError) throw consentError
    if (!consent) return json(request, 409, { error: 'Record Aadhaar offline verification consent before verifying.' })

    if (guestSessionId) {
      const { data: session, error: sessionError } = await userClient.from('guest_sessions')
        .select('id').eq('hotel_id', hotelId).eq('guest_id', guestId).eq('id', guestSessionId).maybeSingle()
      if (sessionError) throw sessionError
      if (!session) return json(request, 409, { error: 'Guest session does not belong to this guest and hotel.' })
    }

    if (guestDocumentId) {
      const { data: documentRow, error: documentError } = await userClient.from('guest_documents')
        .select('id').eq('hotel_id', hotelId).eq('guest_id', guestId).eq('id', guestDocumentId).is('deleted_at', null).maybeSingle()
      if (documentError) throw documentError
      if (!documentRow) return json(request, 409, { error: 'Guest document does not belong to this guest and hotel.' })
    }

    const parsed = new DOMParser().parseFromString(xml, 'text/xml')
    if (!parsed?.documentElement || parsed.getElementsByTagName('parsererror').length) {
      return json(request, 400, { error: 'The uploaded file is not valid XML.' })
    }
    const rootName = parsed.documentElement.localName || parsed.documentElement.nodeName
    if (!['OfflinePaperlessKyc', 'OKY'].includes(rootName)) {
      return json(request, 400, { error: 'This XML is not a supported UIDAI Paperless Offline e-KYC document.' })
    }

    const signature = firstElementByLocalName(parsed, 'Signature')
    if (!signature) {
      return json(request, 400, { error: 'The Aadhaar Offline XML does not contain a digital signature.' })
    }

    const certificate = await loadCertificatePem()
    verifyXmlSignature(xml, parsed, certificate.pem)
    const digest = await sha256Hex(xmlBytes)
    const certDigest = await sha256Hex(certificate.pem)
    const fields = parseVerifiedFields(parsed)
    const reference = maskedReference(parsed)
    const version = sourceVersion(parsed)

    const { data: recorded, error: recordError } = await adminClient.rpc('record_verified_aadhaar_offline_result', {
      target_hotel_id: hotelId,
      target_guest_id: guestId,
      target_guest_session_id: guestSessionId,
      target_guest_document_id: guestDocumentId,
      actor_user_id: userData.user.id,
      payload_sha256: digest,
      reference_id_masked: reference,
      source_version: version,
      verified_fields: fields,
      verification_metadata: {
        certificate_source: certificate.source,
        certificate_sha256: certDigest,
        raw_xml_stored: false,
        share_code_stored: false,
        aadhaar_number_stored: false,
      },
    })
    if (recordError) throw recordError

    return json(request, 200, {
      ok: true,
      status: 'verified',
      signature_valid: true,
      reference_id_masked: reference,
      source_version: version,
      verified_fields: fields,
      verification_id: recorded?.verification_id || null,
      privacy: {
        raw_xml_stored: false,
        share_code_stored: false,
        aadhaar_number_stored: false,
      },
    })
  } catch (error) {
    console.error('verify-aadhaar-offline failed:', error instanceof Error ? error.message : String(error))
    return json(request, 400, { error: error instanceof Error ? error.message : 'Aadhaar offline verification failed.' })
  }
})
