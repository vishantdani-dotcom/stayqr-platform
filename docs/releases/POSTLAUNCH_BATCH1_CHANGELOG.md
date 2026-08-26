# StayQR Post-Launch Batch 1 Changelog

## User items completed in source

| Item | Result |
|---|---|
| 1 | Added `Hotel Login` on `stayqr.in`, targeting `https://app.stayqr.in/login`. |
| 2 | Replaced pricing demo actions with Starter/Growth/Scale paid and 14-day trial acquisition; added monthly/yearly selection, account continuity, Cashfree server-priced checkout, signed-webhook provisioning and recovery. |
| 9 | Activated navbar search with click and Ctrl/Command+K; results are active-hotel and permission scoped. |
| 10 | Replaced the generic sidebar admin lockup with the official StayQR logo asset. |
| 12 | Active guest requests now show `Cancel`, ask for confirmation, and retain `Cancelled` only as the resulting status. |
| 15 | Removed the global light-heading regression, raised muted text contrast, and added shared 1024/900/768/480 responsive safety corrections for marketing and app shells. |

## Controlled regression corrections

- Preserved the locked Day 20 migration and support runbook byte-for-byte.
- Corrected a migration sequence collision by assigning this batch migration 083 after locked migration 082.
- Corrected the inherited Day 7 validator so legal warning text is not mistaken for a browser service-role secret.
- Replaced a pre-existing direct browser KYC metadata delete with a permission-checked, activity-audited RPC after the inherited Day 10 gate identified it.
- Corrected stale Day 17/18 validator assumptions for CRLF-safe JWT restoration and additive lazy routes.
- Corrected consumer-environment lint findings in the new checkout and sidebar: removed an unused icon and replaced manual hook memoization with stable state plus direct intent loading.
- Made Batch A locked-file validation CRLF-safe so Windows Git checkouts verify canonical content without weakening the Day 20 migration or support-runbook locks.

## Deferred

- No platform 24×7 support claim, staffing, SLA, legal, marketing or runbook change is included.
- Batch B and later items remain outside this release.
