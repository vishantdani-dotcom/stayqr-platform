# StayQR v1.1 — Master Execution Plan

Status: PLANNING STARTED

## Release boundary
StayQR v1.0 remains production-maintenance only. v1.1 planning and development happen on dedicated non-production branches and staging until an explicit future production release decision.

## Authoritative v1.1 candidate set
The v1.0 deferred roadmap retained the following for the first 30–60 days:
1. Direct website booking widget
2. Corporate profiles / negotiated rates
3. Split-stay and split-bill refinements
4. Laundry / lost-and-found
5. Scheduled reports
6. WhatsApp Business API
7. Simple inventory
8. KOT printer improvements
9. Multi-property group view
10. Safe support session
11. Accounting connectors / CSV templates
12. Additional operational refinements justified by real usage

## Execution rule
Do not duplicate foundations already built during v1.0 or post-launch stabilization. Every module first receives a current-source/schema audit and is classified as:
- ALREADY COMPLETE
- FOUNDATION EXISTS / EXTEND
- PARTIAL / REPAIR
- NEW BUILD
- DEFER

## Three large execution batches

### Batch V1.1-A — Revenue, Reservation & Finance Growth
- Direct website booking widget / booking engine
- Corporate profiles and negotiated rates
- Split-stay refinements
- Split-bill / folio allocation refinements
- Accounting CSV templates/connectors foundation

Definition of done:
- tenant-safe database contracts
- no double-booking regression
- pricing/rate authority preserved
- folio/invoice equations remain authoritative
- staging E2E for direct booking → reservation → check-in → settlement
- corporate-rate test
- split-stay/bill reconciliation tests
- exports reconcile to source records

### Batch V1.1-B — Hotel Operations & Automation
- Laundry workflow
- Lost-and-found workflow
- Simple consumable/inventory stock
- KOT / kitchen printer improvements
- Scheduled reports

Definition of done:
- department ownership and staff permissions
- audit trail
- guest/folio posting only where applicable
- inventory movement is transactional and tenant-scoped
- scheduled report jobs are retryable/idempotent
- staging operational E2E

### Batch V1.1-C — Platform, Communication & Multi-Property
- WhatsApp Business API production-grade integration
- Multi-property group view refinements
- Safe audited support session / View as Hotel refinement
- cross-property operational/reporting controls where justified

Definition of done:
- explicit consent / opt-out for promotional messaging
- template and delivery/failure tracking
- audited, time-limited support access
- strict hotel isolation
- multi-property authorization tests
- provider failure containment
- staging E2E and rollback evidence

## Release gates
Each large batch gets one consolidated gate:
source/schema discovery → implementation → RLS/security → lint/build → staging database → browser/mobile E2E → evidence lock.

Production is excluded until a future explicit v1.1 release authorization.

## Priority
Start with V1.1-A after the kickoff discovery report is reviewed because it directly expands revenue acquisition and reservation/finance capability while using the strongest existing StayQR foundations.
