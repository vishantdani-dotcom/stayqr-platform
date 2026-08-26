import fs from 'node:fs'
import path from 'node:path'

const root = process.cwd()
const read = (p) => fs.readFileSync(path.join(root, p), 'utf8')

const responsive = read('src/styles/responsive.css')
const rooms = read('src/pages/rooms/Rooms.jsx')

const checks = [
  ['mobile redesign layer exists', responsive.includes('StayQR Post-Launch Mobile UI Redesign REV1')],
  ['phone app shell uses dedicated mobile gutters', responsive.includes('--mobile-page-gutter: 14px')],
  ['sidebar remains off-canvas sized for phones', responsive.includes('width: min(316px, 88vw) !important')],
  ['dashboard uses compact two-column stat cards', responsive.includes('.stat-cards-grid') && responsive.includes('repeat(2, minmax(0, 1fr)) !important')],
  ['dashboard hotel card releases the desktop icon/content split', responsive.includes('.hotel-card-left') && responsive.includes('grid-template-columns: minmax(0, 1fr) !important')],
  ['rooms register has a dedicated mobile hook', rooms.includes('room-register-table-wrap') && rooms.includes('room-register-table')],
  ['rooms register becomes mobile cards', responsive.includes('.room-register-table thead') && responsive.includes("content: 'Commitments'")],
  ['guest directory becomes mobile CRM cards', responsive.includes('.guest-directory-table thead') && responsive.includes("content: 'Stay history'")],
  ['guest toolbar keeps search full-width over two actions', responsive.includes('.guest-directory-actions input') && responsive.includes('grid-column: 1 / -1')],
  ['staff identities become mobile cards', responsive.includes('.staff-table thead') && responsive.includes("content: 'Accepted'")],
  ['operations centre keeps two-column compact KPIs', responsive.includes('.d17-kpis') && responsive.includes('repeat(2, minmax(0, 1fr)) !important')],
  ['Super Admin uses two-column phone metrics', responsive.includes('.commercial-metrics-grid') && responsive.includes('repeat(2, minmax(0, 1fr)) !important')],
  ['Super Admin hero actions cannot clip on phones', responsive.includes('.commercial-hero-actions .commercial-btn:last-child') && responsive.includes('grid-column: 1 / -1')],
  ['Super Admin modal becomes a mobile bottom sheet', responsive.includes('align-items: flex-end !important') && responsive.includes('max-height: 92dvh !important')],
  ['390px small-phone navbar remains bounded', responsive.includes('@media (max-width: 390px)') && responsive.includes('grid-template-columns: repeat(3, 40px) !important')],
  ['mobile data cards use readable label/value columns', responsive.includes('grid-template-columns: 84px minmax(0, 1fr)')]
]

let passed = 0
checks.forEach(([label, ok], i) => {
  if (ok) {
    passed += 1
    console.log(`PASS ${String(i + 1).padStart(2, '0')} | ${label}`)
  } else {
    console.error(`FAIL ${String(i + 1).padStart(2, '0')} | ${label}`)
  }
})

if (passed !== checks.length) {
  console.error(`POSTLAUNCH_MOBILE_UI_REDESIGN_SOURCE_ACCEPTANCE: FAIL (${passed}/${checks.length})`)
  process.exit(1)
}
console.log(`POSTLAUNCH_MOBILE_UI_REDESIGN_SOURCE_ACCEPTANCE: PASS (${passed}/${checks.length})`)
