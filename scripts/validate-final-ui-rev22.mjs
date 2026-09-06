import fs from 'node:fs'

const checks = []
const add = (name, ok) => checks.push({ name, ok: Boolean(ok) })
const read = (file) => fs.readFileSync(file, 'utf8')

const main = read('src/main.jsx')
const css = read('src/styles/finalRev22.css')
const roomCss = read('src/pages/rooms/Rooms.css')
const rooms = read('src/pages/rooms/Rooms.jsx')
const dashboard = read('src/pages/dashboard/Dashboard.jsx')
const housekeeping = read('src/pages/housekeeping/Housekeeping.jsx')

add('REV22 imported after REV21', /finalRev21\.css['"]\s*\nimport ['"]\.\/styles\/finalRev22\.css/.test(main))
add('Admin warm token neutralised', css.includes('--sq21-accent-soft:var(--sq22-panel2)'))
add('Gold-subtle admin token neutralised', css.includes('--gold-subtle:var(--sq22-panel2)'))
add('Dashboard quick action backgrounds neutral', css.includes('.qa-btn--gold') && css.includes('background:var(--sq22-elev)!important'))
add('Dashboard analytics grid hook present', dashboard.includes('dash-analytics-grid'))
add('Dashboard analytics grid fallback neutralises cards', css.includes('.dash-analytics-grid > *') && css.includes('background:var(--sq22-panel)!important'))
add('Housekeeping uses operational checkbox source', housekeeping.includes('className="day13-check"') && housekeeping.includes('type="checkbox"'))
add('Housekeeping custom checkbox appearance', css.includes('-webkit-appearance:none!important') && css.includes('border-width:0 2px 2px 0!important'))
add('QR admin surfaces neutralised', css.includes('.secure-qr-permanent') && css.includes('background:var(--sq22-panel)!important'))
add('Guest Guide Builder admin hero neutralised', css.includes('.simple-builder-hero'))
add('Menu admin studio neutralised', css.includes('.menu15-offer-preview'))
add('Staff profile warm hero neutralised', css.includes('.staff-self-profile'))
add('Operations Centre warm cast neutralised', css.includes('.d17-page{background:var(--sq22-bg)!important'))
add('Onboarding warm surfaces neutralised', css.includes('.onboarding-context-card'))
add('Amenities admin controls neutralised', css.includes('.amenities-form'))
add('Rooms page uses approved visual card grid', rooms.includes('className="rooms22-grid"') && rooms.includes('className={`rooms22-card'))
add('Rooms cards support real photos', rooms.includes('guest_guide_media') && rooms.includes('uploadGuestGuideMediaFile'))
add('Room photo is scoped to room media', rooms.includes("scope_type: 'room'") && rooms.includes("category: 'room'"))
add('Room photo upload accepts only images', rooms.includes('image/jpeg,image/png,image/webp'))
add('Rooms cards retain live status controls', rooms.includes('requestStatus(room, event.target.value)'))
add('Rooms cards retain archive action', rooms.includes('archiveRoom(hotel.id, room.id, reason)'))
add('Rooms edit flow preserved', rooms.includes('openRoomEditor(room)') && rooms.includes("setActiveTab('room-form')"))
add('Room QR readiness is live-backed', rooms.includes(".from('room_qr_codes')") && rooms.includes('qrRoomIds.has(room.id)'))
add('Day13 room contracts retained', rooms.includes('Atomic room import') && rooms.includes('Immutable room-status history') && rooms.includes('active_reservations'))
add('Room card CSS follows approved surface tokens', roomCss.includes('--r22-bg:#06080b') && roomCss.includes('--r22-panel:#0f141a'))
add('Room photo visual card is implemented', roomCss.includes('.rooms22-photo{height:112px'))
add('No solid gold room card background', !/\.rooms22-card[^}]*background\s*:\s*#(?:d4af37|e8bd45|e0b92f)/i.test(roomCss))
add('REV22 CSS is presentation-only', !/fetch\(|createClient\(|supabase\./i.test(css))

let passed = 0
for (const check of checks) {
  console.log(`${check.ok ? 'PASS' : 'FAIL'} ${check.name}`)
  if (check.ok) passed += 1
}
console.log(JSON.stringify({ checks: checks.length, passed, failed: checks.length - passed }))
if (passed !== checks.length) process.exit(1)
