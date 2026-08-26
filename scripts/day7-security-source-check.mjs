import { readFile, readdir } from 'node:fs/promises'
import { extname, join, relative, resolve } from 'node:path'

const root = resolve(process.cwd())
const sourceRoot = join(root, 'src')
const failures = []
const passed = []

async function read(relativePath) {
  return readFile(join(root, relativePath), 'utf8')
}

async function collectFiles(directory) {
  const entries = await readdir(directory, { withFileTypes: true })
  const results = []

  for (const entry of entries) {
    const fullPath = join(directory, entry.name)
    if (entry.isDirectory()) results.push(...(await collectFiles(fullPath)))
    else results.push(fullPath)
  }

  return results
}

function check(name, condition, details) {
  if (condition) passed.push({ name, details })
  else failures.push({ name, details })
}

const [currentHotel, tenantContext, guestPortal, app, qrGenerator, localQr, guestGuide, foodMenu] = await Promise.all([
  read('src/lib/currentHotel.js'),
  read('src/lib/tenantContext.js'),
  read('src/lib/guestPortal.js'),
  read('src/App.jsx'),
  read('src/pages/qr/QRGenerator.jsx'),
  read('src/lib/localQr.js'),
  read('src/pages/guestguide/GuestGuide.jsx'),
  read('src/pages/food/FoodMenu.jsx'),
])

const sourceFiles = (await collectFiles(sourceRoot)).filter((file) =>
  ['.js', '.jsx', '.css'].includes(extname(file))
)
const sourceText = (
  await Promise.all(sourceFiles.map(async (file) => `${relative(root, file)}\n${await readFile(file, 'utf8')}`))
).join('\n')

const uuidLiteral = /['"`]([0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})['"`]/gi
const externalQrService = /(?:api\.qrserver|chart\.googleapis|quickchart\.io|api\.qrcode|qr-code-generator)/i
const legacyGuestRoute = /\/(?:guest|food)\/\$\{[^}]*room/i

check(
  '01_no_fixed_hotel_uuid',
  !uuidLiteral.test(sourceText),
  'No literal production tenant UUID exists in frontend source.'
)
check(
  '02_no_current_hotel_fallback',
  !/fallback|defaultHotel|fixedHotel/i.test(currentHotel) && /selectedHotel \|\| null/.test(currentHotel),
  'Current hotel is resolved only from canonical tenant context.'
)
check(
  '03_user_scoped_hotel_selection',
  /stayqr:selected-hotel-id/.test(tenantContext) && /getStorageKey\(userId\)/.test(tenantContext),
  'Selected hotel storage is scoped to the authenticated user.'
)
check(
  '04_signed_guest_path_validation',
  /SIGNED_GUEST_TOKEN_PATTERN/.test(guestPortal) && /HOTEL_SLUG_PATTERN/.test(guestPortal),
  'Guest routes require a hotel slug and UUID-plus-HMAC token.'
)
check(
  '05_malformed_path_is_safe',
  /safelyDecodePathPart/.test(guestPortal) && /catch \{\s*return ''/s.test(guestPortal),
  'Malformed URL encoding is rejected without crashing the guest page.'
)
check(
  '06_guest_access_uses_rpc_only',
  !/\.from\s*\(/.test(guestPortal) && /supabase\.rpc/.test(guestPortal),
  'Guest capabilities are exposed through approved RPCs, not direct tables.'
)
check(
  '07_secure_guest_and_food_routes',
  /startsWith\('\/guest\/'\)/.test(app) && /startsWith\('\/food\/'\)/.test(app),
  'Guest guide and food menu use signed path entry points.'
)
check(
  '08_no_legacy_room_route_generation',
  !legacyGuestRoute.test(sourceText),
  'Frontend does not construct room-number guest credentials.'
)
check(
  '09_local_qr_renderer_present',
  /createLocalQrSvg/.test(localQr) && /LocalQrCode/.test(qrGenerator),
  'Secure QR codes are generated locally in the browser.'
)
check(
  '10_no_external_qr_service',
  !externalQrService.test(sourceText),
  'Signed guest tokens are never sent to a third-party QR service.'
)
check(
  '11_revocation_state_supported',
  /access_status/.test(qrGenerator) && /Activate new secure link/.test(qrGenerator),
  'Revoked and expired access remains disabled until explicit activation.'
)
check(
  '12_service_role_not_in_browser',
  !/(?:SUPABASE_SERVICE_ROLE_KEY|\bservice_role\b|\bserviceRole(?:Key)?\b)/i.test(sourceText),
  'No Supabase service-role key or browser-side service-role usage exists.'
)

check(
  '13_guest_pages_revalidate_revocation',
  /addEventListener\((?:'|")focus(?:'|")/.test(guestGuide) &&
    /visibilitychange/.test(guestGuide) &&
    /ACCESS_RECHECK_INTERVAL_MS/.test(guestGuide) &&
    /addEventListener\((?:'|")focus(?:'|")/.test(foodMenu) &&
    /visibilitychange/.test(foodMenu) &&
    /ACCESS_RECHECK_INTERVAL_MS/.test(foodMenu),
  'Open guest pages revalidate on focus, visibility return and a bounded interval.'
)
check(
  '14_revoked_guest_state_is_cleared',
  (/setPortal\(null\)/.test(guestGuide) ||
    (/setSession\(null\)/.test(guestGuide) &&
      /setHotelInfo\(null\)/.test(guestGuide))) &&
    /setRequests\(\[\]\)/.test(guestGuide) &&
    (/setActiveSession\(null\)/.test(foodMenu) || /setPortal\(null\)/.test(foodMenu)) &&
    /setItems\(\[\]\)/.test(foodMenu) &&
    (/setMyOrders\(\[\]\)/.test(foodMenu) || /setOrders\(\[\]\)/.test(foodMenu)) &&
    /setCart\(\[\]\)/.test(foodMenu),
  'Revocation clears already-rendered guest, menu, order and cart state.'
)
check(
  '15_guest_actions_prevalidate_access',
  /const accessStillValid = await fetchActive(?:Session|Portal)\(\)/.test(guestGuide) &&
    (/const portal = await validateFoodAccess\(\)/.test(foodMenu) ||
      /const valid = await validateAccess\(\)/.test(foodMenu)),
  'Service requests, food navigation and order placement revalidate access before action.'
)

for (const result of passed) {
  console.log(`PASS ${result.name} — ${result.details}`)
}

if (failures.length > 0) {
  for (const result of failures) {
    console.error(`FAIL ${result.name} — ${result.details}`)
  }
  process.exitCode = 1
} else {
  console.log(`\nDay 7 frontend security source gate passed ${passed.length}/${passed.length}.`)
}
