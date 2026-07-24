# StayQR Day 5 — UI Integration Package

Built from the exact uploaded post-Day-4 source plus the verified Day 5 foundation.

## Apply

Overlay this complete `Frontend` folder onto the current project. The package excludes
`.env`, `node_modules`, `dist`, `.git` and temporary backups.

## Database

Run, in order:

1. `supabase/migrations/202607240008_day5_operations_and_confirmation_hardening.sql`
2. `supabase/audit/021_verify_day5_ui_integration_contracts.sql`

Every audit row must show `passed = true`.

## Local gate

Run:

```powershell
npm run check
npm run dev
```

Expected lint result: zero errors and the same 18 pre-existing warnings.

## First browser checks

- Open **Arrivals & Departures** from the sidebar.
- Confirm the selected hotel is consistent with the sidebar and navbar.
- Change business date and verify all six queues reload.
- Open a confirmed reservation from the queue.
- In Reservation Details, verify room cards, Add Room, PDF, Print and WhatsApp actions.
- Do not perform a real reservation check-in until deterministic Day 5 acceptance data is prepared in the next stage.
