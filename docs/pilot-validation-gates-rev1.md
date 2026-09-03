# Pilot validation gate repair REV1

Date: 3 September 2026 (Asia/Kolkata).

Scope: local validation scripts and documentation only. Starting commit `a6bdf914ce5bc9d529e4421eb7ffdde35f6c22f7` on `commercial-ready/final-completion`; initial working tree clean. No application source, SQL, Edge Function, provider setting, deployment or marketing content is changed.

Status at `7c92cd8`: **both requested validation blockers resolved; the complete `npm run check` passed**, including its final optimized frontend build configured for staging. No checks in that command were skipped. A separately run performance-budget check exposed a 1.1 KiB initial-download overage, detailed below. Its subsequent correction and verification are recorded in [Pilot initial-download optimization REV1](pilot-bundle-performance-rev1.md). The required original base `5f914d4cd049353e9926b26ffb1599e53a6f1772` remains an ancestor.

## Day 9 commercial gate

The previous gate required `requiresPaymentRecovery`, an identifier removed when Pilot Manual Billing made verified offline payment the default Super Admin action. The actual renewal eligibility remained `active`, `past_due` and `suspended`; expired/cancelled subscriptions use the controlled manual-payment activation path.

The gate now checks the current default action, visible recovery option, selected hotel, positive received amount, receipt reference, paid time, idempotency key and trusted manual-payment RPC. It also checks both renewal guards and the suspended-only reactivation option. The original route, RPC, credential and direct-write checks are retained; direct browser writes to the manual-payment ledger and Cashfree calls from the manual branch are additionally rejected.

This changes validation expectations, not payment behaviour or subscription permissions. The existing Pilot Manual Billing server-source gate is now included in `npm run check`, alongside Commercial-Ready validation and the new validator regression tests.

## External marketing source

The original default `C:\StayQR_MASTER\01_SOURCE\marketing` does not exist. The existing Post-Launch Batch A source bundle is at:

`C:\StayQR_MASTER\10_POSTLAUNCH_BATCH_A\Marketing_BATCH_A`

Its `stayqr.in_current.html` and `DEPLOY_stayqr.in/index.html` are identical, and all 43 existing Batch 1 assertions pass. The older `C:\StayQR_MASTER\02_MARKETING_SITE` copy fails the Hotel Login assertion; it was neither selected nor overwritten. No marketing files were copied, invented, modified or deployed.

SHA-256 of both selected files: `f1613060c5aea82594cad2447c1a50026a86be80c7a2230cb2a64ec114cb9c35`.

The resolver uses this deterministic precedence:

1. An explicit `STAYQR_MARKETING_ROOT`, if supplied.
2. The original sibling `../marketing` directory, if it exists.
3. The consolidated workspace's `../../10_POSTLAUNCH_BATCH_A/Marketing_BATCH_A` source bundle.

The first selected directory must contain both required files. An invalid explicit path or an incomplete preferred directory fails without falling back. No directory is selected based on passing content checks. The script prints the exact selected directory and explicitly identifies the result as a **local source check, not live marketing-site acceptance**. All 43 original content/security assertions are unchanged.

On another machine or CI, provide the intended external source bundle and set `STAYQR_MARKETING_ROOT` to its directory. Missing source remains a hard failure; this repository does not contain or deploy the separate marketing site.

## Validation evidence

- `npm ci --no-audit --no-fund`: pass, 171 packages from the existing lockfile. The first restricted attempt hit a Windows npm-cache permission error; the approved rerun succeeded without changing dependencies.
- Targeted Day 9 gate: pass, 29 required contracts and 9 unsafe-pattern checks.
- Targeted Batch 1 gate: 43/43 pass against the existing Batch A source bundle.
- Validator regressions: 29/29 pass, including unsafe billing mutations, removed lifecycle guards, direct ledger writes, credential markers, explicit-path precedence and missing/incomplete marketing sources.
- Additional CLI negative checks: explicitly selecting the older `02_MARKETING_SITE` copy still fails its content assertion; selecting the missing original directory fails with setup instructions. Neither input silently falls back to the Batch A bundle.
- JavaScript module syntax checks and `git diff --check`: pass. Application source, SQL, Edge Functions, deployment configuration and the package lockfile remain identical to `a6bdf91`.
- Full dependency-backed `npm run check`: pass, exit code 0, including all inherited gates and the added Commercial-Ready, Pilot Manual Billing and validator-regression gates.
- Commercial-Ready: 74/74; Pilot Manual Billing: 42/42; existing UI regressions: 8/8; QR: 5/5; responsive: 77/77; relative imports: 276 resolved.
- ESLint: zero errors, seven unchanged hook-dependency warnings.
- Optimized frontend build: pass, 404 modules. Environment guard confirmed `staging`, project `eecinuhvkxlbdvyuazal`, and release `pilot-validation-gates-20260903-a6bdf91`. A read-only Netlify branch-build URL lookup returned no configured value, so the build used the existing verified staging public values in `.env.local`; no environment file or remote setting was changed.
- Built artifact isolation: expected staging reference present; production project reference and privileged-key markers absent.

Changed files: `package.json`, `scripts/day9-commercial-source-check.mjs`, `scripts/validate-postlaunch-batch1.mjs`, `scripts/lib/marketing-root.mjs`, `scripts/validation-gates.test.mjs`, this report and `docs/pilot-ui-reliability-rev1.md`.

## Additional performance check: remaining issue

After the standard check/build succeeded, `node scripts/day18-performance-budget.mjs` was run separately. It is not part of the existing `npm run check` chain. It failed one of five checks:

- Initial JavaScript gzip: **356.1 KiB**, above the unchanged **355 KiB** ceiling by **1.1 KiB**.
- Largest JavaScript chunk: 157.9 KiB / 450 KiB, pass.
- Total JavaScript gzip: 712.1 KiB / 1,800 KiB, pass.
- Largest CSS chunk gzip: 9.9 KiB / 100 KiB, pass.
- Dynamic route entries: 48 / minimum 20, pass.

The manifest's initial static-import closure includes the document-library vendor bundle. Application source, Vite configuration, the dependency lockfile and the performance gate itself are unchanged by this validation-only repair. No budget override was supplied and the threshold was not raised. Bundle optimization and repeat performance/staging verification are separate follow-up work; production rollout should wait for that result.

## Deployment boundary and next action

These files do not enter the frontend bundle, so no staging redeployment or database migration is needed. The live staging acceptance for implementation commit `c8d923a` remains recorded in `docs/pilot-ui-reliability-rev1.md`. No further login or synthetic payment is needed for this repair.

Follow-up: see [the initial-download optimization report](pilot-bundle-performance-rev1.md) for the performance correction and staging evidence. Production rollout of the accepted UI fix and its checkout migration still requires separate explicit approval. Cashfree remains disabled/unchanged. The optional missing staging Turndown checklist is not configured by this change.
