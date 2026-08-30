# StayQR v1.1-B — Hotel Operations & Automation

Status: implementation package

## Scope delivered

1. Laundry operations
   - dedicated operational order number
   - active-stay/room/guest linkage
   - normal/express priority
   - pieces and item summary
   - promised time
   - received → washing → drying → ironing → ready → delivered lifecycle
   - cancelled state with reason
   - existing StayQR service/folio authority is preserved; this module does not create a second financial ledger

2. Lost & Found
   - tenant-scoped custody register
   - found location and optional room/guest linkage
   - storage location
   - stored → matched → claimed/returned/disposed/donated lifecycle
   - claimant and closure evidence

3. Simple inventory
   - SKU/name/category/unit/reorder level
   - on-hand quantity
   - receive/consume/adjust/waste/return movements
   - atomic row lock before stock movement
   - negative stock blocked
   - request-key idempotency for stock retries
   - low-stock visibility in the UI

4. KOT / printer improvements
   - reusable printer profiles
   - 58 mm / 80 mm width
   - 1–5 copies
   - station classification
   - default profile
   - keeps Day 15 `get_food_order_kot` authoritative
   - new print-event audit linked to the existing kitchen ticket/order
   - multi-copy print document generation

5. Scheduled reports
   - report job name, report key, frequency, lookback and next run
   - daily/weekly/monthly recurrence
   - idempotent job run identity `(job_id, scheduled_for)`
   - generated/failed run ledger
   - immutable JSON report snapshot using the existing Day 16 report export RPC
   - due-job reconciliation every 60 seconds while the Operations Automation workspace is open
   - explicit `Run due / force now` control for acceptance and recovery

## Security / architecture

- all new operational tables use RLS
- anonymous table and RPC access is denied
- authenticated users receive read-only direct table access through RLS
- all writes use tenant-scoped SECURITY DEFINER RPCs
- existing Day 15 KOT and Day 16 reporting RPCs are reused, not replaced
- no production URL or secret is added to the frontend
- no production deployment is part of Batch B implementation

## Source UI

A new `Ops Automation` v1.1 entry is added under Operations. Access is permission-aware for hotel owner/manager and relevant housekeeping, restaurant, reports and service roles.
