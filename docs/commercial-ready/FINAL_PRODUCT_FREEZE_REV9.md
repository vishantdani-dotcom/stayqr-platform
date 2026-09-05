# StayQR Final Product Freeze REV9

Date: 2026-09-05
Launch intent: complete the sellable StayQR application without making external-provider activation a launch blocker.

## Locked launch decisions

- Meta / WhatsApp Cloud API automated campaigns: **HOLD / Upcoming**.
- Cashfree recurring AutoPay: **HOLD / Upcoming**.
- Formal UIDAI online authentication: **HOLD / not marketed as live**.
- Subscription collection for launch: **manual / offline billing**.
- Existing hardened provider backend work remains in source with provider flags defaulting to `false`.
- Product UI must not require hotels to complete external-provider activation to operate StayQR.

## Core USP — auto-activated permanent room QR

Every active room receives one high-entropy permanent StayQR QR code. The hotel prints the QR once and may place the same room QR on a key-card sleeve and an in-room standee.

Normal stay lifecycle:

1. Reception checks a guest into a room.
2. Existing StayQR guest-session triggers create/rotate the signed, expiring guest-access token.
3. The permanent room QR immediately resolves the current checked-in stay without a PIN, login, OTP or receptionist QR action.
4. Single, couple and family occupants use the same room guide.
5. Stay extension keeps access active through the new valid checkout time.
6. Room move makes the old room resolver inactive and allows the destination room QR to resolve the moved stay.
7. Checkout, stay expiry or emergency revoke blocks access.
8. The next stay reuses the same printed room QR and resolves the new current stay.

The public room QR contains no guest name, phone number, guest-session identifier or raw signed stay token.

### Exceptional controls

Authorized hotel staff may:

- rotate/restore the signed access token for the active stay;
- emergency-revoke active guest access;
- regenerate a permanently compromised room QR, which invalidates the old physical QR and requires the printed card/standee to be replaced.

The legacy PIN resolver remains in the backend as a fallback contract but is removed from the normal hotel/guest workflow.

## Launch UI finalization

- Navigation reorganized into Front Desk, Guest Experience, Hotel Operations, Management and Property Settings.
- Internal `Day`, `REV`, `V1.1`, `NEW` and pilot-oriented customer labels removed from main operational screens.
- Activation Score uses `Property ready` language.
- QR Guides becomes a simple permanent-room-QR operational screen; temporary signed access stays under the hood.
- Check-in success explicitly confirms automatic Guest Guide activation.
- Subscription & Billing is manual/offline-first; AutoPay is shown as Upcoming.
- New hotel acquisition starts the 14-day trial; paid activation is handled manually during launch.
- Guest Communications keeps consent, suppression and manual WhatsApp contact but marks automated campaigns Upcoming.
- Provider activation controls are hidden from normal hotel UX.
- Support wording avoids unsupported staffed 24x7/SLA promises.
- Application portal is `noindex` and repository metadata/README identify StayQR rather than a starter project.

## Acceptance gate before staging release

The local apply script must pass:

- REV6 multi-occupant regression;
- REV7 companion directory regression;
- REV8 WhatsApp webhook security regression;
- Batch 3 security acceptance;
- Permanent QR final source acceptance;
- Commercial-ready launch validation;
- manual billing validation;
- Final Product Freeze REV9 validation;
- ESLint;
- production build;
- `git diff --check`.

## Staging acceptance after Migration 115

Migration 115 acceptance must pass 12/12 before the staging frontend is deployed.

Browser acceptance must cover in one consolidated session:

1. vacant room QR shows inactive/general state;
2. single guest check-in auto-activates the permanent room QR;
3. couple/family stay uses the same room QR;
4. multiple guest phones can open the guide;
5. extension preserves access to the updated checkout time;
6. room move invalidates the source room and activates destination room QR;
7. early checkout immediately blocks the old stay;
8. scheduled expiry blocks access after checkout time;
9. next guest reuses the same permanent room QR;
10. emergency revoke blocks access;
11. restore/rotate works without replacing the permanent QR;
12. permanent QR regeneration invalidates the old QR and yields a replacement code.

## Production boundary

This package does not deploy production, apply Migration 115, deploy Netlify, change provider secrets, enable Meta/Cashfree/UIDAI provider flags, or destructively clean production data.

Production rollout occurs only after the staging gate and browser acceptance are complete.
