import fs from 'node:fs'
import path from 'node:path'

const root = process.cwd()
const read = (f) => fs.readFileSync(path.join(root, f), 'utf8')
const walk = (dir) => {
  const out = []
  for (const entry of fs.readdirSync(path.join(root, dir), { withFileTypes: true })) {
    const rel = path.join(dir, entry.name)
    if (entry.isDirectory()) out.push(...walk(rel))
    else if (/\.(js|jsx|css|html|md)$/.test(entry.name)) out.push(rel)
  }
  return out
}

const checks = []
function check(name, ok) {
  checks.push({ name, ok: Boolean(ok) })
  console.log(`${ok ? 'PASS' : 'FAIL'} ${name}`)
}

const env = read('.env.example')
const pkg = JSON.parse(read('package.json'))
const index = read('index.html')
const sidebar = read('src/components/sidebar/Sidebar.jsx')
const navbar = read('src/components/navbar/Navbar.jsx')
const qr = read('src/pages/qr/QRGenerator.jsx')
const ownerBilling = read('src/pages/billing/OwnerBilling.jsx')
const allSrc = walk('src').map(read).join('\n')

check('Application package is StayQR', pkg.name === 'stayqr-platform')
check('Application title is StayQR branded', /<title>StayQR/i.test(index))
check('Application routes remain noindex', /name=["']robots["'][^>]*noindex/i.test(index) || /noindex/i.test(index))
check('WhatsApp automation remains off by default', /WHATSAPP_AUTOMATION_ENABLED=false/.test(env))
check('Cashfree launch remains off by default', /CASHFREE_LAUNCH_ENABLED=false/.test(env) || /CASHFREE.*false/i.test(env))
check('UIDAI online auth remains off by default', /UIDAI_ONLINE_AUTH_ENABLED=false/.test(env) || /UIDAI.*false/i.test(env))
check('Manual billing remains launch billing', /manual/i.test(ownerBilling) && !/Cashfree.*required/i.test(ownerBilling))
check('Sidebar uses commercial Room QR Guides label', sidebar.includes('Room QR Guides'))
check('Sidebar uses Guest Bills label', sidebar.includes('Guest Bills'))
check('Zero-PIN room QR flow remains present', /zero[- ]?pin|no pin|automatically/i.test(qr))
check('Notification navbar contains no mojibake glyphs', !/[Γ≡ƒ]/.test(navbar))
check('Notification centre is reachable', navbar.includes('View all notifications'))
check('No staging Netlify URL is hard-coded into src', !allSrc.includes('stayqr-pilot-staging.netlify.app'))
check('No service role key literal is present in frontend src', !/service_role_key|SUPABASE_SERVICE_ROLE_KEY/.test(allSrc))
check('No customer-facing build labels remain in navbar/sidebar', !navbar.includes('V1.1') && !sidebar.includes('V1.1') && !sidebar.includes("badge: 'NEW'") && !sidebar.includes("badge: 'V1.1'"))

const failed = checks.filter((x) => !x.ok)
console.log(JSON.stringify({ checks: checks.length, passed: checks.length - failed.length, failed: failed.length }))
if (failed.length) process.exit(1)
