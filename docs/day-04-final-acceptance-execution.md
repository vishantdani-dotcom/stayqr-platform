# Day 4 Final Acceptance Execution

Day 4 is complete only after every database row and every browser item below passes.

## A. Apply and verify code hardening

1. Apply migration `202607230006_day4_acceptance_hardening.sql`.
2. Run audit `016_day4_final_acceptance_gate.sql`.
3. Expected: 10 rows, every `passed = true`.

## B. Create controlled browser acceptance data

1. Run audit `017_seed_day4_browser_acceptance.sql` once.
2. Record the returned `date_to_open`, hotel, room-type filter and temporary room prefix.
3. Do not rerun 017 while the state exists.

## C. Browser acceptance checklist

### Views, navigation and layout

- Open Day view on `date_to_open`; one date column appears.
- Open Week view; seven date columns appear.
- Open Month view; the selected month appears and horizontal scrolling works.
- Previous, Next, Today and date picker work.
- Scroll horizontally: room column remains visible.
- Scroll vertically: date header remains visible.
- Navigate to the next room page and back; distinct room ranges appear.

### Statuses, legend and filters

- Draft, Tentative, Confirmed, Checked In and Checked Out cards appear.
- Cancelled and No Show appear as non-inventory historical cards.
- Maintenance, Operational and Out of Order blocks appear.
- Direct Stay appears with its actual status.
- Legend text and card colours correspond.
- Filter each status individually.
- Filter to the returned room type.
- Toggle Active blocks / All block statuses.
- Clear filters resets room type, statuses and block toggle.
- No records from another hotel appear.

### Quick details and exact navigation

- Reservation details show booking number, guest, dates, room/type, status, source, amount, deposit and notes.
- Open Reservation navigates to Reservations and automatically opens the exact record.
- Direct Stay details show current status.
- Open Guest Stay navigates to Guests and highlights the exact session.
- Block details show room, type, dates, reason, status, Created by, Created at and actions.
- Block details do not show Guest or Phone placeholders.

### Allocation, drag and block workflows

- Drag the unallocated queue card to a compatible temporary room/date.
- Queue count decreases and exactly one allocation appears.
- Valid same-type drag preserves stay length and persists after Refresh.
- Invalid different-type or overlapping drag is rejected and reloads the authoritative position.
- Reassign / Move preselects the current room and displays proposed checkout.
- Cancel the seeded Operational block with a mandatory reason.
- The cancelled block no longer occupies inventory and appears under All block statuses.

### Calendar invalidation

Using the seeded records and one controlled UI record:

- Create a reservation using source reference `DAY4-ACCEPT-UI-CREATE` and an existing acceptance guest.
- Return to Calendar; the new reservation appears.
- Edit `DAY4-ACCEPT-CONFIRMED-EDIT-CANCEL`; the changed dates/room appear.
- Cancel it; it stops occupying inventory.
- Mark `DAY4-ACCEPT-CONFIRMED-NOSHOW` no-show; it stops occupying inventory.

### Runtime

- Open DevTools Console before testing.
- Clear the console.
- Perform the touched flows.
- Final console has no new red errors.

## D. Cleanup

1. Run `018_cleanup_day4_browser_acceptance.sql`.
2. Expected JSON: every remaining count is 0.
3. Run read-only `019_verify_day4_browser_acceptance_cleanup.sql`.
4. Expected JSON: every remaining count is 0.

## E. Repository closure

1. Run `npm run check`.
2. Expected: zero errors; existing warnings only; build succeeds.
3. Commit and push.
4. Confirm `git status` reports a clean working tree.
5. Optional closure tag: `day-04-booking-calendar-complete`.
