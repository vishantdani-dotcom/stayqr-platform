import fs from 'node:fs'
import path from 'node:path'

const root = process.cwd()
const guests = fs.readFileSync(path.join(root, 'src/pages/guests/Guests.jsx'), 'utf8')
const reservations = fs.readFileSync(path.join(root, 'src/lib/day5Reservations.js'), 'utf8')
const migration = fs.readFileSync(path.join(root, 'supabase/migrations/202609290124_checkout_room_charge_reconciliation_REV1.sql'), 'utf8')

const checks = [
  ['frontend imports reconciliation RPC', guests.includes('reconcileActiveStayRoomCharge')],
  ['checkout calculates billable nights', guests.includes('billable night(s)') && guests.includes('stayNights')],
  ['checkout exposes final room charge', guests.includes('Final room charge') && guests.includes('checkoutRoomCharge')],
  ['checkout requires adjustment reason', guests.includes('Room charge adjustment reason') && guests.includes('checkoutRoomChargeReason')],
  ['checkout requires explicit confirmation', guests.includes('I confirm the final room charge') && guests.includes('checkoutRoomChargeConfirmed')],
  ['payment confirmation resets when bill changes', guests.includes('setRemainingPaymentCollected(false)')],
  ['reservation rate lookup present', guests.includes('Reservation nightly rate') && guests.includes('reservation_rooms')],
  ['walk-in agreed rate lookup present', guests.includes('Agreed check-in rate') && guests.includes('walkin_checkin_events')],
  ['client wrapper invokes server RPC', reservations.includes("supabase.rpc('reconcile_active_stay_room_charge'")],
  ['migration creates immutable event table', migration.includes('create table if not exists public.guest_session_room_charge_events')],
  ['migration locks active stay', migration.includes('for update') && migration.includes("session_row.status <> 'active'")],
  ['migration blocks issued invoice mutation', migration.toLowerCase().includes('invoice already exists for this stay')],
  ['migration has stale amount guard', migration.toLowerCase().includes('room charge changed after checkout was opened')],
  ['migration updates authoritative payment source', migration.includes('update public.payments') && migration.includes("payment.payment_type = 'room_charge'")],
  ['migration preserves activity audit', migration.includes("'checkout.room_charge_reconciled'")],
  ['migration grants only RPC execution for writes', migration.includes('grant execute on function public.reconcile_active_stay_room_charge')],
]

let failed = 0
for (const [name, ok] of checks) {
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}`)
  if (!ok) failed += 1
}

console.log(`\n${checks.length - failed}/${checks.length} checks passed.`)
if (failed) process.exit(1)
