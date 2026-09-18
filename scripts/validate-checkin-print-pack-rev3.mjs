import fs from 'node:fs'

const files = {
  guests: 'src/pages/guests/Guests.jsx',
  guestsCss: 'src/pages/guests/Guests.css',
  print: 'src/lib/checkInPrintPack.js',
}

for (const path of Object.values(files)) {
  if (!fs.existsSync(path)) throw new Error(`Missing ${path}`)
}

const guests = fs.readFileSync(files.guests, 'utf8')
const guestsCss = fs.readFileSync(files.guestsCss, 'utf8')
const print = fs.readFileSync(files.print, 'utf8')

const checks = [
  ['Guests imports stored print helper', guests.includes('printStoredCheckInPaperwork')],
  ['Guests loads tenant permissions', guests.includes('loadTenantContext')],
  ['Sensitive print permission boundary preserved', guests.includes('"guests.manage", "checkin.manage", "checkout.manage"')],
  ['Active stay print button exists', guests.includes('Print check-in pack')],
  ['Registration-only reprint button exists', guests.includes('Registration card')],
  ['Paperwork UI is scoped to active stay cards', guests.includes('FRONT DESK PAPERWORK')],
  ['Existing stay printer exported', print.includes('export async function printStoredCheckInPaperwork')],
  ['Existing stay must be active', print.includes("session.status !== 'active'")],
  ['Stored snapshot is hotel scoped', print.includes(".eq('hotel_id', hotel.id)")],
  ['Stored snapshot is session scoped', print.includes(".eq('guest_session_id', sessionId)")],
  ['Companions are reconstructed', print.includes(".from('guest_companions')")],
  ['Stay details are reconstructed', print.includes(".from('guest_stay_details')")],
  ['Stored documents are reconstructed', print.includes(".from('guest_documents')")],
  ['Stored ID images use temporary signed URLs', print.includes('.createSignedUrl(entry.storagePath, 300)')],
  ['Stored ID prints remain audited', print.includes("action: 'print'")],
  ['Masked references are used', print.includes('maskIdReference')],
  ['A4 print declaration preserved', print.includes('@page{size:A4;margin:10mm}')],
  ['Tablet/mobile print preview breakpoint exists', print.includes('@media screen and (max-width:860px)')],
  ['Phone print preview breakpoint exists', print.includes('@media screen and (max-width:560px)')],
  ['Mobile paperwork action layout exists', guestsCss.includes('@media (max-width: 700px)') && guestsCss.includes('.guest-paperwork-actions')],
  ['Mobile buttons are full width', guestsCss.includes('width: 100% !important')],
]

let passed = 0
for (const [label, ok] of checks) {
  if (!ok) throw new Error(`FAIL ${label}`)
  passed += 1
  console.log(`PASS ${String(passed).padStart(2, '0')} ${label}`)
}

console.log(`CHECK-IN PRINT PACK REV3 VALIDATION: ${passed}/${checks.length} passed.`)
