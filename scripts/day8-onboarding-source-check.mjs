import fs from 'node:fs'
import path from 'node:path'

const root = process.cwd()

function read(relativePath) {
  return fs.readFileSync(path.join(root, relativePath), 'utf8')
}

const app = read('src/App.jsx')
const login = read('src/pages/auth/Login.jsx')
const onboarding = read('src/pages/onboarding/HotelOnboarding.jsx')
const onboardingLib = read('src/lib/onboarding.js')
const superAdmin = read('src/pages/superadmin/SuperAdmin.jsx')
const menu = read('src/pages/menumanagement/MenuManagement.jsx')
const amenities = read('src/pages/amenities/Amenities.jsx')
const currentStaff = read('src/lib/currentStaff.js')
const sidebar = read('src/components/sidebar/Sidebar.jsx')

const checks = [
  {
    name: '00_owner_self_signup_available',
    pass:
      login.includes('supabase.auth.signUp') &&
      login.includes("account_type: 'hotel_owner'") &&
      login.includes("setMode('signup')") === false &&
      login.includes("changeMode('signup')"),
    detail: 'A new hotel owner can create an authenticated account before entering secure onboarding.',
  },
  {
    name: '01_unassigned_user_enters_onboarding',
    pass:
      app.includes('onboardingRequired') &&
      app.includes('standalone') &&
      app.includes("setActiveSection('onboarding')"),
    detail: 'Authenticated accounts without hotel access enter the secure onboarding wizard.',
  },
  {
    name: '02_atomic_bootstrap_rpc_used',
    pass:
      onboardingLib.includes("'bootstrap_hotel_onboarding'") &&
      onboarding.includes('bootstrapHotel('),
    detail: 'The wizard creates tenants through the atomic bootstrap RPC.',
  },
  {
    name: '03_inventory_rpc_used',
    pass:
      onboardingLib.includes("'configure_hotel_inventory'") &&
      onboarding.includes('configureHotelInventory('),
    detail: 'Floors, room types and rates use the server-owned inventory RPC.',
  },
  {
    name: '04_room_import_rpc_used',
    pass:
      onboardingLib.includes("'import_hotel_rooms'") &&
      onboarding.includes('parseRoomsCsv(') &&
      onboarding.includes('importHotelRooms('),
    detail: 'CSV room creation uses the validated bulk-room RPC.',
  },
  {
    name: '05_readiness_is_server_computed',
    pass:
      onboardingLib.includes("'get_hotel_onboarding_readiness'") &&
      onboardingLib.includes("'refresh_hotel_onboarding_readiness'") &&
      onboarding.includes('readiness?.ready'),
    detail: 'The browser cannot self-declare the hotel operational.',
  },
  {
    name: '06_resumable_step_rpc_used',
    pass:
      onboardingLib.includes("'save_hotel_onboarding_step'") &&
      onboarding.includes("'floors_rooms'") &&
      onboarding.includes("'review'"),
    detail: 'Wizard progress is persisted through server-validated onboarding steps.',
  },
  {
    name: '07_superadmin_direct_hotel_insert_removed',
    pass:
      !/\.from\(['"]hotels['"]\)[\s\S]{0,160}\.insert\(/.test(superAdmin) &&
      superAdmin.includes("onNavigate?.('onboarding')"),
    detail: 'Super Admin launches atomic onboarding instead of separate table inserts.',
  },
  {
    name: '08_normalized_menu_categories_used',
    pass:
      menu.includes(".from('menu_categories')") &&
      menu.includes('category_id') &&
      onboardingLib.includes('category_id: values.category_id'),
    detail: 'Menu configuration uses hotel-owned normalized categories.',
  },
  {
    name: '09_database_amenities_used',
    pass:
      amenities.includes(".from('amenities')") &&
      !amenities.includes('Multi-cuisine dining experience'),
    detail: 'The Amenities page no longer renders fixed demo data.',
  },
  {
    name: '10_hotel_setup_navigation_authorized',
    pass:
      currentStaff.includes("'onboarding'") &&
      sidebar.includes("id: 'onboarding'") &&
      sidebar.includes("label: 'Hotel Setup'"),
    detail: 'Owners, managers and Platform Admins can open Hotel Setup through normal authorization.',
  },
  {
    name: '11_user_scoped_idempotency_key',
    pass:
      onboardingLib.includes('stayqr:onboarding-request') &&
      onboardingLib.includes('crypto.randomUUID()') &&
      onboardingLib.includes('getScopedKey'),
    detail: 'Bootstrap retry protection is scoped to the authenticated user.',
  },
  {
    name: '12_no_service_role_or_fixed_tenant',
    pass:
      !/service[_-]?role/i.test(onboarding + onboardingLib + superAdmin) &&
      !/[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/i.test(
        onboarding + onboardingLib + superAdmin
      ),
    detail: 'Day 8 frontend code contains no service-role secret or fixed tenant UUID.',
  },
  {
    name: '13_subscription_plan_schema_contract',
    pass:
      !onboardingLib.includes('max_staff') &&
      onboardingLib.includes(
        'id, plan_name, price_monthly, max_rooms, features, status'
      ) &&
      onboardingLib.includes(
        'subscription_plans (id, plan_name, price_monthly, max_rooms)'
      ),
    detail: 'Onboarding queries only subscription-plan columns that exist in the locked production schema.',
  },
]

let failed = 0

for (const check of checks) {
  if (check.pass) {
    console.log(`PASS ${check.name} — ${check.detail}`)
  } else {
    failed += 1
    console.error(`FAIL ${check.name} — ${check.detail}`)
  }
}

if (failed > 0) {
  console.error(`\nDay 8 onboarding source gate failed ${failed}/${checks.length}.`)
  process.exit(1)
}

console.log(`\nDay 8 onboarding source gate passed ${checks.length}/${checks.length}.`)
