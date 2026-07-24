# Day 5 foundation execution

1. Open Supabase SQL Editor using role `postgres`.
2. Run the complete migration:
   `supabase/migrations/202607240007_reservation_checkin_folio_operations.sql`
3. A single blank `pg_advisory_xact_lock` result row is expected.
4. Run:
   `supabase/audit/020_verify_day5_foundation.sql`
5. Every returned row must have `passed = true`.
6. Do not start browser check-in testing until this verification is green.
