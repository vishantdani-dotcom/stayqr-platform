import fs from 'node:fs'
import path from 'node:path'
import process from 'node:process'

const root = process.cwd()
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8')
const guide = read('src/pages/guestguide/GuestGuide.jsx')
const guideCss = read('src/pages/guestguide/GuestGuide.css')
const builder = read('src/pages/guestbuilder/GuestGuideBuilder.jsx')
const builderCss = read('src/pages/guestbuilder/GuestGuideBuilder.css')
const i18n = read('src/lib/guestGuideI18n.js')
const helper = read('src/lib/guestGuideBuilder.js')

const required = [
  ['apex signature renderer marker', guide.includes('apex_signature_renderer_rev4')],
  ['full language UI copy', guide.includes('getGuideCopy(locale')],
  ['section language fallback', guide.includes('getDefaultSectionCopy')],
  ['item language fallback', guide.includes('getDefaultItemCopy')],
  ['personal guest name greeting', guide.includes('guestName') && guide.includes('ag-personal-greeting')],
  ['featured offer band', guide.includes('ag-offer-band') && guide.includes('offerConfig')],
  ['offer action handler', guide.includes('runOfferAction')],
  ['working UPI deep link', guide.includes('upi://pay?pa=') && guide.includes('ag-pay-button')],
  ['payment amount included', guide.includes('&am=')],
  ['payment QR shown', guide.includes("category === 'payment_qr'")],
  ['instruction item media direct match', guide.includes('entry.item_id === item.id')],
  ['instruction category fallback', guide.includes('categoryMap') && guide.includes('ac_remote') && guide.includes('tv_remote')],
  ['wifi media rendered', guide.includes('ag-wifi-photo')],
  ['StayQR hero branding', guide.includes('ag-hero-brand')],
  ['StayQR footer signature', guide.includes('ag-stayqr-signature')],
  ['mobile sticky actions', guide.includes('ag-sticky')],
  ['signed access revalidation interval', guide.includes('ACCESS_RECHECK_INTERVAL_MS')],
  ['signed access focus revalidation', guide.includes("window.addEventListener('focus'")],
  ['service request access revalidation', guide.includes('const accessStillValid = await fetchActivePortal()')],
  ['food signed route retained', guide.includes('/food/${encodeURIComponent(hotelSlug)}')],
  ['fixed visible guest toast', guide.includes('ag-toast')],
  ['builder fixed save toast', builderCss.includes('position: fixed !important')],
  ['builder inline save confirmation', builder.includes('simple-inline-saved')],
  ['builder full guide language editor', builder.includes('Translate the complete guest guide')],
  ['builder saves hotel language content', builder.includes('saveHotelGuestContent')],
  ['builder saves all section translations', builder.includes('saveLanguageContent')],
  ['builder offer editor', builder.includes('Featured offer below the hero')],
  ['builder offer localized fields', builder.includes('offer.translations')],
  ['builder preserves navigation UI copy', builder.includes('ui_copy')],
  ['builder device media association', builder.includes('categoryToKey') && builder.includes('item_id: (() =>')],
  ['12 approved locales', (i18n.match(/'en', 'hi', 'mr', 'ta', 'te', 'bn', 'gu', 'kn', 'ml', 'pa', 'or', 'as'/g) || []).length >= 1],
  ['Urdu absent from locale list', !/code:\s*['"]ur['"]/.test(helper) && !/['"]ur['"]\s*,/.test(i18n)],
  ['Apex-width compact content', guideCss.includes('width: min(100%, 760px)')],
  ['Playfair heading font', guideCss.includes("'Playfair Display'")],
  ['Inter body font', guideCss.includes("'Inter'")],
  ['high contrast white token', guideCss.includes('--ag-white: #f7f5f2')],
  ['offer visual overlap', guideCss.includes('margin: -34px auto 0')],
  ['responsive mobile rules', guideCss.includes('@media (max-width: 760px)')],
  ['hotel content RPC helper', helper.includes("'upsert_hotel_guest_content'")],
]

const unsafe = [
  ['room query-string access', /\?room=/.test(guide)],
  ['direct guest table read', /\.from\(['"]guest_(sessions|access_tokens)['"]\)/.test(guide)],
  ['service role in frontend', /service[_-]?role/i.test(guide + builder + helper)],
  ['arbitrary html injection', /dangerouslySetInnerHTML/.test(guide + builder)],
  ['arbitrary custom JavaScript editor', /custom_javascript|javascript editor/i.test(builder)],
  ['Urdu locale option', /nativeName:\s*['"].*اردو/.test(helper + i18n)],
  ['raw icon text renderer', /<span[^>]*>\s*\{(?:amenity|item)\.icon\}/.test(guide)],
  ['old minimal renderer source marker', /minimal_luxury_renderer/.test(guide)],
  ['old technical item-key UI', /Stable item key/.test(builder)],
  ['save message only at document top', /window\.scrollTo\(\{\s*top:\s*0/.test(builder)],
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
console.log(`\nPASS — Day 14 Apex Signature REV4 source gate (${required.length} required contracts; ${unsafe.length} unsafe patterns blocked).`)
