import fs from 'node:fs'
import path from 'node:path'

const root = process.cwd()
const cssPath = path.join(root, 'src/styles/finalRev54ThemeParity.css')
const mainPath = path.join(root, 'src/main.jsx')

const css = fs.existsSync(cssPath) ? fs.readFileSync(cssPath, 'utf8') : ''
const main = fs.existsSync(mainPath) ? fs.readFileSync(mainPath, 'utf8') : ''
const checks = []
const add = (name, pass, detail = '') => checks.push({ name, pass: Boolean(pass), detail })

add('REV54 stylesheet exists', fs.existsSync(cssPath))
add('REV54 stylesheet imported once', (main.match(/finalRev54ThemeParity\.css/g) || []).length === 1)
add('REV54 import follows App import', main.indexOf("import App from './App.jsx'") >= 0 && main.indexOf('finalRev54ThemeParity.css') > main.indexOf("import App from './App.jsx'"))
add('Canonical page token', css.includes('--sq54-bg: #06080b'))
add('Canonical panel token', css.includes('--sq54-panel: #0f141a'))
add('Canonical control token', css.includes('--sq54-elev: #090c11'))
add('Canonical border token', css.includes('--sq54-line: #27303a'))
add('Live marker token', css.includes('--sq54-theme-parity: 1'))

const required = [
  ['Global Search', '.global-search-dialog'],
  ['Service catalogue', '.service-catalogue-panel'],
  ['Service cards', '.service-type-card'],
  ['Reservations', '.reservation-form-section'],
  ['Reservation detail', '.reservation-room-card'],
  ['Reservation operations', '.operations-control-panel'],
  ['Booking calendar', '.calendar-toolbar'],
  ['Check-In cards', '.simple-checkin-card'],
  ['Check-In occupants', '.simple-occupant-card'],
  ['Guest Contact & Consent', '.guest-comms-card'],
  ['Guest directory', '.guest-directory-toolbar'],
  ['Guest Guide editing language', '.simple-builder-toolbar'],
  ['Guest Guide setup summary', '.rev35-setup-summary'],
  ['Category service windows', '.menu15-panel'],
  ['Food kitchen board', '.day15-kitchen-column'],
  ['Food completed activity', '.day15-terminal-card'],
  ['Housekeeping/Maintenance', '.day13-panel'],
  ['Housekeeping/Maintenance action dialog', '.stayqr-action-dialog'],
  ['Invoice tax cards', '.day12-rate-card'],
  ['Staff responsive cards', '.staff-table tr'],
  ['Hotel Setup', '.config-card'],
]
for (const [name, selector] of required) add(`${name} parity selector`, css.includes(selector), selector)

// Scope guard: REV54 is colour/surface-only. Every ordinary declaration must be
// background/background-image/background-color/border-color; custom properties are allowed.
const blockBodies = [...css.matchAll(/\{([^{}]*)\}/gs)].map((m) => m[1])
const disallowedDeclarations = []
for (const body of blockBodies) {
  const withoutComments = body.replace(/\/\*[\s\S]*?\*\//g, '')
  for (const raw of withoutComments.split(';')) {
    const decl = raw.trim()
    if (!decl || !decl.includes(':')) continue
    const prop = decl.slice(0, decl.indexOf(':')).trim().toLowerCase()
    if (prop.startsWith('--')) continue
    if (!['background', 'background-color', 'background-image', 'border-color'].includes(prop)) {
      disallowedDeclarations.push(prop)
    }
  }
}
add('Only surface-colour declarations are present', disallowedDeclarations.length === 0, [...new Set(disallowedDeclarations)].join(', '))

// Protect semantic red/warning states that are already correct.
add('Overdue service SLA red state preserved', css.includes('.service-request-card:not(.overdue) .service-sla'))
add('No unconditional service SLA override', !/\.service-sla\s*\{/.test(css.replace('.service-request-card:not(.overdue) .service-sla', '')))
add('Menu primary/danger actions excluded from neutral override', css.includes('button:not(.menu15-primary):not(.danger)'))
add('Staff Suspend danger action excluded from neutral override', css.includes('.staff-actions button:not(.danger)'))
add('Service danger actions excluded from neutral override', css.includes('.service-card-actions button:not(.gold):not(.danger)'))
add('Reservation warning/danger reason excluded', css.includes('.reservation-status-reason:not(.danger):not(.warning)'))
add('Reservation row primary/danger actions excluded', css.includes('.reservation-row-actions button:not(.danger):not(.primary)'))
add('Calendar danger action excluded', css.includes('.calendar-btn:not(.primary):not(.danger)'))
add('Guest provider readiness semantic state untouched', !css.includes('.guest-provider-readiness'))
add('Hotel setup active toggle semantic state preserved', css.includes('.toggle-chip:not(.active)'))

// Explicitly ensure already-approved public/auth/media/print surfaces are not targeted.
add('No public booking selector', !/public-booking|publicbooking/i.test(css))
add('No public Guest Guide selector', !/\.guest-guide-page|\.guest-shell|\.guest-menu-page/i.test(css))
add('No auth/login selector', !/sq-login|login-page|auth-page/i.test(css))
add('Printed invoice paper untouched', !/^\s*#root[^\n]*\.day12-paper\b/m.test(css))
const cssNoComments = css.replace(/\/\*[\s\S]*?\*\//g, '')
add('No image/media styling', !/(?:\bimg\b|video|object-fit|background-image\s*:\s*url)/i.test(cssNoComments.replace(/background-image:\s*none/gi, '')))
add('No environment coupling', !/eecinuh|rbyirbo|netlify\.app|supabase\.co/i.test(css))
add('No secret markers', !/service_role|api[_-]?key|client_secret|access_token/i.test(css))

const failed = checks.filter((c) => !c.pass)
for (const c of checks) console.log(`${c.pass ? 'PASS' : 'FAIL'} ${c.name}${c.detail ? ` :: ${c.detail}` : ''}`)
console.log(JSON.stringify({ checks: checks.length, passed: checks.length - failed.length, failed: failed.length }))
if (failed.length) process.exit(1)
