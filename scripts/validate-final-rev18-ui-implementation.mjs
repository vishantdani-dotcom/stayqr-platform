import fs from 'node:fs'
import path from 'node:path'

const root = process.cwd()
const read = (p) => fs.readFileSync(path.join(root, p), 'utf8')
const exists = (p) => fs.existsSync(path.join(root, p))
let passed = 0
let failed = 0

function check(label, ok) {
  if (ok) {
    console.log(`PASS ${label}`)
    passed += 1
  } else {
    console.error(`FAIL ${label}`)
    failed += 1
  }
}

const main = read('src/main.jsx')
const index = read('index.html')
const css = read('src/styles/finalRev18.css')
const login = read('src/pages/auth/Login.jsx')
const loginCss = read('src/pages/auth/Login.css')
const rooms = read('src/components/table/RoomsTable.jsx')
const roomsCss = read('src/components/table/RoomsTable.css')
const calendar = read('src/pages/calendar/BookingCalendar.jsx')
const dashboard = read('src/pages/dashboard/Dashboard.jsx')
const sidebar = read('src/components/sidebar/Sidebar.jsx')
const guests = read('src/pages/guests/Guests.jsx')

check('REV18 stylesheet exists', exists('src/styles/finalRev18.css') && css.length > 12000)
check('REV18 stylesheet imports after REV13/14 styles', /finalModern\.css['"]\s*\nimport ['"]\.\/styles\/finalRev18\.css/.test(main))
check('Poppins production font is linked with real weights', /Poppins:wght@400;500;600;700;800/.test(index))
check('REV18 disables font synthesis', /font-synthesis:none/.test(css))
check('REV18 removes navbar glass blur', /\.navbar\{[^}]*backdrop-filter:none!important/s.test(css))
check('REV18 keeps official StayQR tagline', login.includes('Simplifying Checkinn'))
check('Login preserves signInWithPassword', login.includes('supabase.auth.signInWithPassword'))
check('Login preserves signUp', login.includes('supabase.auth.signUp'))
check('Login preserves password reset', login.includes('supabase.auth.resetPasswordForEmail'))
check('Login contains responsive visual media panel', login.includes('sq-login-visual') && loginCss.includes('.sq-login-visual'))
check('Login preserves StayQR logo asset', login.includes("../../assets/stayqr-logo.png"))
check('Login has accessible password reveal controls', /aria-label=\{showPassword \? 'Hide password' : 'Show password'\}/.test(login))
check('Rooms expose mobile card layout', rooms.includes('rooms-mobile-list') && rooms.includes('room-mobile-card'))
check('Rooms mobile layout is hidden on desktop and enabled on phones', roomsCss.includes('.rooms-mobile-list') && /@media\s*\(max-width:\s*720px\)/.test(roomsCss))
check('Booking Calendar exposes mobile agenda', calendar.includes('calendar-mobile-agenda') && calendar.includes('calendar-mobile-event'))
check('Guests expose mobile active-stay cards', guests.includes('guests-active-mobile') && guests.includes('guest-active-card'))
check('Dashboard metrics use SVG icons instead of emoji', dashboard.includes('function MetricIcon') && !dashboard.includes('icon="🏨"') && !dashboard.includes('icon="🍽️"'))
check('Sidebar menu icon uses SVG utensil icon', sidebar.includes('function UtensilsIcon') && !sidebar.includes("icon: '🍽️'"))
check('REV18 includes mobile calendar refinement', css.includes('.calendar-mobile-agenda'))
check('REV18 includes mobile guest cards refinement', css.includes('.guests-active-mobile'))
check('REV18 includes mobile scanner refinement', css.includes('.document-scanner-modal'))
check('REV18 includes Guest Guide refinement', css.includes('.ag-hero-content') && css.includes('.ag-feedback-form'))
check('REV18 includes food ordering refinement', css.includes('.food-guest-page') && css.includes('.food-mobile-cart'))
check('REV18 includes housekeeping refinement', css.includes('.day13-checklist') && css.includes('.day13-check'))
check('REV18 includes payments refinement', css.includes('.payments-modern-table-card'))
check('REV18 includes Guest Bills refinement', css.includes('.folio-table-wrap'))
check('REV18 includes Reports digit hardening', /font-variant-numeric:tabular-nums!important;white-space:nowrap!important/.test(css))
check('REV18 includes invoice refinement', css.includes('.day12-paper'))
check('REV18 includes mobile room register cards', css.includes('.room-register-table'))
check('No legacy alternate StayQR tagline reintroduced in REV18 files', !/Smart Digital Hospitality|Scan\.? Stay\.? Simplified/i.test([css, login, dashboard, sidebar].join('\n')))
check('No database/provider migration is part of REV18 UI source', !main.includes('supabase/migrations') && !css.includes('CASHFREE') && !css.includes('WHATSAPP_AUTOMATION'))

console.log(JSON.stringify({ checks: passed + failed, passed, failed }))
if (failed) process.exit(1)
