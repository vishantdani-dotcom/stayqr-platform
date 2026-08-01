# StayQR Day 1 — Production Schema Audit Findings

Generated from the Supabase schema snapshot exported on 20 July 2026.

## Baseline

- Public tables: **27**
- Tables containing `hotel_id`: **22**
- Tables with RLS enabled: **9/27**
- RLS policies: **18**
- Public database functions: **0**
- Triggers: **0**

## Critical findings

1. **RLS is disabled on 18 of 27 public tables.**
   Core tables including `hotels`, `rooms`, `guests`, `guest_sessions`,
   `payments`, `invoices`, `staff`, and `service_requests` currently have RLS disabled.

2. **Existing policies are not tenant-safe.**
   Broad `public` policies allow unrestricted reads/writes on:
   `food_order_items, food_orders, invoice_items, menu_categories, menu_items, payment_collections`.

3. **Some RLS-enabled tables have no policy.**
   `hotel_users`, `housekeeping_requests`, and `room_sessions` have RLS enabled
   but no visible policy in the snapshot. Normal browser access may be blocked
   while trusted/postgres access still works.

4. **Most tenant ownership columns are nullable.**
   `hotel_id` is nullable on 19 tenant-owned tables:
   `analytics_events, feedback, food_orders, guest_sessions, guests, hotel_info, hotel_subscriptions, hotel_users, housekeeping_tasks, invoices, manual_charges, menu_categories, menu_items, notifications, payments, room_sessions, rooms, service_requests, staff`.

5. **There are no source-visible transactional functions or triggers.**
   The snapshot found 0 public functions and 0 triggers. Multi-table workflows
   such as Check-In, Checkout, reservation conversion, payment webhook handling,
   and hotel onboarding are therefore not protected by database transactions.

6. **Important uniqueness rules are absent.**
   The schema snapshot does not show a unique room number per hotel, unique
   `staff.auth_user_id`, unique `hotel_users.user_id`, unique role-permission
   pair, one hotel-info row per hotel, or one current subscription per hotel.

7. **Several cross-tenant relationships are not enforced.**
   A normal foreign key can prove that a row exists, but not that the guest,
   room, invoice, staff member, menu item, order, and payment belong to the same
   hotel. The preflight checks these relationships before tenant constraints/RLS
   are added.

8. **Legacy and duplicated concepts exist.**
   `guest_sessions` and `room_sessions` both represent room occupancy. `staff`
   and `hotel_users` both represent hotel membership. These require a controlled
   migration decision rather than further duplication.

9. **Guest/public access is currently too broad.**
   Food orders, order items, menu reads, notifications, invoice items and
   payment collections use policies that do not verify hotel, room, active stay,
   or a secure guest QR token.

10. **Reservation System must not be added on top of this security baseline.**
    Data must first be measured and cleaned, then the initial migration can
    safely introduce tenant helpers, constraints and reservation tables.

## Why Step 2 is read-only

Adding `NOT NULL`, unique constraints, foreign keys or RLS immediately could
break the existing hotel because we do not yet know:

- which tables contain null `hotel_id` values;
- whether duplicate room numbers or memberships exist;
- whether active room/session status is contradictory;
- whether financial rows belong to a different hotel than their guest/room;
- whether active staff records are connected to Supabase Auth;
- whether the legacy `room_sessions` table contains live data.

Run `supabase/audit/002_data_quality_preflight.sql`, export its one JSON result,
and upload it before applying any migration.
