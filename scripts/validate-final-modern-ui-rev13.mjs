import fs from 'node:fs'

const read = (file) => fs.readFileSync(file, 'utf8')
const checks = []
function check(name, ok) {
  checks.push([name, Boolean(ok)])
  console.log(`${ok ? 'PASS' : 'FAIL'} ${name}`)
}

const main = read('src/main.jsx')
const modern = read('src/styles/finalModern.css')
const navbar = read('src/components/navbar/Navbar.css')
const payments = read('src/pages/payments/Payments.jsx')
const calendar = read('src/pages/calendar/BookingCalendar.jsx')
const reports = read('src/pages/reports/Reports.jsx')
const guideCopy = read('src/lib/guestGuideI18n.js')
const guideCss = read('src/pages/guestguide/GuestGuide.css')
const guideBuilder = read('src/pages/guestbuilder/GuestGuideBuilder.jsx')
const hotelProfile = read('src/pages/hotel/HotelProfile.jsx')
const menu = read('src/pages/menumanagement/MenuManagement.jsx')
const srcFiles = [
  'src/lib/guestGuideI18n.js',
  'src/pages/guestbuilder/GuestGuideBuilder.jsx',
  'src/pages/hotel/HotelProfile.jsx',
  'src/pages/menumanagement/MenuManagement.jsx',
  'src/pages/guestguide/GuestGuide.jsx',
].map(read).join('\n')

check('REV13 modern stylesheet is imported after REV12', /finalPolish\.css['"]\s*\nimport ['"]\.\/styles\/finalModern\.css/.test(main))
check('REV13 modern stylesheet is substantive', modern.length > 12000)
check('Modern UI uses system sans display stack', modern.includes('--font-display: "Segoe UI Variable Display"'))
check('Internal app removes backdrop blur from navbar/notification surfaces', modern.includes('.navbar,') && modern.includes('backdrop-filter: none !important'))
check('Read notifications keep full-opacity crisp text', modern.includes('.notif-item.read') && modern.includes('opacity: 1 !important'))
check('Notification cards use readable 12.5px titles', modern.includes('font-size: 12.5px !important'))
check('Calendar identifies itself as Reservations & Room Planning', calendar.includes('Reservations &amp; Room Planning'))
check('Calendar workspace is full-width instead of squeezed by queue', modern.includes('.calendar-workspace') && modern.includes('grid-template-columns: minmax(0, 1fr) !important'))
check('Calendar assignment queue moves below timeline', modern.includes('.unallocated-panel') && modern.includes('position: static !important'))
check('Calendar room lane is narrower and cleaner', modern.includes('grid-template-columns: 180px minmax(0,1fr) !important'))
check('Housekeeping uses custom modern checkboxes', modern.includes('.day13-check input[type="checkbox"]') && modern.includes('appearance: none !important'))
check('Housekeeping cards use quieter surface treatment', modern.includes('.day13-card') && modern.includes('background: var(--sqm-surface) !important'))
check('Payments exposes modern styling hooks', payments.includes('payments-modern-stats') && payments.includes('payments-modern-table'))
check('Payments uses compact sticky table header', modern.includes('.payments-modern-table th') && modern.includes('position: sticky'))
check('Guest Bills uses larger readable table/subcopy', modern.includes('.folio-table td') && modern.includes('font-size: 11.5px !important'))
check('Reports title is modern Reports & Insights', reports.includes('Reports &amp; Insights'))
check('Reports metrics cannot split currency digits across lines', modern.includes('.reports-metric-card > strong') && modern.includes('white-space: nowrap !important'))
check('Reports use modern sans display typography', modern.includes('.reports-hero h1') && modern.includes('font-family: var(--font-display) !important'))
check('Invoices use modern table density', modern.includes('.day12-table td') && modern.includes('font-size: 11.5px !important'))
check('Invoice paper uses the product font instead of legacy Arial look', modern.includes('.day12-paper') && modern.includes('font-family: var(--font-body) !important'))
check('Guest Guide no longer imports Playfair Display', !guideCss.includes('Playfair Display'))
check('Guest Guide heading font is Inter/system sans', guideCss.includes("--ag-head: 'Inter', system-ui, sans-serif"))
check('Guest Guide hero uses compact modern heading sizes', modern.includes('.ag-hero h1 strong') && modern.includes('font-size: clamp(38px,6vw,64px) !important'))
check('Guest Guide thank-you heading uses modern sans sizing', modern.includes('.ag-thankyou h2') && modern.includes('font-size: clamp(30px,5vw,42px) !important'))
check('Official StayQR tagline is forced to Simplifying Checkinn', guideCopy.includes("stayqrTagline: 'Simplifying Checkinn'"))
check('Legacy Smart Digital Hospitality tagline is absent from patched UI source', !/Smart Digital Hospitality/i.test(srcFiles))
check('Legacy Scan Stay Simplified tagline is absent from patched UI source', !/Scan[. ·•-]*\s*Stay[. ·•-]*\s*Simplified/i.test(srcFiles))
check('Hotel profile default no longer uses luxury branding language', !/Luxury Smart Hospitality Experience/i.test(hotelProfile))
check('Menu Management no longer shows Premium Dining as a product label', !menu.includes('Premium Dining · Language & Offer Studio'))
check('Guest builder uses modern Inter heading font', guideBuilder.includes("heading_font: 'Inter'"))
check('Guest builder uses only the approved StayQR tagline', guideBuilder.includes("stayqr_tagline: 'Simplifying Checkinn'"))
check('REV13 keeps existing notification implementation source available', navbar.includes('.notif-dropdown'))

const passed = checks.filter(([, ok]) => ok).length
const failed = checks.length - passed
console.log(JSON.stringify({ checks: checks.length, passed, failed }))
if (failed) process.exit(1)
