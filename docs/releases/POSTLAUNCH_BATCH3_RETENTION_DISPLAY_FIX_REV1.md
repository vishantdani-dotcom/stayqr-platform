# StayQR Post-Launch Batch 3 — Retention Display Fix REV1

## Confirmed root cause

Staging database acceptance passed 8/8 and all active `guest_documents` rows
have a non-null `retention_until`.

The browser still displayed `Retention —` because `retention_until` is a
`timestamptz`, while `formatDateOnly()` appended `T00:00:00` to every value.
For a timestamp such as:

`2027-08-21T08:07:39.000Z`

the old formatter attempted to parse:

`2027-08-21T08:07:39.000ZT00:00:00`

which is invalid and intentionally fell back to `—`.

## Fix

- `YYYY-MM-DD` values continue to be treated as date-only values.
- ISO timestamps are parsed directly.
- No KYC data is changed.
- No retention policy is changed.
- No database migration is re-run.
- Production remains untouched.
