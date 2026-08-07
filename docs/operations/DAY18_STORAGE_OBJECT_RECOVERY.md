# StayQR Day 18 — Storage Object Backup and Isolated Restore

## Purpose

Close the Day 18 storage-recovery boundary left by the database-only restore drill.

The database drill proves SQL recoverability, but Supabase database backups contain
Storage metadata rather than the actual Storage object bytes. This drill therefore:

1. reads every Files bucket from the StayQR production source;
2. downloads every object byte to ignored local evidence;
3. calculates a SHA-256 for every object and a deterministic object-set SHA-256;
4. restores the backup into temporary private buckets in the dedicated StayQR Staging project;
5. downloads the restored bytes and compares object path, object count, total byte count and SHA-256;
6. deletes the temporary staging buckets after verification;
7. records a sanitized acceptance report without credentials or raw object bytes.

## Source-read proof

Production downloads are routed through the reusable `downloadBytes(bucketApi, objectPath)`
helper. The source gate verifies both the helper's `.download()` implementation and the
specific call `downloadBytes(source.storage.from(bucketName), fullPath)`. This preserves
the strict source-read-only contract while allowing the implementation to use a helper.

## Production safety contract

The operational runner contains no production/source upload, delete, move, copy,
bucket-create or bucket-delete operation. Source access is limited to bucket
listing, object listing and object download.

The target is hard-locked to `ggtcvgteefcrlwvxkfwf.supabase.co`.

The runner refuses to run if source and target are the same project or if the
target is not the dedicated StayQR Staging project.

## Required StayQR buckets

- `hotel-assets`
- `guest-guide-media`
- `guest-documents`

## Acceptance

A successful run requires:
- required production buckets present;
- at least one real production object byte backed up;
- every local backup byte matches source SHA-256;
- isolated staging restore succeeds;
- object count and total bytes match;
- every object path/size/SHA-256 matches;
- source/restored deterministic object-set SHA-256 values match;
- temporary staging restore buckets are deleted;
- no production/source write operation is executed.
