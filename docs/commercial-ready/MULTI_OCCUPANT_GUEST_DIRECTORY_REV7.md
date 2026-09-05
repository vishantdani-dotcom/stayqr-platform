# StayQR Multi-Occupant Guest Directory REV7

## Scope
REV7 closes the remaining multi-occupant CRM summary gap after REV6 check-in acceptance.

### Fixed
- Companion guests now count the shared room stay in Guest Directory & History.
- Companion guests now show `In Room <number>` while the shared guest session is active.
- `Currently in-house` counts guest profiles, including persisted companions.
- Last-stay date and repeat-guest calculations use the companion-aware Guest 360 summary.
- Controlled Guest 360 export inherits companion-aware stay totals/status through `get_guest_360_directory`.
- Communications audience active-room summary now includes companions.
- Existing companion-aware profile modal, per-person ID/KYC linkage and REV6 check-in contract are preserved.

## Database
Migration 113 replaces only:
- `public.get_guest_360_directory(uuid)`
- `public.get_guest_communication_audience(uuid)`

No table/schema rewrite is introduced. Stay membership is a deduplicated union of primary `guest_sessions.guest_id` and `guest_companions.guest_id` memberships.

## Required staging acceptance
1. Apply Migration 113 directly in StayQR Staging SQL Editor.
2. Run the supplied 12-check acceptance SQL; require 12/12 PASS.
3. Deploy the locally validated source to `stayqr-pilot-staging`.
4. Verify existing family companions show 1 stay and In Room 102.
5. Verify existing couple companion shows 1 stay and In Room 101.
6. Verify Currently in-house reflects all guest profiles in active stays.
7. Run one normal single-guest check-in regression.
8. Confirm primary and companion profile modals still show correct private ID documents and shared stay dates.

Production remains out of scope until staging is accepted.
