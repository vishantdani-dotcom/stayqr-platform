# Day 18 canonical database baseline

## Why the historical chain was rebased

The authoritative StayQR source database had 134 public tables and no `supabase_migrations.schema_migrations` relation. The historical files were production-upgrade migrations for an already-existing legacy database, not an empty-database bootstrap chain. The first historical migration therefore referenced legacy tables before creating them, and duplicate timestamp versions also prevented a clean long-term Supabase CLI history.

## Active migration chain

1. `202608060060_day18_canonical_schema_baseline_REV1.sql` - schema-only baseline created from the accepted Day 18 source snapshot. It contains an empty-target guard and refuses to run when public tables or views already exist.
2. `202608060061_day18_default_privilege_hardening_REV1.sql` - revokes automatic future privileges on tables, sequences, and functions from `anon` and `authenticated`, while preserving explicit grants and RLS policies.

## Historical migration archive

The complete Day 1-Day 18 upgrade chain is preserved under:

`docs/database/legacy-migrations/pre-day18-canonical-baseline/`

`SHA256SUMS.txt` records the SHA-256 hash of every archived SQL file. Source-check scripts that verify historical contracts read the preserved files from this archive.

## Production boundary

The canonical baseline must never execute on the existing production database. Its SQL guard rejects every non-empty public schema. Production migration-history adoption is a separate controlled operation: verify the production fingerprint, record version `202608060060` as already applied without executing the baseline, and then apply only later migrations through the normal controlled pipeline.

Netlify frontend deployments do not execute database migrations.

## Staging boundary

The separate StayQR Staging project was created as a disposable empty target. The two-file canonical chain was applied there and verified against the accepted schema fingerprint before frontend preview deployment.

## Data boundary

The baseline contains schema only. It does not contain production rows, Auth users, database passwords, API keys, service-role credentials, or Storage object bytes.
