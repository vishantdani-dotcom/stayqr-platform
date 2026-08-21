# StayQR Batch 3 — Aadhaar Offline XML Feedback Fix REV1

## Acceptance failure observed
Selecting a synthetic XML and clicking **Verify offline XML** produced no visible
rejection message.

## Root causes
1. Frontend XML-shape rejection was routed only through the global notice
   mechanism, which can be visually obscured while the Guest Profile modal is open.
2. Supabase `FunctionsHttpError` response JSON was discarded, hiding the precise
   Edge Function rejection reason.
3. The original negative fixture was not UIDAI-shaped enough to reach the Edge
   Function signature-verification path.
4. The Edge Function fetched the UIDAI certificate before rejecting XML that had
   no `<Signature>`, creating an unnecessary external dependency for an obvious
   invalid document.

## Fix
- Adds persistent inline status/error feedback directly inside the Offline XML card.
- Parses Supabase Edge Function error response JSON and surfaces `error`.
- Rejects missing XML Digital Signature before certificate download.
- Adds a structurally UIDAI-like but deliberately unsigned synthetic fixture.
- Preserves consent, RLS, no-biometric-storage wording and raw-XML non-retention.

Production is not targeted by this patch.
