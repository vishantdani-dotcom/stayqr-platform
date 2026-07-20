# StayQR Canonical Tenant Context

## Locked production rule

Every authenticated hotel-dashboard operation resolves tenant access through:

1. Supabase Auth user;
2. active `platform_admins` identity, if present;
3. active `staff.auth_user_id` assignments;
4. active `hotel_users.user_id` memberships;
5. one selected hotel from only those authorized hotels;
6. all page queries and writes scoped to the selected `hotel_id`.

No page may:

- contain a fixed hotel UUID;
- use a default/fallback hotel;
- resolve membership by email;
- trust a hotel ID supplied only by the browser;
- assume that one user can belong to only one hotel.

## Frontend implementation

`src/lib/tenantContext.js` is the only canonical resolver.

Compatibility wrappers:

- `getCurrentHotel()` returns its selected hotel;
- `getCurrentStaff()` returns its selected hotel user profile.

The selected hotel is stored as `stayqr:selected-hotel-id` only after the user
has proven access. `selectTenantHotel()` rejects unauthorized hotel IDs.

## Platform administration

Platform administrators are resolved from `platform_admins`, not from a
hotel-level `super_admin` membership. A platform admin may access the Super
Admin system and may also select an authorized/visible hotel context.

## Database enforcement

Frontend context improves consistency but is not the security boundary.
Supabase RLS and trusted database functions remain authoritative for every
read and write.
