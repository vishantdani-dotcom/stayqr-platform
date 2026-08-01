# StayQR Day 1 — Data Quality Preflight Result

## Result

The production dataset is substantially cleaner than the schema-security posture.

### Clean checks

- No duplicate room numbers within a hotel.
- No multiple active guest sessions in one room.
- No orphan or cross-hotel active guest-session relationships.
- No cross-hotel food order or food-item relationships.
- No cross-hotel service request, housekeeping, invoice, payment,
  payment collection, manual charge, or menu-item relationships.
- No negative payment, collection, food, invoice, or manual-charge amounts.
- Legacy `room_sessions` contains zero rows and is not active.

### Remaining decision areas

1. **One `hotel_info` row has no `hotel_id`.**
   It must not be assigned automatically until its content is compared with
   the two existing hotels. It may be a legacy prototype profile rather than
   the missing profile of the trial hotel.

2. **One active guest session conflicts with Room 102.**
   The room is marked `available` while the session is `active`. The exact
   check-out/extended date decides whether the session should be expired or
   the room should be marked occupied.

3. **Fifteen invoice balances do not reconcile.**
   The repair depends on invoice status, payment status, linked collections,
   and whether these are historical draft records. The targeted audit returns
   the exact non-PII financial fields.

4. **Identity and subscription mapping require review.**
   - One active staff row has no `auth_user_id`.
   - One hotel membership email differs from the linked Auth email.
   - One Auth user belongs to two hotels. This is not automatically an error:
     multi-hotel membership is a legitimate SaaS capability. The future unique
     rule must be `(hotel_id, user_id)`, not global uniqueness on `user_id`.
   - The operational hotel reports `subscription_status = active` but has no
     current `hotel_subscriptions` row.
   - The trial hotel has a current subscription but no rooms, profile, staff,
     or active membership.

## Decision

No production mutation is applied yet. Run the targeted read-only audit so the
first repair migration can be explicit, guarded, reversible, and based on the
actual affected records.
