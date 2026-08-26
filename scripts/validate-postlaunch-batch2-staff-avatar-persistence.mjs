import fs from 'node:fs'
import path from 'node:path'

const root = process.cwd()

function read(relativePath) {
  return fs.readFileSync(path.join(root, relativePath), 'utf8')
}

function expect(label, condition) {
  if (!condition) {
    console.error(`FAIL | ${label}`)
    process.exitCode = 1
    return
  }
  console.log(`PASS | ${label}`)
}

const tenant = read('src/lib/tenantContext.js')
const staff = read('src/pages/staff/StaffManagement.jsx')
const migration = read('supabase/migrations/202608190084_postlaunch_batch2_operations_crm.sql')

expect(
  'Tenant staff query selects avatar_path',
  tenant.includes('avatar_path,')
)

expect(
  'Tenant currentStaff propagates avatar_path after reload',
  tenant.includes('avatar_path: selectedAccess?.staff?.avatar_path || null')
)

expect(
  'Staff page reloads current avatar from currentStaff',
  staff.includes('loadAvatarPreview(loggedStaff?.avatar_path)')
)

expect(
  'Staff page uses a signed private-storage URL',
  staff.includes('.createSignedUrl(avatarPath, 3600)')
)

expect(
  'Staff profile save persists avatar_path through existing RPC',
  staff.includes('p_avatar_path: avatarPath')
)

expect(
  'Migration keeps staff avatar bucket private',
  migration.includes("'staff-avatars'") &&
    migration.includes('false,') &&
    migration.includes('stayqr_staff_avatars_select')
)

if (process.exitCode) {
  console.error('POSTLAUNCH_BATCH2_STAFF_AVATAR_PERSISTENCE: FAIL')
} else {
  console.log('POSTLAUNCH_BATCH2_STAFF_AVATAR_PERSISTENCE: PASS (6/6)')
}
