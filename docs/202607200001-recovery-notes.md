# StayQR Migration 202607200001 — Recovery Notes

The migration is wrapped in one transaction. If any statement fails before the
final `COMMIT`, PostgreSQL automatically rolls back the complete migration.

## Before running

1. Do not edit individual statements.
2. Keep the SQL Editor result visible.
3. Run the verification query immediately after success.
4. Do not manually delete the `private` archive tables.

## Archived rows

Complete pre-change copies are stored in:

- `private.hotel_info_archive_20260720`
- `private.hotel_users_archive_20260720`
- `private.rooms_archive_20260720`

These tables are inaccessible to browser roles.

## Emergency recovery

Do not run a broad rollback automatically after hotels begin using the secured
schema. A safe rollback depends on whether new records were created after the
migration. Use the archive tables and migration-specific indexes/policies to
prepare a forward-fix or controlled recovery.

The first response to an unexpected result is:

1. stop further writes;
2. export the verification result;
3. preserve database logs;
4. prepare an explicit corrective migration.

Never restore the old unrestricted public financial policies merely to make a
screen work.
