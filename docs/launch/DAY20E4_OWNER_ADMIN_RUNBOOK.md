# StayQR v1.0 — Hotel Owner / Admin Runbook

**Audience:** hotel owner, manager or authorised hotel administrator

## 1. Start of day

1. Sign in with your own StayQR account.
2. Confirm the correct property in the hotel switcher before making changes.
3. Review **Dashboard** occupancy, arrivals/departures, active guests, pending requests, food orders and revenue indicators.
4. Open **Operations Centre** if a system warning, support issue or incident requires attention.
5. Review **Booking Calendar** and **Reservations** for the current operating day.

Never continue with another hotel's data selected. If the property context appears wrong, stop and sign out rather than attempting a correction through direct database access.

## 2. Reservations and front desk

Use:

- **Reservations** for reservation records and updates;
- **Booking Calendar** for room/date allocation visibility;
- **Arrivals & Departures / reservation operations** where available to handle operational reservation actions;
- **Check-In/Out** for controlled walk-ins and stay processing;
- **Guests** for active/history views, stay changes and checkout workflows.

For guest identity/KYC:

- collect only operationally required information;
- use authorised KYC upload/view/delete controls;
- do not copy KYC documents into ordinary support email or chat;
- use the foreign-guest/Form C fields only where applicable to the stay and hotel obligations.

## 3. Guest QR and guest experience

1. Maintain hotel content through **Guest Guide Builder**.
2. Publish updated guide content before treating it as live.
3. Use **QR Guides** only for an active stay.
4. Copy/download the signed guest/food links from StayQR.
5. Rotate access when a signed link may have been exposed or when a controlled refresh is required.
6. Revoke access immediately if guest access must stop before the normal expiry/checkout path.

A hotel slug or room number alone is not a valid guest-access credential. Do not manually construct guest URLs.

## 4. Food and service operations

- **Menu Management**: maintain hotel menu content, pricing and availability.
- **Food Orders**: process order lifecycle and operational status.
- **Service Requests**: triage guest requests and complete/assign them as permitted.
- **Amenities**: maintain hotel-owned amenity/service content.
- **Housekeeping**: progress room-turnover tasks.
- **Maintenance**: manage room/property maintenance workflow and out-of-order conditions.

Do not mark work complete before the real operational task has been completed.

## 5. Finance and settlement

Use the trusted StayQR finance surfaces rather than spreadsheet-only corrections:

- **Payments** for payment/collection records;
- **Folio & Settlement** for charges, collections, refunds/credits/adjustments and authoritative balance;
- **Invoices & Audit** for invoices, receipts, cashier shifts and Night Audit;
- **Reports** for operational/financial reporting and permitted CSV/PDF exports.

Before checkout:

- verify the folio balance;
- resolve open food/order blockers where the UI requires it;
- review any refund/adjustment warning;
- issue/confirm the required invoice/receipt workflow.

Never “fix” a financial mismatch with direct production SQL. Escalate it and preserve transaction/reference IDs.

## 6. Staff and access administration

Owners/managers with permission may use **Staff** to:

- invite staff;
- update permitted profile/role details;
- send an identity invite for preserved legacy profiles where supported;
- disable/suspend access when a staff member should no longer sign in.

Rules:

- one identity per person;
- no shared password accounts;
- do not silently change a linked authentication email;
- give the minimum role/permission needed;
- disable departed staff promptly.

## 7. Hotel configuration

Use:

- **Hotel Setup** for onboarding/readiness configuration;
- **Hotel Profile** for property information;
- **Operations Centre → System Settings** for authoritative system settings such as timezone, currency, tax and business-day controls.

Do not create a parallel/manual settings source outside StayQR for values that affect hotel operations.

## 8. End of day

1. Review open arrivals/departures and unresolved guest requests.
2. Confirm financial items expected for the day are posted/reconciled.
3. Review invoices/receipts and cashier state as applicable.
4. Open **Invoices & Audit → Night Audit** and review blockers/warnings before closing the business date.
5. Review **Reports** for occupancy/revenue/payment/source totals.
6. Review **Operations Centre → Diagnostics** if errors occurred.
7. Preserve the incident ID/request ID for any unresolved operational error.

Do not close a business date by bypassing a blocker that indicates unresolved financial or operational correctness risk.

## 9. When to contact StayQR support

Primary support: **support@stayqr.in**

Include:

- hotel/property name;
- affected feature;
- time of issue;
- exact business impact;
- screenshot/error text;
- incident/request/reference ID where available;
- whether a safe workaround exists.

Do not send passwords, service-role keys, full payment-card data or unnecessary KYC documents.

For privacy/grievance requests use the channel published in the StayQR Privacy Policy.
