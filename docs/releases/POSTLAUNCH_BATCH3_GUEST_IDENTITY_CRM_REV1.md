# StayQR v1.1 Post-Launch Batch 3 / Batch C — Guest Identity, CRM, Export & Communications REV1

## Scope
Items 6 and 7 from the approved post-launch plan.

### Item 6 — Guest identity / KYC
- Camera-based document capture using rear-facing camera.
- Front/back document grouping.
- Crop, rotate and JPEG compression controls.
- Blur/glare/lighting quality assessment and manual-review flagging.
- Private `guest-documents` storage only.
- Explicit KYC capture consent.
- Retention metadata, legal hold and retention-purge queue.
- Immutable KYC access audit.
- Masked document metadata only.
- UIDAI Paperless Offline XML digital-signature verification.
- UIDAI Secure QR official-reader evidence workflow.
- No biometric collection or matching.
- Aadhaar photograph alone is never treated as Aadhaar authentication.
- Raw Aadhaar XML/share code/full Aadhaar number are not persisted.

### Item 7 — Guest 360 / export / communications
- Guest 360 directory and stay history.
- Filters for dates, stay state, nationality, room, repeat guest, KYC and WhatsApp consent.
- Controlled hotel-scoped CSV export with explicit reason and selected columns.
- CSV formula/injection protection.
- Normal exports exclude document files and full Aadhaar/identity numbers.
- Privileged KYC-summary export remains separately controlled/audited.
- Transactional/marketing consent ledger.
- Opt-out/suppression ledger.
- Hotel-owned WhatsApp provider profile and provider-approved template metadata.
- Campaign/recipient/delivery evidence and idempotent retry controls.
- Meta webhook HMAC verification.
- Manual one-recipient click-to-chat fallback.
- Automated Meta Cloud sending remains feature-flagged until provider credentials/readiness exist.

## Security
- Existing multi-hotel RLS architecture is preserved.
- Generic `guests.view` access is removed from sensitive KYC rows/storage.
- KYC writes are RPC/service controlled.
- Signed KYC document URLs expire after 60 seconds and access is audited first.
- Service-role-only provider/UIDAI reconciliation functions stay unavailable to normal authenticated users.

## Acceptance already completed in source workspace
- Batch 3 source: 69/69 PASS
- Batch 3 security/RLS: 29/29 PASS
- Batch B source regression: 41/41 PASS
- Batch B final regression: 54/54 PASS
- Batch B blocker regression: 8/8 PASS
- Batch B audited View-as-Hotel regression: 14/14 PASS
- Responsive platform: 77/77 PASS
- Mobile REV2: 16/16 PASS
- Relative frontend imports: 249 resolved

Lint/build must run in the user's authoritative local repository as part of RUN_FIRST_BATCH3_REV1.ps1.

## Staging
Use:
`supabase/staging/202608210092_postlaunch_batch3_STAGING_APPLY_AND_ACCEPT.sql`

Expected:
`POSTLAUNCH_BATCH3_DATABASE_ACCEPTANCE: PASS (36/36)`

## Edge Functions
Deploy to StayQR Staging only after the database gate passes:
- verify-aadhaar-offline
- whatsapp-send
- whatsapp-status-webhook
- purge-guest-retention

Production remains untouched until consolidated browser/mobile acceptance is complete.
