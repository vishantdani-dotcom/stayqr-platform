# StayQR ID OCR Backend REV4

## Decision
Front-desk OCR moves off the browser and into a tenant-authorized Supabase Edge Function. The first provider adapter is Google Cloud Vision `DOCUMENT_TEXT_DETECTION`.

The active flow is:

`Scan/Upload ID -> lightweight client image resize -> authenticated StayQR Edge Function -> Google Cloud Vision OCR -> server-side safe parser -> masked structured JSON -> check-in form auto-fill`

## Privacy / safety boundary
- Raw OCR text is never written to StayQR tables or storage by this function.
- Raw OCR text is not returned to the browser.
- Full Aadhaar numbers are never returned; Aadhaar is masked to `XXXX XXXX 1234`.
- The provider API key exists only as a Supabase Edge Function secret.
- Calls require an authenticated StayQR user and hotel-scoped `checkin.manage` or `guests.manage` permission.
- Provider calls are bounded by a 10 second timeout; the browser gives up after 15 seconds and falls back to manual entry.
- This is OCR/data capture, not UIDAI authentication or government verification.

## Staging secrets required before deployment
- `ID_OCR_ENABLED=true`
- `ID_OCR_PROVIDER=google_vision`
- `GOOGLE_CLOUD_VISION_API_KEY=<restricted key>`

Do not expose the key as a Vite variable or database value.

## Provider setup expectations
Create a Google Cloud project, enable Cloud Vision API, enable required billing for the project, create an API key, restrict the key to the Cloud Vision API, and store it only as a Supabase Edge Function secret.

## Acceptance target
The supplied demo Aadhaar text must map to:
- Aadhaar
- Pardeep Yadav
- 1999-03-18
- male
- India
- XXXX XXXX 2806

Provider-backed acceptance must use an approved non-sensitive/synthetic test image where possible. Do not paste API keys or identity numbers into chat.
