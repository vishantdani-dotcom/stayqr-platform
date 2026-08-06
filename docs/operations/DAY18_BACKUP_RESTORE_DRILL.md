# StayQR Day 18 — Backup and Restore Drill

## Scope

The controlled drill follows the Supabase CLI logical-backup flow:

1. dump roles;
2. dump schema;
3. dump data with `COPY`;
4. preserve `supabase_migrations` only when it exists;
5. create a source fingerprint containing only public-table row counts and
   migration status/versions;
6. restore into a local Docker-backed disposable Postgres target;
7. compare the restored public table set and exact row counts.

The scripts never write a database connection string into evidence.

## Important storage boundary

A database backup contains Storage metadata but not the actual object bytes
stored through the Storage API.

Therefore:

- a green database restore drill proves database recoverability for the
  validated SQL backup and public-table fingerprint;
- it does not prove KYC/menu/hotel image object recovery;
- storage object export and re-import must be completed separately before
  final Day 18 lock.

## Prerequisites

Install and make available in `PATH`:

- Supabase CLI;
- Docker Desktop with the engine running;
- PostgreSQL `psql`.

The accepted logical backup must already have passed hashes, manifest,
fingerprint and migration-history-status validation.

## Disposable target contract

The restore drill permits only this local target shape:

```text
host: 127.0.0.1 or localhost
host port: 54322
container port: 5432
database: postgres
user: postgres
PostgreSQL: 17 or newer
public base tables before restore: 0
```

The local target is created in:

```text
C:\StayQR_D18_DISPOSABLE_RESTORE
```

Its identity evidence is:

```text
C:\StayQR_D18_DISPOSABLE_RESTORE\DISPOSABLE_TARGET_IDENTITY.txt
```

A database started with the Supabase CLI is for local development/testing,
not production.

## Source-credential isolation

During the restore drill:

- `STAYQR_SOURCE_DB_URL` must be absent;
- `PGPASSWORD` must be absent;
- the target URL must not contain `supabase.com`;
- the target must be localhost port `54322`;
- the Docker database container must be healthy.

This is stronger than comparing two remote URLs because the production
credential is not loaded at all.

## Preflight only

Set only the local target and confirmation:

```powershell
$env:STAYQR_RESTORE_DB_URL = `
  "postgresql://postgres:postgres@127.0.0.1:54322/postgres"

$env:STAYQR_RESTORE_CONFIRM = `
  "RESTORE_TO_DISPOSABLE_TARGET"
```

Run the no-write preflight:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File ".\scripts\day18-restore-drill.ps1" `
  -RepoRoot "C:\StayQR_D18_WORK" `
  -BackupDirectory `
    "C:\StayQR_D18_WORK\.stayqr-evidence\day18-backup\20260806_052538" `
  -PreflightOnly
```

Required ending:

```text
DAY 18 RESTORE PREFLIGHT PASSED - NO RESTORE EXECUTED
```

## Execute the local restore drill

After the preflight passes, run the same command without `-PreflightOnly`:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File ".\scripts\day18-restore-drill.ps1" `
  -RepoRoot "C:\StayQR_D18_WORK" `
  -BackupDirectory `
    "C:\StayQR_D18_WORK\.stayqr-evidence\day18-backup\20260806_052538"
```

The restore follows the documented Supabase `psql` sequence: one transaction,
`ON_ERROR_STOP=1`, roles, schema, trigger suppression, then data.

When the source had no `supabase_migrations` schema, the no-op marker files are
validated but no migration-history SQL is applied. The target local CLI's own
internal migration history is not compared to a source history that never
existed.

Required ending:

```text
DAY 18 DATABASE RESTORE DRILL PASSED
Public table counts and migration history match.
Target was localhost-only and production credentials were absent.
```

## Evidence

Accepted restore evidence is written below ignored local storage:

```text
.stayqr-evidence/day18-restore/<UTC timestamp>/
```

It contains:

- `DISPOSABLE_TARGET_IDENTITY.txt`;
- `target-fingerprint.json`;
- `restore-report.json`.

No source or target database URL is written to evidence.

## Stop conditions

Stop and preserve output on:

- backup hash or manifest mismatch;
- missing/empty backup artifact;
- database URI found inside evidence;
- source production credential loaded;
- non-local target or wrong port/database/user;
- unhealthy/missing disposable Docker database;
- non-empty public target before restore;
- `psql` error;
- public table-set mismatch;
- public row-count mismatch;
- source migration-version mismatch when source history exists.

Do not weaken a failed restore gate by removing a mismatching table or by
pointing the script at a remote project.
