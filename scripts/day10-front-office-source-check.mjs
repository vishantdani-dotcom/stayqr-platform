import fs from 'node:fs'
import path from 'node:path'
import process from 'node:process'

const root = process.cwd()
const read = (relativePath) =>
  fs.readFileSync(path.join(root, relativePath), 'utf8')

const checkInSource = read('src/pages/checkin/CheckIn.jsx')
const guestsSource = read('src/pages/guests/Guests.jsx')
const directorySource = read('src/pages/guests/GuestDirectory.jsx')
const operationsSource = read('src/pages/operations/ReservationOperations.jsx')
const source = `${checkInSource}\n${guestsSource}\n${directorySource}\n${operationsSource}`

const required = [
  ['Atomic walk-in RPC', /\.rpc\(\s*["']check_in_walk_in_guest["']/],
  ['Canonical hotel argument', /target_hotel_id\s*:\s*currentHotel\.id/],
  ['Stable idempotency request', /request_id\s*:\s*requestId/],
  ['Room UUID payload', /room_id\s*:\s*roomId/],
  ['Atomic room charge', /room_charge\s*:\s*Number\(roomCharge\)/],
  ['Guest identity payload', /guest\s*:\s*guestPayload/],
  ['Companion payload', /companions\s*:\s*companionPayload/],
  ['Stay details payload', /stay_details\s*:\s*compactObject/],
  ['Existing guest explicit selection', /id\s*:\s*selectedGuest\?\.id/],
  ['Normalized guest lookup', /normalized_(?:id_type|email|phone)/],
  ['Guest directory view', /Guest directory & history/],
  ['Complete guest-session history', /\.from\(\s*["']guest_sessions["']\s*\)/],
  ['Stay room history', /\.from\(\s*["']stay_room_history["']\s*\)/],
  ['Companion history', /\.from\(\s*["']guest_companions["']\s*\)/],
  ['Private guest notes', /\.from\(\s*["']guest_notes["']\s*\)/],
  ['Guest preferences', /\.from\(\s*["']guest_preferences["']\s*\)/],
  ['Private KYC metadata', /\.from\(\s*["']guest_documents["']\s*\)/],
  ['Private KYC bucket', /\.from\(\s*KYC_BUCKET\s*\)/],
  ['Private KYC object upload', /\.upload\(\s*storagePath\s*,\s*file/],
  ['Authoritative KYC registration RPC', /\.rpc\(\s*["']register_guest_document["']/],
  ['Authoritative KYC review RPC', /\.rpc\(\s*["']review_guest_document["']/],
  ['Short-lived signed KYC access', /\.createSignedUrl\(\s*documentRecord\.storage_path\s*,\s*60\s*\)/],
  ['Strict tenant guest document path', /`\$\{currentHotel\.id\}\/\$\{selectedGuest\.id\}\/\$\{kycDocumentId\}\//],
  ['KYC request idempotency', /request_id\s*:\s*kycRequestId/],
  ['KYC file size guard', /MAX_KYC_FILE_SIZE/],
  ['KYC MIME allowlist', /KYC_MIME_TYPES/],
  ['KYC role permissions', /guests\.manage["'][\s\S]{0,120}?checkin\.manage|checkin\.manage["'][\s\S]{0,120}?guests\.manage/],
  ['Repeat guest signal', /Repeat guest/],
  ['Tenant-scoped directory', /\.eq\(\s*["']hotel_id["']\s*,\s*currentHotel\.id\s*\)/],
  ['Atomic active-stay room move RPC', /\.rpc\(\s*["']move_active_walkin_guest_room["']/],
  ['Room-move hotel scope', /target_hotel_id\s*:\s*moveSession\.hotel_id/],
  ['Room-move guest-session scope', /target_guest_session_id\s*:\s*moveSession\.id/],
  ['Room-move target room UUID', /target_room_id\s*:\s*moveTargetRoomId/],
  ['Room-move request idempotency', /request_id\s*:\s*moveRequestId/],
  ['Room-move stale-screen guard', /expected_from_room_id\s*:\s*moveSession\.room_id/],
  ['Room-move reason evidence', /move_reason\s*:\s*moveReason\.trim\(\)/],
  ['Room-move effective timestamp', /effective_at\s*:\s*new Date\(\)\.toISOString\(\)/],
  ['Room-type rate confirmation', /confirm_rate_change\s*:/],
  ['Room-move calendar invalidation', /reason\s*:\s*["']active_stay_room_moved["']/],
  ['Direct walk-in frontend guard', /session\.reservation_id\s*\|\|\s*session\.reservation_room_id/],
  ['Atomic active-stay extension RPC', /\.rpc\(\s*["']extend_active_walkin_guest_stay["']/],
  ['Stay-extension hotel scope', /target_hotel_id\s*:\s*selectedSession\.hotel_id/],
  ['Stay-extension guest-session scope', /target_guest_session_id\s*:\s*selectedSession\.id/],
  ['Stay-extension request idempotency', /request_id\s*:\s*extendRequestId/],
  ['Stay-extension stale checkout guard', /expected_checkout_at\s*:\s*extendCurrentCheckoutAt/],
  ['Stay-extension new checkout timestamp', /new_checkout_at\s*:\s*newCheckoutAt/],
  ['Stay-extension additional charge', /additional_room_charge\s*:\s*parsedAdditionalCharge/],
  ['Stay-extension charge confirmation', /confirm_room_charge\s*:\s*extendConfirmCharge/],
  ['Stay-extension reason evidence', /extension_reason\s*:\s*extendReason\.trim\(\)/],
  ['Hotel-timezone datetime renderer', /formatDateTimeLocalInTimeZone/],
  ['Hotel-timezone datetime parser', /zonedDateTimeLocalToISOString/],
  ['Stay-extension calendar invalidation', /reason\s*:\s*["']active_stay_extended["']/],
  ['Canonical overdue queue preferred', /result\?\.overdue_exceptions\s*\|\|\s*result\?\.overdue_arrivals/],
  ['Stable operations row identity', /item\.reservation_room_id\s*\|\|[\s\S]{0,120}?item\.guest_session_id/],
  ['Direct walk-in operation detection', /item\.operation_source\s*===\s*["']walk_in["']/],
  ['Direct walk-in routes to guest stay', /isDirectStay\s*&&\s*item\.guest_session_id[\s\S]{0,180}?navigateToSection\(\s*["']guests["']/],
  ['Reservation open route preserved', /navigateToSection\(\s*["']reservations["'][\s\S]{0,100}?reservationId\s*:\s*item\.reservation_id/],
  ['Contextual open action label', /isDirectStay\s*\?\s*["']Open stay["']\s*:\s*["']Open booking["']/],
  ['Overdue exception type rendered', /item\.exception_type[\s\S]{0,180}?operations-exception/],
  ['Overdue duration rendered', /formatOverdueDuration\(item\.minutes_overdue\)/],
  ['Arrival exception check-in guard', /\[["']missed_arrival["']\s*,\s*["']late_arrival["']\]/],
  ['No duplicate direct in-house action', /activeTab\s*===\s*["']in_house["'][\s\S]{0,80}?!isDirectStay/],
  ['Form C readiness builder', /buildFormCChecklist/],
  ['Form C checklist export', /Export Form C checklist/],
  ['Client-side Form C CSV', /text\/csv;charset=utf-8/],
  ['Form C required readiness count', /pendingRequired/],
  ['Foreign-stay Form C panel', /selectedGuest\.is_foreign_guest/],
  ['Positive early check-in payload', /early_checkin/],
  ['Cross-type upgrade rate confirmation', /Changing room type[\s\S]{0,260}?confirm_rate_change|confirm_rate_change[\s\S]{0,260}?new_room_charge/],
]

const forbidden = [
  ['direct guest insert', /\.from\(\s*["']guests["']\s*\)[\s\S]{0,220}?\.insert\s*\(/],
  ['direct guest-session insert', /\.from\(\s*["']guest_sessions["']\s*\)[\s\S]{0,220}?\.insert\s*\(/],
  ['direct payment insert', /\.from\(\s*["']payments["']\s*\)[\s\S]{0,220}?\.insert\s*\(/],
  ['direct room occupancy update', /\.from\(\s*["']rooms["']\s*\)[\s\S]{0,220}?\.update\s*\(/],
  ['direct KYC metadata insert', /\.from\(\s*["']guest_documents["']\s*\)[\s\S]{0,220}?\.insert\s*\(/],
  ['direct KYC metadata update', /\.from\(\s*["']guest_documents["']\s*\)[\s\S]{0,220}?\.update\s*\(/],
  ['direct KYC metadata delete', /\.from\(\s*["']guest_documents["']\s*\)[\s\S]{0,220}?\.delete\s*\(/],
  ['public KYC URL generation', /getPublicUrl\s*\(/],
  ['fixed production hotel UUID', /[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/i],
  ['service role in browser', /service[_-]?role/i],
  ['direct guest-session extension update', /\.from\(\s*["']guest_sessions["']\s*\)[\s\S]{0,260}?\.update\s*\([\s\S]{0,160}?extended_until/],
  ['UTC datetime-local slicing', /toISOString\(\)\s*\.slice\(\s*0\s*,\s*16\s*\)/],
  ['null-only operations row key', /key=\{`\$\{item\.reservation_room_id\}-\$\{activeTab\}`\}/],
]

const failures = []

for (const [label, pattern] of required) {
  if (!pattern.test(source)) failures.push(`Missing: ${label}`)
}

for (const [label, pattern] of forbidden) {
  if (pattern.test(source)) failures.push(`Unsafe source detected: ${label}`)
}

if (failures.length) {
  console.error('FAIL — Day 10 front-office source gate')
  for (const failure of failures) console.error(`- ${failure}`)
  process.exit(1)
}

console.log(
  `PASS — Day 10 front-office source gate (${required.length} required contracts; ${forbidden.length} unsafe patterns blocked).`
)
