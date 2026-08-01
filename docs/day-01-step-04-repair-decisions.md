# StayQR Day 1 — Step 4 Repair Decisions

## Decisions made from exact production records

### 1. Hotel profile

Two profile rows represented VD Stay Inn:

- linked row: `VD Stay Innn`
- orphan row: `VD Stay Inn`

The migration:

1. archives both complete rows in `private.hotel_info_archive_20260720`;
2. corrects the linked row's spelling;
3. deletes only the exact orphan row;
4. adds one-profile-per-hotel uniqueness.

No profile is assigned to Hotel Apex automatically because the orphan row clearly
belongs to VD Stay Inn.

### 2. Room 102

The active session had not expired when the audit ran. Room 102 was therefore
incorrectly marked `available`. The migration archives the original room row and
changes the room to `occupied` only if the exact active session still exists and
its checkout/extension time is still in the future.

### 3. Platform administrator

The same Auth user had two memberships in VD Stay Inn:

- `super_admin`
- `Manager`

A platform administrator is not a hotel role. The migration creates
`platform_admins`, archives/removes only the duplicate `super_admin` hotel
membership, and retains the valid Manager membership and Manager staff record.

### 4. Invoices

The 15 mismatches are all draft records marked paid with:

- `paid_amount = 0`
- `pending_amount = 0`
- no invoice items
- no linked payment collections in the previous audit

They are not changed in this migration. Automatically changing either the paid
amount or payment status would invent financial history. They remain a declared
Day 11 billing-reconciliation task.

### 5. Reception staff without Auth

The active Reception record is retained. The correct solution is to invite/link
a real Supabase Auth user through the Day 6 staff identity workflow, not to
silently disable or fabricate an Auth account.

### 6. Subscription mismatch

VD Stay Inn remains `subscription_status = active` without a normalized
`hotel_subscriptions` row. No plan is guessed. The Day 9 subscription migration
will introduce controlled legacy entitlement, plan assignment and lifecycle
events.

## RLS scope in this migration

The migration secures internal operational and financial tables now.

The following guest-facing tables remain temporarily compatible with the
existing anonymous room-number URLs:

- rooms
- guests
- guest_sessions
- hotel_info
- feedback
- menu_categories
- menu_items
- food_orders
- food_order_items
- service_requests
- notifications

They will be hardened after the secure QR token model is implemented. Enabling
strict RLS before replacing the current public URL model would break real guest
flows without actually providing a complete secure alternative.
