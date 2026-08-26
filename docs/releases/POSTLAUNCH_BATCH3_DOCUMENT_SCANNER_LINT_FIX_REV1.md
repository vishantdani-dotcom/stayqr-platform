# StayQR Batch 3 Document Scanner Lint Fix REV1

Fixes the React `react-hooks/refs` lint error in DocumentScanner.jsx.

Cause:
The Capture button read `streamRef.current` during render.

Fix:
A `cameraReady` state now represents camera readiness for rendering.
The MediaStream remains stored in a ref for imperative lifecycle handling.

Scope:
- No database changes.
- No RLS changes.
- No KYC model changes.
- No Guest 360 changes.
- No WhatsApp changes.
- No Production changes.

After applying this overlay, rerun the existing consolidated Batch 3 local acceptance.
