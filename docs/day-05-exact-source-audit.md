# Day 5 exact-source audit

## Audited baseline

- Branch source supplied after Day 4 hotel-switcher closure.
- Reservation foundation and CRUD migrations: `202607200002`–`202607220004`.
- Calendar/allocation migrations: `202607230005`–`202607230006`.
- Current frontend: React/Vite/Supabase with hotel context remounting.

## Critical baseline findings

1. `CheckIn.jsx` performs guest insert, session insert, payment insert and room update as separate browser requests. A late failure can leave partial records.
2. Reservation records already contain `guest_sessions.reservation_id` and `reservation_room_id`, but no production check-in RPC uses them.
3. Reservation deposits are stored separately in `reservation_payments`; no immutable link transfers them into the stay payment/collection flow.
4. The current create/edit UI and Day 3 RPCs are intentionally single-room. The normalized schema already supports multiple `reservation_rooms`, so Day 5 must add controlled room-level operations rather than replace the model.
5. Checkout currently completes the guest session and marks the room for cleaning, but does not authoritatively advance linked reservation-room/header status.
6. There is no hotel-scoped arrivals/departures read model and no authoritative reservation-confirmation snapshot.

## Day 5 foundation decision

Migration `202607240007_reservation_checkin_folio_operations.sql` adds:

- Atomic reservation-room check-in.
- Idempotent guest-session and room-charge creation.
- Partial, traceable reservation-deposit transfer into existing payment collections.
- Group/multi-room add and remove RPCs.
- Arrivals/departures operational read model.
- Authoritative confirmation snapshot.
- Checkout-to-reservation and room-status synchronization.

The existing direct walk-in form remains available during integration, but reservation check-in must use the new transactional RPC.
