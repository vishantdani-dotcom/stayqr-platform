# Pilot UI reliability REV1 — local and staging evidence

Date: 3 September 2026 (Asia/Kolkata).

Status: implemented locally and published to staging. **Not released to production.** Full live Food Orders and Housekeeping workflow acceptance remains pending a staging hotel owner/manager login.

## Scope and deployment

- Branch: `commercial-ready/final-completion`.
- Parent commit: `bdc5ae719992e193edd15cdd784b615591e37bdc`; initial working tree was clean.
- Staging Supabase: `eecinuhvkxlbdvyuazal` only.
- Staging Netlify site: `73c4d1f8-d264-4572-a670-2d4984b0a0a5` (`stayqr-pilot-staging`).
- Preview: https://pilot-manual-billing--stayqr-pilot-staging.netlify.app/
- Deploy ID: `6a986f64448c0758da7bac72`.
- Built release label: `pilot-ui-reliability-20260903-bdc5ae7` (built from the patch working tree).
- Uploaded the prebuilt staging artifact with `--no-build`, explicit staging site ID and preview alias; no `--prod`, GitHub push, production database write or Edge Function deployment.
- Read-only deployment verification confirms `app.stayqr.in` still publishes production deploy `6a97eda73762340b04452b37`, unchanged from before this patch.
- Cashfree configuration was not changed. Staging recurring-provider readiness remains `pending` / `not_configured`.

## Changes

1. Dashboard food revenue includes delivered orders only. Cancelled/open orders still count as orders placed, but contribute no revenue. The calculation retains hotel filtering, uses the hotel's business date and sums currency in cents. The tile now says **Food Revenue Today** and explicitly distinguishes sales from cash collected.
2. Checkout returns the invoice number actually saved by the invoice INSERT/trigger, so its response, checkout evidence and housekeeping notes agree. A guarded migration edits only that RETURNING clause in the current function definition; it preserves newer reconciliation logic, function ownership, grants, SECURITY DEFINER and search-path settings. It does not repair or overwrite historical records.
3. Food order cancellation and housekeeping assignment/cancellation/inspection use one shared in-page dialog instead of native prompts. It provides required reasons, an active-hotel staff selector, cancellation/Escape, focus restoration, duplicate-submit protection and retained input on server rejection. Existing trusted RPCs remain the write path and the current hotel is rechecked before submission.
4. Zero-total checkout wording no longer falsely claims that a complimentary stay was covered by previous payments.

Files: `src/lib/dashboardAnalytics.js`; `src/pages/dashboard/Dashboard.jsx`; `src/components/modals/ActionDialog.jsx` and `.css`; `src/pages/foodorders/FoodOrders.jsx`; `src/pages/housekeeping/Housekeeping.jsx`; `src/pages/guests/Guests.jsx`; `package.json`; `scripts/pilot-ui-reliability.test.mjs`; two files in `scripts/fixtures/`; migration, rollback and staging regression SQL numbered `202609020105`; this report.

## Validation results

| Check | Result |
| --- | --- |
| Exact dependency installation (`npm ci --no-audit --no-fund`) | Pass |
| Commercial-Ready source validation | 74/74 pass |
| Pilot Manual Billing source validation | 42/42 pass |
| Pilot UI regression tests | 8/8 pass; included in `npm run check` |
| ESLint | 0 errors; 7 pre-existing hook-dependency warnings |
| Relative imports | 276 imports pass |
| Day 7 and Day 8 source checks | Pass |
| Day 10–15, Day 17 final, Day 18 frontend/monitoring/infrastructure source checks | Pass |
| QR tests | 5/5 pass |
| Responsive source checks | 77/77 pass |
| Optimized frontend build, configured for staging | Pass; 404 modules |
| Staging artifact isolation | Staging reference present; production database reference and privileged-key markers absent |
| Deployed HTTPS/security headers, immutable asset, SPA deep link | Pass |
| Changed SQL | Executed and regression-tested on staging PostgreSQL |
| Edge Functions | Unchanged; no redeployment or new syntax validation required by this patch |
| Whitespace/diff check | Pass |

The entire legacy `npm run check` is **not green**. Its Day 9 check expects `requiresPaymentRecovery`, which is already absent in parent `bdc5ae7` after Pilot Manual Billing. All three source files that gate reads, and the gate itself, are unchanged by this patch. Running the remaining checks separately also finds a pre-existing missing external marketing file: `C:\StayQR_MASTER\01_SOURCE\marketing\stayqr.in_current.html`. Neither issue was hidden or bypassed; unrelated billing/marketing code was not modified.

## SQL regression: failing before, passing after

`supabase/staging/202609020105_pilot_ui_reliability_TRANSACTIONAL_SMOKE_REV1.sql` uses staging's existing 20E Test Hotel, room 102, and an authenticated owner context. It refuses to run unless the expected hotel and available room exist.

- Before the migration, it reproduced the mismatch: response `INV-20260902-043B4882`, persisted `20ET-INV/2026-27/000011`.
- After the migration, response, persisted invoice, checkout event snapshot and housekeeping note use the same invoice number.
- A full complimentary discount yields zero total, paid, pending and checkout collection amounts; no payment collection is created.
- A second checkout is rejected.
- The entire synthetic stay, invoice, housekeeping task and related transactional evidence are rolled back. Room 101 and room 102 were both verified available afterward.
- The patched checkout remains SECURITY DEFINER with an empty search path.

The migration was applied explicitly using the staging project reference and SQL file, not through a blanket migration push. The inverse rollback file is supplied but **was not run**.

## Browser evidence and remaining acceptance

The local fixture imports the actual shared dialog and has no authentication or network calls. Tested required/whitespace rejection without a submission, Back and Escape without a write, error/input retention, disabled saving controls, trimmed successful values, optional blank inspection notes, staff selection, no-active-staff protection, close/focus restoration, and desktop appearance.

To reproduce: run `npm run dev -- --host 127.0.0.1 --port 5174 --strictPort`, then open `http://127.0.0.1:5174/scripts/fixtures/pilot-action-dialog.html`. The fixture is not part of the production build entry point.

An explicitly approved 60-minute, staging-only View as Hotel session used `hotel_configuration` and `read_only` for 20E Test Hotel. The deployed dashboard showed the new food-revenue label and explanation, zero food revenue, two available rooms and no active guests. That role deliberately does not permit Food Orders or Housekeeping (`src/lib/currentStaff.js`), so those restrictions were not bypassed or broadened. The support session was explicitly ended, verified in the database at **3 September 2026, 00:22:15 IST**.

Next action: sign in to the staging preview as an existing owner or manager of 20E Test Hotel. Then validate the new cancellation/assignment/inspection dialogs against the existing trusted workflows, using clearly labelled staging-only fixtures and no payment collection. A separate explicit approval is still required for any production rollout. Keep Cashfree disabled.
