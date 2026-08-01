StayQR v1.0 — Day 10 Private KYC Frontend REV1

Prerequisite
------------
Migration 027 must already be installed and accepted 30/30.

Install
-------
1. Stop the Vite development server with Ctrl+C.
2. Place the patch ZIP in C:\Users\HP\Documents\StayQR.
3. From PowerShell run:

   cd C:\Users\HP\Documents\StayQR
   Expand-Archive -Path .\StayQR_Day10_Private_KYC_Frontend_REV1_PATCH.zip -DestinationPath . -Force

4. Validate:

   cd .\Frontend
   npm run check

5. Start:

   npm run dev

6. Open Guests > Guest Directory & History > Day10 Identity Test Guest > View profile.

Expected KYC interface
----------------------
- Synthetic-file warning
- Document type, masked number, country, issue/expiry dates
- JPEG/PNG/PDF file selector with 15 MB limit
- Stable idempotency request ID
- Private upload followed by register_guest_document RPC
- Pending metadata card
- 60-second signed private-file view
- Verify/reject/expire/reset actions for guests.manage users

Safety
------
Use only a synthetic test file. Never upload a real Aadhaar, passport, PAN card,
visa or other personal identity document during acceptance testing.

Do not modify or check out Rooms 106 or 107 yet.
