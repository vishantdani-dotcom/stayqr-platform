# StayQR Commercial-Ready Final Completion REV1

Base: locked V1.1 production source `5f914d4cd049353e9926b26ffb1599e53a6f1772`
Working branch: `commercial-ready/final-completion`
Production changed by this package: **NO**

## Included

- Polished Hotel Owner Billing & AutoPay portal.
- Actionable, weighted Dashboard Activation Score.
- Cashfree recurring/AutoPay mandate, manage, charge/retry and signed webhook foundation.
- Existing Meta WhatsApp safeguards preserved, plus controlled provider/sender readiness configuration.
- Formal UIDAI online-auth provider adapter with separate consent, OTP flow and hash/masked-only evidence; offline fallback preserved.
- 24×7 support wording, founder after-hours escalation and dedicated-number configuration path.
- A 24×7 support operating runbook without invented numeric SLA promises.
- One source validator, one consolidated staging SQL, one browser acceptance checklist, provider guide and guarded rollback.

## Run now — local implementation only

1. Extract `StayQR_COMMERCIAL_READY_FINAL_COMPLETION_REV1.zip`.
2. Right-click `RUN_COMMERCIAL_READY_FINAL_COMPLETION_REV1.ps1` and choose **Run with PowerShell**.
3. The script uses the exact repository path `C:\StayQR_MASTER\01_SOURCE\stayqr-platform`, creates `commercial-ready/final-completion` from the locked commit, installs the complete batch and runs lint/build/source validation.

## Then — StayQR Staging only

1. In Supabase project **StayQR Staging** (`eecinuhvkxlbdvyuazal`), open SQL Editor.
2. Run the entire file `supabase/staging/202609010103_commercial_ready_FINAL_STAGING_APPLY_AND_ACCEPT.sql` once.
3. Required result: **52/52 TRUE**.
4. Run `RUN_COMMERCIAL_READY_STAGING_FUNCTIONS_REV1.ps1` to deploy only the three new staging Edge Functions. Safety flags remain OFF.
5. Deploy the branch to a staging/preview Netlify URL.
6. Complete `docs/commercial-ready/COMMERCIAL_READY_BROWSER_ACCEPTANCE_REV1.md` in one browser pass. Required result: **50/50**.

## Provider activation

Follow `docs/commercial-ready/COMMERCIAL_READY_PROVIDER_CONFIGURATION_REV1.md`. Provider approval is external work, not a software pass. Pending states are intentional until real Cashfree, Meta and authorized UIDAI credentials/evidence exist.

## Production lock

Do not run `RUN_COMMERCIAL_READY_FINAL_ACCEPTANCE_AND_LOCK_REV1.ps1` yet. It is guarded and requires a new explicit Commercial-Ready production authorization plus the exact accepted commit. The earlier V1.1 authorization does not authorize this rollout.
