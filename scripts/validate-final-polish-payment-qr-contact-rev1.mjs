import fs from 'node:fs'
const paymentsCss = fs.readFileSync('src/styles/finalRev19.css', 'utf8')
const roomAccess = fs.readFileSync('src/pages/roomaccess/RoomAccess.jsx', 'utf8')
const roomCss = fs.readFileSync('src/pages/roomaccess/RoomAccess.css', 'utf8')
const migration = fs.readFileSync('supabase/migrations/202609190123_room_qr_reception_contact_REV1.sql', 'utf8')

const checks = [
  ['desktop payment guest column gets usable width', /@media\(min-width:721px\)\{[\s\S]*?payments-modern-table th:nth-child\(2\),\.payments-modern-table td:nth-child\(2\)\{min-width:180px!important;width:180px!important\}/.test(paymentsCss)],
  ['desktop guest names do not split mid-word', /payments-modern-table td:nth-child\(2\)>strong\{[\s\S]*?word-break:normal!important;[\s\S]*?overflow-wrap:break-word!important/.test(paymentsCss)],
  ['mobile payment layout breakpoint remains', /@media\(max-width:720px\)/.test(paymentsCss)],
  ['inactive QR reads reception phone', roomAccess.includes("context?.reception_phone")],
  ['inactive QR extension/help prompt present', roomAccess.includes('Need help or want to extend your stay?')],
  ['inactive QR renders reception number', roomAccess.includes('<strong>{receptionPhone}</strong>')],
  ['inactive QR call action present', roomAccess.includes('href={`tel:${dialableReceptionPhone}`}')],
  ['inactive QR missing-contact fallback present', roomAccess.includes('Reception contact is not configured. Please visit the front desk for assistance.')],
  ['inactive QR contact styling present', roomCss.includes('.room-entry-support') && roomCss.includes('.room-entry-call')],
  ['public context uses hotel reception phone', migration.includes("'reception_phone'") && migration.includes('public.hotel_info')],
  ['valid QR guards preserved', migration.includes('q.is_active') && migration.includes('r.is_active') && migration.includes("h.status = 'active'")],
  ['anon QR visitors retain RPC execute', migration.includes('grant execute on function public.get_room_qr_public_context(uuid) to anon, authenticated')],
]
let failed = 0
for (const [name, ok] of checks) {
  console.log(`${ok ? 'PASS' : 'FAIL'} ${name}`)
  if (!ok) failed++
}
console.log(`\nFINAL POLISH PAYMENT + QR CONTACT: ${checks.length - failed}/${checks.length} passed.`)
if (failed) process.exit(1)
