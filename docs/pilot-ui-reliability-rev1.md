# Pilot UI reliability REV1 — local and staging evidence

Date: 3 September 2026 (Asia/Kolkata).

Status: implemented locally and published to staging. **Live staging Food Orders, checkout and Housekeeping acceptance passed on 3 September 2026. Not released to production.** The unrelated legacy validation blockers below remain open.

## Scope and deployment

- Branch: `commercial-ready/final-completion`.
- Implementation commit: `c8d923a583e0befbfca3f4618475d8843fd82565`.
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
| Live owner-browser workflows | Food cancellation, zero-total checkout, housekeeping assignment/checklist/rework/pass/ready and task cancellation passed |
| Read-only browser-fixture database acceptance | 18/18 pass; zero failed checks |
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

## Browser evidence

The local fixture imports the actual shared dialog and has no authentication or network calls. Tested required/whitespace rejection without a submission, Back and Escape without a write, error/input retention, disabled saving controls, trimmed successful values, optional blank inspection notes, staff selection, no-active-staff protection, close/focus restoration, and desktop appearance.

To reproduce: run `npm run dev -- --host 127.0.0.1 --port 5174 --strictPort`, then open `http://127.0.0.1:5174/scripts/fixtures/pilot-action-dialog.html`. The fixture is not part of the production build entry point.

An explicitly approved 60-minute, staging-only View as Hotel session used `hotel_configuration` and `read_only` for 20E Test Hotel. The deployed dashboard showed the new food-revenue label and explanation, zero food revenue, two available rooms and no active guests. That role deliberately does not permit Food Orders or Housekeeping (`src/lib/currentStaff.js`), so those restrictions were not bypassed or broadened. The support session was explicitly ended, verified in the database at **3 September 2026, 00:22:15 IST**.

### Completed live owner acceptance

The user then signed in as the existing owner of **20E Test Hotel** on the correct staging preview. No new support session or additional permission was granted. Testing used room 102 and a synthetic guest labelled `STAGING QA UI c8d923a`, with no guest contact or identity details.

- Ordered one existing `coke` item for INR 20 through the signed guest menu. Food cancellation rejected a whitespace-only reason; Back closed without changing the order. A valid reason cancelled the order once, and both the kitchen and guest views agreed. Dashboard Food Orders Today was 1 while Food Revenue Today remained INR 0.
- Checked out the synthetic INR 2,500 room charge with a full complimentary discount. The UI correctly showed zero total, paid and remaining amounts and explicitly said no collection would be recorded. The invoice, checkout event and cleaning-task note all reference `20ET-INV/2026-27/000011`. There are **zero payment collection records** for this stay; a room-charge ledger entry is not money collected.
- Housekeeping assignment rejected an empty selection and accepted the existing active hotel owner. Completion was blocked until all eight required checklist items were checked. A whitespace-only inspection failure reason was rejected; a valid simulated reason produced a failed inspection and an audited rework cycle. Escape dismissed the pass dialog without passing; optional blank notes were accepted on the subsequent submission. Explicit room-ready approval restored room 102 to available.
- A separate, clearly labelled dummy room-cleaning task tested cancellation. Whitespace was rejected and Back made no change; the valid cancellation was recorded exactly once. No open tasks remain for room 102.
- The previous guest food link was rejected after checkout as invalid, expired or no longer active. Database readback confirms its guest access tokens are revoked. The synthetic guest tab was closed.
- Final owner dashboard: two available rooms, zero occupied/cleaning rooms, zero active guests, one food order today and INR 0 food revenue. Cashfree readiness remains `pending` / `not_configured`.

Unlike the earlier transactional SQL regression, these browser-created records are **retained as labelled staging audit history**: the completed synthetic stay, zero-total invoice, cancelled food order, ready cleaning task and cancelled dummy task. No production records or real payments were created, and no test-history deletion was performed.

| Staging evidence | Identifier |
| --- | --- |
| Hotel | `c6f16ea5-dcb0-40c3-a483-e628a5ea177c` (`20e-test-hotel`) |
| Completed guest session | `e50ee898-1edd-44f2-b2de-bbbc78de8a95` |
| Cancelled food order | `14526a5a-1a60-4d52-874d-d8172ee6bfee` |
| Zero-total invoice | `33a7254a-dd6a-408c-ab01-f47a8d3bf49f` |
| Ready checkout-cleaning task | `4487fcbc-a7d2-4710-b05d-95f330f9c590` |
| Cancelled dummy task | `f84f255e-a39a-4554-87d2-cc4b75679696` |

`supabase/staging/202609020105_pilot_ui_reliability_BROWSER_ACCEPTANCE_REV1.sql` verifies these exact records in a read-only transaction. It passed **18/18** checks against staging, including invoice consistency, no collections, saved cancellation reasons, checklist completion, the rework event counts, token revocation, room availability and unchanged Cashfree readiness. It contains no guest access token values and makes no changes.

### Existing configuration gap encountered

Creating the cancellation-only fixture as a **Turndown** task was rejected because staging has no active checklist template for that task type. No Turndown task was created. The test used the existing room-cleaning template instead. This is a staging configuration gap, not a regression in the new cancellation dialog; no template or production setting was changed.

## Next action

No further owner login is needed for this acceptance run. Review and resolve the pre-existing Day 9 validation mismatch and missing external marketing file before treating the entire release gate as green. Configure a Turndown checklist only if that optional workflow is required. Any additional fixes or configuration changes need their own scoped work; this acceptance run did not bypass the blockers.

A separate explicit approval is still required before releasing implementation commit `c8d923a` or its checkout migration to production. Keep Cashfree disabled. The follow-up evidence/report changes do not require another frontend deployment.
