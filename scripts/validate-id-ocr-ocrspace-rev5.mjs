import fs from 'node:fs'

const file = 'supabase/functions/id-document-ocr/index.ts'
const src = fs.readFileSync(file, 'utf8')
const checks = [
  ['supports OCR.Space provider', src.includes("provider === 'ocr_space'") && src.includes('OCR_SPACE_API_KEY')],
  ['keeps Google fallback support', src.includes("provider === 'google_vision'") && src.includes('GOOGLE_CLOUD_VISION_API_KEY')],
  ['OCR.Space key stays server-side', src.includes('OCR_SPACE_API_KEY')],
  ['uses HTTPS OCR.Space endpoint', src.includes("https://api.ocr.space/parse/image")],
  ['sends key in request header', src.includes('apikey: ocrSpaceApiKey!')],
  ['uses fast Engine 2', src.includes("form.set('OCREngine', '2')")],
  ['enables scale and orientation', src.includes("form.set('scale', 'true')") && src.includes("form.set('detectOrientation', 'true')")],
  ['does not return raw OCR text', src.includes('raw OCR text and provider response are intentionally not returned or persisted')],
  ['preserves authentication', src.includes('userClient.auth.getUser(token)')],
  ['preserves hotel permission checks', src.includes("permissionSet.has('checkin.manage')") && src.includes("permissionSet.has('guests.manage')")],
  ['preserves masking parser', src.includes('maskSensitiveNumbers(rawText)') && src.includes('extractMaskedDocumentNumber')],
  ['has staging free-tier size guard', src.includes('OCR_SPACE_FREE_MAX_IMAGE_BYTES')],
]
let failed = 0
for (const [name, ok] of checks) {
  console.log(`${ok ? 'PASS' : 'FAIL'} ${name}`)
  if (!ok) failed++
}
console.log(JSON.stringify({ checks: checks.length, passed: checks.length - failed, failed }))
if (failed) process.exit(1)
