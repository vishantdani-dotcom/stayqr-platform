# Day 3 Deposit Trigger Corrective Migration

Verification 008 passed. During review before running Exit Test 009, the original
deposit trigger was found to have a DELETE edge case.

PostgreSQL supplies:

- `NEW` for INSERT;
- `OLD` and `NEW` for UPDATE;
- `OLD` for DELETE.

The original function attempted to use `COALESCE(NEW..., OLD...)`, which is not
a safe way to access trigger records during DELETE.

Migration 004:

- uses explicit `TG_OP` branches;
- recalculates the correct reservation after insert, update or delete;
- supports a future trusted workflow that moves a payment between reservations;
- remains safe when reservation deletion cascades to deposit deletion.

No existing business records are modified by the migration.
