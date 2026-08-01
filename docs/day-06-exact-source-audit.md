# StayQR Day 6 Exact Source Audit

Source audited: Day 5 closed Frontend uploaded on 25 July 2026.

## Confirmed existing foundation

- Supabase email/password sessions are already used.
- `staff.auth_user_id`, `hotel_users.user_id` and `platform_admins.user_id` exist.
- Tenant context resolves platform and hotel identities separately.
- Hotel switching is stored per authenticated user.
- Existing tenant RLS rejects hotel data when an active membership no longer exists.
- Client navigation already has a role-based compatibility map.

## Production gaps found

1. Staff Management inserted only a `public.staff` row. It did not create a real Supabase Auth identity or send an invitation.
2. The UI used `disabled` and `archived`, while the live tenant foundation permits `active`, `invited`, `inactive` and `suspended`.
3. Login had no forgot-password, recovery or invitation-completion flow.
4. The login screen was labelled only for hotel administrators even though platform administrators and departmental staff use the same secure entry point.
5. Staff and `hotel_users` could drift because they were edited separately.
6. Browser clients could write staff and membership rows directly instead of using a trusted server-side identity workflow.
7. Disabled staff lost RLS access, but their Supabase Auth account was not administratively banned when they had no other active hotel access.
8. `role_permissions` existed but was not used by the frontend tenant context.
9. The Staff page had a fail-open `manager` fallback when the current role was unavailable.
10. Client navigation alone was not sufficient proof of action-level authorization.

## Stage 1 corrections in this package

- Canonical staff lifecycle columns and status constraints.
- Canonical role and permission seed.
- Server-authoritative permission RPC.
- Secure invitation-activation RPC.
- Staff-to-hotel-membership synchronization trigger.
- Direct browser identity writes revoked.
- Trusted `manage-staff-user` Edge Function.
- Real Supabase Auth invitation creation and identity linking.
- Auth ban/unban when staff access is disabled or restored.
- Last-active-owner and self-disable protections.
- Secure login, forgot-password, reset-password and invitation-password screens.
- Permission-aware navigation with role fallback only for compatibility.
- Staff Identity UI that invokes the trusted Edge Function.

## Not yet claimed complete

This is the Day 6 authentication and staff-identity foundation. Day 6 is not complete until the migration, Edge Function, email redirects, invitation flow, role login tests, disable-access tests and final action-level authorization gate all pass.
