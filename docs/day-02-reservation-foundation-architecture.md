# StayQR Reservation Foundation — Architecture Decision

## Inventory source of truth

`room_inventory_allocations` is the authoritative ledger for room occupancy.

It contains active date ranges originating from:

1. reservation room allocations;
2. operational/maintenance room blocks;
3. direct guest stays that were not created from a reservation.

A PostgreSQL GiST exclusion constraint prevents two active allocations for the
same room from overlapping. This is database protection, not merely a frontend
availability check.

## Why a reservation keeps room and room-type data

`reservation_rooms` stores both:

- the requested room type; and
- the assigned physical room.

Draft records may remain unassigned. Tentative, confirmed and checked-in records
create an inventory allocation when a physical room is assigned. The upcoming
transactional Reservation API will automatically select a valid room when
confirmation is requested without an explicit assignment.

## Existing PMS compatibility

The migration retains `rooms.room_type` so the current Rooms, Check-In,
Dashboard and Guest pages continue working. It adds `room_type_id` as the
normalized relation that all new Reservation and Rate systems use.

## Rate policy

The migration creates one Standard Rate plan for each existing room type, but
sets its rate to zero because the old schema contains no authoritative room
rate. StayQR must not invent hotel prices. Rate configuration becomes the first
step of the Reservation settings UI.

## Active stays

Existing direct Check-In creates `guest_sessions`. A trigger now synchronizes
active direct stays into the inventory ledger. Reservation-linked check-ins will
continue using the reservation allocation, avoiding duplicate overlap records.

## Next implementation

After this migration and smoke test pass, the next patch will add:

- Reservation service functions;
- atomic create/modify/cancel/no-show operations;
- automatic room assignment;
- advance/deposit records;
- React Reservation pages and calendar integration.
