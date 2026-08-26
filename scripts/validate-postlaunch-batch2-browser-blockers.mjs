import fs from 'node:fs'
const read = (path) => fs.readFileSync(path, 'utf8')
const media = read('src/lib/guestGuideBuilder.js')
const staff = read('src/pages/staff/StaffManagement.jsx')
const admin = read('src/pages/superadmin/SuperAdmin.jsx')
const migration = read('supabase/migrations/202608200090_postlaunch_batch2_checkout_zero_collection_guard.sql')
const checks = [
  ['MP4 duration has container metadata fallback', media.includes('readMp4DurationSeconds') && media.includes("'mvhd'")],
  ['Video still enforces 30-second limit', media.includes('MAX_GUEST_GUIDE_VIDEO_SECONDS') && media.includes('durationSeconds = await readVideoDurationSeconds(file)')],
  ['SMS provider failure is explicit', staff.includes('no SMS provider configured')],
  ['Overview exposes View as Hotel', admin.includes('onViewHotel') && admin.includes('View as Hotel')],
  ['Hotels table exposes View as Hotel', admin.includes('onSupport(hotel)') && admin.includes('View as Hotel')],
  ['Audited RPC path preserved', admin.includes("openDialog('safe-support'") && admin.includes('startSafeSupportAccess')],
  ['Zero payment folio guard migration exists', migration.includes('POSTLAUNCH_BATCH2_ZERO_PAYMENT_FOLIO_GUARD_REV1')],
  ['Zero payment guard requires positive amount', migration.includes('coalesce(payment_row.amount, 0) > 0')],
]
let passed = 0
checks.forEach(([label, ok], index) => { if (ok) { passed++; console.log(`PASS ${String(index+1).padStart(2,'0')} | ${label}`) } else console.error(`FAIL ${String(index+1).padStart(2,'0')} | ${label}`) })
if (passed !== checks.length) { console.error(`POSTLAUNCH_BATCH2_BROWSER_BLOCKERS_SOURCE_ACCEPTANCE: FAIL (${passed}/${checks.length})`); process.exit(1) }
console.log(`POSTLAUNCH_BATCH2_BROWSER_BLOCKERS_SOURCE_ACCEPTANCE: PASS (${passed}/${checks.length})`)
