# Day 2 Reservation & Availability Exit Gate

Run `007_day2_reservation_availability_exit_gate.sql` after Smoke Test 006.

The suite returns fifteen test rows covering:

1. room availability before booking;
2. room removal after booking;
3. room-type inventory reduction;
4. room return after release;
5. booking-number generation;
6. nightly rate quote;
7. status history;
8. reservation-overlap rejection;
9. room-block-overlap rejection;
10. adjacent date acceptance;
11. room block availability impact;
12. reservation rejection against a block;
13. identical dates across two hotels;
14. unaffiliated access denial;
15. complete test-data cleanup.

Every row must show `passed = true`.

The test selects far-future dates, restores reservation-number sequence values,
and deletes every test reservation, room block and inventory allocation before
returning.
