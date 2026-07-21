# Day 4 Exact Source Audit

Audited source: `StayQR_Day4_Current_Source.zip`

## Baseline evidence

- `npm ci` completed.
- `npm run check` passed.
- ESLint: 0 errors, 18 pre-existing hook warnings.
- Vite production build: 311 modules transformed.
- Day 3 Reservations UI and SQL migrations 003/004 are present.
- No Booking Calendar page or calendar service currently exists.

## Exact frontend integration points

Day 4 UI will require:

- `src/pages/calendar/BookingCalendar.jsx`
- `src/pages/calendar/BookingCalendar.css`
- `src/lib/bookingCalendar.js`
- `src/App.jsx`: import and render the `calendar` section
- `src/components/sidebar/Sidebar.jsx`: Booking Calendar navigation item
- `src/lib/currentStaff.js`: calendar access for owner, manager, reception,
  front desk and platform administrator
- a small application-level calendar invalidation event so successful
  reservation create/edit/cancel/no-show actions refresh an open calendar

## Existing backend capabilities reused

- Authoritative `room_inventory_allocations` ledger
- PostgreSQL exclusion constraint preventing active overlaps
- Reservation status and allocation triggers
- Day 3 transactional Reservation CRUD
- Hotel-scoped RLS helpers
- Generic immutable activity logs

## Production gap fixed by Migration 005

The existing database has no:

- paginated calendar read model;
- atomic calendar move/reassignment RPC;
- trusted room-block CRUD/release RPC;
- stale calendar update protection;
- explicit rejection of rate-changing drags;
- quick block detail RPC.

Migration 005 supplies these server contracts before any drag-and-drop UI is
built.
