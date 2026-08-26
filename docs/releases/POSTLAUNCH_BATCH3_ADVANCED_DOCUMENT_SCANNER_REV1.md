# StayQR Batch 3 Advanced Document Scanner REV1

## Why
Browser scanner acceptance passed functionally, but captured ID detail was softer than desired.

## Root cause
The previous scanner:
- limited captured frames to roughly 1600 px width;
- encoded JPEG at 0.86 quality;
- normally saved a frame from the live video stream rather than a camera still.

## Upgrade
1. Prefer `ImageCapture.takePhoto()` to obtain a full-resolution still from supported cameras.
2. Preserve captures up to 3200 px on the longest edge.
3. Encode JPEG at 0.94 quality.
4. Request higher-resolution environment-camera streams.
5. Best-effort continuous autofocus where the camera/browser exposes it.
6. Torch toggle and optical/digital camera zoom controls when exposed by browser capabilities.
7. Native mobile camera fallback (`capture=environment`) for devices that can deliver a better still through the OS camera.
8. Record capture method and saved resolution in existing quality flags for audit evidence.
9. Retain manual crop/rotate and lighting/glare/blur quality review.
10. No OCR, face recognition, biometric matching, or Aadhaar extraction is introduced.

Production remains untouched until consolidated Batch 3 browser acceptance is complete.
