import fs from 'node:fs'
import path from 'node:path'

const root = process.cwd()
const jsxPath = path.join(root, 'src/pages/reports/Reports.jsx')
const cssPath = path.join(root, 'src/pages/reports/Reports.css')

if (!fs.existsSync(jsxPath) || !fs.existsSync(cssPath)) {
  console.error('FAIL — Day 16 report frontend files were not found.')
  process.exit(1)
}

const jsx = fs.readFileSync(jsxPath, 'utf8')
const css = fs.readFileSync(cssPath, 'utf8')

const required = [
  ['trusted KPI RPC', jsx.includes('get_report_kpi_summary')],
  ['daily occupancy RPC', jsx.includes('get_report_occupancy_daily')],
  ['daily revenue RPC', jsx.includes('get_report_revenue_daily')],
  ['category revenue RPC', jsx.includes('get_report_revenue_by_category')],
  ['reservation source RPC', jsx.includes('get_report_reservations_by_source')],
  ['arrival departure RPC', jsx.includes('get_report_arrivals_departures')],
  ['payment method RPC', jsx.includes('get_report_payments_by_method')],
  ['tax GST RPC', jsx.includes('get_report_tax_gst_summary')],
  ['guest food service RPC', jsx.includes('get_report_guest_food_service')],
  ['service SLA RPC', jsx.includes('get_report_service_sla')],
  ['housekeeping RPC', jsx.includes('get_report_housekeeping')],
  ['staff department RPC', jsx.includes('get_report_staff_department')],
  ['filter options RPC', jsx.includes('get_report_filter_options')],
  ['export dispatcher RPC', jsx.includes('get_report_export_rows')],
  ['date from filter', jsx.includes('type="date"') && jsx.includes("updateDate('from'")],
  ['date to filter', jsx.includes("updateDate('to'")],
  ['preset filters', jsx.includes('Month to date') && jsx.includes('30 days')],
  ['ADR metric', jsx.includes('ADR / ARR')],
  ['RevPAR metric', jsx.includes('RevPAR')],
  ['occupancy metric', jsx.includes('Occupancy')],
  ['revenue collections separation', jsx.includes('Revenue versus collections')],
  ['source drilldown', jsx.includes('Booking source')],
  ['department drilldown', jsx.includes('Department')],
  ['payment drilldown', jsx.includes('Payment method')],
  ['CSV export', jsx.includes('toCsv') && jsx.includes('.csv')],
  ['PDF export', jsx.includes('html2canvas') && jsx.includes('jsPDF')],
  ['role aware copy', jsx.includes('reports.view')],
  ['premium charts', jsx.includes('TrendChart') && jsx.includes('BarList')],
  ['responsive tables', jsx.includes('DataTable')],
  ['fixed save toast', css.includes('.reports-toast')],
  ['responsive CSS', css.includes('@media (max-width: 640px)')],
]

const unsafe = [
  ['direct rooms read', /\.from\(['"]rooms['"]\)/.test(jsx)],
  ['direct reservation read', /\.from\(['"]reservations['"]\)/.test(jsx)],
  ['direct folio read', /\.from\(['"]folio_items['"]\)/.test(jsx)],
  ['direct invoice read', /\.from\(['"]invoices['"]\)/.test(jsx)],
  ['direct food read', /\.from\(['"]food_orders['"]\)/.test(jsx)],
  ['direct service read', /\.from\(['"]service_requests['"]\)/.test(jsx)],
  ['fixed hotel UUID', /[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/i.test(jsx)],
  ['service role key', /service[_-]?role/i.test(jsx)],
  ['unsafe HTML', /dangerouslySetInnerHTML|\.innerHTML\s*=/.test(jsx)],
  ['external report API', /fetch\(['"]https?:\/\//.test(jsx)],
]

const missing = required.filter(([, ok]) => !ok)
const hits = unsafe.filter(([, hit]) => hit)

if (missing.length || hits.length) {
  for (const [name] of missing) console.error(`FAIL required: ${name}`)
  for (const [name] of hits) console.error(`FAIL unsafe: ${name}`)
  process.exit(1)
}

console.log(
  `PASS — Day 16 reports frontend source gate `
  + `(${required.length} required contracts; `
  + `${unsafe.length} unsafe patterns blocked).`
)
