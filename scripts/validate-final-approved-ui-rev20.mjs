import fs from 'node:fs'

const read = (p) => fs.readFileSync(p, 'utf8')
const exists = (p) => fs.existsSync(p)

const main = read('src/main.jsx')
const calendar = read('src/pages/calendar/BookingCalendar.jsx')
const css = read('src/styles/finalRev20.css')
const index = read('index.html')

const checks = []
const check = (name, ok) => checks.push({ name, ok: Boolean(ok) })

check('REV20 stylesheet imported last', /finalRev19\.css['"]\s*\nimport ['"]\.\/styles\/finalRev20\.css/.test(main))
check('Poppins production font remains linked', /Poppins:wght@400;500;600;700;800/.test(index))
check('Approved REV18 background token', /--sq20-bg:#06080b/.test(css))
check('Approved REV18 panel token', /--sq20-panel:#0f141a/.test(css))
check('Approved REV18 accent token', /--sq20-accent:#e8bd45/.test(css))
check('Approved REV18 Poppins font stack', /font-family:"Poppins"/.test(css))
check('Legacy warm Arrivals background removed', /\.reservation-operations-page[\s\S]*background:var\(--sq20-bg\)!important/.test(css))
check('Booking calendar has prototype search control', /placeholder="Search guest or room"/.test(calendar))
check('Booking calendar has one room type select', /All room types/.test(calendar))
check('Booking calendar has one status select', /All statuses/.test(calendar))
check('Legacy calendar filter popover removed from JSX', !/calendar-filter-menu/.test(calendar))
check('Legacy calendar legend popover removed from JSX', !/calendar-legend-menu/.test(calendar))
check('Secondary calendar options grouped under More', /calendar-more-legend/.test(calendar) && /Show historical blocks/.test(calendar))
check('Calendar search filters visible rooms locally', /const visibleRooms = normalizedSearch/.test(calendar))
check('Calendar mobile agenda uses visible events', /visibleEvents\.length/.test(calendar))
check('Native drop-cell tooltip removed', !/title=\{`Drop a reservation/.test(calendar))
check('Drop cell retains accessible label', /aria-label=\{`Room \$\{room\.room_number\}/.test(calendar))
check('Historical event lanes have readable height', /repeat\(\$\{historicalLaneCount\}, 42px\)/.test(calendar))
check('Calendar event cards remove stripe clutter', /\.calendar-event\.non-inventory[\s\S]*background-image:none!important/.test(css))
check('Calendar cards use approved completed gray', /background:#232a34!important/.test(css))
check('Calendar cards use approved booking blue', /background:#16365c!important/.test(css))
check('Calendar block cards use approved gold-brown', /background:#3b2b0c!important/.test(css))
check('Calendar filter row is one clean grid', /\.calendar-approved-filterbar[\s\S]*grid-template-columns:minmax\(260px,1fr\)/.test(css))
check('Housekeeping checked boxes use approved green', /input\[type="checkbox"\]:checked[\s\S]*background:var\(--sq20-green\)!important/.test(css))
check('Housekeeping remains two-column on desktop', /\.day13-grid\{grid-template-columns:repeat\(2,minmax\(0,1fr\)\)!important/.test(css))
check('Housekeeping remains one-column on mobile', /\.day13-grid\{grid-template-columns:1fr!important\}/.test(css))
check('Mobile calendar keeps agenda and hides timeline', /\.calendar-workspace,\.calendar-pagination\{display:none!important\}/.test(css))
check('No Meta/Cashfree implementation added', !/WHATSAPP_ACCESS_TOKEN|CASHFREE_CLIENT_SECRET|graph\.facebook\.com/.test(calendar + css))
check('No database/provider SQL in REV20 files', !/create\s+table|alter\s+table|supabase\.rpc|service_role/i.test(calendar + css))

let passed = 0
for (const item of checks) {
  if (item.ok) {
    passed += 1
    console.log(`PASS ${item.name}`)
  } else {
    console.error(`FAIL ${item.name}`)
  }
}
console.log(JSON.stringify({ checks: checks.length, passed, failed: checks.length - passed }))
if (passed !== checks.length) process.exit(1)
