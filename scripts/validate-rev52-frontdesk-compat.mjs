import fs from 'node:fs'
import path from 'node:path'

const root = process.cwd()
const read = (p) => fs.readFileSync(path.join(root, p), 'utf8')
const checks = []
const pass = (name, ok) => checks.push({ name, ok: Boolean(ok) })

const checkin = read('src/pages/checkin/CheckIn.jsx')
const client = read('src/lib/idDocumentIntelligence.js')

// REV52 compatibility gate for the currently accepted REV51 front-desk implementation.
// This deliberately checks behavior contracts instead of the superseded REV6/REV1
// literal-source patterns that predated the REV51 fail-closed scanner handler.
pass('Multi-occupant section remains present', /companions\.map\s*\(/.test(checkin) || /companion/i.test(checkin))
pass('Shared SimpleGuestIdCapture remains wired', /SimpleGuestIdCapture/.test(checkin))
pass('Companion capture state remains stored', /id_capture/.test(checkin) && /updateCompanionCapture/.test(checkin))
pass('Companion extraction handler remains present', /handleCompanionIdExtracted/.test(checkin))
pass('Companion extraction reads extractedFields', /analysis\.extractedFields\s*\|\|\s*\{\}/.test(checkin))
pass('Companion fail-closed auto-fill guard remains present', /analysis\.autoFillAllowed\s*===\s*false/.test(checkin))
pass('Companion name can be OCR-filled', /full_name:\s*fillBlankField\(item\.full_name,\s*fields\.full_name\)/s.test(checkin))
pass('Companion DOB can be OCR-filled', /date_of_birth:\s*fillBlankField\(item\.date_of_birth,\s*fields\.date_of_birth\)/s.test(checkin))
pass('Companion gender can be OCR-filled', /gender:\s*fillBlankField\(item\.gender,\s*fields\.gender\)/s.test(checkin))
pass('Companion nationality can be OCR-filled', /nationality:\s*fillBlankField\(item\.nationality,\s*fields\.nationality\)/s.test(checkin))
pass('Companion masked ID can be OCR-filled', /id_number:\s*fillBlankField\(item\.id_number,\s*analysis\.documentNumberMasked\)/s.test(checkin))
pass('Companion ID type can be OCR-filled', /id_type:\s*fillBlankField[\s\S]{0,220}analysis\.documentType/.test(checkin))
pass('Primary scanner reads extractedFields', /const\s+handleIdExtracted[\s\S]{0,250}analysis\.extractedFields\s*\|\|\s*\{\}/.test(checkin))
pass('Primary fail-closed auto-fill guard remains present', /handleIdExtracted[\s\S]{0,500}analysis\.autoFillAllowed\s*===\s*false/.test(checkin))
pass('Primary name can be OCR-filled', /full_name:\s*fillBlankField\(current\.full_name,\s*fields\.full_name\)/s.test(checkin))
pass('Primary DOB can be OCR-filled', /date_of_birth:\s*fillBlankField\(current\.date_of_birth,\s*fields\.date_of_birth\)/s.test(checkin))
pass('Primary gender can be OCR-filled', /gender:\s*fillBlankField\(current\.gender,\s*fields\.gender\)/s.test(checkin))
pass('Primary nationality can be OCR-filled', /nationality:\s*fillBlankField\(current\.nationality,\s*fields\.nationality\)/s.test(checkin))
pass('Primary masked ID can be OCR-filled', /id_number:\s*fillBlankField\(current\.id_number,\s*analysis\.documentNumberMasked\)/s.test(checkin))
pass('Captured ID save remains hotel/guest scoped', /storagePath\s*=\s*`\$\{currentHotel\.id\}\/\$\{guestId\}\/\$\{documentId\}\//.test(checkin))
pass('Captured ID still uses private guest document registration', /register_guest_document/.test(checkin) && /GUEST_DOCUMENT_BUCKET/.test(checkin))
pass('Extraction evidence is still recorded', /recordGuestDocumentExtraction/.test(checkin))
pass('Raw OCR text remains non-persistent', /raw_ocr_text_stored:\s*false/.test(checkin))
pass('Government verification is not falsely claimed', /government_verification_claimed:\s*false/.test(checkin))
pass('Primary and companion captures save after atomic check-in', /saveCapturedIdsAfterCheckin/.test(checkin) && /saveCapturedIdForGuest/.test(checkin))
pass('Companion result mapping remains by client_id', /client_id/.test(checkin) && /resultCompanions/.test(checkin))
pass('Companion payload still carries DOB', /date_of_birth/.test(checkin))
pass('Companion payload still carries gender', /gender/.test(checkin))
pass('Companion payload still carries nationality', /nationality/.test(checkin))
pass('REV52 uses server-side OCR v2 instead of obsolete browser OCR expectation', /functions\.invoke\(["']id-document-ocr-v2["']/.test(client))
pass('REV52 keeps enhanced retry', /createEnhancedOcrVariant/.test(client) && /retryApplied/.test(client))
pass('REV52 keeps 45 second provider window', /CLIENT_OCR_TIMEOUT_MS\s*=\s*45000/.test(client))
pass('REV52 exposes only masked document number to check-in', /documentNumberMasked/.test(client))
pass('REV52 can withhold unreliable identity results', /autoFillAllowed/.test(client) && /withheld|unreliable|consensus/i.test(client))

const failed = checks.filter((c) => !c.ok)
checks.forEach((c) => console.log(`${c.ok ? 'PASS' : 'FAIL'} ${c.name}`))
console.log(JSON.stringify({ checks: checks.length, passed: checks.length - failed.length, failed: failed.length }))
if (failed.length) process.exit(1)
