import fs from 'node:fs'
import path from 'node:path'
import process from 'node:process'

const root = process.cwd()
const read = (relativePath) =>
  fs.readFileSync(path.join(root, relativePath), 'utf8')

const files = {
  builder: 'src/pages/guestbuilder/GuestGuideBuilder.jsx',
  builderCss: 'src/pages/guestbuilder/GuestGuideBuilder.css',
  guide: 'src/pages/guestguide/GuestGuide.jsx',
  guideCss: 'src/pages/guestguide/GuestGuide.css',
  lib: 'src/lib/guestGuideBuilder.js',
  portal: 'src/lib/guestPortal.js',
  migration: 'docs/database/legacy-migrations/pre-day18-canonical-baseline/202608030048_day14_payment_upi_regex_compatibility_FIX_REV1.sql',
}

const source = Object.fromEntries(
  Object.entries(files).map(([key, relativePath]) => [key, read(relativePath)])
)

const required = [
  ['builder', 'Guest Guide Setup'],
  ['builder', 'Brand & Photos'],
  ['builder', 'Languages'],
  ['builder', 'Contacts & Services'],
  ['builder', 'Rooms & Instructions'],
  ['builder', 'Local & Payment'],
  ['builder', 'Review & Publish'],
  ['builder', 'Prepare essential actions'],
  ['builder', 'Hotel Logo'],
  ['builder', 'Hero / Cover Photo'],
  ['builder', 'Payment QR'],
  ['builder', 'Room-type instructions replace them'],
  ['builder', 'One specific room'],
  ['builder', 'Nearby Restaurants'],
  ['builder', 'Transport Assistance'],
  ['builder', 'Manual UPI payments always require hotel confirmation'],
  ['builder', 'publishGuestGuide'],
  ['builder', 'saveGuestGuideGreeting'],
  ['builder', 'uploadGuestGuideMediaFile'],
  ['builder', 'saveGuestGuidePaymentProfile'],
  ['guide', 'resolvePremiumGuestGuide'],
  ['guide', 'This signed StayQR link is invalid, expired or has been revoked.'],
  ['guide', 'GuideIcon'],
  ['guide', 'sg-sticky-bar'],
  ['guide', 'sg-action-grid'],
  ['guide', 'sg-glance-grid'],
  ['guide', 'sg-gallery'],
  ['guide', 'sg-accordion'],
  ['guide', 'nearby guest-convenience links'],
  ['guide', 'does not automatically mark the invoice as paid'],
  ['guide', 'recordGuestGuideEvent'],
  ['guide', 'createGuestServiceRequest'],
  ['guide', 'submitGuestFeedback'],
  ['guide', 'recordGuestReviewRewardAction'],
  ['guide', 'ACCESS_RECHECK_INTERVAL_MS'],
  ['guideCss', "'Playfair Display'"],
  ['guideCss', "'Inter'"],
  ['guideCss', 'color: var(--sg-text) !important'],
  ['guideCss', 'width: min(560px, 100%)'],
  ['guideCss', 'sg-sticky-bar'],
  ['builderCss', 'simple-steps'],
  ['builderCss', 'simple-language-grid'],
  ['builderCss', 'simple-scope-explainer'],
  ['migration', "{2,200}"],
  ['migration', 'invalid repetition count'],
]

const forbidden = [
  ['all', 'dangerouslySetInnerHTML'],
  ['all', 'service_role'],
  ['guide', '?room='],
  ['guide', 'window.scrollTo({ top: 0'],
  ['guideCss', 'color: #000'],
  ['builder', 'Install recommended starter'],
  ['builder', 'Stable item key'],
  ['builder', 'GUEST_GUIDE_ACTION_TYPES'],
  ['builder', 'GUEST_GUIDE_ITEM_TYPES'],
  ['builder', "code: 'ur'"],
  ['lib', "code: 'ur'"],
]

const failures = []
for (const [fileKey, contract] of required) {
  if (!source[fileKey].includes(contract)) {
    failures.push(`Missing contract in ${files[fileKey]}: ${contract}`)
  }
}

const allSource = Object.values(source).join('\n')
for (const [fileKey, pattern] of forbidden) {
  const haystack = fileKey === 'all' ? allSource : source[fileKey]
  if (haystack.includes(pattern)) {
    failures.push(`Unsafe or obsolete pattern found in ${fileKey === 'all' ? 'frontend patch' : files[fileKey]}: ${pattern}`)
  }
}

const approvedLocaleCodes = [
  "code: 'en'",
  "code: 'hi'",
  "code: 'mr'",
  "code: 'ta'",
  "code: 'te'",
  "code: 'bn'",
  "code: 'gu'",
  "code: 'kn'",
  "code: 'ml'",
  "code: 'pa'",
  "code: 'or'",
  "code: 'as'",
]

for (const localeCode of approvedLocaleCodes) {
  if (!source.lib.includes(localeCode)) {
    failures.push(`Approved locale missing from guest guide library: ${localeCode}`)
  }
}

if (failures.length > 0) {
  console.error('FAIL — Day 14 minimal-luxury recovery source gate.')
  failures.forEach((failure) => console.error(`- ${failure}`))
  process.exit(1)
}

console.log('PASS — Day 14 minimal-luxury recovery source gate.')
console.log(`PASS — ${required.length} required contracts present.`)
console.log(`PASS — ${forbidden.length} unsafe or obsolete patterns blocked.`)
console.log('PASS — 12 approved Indian language presets retained; Urdu excluded.')
console.log('PASS — secure signed-token access and guest action revalidation retained.')
console.log('PASS — simplified six-step hotel setup and Apex-inspired renderer present.')
