import fs from 'node:fs'
import path from 'node:path'

const root = process.cwd()

const requiredFiles = [
  'src/lib/day13Operations.js',
  'src/pages/day13/Day13Operations.css',
  'src/pages/rooms/Rooms.jsx',
  'src/pages/housekeeping/Housekeeping.jsx',
  'src/pages/maintenance/Maintenance.jsx',
  'src/pages/services/ServiceRequests.jsx',
  'src/App.jsx',
  'src/components/sidebar/Sidebar.jsx',
  'src/lib/currentStaff.js',
]

const requiredContracts = [
  ['src/App.jsx', "import Maintenance from './pages/maintenance/Maintenance'"],
  ['src/App.jsx', "case 'maintenance'"],
  ['src/components/sidebar/Sidebar.jsx', "id: 'maintenance'"],
  ['src/lib/currentStaff.js', "maintenance: 'rooms.view'"],
  ['src/lib/day13Operations.js', "'get_room_inventory_workspace'"],
  ['src/lib/day13Operations.js', "'upsert_floor'"],
  ['src/lib/day13Operations.js', "'archive_floor'"],
  ['src/lib/day13Operations.js', "'upsert_room_type'"],
  ['src/lib/day13Operations.js', "'archive_room_type'"],
  ['src/lib/day13Operations.js', "'upsert_room'"],
  ['src/lib/day13Operations.js', "'transition_room_status'"],
  ['src/lib/day13Operations.js', "'archive_room'"],
  ['src/lib/day13Operations.js', "'import_rooms'"],
  ['src/lib/day13Operations.js', "'get_housekeeping_workspace'"],
  ['src/lib/day13Operations.js', "'get_housekeeping_mobile_queue'"],
  ['src/lib/day13Operations.js', "'create_housekeeping_task'"],
  ['src/lib/day13Operations.js', "'assign_housekeeping_task'"],
  ['src/lib/day13Operations.js', "'start_housekeeping_task'"],
  ['src/lib/day13Operations.js', "'update_housekeeping_checklist_item'"],
  ['src/lib/day13Operations.js', "'complete_housekeeping_cleaning'"],
  ['src/lib/day13Operations.js', "'inspect_housekeeping_task'"],
  ['src/lib/day13Operations.js', "'approve_housekeeping_room_ready'"],
  ['src/lib/day13Operations.js', "'cancel_housekeeping_task'"],
  ['src/lib/day13Operations.js', "'get_maintenance_workspace'"],
  ['src/lib/day13Operations.js', "'get_maintenance_mobile_queue'"],
  ['src/lib/day13Operations.js', "'report_maintenance_task'"],
  ['src/lib/day13Operations.js', "'assign_maintenance_task'"],
  ['src/lib/day13Operations.js', "'start_maintenance_task'"],
  ['src/lib/day13Operations.js', "'hold_maintenance_task'"],
  ['src/lib/day13Operations.js', "'resolve_maintenance_task'"],
  ['src/lib/day13Operations.js', "'verify_maintenance_task'"],
  ['src/lib/day13Operations.js', "'cancel_maintenance_task'"],
  ['src/pages/rooms/Rooms.jsx', 'Atomic room import'],
  ['src/pages/rooms/Rooms.jsx', 'Immutable room-status history'],
  ['src/pages/rooms/Rooms.jsx', 'active_reservations'],
  ['src/pages/housekeeping/Housekeeping.jsx', 'Staff workload'],
  ['src/pages/housekeeping/Housekeeping.jsx', 'Mobile staff view'],
  ['src/pages/housekeeping/Housekeeping.jsx', 'Pass inspection'],
  ['src/pages/housekeeping/Housekeeping.jsx', 'Approve room ready'],
  ['src/pages/maintenance/Maintenance.jsx', 'Inventory impact'],
  ['src/pages/maintenance/Maintenance.jsx', 'Expected return'],
  ['src/pages/maintenance/Maintenance.jsx', 'Verify & release'],
  ['src/pages/maintenance/Maintenance.jsx', 'Require housekeeping cleaning'],
  ['src/pages/services/ServiceRequests.jsx', 'navigateToSection("guests"'],
  ['src/pages/services/ServiceRequests.jsx', 'Open Settlement'],
]

const unsafePatterns = [
  /\.from\(['"]rooms['"]\)\s*\.\s*insert/s,
  /\.from\(['"]rooms['"]\)\s*\.\s*update/s,
  /\.from\(['"]rooms['"]\)\s*\.\s*delete/s,
  /\.from\(['"]housekeeping_tasks['"]\)\s*\.\s*insert/s,
  /\.from\(['"]housekeeping_tasks['"]\)\s*\.\s*update/s,
  /\.from\(['"]housekeeping_tasks['"]\)\s*\.\s*delete/s,
  /\.from\(['"]maintenance_tasks['"]\)\s*\.\s*insert/s,
  /\.from\(['"]maintenance_tasks['"]\)\s*\.\s*update/s,
  /\.from\(['"]maintenance_tasks['"]\)\s*\.\s*delete/s,
  /\.from\(['"]guest_sessions['"]\)\s*\.\s*update/s,
  /markRoomReady/,
  /markCompleted\(task\)/,
  /Delete Room/,
  /Room cleaned and marked available/,
]

const failures = []

for (const file of requiredFiles) {
  if (!fs.existsSync(path.join(root, file))) {
    failures.push(`Missing required file: ${file}`)
  }
}

for (const [file, contract] of requiredContracts) {
  const absolute = path.join(root, file)
  if (!fs.existsSync(absolute)) continue
  const content = fs.readFileSync(absolute, 'utf8')
  if (!content.includes(contract)) {
    failures.push(`Missing contract in ${file}: ${contract}`)
  }
}

const protectedDay13Files = [
  'src/lib/day13Operations.js',
  'src/pages/rooms/Rooms.jsx',
  'src/pages/housekeeping/Housekeeping.jsx',
  'src/pages/maintenance/Maintenance.jsx',
  'src/pages/services/ServiceRequests.jsx',
  'src/components/table/RoomsTable.jsx',
  'src/components/modals/AddRoomModal.jsx',
]

const combined = protectedDay13Files
  .map((file) => fs.readFileSync(path.join(root, file), 'utf8'))
  .join('\n')

for (const pattern of unsafePatterns) {
  if (pattern.test(combined)) {
    failures.push(`Unsafe Day 13 pattern found: ${pattern}`)
  }
}

if (failures.length) {
  console.error('FAIL — Day 13 rooms, housekeeping and maintenance source gate.')
  for (const failure of failures) console.error(`- ${failure}`)
  process.exit(1)
}

console.log(
  `PASS — Day 13 rooms, housekeeping and maintenance frontend source gate (${requiredContracts.length} required contracts; ${unsafePatterns.length} unsafe patterns blocked).`
)
