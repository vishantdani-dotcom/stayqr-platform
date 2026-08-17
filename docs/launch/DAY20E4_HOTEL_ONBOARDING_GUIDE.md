# StayQR v1.0 — Hotel Onboarding Guide

**Audience:** hotel owner/manager implementing a property in StayQR  
**Product:** StayQR v1.0  
**Launch baseline:** 17 August 2026

## 1. Before starting

Have these items ready:

- hotel/property legal and display name;
- owner/contact name, email and phone;
- address, city and state;
- timezone and currency;
- tax/GST information where applicable;
- standard check-in and check-out times;
- cancellation policy, house rules and invoice notes;
- floors, room types, room numbers and base rates;
- amenities and guest-request categories;
- at least one real menu item if food ordering will be used;
- names/emails/roles of staff who need StayQR access;
- guest-guide content, hotel contact numbers, service details and QR placement plan.

Do not use sample customer PII during setup. Test with synthetic data until the property is ready for controlled go-live.

## 2. Run Hotel Setup

Open **Settings → Hotel Setup**. StayQR uses five onboarding stages.

### Stage 1 — Hotel & Policies

Enter and verify:

- hotel name and owner/contact details;
- address/location and website if used;
- timezone and currency;
- tax registration number and default tax settings;
- check-in/check-out time;
- hotel cancellation policy, house rules, terms and invoice notes;
- active StayQR plan/trial selection shown by the system.

**Pass condition:** hotel-owned settings are saved and the property/trial exists without manual database edits.

### Stage 2 — Types, Floors & Rates

Configure:

- one or more floors;
- room types and occupancy limits;
- base/extra-person rates;
- rate plans and meal plan;
- refundability/minimum stay/other rate rules used by the property.

**Pass condition:** the inventory model represents the hotel's real sellable room/rate structure.

### Stage 3 — Rooms Import

The onboarding room import expects these CSV columns:

```text
room_number,room_type_code,floor_code,status
```

`status` defaults to available when omitted by the supported importer. Validate room numbers, room-type codes and floor codes before import.

Do not attempt to reconfigure an occupied room through bulk setup.

**Pass condition:** every sellable room exists once and is assigned to the correct type/floor.

### Stage 4 — Guest Operations

Configure guest-facing operational defaults:

- amenities;
- service/request categories;
- menu categories/items where food ordering is enabled.

The current readiness flow expects at least:

- one active amenity;
- one active guest-request category;
- one menu item.

**Pass condition:** the guest experience has real hotel-owned content rather than placeholder data.

### Stage 5 — Readiness

Open the **Readiness** stage and refresh the authoritative checklist.

Do not complete onboarding while the wizard reports missing readiness items. The final action is enabled only when the property is considered ready by StayQR.

**Correct final result:** the property reports **Operational**, onboarding completes, and the hotel is ready for the remaining launch checks.

## 3. Complete the post-wizard setup

The onboarding wizard is not the entire hotel launch. After the readiness gate:

1. Open **Staff** and invite the required hotel staff. Use individual identities; do not share an owner login.
2. Open **Hotel Profile** and verify public/property information.
3. Open **Guest Guide Builder**, replace any sample content, configure hotel contact/service information and publish the guide.
4. Open **QR Guides** only after a guest has a valid active stay; validate copy/download, rotation and revocation behavior.
5. Review **Menu Management**, **Amenities**, **Service Requests**, **Housekeeping** and **Maintenance** settings relevant to the property.
6. Verify **Operations Centre → System Settings** for timezone, currency, tax, check-in/out and business-day settings.

## 4. Staff launch checklist

Before real use, confirm:

- owner/manager can sign in;
- reception/front-desk user can handle reservation/check-in/guest/payment workflows required by their permissions;
- housekeeping user can see the housekeeping/room workflow required by their permissions;
- restaurant user can see food/menu operations where enabled;
- accounts user can see payment/folio/report/invoice areas where enabled;
- no disabled/invited-only account is being used as a shared login.

## 5. Controlled hotel smoke test

Run one synthetic operational chain before accepting the property:

1. create a reservation or controlled walk-in;
2. confirm the room is available and allocated correctly;
3. check in the synthetic guest;
4. generate signed guest access and open the guest guide;
5. submit at least one guest action (food or service where enabled);
6. confirm the folio reflects expected charges;
7. record/confirm settlement as appropriate to the test;
8. issue/preview the expected invoice/receipt;
9. checkout;
10. confirm QR access becomes unavailable as designed;
11. complete housekeeping turnover;
12. confirm report totals for the test transaction.

This smoke test does not replace the formal Day 20F first-hotel controlled go-live.

## 6. Go-live handover

Record:

- hotel name;
- owner/admin contact;
- launch date/time;
- enabled plan;
- number of configured rooms;
- staff identities/roles created;
- guest guide published: yes/no;
- QR smoke test: pass/fail;
- finance/invoice smoke test: pass/fail;
- housekeeping smoke test: pass/fail;
- known hotel-specific limitations;
- training completed by;
- go-live approved by.

If any P0/P1 issue is found, stop go-live and use the incident/rollback runbook.
