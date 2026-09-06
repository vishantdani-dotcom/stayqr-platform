import fs from 'node:fs'
import path from 'node:path'

const repo = process.cwd()
const mainPath = path.join(repo, 'src', 'main.jsx')
const rev22Path = path.join(repo, 'src', 'styles', 'finalRev22.css')
const rev23Path = path.join(repo, 'src', 'styles', 'finalRev23.css')
const housekeepingPath = path.join(repo, 'src', 'pages', 'housekeeping', 'Housekeeping.jsx')

function fail(message) {
  console.error(`FAIL ${message}`)
  process.exit(1)
}

for (const required of [mainPath, rev22Path, rev23Path, housekeepingPath]) {
  if (!fs.existsSync(required)) fail(`Required file missing: ${path.relative(repo, required)}`)
}

let main = fs.readFileSync(mainPath, 'utf8')
const housekeeping = fs.readFileSync(housekeepingPath, 'utf8')

if (!main.includes("./styles/finalRev22.css")) {
  fail('REV22 import marker missing. REV23 must be applied only after the accepted REV22 FIX4 staging state.')
}
if (!housekeeping.includes('className="day13-check"') || !housekeeping.includes('type="checkbox"')) {
  fail('Expected Housekeeping operational checklist source is missing.')
}

if (!main.includes("./styles/finalRev23.css")) {
  main = main.replace(
    "import './styles/finalRev22.css'",
    "import './styles/finalRev22.css'\nimport './styles/finalRev23.css'"
  )
  fs.writeFileSync(mainPath, main, 'utf8')
  console.log('PASS finalRev23.css import added immediately after REV22')
} else {
  console.log('PASS finalRev23.css import already present')
}

console.log('PASS Housekeeping functional JSX intentionally unchanged; REV23 fixes the control at presentation layer')
console.log('PASS REV23 source integration complete')
