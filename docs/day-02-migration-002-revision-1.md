# Migration 002 — Revision 1

## Failure observed

PostgreSQL error `42830` reported:

`there is no unique constraint matching given keys for referenced table "guests"`

## Root cause

The reservation schema correctly uses hotel-scoped composite foreign keys such
as `(hotel_id, guest_id) -> guests(hotel_id, id)`. PostgreSQL requires the
referenced column pair to be backed by a unique or primary-key constraint.

The original migration created composite parent keys for rooms, room types,
rates, reservations and reservation rooms, but omitted:

- `guests(hotel_id, id)`
- `guest_sessions(hotel_id, id)`

## Correction

Revision 1 creates:

- `uq_guests_hotel_id_id`
- `uq_guest_sessions_hotel_id_id`

before any reservation or inventory foreign key references them. The final
migration assertions and verification report also check both indexes.

## Database state after the failed attempt

The migration was wrapped in `BEGIN ... COMMIT`. Because PostgreSQL raised an
error before `COMMIT`, all statements from that attempt were rolled back. No
cleanup migration is required before running Revision 1.
