# StayQR v1.0 Status Dictionary

The application constants are in `src/constants/statuses.js`. Database checks
and trusted functions must remain aligned with this document.

## Hotels

`active`, `suspended`, `inactive`, `archived`

## Subscriptions

`trial`, `trialing`, `active`, `past_due`, `suspended`, `cancelled`, `expired`

## Rooms

`available`, `occupied`, `cleaning`, `maintenance`, `out_of_order`

## Reservations

`draft` → `tentative` or `confirmed` → `checked_in` → `checked_out`

Terminal alternatives: `cancelled`, `no_show`.

## Guest sessions

`active` → `completed`, `expired`, or `cancelled`

## Food orders

`pending` → `accepted` → `preparing` → `ready` → `out_for_delivery` →
`delivered`; permitted cancellation depends on the operational rule.

## Service requests

`pending` → `accepted` → `in_progress` → `completed`

Side states: `cancelled`, `escalated`.

## Housekeeping

`pending` → `assigned` → `in_progress` → `inspection` → `completed`

Side states: `blocked`, `cancelled`.

## Payments

`pending`, `partially_paid`, `paid`, `waived`, `refunded`,
`partially_refunded`, `failed`, `cancelled`

## Invoices

`draft`, `issued`, `partially_paid`, `paid`, `cancelled`, `void`, `credited`

## Rule

Status changes must be validated by the database or a trusted transaction.
UI labels alone are never authoritative.
