import fs from 'node:fs'
import path from 'node:path'

const root = process.cwd()
const read = (p) => fs.readFileSync(path.join(root, p), 'utf8')

const superAdmin = read('src/pages/superadmin/SuperAdmin.jsx')
const migration = read('supabase/migrations/202608200086_postlaunch_batch2_superadmin_qr_scan_metrics.sql')
const audit = read('supabase/audit/202608200087_postlaunch_batch2_superadmin_qr_scan_metrics_ACCEPTANCE.sql')

const checks = [
  ['Super Admin shows Guest guide QR scans card',
    superAdmin.includes('label="Guest guide QR scans"')],
  ['Super Admin reads total QR scan metric',
    superAdmin.includes('platformMetrics.guest_guide_qr_scans_total')],
  ['Super Admin shows unique access-link metric',
    superAdmin.includes('platformMetrics.guest_guide_qr_scans_unique')],
  ['Migration extends existing platform metrics RPC',
    migration.includes('create or replace function public.get_postlaunch_batch2_platform_metrics()')],
  ['Total metric counts guide_opened events',
    migration.includes("'guest_guide_qr_scans_total'") &&
    migration.includes("event_type = 'guide_opened'")],
  ['Unique metric deduplicates signed guest access tokens',
    migration.includes("'guest_guide_qr_scans_unique'") &&
    migration.includes('count(distinct guest_access_token_id)')],
  ['Platform-admin guard remains enforced',
    migration.includes('private.is_platform_admin()')],
  ['Database acceptance audit is included',
    audit.includes('POSTLAUNCH_BATCH2_QR_SCAN_METRICS_DATABASE_ACCEPTANCE: PASS (6/6)')]
]

let passed = 0
checks.forEach(([label, ok], index) => {
  if (ok) {
    passed += 1
    console.log(`PASS ${String(index + 1).padStart(2, '0')} | ${label}`)
  } else {
    console.error(`FAIL ${String(index + 1).padStart(2, '0')} | ${label}`)
  }
})

if (passed !== checks.length) {
  console.error(`POSTLAUNCH_BATCH2_SUPERADMIN_QR_SCAN_METRIC: FAIL (${passed}/${checks.length})`)
  process.exit(1)
}

console.log(`POSTLAUNCH_BATCH2_SUPERADMIN_QR_SCAN_METRIC: PASS (${passed}/${checks.length})`)
