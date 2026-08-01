STAYQR v1.0 — DAY 7 STAGE 2 REV3 FRONTEND

Purpose
- Preserve immediate guest-access revocation revalidation from REV2.
- Fix the four ESLint react-hooks/purity errors reported after npm install.
- Replace Date.now() calls used during render with a state-backed clock updated inside effects.
- Preserve the Guest Access Not Available heading layout correction.
- Preserve Migration 015 manual-revocation RPC repair.

Validation completed on the corrected source
- ESLint: 0 errors, 17 existing warnings.
- Relative imports: 141/141 resolved.
- Day 7 frontend security source gate: 15/15 passed.
- Local QR engine: 5/5 passed.

Run
1. Preserve your private .env.
2. Replace the frontend with this folder.
3. Copy the private .env into the new Frontend folder.
4. npm install
5. npm run check
6. npm run dev

Browser acceptance to resume
- Room 103 access is currently revoked in the live database.
- Use “Activate new secure link” to create a fresh token.
- Open the new guest and food links.
- Revoke access from QR Guides.
- Return to each open Incognito tab without manually refreshing.
- The page must revalidate on focus/visibility and switch to unavailable.
