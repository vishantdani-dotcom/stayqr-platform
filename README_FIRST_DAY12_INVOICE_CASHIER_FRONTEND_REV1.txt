StayQR v1.0 — Day 12 Invoice, Receipt, Cashier & Night Audit Frontend REV1

INSTALL
-------
1. Stop the Vite development server.
2. Extract this ZIP.
3. Copy the enclosed `Frontend` folder into:
   C:\Users\HP\Documents\StayQR
4. Choose “Replace the files in the destination”.
5. Do not delete or overwrite your `.env`.
6. Run:
   cd C:\Users\HP\Documents\StayQR\Frontend
   npm run check

DAY 12 MODULE
-------------
Navigation:
  Settings → Invoices & Audit

Tabs:
- Invoices
- Receipts
- Cashier Shifts
- Night Audit
- GST / Tax Setup

DELIVERY
--------
Invoice and receipt documents support:
- local PDF generation;
- isolated print window;
- WhatsApp message;
- email client message.

Finalized invoices include a locally generated QR that opens:
  /invoice/verify/<verification_token>

The public verification page calls only `verify_invoice` and shows bounded
invoice/GST/hash data. Buyer snapshots and private line metadata are not shown.

SAFETY
------
All financial writes use RPCs. The frontend contains no direct insert/update/
delete call against invoices, receipts, cashier shifts, night audits, accounting
exports or tax rates.

BROWSER ACCEPTANCE — DO NOT SUBMIT REAL FINANCIAL ACTIONS
----------------------------------------------------------
Verify:
1. Dashboard counts:
   - invoices 25
   - immutable finals 7
   - receipts 38
   - receipted value INR 199,475
   - open cashier shifts 0
   - night audits 0
2. Open a finalized invoice and show:
   - GST breakup
   - PDF / Print / WhatsApp / Email
   - local QR and hash
3. Open a receipt and show document actions/hash.
4. Open cashier shift form without submitting.
5. Preview current day close only; do not close.
6. Open GST/tax setup form without saving a rate.
