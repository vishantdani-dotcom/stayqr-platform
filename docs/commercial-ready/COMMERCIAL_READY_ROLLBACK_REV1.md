# StayQR Commercial-Ready Rollback REV1

Rollback is for staging or an explicitly authorized production incident only. Take a database backup first. Never run rollback merely because a provider has not approved the account; pending provider states are expected and safe.

## Application rollback

1. Return the deployment branch to the last locked V1.1 commit `5f914d4cd049353e9926b26ffb1599e53a6f1772`.
2. Redeploy that exact commit.
3. Keep the additive Commercial-Ready database objects in place unless they are proven to cause the incident; the V1.1 source does not depend on them.
4. Keep all provider safety flags OFF during investigation.

## Provider emergency stop

- Cashfree: set `CASHFREE_SUBSCRIPTIONS_ENABLED=false`.
- Meta: set `WHATSAPP_AUTOMATION_ENABLED=false` and disable hotel channel settings.
- UIDAI: set `UIDAI_ONLINE_AUTH_ENABLED=false`; offline fallback remains available.

## Database rollback conditions

Database removal is permitted only before provider/owner/UIDAI evidence exists, or after that evidence has been exported and retention/legal requirements are confirmed. Prefer disabling provider flags over dropping audit data.

Use `supabase/rollback/202609010103_commercial_ready_ROLLBACK_REV1.sql` only after those conditions are satisfied.
