# Day 4 Platform Admin Hotel Switcher Runtime Fix

The first switcher package queried `staff.department`, but the production `staff` table does not contain that column. Supabase therefore rejected tenant-context loading after authentication and the application displayed **Hotel Access Required**.

This correction removes the nonexistent column from the canonical tenant-context query. Authentication credentials are unchanged.
