# StayQR v1.0 — Day 1 Baseline

## Verified locally

- Clean dependency installation succeeds with `npm ci`.
- Production build succeeds.
- Existing application bundle has a large-chunk warning and requires later code splitting.
- Lint baseline previously contained 11 errors and 19 warnings.

## Changes in this baseline patch

- Removed the hard-coded default hotel fallback from `getCurrentHotel()`.
- Changed Check-In to resolve and filter by the authenticated user's hotel.
- Ensured new rooms are inserted with an explicit `hotel_id`.
- Added the `npm run check` quality command.
- Added a read-only Supabase schema/RLS snapshot query.
- Removed current blocking lint errors while retaining Hook dependency warnings for staged refactoring.

## Known critical work still pending

- Check-In remains a multi-request browser workflow and is not yet atomic. It must be replaced by a transactional database function during the reservation/front-office sprint.
- Guest QR URLs still use room numbers and must be replaced with random, revocable access tokens.
- RLS cannot be certified until the live schema snapshot is reviewed.
- Automated tests and CI/CD are not yet present.
- Application bundle code splitting is pending.

## Next gate

Run `supabase/audit/001_export_schema_snapshot.sql` in the live Supabase SQL Editor and preserve the returned JSON. Then create the authoritative migration baseline and Reservation schema.
