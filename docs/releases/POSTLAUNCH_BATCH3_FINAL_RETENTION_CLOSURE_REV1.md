# StayQR Post-Launch Batch 3 — Final Retention Closure REV1

## Browser evidence before patch
Batch 3 browser acceptance confirmed:

- Aadhaar Offline XML unsigned rejection: PASS.
- UIDAI Secure QR evidence: PASS.
- Secure QR reference encoding: PASS.
- Private KYC camera/file workflow: PASS.
- Guest 360 directory/history: PASS.
- Controlled CSV export: PASS.
- Private signed-file access: PASS.
- WhatsApp transactional consent: PASS.
- WhatsApp suppression/unsuppression: PASS.
- WhatsApp consent revocation: PASS.
- Manual campaign preparation: PASS (1 eligible, 0 suppressed).
- Delivery evidence persisted: PASS (`ready`).
- Invalid/missing-phone recipient remains blocked: PASS.

The only remaining browser defect is that saved KYC records display a retention
basis but no retention deadline.

## Fix
Migration 093:

1. Backfills existing null deadlines to `created_at + 365 days`.
2. Normalizes blank/missing bases to `hotel_policy`.
3. Adds an authoritative trigger so future direct/RPC inserts cannot omit
   retention metadata.
4. Makes `retention_until` and `retention_basis` mandatory after backfill.
5. Preserves RLS and the existing retention index.
6. Includes an 8/8 SQL acceptance gate.

Run against StayQR Staging first. Production remains untouched until browser
acceptance shows the deadline correctly.
