# Day 3 — Reservation CRUD Transaction Architecture

## Scope of Migration 003

The migration adds the trusted database API required by the Reservation UI:

- transactional create reservation;
- transactional modification with optimistic concurrency;
- cancellation and no-show status actions;
- secure guest search and guest creation;
- reservation-aware room availability;
- base/seasonal rate and occupancy quotation;
- deposit records and automatic collected-total synchronization;
- reservation list/detail APIs;
- activity logging.

## Atomicity

All public write operations are PostgreSQL functions. A failure in guest
creation, reservation header, room allocation, deposit, status or activity log
rolls back the complete operation.

## Single-room boundary

Day 3 intentionally supports one physical room per reservation. The underlying
Day 2 database is multi-room capable, but group/multi-room booking is the Day 5
integration scope.

## Rate calculation

The quotation function uses:

- the selected active rate plan;
- seasonal date overrides;
- extra-adult rates above room-type base occupancy;
- child rates;
- one row per occupied night.

Tax and discount remain zero in the Reservation quote because hotel tax and
discount policy belongs to the Billing configuration sprint. StayQR does not
invent financial rules.

## Deposit boundary

Deposits are stored in `reservation_payments`, separate from the existing final
stay/payment ledger. They are transferred into the stay folio during the Day 5
reservation-to-check-in transaction.

## Activity logs

Reservation create, update, cancellation and no-show actions record the actor,
hotel, before/after snapshot and metadata. Browser clients have read-only RLS
access to these logs; writes are trusted-function only.
