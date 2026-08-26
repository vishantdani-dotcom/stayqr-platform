# StayQR Batch 3 — Aadhaar XML Staging CORS Fix REV1

## Browser symptom
A UIDAI-shaped synthetic XML reached the network path, but the UI reported:

`Failed to send a request to the Edge Function`

## Cause addressed
Batch 3 is being tested from a Netlify branch alias:
`preview-batch3-crm--stayqr-day18-preview.netlify.app`.

The Aadhaar Edge Function previously allowed only exact origins from
`STAYQR_APP_URL` / `STAYQR_APP_URLS`. A newer branch alias therefore fails
browser CORS before its JSON rejection can reach the UI.

## Fix
- Adds `STAYQR_PREVIEW_ORIGIN_SUFFIXES`.
- Staging is configured with the exact Netlify site suffix
  `stayqr-day18-preview.netlify.app`.
- HTTPS branch aliases ending in
  `--stayqr-day18-preview.netlify.app` are allowed.
- Arbitrary `*.netlify.app` origins are NOT allowed.
- Existing exact-origin allowlist remains supported.
- Adds `x-supabase-api-version` to allowed request headers.
- Disallowed origins are no longer implicitly echoed when the exact-origin
  configuration is absent.
- Deployment script performs an OPTIONS preflight and fails unless
  `Access-Control-Allow-Origin` equals the Batch 3 preview origin.

Production is untouched.
