# Pilot routed checkout compatibility REV1

Date: 3 September 2026 (Asia/Kolkata).

Status: **implemented locally, validated and deployed to staging only**. Production code, deployments, business records and Cashfree settings remain unchanged. Hotel DANI's historical ledger has not been corrected by this patch.

## Scope and baseline

The user approved the compatibility patch locally and on staging after the read-only production review. Starting branch: `commercial-ready/final-completion`, clean at `7e1df2b7d4d868fdf251249069d7e738fddc4bb6`. The required original base remains an ancestor.

Production has a public checkout router, a directly callable legacy delegate, and a private existing-invoice delegate. Staging previously had a single flat implementation. Migrations 105/106 cannot be applied unchanged to that production router. Migration 107 is the guarded cumulative adapter for the two exact reviewed predecessors; it is not a blanket migration push or a historical backfill.

## Changes

- Captured the three production checkout definitions and the two staging predecessor definitions, signatures, security settings and normalized body fingerprints in a local source-contract snapshot. It contains code, not guest data or credentials.
- Kept the production public router exactly unchanged. Staging now uses the same routing contract.
- Applied persisted invoice-number and folio consistency corrections to the legacy new-invoice path. Direct legacy calls retain their existing charge compatibility checks before using the guarded issued-invoice path.
- Preserved finalized invoice reuse, same-hotel access, stay/room/folio locking, tax/discount matching, active-food-order rejection and idempotent public retries.
- Added same-stay ledger checks for issued invoices. Missing discount/tax is reconciled through the existing private helper and permission-checked discount approval workflow, not through a fabricated collection. This occurs only during an authorized active-stay checkout; completed historical records are untouched.
- Handled both accounting formats explicitly: checkout-compatibility invoices store gross subtotal; native authoritative folio invoices store subtotal after discount. The latter must have their discount added back to compare with gross charges. Unknown formats and conflicting charges fail closed.
- Retained valid refunded-and-recollected settlement, while unpaid/refunded balances, unresolved credits, conflicting adjustments and excess funds require review. Issued checkout creates no collection and does not rewrite the invoice or invoice lines. Its final check also detects changes to financial evidence caused by operational triggers.
- Updated the existing Guests component to load its same-hotel/same-stay issued invoice, show exact immutable totals, and lock issued tax/discount inputs. Live collections minus refunds determine payment, not stale saved invoice pending/paid fields. Unpaid issued invoices direct the user to Folio & Settlement; they cannot use the new-payment confirmation controls. New-invoice controls remain available.
- Rechecked the current hotel asynchronously before showing/submitting checkout. No tenant fallback was added.

## Permission and migration safety

The adapter only accepts known function-body fingerprints. It preserves existing function ownership, grants, SECURITY DEFINER, empty search path and argument defaults. Newly created delegates receive the corresponding production execution contract; private helpers are not directly executable by browser roles.

No existing table grant or RLS policy is changed by migration 107. Production's seven stricter finance-table INSERT/UPDATE/DELETE restrictions were reproduced **inside rollback-only staging tests**. The test RPCs ran under the actual `authenticated` database role, not merely an authenticated JWT executed as postgres. Those temporary restrictions were rolled back along with the fixtures; existing staging table grants remain unchanged.

Separate code-only rollback files cover the original flat staging and routed production predecessors. Both were rehearsed on staging inside transactions that were rolled back. A production-shaped rehearsal means production **source definitions in staging**, never a production write. Rollback does not remove historical invoice, discount or collection evidence.

## Validation

| Check | Result |
| --- | --- |
| Locked dependency installation | Pass; `npm ci --no-audit --no-fund`; lockfile unchanged |
| Complete source/check suite | Pass twice, including explicitly staging-configured release build; no original gate removed or weakened |
| Commercial-Ready / Pilot Manual Billing | 74/74 and 42/42 pass |
| ESLint | 0 errors; 7 inherited hook-dependency warnings |
| New compatibility JavaScript tests | 14/14 pass |
| Inherited UI / invoice / validation / bundle tests | 8/8, 6/6, 29/29 and 4/4 pass |
| Staging from flat predecessor | 12 new-invoice + 15 issued-invoice cases pass; rollback rehearsed |
| Staging with routed production predecessor | Same 27 cases pass; rollback rehearsed |
| Post-install repeat/idempotency rehearsal | Same 27 cases pass; installed patch remains in place afterward |
| Authorization | Four cross-hotel/unauthorized-actor rejections across public and direct legacy entry points; finance grant assertions and private-helper restrictions pass |
| Local real-component browser tests | Paid, unpaid, complimentary and new-invoice controls verified; whitespace-only reason rejected |
| Staging environment guard | Pass; staging project and traceable release label verified |
| Optimized build | Pass; 405 modules, 72 JavaScript chunks, 48 dynamic entries |
| Initial JavaScript | 198.9 KiB gzip, within unchanged 355 KiB budget |
| Artifact isolation | Staging reference present; production reference and secret-key marker absent from built JavaScript |
| Deployed assets | 14 live staging assets match the verified build |
| Installed code readback | All four staging checkout/helper definitions match expected fingerprints and security metadata |
| Production readback | All three production checkout definitions and execution ACLs match the captured originals |
| Edge Functions | No changes or redeployment; no new Edge Function syntax to validate |

The 15 issued cases cover native fully paid invoices with stale saved pending, full/partial discounts, direct legacy reuse, old-format missing/full/delta discounts, missing tax with full discount, unpaid rejection, tax/discount mismatch rejection, charge discrepancy rejection, refunded-pending rejection, valid refund/recollection, credit review and missing discount reason. Successful cases assert immutable invoice/line evidence, no new money evidence, one checkout event and repeat-call idempotency.

Each runtime scenario uses a synthetic staging stay and rolls back its entire subtransaction; the outer transaction also rolls back. Legacy-format fixture setup is explicitly separated from the real authenticated RPC call. No test stay, invoice, adjustment, refund or simulated collection from these rehearsals persists.

The Browser skill was used to test the actual Guests component with an isolated local mock data source: no credentials, real hotel data, Supabase client or external write path. Paid issued checkout sent the saved tax/discount and `remaining_payment_collected: false`; unpaid issued checkout was disabled with no collection checkbox; complimentary amounts remained zero; whitespace-only reason was rejected; new invoice inputs and collection controls remained editable. This is not a claim that a new real staging guest was checked out through the browser. Runtime database acceptance was performed separately as described above.

## Deployment and final state

- Supabase target: **`eecinuhvkxlbdvyuazal` only**. Migration 107 was applied explicitly.
- Netlify staging site: `stayqr-pilot-staging`, ID `73c4d1f8-d264-4572-a670-2d4984b0a0a5`.
- Staging deploy: `6a99163d779af2c36eb784e1`.
- Preview: https://pilot-manual-billing--stayqr-pilot-staging.netlify.app/.
- Build release: `pilot-checkout-compatibility-20260903-7e1df2b` (the verified patch working tree).
- Production published deploy remains **`6a97eda73762340b04452b37`**.
- Staging 20E Test Hotel: zero active test stays, two available rooms, zero retained rollback-fixture guests.
- The previously reconciled staging folio remains settled: INR 2,500 discount, zero collection and zero balance. It was not re-reconciled.
- Production Hotel DANI's existing discrepancy remains unchanged: INR 2,500 ledger balance, zero ledger discount and zero collections.
- Production `CASHFREE_SUBSCRIPTIONS_ENABLED` digest still matches `false`. Both provider-readiness records remain `pending / not_configured`.
- No production migration/deployment, GitHub push, provider activation, access expansion, real payment or historical deletion was performed.

## Files and reproducibility

Implementation: `src/lib/issuedCheckout.js`, `src/pages/guests/Guests.jsx`, migration 107, and the reviewed snapshot under `supabase/compatibility`.

Reproducible SQL generation: `scripts/lib/pilot-checkout-compatibility.mjs` exports `migrationSql()` and environment-specific `rollbackSql()`. The JavaScript test compares their output against the committed SQL files and verifies all original snapshot fingerprints.

Staging rehearsal composition: `scripts/lib/pilot-checkout-rehearsal.mjs` exports `rehearsalSql('staging', true)` and `rehearsalSql('production', true)`. Both outputs are staging-fixture-guarded and end in ROLLBACK. They reuse the inherited 12-case suite, adapting repeat-call expectations to the existing production idempotent contract, and append `supabase/staging/202609030107_pilot_issued_checkout_TEST.sql`. That issued-test file is a fragment, not a standalone migration.

Local browser fixture: run `node scripts/pilot-checkout-browser-fixture.mjs`, then open `http://127.0.0.1:5176/scripts/fixtures/pilot-checkout.html`. It imports the real Guests component while substituting only the data/current-hotel modules in a dedicated local Vite server. It is not imported by the application or included in the production build.

## Exact next action

The compatibility patch is accepted on staging. The next step is **separate approval for production rollout of the final local commit**, keeping Cashfree disabled. Before any production write, recheck the exact source/security fingerprints and published deployment, create a fresh production-configured build, validate its project reference, and use migration 107 explicitly rather than attempting 105/106 against the production router.

Hotel DANI's historical ledger correction remains a separate, exact-record production approval. It must preserve the finalized invoice/hash and use auditable discount evidence, never a fake payment. The unrelated pre-existing staging source exception and optional Turndown checklist remain outside this patch.
