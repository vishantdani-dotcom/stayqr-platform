import fs from 'node:fs'
import path from 'node:path'
import process from 'node:process'

const root = process.cwd()
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8')

const app = read('src/App.jsx')
const dashboard = read('src/pages/dashboard/Dashboard.jsx')
const operations = read('src/pages/operationscenter/OperationsCenter.jsx')
const operationsCss = read('src/pages/operationscenter/OperationsCenter.css')

const checks = [
  ['Operations Centre receives navigation tab intent', /initialTab=\{navigationRequest\?\.initialTab \|\| 'notifications'\}/.test(app)],
  ['Operations Centre receives create-ticket intent', /initialAction=\{navigationRequest\?\.initialAction \|\| null\}/.test(app)],
  ['Report Issue deep-links to Support', /initialTab:\s*'support'[\s\S]{0,120}?initialAction:\s*'create-ticket'/.test(dashboard)],
  ['Get Support opens Support workspace', /actionId === 'support'[\s\S]{0,180}?initialTab:\s*'support'/.test(dashboard)],
  ['Support workspace uses existing createSupportTicket contract', /createSupportTicket\([\s\S]{0,220}?hotelId/.test(operations)],
  ['Support workspace includes ticket creation form', /Create support ticket/.test(operations) && /Submit issue/.test(operations)],
  ['Published support hours remain unchanged', /09:00–19:00 IST, Monday–Saturday/.test(operations)],
  ['Support composer has responsive styling', /\.d17-support-toolbar/.test(operationsCss) && /@media\(max-width:700px\)/.test(operationsCss)],
]

let passed = 0
checks.forEach(([label, ok], index) => {
  if (ok) passed += 1
  console.log(`${ok ? 'PASS' : 'FAIL'} ${String(index + 1).padStart(2, '0')} | ${label}`)
})

const forbidden24x7 = /24\s*[×xX]\s*7|24\/7/i.test(`${dashboard}\n${operations}`)
if (forbidden24x7) {
  console.log('FAIL 09 | No unsupported 24x7 support claim')
} else {
  passed += 1
  console.log('PASS 09 | No unsupported 24x7 support claim')
}

if (passed !== 9) {
  console.error(`POSTLAUNCH_BATCH2_BROWSERFIX_SOURCE_ACCEPTANCE: FAIL (${passed}/9)`)
  process.exit(1)
}

console.log('POSTLAUNCH_BATCH2_BROWSERFIX_SOURCE_ACCEPTANCE: PASS (9/9)')
