# StayQR Day 6 Final Identity Reconciliation and Authorization

## Why this stage exists

The browser acceptance test proved that real staff invitation, password creation,
password recovery, role-restricted navigation, suspension, Auth banning and
reactivation work. The final source audit still found two production concerns:

1. a legacy active staff profile could exist without a real Supabase Auth user;
2. the Edge Function gateway could reject ES256 access tokens before the
   function's own trusted Auth verification ran.

## Final corrections

- Legacy unlinked active profiles are preserved as inactive archived profiles.
- Exact verified-email matches are linked automatically.
- Valid linked `hotel_users` memberships are converted into authoritative staff
  rows when required.
- Active and invited access now requires a real Auth user at constraint level.
- `staff` is the sole hotel-access authority; `hotel_users` is a synchronized
  compatibility mirror only.
- Staff identity lifecycle events are recorded in a protected server-written
  ledger.
- Staff list RLS permits self-read and full hotel-list access only with
  `staff.view`.
- Reservation, payment, invoice, housekeeping and hotel configuration writes use
  the canonical permission matrix.
- The Edge Function is deployed without gateway JWT verification and verifies
  the bearer token directly against Supabase Auth before using service-role
  operations.
- Staff disable/suspend and Auth ban operations include compensating rollback if
  the database update fails.
- Preserved legacy profiles now expose a `Send identity invite` action.
- Reception Dashboard greetings use the authenticated staff identity instead of
  the hard-coded word `Admin`.

## Acceptance sequence

1. Run migration `202607250012`.
2. Run Audit `032`; all 16 rows must pass.
3. Deploy `manage-staff-user` with `--no-verify-jwt`.
4. Suspend and reactivate the Day 6 Reception test identity once to verify the
   corrected function returns success without the ES256 gateway error.
5. Run Audit `033` to create the private final-gate context.
6. Run Audit `034`; all 20 rows must pass.
7. Run Audit `035` to remove the temporary Day 6 test Auth identity.
8. Run Audit `036`; all 8 rows must pass.
9. Run `npm run check`, commit, push and verify a clean working tree.

The inactive archived legacy profile is production history, not test data. It is
not deleted during cleanup. A Platform Admin or hotel manager may later use
`Send identity invite` to create/link a real Auth identity and restore it.
