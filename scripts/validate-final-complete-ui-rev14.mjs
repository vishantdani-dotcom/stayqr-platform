import fs from 'node:fs'

const read = (p) => fs.readFileSync(p, 'utf8')
const checks = []
const check = (name, ok) => {
  checks.push([name, Boolean(ok)])
  console.log(`${ok ? 'PASS' : 'FAIL'} ${name}`)
}

const main = read('src/main.jsx')
const polish = read('src/styles/finalPolish.css')
const modern = read('src/styles/finalModern.css')
const app = read('src/App.jsx')
const appCss = read('src/App.css')
const reports = read('src/pages/reports/Reports.jsx')
const calendar = read('src/pages/calendar/BookingCalendar.jsx')
const payments = read('src/pages/payments/Payments.jsx')
const guideCopy = read('src/lib/guestGuideI18n.js')

check('REV12 final polish stylesheet remains loaded', main.includes("./styles/finalPolish.css"))
check('REV13 modern layer loads after REV12', main.indexOf('./styles/finalModern.css') > main.indexOf('./styles/finalPolish.css'))
check('REV12 polish remains substantive', polish.length > 9000)
check('REV13 modern layer remains substantive', modern.length > 12000)
check('Guest Bills terminology is preserved', app.includes("folios: 'guest bills'"))
check('Legacy Vite starter counter/hero styles remain removed', !appCss.includes('.counter') && !appCss.includes('.hero'))
check('Notification blur mitigation is present', modern.includes('backdrop-filter: none !important'))
check('Booking Calendar final planning layout is present', calendar.includes('Reservations &amp; Room Planning'))
check('Payments final modern hooks are present', payments.includes('payments-modern-stats') && payments.includes('payments-modern-table'))
check('Reports title and KPI layout are final', reports.includes('Reports &amp; Insights') && modern.includes('white-space: nowrap !important'))
check('Official StayQR tagline is Simplifying Checkinn', guideCopy.includes("stayqrTagline: 'Simplifying Checkinn'"))
check('Meta automation remains disabled by default', read('.env.example').includes('WHATSAPP_AUTOMATION_ENABLED=false'))
check('Cashfree subscriptions remain disabled by default', read('.env.example').includes('CASHFREE_SUBSCRIPTIONS_ENABLED=false'))
check('Online UIDAI remains disabled by default', read('.env.example').includes('UIDAI_ONLINE_AUTH_ENABLED=false'))

const passed = checks.filter(([, ok]) => ok).length
const failed = checks.length - passed
console.log(JSON.stringify({ checks: checks.length, passed, failed }))
if (failed) process.exit(1)
