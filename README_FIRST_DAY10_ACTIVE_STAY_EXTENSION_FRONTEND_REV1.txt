StayQR v1.0 — Day 10 Stay Extension Frontend REV1

PURPOSE
-------
Replace the unsafe direct guest_sessions update with the authoritative
extend_active_walkin_guest_stay RPC and correct the UTC-to-hotel-timezone
rendering bug in the datetime-local control.

INSTALL
-------
1. Stop Vite with Ctrl+C.
2. Put this ZIP inside:
   C:\Users\HP\Documents\StayQR
3. Extract with overwrite:
   Expand-Archive -Path .\StayQR_Day10_Active_Stay_Extension_Frontend_REV1_PATCH.zip -DestinationPath . -Force
4. Run:
   cd .\Frontend
   npm run check
5. Start:
   npm run dev

EXPECTED SOURCE GATE
--------------------
PASS — Day 10 front-office source gate
52 required contracts
12 unsafe patterns blocked
Vite build passed

CONTROLLED BROWSER ACCEPTANCE
-----------------------------
Open Guests -> Active stays -> Day10 Identity Test Guest -> Extend Stay.

The modal must show:
- Current checkout: 30 Jul 2026, 11:00 AM
- Hotel timezone: Asia/Kolkata
- Current room charge: ₹3,000
- New checkout default: 31 Jul 2026, 11:00 AM
- Availability is server validated
- Operational reason
- Additional room charge
- Explicit confirmation checkbox
- Idempotency request

Prepare only:
- New checkout: 31 Jul 2026, 11:00 AM
- Additional room charge: 3000
- Reason: Day 10 controlled one-night stay extension acceptance.
- Tick the confirmation checkbox

Do not click Confirm stay extension until the prepared-form screenshot is
reviewed.

SAFETY
------
- No direct guest_sessions extension update remains in the browser.
- Reservation-linked stays are excluded from this direct-walk-in RPC.
- The hotel timezone is used for both rendering and UTC conversion.
- Stable request id, stale-screen checkout, reason and charge confirmation are
  sent to the server.
