# StayQR v1.1-B — Consolidated Staging Acceptance

Environment: StayQR Staging only (`eecinuhvkxlbdvyuazal`)

Do the browser acceptance as one continuous controlled test after Migration 098 + Audit 099 return 44/44 TRUE.

## Controlled hotel

Use `20E Test Hotel` unless it is unavailable. Do not use production.

## A. Laundry

1. Create a controlled active stay if none exists.
2. Ops Automation → Laundry.
3. Create one express laundry order with 3 pieces and item summary `V11B 2 shirts + 1 trouser`.
4. Move it through washing → drying → ironing → ready → delivered.
5. Verify no duplicate laundry order appears after refresh.

## B. Lost & Found

1. Record `V11B Test Wallet 300826` found at `Lobby sofa` and stored at `Front desk locker A`.
2. Mark it matched.
3. Return it to claimant `V11B Test Claimant`.
4. Verify status is closed/returned and it leaves the open register.

## C. Simple inventory

1. Create item:
   - SKU: `V11B-WATER-300826`
   - Name: `V11B Water Bottle`
   - Category: guest_amenity
   - Unit: bottle
   - Opening stock: 10
   - Reorder level: 5
2. Post Receive 5.
3. Post Consume 4.
4. Final quantity must be 11.
5. Attempt a consume greater than current stock; it must be rejected without changing quantity.

## D. KOT / printer

1. Ensure `Kitchen Default` printer profile exists.
2. Set 80 mm and 2 copies and save.
3. Use any controlled recent food order for the hotel.
4. Print KOT through Ops Automation.
5. Confirm a new kitchen print event appears after refresh and the existing KOT identity is reused.

## E. Scheduled reports

1. Create schedule:
   - Name: `V11B Daily Occupancy 300826`
   - Report: Occupancy Daily
   - Frequency: Daily
   - Lookback: 1
   - Next run: current time or earlier for acceptance
2. Click Run due / force now.
3. Confirm one generated run is visible.
4. Download the JSON snapshot.
5. Click Run due again without rewinding next run; no duplicate run for the same scheduled timestamp may be created.

## F. Regression / cleanup

Verify these existing modules still load:
- Service Requests
- Food Orders
- Housekeeping
- Maintenance
- Reports
- Folio & Settlement
- Revenue Growth

Close the controlled active stay and housekeeping if one was created for Laundry. Leave inventory/lost-found/schedule records as staging acceptance evidence.

## Final browser evidence expected

- Laundry delivered
- Lost item returned/closed
- Inventory quantity 11 and negative-stock rejection observed
- KOT print event created with printer profile
- Scheduled report generated once and downloadable
- no P0/P1 regression in touched existing flows
