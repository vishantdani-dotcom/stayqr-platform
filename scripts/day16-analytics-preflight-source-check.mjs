import fs from 'node:fs'
import path from 'node:path'

const root = process.cwd()
const reportsPath = path.join(root, 'src/pages/reports/Reports.jsx')

if (!fs.existsSync(reportsPath)) {
  console.error('FAIL — Reports.jsx was not found.')
  process.exit(1)
}

const source = fs.readFileSync(reportsPath, 'utf8')

const baseline = [
  ['reports page exists', true],
  ['hotel context', source.includes('getCurrentHotel')],
  ['occupancy snapshot', source.includes('occupancyRate')],
  ['revenue snapshot', source.includes('totalRevenue')],
  ['food snapshot', source.includes('foodRevenue')],
  ['service snapshot', source.includes('completedRequests')],
  ['housekeeping snapshot', source.includes('completedHousekeeping')],
]

const plannedGaps = [
  ['trusted report RPCs', !/supabase\.rpc\(/.test(source)],
  ['date range filters', !/type=["']date["']/.test(source)],
  ['ADR or ARR', !/\bADR\b|\bARR\b/.test(source)],
  ['RevPAR', !/\bRevPAR\b/i.test(source)],
  ['reservation source drill-down', !/booking_source/.test(source)],
  ['arrival/departure report', !/arrival|departure/i.test(source)],
  ['payment method drill-down', !/payment_method/.test(source)],
  ['GST report', !/CGST|SGST|IGST|GST/.test(source)],
  ['staff/department report', !/department|staff/i.test(source)],
  ['CSV export', !/csv/i.test(source)],
  ['PDF export', !/pdf/i.test(source)],
  ['standard charts', !/chart|svg|canvas/i.test(source)],
  ['role-aware export controls', !/reports\.view/.test(source)],
  ['server-authoritative metrics', /\.from\(['"]rooms['"]\)/.test(source)],
]

const baselineFailures = baseline.filter(([, ok]) => !ok)

for (const [name, ok] of baseline) {
  console.log(`${ok ? 'PASS' : 'FAIL'} baseline — ${name}`)
}

for (const [name, gapPresent] of plannedGaps) {
  console.log(
    `${gapPresent ? 'PLANNED GAP' : 'ALREADY PRESENT'} — ${name}`
  )
}

if (baselineFailures.length) {
  process.exit(1)
}

console.log(
  `PASS — Day 16 source preflight `
  + `(${baseline.length} baseline checks; `
  + `${plannedGaps.filter(([, gap]) => gap).length} planned gaps).`
)
