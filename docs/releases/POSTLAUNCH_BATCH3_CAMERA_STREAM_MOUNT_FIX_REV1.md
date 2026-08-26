# StayQR Batch 3 Camera Stream Mount Fix REV1

## Symptom
After camera permission was correctly allowed, the scanner modal opened without
`Permission denied`, Chrome indicated that the camera was active, but the live
preview remained black and `Capture document` stayed disabled.

## Root cause
`DocumentScanner.jsx` acquired the MediaStream and then attempted to attach it
to the `<video>` element inside `setTimeout(..., 0)`. React had not necessarily
mounted the modal/video element by the time that callback executed. When
`videoRef.current` was still null, the callback returned silently and the stream
was never attached.

## Fix
- MediaStream lifecycle remains imperative in `streamRef`.
- A small `streamVersion` state signals that a new stream is available.
- A React effect runs only after the scanner/video has mounted and attaches the
  current MediaStream to the `<video>`.
- Camera readiness is set only after playback and usable video dimensions.
- Removed the mount-racy `setTimeout(0)` attachment.
- Added Batch 3 source regression coverage for the post-mount attachment path.

No database, RLS, KYC schema, UIDAI, Guest 360, WhatsApp or Production changes.
