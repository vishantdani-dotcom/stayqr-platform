import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const read = (relative) => fs.readFileSync(path.join(root, relative), 'utf8')

const food = read('src/pages/food/FoodMenu.jsx')
const foodCss = read('src/pages/food/FoodMenu.css')
const manager = read('src/pages/menumanagement/MenuManagement.jsx')
const guestGuide = read('src/pages/guestguide/GuestGuide.jsx')
const locale = read('src/lib/guestLocale.js')
const i18n = read('src/lib/diningI18n.js')
const migration = read('docs/database/legacy-migrations/pre-day18-canonical-baseline/202608040054_day15_premium_dining_i18n_offer_performance_REV1.sql')
const packageJson = read('package.json')
const combined = [food, foodCss, manager, guestGuide, locale, i18n, migration, packageJson].join('\n')

const required = [
  ['twelve launch locales', /'en','hi','mr','ta','te','bn','gu','kn','ml','pa','or','as'/],
  ['language selector in dining page', /food-language-picker/],
  ['guest locale query persistence', /replaceGuestLocaleInUrl/],
  ['guest locale local storage', /persistGuestLocale/],
  ['guest guide passes locale to dining', /withGuestLocale\(foodPath, locale\)/],
  ['complete localized UI copy', /getDiningCopy\(locale\)/],
  ['item localization', /localizeMenuItem\(item, locale, defaultLocale\)/],
  ['tracked order localization', /localizeOrderItem\(item, locale, defaultLocale\)/],
  ['modifier localization', /localizeModifierGroup/],
  ['category translations exposed', /category_translations/],
  ['menu item translation columns', /alter table public\.menu_items[\s\S]*add column if not exists translations/],
  ['category translation columns', /alter table public\.menu_categories[\s\S]*add column if not exists translations/],
  ['modifier translation columns', /menu_item_modifier_groups[\s\S]*translations[\s\S]*menu_item_modifiers/],
  ['trusted locale save RPC', /save_menu_locale_translations/],
  ['hotel manage authorization', /user_has_permission\(p_hotel_id, 'hotel\.manage'\)/],
  ['menu language studio', /Menu Language Studio/],
  ['translation seed catalog', /getTranslationSeed/],
  ['offer editor', /Dining Offer & Banner/],
  ['offer per-locale translations', /currentOffer\.translations/],
  ['offer banner upload', /dining_offer_banner/],
  ['offer settings save', /saveGuestGuideSettings/],
  ['offer publish action', /publishGuestGuide/],
  ['offer image resolver', /offerImageUrl/],
  ['offer action URL support', /actionType === 'url'/],
  ['offer action WhatsApp support', /actionType === 'whatsapp'/],
  ['menu fetched once on initialize', /Promise\.all\(\[loadMenuData\(\), loadOrderData\(\), loadBranding\(\)\]\)/],
  ['orders poll separately', /ORDER_RECHECK_INTERVAL_MS = 12000/],
  ['access poll separately', /ACCESS_RECHECK_INTERVAL_MS = 30000/],
  ['low-frequency clock', /CLOCK_RECHECK_INTERVAL_MS = 30000/],
  ['hidden-tab polling pause', /document\.visibilityState !== 'visible'/],
  ['memoized menu cards', /const MenuItemCard = memo/],
  ['lazy async images', /loading=\{priority \? 'eager' : 'lazy'\}[\s\S]*decoding="async"/],
  ['render containment', /contain: layout paint style/],
  ['offscreen content visibility', /content-visibility: auto/],
  ['reduced motion compatibility', /prefers-reduced-motion/],
  ['notification non-null title fallback', /v_title text := coalesce\(nullif\(trim\(p_title\), ''\), 'Order update'\)/],
  ['notification non-null message fallback', /v_message text := coalesce\(nullif\(trim\(p_message\), ''\), 'Your order has been updated\.'\)/],
  ['migration acceptance target', /exactly 30 rows/i],
]

const missing = required.filter(([, pattern]) => !pattern.test(combined))
if (missing.length) {
  console.error('FAIL — missing Premium Dining REV2 contracts:')
  for (const [label] of missing) console.error(`- ${label}`)
  process.exit(1)
}

const unsafe = [
  ['Urdu locale code included', /['"]ur['"]/i],
  ['one-second full-page clock', /setInterval\([^,]+,\s*1000\)/],
  ['menu refetched in order poll', /setInterval\([\s\S]{0,180}?loadMenuData/],
  ['guest direct menu writes', /src\/pages\/food[\s\S]*\.from\(['"]menu_(items|categories)['"]\)[\s\S]{0,180}?\.(insert|update|delete)\(/],
  ['guest direct food order writes', /src\/pages\/food[\s\S]*\.from\(['"]food_orders['"]\)[\s\S]{0,180}?\.(insert|update|delete)\(/],
  ['service role browser key', /service_role|SUPABASE_SERVICE_ROLE/i, [food, manager, guestGuide, locale, i18n].join('\n')],
  ['arbitrary hotel HTML', /dangerouslySetInnerHTML|innerHTML\s*=/],
  ['third-party translation API', /translate\.google|googletrans|deepl|azure.*translator/i],
  ['third-party QR API', /api\.qrserver|quickchart|googleapis.*chart/i],
  ['fake restaurant rating', /4\.7\s*\(/],
  ['fake platform fee', /Platform Fee/i],
  ['hard-coded StayQR test hotel in guest dining', /Hotel Apex Stay Inn|VD Stay Inn/],
]

const triggered = unsafe.filter(([, pattern, source]) => pattern.test(source || combined))
if (triggered.length) {
  console.error('FAIL — unsafe Premium Dining REV2 patterns detected:')
  for (const [label] of triggered) console.error(`- ${label}`)
  process.exit(1)
}

console.log(`PASS — Premium Dining REV2 source gate (${required.length} required contracts; ${unsafe.length} unsafe patterns blocked; 12 approved locales).`)
