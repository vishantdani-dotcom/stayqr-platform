import fs from 'node:fs'
import path from 'node:path'

const root = process.cwd()
const reportsJsx = path.join(root, 'src/pages/reports/Reports.jsx')
const reportsCss = path.join(root, 'src/pages/reports/Reports.css')
const migration = path.join(
  root,
  'supabase/migrations/202608050055_day16_trusted_reporting_kernel_REV3_INVOICE_STATUS_FIX.sql'
)
const audit = path.join(
  root,
  'supabase/audit/202608050068_day16_final_consolidated_acceptance_REV3_RUNTIME_SELECTION_FIX.sql'
)
const packageJson = path.join(root, 'package.json')

for (const file of [reportsJsx, reportsCss, migration, audit, packageJson]) {
  if (!fs.existsSync(file)) {
    console.error(`FAIL missing: ${path.relative(root, file)}`)
    process.exit(1)
  }
}

const jsx = fs.readFileSync(reportsJsx, 'utf8')
const css = fs.readFileSync(reportsCss, 'utf8')
const sql = fs.readFileSync(migration, 'utf8')
const auditSql = fs.readFileSync(audit, 'utf8')
const packageBytes = fs.readFileSync(packageJson)
const packageText = packageBytes.toString('utf8')

const required = [
  ['all 14 trusted report RPC calls', [
    'get_report_filter_options',
    'get_report_kpi_summary',
    'get_report_occupancy_daily',
    'get_report_revenue_daily',
    'get_report_revenue_by_category',
    'get_report_reservations_by_source',
    'get_report_arrivals_departures',
    'get_report_payments_by_method',
    'get_report_tax_gst_summary',
    'get_report_guest_food_service',
    'get_report_service_sla',
    'get_report_housekeeping',
    'get_report_staff_department',
    'get_report_export_rows',
  ].every((name) => jsx.includes(name))],
  ['today preset', jsx.includes("preset === 'today'")],
  ['7 day preset', jsx.includes("preset === '7d'")],
  ['30 day preset', jsx.includes("preset === '30d'")],
  ['month to date preset', jsx.includes('Month to date')],
  ['custom date inputs', jsx.includes('type="date"')],
  ['occupancy', jsx.includes('Occupancy')],
  ['ADR ARR', jsx.includes('ADR / ARR')],
  ['RevPAR', jsx.includes('RevPAR')],
  ['revenue collection separation', jsx.includes('Revenue versus collections')],
  ['reservation source', jsx.includes('Reservations by booking source')],
  ['arrivals departures', jsx.includes('Arrivals and departures')],
  ['payment method', jsx.includes('Payments by method')],
  ['tax GST', jsx.includes('Tax & Staff')],
  ['guest food service', jsx.includes('Food operations')],
  ['service SLA', jsx.includes('Department performance')],
  ['housekeeping', jsx.includes('Task distribution')],
  ['staff department', jsx.includes('Staff and work-department report')],
  ['booking-source drilldown', jsx.includes('bookingSource')],
  ['department drilldown', jsx.includes('department')],
  ['payment-method drilldown', jsx.includes('paymentMethod')],
  ['clear drilldowns', jsx.includes('Clear drill-downs')],
  ['CSV generation', jsx.includes('toCsv') && jsx.includes('.csv')],
  ['PDF generation', jsx.includes('html2canvas') && jsx.includes('jsPDF')],
  ['export current view', jsx.includes('Export current view as PDF')],
  ['loading state', jsx.includes('reports-loader')],
  ['empty states', jsx.includes('No reservations in this period.')],
  ['success toast', css.includes('.reports-toast')],
  ['responsive CSS', css.includes('@media (max-width: 640px)')],
  ['source reconciled copy', jsx.replace(/\s+/g, ' ').includes('Source-reconciled metrics')],
  ['reports.view copy', jsx.includes('reports.view')],
  ['hotel context', jsx.includes('getCurrentHotel')],
  ['Migration 055 invoice_status', sql.includes('invoice_status')],
  ['Migration 055 invoice_items', sql.includes('invoice_items')],
  ['Migration 055 report guard', sql.includes('day16_assert_report_access')],
  ['Migration 055 whitelist', sql.includes('case v_key')],
  ['Audit 068 migration replay', auditSql.includes('day16_migration_055_acceptance_rev1')],
  ['Audit 068 source reconciliation', auditSql.includes('KPI_RECONCILIATION')],
  ['Audit 068 cross-hotel denial', auditSql.includes('cross_hotel_export_rejected')],
  ['Audit 068 activity-backed runtime selection',
    auditSql.includes('where c.activity_score > 0')
      && auditSql.includes('c.activity_score desc')],
  ['Audit 068 accurate 217-row expectation',
    auditSql.includes('-- 217 rows')
      && auditSql.includes('-- 217 passed = true')],
  ['package JSON valid', (() => {
    try {
      JSON.parse(packageText)
      return true
    } catch {
      return false
    }
  })()],
  ['package JSON no BOM', !(
    packageBytes.length >= 3
    && packageBytes[0] === 0xef
    && packageBytes[1] === 0xbb
    && packageBytes[2] === 0xbf
  )],
]

const unsafe = [
  ['direct rooms read', /\.from\(['"]rooms['"]\)/.test(jsx)],
  ['direct reservations read', /\.from\(['"]reservations['"]\)/.test(jsx)],
  ['direct folio read', /\.from\(['"]folio_items['"]\)/.test(jsx)],
  ['direct invoice read', /\.from\(['"]invoices['"]\)/.test(jsx)],
  ['direct food read', /\.from\(['"]food_orders['"]\)/.test(jsx)],
  ['direct service read', /\.from\(['"]service_requests['"]\)/.test(jsx)],
  ['fixed hotel UUID', /[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/i.test(jsx)],
  ['service-role key', /service[_-]?role/i.test(jsx)],
  ['unsafe HTML', /dangerouslySetInnerHTML|\.innerHTML\s*=/.test(jsx)],
  ['external report fetch', /fetch\(['"]https?:\/\//.test(jsx)],
  ['dynamic export SQL', /execute\s+format/i.test(sql)],
  ['invoice status mismatch', /\b(?:i|invoice_row)\.status\b/i.test(sql)],
]

const missing = required.filter(([, ok]) => !ok)
const unsafeHits = unsafe.filter(([, hit]) => hit)

for (const [name, ok] of required) {
  console.log(`${ok ? 'PASS' : 'FAIL'} required — ${name}`)
}
for (const [name, hit] of unsafe) {
  console.log(`${hit ? 'FAIL' : 'PASS'} blocked — ${name}`)
}

if (missing.length || unsafeHits.length) {
  process.exit(1)
}

console.log(
  `PASS — Day 16 final source gate `
  + `(${required.length} required contracts; `
  + `${unsafe.length} unsafe patterns blocked).`
)
