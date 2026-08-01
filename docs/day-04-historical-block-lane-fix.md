# Day 4 — Historical block lane correction

## Problem

When **All block statuses** was enabled, a released or cancelled room block could occupy the same room/date columns as a valid active reservation. Both cards were rendered in the same visual lane, so their text and action handles overlapped even though only the reservation occupied inventory.

## Correction

- Active inventory events remain in the primary 82 px room timeline lane.
- Released, cancelled and other non-inventory events are allocated to compact historical lanes below the primary lane.
- Historical events are lane-packed by date range, so non-overlapping records reuse a lane and overlapping historical records remain individually readable.
- Room rows expand only when visible historical records require additional lanes.
- Drop cells span the complete expanded room row, preserving drag-and-drop targeting.
- Historical cards retain their striped, reduced-opacity treatment and remain clickable for audit details.

## Acceptance result

An active reservation and a cancelled/released block may share the same room and dates without visual collision. Historical blocks remain visible in **All block statuses** mode while never appearing to occupy active inventory.
