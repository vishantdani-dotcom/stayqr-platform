# StayQR Final Complete UI Freeze REV14

This is the single consolidated final UI package requested before production release.

It combines the complete REV12 release polish with the REV13 modern UI correction layer in the correct order.

## Included from REV12
- final typography cleanup
- sidebar polish
- navbar polish
- consistent inputs and buttons
- cards, panels and tables consistency
- modal and drawer polish
- empty and loading states
- scrollbar polish
- final checkout visual refinement
- Guest Bills polish
- check-in/OCR surface polish
- Room QR Guides polish
- mobile spacing, headings, drawers and modals
- cleanup of old Vite starter CSS
- `folio settlement` loading terminology -> Guest Bills
- removal of development-oriented fallback copy
- source-level production-readiness checks
- Meta/Cashfree/online UIDAI explicitly disabled

## Included from REV13
- blur/compositing correction for notifications/navbar/overlays
- modern system sans typography and hierarchy
- Booking Calendar declutter and workspace correction
- Housekeeping checkbox/card cleanup
- Payments table/KPI cleanup
- Guest Bills readability improvements
- Reports KPI digit/currency correction
- Invoice density and typography cleanup
- Guest Guide modern typography while preserving accepted QR logic
- official StayQR tagline standardized to `Simplifying Checkinn`
- removal of `Smart Digital Hospitality`, `Scan. Stay. Simplified.`, luxury/premium product wording

## Boundaries
- no database migration
- no Edge Function deployment
- no Meta/Cashfree activation
- no production deployment
- no QR/OCR/billing/business-logic change
