# Day 4 cleanup SQL correction

Corrects the inventory-allocation verification join in audit files 014 and 015.

Incorrect relationship:

`room_inventory_allocations.reservation_id`

Correct relationship:

`room_inventory_allocations.reservation_room_id -> reservation_rooms.id -> reservations.id`

File 014 is also idempotent: it safely returns an all-zero report when the exact test reservation has already been removed.
