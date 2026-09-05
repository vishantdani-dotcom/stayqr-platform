import fs from 'node:fs'
import path from 'node:path'

const root = process.cwd()
const failures = []
let passed = 0

function check(name, condition) {
  if (condition) {
    passed += 1
    console.log(`PASS ${String(passed).padStart(2, '0')} · ${name}`)
  } else {
    failures.push(name)
  }
}

function read(file) {
  const full = path.join(root, file)
  check(`${file} exists`, fs.existsSync(full))
  return fs.existsSync(full) ? fs.readFileSync(full, 'utf8') : ''
}

function contains(name, source, token) {
  check(`${name} contains ${token}`, source.includes(token))
}

const migration = read('supabase/migrations/202609020104_pilot_manual_billing_REV1.sql')
const staging = read('supabase/staging/202609020104_pilot_manual_billing_STAGING_ACCEPTANCE_REV1.sql')
const stagingSmoke = read('supabase/staging/202609020104_pilot_manual_billing_TRANSACTIONAL_SMOKE_REV1.sql')
const rollback = read('supabase/rollback/202609020104_pilot_manual_billing_ROLLBACK_REV1.sql')
const control = read('src/lib/commercialControl.js')
const workspace = read('src/lib/commercialReady.js')
const superAdmin = read('src/pages/superadmin/SuperAdmin.jsx')
const ownerBilling = read('src/pages/billing/OwnerBilling.jsx')
const docs = read('docs/pilot-manual-billing-rev1.md')

contains('migration', migration, 'subscription_manual_payments')
contains('migration', migration, 'record_manual_subscription_payment')
contains('migration', migration, 'get_manual_subscription_payments')
contains('migration', migration, 'private.is_platform_admin()')
contains('migration', migration, 'private.user_has_hotel_access(hotel_id)')
contains('migration', migration, 'prevent_immutable_event_mutation_20260728')
contains('migration', migration, 'uq_subscription_manual_payments_idempotency')
contains('migration', migration, 'uq_subscription_manual_payments_reference')
contains('migration', migration, "payment_method in ('upi', 'bank_transfer', 'cash', 'other')")
contains('migration', migration, "'manual_payment_recorded'")
contains('migration', migration, 'public.activate_paid_subscription')
contains('migration', migration, 'public.renew_hotel_subscription')
check('Manual-payment amount must be positive', migration.includes('amount_minor > 0') && migration.includes('v_amount <= 0'))
check('Manual-payment period must be valid', migration.includes('period_end > period_start') && migration.includes('v_period_end <= v_period_start'))
check('Migration enables RLS', migration.includes('alter table public.subscription_manual_payments enable row level security'))
check('Migration never disables RLS', !migration.toLowerCase().includes('disable row level security'))
check('Migration is transactional', migration.startsWith('begin;') && migration.trimEnd().endsWith('commit;'))
check('Manual path never calls a Cashfree Edge Function', !migration.includes('cashfree-recurring') && !superAdmin.includes("recordManualSubscriptionPayment({ body"))

contains('commercial control', control, 'recordManualSubscriptionPayment')
contains('commercial control', control, 'get_manual_subscription_payments')
contains('owner workspace loader', workspace, 'manual_payments')
contains('Super Admin', superAdmin, 'Record offline payment &amp; activate / renew')
contains('Super Admin', superAdmin, 'payment_reference')
contains('Super Admin', superAdmin, 'It does not contact Cashfree.')
contains('Super Admin', superAdmin, 'Confirmed offline payments')
contains('owner billing', ownerBilling, 'Manual / offline billing')
contains('owner billing', ownerBilling, 'Online AutoPay')
contains('owner billing', ownerBilling, 'manualPayments')
contains('staging acceptance', staging, 'PILOT_MANUAL_BILLING_STAGING_ACCEPTANCE')
contains('staging smoke', stagingSmoke, 'public.record_manual_subscription_payment')
check('Staging smoke always rolls back', stagingSmoke.trimEnd().endsWith('rollback;'))
contains('rollback', rollback, 'Refusing rollback because manual payment evidence exists')
contains('documentation', docs, 'Production remains untouched')

if (failures.length) {
  console.error(`\nPILOT_MANUAL_BILLING_SOURCE_VALIDATION: FAIL (${passed} passed / ${failures.length} failed)`)
  for (const failure of failures) console.error(`FAIL · ${failure}`)
  process.exit(1)
}

console.log(`\nPILOT_MANUAL_BILLING_SOURCE_VALIDATION: PASS (${passed}/${passed})`)
