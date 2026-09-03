import fs from 'node:fs'
import path from 'node:path'
import process from 'node:process'
import { pathToFileURL } from 'node:url'

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
  [
    'direct browser write to manual-payment ledger',
    /\.from\(\s*['"]subscription_manual_payments['"]\s*\)[\s\S]{0,180}?\.(?:insert|update|upsert|delete)\s*\(/,
  ],
]

export function validateCommercialSources({ appSource, pageSource, apiSource }) {
  const combined = `${appSource}\n${pageSource}\n${apiSource}`
  const failures = []

  for (const [label, pattern] of required) {
    if (!pattern.test(combined)) failures.push(`Missing: ${label}`)
  }

  // Pilot Manual Billing replaced the old Cashfree-only recovery variable.
  // Check the active action and its safety boundaries, not a retired identifier.
  const actionForm = pageSource.slice(pageSource.indexOf('function HotelActionForm('))
  const manualAction = actionForm.match(/if\s*\(action === 'manual-payment'\)\s*\{([\s\S]*?)\}\s*else if/)?.[1] || ''
  const pilotRequired = [
    ['Manual payment is the default recovery action for every lifecycle', actionForm, /const defaultAction = 'manual-payment'\s+const \[action, setAction\] = useState\(defaultAction\)/],
    ['Manual payment recovery option is available', actionForm, /<option value="manual-payment">Record offline payment &amp; activate \/ renew<\/option>/],
    ['Manual payment uses the selected hotel and trusted client', manualAction, /await recordManualSubscriptionPayment\(hotel\.id,\s*\{/],
    ['Manual payment validates a positive received amount', manualAction, /if \(amountMinor <= 0\)\s*\{\s*throw new Error/],
    ['Manual payment requires a receipt reference', manualAction, /if \(paymentReference\.trim\(\)\.length < 3\)\s*\{\s*throw new Error/],
    ['Manual payment sends the receipt, paid time and idempotency key', manualAction, /payment_reference: paymentReference\.trim\(\),[\s\S]*paid_at: new Date\(paidAt\)\.toISOString\(\),[\s\S]*idempotency_key: actionKey/],
    ['Manual payment client uses the controlled RPC', apiSource, /export function recordManualSubscriptionPayment\(hotelId, payload\)\s*\{\s*return rpc\(\s*'record_manual_subscription_payment',\s*\{ p_hotel_id: hotelId, p_payload: payload \}/],
    ['Renew action is lifecycle-guarded on submission', actionForm, /else if \(action === 'renew' && canRenew\)/],
    ['Renew option is lifecycle-guarded in the UI', actionForm, /\{canRenew && <option value="renew">/],
    ['Reactivate option is limited to suspended subscriptions', actionForm, /\{lifecycle === 'suspended' && \(\s*<option value="reactivate">/],
  ]

  for (const [label, source, pattern] of pilotRequired) {
    if (!pattern.test(source)) failures.push(`Missing: ${label}`)
  }
  if (/createCashfreePaymentLink\s*\(|supabase\.functions\.invoke\s*\(/.test(manualAction)) {
    failures.push('Unsafe source detected: manual-payment recovery calls Cashfree')
  }
  for (const [label, pattern] of forbidden) {
    if (pattern.test(combined)) failures.push(`Unsafe source detected: ${label}`)
  }
  return { failures, requiredCount: required.length + pilotRequired.length, forbiddenCount: forbidden.length + 1 }
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  const root = process.cwd()
  const read = (relativePath) => fs.readFileSync(path.join(root, relativePath), 'utf8')
  const { failures, requiredCount, forbiddenCount } = validateCommercialSources({
    appSource: read('src/App.jsx'),
    pageSource: read('src/pages/superadmin/SuperAdmin.jsx'),
    apiSource: read('src/lib/commercialControl.js'),
  })
  if (failures.length) {
    console.error('FAIL — Day 9 commercial frontend source gate')
    for (const failure of failures) console.error(`- ${failure}`)
    process.exitCode = 1
  } else {
    console.log(`PASS — Day 9 commercial frontend source gate (${requiredCount} required contracts; ${forbiddenCount} unsafe patterns blocked).`)
  }
}
