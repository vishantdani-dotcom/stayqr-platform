# StayQR Final Launch Corrections REV10

Scope locked after REV9 staging acceptance. This release fixes only launch blockers found in real browser testing.

## 1. Aadhaar / ID OCR hardening
- Rejects label/noise words such as `Verified` as guest names.
- Rejects UIDAI/disclaimer text as addresses.
- Validates dates and only accepts a plausible address block.
- Adds extraction quality scoring and a `review_required` state instead of confidently filling bad data.
- If both staging OCR providers are configured, a weak result automatically retries the alternate provider and keeps the safer result.
- Raw OCR text/provider responses remain non-persistent and are not returned to the browser.

## 2. Stay-owned billing and checkout
Financial ownership is now `guest_session_id / folio_id`, not the guest's current room.
A room move can no longer detach food, service, manual, room-charge or payment evidence from the final bill.
Invoice line snapshots are created from authoritative posted folio items.

## 3. Reception UX
- `Folio & Settlement` is presented as **Guest Bills**.
- Final modal is **Final Bill & Checkout**.
- Clear Room / Food & Dining / Hotel Services / Other Charges breakdown.
- CTA is `Complete Checkout` at zero balance or `Collect ₹X & Checkout` when a balance remains.
- Final checkout receives additional phone-width polish.

## Hold boundary
Meta WhatsApp automation and Cashfree/AutoPay remain on hold/upcoming. REV10 does not configure provider secrets or flags.

## Release gate
1. Local regressions + REV10 validation + lint + build.
2. Migration 116 + 14/14 staging acceptance.
3. Deploy only `id-document-ocr` Edge Function to staging.
4. Deploy frontend to the existing StayQR staging site.
5. Browser acceptance: real Aadhaar, moved-room food charge, Guest Bills/checkout, mobile.
6. Production remains untouched until explicit approval.
