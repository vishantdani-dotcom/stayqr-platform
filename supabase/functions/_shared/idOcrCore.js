const AADHAAR_RE = /\b(\d{4})[\s.-]?(\d{4})[\s.-]?(\d{4})\b/g
const PAN_RE = /\b[A-Z]{5}\d{4}[A-Z]\b/i
const VOTER_RE = /\b[A-Z]{3}\d{7}\b/i
const DATE_RE = /\b([0-3]?\d)[\s./-]+([01]?\d)[\s./-]+((?:19|20)\d{2})\b/
const YEAR_RE = /\b(?:YOB|YEAR OF BIRTH)\s*[:.-]?\s*((?:19|20)\d{2})\b/i
const NAME_NOISE = /government|govt\.?|india|bharat|aadhaar|aadhar|uidai|unique identification|income tax|department|date of birth|\bdob\b|\byob\b|male|female|address|father|mother|signature|signat|passport|republic|driving|licen[cs]e|election|commission|authority|number|\bno\b|issue|issued|valid|verified|download|document|identity|support|update|enrolment|vid\b|help|www\.|http|toll\s*free|permanent account/i
const ADDRESS_SIGNAL = /\b(?:road|rd\.?|street|st\.?|lane|nagar|colony|sector|ward|village|gaon|taluka|tehsil|district|dist\.?|state|near|opp(?:osite)?|behind|apartment|flat|house|plot|floor|post|po\b|pin(?:code)?|maharashtra|madhya pradesh|uttar pradesh|delhi|karnataka|tamil nadu|telangana|gujarat|rajasthan|punjab|haryana|bihar|odisha|west bengal|kerala|goa)\b/i

export function normalizeSpace(value) {
  return String(value || '').replace(/\s+/g, ' ').trim()
}

function titleCase(value) {
  return normalizeSpace(value).toLowerCase().replace(/\b([a-z])/g, (m) => m.toUpperCase())
}

function normalizeName(value) {
  return normalizeSpace(value).replace(/[^A-Za-z .'-]/g, ' ')
}

function nameTokens(value) {
  return normalizeName(value).toLowerCase().split(/\s+/).filter((x) => x.length >= 2)
}

function looksLikeName(value) {
  const text = normalizeSpace(value)
  if (text.length < 4 || text.length > 70) return false
  if (!/^[A-Za-z][A-Za-z .'-]+$/.test(text)) return false
  if (NAME_NOISE.test(text)) return false
  const tokens = nameTokens(text)
  return tokens.length >= 2 && tokens.length <= 6
}

function sameName(a, b) {
  const left = new Set(nameTokens(a))
  const right = new Set(nameTokens(b))
  if (!left.size || !right.size) return false
  let overlap = 0
  for (const token of left) if (right.has(token)) overlap += 1
  return overlap / Math.max(left.size, right.size) >= 0.6
}

function toIsoDate(value) {
  const raw = normalizeSpace(value)
  if (/^\d{4}-\d{2}-\d{2}$/.test(raw)) {
    const date = new Date(`${raw}T00:00:00Z`)
    if (!Number.isNaN(date.valueOf())) return raw
  }
  const match = raw.match(DATE_RE)
  if (!match) return ''
  const day = String(match[1]).padStart(2, '0')
  const month = String(match[2]).padStart(2, '0')
  const year = match[3]
  const iso = `${year}-${month}-${day}`
  const date = new Date(`${iso}T00:00:00Z`)
  if (Number.isNaN(date.valueOf())) return ''
  if (date.getUTCFullYear() !== Number(year) || date.getUTCMonth() + 1 !== Number(month) || date.getUTCDate() !== Number(day)) return ''
  return iso
}

function parseGender(value) {
  const raw = normalizeSpace(value).toUpperCase()
  if (/^(?:F|FEMALE)$/.test(raw) || /\bFEMALE\b/.test(raw)) return 'female'
  if (/^(?:M|MALE)$/.test(raw) || /\bMALE\b/.test(raw)) return 'male'
  if (/^(?:X|OTHER|TRANSGENDER)$/.test(raw) || /\bTRANSGENDER\b/.test(raw)) return 'other'
  return ''
}

function maskGeneric(value) {
  const raw = normalizeSpace(value).toUpperCase().replace(/\s+/g, '')
  if (raw.length < 4) return ''
  return `${'•'.repeat(Math.min(8, Math.max(4, raw.length - 4)))}${raw.slice(-4)}`
}

const d = [
  [0,1,2,3,4,5,6,7,8,9],[1,2,3,4,0,6,7,8,9,5],[2,3,4,0,1,7,8,9,5,6],[3,4,0,1,2,8,9,5,6,7],[4,0,1,2,3,9,5,6,7,8],
  [5,9,8,7,6,0,4,3,2,1],[6,5,9,8,7,1,0,4,3,2],[7,6,5,9,8,2,1,0,4,3],[8,7,6,5,9,3,2,1,0,4],[9,8,7,6,5,4,3,2,1,0],
]
const p = [
  [0,1,2,3,4,5,6,7,8,9],[1,5,7,6,2,8,3,0,9,4],[5,8,0,3,7,9,6,1,4,2],[8,9,1,6,0,4,3,5,2,7],
  [9,4,5,3,1,2,6,8,7,0],[4,2,8,6,5,7,3,9,0,1],[2,7,9,3,8,0,6,4,1,5],[7,0,4,6,9,1,3,2,5,8],
]

export function isValidAadhaar(value) {
  const digits = String(value || '').replace(/\D/g, '')
  if (!/^\d{12}$/.test(digits)) return false
  let c = 0
  const reversed = digits.split('').reverse()
  for (let i = 0; i < reversed.length; i += 1) c = d[c][p[i % 8][Number(reversed[i])]]
  return c === 0
}

function cleanDocumentNumber(value, type) {
  const raw = normalizeSpace(value).toUpperCase()
  if (!raw) return { full: '', masked: '', valid: false }
  if (type === 'aadhaar') {
    const digits = raw.replace(/\D/g, '')
    if (!isValidAadhaar(digits)) return { full: '', masked: '', valid: false }
    return { full: digits, masked: `XXXX XXXX ${digits.slice(-4)}`, valid: true }
  }
  if (type === 'pan') {
    const value2 = raw.replace(/\s+/g, '')
    if (!PAN_RE.test(value2)) return { full: '', masked: '', valid: false }
    return { full: value2, masked: `${value2.slice(0,5)}••••${value2.slice(-1)}`, valid: true }
  }
  if (type === 'voter_id') {
    const value2 = raw.replace(/\s+/g, '')
    if (!VOTER_RE.test(value2)) return { full: '', masked: '', valid: false }
    return { full: value2, masked: maskGeneric(value2), valid: true }
  }
  if (type === 'passport') {
    const value2 = raw.replace(/[^A-Z0-9]/g, '')
    if (value2.length < 6 || value2.length > 12 || !/[0-9]/.test(value2)) return { full: '', masked: '', valid: false }
    return { full: value2, masked: maskGeneric(value2), valid: true }
  }
  if (type === 'driving_licence') {
    const value2 = raw.replace(/[^A-Z0-9-]/g, '')
    if (value2.length < 8 || value2.length > 22 || !/[0-9]/.test(value2)) return { full: '', masked: '', valid: false }
    return { full: value2, masked: maskGeneric(value2), valid: true }
  }
  return { full: '', masked: '', valid: false }
}

function inferType(text, requested = 'auto', providerDocType = '') {
  if (requested && requested !== 'auto') return requested
  const upper = String(text || '').toUpperCase()
  const dt = String(providerDocType || '').toLowerCase()
  if (dt.includes('passport') || /P<[A-Z]{3}/.test(upper) || /\bPASSPORT\b/.test(upper)) return 'passport'
  if (/PERMANENT ACCOUNT NUMBER|INCOME TAX DEPARTMENT/.test(upper) || PAN_RE.test(upper)) return 'pan'
  if (/AADHAAR|AADHAR|UNIQUE IDENTIFICATION AUTHORITY/.test(upper)) return 'aadhaar'
  if (/DRIVING LICEN[CS]E|TRANSPORT DEPARTMENT|\bDL\s*NO/.test(upper) || dt.includes('driver')) return 'driving_licence'
  if (/ELECTION COMMISSION|ELECTOR PHOTO IDENTITY|\bEPIC\b/.test(upper)) return 'voter_id'
  if (dt.includes('nationalidentity')) return 'other'
  return 'other'
}

function extractAddress(lines) {
  let start = lines.findIndex((line) => /^(?:address|पता)\s*[:.-]?/i.test(line))
  if (start < 0) start = lines.findIndex((line) => /^(?:c\/?o|s\/?o|d\/?o|w\/?o)\b/i.test(line))
  if (start < 0) return ''
  const parts = []
  for (let i = start; i < Math.min(lines.length, start + 8); i += 1) {
    let line = normalizeSpace(lines[i]).replace(/^(?:address|पता)\s*[:.-]?\s*/i, '')
    if (!line) continue
    if (/\b(?:dob|date of birth|male|female|aadhaar|vid|signature|verified)\b/i.test(line)) break
    if (AADHAAR_RE.test(line)) break
    AADHAAR_RE.lastIndex = 0
    parts.push(line)
  }
  const combined = normalizeSpace(parts.join(', ')).slice(0, 260)
  if (combined.length < 10) return ''
  if (!ADDRESS_SIGNAL.test(combined) && !/\b[1-9]\d{5}\b/.test(combined) && parts.length < 2) return ''
  return combined
}

function parseMrzName(text) {
  const line = String(text || '').split(/\r?\n/).map((x) => x.trim()).find((x) => /^P<[A-Z]{3}/.test(x.toUpperCase()))
  if (!line) return ''
  const body = line.slice(5).split('<<')
  if (body.length < 2) return ''
  const surname = body[0].replace(/</g, ' ')
  const given = body[1].replace(/</g, ' ')
  const combined = normalizeSpace(`${given} ${surname}`)
  return looksLikeName(combined) ? titleCase(combined) : ''
}

function probableName(lines, type, text) {
  const labelPatterns = type === 'voter_id'
    ? [/^(?:name|elector'?s? name)\s*[:.-]?\s*/i]
    : type === 'driving_licence'
      ? [/^(?:name|holder'?s? name)\s*[:.-]?\s*/i]
      : type === 'pan'
        ? [/^(?:name)\s*[:.-]?\s*/i]
        : []

  for (const pattern of labelPatterns) {
    for (let i = 0; i < lines.length; i += 1) {
      if (!pattern.test(lines[i])) continue
      const inline = normalizeSpace(lines[i].replace(pattern, ''))
      const candidate = inline || normalizeSpace(lines[i + 1] || '')
      if (looksLikeName(candidate)) return titleCase(candidate)
    }
  }

  if (type === 'passport') {
    const mrz = parseMrzName(text)
    if (mrz) return mrz
  }

  const dateIndex = lines.findIndex((line) => /\b(?:DOB|DATE OF BIRTH|D\.O\.B\.?|YOB|YEAR OF BIRTH)\b/i.test(line) || DATE_RE.test(line))
  const searchStart = dateIndex > 0 ? Math.max(0, dateIndex - 7) : 0
  const searchEnd = dateIndex > 0 ? dateIndex : Math.min(lines.length, 15)
  const candidates = []
  for (let i = searchStart; i < searchEnd; i += 1) {
    const line = normalizeSpace(lines[i])
    if (!looksLikeName(line)) continue
    let score = 10
    if (dateIndex > 0) score += Math.max(0, 10 - (dateIndex - i))
    if (line.split(/\s+/).length >= 2) score += 6
    if (/^[A-Z .'-]+$/.test(line) && type === 'pan') score += 3
    candidates.push({ line, score })
  }
  candidates.sort((a, b) => b.score - a.score)
  return candidates[0] ? titleCase(candidates[0].line) : ''
}

function parseDob(lines, text) {
  for (const line of lines) {
    if (/\b(?:DOB|DATE OF BIRTH|D\.O\.B\.?)\b/i.test(line)) {
      const iso = toIsoDate(line)
      if (iso) return iso
    }
  }
  const yearMatch = String(text || '').match(YEAR_RE)
  if (yearMatch) return `${yearMatch[1]}-01-01`
  const any = String(text || '').match(DATE_RE)
  return any ? toIsoDate(any[0]) : ''
}

function extractNumberFromText(text, type) {
  const raw = String(text || '')
  if (type === 'aadhaar') {
    for (const match of raw.matchAll(AADHAAR_RE)) {
      const cleaned = match[0].replace(/\D/g, '')
      if (isValidAadhaar(cleaned)) return cleaned
    }
    return ''
  }
  if (type === 'pan') return raw.toUpperCase().match(PAN_RE)?.[0] || ''
  if (type === 'voter_id') return raw.toUpperCase().match(VOTER_RE)?.[0] || ''
  if (type === 'passport') {
    const mrz2 = raw.split(/\r?\n/).map((x) => x.trim()).find((x) => /^[A-Z0-9<]{30,50}$/.test(x.toUpperCase()) && !/^P</.test(x.toUpperCase()))
    if (mrz2) {
      const number = mrz2.slice(0, 9).replace(/</g, '')
      if (number.length >= 6) return number
    }
    const explicit = raw.toUpperCase().match(/(?:PASSPORT\s*(?:NO|NUMBER)?\s*[:.-]?\s*)([A-Z0-9]{6,12})/i)
    return explicit?.[1] || ''
  }
  if (type === 'driving_licence') {
    const explicit = raw.toUpperCase().match(/(?:DL\s*(?:NO|NUMBER)?|LICEN[CS]E\s*(?:NO|NUMBER)?)\s*[:.-]?\s*([A-Z0-9-]{8,22})/i)
    return explicit?.[1] || ''
  }
  return ''
}

export function candidateFromText(provider, rawText, requestedType = 'auto', providerConfidence = 0.55) {
  const text = String(rawText || '')
  const lines = text.split(/\r?\n/).map(normalizeSpace).filter(Boolean)
  const type = inferType(text, requestedType)
  const number = cleanDocumentNumber(extractNumberFromText(text, type), type)
  const fullName = probableName(lines, type, text)
  const dob = parseDob(lines, text)
  const address = extractAddress(lines)
  const gender = parseGender(text)
  const postal = address.match(/\b[1-9]\d{5}\b/)?.[0] || ''
  return {
    provider,
    structured: false,
    providerConfidence,
    documentType: type,
    extractedFields: {
      full_name: fullName,
      date_of_birth: dob,
      gender,
      address_line1: address,
      postal_code: postal,
      nationality: type === 'aadhaar' || type === 'pan' || type === 'voter_id' ? 'Indian' : '',
    },
    documentNumberFull: number.full,
    documentNumberMasked: number.masked,
    documentNumberValid: number.valid,
  }
}

function fieldContent(field) {
  if (!field || typeof field !== 'object') return ''
  if (field.valueString != null) return normalizeSpace(field.valueString)
  if (field.valueDate != null) return normalizeSpace(field.valueDate)
  if (field.valueCountryRegion != null) return normalizeSpace(field.valueCountryRegion)
  if (field.valueAddress && typeof field.valueAddress === 'object') {
    const address = field.valueAddress
    return normalizeSpace(address.formattedAddress || [address.houseNumber, address.road, address.city, address.state, address.postalCode, address.countryRegion].filter(Boolean).join(', '))
  }
  return normalizeSpace(field.content || '')
}

function fieldConfidence(field) {
  const value = Number(field?.confidence)
  return Number.isFinite(value) ? value : null
}

export function candidateFromAzure(result, requestedType = 'auto') {
  const analyze = result?.analyzeResult || result || {}
  const document = Array.isArray(analyze.documents) ? analyze.documents[0] : null
  const fields = document?.fields || {}
  const text = String(analyze.content || '')
  const type = inferType(text, requestedType, document?.docType || '')
  const first = fieldContent(fields.FirstName)
  const middle = fieldContent(fields.MiddleName)
  const last = fieldContent(fields.LastName)
  const directName = fieldContent(fields.Name)
  const combined = normalizeSpace([first, middle, last].filter(Boolean).join(' '))
  const fullName = looksLikeName(directName) ? titleCase(directName) : (looksLikeName(combined) ? titleCase(combined) : probableName(text.split(/\r?\n/).map(normalizeSpace).filter(Boolean), type, text))
  const dob = toIsoDate(fieldContent(fields.DateOfBirth)) || parseDob(text.split(/\r?\n/), text)
  const gender = parseGender(fieldContent(fields.Sex) || text)
  const address = fieldContent(fields.Address) || extractAddress(text.split(/\r?\n/).map(normalizeSpace).filter(Boolean))
  const nationalityRaw = fieldContent(fields.Nationality) || fieldContent(fields.CountryRegion)
  const nationality = nationalityRaw ? (nationalityRaw.toUpperCase() === 'IND' ? 'Indian' : nationalityRaw) : (type === 'aadhaar' || type === 'pan' ? 'Indian' : '')
  const rawNumber = fieldContent(fields.DocumentNumber) || extractNumberFromText(text, type)
  const number = cleanDocumentNumber(rawNumber, type)
  const confidences = [fields.FirstName, fields.MiddleName, fields.LastName, fields.Name, fields.DateOfBirth, fields.DocumentNumber, fields.Address, fields.Sex]
    .map(fieldConfidence).filter((x) => x != null)
  const providerConfidence = confidences.length ? confidences.reduce((a,b) => a+b, 0) / confidences.length : Number(document?.confidence || 0.72)
  return {
    provider: 'azure-document-intelligence',
    structured: true,
    providerConfidence: Number.isFinite(providerConfidence) ? providerConfidence : 0.72,
    documentType: type,
    extractedFields: {
      full_name: fullName,
      date_of_birth: dob,
      gender,
      address_line1: address,
      postal_code: address.match(/\b[1-9]\d{5}\b/)?.[0] || '',
      nationality,
    },
    documentNumberFull: number.full,
    documentNumberMasked: number.masked,
    documentNumberValid: number.valid,
  }
}

function candidateCompleteness(candidate) {
  const f = candidate?.extractedFields || {}
  let score = 0
  if (f.full_name) score += 30
  if (f.date_of_birth) score += 18
  if (candidate?.documentNumberValid) score += 25
  if (f.address_line1) score += 10
  if (f.gender) score += 5
  if (f.nationality) score += 4
  if (candidate?.structured) score += 6
  score += Math.round(Math.max(0, Math.min(1, Number(candidate?.providerConfidence || 0))) * 8)
  return Math.min(100, score)
}

function identityAgrees(a, b) {
  if (!a || !b) return false
  if (a.documentType !== 'other' && b.documentType !== 'other' && a.documentType !== b.documentType) return false
  const af = a.extractedFields || {}
  const bf = b.extractedFields || {}
  if (a.documentNumberFull && b.documentNumberFull && a.documentNumberFull === b.documentNumberFull) {
    if (af.full_name && bf.full_name && !sameName(af.full_name, bf.full_name)) return false
    return true
  }
  if (af.full_name && bf.full_name && sameName(af.full_name, bf.full_name)) {
    if (af.date_of_birth && bf.date_of_birth) return af.date_of_birth === bf.date_of_birth
    return true
  }
  return false
}

function coreReady(candidate) {
  const f = candidate?.extractedFields || {}
  if (!f.full_name) return false
  switch (candidate?.documentType) {
    case 'aadhaar': return Boolean(f.date_of_birth && candidate.documentNumberValid)
    case 'pan': return Boolean(f.date_of_birth && candidate.documentNumberValid)
    case 'passport': return Boolean(f.date_of_birth && candidate.documentNumberValid)
    case 'driving_licence': return Boolean(candidate.documentNumberValid)
    case 'voter_id': return Boolean(candidate.documentNumberValid)
    default: return false
  }
}

function mergeMissing(base, other) {
  if (!identityAgrees(base, other)) return base
  const next = { ...base, extractedFields: { ...(base.extractedFields || {}) } }
  for (const key of ['full_name','date_of_birth','gender','address_line1','postal_code','nationality']) {
    if (!next.extractedFields[key] && other.extractedFields?.[key]) next.extractedFields[key] = other.extractedFields[key]
  }
  if (!next.documentNumberFull && other.documentNumberFull) {
    next.documentNumberFull = other.documentNumberFull
    next.documentNumberMasked = other.documentNumberMasked
    next.documentNumberValid = other.documentNumberValid
  }
  return next
}

export function finalizeCandidates(inputCandidates = [], requestedType = 'auto') {
  const candidates = inputCandidates.filter(Boolean).map((candidate) => ({ ...candidate, baseScore: candidateCompleteness(candidate) }))
  if (!candidates.length) {
    return {
      status: 'review_required', method: 'provider_unavailable', provider: 'none', documentType: requestedType === 'auto' ? 'other' : requestedType,
      extractedFields: {}, documentNumberMasked: null, qualityScore: 0, reviewRequired: true, qualityReasons: ['No OCR provider returned a usable result'],
      identityConsensus: 'none', providerStructured: false, rawOcrTextStored: false, rawQrPayloadStored: false,
      message: 'StayQR could not read this ID reliably. Enter the guest details manually or try a clearer photo.',
    }
  }

  candidates.sort((a,b) => b.baseScore - a.baseScore)
  let best = candidates[0]
  let consensus = 'single'
  const agreeing = candidates.filter((candidate, index) => index > 0 && identityAgrees(best, candidate))
  if (best.structured && Number(best.providerConfidence || 0) >= 0.70 && coreReady(best)) consensus = 'strong'
  else if (agreeing.length > 0) consensus = 'strong'
  else if (candidates.length > 1) consensus = 'low'

  for (const candidate of agreeing) best = mergeMissing(best, candidate)

  const reasons = []
  const score = Math.min(100, candidateCompleteness(best) + (consensus === 'strong' ? 8 : consensus === 'low' ? -12 : 0))
  if (!best.extractedFields?.full_name) reasons.push('name was not read reliably')
  if (!best.documentNumberValid && best.documentType !== 'other') reasons.push('document number could not be validated')
  if ((best.documentType === 'aadhaar' || best.documentType === 'pan' || best.documentType === 'passport') && !best.extractedFields?.date_of_birth) reasons.push('date of birth was not read reliably')
  if (consensus === 'low') reasons.push('OCR providers did not agree strongly enough')
  if (best.documentType === 'other') reasons.push('document type was not recognized')

  const ready = coreReady(best) && score >= 72 && consensus !== 'low'
  return {
    status: ready ? 'extracted' : 'review_required',
    method: best.structured ? 'structured_id_model' : 'multi_provider_ocr',
    provider: best.provider,
    providerStructured: Boolean(best.structured),
    identityConsensus: consensus,
    documentType: best.documentType,
    extractedFields: Object.fromEntries(Object.entries(best.extractedFields || {}).filter(([,value]) => Boolean(value))),
    documentNumberMasked: best.documentNumberMasked || null,
    qualityScore: Math.max(0, score),
    reviewRequired: !ready,
    qualityReasons: reasons,
    rawOcrTextStored: false,
    rawQrPayloadStored: false,
    message: ready
      ? 'ID details extracted. Review them before saving the guest.'
      : 'StayQR could not confirm every identity field with enough confidence. Review the scan before saving.',
  }
}
