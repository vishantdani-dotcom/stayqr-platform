# Pilot invoice / folio consistency REV1

Date: 3 September 2026 (Asia/Kolkata).

Status: **implemented, validated and deployed to staging only**. Production and Cashfree configuration are unchanged.

Scope approved by the user: correct checkout/folio discount accounting and zero-taxable rendering locally and on staging; reconcile only the labelled staging invoice's ledger through an auditable discount, preserving the original invoice. Starting branch `commercial-ready/final-completion`, clean at `e6e1383b053f49937c62de94d720b771c6d1c025`.

## Confirmed cause and correction

The prior checkout recorded its discount in an immutable invoice but not in `folio_adjustments`. The register correctly used the live folio, so a complimentary INR 2,500 invoice displayed a spurious INR 2,500 live balance. A read-only staging query confirmed one room charge, zero folio adjustments and zero collections.

Migration 106 adds a private preparation helper to the existing atomic checkout function. It locks the same-hotel folio, verifies charge/collection consistency, posts any missing checkout tax to the ledger, and uses the existing permission-checked discount request/review workflow for the missing discount amount only. It preserves existing approval history and idempotency. The discount input represents the total discount, not an amount to add twice. Checkout notes are required as the reason for a new discount; the guest screen explains and validates that requirement.

Before completing the stay, checkout now asserts that the invoice's totals and zero pending balance agree with its live folio, including actual collections. It never creates a collection to represent a discount and does not mark a legacy demand paid without collection evidence. The helper cannot be called directly by anonymous or authenticated browser roles. The original checkout owner, grants, SECURITY DEFINER setting, empty search path, hotel-role checks and persisted invoice-number correction are preserved.

Incompatible charges/collections, existing tax/discount totals above the checkout inputs, and refund/credit cases needing separate reconciliation fail closed with a Folio & Settlement review message. Existing refund/credit APIs are unchanged; this patch does not reinterpret or erase that evidence.

Invoice register, preview totals and discount-line rendering now use a missing-value fallback that preserves numeric zero. The live ledger remains the register's balance source; the immutable invoice remains the preview's source. No discrepancy is hidden by substituting one for the other.

## Files

- `src/pages/invoices/Invoices.jsx`: preserve zero taxable values in all three affected render expressions.
- `src/pages/guests/Guests.jsx`: request and validate the checkout discount reason.
- `package.json`: include six new regression tests in the full check.
- `scripts/pilot-invoice-folio.test.mjs`: real render-expression tests plus source/security contracts.
- `supabase/migrations/202609030106_pilot_checkout_folio_consistency_REV1.sql`: guarded forward-only function correction; no historical business-data rewrite.
- `supabase/staging/202609030106_pilot_checkout_folio_TRANSACTIONAL_TEST.sql`: rollback-only runtime and authorization scenarios.
- `supabase/staging/202609030106_reconcile_labelled_test_folio.sql`: separately approved, strictly guarded, one-folio historical correction.
- `supabase/staging/202609030106_pilot_checkout_folio_ROLLBACK.sql`: code-only rollback; intentionally preserves approved ledger evidence.
- This report.

## Validation

| Check | Result |
| --- | --- |
| Locked dependency installation (`npm ci`) | Pass; dependency lockfile unchanged |
| Complete `npm run check` | Pass, exit 0; no skipped or weakened gates |
| ESLint | Zero errors; seven existing warnings |
| Invoice/folio JavaScript regressions | 6/6 pass |
| Inherited UI / validator / bundle regressions | 8/8, 29/29, 4/4 pass |
| Staging PostgreSQL runtime | 12/12 scenarios plus 3/3 authorization checks |
| Production-format build with staging configuration | Pass; 404 modules, 72 JavaScript chunks, 48 lazy entries |
| Performance budget | Pass; initial JavaScript 198.9 KiB gzip, unchanged 355 KiB limit |
| Environment separation | Staging reference present, production reference and secret-key marker absent from built assets |
| Deployment artifact check | 14 live assets match the verified local build, including both changed pages and PDF library |
| Browser read-back | Invoice register, preview and Folio & Settlement show corrected values |
| Diff whitespace check | Pass |

The new runtime test failed before the correction with invoice total INR 0 and folio balance INR 2,500. After correction, it passes full fixed/percentage discounts, partial/no discounts, tax with full/partial discounts, prepaid/partially prepaid stays, existing matching/delta discounts, conflicting discount rejection and required-reason rejection. It also checks duplicate checkout rejection and approval evidence. All scenario stays, invoices, tasks, audit events and simulated collections are rolled back; no test payment remains.

The three additional authorization checks verify rejection of a foreign hotel target, rejection of an unprivileged actor, and no direct browser-role execution grant on the private helper. The code-only rollback was rehearsed inside a transaction that was itself rolled back; the correction remained installed afterward. Changed SQL was compiled and executed on staging PostgreSQL. Edge Functions and provider configuration were not changed or redeployed.

## Existing test-ledger reconciliation

- Hotel: 20E Test Hotel (`c6f16ea5-dcb0-40c3-a483-e628a5ea177c`).
- Invoice: `20ET-INV/2026-27/000011` (`33a7254a-dd6a-408c-ab01-f47a8d3bf49f`).
- Folio: `82c01592-4241-4abc-9ff0-70631bbd62da`.
- Added exactly one approved INR 2,500 discount through the existing owner-authorized request/review functions, with reconciliation reason and actor evidence.
- Folio: INR 2,500 charge minus INR 2,500 discount, INR 0 collections, INR 0 balance, `settled`.
- Original invoice row was compared before and after and remained identical, including its stored hash. Invoice total, paid and pending remain INR 0. No invoice, payment or collection was created by this correction.
- Browser register: taxable, tax, total and balance each INR 0. Preview: original room/discount lines retained, discount-line taxable INR 0, header taxable/total/paid/balance INR 0.
- Browser Folio & Settlement: the labelled row shows INR 2,500 charge, INR 0 collection, INR 2,500 adjustment, INR 0 balance and Settled.
- Both staging rooms remain available; the earlier support-access session remains ended. Cashfree readiness remains `pending` / `not_configured`.

The one-folio script deliberately fails closed if rerun after reconciliation, or if any of its exact preconditions have changed. Do not run it against production or use it as a generic historical backfill.

## Deployment and next action

- Staging Supabase: `eecinuhvkxlbdvyuazal` only. Migration 106 was applied explicitly, not through a blanket migration push.
- Staging Netlify site: `stayqr-pilot-staging`, ID `73c4d1f8-d264-4572-a670-2d4984b0a0a5`.
- Staging deploy: `6a9906587cd34e5c66415c65`.
- URL: https://pilot-manual-billing--stayqr-pilot-staging.netlify.app/.
- Build release: `pilot-invoice-folio-20260903-e6e1383` (the verified patch working tree).
- Production published deploy was verified before and after deployment: `6a97eda73762340b04452b37`, unchanged.
- No production database action, production deployment, GitHub push, provider activation or real payment is included.

This correction is accepted on staging; it is not a blanket sign-off for every project feature. Next is a separately authorized production compatibility review and rollout plan for the accumulated staging changes. Production historical data must be reviewed read-only before proposing any record-specific correction; do not copy the staging fixture reconciliation into production. Cashfree must remain disabled. The previously deferred optional Turndown checklist and unrelated pre-existing source exception are outside this patch.
