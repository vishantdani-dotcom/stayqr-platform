# StayQR v1.1-A — Revenue, Reservation & Finance Growth

Status: IMPLEMENTATION PACKAGE PREPARED — STAGING FIRST

## Scope delivered

1. Direct website booking
   - public `/book/<hotel-slug>` route
   - hotel-controlled enable/disable and stay/deposit rules
   - server-side availability and price calculation
   - idempotent reservation creation
   - anonymous surface exposes RPCs only, never direct table access
   - direct booking disabled by default

2. Corporate profiles and negotiated rates
   - corporate accounts and unique booking codes
   - negotiated room/rate-plan pricing with validity/min/max stay rules
   - corporate booking links
   - reservation-to-corporate rate snapshot evidence

3. Split-stay refinement
   - planned room move register for active stays
   - target-room commitment check for planned date
   - preserves the existing authoritative atomic room-move RPC
   - plan becomes verified only after the real room move is completed

4. Split-bill refinement
   - 2–10 payer shares against one authoritative folio
   - share total must equal current folio balance
   - payer-specific collections call the existing Day 11 collection helper
   - payer retry is idempotent and cannot double-increment the share

5. Accounting templates/connectors
   - StayQR Standard
   - Tally Import
   - Zoho Books
   - QuickBooks
   - generated from existing immutable invoices/accounting export infrastructure

## Preserved v1.0 invariants

- no replacement of existing reservation CRUD RPCs
- no replacement of room inventory allocation/exclusion logic
- no replacement of atomic active-stay room move
- no replacement of folio collection or folio split collection
- no replacement of invoice/accounting source data
- tenant isolation remains hotel-scoped
- production is outside this batch until future explicit authorization
