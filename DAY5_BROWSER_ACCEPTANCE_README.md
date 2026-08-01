# StayQR Day 5 browser acceptance package — corrected

This package adds:

1. Explicit high-contrast headings for Arrivals & Departures and its active queue.
2. `022_seed_day5_browser_acceptance.sql` for deterministic runtime records.
3. A safe temporary positive rate-plan fallback when the selected property has no usable active rate plan.
4. `023_cleanup_day5_browser_acceptance.sql` for controlled cleanup, including a temporary acceptance rate plan.
5. `024_verify_day5_browser_acceptance_cleanup.sql` for the final zero-count proof.

The previous failed seed call did not create partial records. Apply by overlay-copying the complete Frontend folder, preserve the existing `.env` and `node_modules`, and rerun audit 022.
