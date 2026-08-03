import fs from 'node:fs'
import path from 'node:path'
import process from 'node:process'

const root = process.cwd()
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8')
const guide = read('src/pages/guestguide/GuestGuide.jsx')
const guideCss = read('src/pages/guestguide/GuestGuide.css')
const builder = read('src/pages/guestbuilder/GuestGuideBuilder.jsx')
const builderCss = read('src/pages/guestbuilder/GuestGuideBuilder.css')
const catalog = read('src/lib/guestGuideFullCatalog.js')
const packageJson = read('package.json')

const required = [
  ['REV5 renderer marker', guide.includes('apex_signature_full_language_renderer_rev5')],
  ['official StayQR logo in hero', guide.includes('/assets/stayqr-official-logo.png') && guide.includes('ag-hero-brand')],
  ['official StayQR logo in signature', guide.includes('ag-stayqr-signature') && guide.includes('stayqr-official-logo.png')],
  ['official StayQR logo in footer', guide.includes('ag-footer-brand')],
  ['full locale translation reads selected locale directly', guide.includes('getDirectLocaleTranslation')],
  ['localized section catalogue', guide.includes('getFullSectionCopy')],
  ['localized item catalogue', guide.includes('getFullItemCopy')],
  ['localized instruction fallback', guide.includes('defaults.instructions.length > 0')],
  ['Hindi instruction pack', catalog.includes("air_conditioner: ['एयर कंडीशनर'")],
  ['Marathi instruction pack', catalog.includes("air_conditioner: ['एअर कंडिशनर'")],
  ['Tamil instruction pack', catalog.includes("air_conditioner: ['ஏர் கண்டிஷனர்'")],
  ['guest name personalization', guide.includes('ag-personal-greeting') && guide.includes('guestName')],
  ['featured offer band', guide.includes('ag-offer-band') && guide.includes('offerConfig')],
  ['UPI deep link', guide.includes('upi://pay?pa=') && guide.includes('&am=')],
  ['payment QR', guide.includes("category === 'payment_qr'")],
  ['instruction item media match', guide.includes('entry.item_id === item.id')],
  ['device category fallback', guide.includes('ac_remote') && guide.includes('tv_remote')],
  ['Wi-Fi photo', guide.includes('ag-wifi-photo')],
  ['fixed guest toast', guide.includes('ag-toast')],
  ['builder local save state', builder.includes('simple-inline-saved')],
  ['builder sticky save feedback', builderCss.includes('.simple-inline-saved') && builderCss.includes('position: sticky')],
  ['official logo in builder', builder.includes('/assets/stayqr-official-logo.png')],
  ['approved logo asset referenced', guideCss.includes('.ag-footer-brand > img')],
  ['final visual polish tokens', guideCss.includes('Day 14 REV5') && guideCss.includes('--ag-gold-light: #f0ce77')],
  ['signed access interval', guide.includes('ACCESS_RECHECK_INTERVAL_MS')],
  ['focus revalidation', guide.includes("window.addEventListener('focus'")],
  ['service action revalidation', guide.includes('const accessStillValid = await fetchActivePortal()')],
  ['food signed route', guide.includes('/food/${encodeURIComponent(hotelSlug)}')],
  ['12 approved locale foundation retained', packageJson.includes('security:day14builder')],
  ['Urdu not in final catalogue', !/['"]ur['"]/.test(catalog)],
]

const unsafe = [
  ['room query-string access', /\?room=/.test(guide)],
  ['direct signed-token table read', /\.from\(['"]guest_access_tokens['"]\)/.test(guide)],
  ['service role key in browser', /service[_-]?role/i.test(guide + builder)],
  ['arbitrary HTML injection', /dangerouslySetInnerHTML/.test(guide + builder)],
  ['custom JavaScript editor', /custom_javascript|javascript editor/i.test(builder)],
  ['raw icon text output', /<span[^>]*>\s*\{(?:amenity|item)\.icon\}/.test(guide)],
  ['old REV3 marker', /minimal_luxury_renderer/.test(guide)],
  ['old REV4 marker', /apex_signature_renderer_rev4/.test(guide)],
  ['technical stable-key wording', /Stable item key/.test(builder)],
  ['save scrolls document to top', /window\.scrollTo\(\{\s*top:\s*0/.test(builder)],
  ['payment auto marks invoice paid', /mark.*invoice.*paid/i.test(guide)],
]

let failed = false
for (const [name, pass] of required) {
  console.log(`${pass ? 'PASS' : 'FAIL'} REQUIRED — ${name}`)
  if (!pass) failed = true
}
for (const [name, found] of unsafe) {
  console.log(`${!found ? 'PASS' : 'FAIL'} BLOCKED — ${name}`)
  if (found) failed = true
}
if (failed) process.exit(1)
console.log(`\nPASS — Day 14 Final REV5 source gate (${required.length} required contracts; ${unsafe.length} unsafe patterns blocked).`)
