import fs from 'node:fs'

const path =
  'supabase/migrations/202609170119_housekeeping_service_routing_fix_REV1.sql'
const sql = fs.readFileSync(path, 'utf8')

const checks = [
  ['migration_exists', fs.existsSync(path)],
  ['migration_118_required', sql.includes('day118_role_can_receive_notification')],
  ['housekeeping_builtin_fixed', sql.includes("in ('housekeeping', 'towel')") && sql.includes("department = 'housekeeping'")],
  ['checkout_builtin_fixed', sql.includes("v_code = 'checkout-request'") && sql.includes("'front_office'")],
  ['future_guard_trigger', sql.includes('day119_normalize_builtin_service_department')],
  ['open_requests_reconciled', sql.includes("sr.status not in ('completed', 'cancelled')")],
  ['restaurant_food_lock_asserted', sql.includes('restaurant_food_locked')],
  ['restaurant_housekeeping_block_asserted', sql.includes('restaurant_housekeeping_blocked')],
  ['housekeeping_allow_asserted', sql.includes('housekeeping_housekeeping_allowed')],
  ['dashboard_lock_asserted', sql.includes('dashboard_global_observer_locked')],
  ['no_day118_helper_replace', !/create\s+or\s+replace\s+function\s+private\.day118_role_can_receive_notification/i.test(sql)],
  ['no_navbar_change_in_migration', !sql.includes('Navbar.jsx')],
  ['no_push_worker_change', !sql.includes('stayqr-sw.js') && !sql.includes('backgroundPush.js')],
  ['transactional', /\bbegin;\s/i.test(sql) && /\bcommit;\s/i.test(sql)],
  ['final_marker', sql.includes('HOUSEKEEPING_SERVICE_ROUTING_REV1_PASSED')],
]

let failed = 0
for (const [name, passed] of checks) {
  if (!passed) failed += 1
  console.log(`${passed ? 'PASS' : 'FAIL'} ${name}`)
}
console.log(`\nHousekeeping routing REV1: ${checks.length - failed}/${checks.length} passed.`)
if (failed) process.exit(1)
