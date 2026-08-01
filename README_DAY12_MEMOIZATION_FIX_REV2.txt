StayQR Day 12 Frontend Memoization FIX REV2

FIXED ERROR
-----------
src/pages/invoices/Invoices.jsx
react-hooks/preserve-manual-memoization:
Existing memoization could not be preserved.

ROOT CAUSE
----------
The callback read the complete currentHotel object and selected modal values,
while its dependency list declared narrower values.

CORRECTION
----------
- Added stable `currentHotelId`.
- `loadWorkspace` depends only on `currentHotelId`.
- Selected invoice/receipt refresh uses functional state setters.
- Initial-load and realtime effects depend on `loadWorkspace`.
- Updated the Day 12 source-gate realtime assertion.

INSTALL
-------
1. Extract the ZIP.
2. Copy the enclosed `Frontend` folder into:
   C:\Users\HP\Documents\StayQR
3. Choose “Replace the files in the destination”.
4. Run:
   cd C:\Users\HP\Documents\StayQR\Frontend
   npm run check

EXPECTED
--------
The previous Invoices.jsx error is removed.
The 14 existing warnings may remain.
The final result must show 0 errors and continue through source gates, QR test,
and Vite production build.
