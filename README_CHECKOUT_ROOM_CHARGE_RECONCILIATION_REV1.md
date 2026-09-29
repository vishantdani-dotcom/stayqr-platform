# StayQR Checkout Room-Charge Reconciliation REV1

Base release: `66e9484aa76d062e2c1c0941c7a12ab1fb57b4f2`
Date: 2026-09-29
Scope: Final Bill & Checkout room-charge correctness for long/overdue stays.

## Problem fixed

The existing checkout screen correctly calculated elapsed stay duration but used only the already-posted room charge. An overdue/multi-night stay could therefore display many billable nights while the room charge still reflected only the original posted amount.

## New checkout behaviour

- Recovers the agreed nightly rate from the reservation or walk-in check-in audit record.
- Calculates `agreed nightly rate × elapsed billable nights` as the suggested room charge.
- Never silently reduces an already-posted charge.
- Shows current posted charge, calculated charge and an editable **Final room charge**.
- Any change requires an adjustment reason and an explicit confirmation checkbox.
- Tax/discount/room-charge changes reset the "payment collected" confirmation.
- The final room-charge change is performed by a security-definer RPC before invoice issuance.
- The RPC locks the active stay and room-charge payment, rejects stale screens, blocks changes after an invoice exists, updates the authoritative `payments` source and relies on the existing Day 11 payment→folio trigger to synchronize the folio.
- Every change is recorded in `guest_session_room_charge_events` and the activity log.

## Files changed

- `src/pages/guests/Guests.jsx`
- `src/lib/day5Reservations.js`
- `supabase/migrations/202609290124_checkout_room_charge_reconciliation_REV1.sql`
- `supabase/audit/202609290124_checkout_room_charge_reconciliation_ACCEPTANCE.sql`
- `supabase/rollback/202609290124_checkout_room_charge_reconciliation_ROLLBACK_REV1.sql`
- `scripts/validate-checkout-room-charge-reconciliation.mjs`

## Safe deployment order

1. Apply Migration 124 to staging.
2. Run the Migration 124 acceptance SQL; every field must be `true`.
3. Deploy the patched frontend to staging and test one normal stay and one overdue stay.
4. Apply Migration 124 to production.
5. Deploy the exact same validated frontend build/source to Production context.
6. Reopen the active stay and verify the Final Bill before collecting payment.

Do not deploy the frontend before the RPC migration is available in the same environment.

## Velvet Loom acceptance example

For the current demo stay shown on 2026-09-29:

- Posted room charge: ₹2,500
- Agreed nightly rate: ₹2,500 (if recovered/confirmed)
- Checkout screen duration: 12 billable nights / ~266 hours
- Calculated room charge: ₹30,000
- Final room charge remains editable by authorized staff.

The hotel must confirm the final amount according to its own billing policy before checkout. StayQR will not silently post the calculated amount.

## Local source validation

```powershell
node scripts/validate-checkout-room-charge-reconciliation.mjs
```

Expected: `16/16 checks passed.`
