import fs from 'node:fs'
import path from 'node:path'
const root=process.cwd()
const read=(p)=>fs.readFileSync(path.join(root,p),'utf8')
let passed=0,failed=0
const check=(n,o)=>{console.log(`${o?'PASS':'FAIL'} ${n}`);o?passed++:failed++}
const env=read('.env.example')
const netlify=read('netlify.toml')
const pkg=JSON.parse(read('package.json'))
const html=read('index.html')
const readme=read('README.md')

check('Package is commercial StayQR package', pkg.name==='stayqr-platform' && pkg.version==='1.0.0')
check('Netlify production environment declared', netlify.includes('[context.production.environment]') && netlify.includes('VITE_APP_ENV = "production"'))
check('Production security headers include CSP', netlify.includes('Content-Security-Policy'))
check('Production security headers include HSTS', netlify.includes('Strict-Transport-Security'))
check('Frame embedding blocked', netlify.includes('X-Frame-Options = "DENY"') && netlify.includes("frame-ancestors 'none'"))
check('Sensitive provider defaults remain off', env.includes('CASHFREE_SUBSCRIPTIONS_ENABLED=false') && env.includes('WHATSAPP_AUTOMATION_ENABLED=false') && env.includes('UIDAI_ONLINE_AUTH_ENABLED=false'))
check('No example provider secrets contain live values', !/(ACCESS_TOKEN|APP_SECRET|CLIENT_SECRET)=\S+/.test(env))
check('App routes remain noindex', /noindex/.test(html))
check('README documents manual billing hold', /manual/i.test(readme) && /Cashfree/i.test(readme))
check('README documents Meta hold', /WhatsApp/i.test(readme) || /Meta/i.test(readme))
check('Build script is production Vite build', pkg.scripts?.build==='vite build')
check('Commercial validation script remains available', Boolean(pkg.scripts?.['validate:commercial-ready']))
check('Full check suite remains available', Boolean(pkg.scripts?.check))

console.log(JSON.stringify({checks:passed+failed,passed,failed}))
if(failed) process.exit(1)
