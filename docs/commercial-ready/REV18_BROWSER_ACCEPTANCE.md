# StayQR REV18 Browser Acceptance — Single Consolidated Gate

Run only after the REV18 script deploys successfully to `https://stayqr-pilot-staging.netlify.app`.

## Desktop — 1366/1440px
- Login page: sharp Poppins typography, StayQR logo/media present, no overflow.
- Dashboard: hotel photo/logo retained, metrics/icons aligned, notification drawer crisp.
- Booking Calendar: readable timeline, clean filters, no overlap.
- Rooms, Guests, Housekeeping, Payments, Guest Bills, Reports, Invoices, Kitchen/Food Orders: no clipping or broken actions.
- Check-in/OCR and Final Bill & Checkout modal: readable, correct action hierarchy.

## Tablet — approximately 768–820px
- Sidebar/navigation does not cover content.
- Cards and filters reflow cleanly.
- Tables remain usable without page-level horizontal overflow.
- Modals/drawers remain inside viewport.
- QR Guest Guide and food ordering remain touch-friendly.

## Mobile — 390–430px
- Dashboard has no desktop compression or horizontal overflow.
- Rooms render cards rather than crushed table columns.
- Active Guests render mobile stay cards.
- Booking Calendar renders the mobile agenda.
- Housekeeping controls are touch-friendly.
- Payments / Guest Bills / Reports / Invoices remain readable.
- Scanner fills viewport cleanly and controls remain reachable.
- Guest Guide: hotel media preserved, Call/WhatsApp/Services controls usable.
- Menu/cart: add item, quantity, place order, live order state works.
- Feedback form and thank-you/footer are clean.

## Functional regression spot-check
- Multi-occupant check-in still works.
- Permanent Room QR auto-activates for active stay without staff PIN issuance.
- Food order follows stay, including after room move.
- Checkout collects authoritative Guest Bill/Folio total.
- Notification mark-read/click-through still works.

Acceptance is complete only when Desktop + Tablet + Mobile are all PASS.
