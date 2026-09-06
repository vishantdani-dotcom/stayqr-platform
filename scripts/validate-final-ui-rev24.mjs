import fs from 'node:fs'

const read = (file) => fs.readFileSync(file, 'utf8')
const checks = []
const add = (name, ok) => checks.push({ name, ok: Boolean(ok) })

const main = read('src/main.jsx')
const rev22 = read('src/styles/finalRev22.css')
const css = read('src/styles/finalRev24.css')
const housekeeping = read('src/pages/housekeeping/Housekeeping.jsx')

add('REV22 remains imported', main.includes("./styles/finalRev22.css"))
add('REV24 imported immediately after REV22', /finalRev22\.css['"]\s*\nimport ['"]\.\/styles\/finalRev24\.css/.test(main))
add('Rejected REV23 import removed', !main.includes('finalRev23.css'))
add('Rejected REV23 stylesheet removed', !fs.existsSync('src/styles/finalRev23.css'))
add('Approved REV22 gold accent retained', rev22.includes('--sq22-accent:#e8bd45'))
add('REV24 does not override REV22 palette tokens', !/--sq22-(?:accent|bg|panel|text|muted)\s*:/.test(css))
add('REV24 does not change fonts', !/font-family\s*:/i.test(css))
add('No rejected blue accent values in REV24', !/(#8fb3ff|#7aa2ff|#355d9d|#78a8f7|rgba\([^)]*143\s*,\s*179\s*,\s*255)/i.test(css))
add('REV24 does not restyle dashboard', !/\.dashboard-page|\.dash-|activation-card|quick-actions-wrap/.test(css))
add('REV24 does not restyle sidebar/navigation', !/\.nav-item|\.sidebar|sidebar-hotel/.test(css))
add('REV24 does not restyle login', !/\.login-|login-page|login-card/.test(css))
add('Housekeeping live checkbox source retained', housekeeping.includes('className="day13-check"') && housekeeping.includes('type="checkbox"'))
add('Housekeeping checkbox direct selector present', css.includes('.app-shell .day13-check input[type="checkbox"]'))
add('Housekeeping checked state uses approved gold accent', css.includes('border-color:var(--sq22-accent)!important') && css.includes('var(--sq22-accent-hi)'))
add('Housekeeping checked state does not use green fill', !/input\[type="checkbox"\]:checked\s*\{[^}]*sq22-green/s.test(css))
add('Legacy inline gold form labels neutralised', css.includes('label[style*="color: rgb(212, 175, 55)"]'))
add('Warm fill neutralisation is narrow', css.includes('background: rgb(36, 29, 10)') && css.includes('background:var(--sq22-panel)!important'))
add('Legacy operational heading visibility correction exists', css.includes('h1[style*="font-size: 42px"]'))
add('Mobile Day13 target size exists', css.includes('min-height:44px!important'))
add('Mobile inline legacy page padding correction exists', css.includes('padding:18px!important'))
add('Reduced-motion rule retained', css.includes('@media(prefers-reduced-motion:reduce)'))
add('REV24 is presentation-only', !/fetch\(|createClient\(|supabase\.|\.from\(/i.test(css))
add('Guest guide styling untouched', !/\.ag-(?:page|hero|section|card)\b/.test(css))
add('Food guest styling untouched', !/\.food-(?:page|hero|shell|menu)\b/.test(css))

let passed = 0
for (const check of checks) {
  console.log(`${check.ok ? 'PASS' : 'FAIL'} ${check.name}`)
  if (check.ok) passed += 1
}
console.log(JSON.stringify({ checks: checks.length, passed, failed: checks.length - passed }))
if (passed !== checks.length) process.exit(1)
