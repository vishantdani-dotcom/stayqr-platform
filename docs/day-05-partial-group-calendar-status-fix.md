# Day 5 partial-group calendar status correction

## Browser finding

After checking in only Room `D5QA-5183A0-02` under group booking
`RES-2026-000002`, the authoritative operational queue and Rooms page were
correct:

- Room 02 was checked in and occupied.
- Room 03 remained confirmed and available.

The Booking Calendar still coloured Room 03 as Checked In because the Day 4
calendar payload exposed the reservation header status as the card status.
For a partially checked-in group booking, the header is `checked_in` while an
individual remaining room can still be `confirmed`.

## Correction

- Added `get_booking_calendar_room_status`.
- Reservation cards now expose `reservation_rooms.status` as `status`.
- The reservation header status remains available as `booking_status`.
- Calendar status filters now operate at reservation-room level.
- A mixed group booking can therefore show Room 02 as Checked In and Room 03
  as Confirmed under the same booking number.
- Calendar drag/reassignment controls remain disabled when the booking header
  is already checked in, avoiding a misleading action that the server would
  reject.
- Reservation list/detail badges display `Partially Checked In` when checked-in
  and pending room rows coexist.
