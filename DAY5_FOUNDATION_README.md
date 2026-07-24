# StayQR Day 5 — Foundation Package

This package is built from the uploaded post-Day-4 source.

## Included now

- Exact-source audit.
- Atomic reservation-room check-in migration.
- Reservation deposit-to-payment transfer ledger.
- Group/multi-room add/remove RPCs.
- Arrivals/departures read model.
- Authoritative reservation confirmation snapshot.
- Reservation-linked checkout status synchronization.
- Foundation verification audit.

## First execution

1. Overlay this package onto the current `Frontend` folder. It contains the complete source tree and excludes `.env`, `node_modules`, `dist`, and `.git`.
2. Run the complete Supabase migration:
   `supabase/migrations/202607240007_reservation_checkin_folio_operations.sql`
3. Run:
   `supabase/audit/020_verify_day5_foundation.sql`
4. Every verification row must show `passed = true`.

Do not run browser check-in tests before the database verification is green.
