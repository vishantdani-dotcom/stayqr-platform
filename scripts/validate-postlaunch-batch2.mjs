import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const read = (relativePath) => fs.readFileSync(path.join(root, relativePath), 'utf8')

const files = {
  app: read('src/App.jsx'),
  commercial: read('src/lib/commercialControl.js'),
  context: read('src/lib/tenantContext.js'),
  dashboard: read('src/pages/dashboard/Dashboard.jsx'),
  dashboardCss: read('src/pages/dashboard/Dashboard.css'),
  guestGuide: read('src/pages/guestguide/GuestGuide.jsx'),
  guestGuideCss: read('src/pages/guestguide/GuestGuide.css'),
  guests: read('src/pages/guests/GuestDirectory.jsx'),
  guestsCss: read('src/pages/guests/GuestDirectory.css'),
  navbar: read('src/components/navbar/Navbar.jsx'),
  navbarCss: read('src/components/navbar/Navbar.css'),
  quickActions: read('src/components/buttons/QuickActions.jsx'),
  sidebar: read('src/components/sidebar/Sidebar.jsx'),
  sidebarCss: read('src/components/sidebar/Sidebar.css'),
  staff: read('src/pages/staff/StaffManagement.jsx'),
  staffCss: read('src/pages/staff/StaffManagement.css'),
  superAdmin: read('src/pages/superadmin/SuperAdmin.jsx'),
  migration: read('supabase/migrations/202608190084_postlaunch_batch2_operations_crm.sql'),
  audit: read('supabase/audit/202608190085_postlaunch_batch2_ACCEPTANCE.sql'),
  packageJson: read('package.json'),
}

const checks = []
const expect = (name, condition) => checks.push({ name, passed: Boolean(condition) })
const has = (source, value) => source.includes(value)

expect(
  'Dashboard receives navigation control',
  has(files.app, '<Dashboard') && has(files.app, 'onNavigate={handleNavigate}')
)
expect('Dashboard quick actions include guest directory', has(files.quickActions, "label: 'Guest Directory'"))
expect('Dashboard quick actions include support', has(files.quickActions, "label: 'Get Support'"))
expect('Dashboard quick actions include report issue', has(files.quickActions, "label: 'Report Issue'"))
expect('Dashboard support routes to Operations Centre', has(files.dashboard, "onNavigate?.('operationscenter')"))
expect('Dashboard publishes approved support hours', has(files.dashboard, '09:00–19:00 IST, Monday–Saturday'))
expect('Dashboard support panel is responsive', has(files.dashboardCss, '.dash-support-panel'))

expect('Platform metrics client RPC exists', has(files.commercial, "'get_postlaunch_batch2_platform_metrics'"))
expect('Super Admin loads platform metrics', has(files.superAdmin, 'getPostlaunchBatch2PlatformMetrics()'))
expect('Super Admin shows total guests', has(files.superAdmin, 'label="Total guests"'))
expect('Super Admin shows document scans', has(files.superAdmin, 'label="Guest document scans"'))
expect('Super Admin shows reservations and rooms', has(files.superAdmin, 'platformMetrics.reservations'))
expect('Super Admin shows staff count', has(files.superAdmin, 'platformMetrics.staff'))
expect('Navbar blocks ordinary platform hotel switching', has(files.navbar, 'isPlatformAdmin ? (') && has(files.navbar, 'timed, audited support session'))
expect('Sidebar blocks ordinary platform hotel switching', has(files.sidebar, 'isPlatformAdmin ? (') && has(files.sidebar, 'Use Super Admin for timed hotel support access'))
expect('Platform scope treatments are styled', has(files.navbarCss, '.navbar-platform-scope') && has(files.sidebarCss, '.sidebar-platform-scope'))

expect('Staff context includes avatar path', has(files.context, 'avatar_path'))
expect('Staff profile uses private avatar bucket', has(files.staff, "const STAFF_AVATAR_BUCKET = 'staff-avatars'"))
expect('Staff profile enforces five megabyte limit', has(files.staff, '5 * 1024 * 1024'))
expect('Staff profile constrains image MIME types', has(files.staff, 'image/jpeg') && has(files.staff, 'image/png') && has(files.staff, 'image/webp'))
expect('Staff profile calls tenant-explicit RPC', has(files.staff, "supabase.rpc('update_my_staff_profile'") && has(files.staff, 'p_hotel_id: currentHotel.id'))
expect('Staff profile is responsive', has(files.staffCss, '.staff-self-profile'))

expect('Guest directory exports CSV', has(files.guests, 'exportGuestDirectory') && has(files.guests, 'new Blob'))
expect('Guest export excludes identity documents', has(files.guests, 'CSV exports exclude identity documents'))
expect('WhatsApp is click-to-chat only', has(files.guests, 'https://wa.me/') && has(files.guests, 'window.confirm'))
expect('WhatsApp requires guest consent confirmation', has(files.guests, 'Confirm the guest has consented'))
expect(
  'Guest CRM controls are responsive',
  has(files.guestsCss, '@media (max-width: 680px)') && has(files.guestsCss, '.guest-directory-actions')
)
expect('Guest management escalation is available', has(files.guestGuide, "createRequest('Management Escalation')"))
expect('Guest management escalation is responsive', has(files.guestGuideCss, '.ag-escalation-cta'))

expect('Migration adds staff avatar column', has(files.migration, 'add column if not exists avatar_path text'))
expect(
  'Migration creates private staff avatar bucket',
  has(files.migration, "'staff-avatars',\n  false") && has(files.migration, 'set public = excluded.public')
)
expect('Migration limits avatar size', has(files.migration, '5242880'))
expect('Migration limits avatar path to authenticated user', has(files.migration, "split_part(name, '/', 2) = (select auth.uid())::text"))
expect('Migration defines four avatar policies', (files.migration.match(/create policy stayqr_staff_avatars_/g) || []).length === 4)
expect('Staff self-profile RPC is tenant explicit', has(files.migration, 'p_hotel_id uuid') && has(files.migration, 's.hotel_id = p_hotel_id'))
expect('Platform metrics RPC requires platform admin', has(files.migration, 'if not private.is_platform_admin()'))
expect('RPC grants are authenticated only', (files.migration.match(/grant execute on function/g) || []).length === 2 && (files.migration.match(/revoke all on function/g) || []).length === 2)
expect('Database acceptance gate exists', has(files.audit, 'POSTLAUNCH_BATCH2_DATABASE_ACCEPTANCE: PASS (8/8)'))
expect('Batch B source script is registered', has(files.packageJson, 'test:postlaunch-batch2'))

const changedScope = [
  files.dashboard,
  files.guestGuide,
  files.guests,
  files.navbar,
  files.quickActions,
  files.sidebar,
  files.staff,
  files.superAdmin,
  files.migration,
  files.audit,
].join('\n')

expect('No unsupported 24x7 support claim was added', !/(24\s*[x×/]\s*7|24\/7)/i.test(changedScope))
expect('Production Supabase reference is absent', !changedScope.includes('rbyirbovbkguzvwijyaj'))

for (const [index, check] of checks.entries()) {
  console.log(`${check.passed ? 'PASS' : 'FAIL'} ${String(index + 1).padStart(2, '0')} | ${check.name}`)
}

const failures = checks.filter((check) => !check.passed)
if (failures.length > 0) {
  console.error(`POSTLAUNCH_BATCH2_SOURCE_ACCEPTANCE: FAIL (${checks.length - failures.length}/${checks.length})`)
  process.exit(1)
}

console.log(`POSTLAUNCH_BATCH2_SOURCE_ACCEPTANCE: PASS (${checks.length}/${checks.length})`)
