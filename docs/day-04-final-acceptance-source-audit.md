# Day 4 Final Acceptance — Exact Source Audit

## Source audited

`StayQR_Day4_Final_Acceptance_Source.zip`, uploaded after commit `22a6989`.

## Already implemented and retained

- Day, week and month ranges.
- Sticky room column and sticky date header.
- Horizontal scrolling and 18-room pagination.
- Hotel, room-type, reservation-status and block-status filters.
- Reservation, room-block and direct-stay events.
- Unallocated queue with manual and drag assignment.
- Server-validated movement with tenant, status, room type, capacity, stale-update, rate and overlap checks.
- Room-block create, update, release and cancel RPCs.
- Authoritative reload after calendar actions and reservation invalidation events.
- Dedicated drag handle, compact drag preview and target details.

## Gaps found and corrected by this patch

1. **Open Reservation did not open the selected reservation.** It only changed the section. Navigation now carries the reservation ID and opens its detail drawer.
2. **Open Check-In / Stay did not open the selected stay.** It only changed the section. The action now opens Guests and highlights the exact guest session, including historical sessions when requested.
3. **Room-block details did not display Created by.** Migration `202607230006` adds human-readable actor names and the UI displays Created by and Created at.
4. **Cancelled block reason was labelled Release reason.** The label now follows the block status.
5. **Direct-stay event cards displayed Checked In regardless of actual session status.** They now use the returned session status.
6. **Unallocated cards did not show guest count.** Adults and children are now visible.
7. **Drag target cleanup was not explicit when leaving a cell.** `onDragLeave` now clears the stale target safely.
8. **Remaining backend acceptance checks were not executable as a dedicated gate.** Audit `016` tests filters, stale updates, capacity, rate-changing moves, no partial activity, block actor display and cancellation.
9. **Remaining browser checks lacked a reproducible dataset.** Audits `017–019` provide isolated seed, cleanup and verification workflows.

## Boundary clarification

Room physical status reconciliation and expiry of stale active guest sessions belong to the Check-In/Out transaction owned by Day 5. Day 4 represents authoritative stay dates and allocation records but does not silently close stays or change physical room status.
