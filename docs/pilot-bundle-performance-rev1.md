# Pilot initial-download optimization REV1

Date: 3 September 2026 (Asia/Kolkata).

Scope: local build optimization and staging-only deployment. Starting commit `7c92cd830c8e3af00918979eaa04e6340ec3f4e9` on `commercial-ready/final-completion`; initial working tree clean. Production rollout is not authorized by this change. Cashfree and other provider settings are unchanged.

Status: **performance correction implemented, fully validated and deployed to staging only**. A separate invoice-register/folio balance discrepancy was observed during the read-only invoice check; it is not repaired by this packaging change.

## Cause and correction

The previous manifest placed Vite's shared `\0vite/preload-helper.js` inside `vendor-documents`. The app shell and Supabase imported that helper, so the static startup dependency tree also loaded the PDF libraries even before opening a document screen. This was confirmed from both the built manifest and staging's preload links.

The installed bundler recursively groups dependencies. Merely assigning a name to the helper through `manualChunks` did not isolate it: a diagnostic build showed it was still absorbed into `vendor-documents`. The final configuration uses the supported `codeSplitting.groups` API and a higher-priority, exact-match group for that helper. The existing React, Supabase, document, drag-and-drop and common-vendor classification is retained.

Only packaging changes. No hotel isolation, permission, business workflow, database, Edge Function or PDF-generation source code is changed. All 48 lazy route entries remain available, and the invoice route still imports its document libraries.

## Measured results

| Build check | Before | After | Unchanged limit |
| --- | --- | --- | --- |
| Initial JavaScript gzip | 356.1 KiB, fail | 198.9 KiB, pass | 355 KiB |
| Largest JavaScript chunk gzip | 157.9 KiB | 157.4 KiB | 450 KiB |
| Total JavaScript gzip | 712.1 KiB | 712.3 KiB | 1,800 KiB |
| Largest CSS chunk gzip | 9.9 KiB | 9.9 KiB | 100 KiB |
| Dynamic route entries | 48 | 48 | At least 20 |

Startup JavaScript is approximately 44% smaller (157.2 KiB saved). Total JavaScript is approximately unchanged; the PDF library has been deferred, not removed. No performance threshold or environment override was used to make the budget pass.

`npm run check` now includes the real performance budget and the new post-build bundle tests. The four bundle tests cover runtime priority, Windows/POSIX vendor classification, absence of PDF code in every app entry's static dependency tree, and continued document-library availability from the lazy invoice route. The previous artifact failed the new startup-isolation test; the optimized artifact passes 4/4.

## Final local validation

- Complete `npm run check`: pass, exit code 0, including the build, performance budget and new bundle tests. No gate was skipped or weakened.
- Commercial-Ready: 74/74; Pilot Manual Billing: 42/42; UI regressions: 8/8; validator regressions: 29/29; bundle regressions: 4/4.
- All inherited source/security gates passed; relative imports: 276; QR: 5/5; responsive: 77/77.
- ESLint: zero errors, seven unchanged warnings. Optimized build: pass, 404 modules and 72 JavaScript chunks.
- Build environment guard: staging project verified. Built assets contain the expected staging reference and no production project reference or privileged-key markers.
- The dependency lockfile and all application, SQL and Edge Function source files are unchanged. Dependencies were already installed with `npm ci` in the preceding gate-repair run; no dependency upgrade is included here.
- `git diff --check`: pass.

## Staging verification

- Deployed the verified `dist` artifact with `--no-build`, explicit staging site ID and the existing `pilot-manual-billing` preview alias. Deploy ID: `6a98d1782936521413cd848a`.
- HTTPS, security headers, immutable entry-asset caching and SPA deep-link rewrite: pass.
- All eight checked assets match the verified local build byte-for-byte: the entry, its startup dependency tree and the separately loaded document library.
- Reloaded staging as the existing **20E Test Hotel** owner. Dashboard rendered successfully with two available rooms, no active guests and zero food revenue. Before opening the invoice screen, the DOM contained **no document-library preload link**.
- Opened **Invoices & Audit**. The document-library preload appeared only then (`vendor-documents-BiFMAFD1.js`), and the invoice register rendered successfully.
- Opened the existing labelled staging invoice `20ET-INV/2026-27/000011`. Its immutable preview rendered its room charge and full discount, with invoice total, paid and balance all INR 0. The Download PDF action was exercised without a visible failure. The downloaded file itself was not independently inspected; this is a browser-action smoke check, not a fresh PDF-layout audit.
- No new hotel, stay, invoice, payment, subscription or housekeeping record was created for this optimization. The browser was returned to the owner dashboard.
- Production deployment identifier was checked again and remains `6a97eda73762340b04452b37`, unchanged. No provider setting was modified.

## Deployment boundary

- Target site: `stayqr-pilot-staging`, ID `73c4d1f8-d264-4572-a670-2d4984b0a0a5`.
- Target preview: `https://pilot-manual-billing--stayqr-pilot-staging.netlify.app/`.
- Build environment: staging, Supabase `eecinuhvkxlbdvyuazal`.
- Build release: `pilot-bundle-performance-20260903-7c92cd8` (built from this patch's working tree).
- Production site `stayqr-day18-preview` was read-only verified at published deploy `6a97eda73762340b04452b37` before work.
- No GitHub push, production deploy, SQL migration, Edge Function deployment, payment collection or provider activation is part of this patch.

The earlier labelled staging invoice and completed stay can be read for browser checks; no new hotel, guest, payment or subscription is needed.

## Separate settlement follow-up before production

The existing zero-total fixture `20ET-INV/2026-27/000011` shows **INR 2,500 live balance in the invoice register**, while its immutable preview correctly shows **INR 0 total, paid and balance**. Source inspection explains the two inputs: `getLiveInvoiceSettlement()` in `src/pages/invoices/Invoices.jsx` uses the linked live folio's `balance_amount`, whereas the invoice preview uses the stored invoice's `pending_amount`. Those files are unchanged by this optimization.

This is a settlement-consistency finding, not a PDF-loading failure. A fresh, single-fixture read-only SQL cross-check was attempted but the local Supabase CLI failed to start (`spawn UNKNOWN`) before the query ran. The current browser evidence and earlier invoice database acceptance are retained; no assumption was made that the two balances are reconciled.

Next action: investigate the test invoice's linked folio and complimentary-discount accounting read-only, then agree the scoped correction before any production rollout. Do not record a payment, alter an immutable invoice or clear a balance simply to make the display agree. Cashfree must remain disabled. The optional staging Turndown checklist also remains outside this patch.
