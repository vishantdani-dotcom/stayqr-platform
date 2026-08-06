# StayQR legacy migrations before the Day 18 canonical baseline

This directory preserves the complete historical Day 1-Day 18 upgrade chain without content changes.

The files are no longer active under `supabase/migrations` because they were written for an already-existing legacy database, included duplicate timestamp versions, and could not bootstrap a fresh empty staging database. The authoritative source database also had no `supabase_migrations.schema_migrations` history.

The active migration chain now begins with:

- `202608060060_day18_canonical_schema_baseline_REV1.sql`
- `202608060061_day18_default_privilege_hardening_REV1.sql`

Historical source-check scripts may read these archived SQL files to verify the contracts that were accepted during Days 1-18.

Never delete or edit this archive. `SHA256SUMS.txt` records the expected SHA-256 hash of every preserved SQL file.
