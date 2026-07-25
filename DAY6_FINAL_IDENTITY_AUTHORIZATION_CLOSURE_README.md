# StayQR Day 6 Final Closure Package

This is the complete Frontend source after the successful Day 6 browser tests,
plus the final identity-reconciliation, ES256 Edge Function and action-level
permission hardening.

## New migration

`supabase/migrations/202607250012_day6_identity_reconciliation_and_authorization_hardening.sql`

## Final audit sequence

- `032_verify_day6_identity_reconciliation_and_authorization.sql` — 16/16
- `033_seed_day6_final_acceptance_context.sql` — one JSON context
- `034_day6_final_acceptance_gate.sql` — 20/20
- `035_cleanup_day6_browser_acceptance.sql` — one cleanup JSON
- `036_verify_day6_browser_acceptance_cleanup.sql` — 8/8

## Edge Function deployment

The project uses ES256 Auth signing keys. Deploy the function with gateway JWT
verification disabled. The function performs its own verified Auth lookup before
any privileged operation.

```powershell
npx supabase@latest functions deploy manage-staff-user `
  --project-ref rbyirbovbkguzvwijyaj `
  --use-api `
  --no-verify-jwt
```

Do not expose or copy the service-role key into the frontend `.env`.
