import fs from 'node:fs'
import path from 'node:path'

const root = process.cwd()
const read = (p) => fs.readFileSync(path.join(root, p), 'utf8')

const files = {
  responsive: read('src/styles/responsive.css'),
  navbar: read('src/components/navbar/Navbar.css'),
  sidebar: read('src/components/sidebar/Sidebar.css'),
  dashboard: read('src/pages/dashboard/Dashboard.css'),
  hotel: read('src/components/cards/HotelOverviewCard.css'),
  stats: read('src/components/cards/StatCards.css'),
  day13: read('src/pages/day13/Day13Operations.css'),
  rooms: read('src/pages/rooms/Rooms.jsx'),
  guests: read('src/pages/guests/GuestDirectory.css'),
  staff: read('src/pages/staff/StaffManagement.css'),
  operations: read('src/pages/operationscenter/OperationsCenter.css'),
  superadmin: read('src/pages/superadmin/SuperAdmin.css'),
}

const checks = [
  ['Shared shell prevents horizontal overflow', files.responsive.includes('StayQR Mobile UI REV2 — shared hard safety only')],
  ['Navbar has route-local mobile treatment', files.navbar.includes('StayQR Mobile UI REV2 — navbar')],
  ['Sidebar has route-local off-canvas treatment', files.sidebar.includes('StayQR Mobile UI REV2 — off-canvas navigation')],
  ['Dashboard title explicitly wraps on phone', files.dashboard.includes('white-space: normal !important') && files.dashboard.includes('StayQR Mobile UI REV2 — Dashboard')],
  ['Property overview is one-column on phone', files.hotel.includes('StayQR Mobile UI REV2 — property overview')],
  ['Dashboard metrics become compact two-column cards', files.stats.includes('grid-template-columns: repeat(2, minmax(0, 1fr)) !important')],
  ['Rooms header and actions are phone-safe', files.day13.includes('StayQR Mobile UI REV2 — Rooms & Inventory')],
  ['Room register has mobile card selectors', files.day13.includes('.room-register-table td:nth-child(6)::before')],
  ['Rooms JSX provides mobile register hooks', files.rooms.includes('room-register-table-wrap') && files.rooms.includes('room-register-table')],
  ['Guest directory actions stack on phone', files.guests.includes('StayQR Mobile UI REV2 — Guest Directory')],
  ['Guest directory table becomes mobile cards', files.guests.includes('.guest-directory-table td:nth-child(7)::before')],
  ['Staff workspace has mobile layout', files.staff.includes('StayQR Mobile UI REV2 — Staff')],
  ['Operations Centre has mobile layout', files.operations.includes('StayQR Mobile UI REV2 — Operations Centre')],
  ['Super Admin metrics use phone-safe two-column grid', files.superadmin.includes('StayQR Mobile UI REV2 — Super Admin') && files.superadmin.includes('grid-template-columns: repeat(2, minmax(0, 1fr)) !important')],
  ['Super Admin tabs horizontally scroll', files.superadmin.includes('.commercial-tabs') && files.superadmin.includes('overflow-x: auto !important')],
  ['Support access dialog is phone-safe', files.superadmin.includes('.commercial-dialog') && files.superadmin.includes('max-height: calc(100dvh - 16px) !important')],
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
  console.error(`POSTLAUNCH_MOBILE_UI_REV2_SOURCE_ACCEPTANCE: FAIL (${passed}/${checks.length})`)
  process.exit(1)
}

console.log(`POSTLAUNCH_MOBILE_UI_REV2_SOURCE_ACCEPTANCE: PASS (${passed}/${checks.length})`)
