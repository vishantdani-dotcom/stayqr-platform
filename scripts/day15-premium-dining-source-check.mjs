import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const read = (relative) => fs.readFileSync(path.join(root, relative), 'utf8')

const menu = read('src/pages/food/FoodMenu.jsx')
const menuCss = read('src/pages/food/FoodMenu.css')
const manager = read('src/pages/menumanagement/MenuManagement.jsx')
const i18n = read('src/lib/diningI18n.js')
const combined = [menu, menuCss, manager, i18n].join('\n')

const required = [
  ['premium guide branding resolver', /resolvePremiumGuestGuide\('food'\)/],
  ['hotel logo inheritance', /hotelLogoUrl/],
  ['hero media inheritance', /heroImageUrl/],
  ['official StayQR branding', /stayqr-official-logo\.png/],
  ['premium dining sidebar', /food-side-nav/],
  ['active room and stay status', /food-stay-pills/],
  ['premium hotel hero', /food-hero-card/],
  ['editable hotel offer banner', /food-offer-band/],
  ['category chip navigation', /food-category-strip/],
  ['featured menu filter', /activeCategory === 'featured'/],
  ['photo-led menu cards', /food-item-image/],
  ['localized customisable badge', /copy\.customisable/],
  ['sticky premium cart', /food-cart-panel/],
  ['cart image thumbnails', /food-cart-thumb/],
  ['localized bill summary', /copy\.itemSubtotal[\s\S]{0,500}?copy\.total/],
  ['active-stay security note', /secureOrderFromRoom/],
  ['kitchen story tile', /food-kitchen-story/],
  ['optional hotel video support', /video_url/],
  ['live order tracking retained', /ORDER_RECHECK_INTERVAL_MS/],
  ['guest cancellation retained', /cancelGuestFoodOrder/],
  ['secure placement retained', /placeGuestFoodOrder/],
  ['modifier selection retained', /selectedModifiers/],
  ['mobile cart CTA', /food-mobile-cart/],
  ['menu item photo upload', /uploadGuestGuideMediaFile/],
  ['photo upload accepts safe image types', /image\/jpeg,image\/png,image\/webp/],
  ['menu photo preview', /menu15-photo-preview/],
]

const missing = required.filter(([, pattern]) => !pattern.test(combined))
if (missing.length) {
  console.error('FAIL — missing premium dining contracts:')
  for (const [label] of missing) console.error(`- ${label}`)
  process.exit(1)
}

const unsafe = [
  ['fake restaurant rating', /4\.7\s*\(/, menu],
  ['fake platform fee', /Platform Fee/i, menu],
  ['fake applied discount', /Offer Discount|You.re saving/i, menu],
  ['guest direct order insert', /\.from\(['"]food_orders['"]\)[\s\S]{0,220}?\.insert\(/, menu],
  ['guest direct order update', /\.from\(['"]food_orders['"]\)[\s\S]{0,220}?\.update\(/, menu],
  ['third-party QR generator', /api\.qrserver|quickchart|googleapis.*chart/i, combined],
  ['unsafe video scheme', /window\.open\([^)]*(javascript:|data:)/i, menu],
  ['hard-coded hotel name', /Hotel Apex Stay Inn|VD Stay Inn/, menu],
]

const triggered = unsafe.filter(([, pattern, source]) => pattern.test(source))
if (triggered.length) {
  console.error('FAIL — unsafe premium dining patterns detected:')
  for (const [label] of triggered) console.error(`- ${label}`)
  process.exit(1)
}

console.log(`PASS — StayQR premium dining source gate (${required.length} required contracts; ${unsafe.length} unsafe patterns blocked).`)
