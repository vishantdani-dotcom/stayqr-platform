# StayQR Post-Launch Batch 1 Release Runbook

Scope: items 1, 2, 9, 10, 12 and 15 only — acquisition, Cashfree checkout, search, branding, cancellation wording/workflow, and responsive/contrast correction.

Explicit exclusion: do not change or advertise platform support as 24×7 in this batch.

## Release contract

- Paid signup: plan and monthly/yearly choice → verified owner account → Cashfree Payment Link → signed webhook → atomic hotel bootstrap and paid subscription → hotel setup.
- Trial signup: plan choice → verified owner account → one 14-day trial for an account without existing hotel access → hotel setup. No payment is collected.
- The browser never selects the charge amount. The Edge Function resolves the active public plan and price from PostgreSQL.
- A paid hotel is not created before the signed Cashfree `PAID` webhook is validated.
- Payment retries are idempotent. Failed/expired/cancelled checkouts require a new request; partial payment is stopped for support review.
- Search is tenant-scoped and permission-aware. Guest phone evidence is masked to the final four digits.
- The locked v1.0 tag and Day 20 migration remain byte-identical.

## Gate 0 — local safety and branch

From `C:\StayQR_MASTER\01_SOURCE\stayqr-platform`:

```powershell
git status --short
git rev-parse HEAD
git switch -c feature/postlaunch-batch1-market-ready
```

Expected:

- `git status --short`: no output.
- HEAD: `d921c1f633a5d609cebd3b4c65884e891dd5f956` before applying this batch.
- New branch: `feature/postlaunch-batch1-market-ready`.

Apply the supplied changed-file patch folder over the repository. Do not copy `.git`, `node_modules` or `dist` from another machine.

## Gate 1 — dependency-backed validation

```powershell
npm ci
npm run check
git diff --check
npm run test:postlaunch-batch1
```

Exact acceptance:

- ESLint: `0 errors`; the accepted inherited baseline is `7 warnings`.
- Relative imports: PASS.
- Inherited Day 7–15 gates: PASS.
- Local QR: `5/5 PASS`.
- Batch 1 source acceptance: `POSTLAUNCH_BATCH1_SOURCE_ACCEPTANCE: PASS (43/43)`.
- Vite production build: exit code `0` and `dist` created.
- `git diff --check`: no output.

Stop on any error. Do not deploy a build that merely renders while a source/security gate fails.

## Gate 2 — staging database and Edge Functions

Target staging project only: `eecinuhvkxlbdvyuazal`.

```powershell
supabase link --project-ref eecinuhvkxlbdvyuazal
supabase migration list
supabase db push
supabase functions deploy cashfree-create-self-service-checkout --no-verify-jwt
supabase functions deploy cashfree-webhook --no-verify-jwt
```

Expected:

- New migration applied: `202608180083_postlaunch_batch1_acquisition_search.sql`.
- Locked migration `202608180082_day20f_invoice_number_allocator_overflow_hardening_REV1.sql` remains applied and unchanged.
- Both Edge deployments exit `0`.

Required staging secrets are the already-approved Cashfree/Supabase values used by the existing Cashfree functions, plus `STAYQR_APP_URL` set to the staging app origin. Never print them. `CASHFREE_MODE=test` must resolve to the Cashfree sandbox API host.

In Supabase Auth URL configuration, allow the staging equivalents of:

- `/checkout`
- `/checkout/success`
- `/checkout/recover`
- `/setup`

Run `supabase/audit/202608180084_postlaunch_batch1_ACCEPTANCE.sql` in staging SQL Editor.

Exact terminal output:

`POSTLAUNCH_BATCH1_DATABASE_ACCEPTANCE: PASS (16/16)`

## Gate 3 — staging application acceptance

Deploy the branch to the Netlify SaaS project `stayqr-day18-preview`. Do not update the marketing project yet.

Test at 1440px, 1024px, 768px, 393px and 390px widths:

1. `/signup?plan=growth&billing=monthly&mode=paid` opens registration, preserves the selection after email verification/login, and shows the Growth monthly server price.
2. Change to yearly; the summary changes to the annual server price.
3. Paid checkout opens Cashfree sandbox. Before a signed `PAID` webhook, no hotel/staff/subscription is created. After it, `/checkout/success` reaches `completed` and `/setup` opens the same account’s hotel.
4. Re-deliver the same signed webhook. Expected: idempotent response; no duplicate hotel, subscription, or payment ledger row.
5. Start the trial path with a new account. Expected: 14-day trial, no Cashfree call, `/setup` opens.
6. Attempt another self-service bootstrap from an account with active hotel access. Expected: denied.
7. Click the navbar search icon and press `Ctrl+K`. Search by room, guest, reservation, service request and invoice. Expected: only authorised active-hotel results; reservation result opens its record.
8. Sidebar displays the official StayQR logo with no generic “StayQR Admin” lockup.
9. Guest guide active request button reads `Cancel`; click, dismiss confirmation, then confirm. Expected: dismiss does nothing; confirm changes the state to `Cancelled` only after the RPC succeeds.
10. Operations Centre headings and text remain readable; no dark-on-dark title, clipped card, page-wide horizontal scroll or unusable mobile navigation.

Record the Cashfree sandbox link ID, acquisition intent ID, webhook event ID, hotel ID and subscription ID. Do not record secrets or raw identity documents.

## Gate 4 — production promotion

Production targets:

- Supabase: `rbyirbovbkguzvwijyaj`
- SaaS Netlify: `stayqr-day18-preview` / `app.stayqr.in`
- Marketing Netlify Drop: `stayqr` / `stayqr.in`

Promote only after every staging gate passes. Apply in this order:

1. Production database migration.
2. Production `cashfree-create-self-service-checkout` and `cashfree-webhook` functions.
3. SaaS app build.
4. SaaS runtime acceptance.
5. Marketing `DEPLOY_stayqr.in` folder last, so public CTAs never point to an undeployed checkout.
6. Database acceptance SQL.
7. Public smoke:

```powershell
npm run smoke:postlaunch-batch1
```

Exact terminal output after deployment:

`POSTLAUNCH_BATCH1_LIVE_SMOKE: PASS (12/12)`

Then perform one controlled paid Cashfree production transaction and the browser checks from Gate 3. A public HTTP smoke cannot prove webhook provisioning or tenant isolation.

## Rollback

If a P0/P1 appears:

1. Remove/disable the new acquisition links in marketing first.
2. Roll back the SaaS Netlify deploy to the immediately preceding accepted deploy.
3. Redeploy the preceding `cashfree-webhook` function if the regression is in webhook handling; leave the new checkout function unreachable.
4. Do not move `stayqr-v1.0-production` and do not blindly reverse migration 083. It is additive and includes acquisition evidence; preserve rows for incident review.
5. Follow `docs/launch/DAY20E4_INCIDENT_ROLLBACK_RUNBOOK.md` and capture event/intent identifiers without secrets.

Production is accepted only when source, database, app runtime, Cashfree lifecycle, responsive widths and public smoke all pass.
