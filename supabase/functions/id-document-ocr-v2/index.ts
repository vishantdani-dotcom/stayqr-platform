import { createClient } from '@supabase/supabase-js'
import { candidateFromAzure, candidateFromText, finalizeCandidates } from '../_shared/idOcrCore.js'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' },
  })
}

function safeErrorMessage(error: unknown) {
  const message = error instanceof Error ? error.message : String(error || '')
  if (/timeout/i.test(message)) return 'The ID-reading service timed out. Please try once more.'
  return 'The ID-reading service could not process this image reliably.'
}

function env(name: string) {
  return (Deno.env.get(name) || '').trim()
}

function decodeBase64Bytes(base64: string) {
  const binary = atob(base64)
  const bytes = new Uint8Array(binary.length)
  for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i)
  return bytes
}

async function withTimeout<T>(promise: Promise<T>, ms: number, label: string): Promise<T> {
  let timer: number | undefined
  try {
    return await Promise.race([
      promise,
      new Promise<T>((_, reject) => { timer = setTimeout(() => reject(new Error(`${label} timeout`)), ms) }),
    ])
  } finally {
    if (timer) clearTimeout(timer)
  }
}

async function authorizeHotel(req: Request, hotelId: string) {
  const authHeader = req.headers.get('Authorization') || ''
  const jwt = authHeader.replace(/^Bearer\s+/i, '').trim()
  if (!jwt) throw new Error('Unauthorized')

  const supabaseUrl = env('SUPABASE_URL')
  const serviceKey = env('SUPABASE_SERVICE_ROLE_KEY') || env('SUPABASE_SECRET_KEY')
  if (!supabaseUrl || !serviceKey) throw new Error('Server authorization is unavailable')

  const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } })
  const { data: userData, error: userError } = await admin.auth.getUser(jwt)
  const user = userData?.user
  if (userError || !user?.id) throw new Error('Unauthorized')

  const [{ data: staff }, { data: platformAdmin }] = await Promise.all([
    admin.from('staff').select('id').eq('hotel_id', hotelId).eq('auth_user_id', user.id).eq('status', 'active').maybeSingle(),
    admin.from('platform_admins').select('user_id').eq('user_id', user.id).eq('status', 'active').maybeSingle(),
  ])
  if (!staff && !platformAdmin) throw new Error('Forbidden')
  return user.id
}

async function analyzeWithAzure(contentBase64: string, requestedType: string) {
  const endpoint = env('AZURE_DOCUMENT_INTELLIGENCE_ENDPOINT').replace(/\/$/, '')
  const key = env('AZURE_DOCUMENT_INTELLIGENCE_KEY')
  if (!endpoint || !key) return null

  const analyzeUrl = `${endpoint}/documentintelligence/documentModels/prebuilt-idDocument:analyze?_overload=analyzeDocument&api-version=2024-11-30`
  const response = await withTimeout(fetch(analyzeUrl, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Ocp-Apim-Subscription-Key': key },
    body: JSON.stringify({ base64Source: contentBase64 }),
  }), 12000, 'Azure submit')

  if (response.status !== 202) throw new Error(`Azure submit HTTP ${response.status}`)
  const operationLocation = response.headers.get('Operation-Location')
  if (!operationLocation) throw new Error('Azure operation location missing')

  const started = Date.now()
  while (Date.now() - started < 22000) {
    await new Promise((resolve) => setTimeout(resolve, 550))
    const poll = await withTimeout(fetch(operationLocation, { headers: { 'Ocp-Apim-Subscription-Key': key } }), 7000, 'Azure poll')
    if (!poll.ok) throw new Error(`Azure poll HTTP ${poll.status}`)
    const body = await poll.json()
    if (body?.status === 'succeeded') return candidateFromAzure(body, requestedType)
    if (body?.status === 'failed') throw new Error('Azure analysis failed')
  }
  throw new Error('Azure analysis timeout')
}

async function analyzeWithGoogle(contentBase64: string, requestedType: string) {
  const key = env('GOOGLE_VISION_API_KEY') || env('GOOGLE_CLOUD_VISION_API_KEY')
  if (!key) return null
  const response = await withTimeout(fetch(`https://vision.googleapis.com/v1/images:annotate?key=${encodeURIComponent(key)}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      requests: [{
        image: { content: contentBase64 },
        features: [{ type: 'DOCUMENT_TEXT_DETECTION', maxResults: 1 }],
        imageContext: { languageHints: ['en', 'hi'] },
      }],
    }),
  }), 18000, 'Google Vision')
  if (!response.ok) throw new Error(`Google Vision HTTP ${response.status}`)
  const body = await response.json()
  const item = body?.responses?.[0] || {}
  if (item?.error) throw new Error('Google Vision provider error')
  const text = item?.fullTextAnnotation?.text || item?.textAnnotations?.[0]?.description || ''
  return text ? candidateFromText('google-vision', text, requestedType, 0.72) : null
}

async function analyzeWithOcrSpace(contentBase64: string, mimeType: string, requestedType: string) {
  const key = env('OCR_SPACE_API_KEY')
  if (!key) return null
  const form = new FormData()
  form.set('base64Image', `data:${mimeType || 'image/jpeg'};base64,${contentBase64}`)
  form.set('language', 'eng')
  form.set('isOverlayRequired', 'false')
  form.set('detectOrientation', 'true')
  form.set('scale', 'true')
  form.set('OCREngine', '2')
  const response = await withTimeout(fetch('https://api.ocr.space/parse/image', {
    method: 'POST', headers: { apikey: key }, body: form,
  }), 18000, 'OCR.Space')
  if (!response.ok) throw new Error(`OCR.Space HTTP ${response.status}`)
  const body = await response.json()
  if (body?.IsErroredOnProcessing) throw new Error('OCR.Space provider error')
  const text = Array.isArray(body?.ParsedResults)
    ? body.ParsedResults.map((x: any) => x?.ParsedText || '').filter(Boolean).join('\n')
    : ''
  return text ? candidateFromText('ocr-space', text, requestedType, 0.58) : null
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'POST') return json(405, { ok: false, error: 'Method not allowed' })

  try {
    const body = await req.json().catch(() => null)
    const hotelId = String(body?.hotel_id || '').trim()
    const contentBase64 = String(body?.content_base64 || '').replace(/^data:[^,]+,/, '').trim()
    const mimeType = String(body?.mime_type || 'image/jpeg').toLowerCase()
    const requestedType = String(body?.requested_document_type || 'auto').trim() || 'auto'

    if (!/^[0-9a-f-]{36}$/i.test(hotelId)) return json(400, { ok: false, error: 'A valid hotel context is required.' })
    if (!contentBase64) return json(400, { ok: false, error: 'ID image data is required.' })
    if (!/^image\/(?:jpeg|jpg|png|webp)$/i.test(mimeType)) return json(400, { ok: false, error: 'Use a JPG, PNG or WebP photo for automatic ID reading.' })

    const approxBytes = Math.floor(contentBase64.length * 0.75)
    if (approxBytes > 4 * 1024 * 1024) return json(413, { ok: false, error: 'Use an ID image smaller than 4 MB for automatic reading.' })
    decodeBase64Bytes(contentBase64.slice(0, Math.min(contentBase64.length, 32)))

    await authorizeHotel(req, hotelId)

    const providerErrors: string[] = []
    const azureConfigured = Boolean(env('AZURE_DOCUMENT_INTELLIGENCE_ENDPOINT') && env('AZURE_DOCUMENT_INTELLIGENCE_KEY'))

    // Accuracy-first fan-out: a structured ID model plus both existing OCR engines
    // run in parallel. The pure consensus layer rejects conflicts instead of
    // silently binding a plausible-but-wrong identity to the guest.
    const providerTasks = [
      analyzeWithAzure(contentBase64, requestedType).catch(() => { providerErrors.push('azure'); return null }),
      analyzeWithGoogle(contentBase64, requestedType).catch(() => { providerErrors.push('google'); return null }),
      analyzeWithOcrSpace(contentBase64, mimeType, requestedType).catch(() => { providerErrors.push('ocr_space'); return null }),
    ]
    const candidates = (await Promise.all(providerTasks)).filter(Boolean) as any[]

    const analysis = finalizeCandidates(candidates, requestedType)
    if (!azureConfigured && analysis.reviewRequired) {
      analysis.message = 'StayQR could not confirm every identity field with enough confidence. A dedicated ID model is not configured yet; review the scan or enter the details manually.'
    }

    return json(200, {
      ok: true,
      analysis,
      provider_readiness: {
        azure: azureConfigured,
        google: Boolean(env('GOOGLE_VISION_API_KEY') || env('GOOGLE_CLOUD_VISION_API_KEY')),
        ocr_space: Boolean(env('OCR_SPACE_API_KEY')),
      },
      provider_failures: providerErrors,
    })
  } catch (error) {
    const message = error instanceof Error ? error.message : ''
    if (message === 'Unauthorized') return json(401, { ok: false, error: 'Authentication required.' })
    if (message === 'Forbidden') return json(403, { ok: false, error: 'You do not have access to this hotel.' })
    return json(502, { ok: false, error: safeErrorMessage(error) })
  }
})
