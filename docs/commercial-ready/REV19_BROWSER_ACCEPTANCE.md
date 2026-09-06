# StayQR REV19 — Final Authenticated Browser Acceptance

Run this once on `https://stayqr-pilot-staging.netlify.app` after the package deploys. This is a single consolidated visual gate, not a new redesign cycle.

## Desktop

Check Dashboard, Booking Calendar, Check-In/OCR, Guests, Rooms, Room QR Guides, Guest Guide/Menu, Housekeeping, Kitchen Orders/Food Orders, Payments, Guest Bills, Reports, Invoices and Notifications.

Pass only when:

- Poppins type and the approved black/gold palette visibly match the approved REV18 prototype.
- No blurry small text, glass blur, overlapping text, clipped controls or unexplained horizontal page overflow.
- Sidebar/navbar proportions and spacing feel consistent with REV18.
- Booking Calendar opens cleanly with compact controls; reservation status filters are under `Filters`; empty assignment queue is absent.
- Housekeeping checklist does not jump/reload after a normal tick and `Complete all` / `Clear all` works.
- Hotel logos, photos and existing media remain present where the live product already provides them.
- Payments, Guest Bills, Reports and Invoices remain readable without zooming.

## Tablet

Repeat the same workflow at approximately 820 px width. Pass when controls wrap intentionally, drawers/modals fit the viewport, and no desktop table becomes unreadable.

## Mobile

Repeat at approximately 390 x 844. Pass when:

- Headings and small copy are crisp and readable.
- Tables that need mobile treatment render as cards/compact responsive layouts.
- Scanner fills the usable viewport without broken controls.
- Guest Guide, menu, cart and feedback remain touch friendly.
- Room and guest actions do not crush into narrow columns.
- Bottom/safe-area spacing is correct.

## Boundaries

Do not enable or test Meta automation, Cashfree AutoPay or online UIDAI as part of this visual gate. No production deploy is authorized by REV19 acceptance.
