# Day 3 — Reservation CRUD and Rate Quotation UI

## Included functionality

- Reservations navigation and hotel-scoped booking register.
- Advance and walk-in reservation entry modes.
- Existing guest search by name, phone, email or identity number.
- New guest creation with duplicate-profile detection by exact phone/email.
- Arrival, departure, adults, children, room-type and room search.
- Live reservation-aware availability from the Day 3 RPC.
- Base and seasonal rate quotation with occupancy supplements.
- Booking source, source reference, guest requests and internal notes.
- Deposit requirement, initial collection and additional collection on edit.
- Reservation detail drawer with rooms, amount, deposits and activity log.
- Modification with optimistic concurrency using `updated_at`.
- Cancellation with mandatory reason.
- No-show workflow and room release.
- Loading, empty, error, permission and stale-record feedback.

## Scope boundary

Day 3 supports one room per reservation. The Day 2 database remains capable of
multiple rooms, but group/multi-room booking and reservation-to-check-in are Day
5 roadmap systems.

Tax and discount values remain zero because hotel-specific financial rules are
not invented by the Reservation UI.

## Build evidence

The patched source passed:

- ESLint: 0 errors, 18 pre-existing warnings.
- Vite production build: successful.
- 311 modules transformed.

The remaining bundle-size warning belongs to the production performance sprint.
