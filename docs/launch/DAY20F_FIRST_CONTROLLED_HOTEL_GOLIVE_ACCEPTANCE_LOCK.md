# StayQR v1.0 — Day 20F First Controlled Hotel Go-Live Acceptance Lock

Status: COMPLETE + LOCKED
Controlled Hotel: VD Stay Inn
Hotel Slug: vd-stay-inn
Environment: Production

## Controlled Go-Live Scope

VD Stay Inn successfully completed the Day 20F real-hotel operational chain:

- hotel configuration and onboarding
- rooms and rates
- controlled walk-in
- check-in
- signed guest QR access
- guest service requests
- food ordering
- folio posting
- payment and settlement
- invoice generation
- checkout
- post-checkout QR revocation
- housekeeping turnover
- room returned to available
- reporting
- paid subscription verification
- support workspace verification

Controlled synthetic guest:

StayQR 20F Controlled Guest 20260817-A

No real guest PII was required.

## Financial Acceptance

Folio:
FOL-20260817-BA508502

Charges:
- Room: INR 1.00
- Food: INR 270.00
- Total: INR 271.00

Final folio:
- Charges: INR 271.00
- Collections: INR 271.00
- Refunds: INR 0.00
- Credits: INR 0.00
- Balance: INR 0.00
- Status: settled

Invoice:
VDST-INV/2026-27/1782050133239

Invoice:
- status: paid
- payment_status: paid
- total: INR 271.00
- paid: INR 271.00
- pending: INR 0.00

## Day 20 Controlled Correction

A production checkout blocker was discovered:

uq_invoices_hotel_invoice_number

Root cause:
the invoice sequence exceeded its configured display padding and the previous allocator truncated the oversized sequence, causing a collision with an existing invoice number.

Correction:

202608180082_day20f_invoice_number_allocator_overflow_hardening_REV1.sql

Final verifier:

202608180083_day20f_invoice_number_allocator_overflow_acceptance_REV2.sql

The correction:
- preserves existing invoices
- does not rewind the invoice sequence
- treats padding as a minimum width
- preserves oversized sequence digits
- skips already-used canonical numbers
- preserves advisory transaction locking

The correction passed validation before the same controlled checkout was successfully retried.

## Final Runtime Acceptance

Final Day 20F post-transaction verifier:

16 / 16 PASS

Verified:

1. controlled guest unique
2. controlled stay exists
3. actual configured hotel used
4. stay checked out
5. QR access closed
6. guest action completed
7. folio exists
8. folio reconciled
9. invoice exists
10. invoice reconciled
11. collection recorded
12. housekeeping task exists
13. housekeeping cycle closed
14. subscription active and paid
15. plan room capacity valid
16. no new critical production error

Final housekeeping state:
- task_status: ready
- room_status: available

Subscription:
- Growth
- active
- paid
- Cashfree
- 12 active rooms within 50-room limit

Critical production errors since controlled check-in:
0

## Acceptance

The first configured production hotel successfully executed the controlled transaction.

Finance reconciled.
QR and guest experience passed.
Housekeeping closed the room lifecycle.
Reporting passed.
Subscription state passed.
Support workspace was operational.
The discovered launch blocker was corrected with source/migration provenance and revalidated.

DAY 20F ACCEPTANCE: PASS

DAY 20F — COMPLETE + LOCKED
