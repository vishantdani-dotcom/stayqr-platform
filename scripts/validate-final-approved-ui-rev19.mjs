import fs from 'node:fs'
import path from 'node:path'

const root = process.cwd()
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8')
const main = read('src/main.jsx')
const css = read('src/styles/finalRev19.css')
const calendar = read('src/pages/calendar/BookingCalendar.jsx')
const housekeeping = read('src/pages/housekeeping/Housekeeping.jsx')
const login = read('src/pages/auth/Login.jsx')

const checks = []
const check = (name, ok) => checks.push({ name, ok: Boolean(ok) })

check('REV19 stylesheet imported after REV18', /finalRev18\.css['"]\s*\nimport ['"]\.\/styles\/finalRev19\.css['"]/.test(main))
check('Approved background token matches REV18 prototype', css.includes('--sq19-bg:#06080b'))
check('Approved panel token matches REV18 prototype', css.includes('--sq19-panel:#0f141a'))
check('Approved accent token matches REV18 prototype', css.includes('--sq19-accent:#e8bd45'))
check('Approved Poppins typography is authoritative', css.includes('--font-body:"Poppins"'))
check('Approved sidebar width is 238px', css.includes('--sidebar-w:238px'))
check('Approved topbar height is 66px', css.includes('--navbar-h:66px'))
check('Small operational body copy is 13px baseline', css.includes('body{font-size:13px!important'))
check('No text glass blur in REV19 authority', !/backdrop-filter\s*:\s*blur\(/i.test(css))
check('Booking Calendar approved title and subtitle', calendar.includes('A clear room timeline on desktop and a readable agenda on mobile.'))
check('Booking Calendar status filters moved into filter menu', calendar.includes('className="calendar-filter-menu"') && calendar.includes('Reservation status'))
check('Booking Calendar legend moved into compact menu', calendar.includes('className="calendar-legend-menu"'))
check('Booking Calendar room type remains quick filter', calendar.includes('className="calendar-quick-room-type"'))
check('Booking Calendar empty assignment queue is hidden', calendar.includes("unallocated.length > 0 && ("))
check('Booking Calendar mobile agenda retained', calendar.includes('className="calendar-mobile-agenda"'))
check('Housekeeping checklist uses optimistic local patching', housekeeping.includes('updateChecklistItemOptimistic') && housekeeping.includes('patchChecklist'))
check('Housekeeping single item update does not reload workspace', (() => {
  const start = housekeeping.indexOf('const updateChecklistItemOptimistic')
  const end = housekeeping.indexOf('const updateChecklistAllOptimistic')
  return start >= 0 && end > start && !housekeeping.slice(start, end).includes('loadData(')
})())
check('Housekeeping bulk complete/clear all exists', housekeeping.includes("allComplete ? 'Clear all' : 'Complete all'"))
check('Housekeeping bulk success path does not reload workspace', (() => {
  const start = housekeeping.indexOf('const updateChecklistAllOptimistic')
  const catchAt = housekeeping.indexOf('} catch (actionError) {', start)
  return start >= 0 && catchAt > start && !housekeeping.slice(start, catchAt).includes('loadData(')
})())
check('Housekeeping bulk failure reconciles authoritative state', (() => {
  const start = housekeeping.indexOf('const updateChecklistAllOptimistic')
  const end = housekeeping.indexOf('const createTask', start)
  const block = start >= 0 && end > start ? housekeeping.slice(start, end) : ''
  return block.includes('await loadData(false)')
})())
check('Housekeeping summary reduced to approved four metrics', (() => { const start = housekeeping.indexOf('day13-stats day13-stats-approved'); const end = housekeeping.indexOf('<div className="day13-tabs">', start); return start >= 0 && end > start && (housekeeping.slice(start, end).match(/<Stat label=/g) || []).length === 4 })())
check('Housekeeping task board keeps existing workflow actions', ['assignHousekeepingTask','startHousekeepingTask','completeHousekeepingCleaning','inspectHousekeepingTask','approveHousekeepingRoomReady'].every((name) => housekeeping.includes(name)))
check('Login remains present and is not replaced by fallback UI', login.includes('export default function Login') || login.includes('function Login'))
check('Mobile Rooms card conversion is present', css.includes('.room-register-table tbody tr{display:grid'))
check('Mobile Guests card conversion is present', css.includes('.guests-active-mobile{display:block'))
check('Payments mobile declutter is present', css.includes('.payments-modern-row'))
check('Guest Bills mobile declutter is present', css.includes('.folio-table tbody tr'))
check('Reports tabular digit polish is present', css.includes('font-variant-numeric:tabular-nums'))
check('Scanner mobile full-height refinement is present', css.includes('.document-scanner-modal{position:fixed'))
check('Guest guide / food mobile polish is present', css.includes('.food-mobile-cart'))
check('Reduced-motion accessibility is present', /@media\s*\(prefers-reduced-motion:reduce\)/.test(css))

for (const item of checks) console.log(`${item.ok ? 'PASS' : 'FAIL'} ${item.name}`)
const passed = checks.filter((item) => item.ok).length
const failed = checks.length - passed
console.log(JSON.stringify({ checks: checks.length, passed, failed }))
if (failed) process.exit(1)
