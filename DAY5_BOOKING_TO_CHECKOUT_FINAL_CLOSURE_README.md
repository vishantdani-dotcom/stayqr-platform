# StayQR Day 5 — Final Booking-to-Checkout Closure

This patch closes the only remaining Day 5 completion-gate item: a controlled, end-to-end booking-to-checkout smoke test.

## What this patch changes

- Replaces the old browser-side multi-request checkout with one server-controlled atomic RPC.
- Creates the final invoice, line items and exact remaining collection in one transaction.
- Links the reservation deposit and final settlement to the invoice exactly once.
- Completes the guest session and expires guest access.
- Changes the linked reservation room and booking to `checked_out`.
- Releases the authoritative room inventory allocation on early checkout.
- Changes the physical room to `cleaning` and creates exactly one housekeeping task.
- Adds an immutable checkout event for duplicate-checkout rejection and audit.
- Corrects checkout preview queries so multi-room bookings are scoped to the selected room/session rather than combining the same guest's other rooms.
- Adds controlled seed, final acceptance, cleanup and cleanup-verification SQL.

## Files added

- `supabase/migrations/202607240010_atomic_checkout_and_booking_completion.sql`
- `supabase/audit/026_verify_day5_atomic_checkout_foundation.sql`
- `supabase/audit/027_seed_day5_booking_checkout_smoke.sql`
- `supabase/audit/028_day5_booking_checkout_final_gate.sql`
- `supabase/audit/029_cleanup_day5_booking_checkout_smoke.sql`
- `supabase/audit/030_verify_day5_booking_checkout_cleanup.sql`

## Files updated

- `src/lib/day5Reservations.js`
- `src/pages/guests/Guests.jsx`
- `src/pages/guests/Guests.css`

---

# Exact execution order

## 1. Overlay the source

Stop the dev server. Copy everything inside this package's `Frontend` folder into:

```text
C:\Users\HP\Documents\StayQR\Frontend
```

Choose **Replace files in the destination**. Do not delete the destination first. Preserve the existing `.env` and `node_modules`.

## 2. Apply the migration

In Supabase SQL Editor, open a **new query**, paste the complete contents of:

```text
supabase/migrations/202607240010_atomic_checkout_and_booking_completion.sql
```

Use **Primary Database**, role **postgres**, and click **Run**. One blank `pg_advisory_xact_lock` row is expected.

## 3. Verify the foundation

Run:

```text
supabase/audit/026_verify_day5_atomic_checkout_foundation.sql
```

Required: **8 rows and every `passed` value is `true`.**

## 4. Run the frontend check

From the Frontend terminal:

```powershell
npm run check
npm run dev
```

Required: `0 errors`. Existing unrelated warnings may remain.

## 5. Create controlled smoke-test data

Run:

```text
supabase/audit/027_seed_day5_booking_checkout_smoke.sql
```

The result returns the selected hotel, business date, reservation number, room, total, deposit and expected remaining balance. Do not run cleanup yet.

## 6. Browser test — check in

1. Log in as Platform Admin.
2. Select the hotel returned by Audit 027, normally **VD Stay Inn**.
3. Open **Arrivals & Departures**.
4. Set the Business Date to the exact date returned by Audit 027.
5. Locate the controlled guest **StayQR Day 5 Checkout Smoke Guest**.
6. Click **Check in** and confirm.

Required:

- Success notification appears.
- The reservation leaves Today Arrivals and enters In House.
- The room becomes Occupied.
- The reservation and room record become Checked In.
- The notification confirms the controlled deposit was transferred.

## 7. Browser test — final bill and checkout

1. Open **Guests**.
2. Locate **StayQR Day 5 Checkout Smoke Guest**.
3. Click **Final Bill & Checkout**.
4. Keep Tax at `0` and Discount at `0` for this controlled smoke test.
5. Confirm that the preview shows the reservation total, previously paid deposit and exact remaining amount.
6. Select **Cash** as Final Payment Method.
7. Tick the confirmation that the remaining amount has been collected.
8. Click **Confirm Settlement & Checkout**.

Required:

- A green success notification shows the new invoice number.
- The controlled guest disappears from the active Guests list.
- Reservation and reservation-room status become Checked Out.
- Room status becomes Cleaning.
- The active inventory allocation is released.
- Exactly one room-cleaning task is created.
- No duplicate stay, invoice, collection or checkout event is created.

## 8. Browser proof after checkout

Verify all of the following before the final gate:

- **Reservations:** controlled reservation is Checked Out.
- **Booking Calendar:** enable Checked Out status; one historical checked-out card is shown for the controlled room.
- **Arrivals & Departures:** the controlled record is absent from Today Arrivals, In House and pending Today Departures.
- **Rooms:** controlled room is Cleaning.
- **Housekeeping:** exactly one pending room-cleaning task exists for the controlled room.
- **Invoices:** exactly one paid invoice exists. Open it and test PDF, Print and WhatsApp. Total, paid amount and balance must match.
- **Tenant isolation:** switch to the other hotel returned by Audit 027. The controlled reservation, room, guest and invoice must not appear. Switch back before running the final SQL gate.

## 9. Run the final database gate

Run:

```text
supabase/audit/028_day5_booking_checkout_final_gate.sql
```

Required: **13 rows and every `passed` value is `true`.**

This audit also performs a duplicate-checkout retry and confirms that it is rejected without creating any second invoice, payment or event.

## 10. Cleanup

Only after Audit 028 passes, run:

```text
supabase/audit/029_cleanup_day5_booking_checkout_smoke.sql
```

Then run:

```text
supabase/audit/030_verify_day5_booking_checkout_cleanup.sql
```

Required: every `remaining_*` value is `0`.

Do not rerun Audit 027 after cleanup unless the entire smoke test must be repeated.

## 11. Repository closure

```powershell
git status --short
git add .
git commit -m "feat: complete Day 5 booking-to-checkout smoke test"
git push
git status
```

Required final result:

```text
Your branch is up to date with 'origin/stayqr-v1-reservation-system'.
nothing to commit, working tree clean
```

Once the migration, 8 foundation checks, browser evidence, 13 final checks, cleanup zeros, frontend check and clean Git status all pass, Day 5 is formally 100% complete.
