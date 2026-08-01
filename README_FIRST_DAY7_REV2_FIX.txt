RUN THIS REV2 MIGRATION FILE

supabase/migrations/202607260013_day7_guest_access_and_rls_foundation.sql

The original v1 migration failed before commit because PostgreSQL does not allow a composite %ROWTYPE variable in a multiple-item INTO list. REV2 separates composite-row and scalar assignments in all affected functions.

After migration success, run:
supabase/audit/037_verify_day7_guest_access_and_rls_foundation.sql

Required result: 20 rows, every passed value = true.
