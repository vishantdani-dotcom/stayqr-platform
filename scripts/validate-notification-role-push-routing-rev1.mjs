import fs from 'node:fs'
import crypto from 'node:crypto'

const checks = []
function check(name, condition, detail = '') {
  checks.push({ name, passed: Boolean(condition), detail })
}
function read(path) {
  return fs.readFileSync(path, 'utf8')
}
function sha256(path) {
  return crypto.createHash('sha256').update(fs.readFileSync(path)).digest('hex')
}

const migrationPath = 'supabase/migrations/202609160118_notification_role_push_routing_fix_REV1.sql'
const migration = read(migrationPath)

check('01_migration_118_exists', fs.existsSync(migrationPath))
check('02_role_guard_defined', migration.includes('private.day118_role_can_receive_notification'))
check('03_restaurant_food_role_map', migration.includes("array['restaurant','kitchen','chef']"))
check('04_housekeeping_role_map', migration.includes("array['housekeeping','housekeeper','maintenance','laundry']"))
check('05_accounts_role_map', migration.includes("array['accounts','accounting']"))
check('06_dashboard_observer_preserved', migration.includes("'owner','manager','reception','front_desk','frontdesk'"))
check('07_service_department_routing', migration.includes("v_department = 'restaurant'") && migration.includes("array['housekeeping','maintenance','laundry']"))
check('08_restaurant_housekeeping_negative_gate', migration.includes('Restaurant must NOT receive housekeeping requests.'))
check('09_day17_kernel_server_filter', migration.includes('and private.day118_role_can_receive_notification('))
check('10_food_created_catalog', migration.includes("'food_order.created'"))
check('11_food_cancelled_catalog', migration.includes("'food_order.cancelled'"))
check('12_food_templates_published', migration.includes("status = 'published'") && migration.includes("channel = 'in_app'"))
check('13_food_capture_function', migration.includes('private.day118_capture_food_order_notification()'))
check('14_food_trigger', migration.includes('day118_food_order_notification_event'))
check('15_food_trigger_insert_and_status_update', migration.includes('after insert or update of order_status'))
check('16_food_payload_department_restaurant', migration.includes("'department', 'restaurant'"))
check('17_acceptance_final_marker', migration.includes('NOTIFICATION_ROLE_PUSH_ROUTING_REV1_PASSED'))
check('18_transactional', migration.includes('begin;') && migration.includes('commit;'))

const lockedHashes = {
  'src/lib/departmentNotificationRouting.js': '7364e1596b88107f830796ad38cb44761bc17da1719b22aa48fc92514b1bca1f',
  'src/lib/backgroundPush.js': '3c8ec052ee5f18755cb9cf8ec0baaf61b87af23055b584531ecd833f62556f14',
  'public/stayqr-sw.js': '5025c0c702c6e0885bb585a283d82a324dd0f044ed7024d1ddf602ff8c689360',
  'src/App.jsx': 'ecb3b9203b76c86faa729ba3ef85c9eaffb97384c539b593687bc800b6926f96',
}

let index = 19
for (const [path, expected] of Object.entries(lockedHashes)) {
  const actual = sha256(path)
  check(
    `${String(index).padStart(2, '0')}_locked_${path.replaceAll('/', '_')}_unchanged`,
    actual === expected,
    actual === expected ? 'locked baseline preserved' : `expected ${expected}, got ${actual}`
  )
  index += 1
}

const navbar = read('src/components/navbar/Navbar.jsx')
check('23_kitchen_recovery_lock_preserved', navbar.includes('STAYQR_KITCHEN_NOTIFICATION_RECOVERY_REV1'))
check('24_housekeeping_realtime_lock_preserved', navbar.includes('STAYQR_REV62G_HOUSEKEEPING_TASK_REALTIME'))
check('25_background_push_edge_unchanged', !migration.includes('create or replace function stayqr-background-push'))
check('26_no_destructive_existing_recipient_cleanup', !migration.match(/delete\s+from\s+public\.notification_recipients/i))

const failed = checks.filter((item) => !item.passed)
for (const item of checks) {
  console.log(`${item.passed ? 'PASS' : 'FAIL'} ${item.name}${item.detail ? ` — ${item.detail}` : ''}`)
}
console.log(`\nNotification role + food background push REV1: ${checks.length - failed.length}/${checks.length} passed.`)
if (failed.length) process.exit(1)
