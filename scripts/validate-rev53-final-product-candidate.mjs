import fs from 'node:fs'
import path from 'node:path'

const root = process.cwd()
const read = (p) => fs.readFileSync(path.join(root, p), 'utf8')
const exists = (p) => fs.existsSync(path.join(root, p))

const staffPath = 'src/pages/staff/StaffManagement.jsx'
const docPath = 'docs/releases/REV53_FINAL_PRODUCT_CANDIDATE.md'
const scannerPath = 'src/lib/idDocumentIntelligence.js'
const ocrCorePath = 'supabase/functions/_shared/idOcrCore.js'
const ocrFnPath = 'supabase/functions/id-document-ocr-v2/index.ts'
const soundPath = 'public/assets/stayqr-notification.wav'

const staff = exists(staffPath) ? read(staffPath) : ''
const doc = exists(docPath) ? read(docPath) : ''
const scanner = exists(scannerPath) ? read(scannerPath) : ''
const ocrCore = exists(ocrCorePath) ? read(ocrCorePath) : ''
const ocrFn = exists(ocrFnPath) ? read(ocrFnPath) : ''

const checks = [
  ['Staff page exists', exists(staffPath)],
  ['REV53 release note exists', exists(docPath)],
  ['Approved notification sound exists', exists(soundPath)],
  ['REV52 client scanner exists', exists(scannerPath)],
  ['REV52 shared OCR core exists', exists(ocrCorePath)],
  ['REV52 OCR v2 Edge Function exists', exists(ocrFnPath)],
  ['Staff error formatter exists', /function\s+formatStaffActionError\s*\(/.test(staff)],
  ['Staff function response reader exists', /function\s+readFunctionError\s*\(/.test(staff)],
  ['Staff capacity error is recognized', /Staff limit exceeded/i.test(staff)],
  ['Staff capacity message is actionable', /Staff capacity reached/.test(staff) && /Upgrade the hotel plan/.test(staff)],
  ['Staff capacity enforcement is not bypassed client-side', !/max_staff\s*=|update\([^)]*max_staff|\.from\(['"]subscription_plans['"]\)[\s\S]{0,180}\.(?:update|upsert|insert)/i.test(staff)],
  ['Staff action still uses authoritative manage-staff-user Edge Function', /functions\.invoke\(['"]manage-staff-user['"]/.test(staff)],
  ['REV52 OCR v2 route remains in client', /id-document-ocr-v2/.test(scanner)],
  ['REV52 OCR consensus remains present', /identityConsensus/.test(scanner) || /consensus/i.test(scanner)],
  ['REV52 fail-closed wording remains present', /withheld an unreliable OCR result|reviewRequired|fail.closed/i.test(scanner)],
  ['Server OCR core still contains Aadhaar validation support', /isValidAadhaar/.test(ocrCore)],
  ['Azure Document Intelligence support remains in OCR v2', /AZURE_DOCUMENT_INTELLIGENCE_ENDPOINT/.test(ocrFn) && /AZURE_DOCUMENT_INTELLIGENCE_KEY/.test(ocrFn)],
  ['Release note explicitly says OCR is not UIDAI verification', /does not claim UIDAI\/government identity verification/i.test(doc)],
  ['Cashfree AutoPay hold is documented', /Cashfree recurring\/AutoPay: HOLD/i.test(doc)],
  ['Meta automation hold is documented', /Meta\/WhatsApp automated campaigns: HOLD/i.test(doc)],
  ['UIDAI online-auth hold is documented', /UIDAI online authentication: HOLD/i.test(doc)],
  ['Manual billing remains launch mode in policy', /Manual\/offline subscription billing remains the launch billing mode/i.test(doc)],
  ['Production remains blocked in release note', /Production deployment remains blocked/i.test(doc)],
  ['No provider secret values are embedded in release note', !/(AZURE_DOCUMENT_INTELLIGENCE_KEY\s*[=:]\s*['"][^'"]+|service_role\s*[=:]\s*['"][^'"]+)/i.test(doc)],
]

let failed = 0
for (const [name, passed] of checks) {
  console.log(`${passed ? 'PASS' : 'FAIL'} ${name}`)
  if (!passed) failed += 1
}

console.log(JSON.stringify({ checks: checks.length, passed: checks.length - failed, failed }))
process.exit(failed ? 1 : 0)
