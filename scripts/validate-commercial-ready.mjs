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
const cashfree = read('supabase/functions/cashfree-recurring/index.ts')
const cashfreeWebhook = read('supabase/functions/cashfree-subscription-webhook/index.ts')
const uidai = read('supabase/functions/uidai-online-auth/index.ts')
const whatsapp = read('supabase/functions/whatsapp-send/index.ts')
const config = read('supabase/config.toml')
const env = read('.env.example')

contains('src/App.jsx', app, "case 'billing'")
contains('src/App.jsx', app, 'OwnerBilling')
contains('src/components/sidebar/Sidebar.jsx', sidebar, 'Billing & AutoPay')
contains('src/lib/currentStaff.js', access, "billing: 'hotel.manage'")
contains('src/pages/dashboard/Dashboard.jsx', dashboard, 'ActivationScore')
contains('src/pages/dashboard/Dashboard.jsx', dashboard, '24×7 support')
contains('src/components/cards/ActivationScore.jsx', activation, 'HOTEL ACTIVATION SCORE')
contains('src/components/cards/ActivationScore.jsx', activation, 'checklist')
contains('src/pages/billing/OwnerBilling.jsx', billing, 'Cashfree recurring capability')
contains('src/pages/billing/OwnerBilling.jsx', billing, 'Cashfree recurring activation is still pending')
contains('src/pages/billing/OwnerBilling.jsx', billing, 'Schedule cancellation')
contains('src/pages/billing/OwnerBilling.jsx', billing, '24×7 assistance')
contains('src/lib/commercialReady.js', billingLib, 'get_commercial_ready_workspace')
contains('src/lib/commercialReady.js', billingLib, 'request_owner_subscription_action')
contains('src/lib/commercialReady.js', billingLib, 'cashfree-recurring')
contains('src/lib/commercialReady.js', billingLib, 'uidai-online-auth')
contains('src/lib/guestCompliance.js', consent, 'aadhaar_online_authentication')
contains('src/components/guests/GuestIdentityCompliance.jsx', identity, 'Formal UIDAI online authentication')
contains('src/components/guests/GuestIdentityCompliance.jsx', identity, 'Aadhaar number, OTP and PID are never written')
contains('src/pages/operationscenter/OperationsCenter.jsx', operationsCenter, '24×7 support intake')
contains('src/pages/legal/SupportEscalationPolicy.jsx', supportPolicy, '24 hours a day, 7 days a week')
check('Legacy staffed-hours claim removed from product/legal support surfaces', !operationsCenter.includes('09:00–19:00') && !supportPolicy.includes('09:00–19:00'))
contains('migration', migration, 'platform_provider_readiness')
contains('migration', migration, 'owner_subscription_requests')
contains('migration', migration, 'subscription_recurring_attempts')
contains('migration', migration, 'uidai_online_auth_requests')
contains('migration', migration, 'get_commercial_ready_workspace')
contains('migration', migration, 'request_owner_subscription_action')
contains('migration', migration, 'configure_meta_whatsapp_provider')
contains('migration', migration, 'configure_stayqr_support_profile')
contains('migration', migration, "coverage='24x7'")
contains('migration', migration, 'provider_activation_pending')
contains('cashfree recurring function', cashfree, 'CASHFREE_SUBSCRIPTIONS_ENABLED')
contains('cashfree recurring function', cashfree, "'/subscriptions/pay'")
contains('cashfree recurring function', cashfree, '/manage')
contains('cashfree recurring function', cashfree, 'cashfree_recurring_last_evidence')
check('Cashfree function does not retain the full provider response', !cashfree.includes('cashfree_recurring_last_response'))
contains('cashfree webhook', cashfreeWebhook, 'x-webhook-signature')
contains('cashfree webhook', cashfreeWebhook, 'subscription_recurring_attempts')
contains('UIDAI online function', uidai, 'UIDAI_ONLINE_AUTH_ENABLED')
contains('UIDAI online function', uidai, 'aadhaar_sha256')
contains('UIDAI online function', uidai, 'no_aadhaar_or_otp_retained')
check('UIDAI function does not persist plaintext Aadhaar field', !uidai.includes('aadhaar_number: aadhaar,guest'))
contains('WhatsApp function', whatsapp, 'WHATSAPP_AUTOMATION_ENABLED')
contains('WhatsApp function', whatsapp, 'consent is no longer active')
contains('WhatsApp function', whatsapp, 'provider_status')
contains('Supabase config', config, '[functions.cashfree-recurring]')
contains('Supabase config', config, '[functions.cashfree-subscription-webhook]')
contains('Supabase config', config, '[functions.uidai-online-auth]')
contains('.env.example', env, 'CASHFREE_SUBSCRIPTIONS_ENABLED=false')
contains('.env.example', env, 'WHATSAPP_AUTOMATION_ENABLED=false')
contains('.env.example', env, 'UIDAI_ONLINE_AUTH_ENABLED=false')
check('No provider safety flag defaults true', !env.match(/(?:CASHFREE_SUBSCRIPTIONS_ENABLED|WHATSAPP_AUTOMATION_ENABLED|UIDAI_ONLINE_AUTH_ENABLED)=true/))
check('Migration is transactional', migration.includes('begin;') && migration.trimEnd().endsWith('commit;'))
check('Migration does not disable RLS', !migration.toLowerCase().includes('disable row level security'))
check('New tenant tables enable RLS', (migration.match(/enable row level security/g) || []).length >= 3)

if (failures.length) {
  console.error(`\nCOMMERCIAL_READY_SOURCE_VALIDATION: FAIL (${passed} passed / ${failures.length} failed)`)
  for (const failure of failures) console.error(`FAIL · ${failure}`)
  process.exit(1)
}

console.log(`\nCOMMERCIAL_READY_SOURCE_VALIDATION: PASS (${passed}/${passed})`)
