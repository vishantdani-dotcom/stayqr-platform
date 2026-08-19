# StayQR Batch B — Staff Avatar Persistence Fix REV1

## Root cause
`loadTenantContext()` already selected `staff.avatar_path`, but the `currentStaff`
object omitted the field. After a browser refresh, `getCurrentStaff()` therefore
returned no avatar path, so the Staff page could not create a fresh signed URL.

## Fix
Propagate `selectedAccess.staff.avatar_path` into `currentStaff.avatar_path`.

## Database impact
None. Migration 084, the private `staff-avatars` bucket, RLS policies, and
`update_my_staff_profile` RPC remain unchanged.

## Acceptance
Run:
`node scripts/validate-postlaunch-batch2-staff-avatar-persistence.mjs`
then the existing Batch B source gate, lint, and build.
