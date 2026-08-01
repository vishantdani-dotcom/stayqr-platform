StayQR v1.0 — Day 10 Active Room Move Frontend REV1

PREREQUISITE
------------
Migration 029 REV1 must already be installed and its preflight acceptance must
show 28/28 passed.

THIS PATCH ADDS
---------------
- Move Room action for active direct walk-in stays.
- Tenant-scoped available-room loading.
- Same-room-type charge preservation.
- Explicit rate confirmation for cross-room-type moves.
- Stable idempotency request ID.
- Stale-screen source-room evidence.
- Operational reason/audit note.
- Authoritative move_active_walkin_guest_room RPC call.
- Active-stay refresh and calendar invalidation after success.

INSTALL
-------
1. Stop Vite with Ctrl + C.
2. Place the ZIP in:
   C:\Users\HP\Documents\StayQR
3. Extract it to that same StayQR folder with overwrite enabled.
4. Run:
   cd C:\Users\HP\Documents\StayQR\Frontend
   npm run check
5. Start:
   npm run dev

CONTROLLED BROWSER ACCEPTANCE
-----------------------------
1. Open Guests -> Active stays.
2. On Day10 Walkin Test Guest / Room 106, click Move Room.
3. Select Room 108.
4. Confirm that the interface says the existing ₹2,500 charge is preserved.
5. Enter:
   Day 10 controlled same-type room move acceptance.
6. Do not alter the generated request ID.
7. Do not click Confirm room move until instructed after the prepared-form
   screenshot is reviewed.

IMPORTANT
---------
- Do not move Room 107.
- Do not use Final Bill & Checkout.
- Do not use Extend Stay during this test.
- This frontend does not directly update sessions, rooms, allocations,
  payments, history or housekeeping; the authoritative RPC owns the transaction.
