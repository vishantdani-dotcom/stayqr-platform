# Day 4 invalid-drag rejection correction

This correction closes the remaining Day 4 browser UX defect where dropping a reservation over an occupied reservation/block card could bypass the room/date drop-cell handler.

## Corrected behaviour

- The entire room timeline row is now a drop surface, including areas covered by reservation and room-block cards.
- The proposed date is calculated from the pointer position within the room timeline.
- Server-side overlap, room-type, capacity, stale-update and rate-change rejections are surfaced in a visible error toast.
- Drag preview and target highlighting are cleared after success, rejection, cancellation and drag end.
- A previous toast timer can no longer prematurely clear a newer rejection message.
- Structured RPC responses with `success: false` or `ok: false` are treated as rejections.
- Calendar data reloads from the authoritative server after a rejected move.

## Browser retest

Drag `RES-2032-000009` from Room `D4QA-A7219E-13` to the blocked dates in Room `D4QA-A7219E-09`.

Required result:

1. A red rejection toast appears with the server reason.
2. The reservation remains in Room 13 for 11–13 Nov 2032.
3. Room 09's Operational Block remains unchanged.
4. Assignment Queue remains 0.
5. No duplicate reservation, stale compact preview or yellow target box remains.
6. Refresh shows the same authoritative allocation.
