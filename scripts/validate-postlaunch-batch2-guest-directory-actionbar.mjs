import fs from 'node:fs'
import path from 'node:path'

const root = process.cwd()
const read = (p) => fs.readFileSync(path.join(root, p), 'utf8')

const jsx = read('src/pages/guests/GuestDirectory.jsx')
const css = read('src/pages/guests/GuestDirectory.css')

const checks = [
  ['Export button has stable action class', jsx.includes('guest-directory-export-btn')],
  ['Refresh button has stable action class', jsx.includes('guest-directory-refresh-btn')],
  ['Action bar allows shrinking instead of forcing 520px minimum', css.includes('flex: 0 1 640px;') && css.includes('min-width: 0;')],
  ['Search input flexes independently from buttons', css.includes('flex: 1 1 300px;') && css.includes('width: auto;')],
  ['Export button has readable minimum width', css.includes('.guest-directory-export-btn') && css.includes('min-width: 116px;')],
  ['Refresh button has readable minimum width', css.includes('.guest-directory-refresh-btn') && css.includes('min-width: 148px;')],
  ['Toolbar stacks before controls become cramped', css.includes('@media (max-width: 1180px)')],
  ['Mobile controls become full-width', css.includes('width: 100%;') && css.includes('align-items: stretch;')],
  ['CSV export safety notice remains present', jsx.includes('CSV exports exclude identity documents.')]
]

let passed = 0
checks.forEach(([label, ok], index) => {
  if (ok) {
    passed += 1
    console.log(`PASS ${String(index + 1).padStart(2, '0')} | ${label}`)
  } else {
    console.error(`FAIL ${String(index + 1).padStart(2, '0')} | ${label}`)
  }
})

if (passed !== checks.length) {
  console.error(`POSTLAUNCH_BATCH2_GUEST_DIRECTORY_ACTIONBAR: FAIL (${passed}/${checks.length})`)
  process.exit(1)
}

console.log(`POSTLAUNCH_BATCH2_GUEST_DIRECTORY_ACTIONBAR: PASS (${passed}/${checks.length})`)
