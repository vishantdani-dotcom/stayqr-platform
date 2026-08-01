# Day 7 Stage 2 — Frontend guest-access hardening

## Implemented

- Secure Guest Access now consumes the full Migration 014 lifecycle contract: `stay_active`, `access_active`, `access_status`, token expiry, usage and revocation reason.
- Revoked or expired access does not display a signed URL or QR. Staff must explicitly choose **Activate new secure link**.
- Active guest-guide and food-menu QR codes are generated locally in the browser as SVG. The signed token is never sent to a third-party QR image endpoint.
- QR downloads are vector SVG files suitable for printing.
- Guest URL parsing rejects malformed encoding, invalid slugs, room-number routes and tokens that are not UUID-plus-HMAC format before calling Supabase.
- Invalid, expired and revoked food links now show a generic safe state without confirming room or guest data.
- `npm run security:day7` adds a repeatable 12-check frontend source gate.

## Database evidence

- Migration `202607260014_day7_guest_access_revocation_and_local_qr_hardening.sql` applied successfully.
- Audit `038_verify_day7_guest_access_revocation_hardening.sql` passed 24/24 on 26 July 2026.
- Diagnostic 039 REV2 passed 10/10 and confirmed no stale relation named `guest` exists.

## Remaining Day 7 exit gate

- Run clean Windows install/build using the supplied source package.
- Browser-test valid, malformed, tampered, revoked, rotated and checkout-invalidated links.
- Run the controlled Hotel A/Hotel B authenticated isolation and room-number-guessing suite.
