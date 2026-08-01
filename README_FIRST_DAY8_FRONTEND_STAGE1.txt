StayQR v1.0 — Day 8 Frontend Stage 1
Hotel Registration, Onboarding and Configuration Wizard

BACKEND STATUS BEFORE INSTALLATION
- Migration 017: 12/12 passed
- Migration 018: 18/18 passed
- Audit 044 REV3: 24/24 passed
- Migration 019: 24/24 passed
- Audit 046: 28/28 passed
- Audit 047 cleanup/readiness: 18/18 passed

IMPORTANT
- Do not rerun Migrations 017, 018 or 019.
- This ZIP is a complete Frontend replacement, not a partial patch.
- Keep your current Day 7 backup until the Day 8 browser checkpoint passes.
- The ZIP intentionally does not include your private .env file.

WINDOWS INSTALLATION
1. Stop the current Vite server with Ctrl+C.
2. Go to:
   C:\Users\HP\Documents\StayQR
3. Rename the current folder:
   Frontend
   to:
   Frontend_Day7_Locked_Backup
4. Extract this ZIP inside:
   C:\Users\HP\Documents\StayQR
5. Confirm the new active path is:
   C:\Users\HP\Documents\StayQR\Frontend
6. Copy only the existing .env file from the backup folder into the new Frontend folder.
7. Open Terminal in the new Frontend folder and run:

   npm install
   npm run check
   npm run dev

EXPECTED SOURCE CHECKS
- Relative imports: 150/150
- Day 7 security source gate: 15/15
- Day 8 onboarding source gate: 13/13
- Local QR engine: 5/5
- ESLint: 0 errors; existing React Hook warnings may remain
- Vite production build should complete after npm install on Windows

DAY 8 FRONTEND FEATURES
- Hotel-owner account registration and email verification flow
- Automatic onboarding entry for authenticated users without hotel access
- Atomic hotel, owner, settings, invoice sequence and trial bootstrap
- User-scoped idempotency key for safe retry/resume
- Hotel details, timezone, currency, tax and policies configuration
- Floor, room-type and rate-plan configuration through secure RPC
- CSV room import through validated bulk-room RPC
- Editable normalized amenities and request categories
- Normalized menu categories and starter menu item setup
- Server-computed operational-readiness checklist
- Platform Admin secure hotel onboarding entry point
- Hotel Setup navigation for authorized hotel owners/managers
- No fixed hotel UUID and no browser service-role usage

FIRST BROWSER CHECKPOINT
After npm run dev:
1. Sign in with the existing Platform Admin account.
2. Open Super Admin.
3. Click Secure Hotel Onboarding.
4. Confirm Hotel Setup opens without a console or page error.
5. Do not create a real test hotel yet. Send a screenshot of the Hotel Setup page first.
