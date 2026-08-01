StayQR v1.0 — Day 10 Arrivals & Departures Final Hardening REV1

CONFIRMED DEFECT
----------------
The Overdue queue correctly received direct walk-in rows from Migration 031,
but the generic Open action always routed to Reservations using reservation_id.

Direct walk-in rows have:
- operation_source = walk_in
- reservation_id = NULL
- guest_session_id populated

Therefore Room 108 incorrectly opened an empty Reservations page.

CORRECTIONS
-----------
- Direct walk-in booking links and action buttons route to Guests with the
  authoritative guest_session_id.
- Reservation-linked rows continue to route to Reservations.
- Direct stays show "Open stay"; reservations show "Open booking".
- Reservation-linked in-house rows may still separately open the active stay.
- Direct in-house rows no longer show duplicate Open stay buttons.
- Overdue rows display:
    Overdue Departure
    Late Checkout
    Missed Arrival
    Late Arrival
- Overdue duration is displayed from minutes_overdue.
- The frontend prefers the canonical overdue_exceptions key and retains the
  legacy overdue_arrivals fallback.
- Table row keys use reservation_room_id, guest_session_id, reservation_id or
  reservation_number instead of the previous null-only direct-walk-in key.
- Check-in remains available only for reservation arrival exceptions.

INSTALL
-------
1. Stop Vite with Ctrl+C.
2. Put the ZIP in:
   C:\Users\HP\Documents\StayQR
3. Extract with overwrite:
   Expand-Archive `
     -Path .\StayQR_Day10_Arrivals_Departures_Final_Hardening_Frontend_REV1_PATCH.zip `
     -DestinationPath . `
     -Force
4. Run:
   cd .\Frontend
   npm run check
5. Start:
   npm run dev

EXPECTED CHECK
--------------
- ESLint: 0 errors
- Existing 16 React Hook warnings may remain
- Day 7 security: 15/15
- Day 8 onboarding: 14/14
- Day 9 commercial source gate passes
- Day 10 source gate:
    62 required contracts
    13 unsafe patterns blocked
- Local QR test: 5/5
- Vite build passes on the user's Windows installation

BROWSER ACCEPTANCE
------------------
1. Open Arrivals & Departures.
2. Business date: 30/07/2026.
3. Click Refresh.
4. Open Overdue.
5. Confirm:
   - Room 102: Overdue Departure
   - Room 101: Overdue Departure
   - Room 108: Late Checkout
   - Each row displays an overdue duration.
6. Click Open stay on Room 108.
7. Expected:
   - Navigates to Guests.
   - Day10 Walkin Test Guest / Room 108 is focused.
   - It must not navigate to Reservations.

Do not move, extend or check out Rooms 107 or 108 during this test.
