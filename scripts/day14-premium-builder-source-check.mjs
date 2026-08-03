import fs from 'node:fs'
import path from 'node:path'

const root = process.cwd()
const failures = []

const requiredFiles = [
  'src/lib/guestGuideBuilder.js',
  'src/lib/guestPortal.js',
  'src/pages/guestbuilder/GuestGuideBuilder.jsx',
  'src/pages/guestbuilder/GuestGuideBuilder.css',
  'src/pages/guestguide/GuestGuide.jsx',
  'src/pages/guestguide/GuestGuide.css',
  'src/App.jsx',
  'src/components/sidebar/Sidebar.jsx',
  'src/lib/currentStaff.js',
  'supabase/migrations/202608020047_day14_premium_guest_guide_builder_foundation_REV1.sql',
]

const requiredContracts = [
  ['src/lib/guestGuideBuilder.js', "'get_guest_guide_builder'"],
  ['src/lib/guestGuideBuilder.js', "'upsert_guest_guide_settings'"],
  ['src/lib/guestGuideBuilder.js', "'upsert_guest_guide_section'"],
  ['src/lib/guestGuideBuilder.js', "'upsert_guest_guide_item'"],
  ['src/lib/guestGuideBuilder.js', "'upsert_guest_guide_media'"],
  ['src/lib/guestGuideBuilder.js', "'upsert_guest_guide_greeting'"],
  ['src/lib/guestGuideBuilder.js', "'upsert_guest_guide_payment_profile'"],
  ['src/lib/guestGuideBuilder.js', "'publish_guest_guide'"],
  ['src/lib/guestGuideBuilder.js', "GUEST_GUIDE_BUCKET = 'guest-guide-media'"],
  ['src/lib/guestGuideBuilder.js', "{ code: 'mr'"],
  ['src/lib/guestGuideBuilder.js', "{ code: 'ta'"],
  ['src/lib/guestGuideBuilder.js', "{ code: 'as'"],
  ['src/lib/guestPortal.js', "'resolve_premium_guest_guide'"],
  ['src/lib/guestPortal.js', "'record_guest_guide_event'"],
  ['src/pages/guestbuilder/GuestGuideBuilder.jsx', 'Guest Guide Builder'],
  ['src/pages/guestbuilder/GuestGuideBuilder.jsx', 'Install recommended starter'],
  ['src/pages/guestbuilder/GuestGuideBuilder.jsx', 'Local Convenience'],
  ['src/pages/guestbuilder/GuestGuideBuilder.jsx', 'Payment QR image'],
  ['src/pages/guestbuilder/GuestGuideBuilder.jsx', 'Editable guest greetings'],
  ['src/pages/guestbuilder/GuestGuideBuilder.jsx', 'Room type'],
  ['src/pages/guestbuilder/GuestGuideBuilder.jsx', 'Individual room'],
  ['src/pages/guestbuilder/GuestGuideBuilder.jsx', 'Publish guest guide'],
  ['src/pages/guestbuilder/GuestGuideBuilder.jsx', 'missingStarterTemplates'],
  ['src/pages/guestbuilder/GuestGuideBuilder.jsx', 'scrollToItemEditor'],
  ['src/pages/guestbuilder/GuestGuideBuilder.jsx', 'Create room-type instruction'],
  ['src/pages/guestbuilder/GuestGuideBuilder.jsx', 'Create room override'],
  ['src/pages/guestbuilder/GuestGuideBuilder.jsx', 'Configure contacts & social'],
  ['src/pages/guestbuilder/GuestGuideBuilder.jsx', 'Existing edits were preserved'],
  ['src/pages/guestguide/GuestGuide.jsx', 'resolvePremiumGuestGuide'],
  ['src/pages/guestguide/GuestGuide.jsx', 'greetingPeriod'],
  ['src/pages/guestguide/GuestGuide.jsx', 'premium-local-disclaimer'],
  ['src/pages/guestguide/GuestGuide.jsx', 'payment_qr'],
  ['src/pages/guestguide/GuestGuide.jsx', 'does not automatically mark the hotel invoice as paid'],
  ['src/pages/guestguide/GuestGuide.jsx', 'sticky_quick_actions'],
  ['src/App.jsx', "case 'guidebuilder'"],
  ['src/components/sidebar/Sidebar.jsx', 'Guest Guide Builder'],
  ['src/lib/currentStaff.js', "guidebuilder: 'hotel.manage'"],
  ['supabase/migrations/202608020047_day14_premium_guest_guide_builder_foundation_REV1.sql', 'create table if not exists public.guest_guide_settings'],
  ['supabase/migrations/202608020047_day14_premium_guest_guide_builder_foundation_REV1.sql', 'create table if not exists public.guest_guide_media'],
  ['supabase/migrations/202608020047_day14_premium_guest_guide_builder_foundation_REV1.sql', 'create table if not exists public.guest_guide_greetings'],
  ['supabase/migrations/202608020047_day14_premium_guest_guide_builder_foundation_REV1.sql', 'create or replace function public.resolve_premium_guest_guide'],
  ['supabase/migrations/202608020047_day14_premium_guest_guide_builder_foundation_REV1.sql', 'create or replace function public.publish_guest_guide'],
  ['supabase/migrations/202608020047_day14_premium_guest_guide_builder_foundation_REV1.sql', "'en','hi','mr','ta','te','bn'"],
]

for (const file of requiredFiles) {
  if (!fs.existsSync(path.join(root, file))) failures.push(`Missing file: ${file}`)
}

for (const [file, contract] of requiredContracts) {
  const absolute = path.join(root, file)
  if (!fs.existsSync(absolute)) continue
  const content = fs.readFileSync(absolute, 'utf8')
  if (!content.includes(contract)) {
    failures.push(`Missing contract in ${file}: ${contract}`)
  }
}

const protectedFiles = [
  'src/lib/guestGuideBuilder.js',
  'src/lib/guestPortal.js',
  'src/pages/guestbuilder/GuestGuideBuilder.jsx',
  'src/pages/guestguide/GuestGuide.jsx',
  'src/App.jsx',
]

const source = protectedFiles
  .map((file) => fs.readFileSync(path.join(root, file), 'utf8'))
  .join('\n')

const unsafePatterns = [
  /[?&]room=/i,
  /\/guest\/\$\{[^}]*room/i,
  /service[_-]?role/i,
  /\.from\(['"]guest_guide_(?:settings|sections|items|media|greetings|payment_profiles)['"]\)\s*\.\s*(insert|update|delete)/s,
  /custom_html/i,
  /custom_javascript/i,
  /dangerouslySetInnerHTML/,
  /<script/i,
  /(?:api\.qrserver|quickchart\.io|chart\.googleapis)/i,
  /{\s*code:\s*['"]ur['"]/,
  /Urdu.*enabled/i,
]

for (const pattern of unsafePatterns) {
  if (pattern.test(source)) failures.push(`Unsafe premium builder pattern: ${pattern}`)
}

const localeSource = fs.readFileSync(
  path.join(root, 'src/lib/guestGuideBuilder.js'),
  'utf8'
)
const localeCodes = [...localeSource.matchAll(/\{ code: '([a-z]{2})'/g)].map(
  (match) => match[1]
)

if (localeCodes.length !== 12) {
  failures.push(`Expected 12 launch locales, found ${localeCodes.length}.`)
}

if (new Set(localeCodes).size !== localeCodes.length) {
  failures.push('Duplicate guest-guide locale codes found.')
}

if (localeCodes.includes('ur')) {
  failures.push('Urdu must remain excluded from the approved Day 14 scope.')
}

if (failures.length > 0) {
  console.error('FAIL — Day 14 premium builder frontend source gate.')
  failures.forEach((failure) => console.error(`- ${failure}`))
  process.exit(1)
}

console.log(
  `PASS — Day 14 premium builder source gate (${requiredContracts.length} required contracts; ${unsafePatterns.length} unsafe patterns blocked; ${localeCodes.length} approved locales).`
)
