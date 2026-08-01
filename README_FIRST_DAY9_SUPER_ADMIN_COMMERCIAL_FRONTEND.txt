STAYQR V1.0 — DAY 9 SUPER ADMIN COMMERCIAL FRONTEND
====================================================

WHAT TO DO
1. Back up your current Frontend folder.
2. Replace it with the Frontend folder supplied in this ZIP.
3. Copy your existing .env file into the new Frontend folder.
4. Open a terminal inside Frontend.
5. Run:
     npm install
     npm run check
     npm run dev
6. Sign in as Platform Admin and open Super Admin from the sidebar.

IMPORTANT
- No SQL migration is included or required by this frontend package.
- The accepted Day 9 migrations and Cashfree Edge Functions must already exist.
- Cashfree must remain in TEST mode for this acceptance stage.
- Never put SUPABASE_SERVICE_ROLE_KEY, CASHFREE_CLIENT_SECRET or other provider secrets in the browser/Vite environment.

NEW CONTROL-CENTRE SECTIONS
- Overview and MRR
- Hotels and subscription lifecycle
- Plans and capacity limits
- Cashfree payment-link ledger
- Support tickets and safe support access
- Subscription events and webhook health
- Platform announcements

VALIDATION COMMAND
  npm run security:day9

FULL GUIDE
  docs/day-09-super-admin-commercial-frontend.md
