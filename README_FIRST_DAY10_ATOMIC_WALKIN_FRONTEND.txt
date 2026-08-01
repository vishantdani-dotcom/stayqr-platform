StayQR v1.0 — Day 10 Atomic Walk-In Frontend REV1

PURPOSE
Replaces the unsafe browser-side direct check-in sequence with one call to the
accepted Migration 026 RPC: public.check_in_walk_in_guest(uuid,jsonb).

INSTALLED BEHAVIOUR
- Room, guest session, room charge, inventory allocation, room history,
  companions, stay details and immutable event are committed atomically.
- A stable request ID is retained across failed retries.
- Existing guests can be searched by normalized document, email or phone and
  explicitly selected when legacy duplicate phone groups are ambiguous.
- Guest identity/address, companion and foreign-guest/Form C inputs are mapped
  to the Migration 026 payload.
- Reservation arrivals continue to use the accepted reservation workflow.

INSTALLATION
1. Stop Vite.
2. Extract this patch into C:\Users\HP\Documents\StayQR with -Force.
3. From Frontend run: npm run check
4. Then run: npm run dev

DO NOT
- Use this frontend before Migration 026 has passed 40/40.
- Copy node_modules, dist or .env from this patch.
- Run direct guest/session/payment SQL writes.

BROWSER ACCEPTANCE
Open Check-In/Out and perform one controlled walk-in using a currently free test
room. After success, do not repeat with a new request ID until the server ledger,
payment linkage, room status and idempotent retry are verified.
