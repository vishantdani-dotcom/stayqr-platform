# StayQR Batch 3 — Secure QR Evidence Encoding Fix REV1

## Symptom
The verified Secure QR evidence card displayed mojibake before the last four
reference digits.

## Fix
- UI now derives the visible mask from the permitted last four digits and renders
  an ASCII-only `****1234` form.
- Existing staging evidence is normalized at display time, so no destructive
  evidence rewrite is required.
- Future Aadhaar Offline XML evidence returned by the staging Edge Function also
  uses an ASCII-only mask.
- No Aadhaar number, QR payload or biometric data is added or exposed.
- No production deployment is performed.

This is deliberately a display/data-format hardening patch only.
