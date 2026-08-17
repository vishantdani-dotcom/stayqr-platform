# StayQR Day 20E-4 — Operational Launch Documentation Acceptance Index

**Status:** REV1 candidate for 20E-4 acceptance  
**Prepared:** 17 August 2026  
**Scope:** operational launch documentation only. This package does not change application logic, database schema or production data.

## Purpose

This package closes the Day 20E operational-documentation requirement by converting the accepted StayQR v1.0 product behavior into usable launch/runbook material for hotel onboarding, hotel administration, staff operation, support, incident handling, sales demonstration and release control.

## Required set

| Requirement | Authoritative document in this package |
|---|---|
| Hotel onboarding guide | `DAY20E4_HOTEL_ONBOARDING_GUIDE.md` |
| Hotel owner/admin runbook | `DAY20E4_OWNER_ADMIN_RUNBOOK.md` |
| Staff quick-start | `DAY20E4_STAFF_QUICK_START.md` |
| Operational support runbook | `DAY20E4_OPERATIONAL_SUPPORT_RUNBOOK.md` |
| Incident/rollback runbook | `DAY20E4_INCIDENT_ROLLBACK_RUNBOOK.md` |
| Demo script | `DAY20E4_DEMO_SCRIPT.md` |
| Release notes | `DAY20E4_RELEASE_NOTES_V1_0_RC.md` |
| Known limitations | `DAY20E4_KNOWN_LIMITATIONS_V1_0.md` |

## Existing operational foundations reused

The package intentionally references rather than duplicates the already accepted infrastructure material:

- `docs/operations/DAY18_MONITORING_RUNBOOK.md`
- `docs/operations/DAY18_BACKUP_RESTORE_DRILL.md`
- `docs/operations/DAY18_STORAGE_OBJECT_RECOVERY.md`
- `docs/operations/DAY18_CICD_DEPLOYMENT_VALIDATION.md`
- `docs/operations/DAY18_ENVIRONMENT_SEPARATION.md`
- `docs/operations/DAY18_SECURITY_HEADERS_RATE_LIMITING.md`
- `docs/operations/DAY20_PRODUCTION_OPERATIONAL_OWNERSHIP.md`

## Source/product alignment checked

The documentation was grounded against the supplied Day 20 source snapshot, including:

- onboarding five-stage wizard: Hotel & Policies → Types, Floors & Rates → Rooms Import → Guest Operations → Readiness;
- role/permission navigation in `src/lib/currentStaff.js`;
- reservation, calendar, walk-in/check-in, guest/KYC, secure QR, food/service, folio/payment, invoice/receipt/cashier/night-audit and reports surfaces;
- Operations Centre support/diagnostics/settings functions;
- published legal/support/SLA/subscription policies.

## Consistency correction included

`DAY20_PRODUCTION_OPERATIONAL_OWNERSHIP.md` is corrected so the launch payment-provider escalation baseline names **Cashfree**, the currently proven launch payment integration, instead of presenting Razorpay as an active launch provider.

## Acceptance rule

20E-4 may be marked **COMPLETE + LOCKED** only after:

1. the package is applied to the canonical repository;
2. `VERIFY_20E4_DOCS.ps1` returns every required check as PASS;
3. Git diff is reviewed and contains documentation-only changes;
4. the owner confirms the documents are operationally usable.

Final production version/tag/hash remain a **20G** responsibility and are deliberately not invented in these release-candidate notes.
