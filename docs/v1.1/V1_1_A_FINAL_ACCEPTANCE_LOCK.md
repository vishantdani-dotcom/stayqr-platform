# StayQR v1.1-A — Final Acceptance Lock

Status: **COMPLETE & LOCKED**

## Scope
V1.1-A — Revenue, Reservation & Finance Growth:
- Direct website booking
- Corporate profiles and negotiated rates
- Split-stay refinement
- Split-bill payer allocation and payer collections
- Accounting CSV / connector templates

## Authoritative source
- Feature branch before lock: `feature/v1.1-a-revenue-reservation-finance`
- Feature implementation commit: `71fcd86765ed87ddd88669d67c9acd0db2d13155`
- Final lock branch: `release/v1.1-a-locked`
- Final lock tag: `stayqr-v1.1-a-locked`

## Source and regression acceptance
- V1.1-A static source acceptance: **21/21 PASS**
- Legacy post-launch regression: **PASS**
- Responsive validation: **PASS**
- Lint: **PASS**
- Production build: **PASS**

## Staging database acceptance
- Migration 095 + Audit 096: **34/34 TRUE**
- Environment: StayQR Staging
- Staging project ref: `eecinuhvkxlbdvyuazal`

Evidence:
`docs/v1.1/evidence/V1_1_A_DATABASE_ACCEPTANCE_34_OF_34.csv`

## Consolidated browser/data acceptance
Final Acceptance 097: **19/19 TRUE**

Accepted evidence covers:
- Direct Booking returned to OFF after testing
- active corporate account and negotiated rate
- exactly one controlled direct website reservation
- corporate reservation link + public-booking idempotency evidence
- controlled direct reservation checked out
- authoritative folio settled to zero
- authoritative invoice paid with zero pending
- exactly two split-bill payer shares
- both payer shares fully settled
- controlled split-stay plan verified after the authoritative room move
- controlled split-stay lifecycle closed
- checkout housekeeping closed
- controlled Rooms 101/102 returned Available
- StayQR Standard accounting CSV generated
- at least one external accounting connector export generated

Evidence:
`docs/v1.1/evidence/V1_1_A_FINAL_BROWSER_ACCEPTANCE_19_OF_19.csv`

## Environment / release boundary
- Production application changed by V1.1-A closure: **NO**
- Production database changed by V1.1-A closure: **NO**
- v1.0 production release remains independent and locked.
- V1.1-A remains a staging-accepted development release until a future explicit v1.1 production-release decision.

## Final result
**StayQR v1.1-A — COMPLETE & LOCKED**

Next planned execution block:
**V1.1-B — Hotel Operations & Automation**
