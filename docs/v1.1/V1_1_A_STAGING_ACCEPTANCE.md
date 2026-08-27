# StayQR v1.1-A — Consolidated Staging Acceptance

Do this only after Migration 095 + Audit 096 return 34/34 TRUE in StayQR Staging.

## One browser run

Use the existing controlled staging hotel (20E Test Hotel is suitable if still available). Do not use production.

### A. Direct booking + corporate negotiated rate
1. Open Revenue Growth.
2. Confirm Direct Booking starts OFF after a fresh migration unless already deliberately configured.
3. Enable Direct Booking with Instant confirmation, minimum stay 1, maximum stay 30, deposit 0%, then Save.
4. Create corporate profile:
   - Company: `V11A Test Corporate 280826`
   - Internal code: `V11A280826`
   - Booking code: `V11A-280826`
5. Create one negotiated rate for an active room type/rate plan. Use a clearly identifiable staging-only test amount.
6. Copy the generated corporate booking link and open it in Incognito.
7. Search a valid available stay. Confirm `Corporate negotiated pricing applied` and the negotiated rate.
8. Book synthetic guest:
   - Name: `V11A Direct Booking 280826`
   - Phone: `+919999999974`
   - Email: `v11a.direct.280826@example.com`
9. Confirm one reservation number is returned. Refresh/retry must not create a duplicate reservation.
10. In the staff Reservations page confirm the reservation exists with website/direct source.

### B. Split stay
1. Check in the controlled V1.1-A reservation when its arrival date is today, or use another controlled active staging stay.
2. In Revenue Growth → Split Stay, create a plan from the current room to another safe target room inside the active stay.
3. Confirm the plan is Planned.
4. Perform the real room move using StayQR's existing Arrivals & Departures / room-move workflow.
5. Return to Revenue Growth and click Verify after move.
6. Confirm the plan becomes Verified and the active stay is on the target room.

### C. Split bill
1. Open Revenue Growth → Split Bill and choose the controlled open folio.
2. Create two payer shares whose total equals the exact current folio balance.
3. Post payer collections using staging-safe Manual/Cash.
4. Retry protection: do not intentionally duplicate payments; normal UI busy/idempotency protection must remain active.
5. Confirm both payer shares settle and the authoritative folio reaches the expected balance.

### D. Accounting
1. Open Revenue Growth → Accounting.
2. Generate and download StayQR Standard CSV for the test date range.
3. Generate and download one connector template (Tally, Zoho Books or QuickBooks).
4. Confirm the exports appear in Recent accounting exports and downloaded CSVs contain the expected header/rows.

### E. Closure
1. Finish the controlled stay normally: invoice/checkout/housekeeping if the folio is fully settled.
2. Confirm room(s) return to expected Available state.
3. Disable Direct Booking again on staging after acceptance unless you intentionally want to keep the test public route enabled.
4. Confirm old Reservations, Folio, Invoices, QR Guide and Reports still load.

## Acceptance evidence

Final evidence should show:
- Audit 096: 34/34 TRUE
- Direct corporate booking confirmation
- Internal reservation record
- Split-stay plan Verified
- Split-bill payer shares Settled / authoritative folio reconciled
- Accounting export generated
- Final room/folio state
- no regression/error blocking the old v1.0 workflows
