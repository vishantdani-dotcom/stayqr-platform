import fs from 'node:fs'
import path from 'node:path'

const root = process.cwd()
const read = (p) => fs.readFileSync(path.join(root, p), 'utf8')
let passed = 0
let failed = 0
function check(name, ok) {
  console.log(`${ok ? 'PASS' : 'FAIL'} ${name}`)
  ok ? passed++ : failed++
}

const main = read('src/main.jsx')
const app = read('src/App.jsx')
const appCss = read('src/App.css')
const polish = read('src/styles/finalPolish.css')
const sidebar = read('src/components/sidebar/Sidebar.jsx')
const env = read('.env.example')
const html = read('index.html')

check('Final polish stylesheet exists and is substantive', polish.length > 9000)
check('Final polish loads after responsive stylesheet', main.indexOf("./styles/finalPolish.css") > main.indexOf("./styles/responsive.css"))
check('Final polish is scoped to internal app content', polish.includes('.app-content'))
check('Final polish includes navbar refinement', polish.includes('/* ----- Navbar ----- */'))
check('Final polish includes sidebar refinement', polish.includes('/* ----- Sidebar ----- */'))
check('Final polish includes mobile refinement', polish.includes('/* ----- Mobile refinement ----- */'))
check('Guest Bills terminology replaces folio settlement route label', app.includes("folios: 'guest bills'"))
check('Fallback page no longer exposes StayQR v1.0 development copy', !app.includes('being prepared for StayQR v1.0'))
check('Legacy Vite counter selector removed from App.css', !appCss.includes('.counter'))
check('Legacy Vite hero selector removed from App.css', !appCss.includes('.hero'))
check('App.css retains tenant switch loading UX', appCss.includes('.tenant-switch-overlay') && appCss.includes('.tenant-switch-spinner'))
check('Sidebar retains commercial Room QR Guides label', sidebar.includes('Room QR Guides'))
check('Cashfree subscriptions remain disabled by default', env.includes('CASHFREE_SUBSCRIPTIONS_ENABLED=false'))
check('WhatsApp automation remains disabled by default', env.includes('WHATSAPP_AUTOMATION_ENABLED=false'))
check('Online UIDAI remains disabled by default', env.includes('UIDAI_ONLINE_AUTH_ENABLED=false'))
check('Application stays noindex', /robots[^>]+noindex/i.test(html))
check('No staging Supabase ref is hard-coded into source UI', !read('src/App.jsx').includes('eecinuhvkxlbdvyuazal'))

const allSource = [...walk(path.join(root, 'src'))].filter(p => /\.(js|jsx|css)$/.test(p)).map(p => fs.readFileSync(p, 'utf8')).join('\n')
check('Notification mojibake remains absent', !/[≠ƒΓÃ]/.test(allSource))
check('No customer NEW/V1.1 badges reintroduced in sidebar', !/\bNEW\b|V1\.1/.test(sidebar))

console.log(JSON.stringify({ checks: passed + failed, passed, failed }))
if (failed) process.exit(1)

function* walk(dir) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, entry.name)
    if (entry.isDirectory()) yield* walk(p)
    else yield p
  }
}
