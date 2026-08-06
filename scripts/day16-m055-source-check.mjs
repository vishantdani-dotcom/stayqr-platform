import fs from 'node:fs'
import path from 'node:path'

const root = process.cwd()
const sqlPath = path.join(
  root,
  'docs/database/legacy-migrations/pre-day18-canonical-baseline/202608050055_day16_trusted_reporting_kernel_REV3_INVOICE_STATUS_FIX.sql'
)

if (!fs.existsSync(sqlPath)) {
  console.error('FAIL — Migration 055 was not found.')
  process.exit(1)
}

const source = fs.readFileSync(sqlPath, 'utf8')

const contracts = [
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
  'day16_assert_report_access',
  'reports.view',
  'room_inventory_allocations',
  'folio_items',
  'folio_collections',
  'invoice_items',
  'invoice_status',
  'ADR and ARR',
  'RevPAR',
]

const unsafe = [
  ['invoice_lines assumption', /public\.invoice_lines/i.test(source)],
  [
    'wrong invoice status column',
    /public\.invoices\s*\([\s\S]*?\binvoice_date\s*,\s*status\b/i.test(source)
      || /\b(?:i|invoice_row)\.status\b/i.test(source)
  ],
  ['staff department column', /\bs\.department\b/i.test(source)],
  ['dynamic export SQL', /execute\s+format/i.test(source)],
  ['anon report grant', /grant execute[\s\S]*\bto anon\b/i.test(source)],
  ['persistent report facts', /create table public\.report_/i.test(source)],
]

const missing = contracts.filter((contract) => !source.includes(contract))
const unsafeHits = unsafe.filter(([, hit]) => hit)

if (missing.length || unsafeHits.length) {
  for (const name of missing) console.error(`FAIL required: ${name}`)
  for (const [name] of unsafeHits) console.error(`FAIL unsafe: ${name}`)
  process.exit(1)
}

console.log(
  `PASS — Day 16 Migration 055 source gate `
  + `(${contracts.length} required contracts; `
  + `${unsafe.length} unsafe patterns blocked).`
)
