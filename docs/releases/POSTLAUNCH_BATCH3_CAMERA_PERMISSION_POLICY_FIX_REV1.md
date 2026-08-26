# StayQR Batch 3 Camera Permissions-Policy Fix REV1

## Root cause
Netlify's global response header explicitly denied camera access:

`Permissions-Policy: camera=()`

That browser-level response policy overrides Chrome/Windows/site permission choices and causes
`navigator.mediaDevices.getUserMedia()` to fail with `NotAllowedError / Permission denied`
on both desktop and mobile.

## Fix
Allow camera only to the StayQR page's own origin:

`Permissions-Policy: camera=(self), microphone=(), geolocation=(), payment=(), usb=()`

This keeps the Day 18 hardening posture intact:
- camera: same-origin only
- microphone: denied
- geolocation: denied
- payment: denied
- USB: denied

## Regression updates
Updated:
- `scripts/day18-infrastructure-source-check.mjs`
- `scripts/day18-live-deploy-smoke.mjs`

No database, RLS, KYC, Guest 360, consent, WhatsApp or Production configuration changes are included.
