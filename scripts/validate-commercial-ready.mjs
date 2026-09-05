import fs from 'node:fs'
import path from 'node:path'

const root = process.cwd()
let passed = 0
const failures = []

function check(name, condition, detail = '') {
  if (condition) { passed += 1; console.log(`PASS ${String(passed).padStart(2, '0')} · ${name}`) }
  else failures.push(`${name}${detail ? ` — ${detail}` : ''}`)
}
function read(file) {
  const full = path.join(root, file)
  check(`${file} exists`, fs.existsSync(full))
  return fs.existsSync(full) ? fs.readFileSync(full, 'utf8') : ''
}
function contains(file, source, token) { check(`${file} contains ${token}`, source.includes(token)) }

const app = read('src/App.jsx')
const sidebar = read('src/components/sidebar/Sidebar.jsx')
const access = read('src/lib/currentStaff.js')
const dashboard = read('src/pages/dashboard/Dashboard.jsx')
const activation = read('src/components/cards/ActivationScore.jsx')
const billing = read('src/pages/billing/OwnerBilling.jsx')
const billingLib = read('src/lib/commercialReady.js')
const identity = read('src/components/guests/GuestIdentityCompliance.jsx')
const operationsCenter = read('src/pages/operationscenter/OperationsCenter.jsx')
const supportPolicy = read('src/pages/legal/SupportEscalationPolicy.jsx')
const consent = read('src/lib/guestCompliance.js')
const migration = read('supabase/migrations/202609010103_commercial_ready_final_completion_REV1.sql')
const qrMigration = read('supabase/migrations/202609050115_auto_activated_permanent_room_qr_REV1.sql')
const roomAccess = read('src/pages/roomaccess/RoomAccess.jsx')
const qrPage = read('src/pages/qr/QRGenerator.jsx')
const guestComms = read('src/pages/guests/GuestCommunications.jsx')
const env = read('.env.example')
const cashfree = read('supabase/functions/cashfree-recurring/index.ts')
const uidai = read('supabase/functions/uidai-online-auth/index.ts')
const whatsapp = read('supabase/functions/whatsapp-send/index.ts')
const index = read('index.html')
const readme = read('README.md')

contains('src/App.jsx', app, "case 'billing'")
contains('src/components/sidebar/Sidebar.jsx', sidebar, 'Subscription & Billing')
contains('src/components/sidebar/Sidebar.jsx', sidebar, 'Room QR Guides')
check('Launch sidebar has no v1.1 / NEW badges', !/v1\.1|badge:\s*['\"]NEW/i.test(sidebar))
contains('src/lib/currentStaff.js', access, "billing: 'hotel.manage'")
contains('src/pages/dashboard/Dashboard.jsx', dashboard, 'ActivationScore')
contains('src/pages/dashboard/Dashboard.jsx', dashboard, 'Submit support requests anytime')
check('Dashboard does not promise staffed 24x7 support', !/(24\s*[x×/]\s*7|24\/7)/i.test(dashboard))
contains('src/components/cards/ActivationScore.jsx', activation, 'Property ready')
contains('src/pages/billing/OwnerBilling.jsx', billing, 'Manual / offline billing')
contains('src/pages/billing/OwnerBilling.jsx', billing, 'Online AutoPay')
contains('src/pages/billing/OwnerBilling.jsx', billing, 'Upcoming')
check('Owner billing does not invoke Cashfree', !billing.includes('invokeCashfreeRecurring') && !billing.includes('Set up AutoPay'))
contains('src/lib/commercialReady.js', billingLib, 'get_commercial_ready_workspace')
contains('src/lib/commercialReady.js', billingLib, 'request_owner_subscription_action')
contains('src/components/guests/GuestIdentityCompliance.jsx', identity, 'Aadhaar OTP authentication is not part of this workflow')
contains('src/components/guests/GuestIdentityCompliance.jsx', identity, 'UIDAI Paperless Offline e-KYC verification')
contains('src/lib/guestCompliance.js', consent, 'aadhaar_online_authentication')
contains('src/pages/operationscenter/OperationsCenter.jsx', operationsCenter, 'Support requests can be submitted anytime')
contains('src/pages/legal/SupportEscalationPolicy.jsx', supportPolicy, 'Support Availability')
check('Support policy does not claim staffed 24x7 handling', !/(24\s*[x×/]\s*7|24 hours a day|24\/7)/i.test(supportPolicy))
contains('migration', migration, 'platform_provider_readiness')
contains('migration', migration, 'owner_subscription_requests')
contains('migration', migration, 'uidai_online_auth_requests')
contains('cashfree backend foundation', cashfree, 'CASHFREE_SUBSCRIPTIONS_ENABLED')
contains('uidai backend foundation', uidai, 'UIDAI_ONLINE_AUTH_ENABLED')
contains('whatsapp backend foundation', whatsapp, 'WHATSAPP_AUTOMATION_ENABLED')
contains('.env.example', env, 'CASHFREE_SUBSCRIPTIONS_ENABLED=false')
contains('.env.example', env, 'WHATSAPP_AUTOMATION_ENABLED=false')
contains('.env.example', env, 'UIDAI_ONLINE_AUTH_ENABLED=false')
check('No external-provider launch flag defaults true', !env.match(/(?:CASHFREE_SUBSCRIPTIONS_ENABLED|WHATSAPP_AUTOMATION_ENABLED|UIDAI_ONLINE_AUTH_ENABLED)=true/))
contains('Guest communications', guestComms, 'Automated WhatsApp campaigns — upcoming')
check('Guest communications does not expose automated send action', !guestComms.includes('sendWhatsAppCampaignRecipient') && !guestComms.includes('createGuestWhatsAppCampaign'))
contains('Room access', roomAccess, 'No PIN or login is required')
check('Room access does not render a PIN form', !roomAccess.includes('6-digit stay PIN') && !roomAccess.includes('p_pin'))
contains('QR page', qrPage, 'PRINT ONCE · AUTO-ACTIVATE EVERY STAY')
contains('QR page', qrPage, 'Regenerate permanent QR')
contains('QR migration', qrMigration, 'resolve_permanent_room_qr(p_public_code uuid)')
contains('QR migration', qrMigration, 'regenerate_permanent_room_qr')
contains('QR migration', qrMigration, 'private.render_guest_access_token')
check('QR migration is transactional', qrMigration.trimStart().startsWith('begin;') && qrMigration.trimEnd().endsWith('commit;'))
check('QR migration does not disable RLS', !qrMigration.toLowerCase().includes('disable row level security'))
contains('index.html', index, 'noindex, nofollow, noarchive')
contains('README.md', readme, 'Provider hold policy')
contains('README.md', readme, 'Core QR model')

if (failures.length) {
  console.error(`\nCOMMERCIAL_READY_SOURCE_VALIDATION: FAIL (${passed} passed / ${failures.length} failed)`)
  for (const failure of failures) console.error(`FAIL · ${failure}`)
  process.exit(1)
}
console.log(`\nCOMMERCIAL_READY_SOURCE_VALIDATION: PASS (${passed}/${passed})`)
