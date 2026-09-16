import fs from 'node:fs'

const checks = []
function check(name, condition, detail = '') {
  checks.push({ name, passed: Boolean(condition), detail })
}
function read(path) {
  return fs.readFileSync(path, 'utf8')
}

const navbar = read('src/components/navbar/Navbar.jsx')
const app = read('src/App.jsx')
const main = read('src/main.jsx')
const profile = read('src/pages/staff/MyProfile.jsx')
const push = read('src/lib/backgroundPush.js')
const worker = read('public/stayqr-sw.js')
const fn = read('supabase/functions/stayqr-background-push/index.ts')
const migration = read('supabase/migrations/202609160117_background_push_notifications.sql')
const netlify = read('netlify.toml')
const config = read('supabase/config.toml')
const manifest = read('public/manifest.webmanifest')

check('01_locked_navbar_foreground_logic_present', navbar.includes('housekeepingInboxSound') && navbar.includes('rev62k-webaudio-department-ringtones'))
check('02_background_push_does_not_import_navbar', !push.includes('Navbar'))
check('03_service_worker_has_no_fetch_handler', !worker.includes("addEventListener('fetch'") && !worker.includes('addEventListener("fetch"'))
check('04_service_worker_push_handler', worker.includes("addEventListener('push'"))
check('05_service_worker_click_deeplink', worker.includes('STAYQR_PUSH_NAVIGATE') && worker.includes('openWindow'))
check('06_manifest_standalone', manifest.includes('"display": "standalone"'))
check('07_client_requires_user_permission', push.includes('Notification.requestPermission()'))
check('08_client_uses_vapid', push.includes('applicationServerKey') && push.includes('STAYQR_VAPID_PUBLIC_KEY'))
check('09_client_rpc_registration', push.includes('register_background_push_subscription'))
check('10_client_logout_cleanup', app.includes('disableCurrentDevicePushBeforeLogout'))
check('11_deeplink_access_guard', app.includes('canAccessSection(currentRole, section'))
check('12_profile_controls_are_additive', profile.includes('<BackgroundPushCard'))
check('13_push_tables_rls', migration.includes('alter table public.background_push_subscriptions enable row level security') && migration.includes('alter table public.background_push_deliveries enable row level security'))
check('14_anon_blocked', migration.includes("not has_function_privilege('anon'"))
check('15_edge_webhook_secret_auth', fn.includes("get('x-stayqr-push-secret')") && fn.includes("env('STAYQR_PUSH_WEBHOOK_SECRET')"))
check('16_edge_queries_real_recipient', fn.includes("from('notification_recipients')") && fn.includes("from('notification_outbox')"))
check('17_existing_recipient_routing_is_authoritative', fn.includes('Background Push must not create a second routing policy') && !fn.includes('SERVICE_DEPARTMENTS_BY_ROLE'))
check('18_edge_does_not_recompute_service_department', !fn.includes("from('service_requests')") && !fn.includes('allowedDepartments.has(department)'))
check('19_hotel_aware_push_navigation', fn.includes("params.set('hotelId', hotelId)") && push.includes('targetHotelId !== selectedHotelId') && app.includes('consumePendingBackgroundPushNavigation(tenantContext?.selectedHotelId)'))
check('20_edge_idempotent_delivery_log', migration.includes('background_push_delivery_unique') && fn.includes("insert({\n        recipient_id: recipientId"))
check('21_expired_subscription_cleanup', fn.includes("last_error_code: 'subscription_expired'") && fn.includes('statusCode === 404 || statusCode === 410'))
check('22_edge_function_jwt_mode_explicit', config.includes('[functions.stayqr-background-push]') && config.includes('verify_jwt = false'))
check('23_service_worker_cache_protected', netlify.includes('for = "/stayqr-sw.js"') && netlify.includes('no-cache, no-store, must-revalidate'))
check('24_main_bridge_installed', main.includes('installBackgroundPushClientBridge()'))
check('25_no_locked_ringtone_asset_edit_required', fs.existsSync('public/assets/stayqr-rev61f4-kitchen.wav') && fs.existsSync('public/assets/stayqr-rev61f4-housekeeping.wav') && fs.existsSync('public/assets/stayqr-rev61f4-main-dashboard.wav'))

const failed = checks.filter((item) => !item.passed)
for (const item of checks) {
  console.log(`${item.passed ? 'PASS' : 'FAIL'} ${item.name}${item.detail ? ` — ${item.detail}` : ''}`)
}
console.log(`\nBackground push validation: ${checks.length - failed.length}/${checks.length} passed.`)
if (failed.length) process.exit(1)
