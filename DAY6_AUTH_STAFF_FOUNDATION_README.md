# StayQR Day 6 — Authentication and Staff Identity Foundation

## Package order

1. Overlay this `Frontend` folder on the current project.
2. Run migration `202607250011_day6_auth_staff_identity_foundation.sql`.
3. Run audit `031_verify_day6_auth_staff_identity_foundation.sql`.
4. Configure Auth redirect URLs.
5. Deploy the `manage-staff-user` Edge Function.
6. Set `STAYQR_APP_URL` for the Edge Function.
7. Run `npm run check` and `npm run dev`.
8. Continue with Day 6 browser acceptance testing.

## Database files

- `supabase/migrations/202607250011_day6_auth_staff_identity_foundation.sql`
- `supabase/audit/031_verify_day6_auth_staff_identity_foundation.sql`

The audit must return 12 rows with every `passed` value equal to `true`.

## Edge Function

- `supabase/functions/manage-staff-user/index.ts`

The function validates the caller's JWT, verifies owner/manager/platform-admin authority, creates or links the Supabase Auth user, synchronizes hotel membership and bans/unbans identities when appropriate.

## Required Auth redirect URLs for local acceptance

- `http://localhost:5173/auth/complete-invite`
- `http://localhost:5173/auth/reset-password`

Add the production equivalents before deployment.

## Required function secret for local acceptance

- `STAYQR_APP_URL=http://localhost:5173`

Do not place the service-role or secret key in `.env` used by Vite. Supabase supplies backend secrets to hosted Edge Functions.
