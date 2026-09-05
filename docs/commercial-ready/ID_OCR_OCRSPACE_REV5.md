# StayQR ID OCR Provider Switch REV5

This revision adds OCR.Space as the staging/pilot OCR provider while preserving Google Vision as an optional fallback. The active front-desk flow remains server-side: browser -> StayQR Supabase Edge Function -> OCR provider -> StayQR safe parser -> structured fields.

## Staging secrets

- `ID_OCR_ENABLED=true`
- `ID_OCR_PROVIDER=ocr_space`
- `OCR_SPACE_API_KEY=<server-side key>`

`GOOGLE_CLOUD_VISION_API_KEY` may remain configured but is unused while `ID_OCR_PROVIDER=ocr_space`.

The free OCR.Space tier has a 1 MB input limit, so this staging revision rejects larger images before calling the provider. Production can later move to OCR.Space PRO or another provider without changing the front-end workflow.
