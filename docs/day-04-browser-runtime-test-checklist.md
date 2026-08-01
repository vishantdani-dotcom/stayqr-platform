# Day 4 Browser Runtime Test Checklist

Do not mark Day 4 complete until every item passes.

## Initial rendering

- Booking Calendar appears in sidebar and navbar breadcrumb.
- Correct hotel name is visible.
- No Hotel Access Required screen.
- No red console error.
- Two existing direct stays appear on their correct rooms/dates.

## Views and filters

- Day view shows one date.
- Week view shows seven dates.
- Month view shows the selected month.
- Previous, next, Today and date picker work.
- Room-type filter works.
- Reservation-status chips work.
- Active/all block toggle works.
- Clear filters resets all filters.

## Timeline correctness

- Checkout date does not occupy an additional night.
- Reservation click opens quick details.
- Direct stay click opens quick details.
- Status legend matches event appearance.
- Room pagination works if multiple pages are available.

## Room blocks

- Create a future block on a free room.
- Block appears immediately.
- Edit block dates/reason.
- Overlapping block is rejected.
- Adjacent block is accepted.
- Release block and confirm inventory is restored.
- Cancel flow records a mandatory reason.

## Allocation and movement

- Create a temporary tentative/unallocated reservation.
- It appears in the queue.
- Assign it using the button workflow.
- Reassign it using drag-and-drop.
- Invalid overlap is rejected.
- Rejected card returns to authoritative position.
- Stale-update rejection prompts refresh.
- Rate-changing date move is rejected.

## Calendar invalidation

- Create reservation in Reservations and return to Calendar.
- Edit reservation and confirm new dates/room.
- Cancel reservation and confirm it no longer occupies inventory.
- Mark no-show and confirm it no longer occupies inventory.

## Closure

- Runtime test data removed.
- `npm run check` passes.
- No new console errors.
- Commit pushed.
- Working tree clean.
