import fs from 'node:fs'
import path from 'node:path'

const root = process.cwd()
const read = (p) => fs.readFileSync(path.join(root, p), 'utf8')
const checks = []
const check = (name, passed, details = '') => checks.push({ name, passed: Boolean(passed), details })

const navbar = read('src/components/navbar/Navbar.jsx')
const sidebar = read('src/components/sidebar/Sidebar.jsx')
const app = read('src/App.jsx')
const portal = read('src/lib/guestPortal.js')
const guide = read('src/pages/guestguide/GuestGuide.jsx')
const guideCss = read('src/pages/guestguide/GuestGuide.css')
const scanner = read('src/lib/idDocumentIntelligence.js')
const simpleCapture = read('src/components/guests/SimpleGuestIdCapture.jsx')
const food = read('src/pages/food/FoodMenu.jsx')

check('Notification chime uses approved StayQR audio asset', navbar.includes('stayqr-notification.wav') && navbar.includes('playNotificationChime'))
check('Notification chime waits until inbox is primed', navbar.includes('notificationInboxPrimedRef.current && newUnreadItems.length > 0'))
check('Initial historical unread notifications do not chime', navbar.includes('notificationInboxPrimedRef.current = false') && navbar.includes('seenNotificationIdsRef.current = new Set()'))
check('Notification alert uses recipient-scoped trusted inbox', navbar.includes('getNotificationInbox') && navbar.includes('recipient-scoped'))
check('No forced browser notification permission prompt', !navbar.includes('requestPermission('))
check('Explicit sidebar logout exists', sidebar.includes('className="sidebar-logout"') && sidebar.includes('onClick={onLogout}'))
check('Central logout signs out Supabase session', app.includes('await supabase.auth.signOut()'))
check('Logout clears tenant context', app.includes('clearSelectedTenantHotel()') && app.includes('clearTenantContextCache()'))
check('Guest food orders can be queried from guest path', portal.includes("export async function getGuestFoodOrders(root = 'food')") && portal.includes('requireGuestAccess(root)'))
check('Guest Guide polls pending dining total', guide.includes("getGuestFoodOrders('guest')") && guide.includes('FINANCIAL_RECHECK_INTERVAL_MS = 10000'))
check('Guest Guide live payable includes pending dining', guide.includes('livePayableBalance = Math.max(0, balance + pendingDiningAmount)'))
check('UPI amount uses live payable balance', guide.includes("livePayableBalance.toFixed(2)"))
check('Pending dining avoids cancelled/delivered double count', guide.includes("!['cancelled', 'delivered'].includes"))
check('Payment note identifies active dining amount', guide.includes('in active dining orders') && guideCss.includes('.ag-balance em'))
check('Scanner timeout allows provider fallback latency', scanner.includes('CLIENT_OCR_TIMEOUT_MS = 45000'))
check('Scanner creates one enhanced OCR retry variant', scanner.includes('createEnhancedOcrVariant') && scanner.includes('retryApplied: true'))
check('Scanner enhancement is limited to image inputs', scanner.includes('String(file?.type || "").startsWith("image/")'))
check('Scanner chooses stronger OCR result', scanner.includes('analysisSignalScore(retryAnalysis) > analysisSignalScore(firstAnalysis)'))
check('Scanner UI discloses automatic enhancement retry', simpleCapture.includes('Image enhancement retry applied automatically.'))
check('Guest Guide approved UI lock marker remains', guide.includes('stayqr-rev46-functional-uiux-lock'))
check('Food Menu approved UI lock marker remains', food.includes('stayqr-rev46-functional-uiux-lock'))

let pass = 0
for (const item of checks) {
  if (item.passed) pass += 1
  console.log(`${item.passed ? 'PASS' : 'FAIL'} ${String(pass).padStart(2, '0')} | ${item.name}${item.details ? ` | ${item.details}` : ''}`)
}
const failed = checks.length - pass
console.log(`REV50_OPERATIONS_RELIABILITY_SOURCE_ACCEPTANCE: ${failed === 0 ? 'PASS' : 'FAIL'} (${pass}/${checks.length})`)
if (failed) process.exit(1)
