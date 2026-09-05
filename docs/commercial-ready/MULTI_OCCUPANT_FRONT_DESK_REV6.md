# StayQR Multi-Occupant Front Desk REV6

## Scope

This batch completes the simple front-desk model for couples, families and groups sharing one room.

- One room/stay remains anchored to one primary guest.
- Any number of accompanying occupants can be added within room-capacity rules.
- Adults can scan/upload an ID through the same backend OCR provider used by the primary guest.
- Children/infants can be added with basic details; ID capture remains optional in the UI.
- Each companion is still resolved/created as an independent `guests` profile.
- Each captured ID is saved privately against the correct guest profile.
- The same `guest_session_id` links the whole room stay.
- The atomic `check_in_walk_in_guest` contract is preserved.
- The RPC result now includes a `companions` mapping with frontend `client_id` -> persisted `guest_id`.
- `register_guest_document` now accepts the shared stay session when the document owner is a persisted companion of that session, so companion IDs remain tied to both the individual profile and the room stay.
- Guest Profile stay history now includes stays where the selected guest participated as a companion.
- No UIDAI/OTP/government verification claim is introduced.
- Raw OCR text is not persisted by this workflow.

## Staging migration

`202609050112_multi_occupant_checkin_result_contract_REV1.sql`

The migration replaces only the existing `check_in_walk_in_guest(uuid,jsonb)` function body to extend its result contract. It does not create a second stay or second room allocation for companions.

## Acceptance matrix

1. Single guest
2. Couple: primary + one adult companion
3. Family: primary + adult + child
4. Per-adult OCR/autofill
5. Individual private ID document persistence
6. One room / one guest session
7. Independent companion guest profiles
8. Companion profile shows shared stay history
9. Existing room-capacity enforcement remains authoritative
10. No full Aadhaar exposure / no government verification claim
