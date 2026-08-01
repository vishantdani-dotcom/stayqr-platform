# Day 3 Browser Runtime Test Cleanup

The Day 3 browser exit gate created two intentionally identifiable records in
the production Supabase project:

- `RES-2026-000001` — advance create/edit/cancel test;
- `RES-2026-000002` — walk-in/no-show test;
- `StayQR UI Test Guest` — phone `9000000011`.

The cleanup script is intentionally strict. It aborts unless it finds exactly
those two reservations under one hotel and verifies the exact guest identity.

It removes:

- the two test reservations;
- their reservation rooms and allocations;
- reservation guest links;
- status history;
- reservation deposits;
- related activity logs;
- the exact test guest when no other record references it;
- the 2026 booking-number sequence only when no 2026 reservation remains.

The runtime screenshots and source-controlled test scripts remain the evidence
that Day 3 passed.
