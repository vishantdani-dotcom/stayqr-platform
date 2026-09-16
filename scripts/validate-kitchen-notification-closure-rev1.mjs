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

const navbarPath = 'src/components/navbar/Navbar.jsx'
const navbar = read(navbarPath)
const routingPath = 'src/lib/departmentNotificationRouting.js'
const backgroundPushPath = 'src/lib/backgroundPush.js'
const workerPath = 'public/stayqr-sw.js'
const appPath = 'src/App.jsx'

check('01_recovery_marker_present', navbar.includes('STAYQR_KITCHEN_NOTIFICATION_RECOVERY_REV1'))
check('02_recovery_kitchen_role_scoped', navbar.includes("['restaurant', 'kitchen', 'chef'].includes(normalizedRole)") && navbar.includes('if (!hotelId || !kitchenAccount) return undefined'))
check('03_recovery_queries_authoritative_food_orders', navbar.includes(".from('food_orders')") && navbar.includes("rooms (room_number)"))
check('04_recovery_is_bounded', navbar.includes(".limit(50)"))
check('05_recovery_poll_interval', navbar.includes('8000') && navbar.includes('reconcileKitchenOrders'))
check('06_recovery_on_focus_and_visibility', navbar.includes("window.addEventListener('focus', handleKitchenReturn)") && navbar.includes("'visibilitychange'"))
check('07_existing_orders_primed_silently', navbar.includes('kitchenRecoveryPrimedRef') && navbar.includes('createdDuringSession') && navbar.includes('seenNotificationIdsRef.current.add(baseId)'))
check('08_duplicate_guard_preserved', navbar.includes('seenNotificationIdsRef.current.has(notification.id)') && navbar.includes('seenNotificationIdsRef.current.add(notification.id)'))
check('09_realtime_primary_path_preserved', navbar.includes("table: 'food_orders'") && navbar.includes('kitchen_k2_order_cancel_'))
check('10_kitchen_sound_recovery_queue', navbar.includes('pendingKitchenSoundRef') && navbar.includes("playDepartmentSound('kitchen')"))
check('11_dashboard_food_sound_path_preserved', navbar.includes("const soundKey = 'dashboard'") && navbar.includes('dashboard_d1_global_food_'))
check('12_housekeeping_realtime_preserved', navbar.includes('STAYQR_REV62G_HOUSEKEEPING_TASK_REALTIME') && navbar.includes('rev62g_housekeeping_tasks_'))
check('13_background_push_bridge_preserved', navbar.includes('rev62k-webaudio-department-ringtones'))

const lockedHashes = {
  [routingPath]: '7364e1596b88107f830796ad38cb44761bc17da1719b22aa48fc92514b1bca1f',
  [backgroundPushPath]: '3c8ec052ee5f18755cb9cf8ec0baaf61b87af23055b584531ecd833f62556f14',
  [workerPath]: '5025c0c702c6e0885bb585a283d82a324dd0f044ed7024d1ddf602ff8c689360',
  [appPath]: 'ecb3b9203b76c86faa729ba3ef85c9eaffb97384c539b593687bc800b6926f96',
}

let index = 14
for (const [path, expected] of Object.entries(lockedHashes)) {
  const actual = sha256(path)
  check(
    `${String(index).padStart(2, '0')}_locked_${path.replaceAll('/', '_')}_unchanged`,
    actual === expected,
    actual === expected ? 'baseline preserved' : `expected ${expected}, got ${actual}`
  )
  index += 1
}

const failed = checks.filter((item) => !item.passed)
for (const item of checks) {
  console.log(`${item.passed ? 'PASS' : 'FAIL'} ${item.name}${item.detail ? ` — ${item.detail}` : ''}`)
}
console.log(`\nKitchen notification closure REV1: ${checks.length - failed.length}/${checks.length} passed.`)
if (failed.length) process.exit(1)
