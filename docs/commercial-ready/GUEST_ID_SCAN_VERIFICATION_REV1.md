# StayQR Guest ID Scan & Verification REV1

Prepared: 4 September 2026

## Scope completed

This batch completes the provider-independent guest ID capture and verification workflow requested for StayQR:

- mobile camera or private file upload remains the single capture workflow;
- local browser OCR is attempted for JPEG/PNG when the browser exposes the native TextDetector API;
- safe extracted fields are shown to staff and can prefill masked document metadata;
- Aadhaar-like numbers are masked before any preview/storage path;
- QR detection uses the native BarcodeDetector API where available;
- raw OCR text is not persisted;
- raw QR payload is never persisted; only a SHA-256 digest may be retained as detection evidence;
- Aadhaar OCR/visual review can never mark the document verified;
- Aadhaar verification is bound to the exact saved Aadhaar document and requires UIDAI-signed offline evidence (official Secure QR Reader confirmation or verified Offline XML);
- linked Aadhaar verification marks the exact document verified and applies only verified/safe identity fields to Guest 360;
- non-Aadhaar documents can be reviewed by an authorised hotel manager and safe extracted fields can then be applied to Guest 360;
- all protected actions retain hotel isolation, permission checks, consent requirements, private storage and activity auditing;
- the online Aadhaar OTP provider code remains disabled and is not exposed in the hotel Guest 360 workflow.

## Important verification rule

OCR is extraction, not authentication. A photo/PDF that OCR can read is not automatically genuine. Aadhaar reaches `verified` only after linked UIDAI digital-signature evidence. QR presence/detection alone is also not treated as verification.

## Browser capability boundary

The batch deliberately does not weaken StayQR's CSP or load a third-party OCR library from a public CDN. Native OCR/QR feature detection is used where the browser supports it; otherwise the workflow safely falls back to manual review while retaining all verification protections. A future self-hosted OCR engine or approved OCR provider can be plugged into `src/lib/idDocumentIntelligence.js` without changing the database trust boundary.

## New/changed implementation

- `src/lib/idDocumentIntelligence.js`
- `src/lib/guestCompliance.js`
- `src/pages/guests/GuestDirectory.jsx`
- `src/pages/guests/GuestDirectory.css`
- `src/components/guests/GuestIdentityCompliance.jsx`
- `src/components/guests/GuestIdentityCompliance.css`
- `supabase/migrations/202609040109_guest_id_scan_extraction_and_verified_profile_apply_REV1.sql`
- `scripts/validate-id-scan-rev1.mjs`

## Validation performed in isolated source workspace

- ID Scan REV1 source acceptance: 21/21 PASS.
- ESLint complete repository: 0 errors, 7 inherited warnings.
- Commercial-Ready source validation: 74/74 PASS.
- Pilot Manual Billing validation: 42/42 PASS.
- Provider boundary probes: UIDAI 10/10 safety cases PASS; the two pre-existing WhatsApp webhook failures remain outside this ID-scan batch.
- `git diff --check`: PASS.
- Linux build was not executable from the uploaded Windows `node_modules` because Rolldown's Linux native optional binding is absent. The supplied Windows apply script runs the normal project build on the user's Windows repository before any staging migration/deploy action.

## Deployment boundary

This package does **not** apply Migration 109, deploy Edge Functions, enable UIDAI online authentication, contact UIDAI, or touch production. Migration 109 must first pass the Windows repository validation/build and then be applied to staging only under the existing rollout controls.
