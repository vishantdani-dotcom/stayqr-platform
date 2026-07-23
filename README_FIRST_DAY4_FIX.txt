StayQR Day 4 Complete Frontend Fixed v5

This complete Frontend folder includes all v4 corrections plus the historical block lane correction.

Latest correction:
- Active reservation cards and released/cancelled block cards no longer overlap when All block statuses is enabled.
- Non-inventory records render in compact historical lanes beneath the active inventory lane.
- Multiple historical records are lane-packed by date range.
- Expanded rows retain complete drag/drop coverage.

Apply by overlay-copying the contents of this Frontend folder into your existing Frontend folder. Preserve the existing .env and node_modules. Then run:

npm run check
npm run dev
