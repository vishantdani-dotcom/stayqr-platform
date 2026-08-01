import fs from 'node:fs'
import path from 'node:path'
import process from 'node:process'

const root = process.cwd()
const read = (relativePath) =>
  fs.readFileSync(path.join(root, relativePath), 'utf8')

const appSource = read('src/App.jsx')
const pageSource = read('src/pages/superadmin/SuperAdmin.jsx')
const apiSource = read('src/lib/commercialControl.js')
const combined = `${appSource}\n${pageSource}\n${apiSource}`

const required = [
  ['Super Admin route', /case\s+['"]superadmin['"]/],
  ['Controlled commercial data RPC', /get_super_admin_commercial_data/],
  ['Plan save RPC', /save_subscription_plan/],
  ['Hotel usage RPC', /get_hotel_subscription_usage/],
  ['Trial extension RPC', /extend_hotel_trial/],
  ['Suspension RPC', /suspend_hotel_subscription/],
  ['Reactivation RPC', /reactivate_hotel_subscription/],
  ['Plan-change RPC', /change_hotel_subscription_plan/],
  ['Renewal RPC', /renew_hotel_subscription/],
  ['Cancellation RPC', /cancel_hotel_subscription/],
  ['Expiry reconciliation RPC', /reconcile_expired_subscriptions/],
  ['Support creation RPC', /create_support_ticket/],
  ['Support message RPC', /add_support_ticket_message/],
  ['Support triage RPC', /update_support_ticket_status/],
  ['Safe-support start RPC', /start_safe_support_access/],
  ['Safe-support end RPC', /end_safe_support_access/],
  ['Announcement RPC', /save_platform_announcement/],
  ['Cashfree payment-link Edge Function', /cashfree-create-payment-link/],
  ['Expired lifecycle payment recovery guard', /requiresPaymentRecovery\s*=\s*\[['"]expired['"],\s*['"]cancelled['"]\]\.includes\(lifecycle\)/],
  ['Renewal eligibility matches backend contract', /canRenew\s*=\s*\[['"]active['"],\s*['"]past_due['"],\s*['"]suspended['"]\]\.includes\(lifecycle\)/],
]

const forbidden = [
  ['service-role credential in browser source', /service[_-]?role/i],
  ['Cashfree client secret in browser source', /CASHFREE_CLIENT_SECRET/],
  ['Cashfree client ID in browser source', /CASHFREE_CLIENT_ID/],
  [
    'direct browser write to subscription rows',
    /\.from\(\s*['"]hotel_subscriptions['"]\s*\)[\s\S]{0,180}?\.(?:insert|update|upsert|delete)\s*\(/,
  ],
  [
    'direct browser write to payment-link ledger',
    /\.from\(\s*['"]subscription_payment_links['"]\s*\)[\s\S]{0,180}?\.(?:insert|update|upsert|delete)\s*\(/,
  ],
  [
    'direct browser write to immutable subscription events',
    /\.from\(\s*['"]subscription_events['"]\s*\)[\s\S]{0,180}?\.(?:insert|update|upsert|delete)\s*\(/,
  ],
  [
    'direct browser write to webhook events',
    /\.from\(\s*['"]webhook_events['"]\s*\)[\s\S]{0,180}?\.(?:insert|update|upsert|delete)\s*\(/,
  ],
]

const failures = []

for (const [label, pattern] of required) {
  if (!pattern.test(combined)) failures.push(`Missing: ${label}`)
}

for (const [label, pattern] of forbidden) {
  if (pattern.test(combined)) failures.push(`Unsafe source detected: ${label}`)
}

if (failures.length) {
  console.error('FAIL — Day 9 commercial frontend source gate')
  for (const failure of failures) console.error(`- ${failure}`)
  process.exit(1)
}

console.log(
  `PASS — Day 9 commercial frontend source gate (${required.length} required contracts; ${forbidden.length} unsafe patterns blocked).`
)
