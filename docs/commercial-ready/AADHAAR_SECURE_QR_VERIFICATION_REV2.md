# StayQR Aadhaar Secure QR Verification REV2

## Decision
StayQR must not label an Aadhaar image as verified from OCR or browser QR detection. UIDAI's current public guidance states that Secure QR is digitally signed and is to be read using UIDAI's official Aadhaar/mAadhaar/Windows reader. REV2 therefore uses an official-reader-assisted verification boundary and keeps the existing signed Offline XML path.

## Completed behavior
- Pending Aadhaar remains unverified after upload/OCR alone.
- The official UIDAI reader workflow is surfaced directly in Guest 360 and does not use Aadhaar OTP.
- Verification is bound to the exact saved Aadhaar document and active hotel/guest context.
- Staff must confirm the official UIDAI reader verified the digital signature.
- Aadhaar last four and name shown by the official reader are mandatory.
- Known last-four/name/DOB mismatches against saved extraction metadata block verification.
- Full Aadhaar numbers, raw QR payloads, biometrics and raw OCR text are not persisted.
- Successful evidence marks only the linked Aadhaar document verified and applies safe verified fields to Guest 360.
- Duplicate Secure QR verification for the same already-verified document is rejected.
- Activity/consent evidence is retained.

## Future automated path
UIDAI's 2026 Aadhaar App/OVSE framework supports Aadhaar Verifiable Credentials shared with a registered OVSE through a UIDAI callback. StayQR can add that machine-to-machine callback after StayQR/the applicable verifying hotel has the required OVSE registration and UIDAI-issued technical contract. This REV2 does not invent that callback contract or claim registration.
