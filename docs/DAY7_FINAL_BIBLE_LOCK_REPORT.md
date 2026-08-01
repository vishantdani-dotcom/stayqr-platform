# StayQR v1.0 — Day 7 Final Bible Lock Report

**Date completed:** 27 July 2026  
**Status:** COMPLETE AND LOCKED WITHOUT QUALIFICATION  
**Primary outcome:** Full tenant/RLS and guest-access security

## Bible row completion

Day 7 required:

- removal of fixed hotel IDs and fallback tenant behavior;
- canonical tenant-context usage;
- RLS coverage for every existing and newly added tenant table;
- private, hotel-folder-scoped Storage policies;
- signed, rotating and revocable guest QR access;
- hotel-slug guest URLs;
- anonymous access restricted to approved RPCs/views;
- security tests;
- automated Hotel A versus Hotel B isolation;
- rejection of room-number guessing.

Every listed requirement is implemented and evidenced.

## Final acceptance evidence

### Guest access and browser lifecycle

- Signed Guest Guide and Food Menu links worked anonymously.
- Tampered signatures were rejected.
- A valid token with a wrong hotel slug was rejected.
- `/guest/{room-number}` and `/food/{room-number}` guessing was rejected.
- Rotation immediately invalidated both previous links.
- Manual revocation persisted until explicit reactivation.
- Already-open guest pages revalidated on focus/visibility and cleared data without manual refresh.
- Checkout invalidated guest access, closed the stay, produced the invoice and queued the room for cleaning.

### Database tenant isolation

- Audit 038: 24/24 passed.
- Audit 040: 18/18 passed.
- Audit 041: 8/8 passed.
- Hotel A SELECT against Hotel B: 40/40 blocked.
- Hotel A UPDATE against Hotel B: 40/40 blocked.
- Audit 042 runtime INSERT against Hotel B: 40/40 blocked.
- Audit 042 runtime DELETE against Hotel B: 40/40 blocked.
- All current tenant tables carrying `hotel_id` have RLS.
- Append-only/RPC-owned tables safely deny unsupported direct writes by default.

### Supabase Storage API isolation

Real browser calls through the Supabase Storage API produced 25/25 passes:

- Hotel A could not select Hotel B objects.
- Hotel A could not upload into Hotel B folders.
- Hotel A could not update Hotel B objects.
- Hotel A could not delete Hotel B objects; survival was verified after restoring Platform Admin access.
- Hotel A could upload, select, update, download and delete objects in its own folders.
- Both `hotel-assets` and `guest-documents` passed.
- All audit fixtures were removed.
- SQL 019 final cleanup and lock verification: 12/12 passed.

Audit 042's two SQL-only Storage positive-control failures are superseded by the valid Storage API evidence. Supabase Storage object mutations must be tested through the Storage API, not by direct SQL metadata deletion.

## Permanent security state

- Anonymous direct table access: blocked.
- Anonymous execution: exactly six approved signed-token guest RPCs.
- Storage buckets: private.
- Storage policies: eight hotel-folder-scoped CRUD policies.
- Storage folder helper: executable by `authenticated` for policy evaluation; unavailable to `anon`.
- Guest tokens remain bound to the authoritative hotel, room and stay.
- Audit helper functions and temporary context tables were removed.

## Frontend validation

- ESLint: 0 errors, 17 pre-existing warnings.
- Relative imports: 141/141 resolved.
- Day 7 source security gate: 15/15.
- Local QR engine: 5/5.
- Production build: passed.
- Temporary `/internal/day7-storage-audit` route and component are not present in this locked source.

## Applied Day 7 migrations

- `202607260013_day7_guest_access_and_rls_foundation.sql`
- `202607260014_day7_guest_access_revocation_and_local_qr_hardening.sql`
- `202607260015_day7_fix_guest_access_revoke_ambiguity.sql`
- `202607260016_day7_storage_policy_helper_execution_fix.sql`

## Non-blocking carry-forward items

- 17 existing React Hook dependency warnings.
- Production bundle chunk-size warning; code splitting belongs to the infrastructure/performance phase.
- Historical expired guest-session rows can still appear as `Active` in the legacy Guests list. Secure guest access correctly treats them as inactive based on stay expiry. Track this as a Front Office/data-state consistency issue.

Day 7 must remain locked unless a genuine security, tenant-isolation, data-integrity or launch-blocking defect is discovered.
