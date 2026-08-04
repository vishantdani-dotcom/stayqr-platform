import fs from 'node:fs'
import path from 'node:path'

const root = process.cwd()
const read = (relative) => fs.readFileSync(path.join(root, relative), 'utf8')

const css = read('src/pages/food/FoodMenu.css')
const food = read('src/pages/food/FoodMenu.jsx')
const menu = read('src/pages/menumanagement/MenuManagement.jsx')
const i18n = read('src/lib/diningI18n.js')
const pkg = JSON.parse(read('package.json'))

const localeCodes = [
  'hi', 'mr', 'ta', 'te', 'bn', 'gu',
  'kn', 'ml', 'pa', 'or', 'as',
]
const hasAllLocales = localeCodes.every(
  (code) => i18n.includes(`"${code}":`)
)

const required = [
  ['contrast marker', css.includes(
    'StayQR Day 15 final premium dining contrast and readability lock'
  )],
  ['hero title contrast', /food-hero-content h1[\s\S]*color:\s*#fffaf0/i.test(css)],
  ['offer title contrast', /food-offer-(?:band|copy) h2[\s\S]*color:/i.test(css)],
  ['menu heading contrast', /food-section-heading\.premium h2[\s\S]*color:/i.test(css)],
  ['cart heading contrast', /food-cart-heading h2[\s\S]*color:/i.test(css)],
  ['language selector', food.includes('food-language-picker')],
  ['localized menu items', food.includes('localizeMenuItem')],
  ['localized order items', food.includes('localizeOrderItem')],
  ['localized status', food.includes('localizeStatus')],
  ['locale persistence', food.includes('persistGuestLocale')],
  ['locale URL persistence', food.includes('replaceGuestLocaleInUrl')],
  ['12 locale catalogue', hasAllLocales],
  ['offer rendering', food.includes('food-offer-band')],
  ['offer action handler', food.includes('handleOfferAction')],
  ['offer editor', menu.includes('Dining Offer & Banner')],
  ['language studio', menu.includes('Menu Language Studio')],
  ['offer media upload', menu.includes('offer_banner')],
  ['access polling', food.includes('ACCESS_RECHECK_INTERVAL_MS')],
  ['order polling', food.includes('ORDER_RECHECK_INTERVAL_MS')],
  ['hidden-tab pause', food.includes('document.visibilityState')],
  ['lazy image loading', food.includes("loading={priority ? 'eager' : 'lazy'}")],
  ['async image decoding', food.includes('decoding="async"')],
  ['official StayQR logo', food.includes('/assets/stayqr-official-logo.png')],
  ['signed guest token retained', food.includes('accessToken')],
  ['final gate registered',
    pkg.scripts?.['security:day15diningfinal']
      === 'node scripts/day15-premium-dining-final-source-check.mjs'
  ],
]

const unsafe = [
  ['service role key', /service[_-]?role/i.test(food)],
  ['public room query credential', /\?room=/i.test(food)],
  ['external QR endpoint', /api\.qrserver|quickchart/i.test(food)],
  ['direct food-order insert', /\.from\(['"]food_orders['"]\)\s*\.insert/i.test(food)],
  ['direct notification insert',
    /\.from\(['"]guest_notifications['"]\)\s*\.insert/i.test(food)
  ],
  ['unsafe HTML injection', /dangerouslySetInnerHTML|\.innerHTML\s*=/i.test(food)],
]

const missing = required.filter(([, ok]) => !ok)
const unsafeHits = unsafe.filter(([, hit]) => hit)

if (missing.length || unsafeHits.length) {
  for (const [name] of missing) console.error(`FAIL required: ${name}`)
  for (const [name] of unsafeHits) console.error(`FAIL unsafe: ${name}`)
  process.exit(1)
}

console.log(
  `PASS — Day 15 premium dining final source gate `
  + `(${required.length} required contracts; `
  + `${unsafe.length} unsafe patterns blocked).`
)
