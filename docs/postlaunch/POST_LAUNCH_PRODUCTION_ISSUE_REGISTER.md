# StayQR Post-Launch — Production Issue Register

## Open / needs verification

| Issue | Category | Severity | Current status | Allowed next action |
|---|---|---|---|---|
| Current live state after historical Batch 3 access regression | Production runtime verification | P1 history | NEEDS VERIFICATION | Read-only/live smoke only after explicit production authorization |
| Hotel Apex Stay Inn real customer production canary | Rollout acceptance | Launch gate | NOT EXECUTED IN THIS STAGING-ONLY SESSION | Controlled live rollout only after explicit production authorization |

## Closed / staging proven

| Issue | Category | Result |
|---|---|---|
| Staff phone_verified_at / avatar_path schema mismatch | Schema parity | FIXED / ACCEPTED |
| Apex configuration foundation readiness | Configuration | FIXED / ACCEPTED |
| Gate C reservation E2E | Staging acceptance | PASS |
| Gate C walk-in E2E | Staging acceptance | PASS |
| Gate C QR / food / service / folio / invoice / checkout / housekeeping / reports | Staging acceptance | PASS |

Do not convert NEEDS VERIFICATION into PASS without runtime evidence.
