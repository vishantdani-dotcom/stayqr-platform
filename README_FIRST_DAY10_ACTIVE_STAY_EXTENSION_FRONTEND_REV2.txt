StayQR v1.0 — Day 10 Stay Extension Frontend REV2

PURPOSE
-------
REV2 preserves the complete timezone-safe, atomic stay-extension frontend from
REV1 and removes the two unused style constants that caused ESLint to fail:

- smallModal
- modalTitle

INSTALL
-------
1. Stop Vite with Ctrl+C.
2. Put this ZIP inside:
   C:\Users\HP\Documents\StayQR
3. Extract with overwrite:
   Expand-Archive -Path .\StayQR_Day10_Active_Stay_Extension_Frontend_REV2_PATCH.zip -DestinationPath . -Force
4. Run:
   cd .\Frontend
   npm run check
5. Start:
   npm run dev

EXPECTED
--------
- 0 ESLint errors
- Existing React Hook warnings may remain
- PASS — Day 10 front-office source gate
- 52 required contracts
- 12 unsafe patterns blocked
- Vite build passed

CONTROLLED BROWSER ACCEPTANCE
-----------------------------
Open Guests -> Active stays -> Day10 Identity Test Guest -> Extend Stay.

Prepare:
- New checkout: 31 Jul 2026, 11:00 AM
- Additional room charge: 3000
- Reason: Day 10 controlled one-night stay extension acceptance.
- Tick the charge confirmation checkbox

Do not confirm until the prepared modal is reviewed.
