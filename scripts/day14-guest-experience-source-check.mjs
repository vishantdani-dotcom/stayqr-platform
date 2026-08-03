import fs from 'node:fs'
import path from 'node:path'

const root = process.cwd()

const requiredFiles = [
  'src/lib/guestPortal.js',
  'src/pages/guestguide/GuestGuide.jsx',
  'src/pages/guestguide/GuestGuide.css',
  'src/pages/hotel/HotelProfile.jsx',
  'supabase/migrations/202608010045_day14_guest_experience_content_foundation_REV1.sql',
]

const requiredContracts = [
  ['src/lib/guestPortal.js', "'submit_guest_feedback'"],
  ['src/lib/guestPortal.js', "'record_guest_review_reward_action'"],
  ['src/pages/guestguide/GuestGuide.jsx', 'guest_content'],
  ['src/pages/guestguide/GuestGuide.jsx', 'Guest guide language'],
  ['src/pages/guestguide/GuestGuide.jsx', 'PRIVATE FEEDBACK'],
  ['src/pages/guestguide/GuestGuide.jsx', 'submitGuestFeedback'],
  ['src/pages/guestguide/GuestGuide.jsx', 'recordGuestReviewRewardAction'],
  ['src/pages/guestguide/GuestGuide.jsx', 'guestContent.amenities'],
  ['src/pages/hotel/HotelProfile.jsx', '"get_hotel_guest_content"'],
  ['src/pages/hotel/HotelProfile.jsx', '"upsert_hotel_guest_content"'],
  ['src/pages/hotel/HotelProfile.jsx', 'MULTILINGUAL GUEST GUIDE'],
  ['src/pages/hotel/HotelProfile.jsx', 'हिन्दी'],
  ['supabase/migrations/202608010045_day14_guest_experience_content_foundation_REV1.sql', 'create table if not exists public.hotel_guest_content'],
  ['supabase/migrations/202608010045_day14_guest_experience_content_foundation_REV1.sql', 'create table if not exists public.guest_feedback'],
  ['supabase/migrations/202608010045_day14_guest_experience_content_foundation_REV1.sql', 'create table if not exists public.guest_review_rewards'],
  ['supabase/migrations/202608010045_day14_guest_experience_content_foundation_REV1.sql', 'resolve_guest_access_token'],
]

const unsafePatterns = [
  /\.from\(['"]hotel_guest_content['"]\)\s*\.\s*(insert|update|delete)/s,
  /\.from\(['"]guest_feedback['"]\)\s*\.\s*(insert|update|delete)/s,
  /\.from\(['"]guest_review_rewards['"]\)\s*\.\s*(insert|update|delete)/s,
  /Multi-cuisine dining available/,
  /Secure guest parking/,
  /Available throughout hotel/,
  /Same day laundry service/,
]

const failures = []

for (const file of requiredFiles) {
  if (!fs.existsSync(path.join(root, file))) {
    failures.push(`Missing required file: ${file}`)
  }
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
  'src/lib/guestPortal.js',
  'src/pages/guestguide/GuestGuide.jsx',
  'src/pages/hotel/HotelProfile.jsx',
]

const combined = protectedFiles
  .map((file) => fs.readFileSync(path.join(root, file), 'utf8'))
  .join('\n')

for (const pattern of unsafePatterns) {
  if (pattern.test(combined)) {
    failures.push(`Unsafe Day 14 pattern found: ${pattern}`)
  }
}

if (failures.length) {
  console.error('FAIL — Day 14 guest experience and content source gate.')
  for (const failure of failures) console.error(`- ${failure}`)
  process.exit(1)
}

console.log(
  `PASS — Day 14 guest experience and content frontend source gate (${requiredContracts.length} required contracts; ${unsafePatterns.length} unsafe patterns blocked).`
)
