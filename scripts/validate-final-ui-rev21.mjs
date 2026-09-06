import fs from 'node:fs'

const checks = []
const add = (name, ok) => checks.push({ name, ok: Boolean(ok) })
const read = (file) => fs.readFileSync(file, 'utf8')

const main = read('src/main.jsx')
const index = read('index.html')
const css = read('src/styles/finalRev21.css')
const rooms = read('src/components/table/RoomsTable.jsx')

add('REV21 stylesheet imported last after REV20', /finalRev20\.css['"]\s*\nimport ['"]\.\/styles\/finalRev21\.css/.test(main))
add('Poppins 400-800 loaded like approved prototype', index.includes('family=Poppins:wght@400;500;600;700;800'))
add('Approved background token', css.includes('--sq21-bg:#06080b'))
add('Approved elevated token', css.includes('--sq21-bg-elev:#090c11'))
add('Approved panel token', css.includes('--sq21-panel:#0f141a'))
add('Approved panel 2 token', css.includes('--sq21-panel-2:#131920'))
add('Approved line token', css.includes('--sq21-line:#27303a'))
add('Approved text token', css.includes('--sq21-text:#f7f8f9'))
add('Approved muted token', css.includes('--sq21-muted:#b3bbc5'))
add('Approved gold token', css.includes('--sq21-accent:#e8bd45'))
add('Legacy surface variables remapped', css.includes('--surface-2:var(--sq21-panel)'))
add('Reservations brown cast removed', css.includes('.reservation-stat-card{') && css.includes('background:var(--sq21-panel)!important'))
add('Revenue hero warm gradient removed', css.includes('.v11-hero{') && css.includes('background-image:none!important'))
add('Reports hero neutralised', css.includes('.reports-hero{background:var(--sq21-panel)!important'))
add('Dashboard operational cards neutralised', css.includes('.dashboard-page .dash-support-panel{'))
add('Hotel media explicitly preserved', css.includes('.hotel-overview-card.has-cover::after'))
add('Housekeeping green checked state preserved', css.includes('background:var(--sq21-green)!important'))
add('Notification warm cast removed', css.includes('.notif-dropdown{background:var(--sq21-panel)!important'))
add('Rooms action uses real StayQR navigation event', rooms.includes("navigateToSection('rooms'"))
add('Rooms action rendered as button', rooms.includes('className="rooms-table-view-btn"'))
add('Room action has accessible label', rooms.includes('aria-label={`Open Room'))
add('No database code introduced in REV21 CSS', !css.includes('supabase'))
add('REV21 stylesheet is presentation-only', !/fetch\(|supabase\.|createClient\(/i.test(css))

let passed = 0
for (const check of checks) {
  console.log(`${check.ok ? 'PASS' : 'FAIL'} ${check.name}`)
  if (check.ok) passed += 1
}
console.log(JSON.stringify({ checks: checks.length, passed, failed: checks.length - passed }))
if (passed !== checks.length) process.exit(1)
