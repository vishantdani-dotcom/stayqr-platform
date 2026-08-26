# StayQR Batch 3 Retention Display Fix REV2

REV1 correctly patched the timestamp formatter but its source acceptance gate
used an overly specific JSX expression for the KYC card and stopped at 4/5.

REV2 changes only that false-negative gate:
- verifies `retention_until` is actually consumed by GuestDirectory source;
- verifies the retention presentation remains present;
- keeps the timestamp parser checks authoritative.

No database change is repeated. Production remains untouched.
