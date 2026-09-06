import fs from 'node:fs'
import path from 'node:path'

const repo = process.cwd()
const mainPath = path.join(repo, 'src', 'main.jsx')
const dashboardPath = path.join(repo, 'src', 'pages', 'dashboard', 'Dashboard.jsx')

function fail(message) {
  console.error(`FAIL ${message}`)
  process.exit(1)
}

function addHookForStyleVar(source, styleVar, className, { required = false } = {}) {
  if (source.includes(className)) return { source, status: 'already' }

  const escaped = styleVar.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
  const tagRegex = new RegExp(`<([A-Za-z][\\w.-]*)([^>]*?)style=\\{${escaped}\\}([^>]*)>`, 'm')
  const match = source.match(tagRegex)
  if (match) {
    const [whole, tag, before, after] = match
    if (/className\s*=/.test(whole)) {
      const stringClass = whole.match(/className\s*=\s*(["'])(.*?)\1/)
      if (stringClass) {
        const nextClass = `${stringClass[2]} ${className}`.trim()
        const replaced = whole.replace(stringClass[0], `className=${stringClass[1]}${nextClass}${stringClass[1]}`)
        return { source: source.replace(whole, replaced), status: 'patched' }
      }
      console.warn(`WARN ${styleVar} has a non-literal className; leaving JSX unchanged and relying on REV22 CSS fallback`)
      return { source, status: 'fallback' }
    }
    const replaced = `<${tag}${before}className="${className}" style={${styleVar}}${after}>`
    return { source: source.replace(whole, replaced), status: 'patched' }
  }

  if (required) fail(`Dashboard REV22 required anchor missing: style={${styleVar}}`)
  console.warn(`WARN Dashboard style hook not found for ${styleVar}; REV22 CSS fallback will be used`)
  return { source, status: 'fallback' }
}

if (!fs.existsSync(mainPath)) fail('src/main.jsx not found')
if (!fs.existsSync(dashboardPath)) fail('src/pages/dashboard/Dashboard.jsx not found')

let main = fs.readFileSync(mainPath, 'utf8')
if (!main.includes("./styles/finalRev21.css")) {
  fail('REV21 import marker missing. Apply REV22 only after the current REV21 staging state.')
}
if (!main.includes("./styles/finalRev22.css")) {
  main = main.replace(
    "import './styles/finalRev21.css'",
    "import './styles/finalRev21.css'\nimport './styles/finalRev22.css'"
  )
  fs.writeFileSync(mainPath, main, 'utf8')
  console.log('PASS finalRev22.css import added after REV21')
} else {
  console.log('PASS finalRev22.css import already present')
}

let dashboard = fs.readFileSync(dashboardPath, 'utf8')

// The only required dashboard hook is the analytics grid. REV21/REV20 changed the
// card markup several times, so REV22 FIX1 deliberately does not depend on one
// exact <div style={analyticsCard}> shape. This keeps the patch compatible with
// the actual staging source while still allowing CSS to neutralise every card.
const gridResult = addHookForStyleVar(dashboard, 'analyticsGrid', 'dash-analytics-grid', { required: true })
dashboard = gridResult.source
console.log(`PASS dashboard analytics grid hook ${gridResult.status}`)

for (const [styleVar, className] of [
  ['analyticsCard', 'dash-analytics-card'],
  ['analyticsIcon', 'dash-analytics-icon'],
  ['analyticsTitle', 'dash-analytics-title'],
  ['analyticsValue', 'dash-analytics-value'],
]) {
  const result = addHookForStyleVar(dashboard, styleVar, className)
  dashboard = result.source
  console.log(`${result.status === 'patched' || result.status === 'already' ? 'PASS' : 'WARN'} dashboard ${styleVar} hook ${result.status}`)
}

fs.writeFileSync(dashboardPath, dashboard, 'utf8')
console.log('PASS dashboard REV22 integration completed without brittle card-anchor dependency')
