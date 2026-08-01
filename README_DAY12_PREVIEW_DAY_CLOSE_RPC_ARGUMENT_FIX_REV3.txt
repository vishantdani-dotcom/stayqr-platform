StayQR Day 12 — Preview Day Close RPC Argument FIX REV3

OBSERVED DATABASE RESULT
------------------------
The installed function has these named arguments:

  public.preview_day_close(
    h uuid,
    business_date_value date
  )

The browser previously sent:

  target_hotel_id
  business_date_value

PostgREST resolves RPC calls by named JSON arguments, so the call did not match.

FIX
---
The frontend now sends:

  h
  business_date_value

DATABASE SAFETY
---------------
- No SQL migration is required.
- No financial row is inserted, updated or deleted.
- No cashier shift is opened.
- No business date is closed.
- Do not rerun the failed schema-cache FIX REV1.

INSTALL
-------
1. Extract this ZIP.
2. Copy the enclosed `Frontend` folder into:
   C:\Users\HP\Documents\StayQR
3. Choose “Replace the files in the destination”.
4. The Vite dev server should hot-reload. If not, restart it.
5. Hard refresh Chrome:
   Ctrl + Shift + R
6. Open:
   Invoices & Audit → Night Audit
7. Click:
   Preview day close

EXPECTED
--------
- blocker count greater than zero;
- warning count greater than zero;
- exception rows displayed;
- no schema-cache/function-not-found error.

Do not click “Close business date”.
