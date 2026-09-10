# StayQR REV53 — Final Product Candidate

Status: staging-only final product candidate. Production deployment remains blocked until explicit owner authorization.

## Locked baseline

- REV52 staging acceptance is owner-approved at commit `7cf6b46c26011f7e796f2d8bec2023bd7b930589`.
- Approved notification sound remains the single operational notification sound.
- Role-scoped operational notifications remain enabled.
- Aadhaar OCR runtime acceptance passed with Azure Document Intelligence active through Supabase Edge Function secrets.
- OCR remains extraction only. StayQR does not claim UIDAI/government identity verification from document OCR.
- PAN, passport and driving-licence support remains implemented but individual browser-runtime examples were not owner-tested in REV52 because no additional demo IDs were available.

## Launch provider policy

The following external provider projects are intentionally not launch blockers:

- Cashfree recurring/AutoPay: HOLD. Manual/offline subscription billing remains the launch billing mode.
- Meta/WhatsApp automated campaigns: HOLD. Do not present automated Meta sending as live.
- UIDAI online authentication: HOLD. Do not present Aadhaar OCR as UIDAI authentication.

These are deliberate product-policy holds, not software failures. Provider readiness must continue to fail closed until explicitly activated later.

## REV53 closure item

REV53 improves Staff lifecycle UX so subscription staff-capacity enforcement stays server-authoritative while the hotel receives an actionable message instead of a generic `Staff action failed` response.

No database migration is required. No Edge Function change is required. Production is not touched by the REV53 staging runner.
