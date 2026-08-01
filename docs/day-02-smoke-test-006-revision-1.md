# Smoke Test 006 — Revision 1

The original script failed with:

`ERROR 42P01: relation "stayqr_reservation_smoke_result" does not exist`

The original test depended on a temporary result table. The revised test uses a
private function, validates allocation and overlap rejection, removes its own
test rows, and returns three result rows.

Expected:

- `cleanup_completed = true`
- `first_allocation_created = true`
- `overlapping_allocation_rejected = true`
