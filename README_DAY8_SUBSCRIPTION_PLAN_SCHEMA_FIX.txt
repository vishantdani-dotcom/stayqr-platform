StayQR Day 8 — Subscription Plan Schema Fix

Problem fixed:
The onboarding frontend queried subscription_plans.max_staff, but the locked
production subscription_plans table has:
id, plan_name, price_monthly, max_rooms, features, status, created_at.

Files included:
- src/lib/onboarding.js
- scripts/day8-onboarding-source-check.mjs

Installation target:
C:\Users\HP\Documents\StayQR\Frontend

Extract this ZIP directly into the active Frontend folder and allow Windows to
replace both existing files. Do not extract it into the StayQR parent folder.

After replacement:
1. npm run check
2. npm run dev
3. Refresh the verified owner's onboarding page.

Expected Day 8 source gate:
14/14 passed.
