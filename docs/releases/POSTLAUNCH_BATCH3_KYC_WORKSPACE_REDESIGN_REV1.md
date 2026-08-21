# StayQR Batch 3 — KYC Workspace Redesign REV1

## Purpose
Clean up the Guest 360 identity/KYC workspace after functional scanner acceptance. This is a UI/UX-only patch: no database schema, RLS, storage policy, consent model, UIDAI verification logic, WhatsApp logic, retention logic or production configuration is changed.

## UX changes
- Introduces a clear 3-step KYC flow: Consent → Capture → Review.
- Makes consent the first protected action and keeps Aadhaar verification methods progressively disclosed.
- Groups KYC capture into Document details, Dates & retention, and Capture/upload.
- Keeps technical request IDs behind a collapsible details control.
- Shows selected-file status and capture/quality summary before upload.
- Makes existing KYC cards easier to scan and hides secondary metadata behind an expandable panel.
- Keeps all reviewer actions available: private view, verify, reject, expire/reset and delete.
- Collapses verification evidence history until requested.
- Reworks desktop/tablet/mobile spacing, card density, button sizing and one-column mobile layouts.

## Security / privacy invariants retained
- Private `guest-documents` bucket.
- 60-second signed document view URL.
- Document access auditing.
- Masked identity number only.
- Consent gating for protected KYC/Aadhaar actions.
- UIDAI Paperless Offline XML server-side signature verification.
- UIDAI Secure QR evidence only after official-reader verification.
- No raw Aadhaar XML/QR payload, full Aadhaar number, OCR, biometric matching or face recognition.

## Acceptance
`validate-postlaunch-batch3.mjs` now includes UI contracts for the redesigned KYC workflow. Source acceptance is expected to report 87/87 on the Batch 3 package baseline with the advanced scanner applied.
