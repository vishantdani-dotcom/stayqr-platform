import fs from 'node:fs'
import path from 'node:path'

const root = process.cwd()
const read = (p) => fs.readFileSync(path.join(root, p), 'utf8')
const src = {
  rev35: read('src/finalRev35TwoFix.js'),
  rev36: read('src/finalRev36LoginVisibility.js'),
  auth: read('src/pages/auth/AuthAction.jsx'),
  login: read('src/pages/auth/Login.jsx'),
  loginCss: read('src/pages/auth/Login.css'),
  staff: read('src/pages/staff/StaffManagement.jsx'),
  staffCss: read('src/pages/staff/StaffManagement.css'),
  ocr: read('src/lib/idDocumentIntelligence.js'),
  checkin: read('src/pages/checkin/CheckIn.jsx'),
  guide: read('src/pages/guestguide/GuestGuide.jsx'),
  guideCss: read('src/pages/guestguide/GuestGuide.css'),
  navbar: read('src/components/navbar/Navbar.jsx'),
  app: read('src/App.jsx'),
}

const checks = []
function check(name, condition) { checks.push({name, pass:Boolean(condition)}) }

check('Desktop login does not inject sq35 mobile motion', /max-width:\s*900px/.test(src.rev35) && /!login\s*\|\|\s*!mobileViewport/.test(src.rev35))
check('Desktop login does not inject sq36 mobile overlay', /max-width:\s*900px/.test(src.rev36) && /!isLoginPage\(\)\s*\|\|\s*!mobileViewport/.test(src.rev36))
check('Decorative login card no longer says ROOM 101', !/ROOM\s*101/i.test(src.rev35) && !/ROOM\s*101/i.test(src.rev36))
check('Decorative login card is staff-scoped', /HOTEL STAFF/.test(src.rev35) && /SECURE STAFF ACCESS/i.test(src.rev36))

check('Main login already has show password', /aria-label=\{showPassword \? ['"]Hide password['"] : ['"]Show password['"]\}/.test(src.login))
check('Main signup already has show confirm password', /aria-label=\{showConfirmPassword \? ['"]Hide password['"] : ['"]Show password['"]\}/.test(src.login))
check('Staff invitation/recovery has show password state', /showPassword/.test(src.auth) && /showConfirmPassword/.test(src.auth))
check('Staff invitation/recovery toggles password visibility', /type=\{showPassword \? ['"]text['"] : ['"]password['"]\}/.test(src.auth))
check('Staff invitation/recovery toggles confirm visibility', /type=\{showConfirmPassword \? ['"]text['"] : ['"]password['"]\}/.test(src.auth))
check('Staff invitation/recovery uses final dark-gold surface', /sq-auth-action-page/.test(src.auth) && /#06080b/.test(src.loginCss) && /#e8bd45/.test(src.loginCss))

for (const label of ['Staff','Role','Identity','Status','Accepted','Actions']) {
  check(`Staff mobile row includes ${label} label`, new RegExp(`data-label=["']${label}["']`).test(src.staff))
}
check('Staff mobile table converts to cards', /staff mobile readability lock/i.test(src.staffCss) && /\.staff-table thead\{display:none!important\}/.test(src.staffCss))
check('Staff mobile card prevents horizontal table overflow', /\.staff-table-wrap\{[^}]*overflow:visible!important/.test(src.staffCss))
check('Staff mobile actions remain usable', /\.staff-actions\{display:grid!important/.test(src.staffCss))

check('Scanner rejects signature/truncated signature as a name', /signat\(\?:ure\)\?/.test(src.ocr) || /signat/.test(src.ocr))
check('Scanner sanitizes provider identity result', /sanitizeProviderIdentityAnalysis/.test(src.ocr))
check('Scanner cross-checks clear person-name filenames without trusting them as identity', /filenamePersonNameHint/.test(src.ocr) && /overlap === 0/.test(src.ocr))
check('Unsafe scanner result clears identity payload', /for \(const key of Object\.keys\(fields\)\) delete fields\[key\]/.test(src.ocr))
check('Unsafe scanner result clears masked document number', /safeDocumentNumberMasked = rejectedName \? null/.test(src.ocr))
check('Unsafe scanner result never auto-fills', /autoFillAllowed/.test(src.ocr) && /rejectedName/.test(src.ocr))
check('Scanner enhancement retry preserved', /OCR_RETRY_TARGET_DIMENSION/.test(src.ocr) && /retryApplied:\s*true/.test(src.ocr))
check('Scanner 45s provider/fallback window preserved', /CLIENT_OCR_TIMEOUT_MS\s*=\s*45000/.test(src.ocr))
check('Primary check-in OCR fills only blank fields', /function fillBlankField/.test(src.checkin) && /full_name:\s*fillBlankField\(current\.full_name/.test(src.checkin))
check('Companion OCR fills only blank fields', /full_name:\s*fillBlankField\(item\.full_name/.test(src.checkin))
check('Unsafe OCR is withheld from check-in form', /analysis\.autoFillAllowed === false/.test(src.checkin) && /did not auto-fill uncertain identity details/.test(src.checkin))

check('Desktop Guest Guide parity layer exists', /DESKTOP GUEST GUIDE PARITY/.test(src.guideCss) && /@media \(min-width:761px\)/.test(src.guideCss))
check('Desktop Guest Guide uses approved black base', /--ag-black:#06080b!important/.test(src.guideCss))
check('Desktop Guest Guide uses approved panel color', /--ag-card:#0f141a!important/.test(src.guideCss))
check('Desktop Guest Guide uses approved gold', /--ag-gold:#e8bd45!important/.test(src.guideCss) && /--ag-gold-light:#f7d76f!important/.test(src.guideCss))
check('Desktop Guest Guide keeps dashboard-managed hero media', /background-image:var\(--ag-hero-image,none\)!important/.test(src.guideCss))
check('Mobile Guest Guide rules remain present', /@media\s*\(max-width:\s*760px\)/.test(src.guideCss))

check('REV50 notification tone preserved', /New hotel activity/.test(src.navbar))
check('REV50 live payable preserved', /in active dining orders/.test(src.guide))
check('REV50 logout preserved', /Logout from StayQR\?/.test(src.app))

let failed = 0
for (const item of checks) {
  console.log(`${item.pass ? 'PASS' : 'FAIL'} ${item.name}`)
  if (!item.pass) failed += 1
}
console.log(JSON.stringify({checks: checks.length, passed: checks.length - failed, failed}))
if (failed) process.exit(1)
