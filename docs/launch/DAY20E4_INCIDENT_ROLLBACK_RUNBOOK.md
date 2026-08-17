# StayQR Day 20 — Incident and Rollback Runbook

**Primary incident owner:** Vishant Dani  
**Applies to:** production incidents affecting StayQR v1.0

This runbook coordinates the already accepted Day 18 monitoring, environment-separation, backup/restore and deployment controls. It does not authorise untracked production fixes.

## 1. Trigger this runbook

Use incident mode for:

- P0/P1 production outage;
- suspected/confirmed tenant isolation or security failure;
- material data loss or corruption risk;
- financial-integrity/invoice/payment mismatch with material impact;
- broken critical reservation/check-in/checkout/guest QR workflow;
- failed production deployment affecting hotel operation;
- serious third-party provider failure requiring coordinated action.

## 2. Immediate containment

1. Stop non-essential production changes/deployments.
2. Record incident start time and current production release/deploy identity.
3. Open **Operations Centre → Diagnostics** and capture the incident/request ID.
4. Determine affected hotels, workflows and time window without exposing unnecessary PII.
5. If security/tenant isolation is suspected, prioritise containment over feature availability.
6. If financial integrity is uncertain, stop repeated collection/refund/invoice actions for the affected transaction path.
7. Preserve screenshots/log IDs/provider references.

Do **not** run improvised direct production SQL to make the symptom disappear.

## 3. Decide: workaround, forward fix or rollback

### Use a workaround when

- it is safe;
- data/financial correctness remains intact;
- it restores the material workflow while a controlled fix is prepared.

### Use a forward fix when

- root cause is understood;
- source/migration provenance exists;
- staging/local validation can reproduce and prove the correction;
- rollback would create higher data/schema risk.

### Use rollback when

- a newly deployed frontend/config release clearly introduced the incident;
- a known-good production deploy exists;
- rollback will not create schema/application incompatibility.

## 4. Frontend/Netlify rollback

1. Identify the last known-good production deploy and its source commit/release.
2. Confirm the database schema remains compatible with that deploy.
3. Use Netlify deployment controls to republish/promote the known-good production deploy.
4. Verify HTTPS/domain, app shell and critical deep links.
5. Smoke-test the affected production workflow with controlled/synthetic data where safe.
6. Keep the faulty release details in incident evidence; do not delete the evidence needed for diagnosis.

## 5. Database/schema rollback boundary

Database rollback is higher risk than frontend rollback.

- Do not reverse a migration merely because the frontend was rolled back.
- Follow the specific migration's documented rollback posture where one exists.
- For additive monitoring/schema components already receiving production data, export required evidence before destructive removal.
- Do not point restore scripts at production as an experiment.
- Restore drills must first use the dedicated staging/disposable target contract.
- Production restoration requires an explicit incident decision, validated backup, scope confirmation and owner approval.

The accepted database backup/restore drill proves SQL backup recoverability. Storage object bytes have a separate recovery procedure.

## 6. Storage recovery boundary

For missing/corrupt Supabase Storage objects:

- use the accepted storage-object recovery process;
- preserve bucket/object path and hash evidence;
- do not treat a database-only restore as proof that file bytes were restored;
- production source access should remain read-only during backup evidence capture unless an explicitly approved recovery action is being performed.

## 7. Environment safety

Production and staging Supabase projects must remain distinct.

Never expose privileged variables in browser builds. Service-role/database secrets remain server-side/trusted only.

Destructive validation, restore, deletion and rate-limit stress testing belongs in staging or a disposable environment before production.

## 8. Provider incident

For Cashfree or another independent infrastructure dependency:

1. confirm whether StayQR itself is healthy;
2. preserve provider order/payment/reference IDs without storing secrets/full card data;
3. avoid duplicate payment/refund actions while provider state is uncertain;
4. escalate to the provider where required;
5. communicate the known customer impact and workaround without promising the provider's restoration time.

## 9. Recovery acceptance

Do not close P0/P1 until all applicable checks are green:

- affected production path works;
- no reproducible tenant leak;
- no new data-loss/financial mismatch;
- production health is healthy/degraded only for understood non-blocking items;
- failed deliveries/provider events are reconciled as required;
- support/customer communication is updated;
- current deploy/release is recorded;
- rollback/fix evidence is preserved.

## 10. Post-incident

Record:

- incident ID;
- severity;
- start/recovery time;
- affected hotel/workflow;
- root cause;
- workaround;
- fix/rollback commit/deploy;
- database/storage action if any;
- customer/provider communication;
- prevention/follow-up owner;
- whether legal/privacy/security notification review is required.

Reopen the incident if the failure recurs or the earlier recovery was incomplete.

## Existing detailed references

- `docs/operations/DAY18_MONITORING_RUNBOOK.md`
- `docs/operations/DAY18_CICD_DEPLOYMENT_VALIDATION.md`
- `docs/operations/DAY18_ENVIRONMENT_SEPARATION.md`
- `docs/operations/DAY18_BACKUP_RESTORE_DRILL.md`
- `docs/operations/DAY18_STORAGE_OBJECT_RECOVERY.md`
- `docs/operations/DAY20_PRODUCTION_OPERATIONAL_OWNERSHIP.md`
