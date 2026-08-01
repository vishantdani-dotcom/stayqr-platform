# Day 5 browser acceptance seed

Run `supabase/audit/022_seed_day5_browser_acceptance.sql` after migrations 007 and 008 and audits 020 and 021 pass.

The seed creates current-date records under VD Stay Inn when available:

- Four Today Arrivals rows: one atomic/deposit candidate, two rows under one group booking, and one unavailable-room rejection candidate.
- One Upcoming Arrival.
- One In-House room.
- One Unallocated arrival.
- One Overdue arrival.
- One departure when Business Date is moved to the following date.

Do not run cleanup until browser acceptance is complete. Cleanup is audit 023 and read-only cleanup verification is audit 024.
