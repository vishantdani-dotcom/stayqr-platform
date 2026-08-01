# Day 4 Booking Calendar Architecture

## Date semantics

All timeline occupancy uses half-open date ranges: `[start, end)`.

A reservation from 22 July to 23 July occupies 22 July only. A new reservation
or block may begin on 23 July without overlapping it.

## Authoritative data

The browser never decides whether a move is valid. The database remains the
source of truth through `room_inventory_allocations` and its exclusion
constraint.

## Calendar read model

`get_booking_calendar` returns:

- paginated room rows;
- reservation events;
- active or historical room-block events;
- direct stays not linked to reservations;
- unallocated reservations;
- pagination metadata.

The UI may render day, week or month layouts from the same server model.

## Drag-and-drop contract

`move_reservation_on_calendar`:

1. checks hotel write access;
2. locks the reservation, reservation-room row and target room;
3. checks optimistic concurrency through `expected_updated_at`;
4. permits only tentative/confirmed single-room calendar moves;
5. requires a compatible room type and capacity;
6. preserves stay length;
7. recalculates the proposed quote;
8. rejects the drag if the rate total would change;
9. validates availability excluding the reservation's current allocation;
10. releases the old allocation;
11. changes dates/room atomically;
12. relies on the PostgreSQL exclusion constraint as the final protection;
13. records an activity log;
14. returns the authoritative updated reservation.

Any failure rolls back the entire transaction.

## Room blocks

Room blocks are created and edited only through trusted functions in the Day 4
UI. Active blocks create ledger allocations. Released/cancelled blocks release
those allocations and retain release reason, actor and time.

## Large-property handling

The read model supports server-side room pagination up to 100 rooms per page.
The frontend will use a smaller default page and sticky/horizontally scrollable
timeline, satisfying the roadmap requirement without loading every room at
once.
