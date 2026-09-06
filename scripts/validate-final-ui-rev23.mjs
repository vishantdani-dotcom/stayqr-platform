import fs from 'node:fs'

const read = (file) => fs.readFileSync(file, 'utf8')
const checks = []
const add = (name, ok) => checks.push({ name, ok: Boolean(ok) })

const main = read('src/main.jsx')
const css = read('src/styles/finalRev23.css')
const housekeeping = read('src/pages/housekeeping/Housekeeping.jsx')

add('REV23 imported after REV22', /finalRev22\.css['"]\s*\nimport ['"]\.\/styles\/finalRev23\.css/.test(main))
add('Cool professional accent token present', css.includes('--sq23-accent:#8fb3ff'))
add('REV22 accent is overridden by REV23', css.includes('--sq22-accent:var(--sq23-accent)'))
add('Sidebar active state is cool and professional', css.includes('.nav-item.active') && css.includes('var(--sq23-accent-strong)'))
add('Legacy inline gold buttons are neutralised', css.includes('button[style*="#D4AF37"]') && css.includes('background:var(--sq23-accent)!important'))
add('Form controls share final focus system', css.includes('box-shadow:0 0 0 3px var(--sq23-focus)!important'))
add('Housekeeping uses live operational checkbox source', housekeeping.includes('className="day13-check"') && housekeeping.includes('type="checkbox"'))
add('Housekeeping checkbox selector no longer depends on day13-card', css.includes('.app-shell .day13-check input[type="checkbox"]'))
add('Housekeeping checkbox uses custom appearance', css.includes('-webkit-appearance:none!important'))
add('Housekeeping checkbox uses SVG checkmark', css.includes('data:image/svg+xml'))
add('Housekeeping checked state is not bright green', css.includes('background-color:#355d9d!important') && !/\.day13-check input\[type="checkbox"\]:checked\s*\{[^}]*sq23-success/s.test(css))
add('Day13 tabs remain readable', css.includes('.day13-page [role="tab"]') && css.includes('color:#9aa7b6!important'))
add('Charges/inline heading top-offset correction exists', css.includes('h1,h2)[style*="margin-top: -"]'))
add('Hotel Profile field labels neutralised', css.includes('[class*="hotel-profile"] label'))
add('Media Manager presentation rules preserve media', css.includes('[class*="media"] video') && !/\.app-shell[^\n]*img\s*\{[^}]*filter/i.test(css))
add('Login active authentication tab uses cool accent', css.includes('.login-mode-switch button.active'))
add('Login primary CTA uses cool accent', css.includes('form button[type="submit"]') && css.includes('var(--sq23-login-accent)!important'))
add('Login mobile collapse exists', css.includes('@media(max-width:760px)') && css.includes('[class*="showcase"]'))
add('Admin mobile content padding exists', css.includes('@media(max-width:1024px)') && css.includes('padding:14px 16px 34px!important'))
add('Touch targets improve on small screens', css.includes('min-height:44px'))
add('Tables get horizontal mobile containment', css.includes('overflow-x:auto!important'))
add('Reduced-motion accessibility is retained', css.includes('@media(prefers-reduced-motion:reduce)'))
add('REV23 is presentation-only', !/fetch\(|createClient\(|supabase\.|\.from\(/i.test(css))
add('Guest guide root selectors not restyled', !/\.ag-(?:page|hero|section|card)\b/.test(css))
add('Food guest root selectors not restyled', !/\.food-(?:page|hero|shell|menu)\b/.test(css))

let passed = 0
for (const check of checks) {
  console.log(`${check.ok ? 'PASS' : 'FAIL'} ${check.name}`)
  if (check.ok) passed += 1
}
console.log(JSON.stringify({ checks: checks.length, passed, failed: checks.length - passed }))
if (passed !== checks.length) process.exit(1)
