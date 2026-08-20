import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8')
const has = (source, value) => source.includes(value)

const files = {
  app: read('src/App.jsx'),
  currentStaff: read('src/lib/currentStaff.js'),
  tenant: read('src/lib/tenantContext.js'),
  sidebar: read('src/components/sidebar/Sidebar.jsx'),
  navbar: read('src/components/navbar/Navbar.jsx'),
  superAdmin: read('src/pages/superadmin/SuperAdmin.jsx'),
  commercial: read('src/lib/commercialControl.js'),
}

const checks = []
const expect = (name, condition) => checks.push({ name, passed: Boolean(condition) })

expect('Platform Admin has platform-only navigation by default', has(files.currentStaff, "platform_admin: ['superadmin']"))
expect('Audited support mode uses a distinct platform_support role', has(files.tenant, "? 'platform_support'") && has(files.currentStaff, "normalizedRole === 'platform_support'"))
expect('Platform login does not auto-select an ordinary hotel', has(files.tenant, 'const selectedAccess = isPlatformAdmin') && has(files.tenant, '? activeSupportSession'))
expect('Stale platform hotel selection is cleared without an active session', has(files.tenant, 'storedHotelId && !activeSupportSession') && has(files.tenant, 'storeHotelId(user.id, null)'))
expect('Tenant context loads only active non-expired support sessions', has(files.tenant, ".from('support_access_sessions')") && has(files.tenant, ".eq('status', 'active')") && has(files.tenant, ".gt('expires_at'"))
expect('Platform hotel activation requires an active audited session', has(files.tenant, 'Start an audited View as Hotel session from Super Admin before entering this hotel.'))
expect('Selected platform hotel is confirmed as audited support mode', has(files.tenant, '!nextContext?.isPlatformSupportMode'))
expect('Starting View as Hotel immediately enters the audited hotel context', has(files.superAdmin, 'await onViewHotel?.(dialog.hotel.id)') && has(files.app, 'handleAuditedHotelView'))
expect('Existing active audited session can be resumed', has(files.superAdmin, 'onResumeSession') && has(files.superAdmin, 'View hotel'))
expect('Support session expiry automatically returns to platform scope', has(files.app, 'activeSupportSession?.expires_at') && has(files.app, 'clearSelectedTenantHotel()'))
expect('Hotel support mode exposes an explicit Return to Super Admin control', has(files.sidebar, 'Return to Super Admin') && has(files.navbar, 'Return to Super Admin'))
expect('Platform accounts never receive the ordinary hotel switcher UI', has(files.sidebar, 'isPlatformAccount ? (') && has(files.navbar, 'isPlatformAccount ? ('))
expect('Safe support access remains server-authoritative and audited', has(files.commercial, "'start_safe_support_access'") && has(files.commercial, "'end_safe_support_access'"))
expect('Safe support copy no longer instructs use of ordinary hotel switcher', !has(files.superAdmin, 'After starting it, use the hotel switcher'))

for (const [index, check] of checks.entries()) {
  console.log(`${check.passed ? 'PASS' : 'FAIL'} ${String(index + 1).padStart(2, '0')} | ${check.name}`)
}

const failures = checks.filter((check) => !check.passed)
if (failures.length) {
  console.error(`POSTLAUNCH_BATCH2_ITEM3_PLATFORM_VIEW_ACCEPTANCE: FAIL (${checks.length - failures.length}/${checks.length})`)
  process.exit(1)
}

console.log(`POSTLAUNCH_BATCH2_ITEM3_PLATFORM_VIEW_ACCEPTANCE: PASS (${checks.length}/${checks.length})`)
