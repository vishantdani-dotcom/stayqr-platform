STAYQR DAY 7 — REV3 COMPLETE FRONTEND CORRECTION

Use the complete Frontend folder from this package.
Do not combine it with the earlier v1 or REV2 migration file.

The REV3 migration fixes both source-specific PostgreSQL failures:
1. composite %ROWTYPE variables are no longer used in multi-item INTO lists;
2. public.food_order_items is safely upgraded with a mandatory hotel_id,
   backfilled from its parent order, validated against the menu item, and
   protected by a tenant-enforcement trigger without creating ambiguous
   PostgREST relationships.

RUN IN THIS ORDER
1. npm run check
2. supabase/migrations/202607260013_day7_guest_access_and_rls_foundation.sql
3. supabase/audit/037_verify_day7_guest_access_and_rls_foundation.sql

EXPECTED
- Migration: one blank pg_advisory_xact_lock row.
- Audit 037: 22 rows and every passed value = true.

The earlier failed migration was transactional and rolled back. No rollback SQL
is required before running REV3.
