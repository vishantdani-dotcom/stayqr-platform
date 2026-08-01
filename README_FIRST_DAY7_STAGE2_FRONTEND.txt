STAYQR v1.0 — DAY 7 STAGE 2 FRONTEND SECURITY INTEGRATION
===========================================================

DATABASE CHECKPOINT
- Migration 014 applied successfully.
- Audit 038 passed 24/24.
- Diagnostic 039 REV2 passed 10/10.

WHAT THIS PACKAGE ADDS
- Local browser-side QR generation; signed tokens are not sent to any QR website.
- Separate Guest Guide and Food Menu QR codes.
- SVG QR download for high-quality printing.
- Correct active/revoked/expired/not-issued guest-access states.
- Explicit activation after revocation; refreshing cannot silently reactivate access.
- Safe malformed URL handling and strict hotel-slug + signed-token validation.
- Day 7 frontend security source gate (12 checks).
- Local QR engine test (5 checks).
- Migration 014 and final audit/diagnostic files included.

WINDOWS INSTALL / VALIDATION
1. Keep a backup of your current Frontend folder.
2. Extract this package and open the included Frontend folder in VS Code.
3. Copy your existing real .env into the new Frontend root. Do not share it.
4. In the VS Code terminal run:

   npm install
   npm run check
   npm run dev

EXPECTED npm run check RESULT
- ESLint: 0 errors. Existing React Hook warnings may still be shown.
- Relative frontend import graph: all 141 imports resolved.
- Day 7 frontend security source gate: 12/12 passed.
- Local QR engine test: 5/5 passed.
- Vite production build: completed successfully.

FIRST BROWSER CHECK
- Sign in as an authorized hotel owner/manager.
- Open QR Guides / Secure Guest Access.
- For an active checked-in stay, two locally rendered QR codes must appear:
  Guest guide and Food menu.
- Do not print or distribute any QR until the next browser security acceptance gate is completed.
