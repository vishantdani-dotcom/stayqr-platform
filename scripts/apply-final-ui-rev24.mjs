import fs from 'node:fs'
import path from 'node:path'

const repo = process.cwd()
const mainPath = path.join(repo, 'src', 'main.jsx')
const rev22Path = path.join(repo, 'src', 'styles', 'finalRev22.css')
const rev24Path = path.join(repo, 'src', 'styles', 'finalRev24.css')
const housekeepingPath = path.join(repo, 'src', 'pages', 'housekeeping', 'Housekeeping.jsx')

function fail(message) {
  console.error(`FAIL ${message}`)
  process.exit(1)
}

for (const required of [mainPath, rev22Path, rev24Path, housekeepingPath]) {
  if (!fs.existsSync(required)) fail(`Required file missing: ${path.relative(repo, required)}`)
}

let main = fs.readFileSync(mainPath, 'utf8')
const housekeeping = fs.readFileSync(housekeepingPath, 'utf8')

if (!main.includes("./styles/finalRev22.css")) {
  fail('Accepted REV22 stylesheet import is missing. REV24 will not guess a baseline.')
}
if (!housekeeping.includes('className="day13-check"') || !housekeeping.includes('type="checkbox"')) {
  fail('Expected live Housekeeping checklist source is missing.')
}

// Remove the rejected REV23 presentation layer completely.
main = main
  .split(/\r?\n/)
  .filter((line) => !line.includes("./styles/finalRev23.css") && !line.includes("./styles/finalRev24.css"))
  .join('\n')

main = main.replace(
  "import './styles/finalRev22.css'",
  "import './styles/finalRev22.css'\nimport './styles/finalRev24.css'"
)
fs.writeFileSync(mainPath, main.endsWith('\n') ? main : `${main}\n`, 'utf8')

for (const relative of [
  'src/styles/finalRev23.css',
  'scripts/apply-final-ui-rev23.mjs',
  'scripts/validate-final-ui-rev23.mjs',
  'docs/commercial-ready/FINAL_UI_POLISH_REV23.md',
  'docs/commercial-ready/REV23_FINAL_BROWSER_REVIEW.md',
]) {
  const target = path.join(repo, relative)
  if (fs.existsSync(target)) {
    fs.rmSync(target, { force: true })
    console.log(`PASS removed rejected REV23 file ${relative}`)
  }
}

console.log('PASS REV23 presentation layer removed')
console.log('PASS REV22 FIX4 remains the visual authority')
console.log('PASS REV24 surgical polish imported after REV22')
console.log('PASS Dashboard/sidebar/login functional and presentation source intentionally unchanged')
console.log('PASS Housekeeping operational JSX intentionally unchanged')
