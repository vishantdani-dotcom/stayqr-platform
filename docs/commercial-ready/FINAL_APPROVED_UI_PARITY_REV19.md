# StayQR — Final Approved UI Parity REV19

## Authority

This release is a parity correction against the stakeholder-approved `StayQR_UIUX_FINAL_REV18_PROTOTYPE.html`. The prototype remains the visual design authority. REV19 does not introduce a new design direction.

## Locked visual system

- Primary background: `#06080b`
- Elevated background: `#090c11`
- Panel: `#0f141a`
- Secondary panel: `#131920`
- Border: `#27303a`
- Primary text: `#f7f8f9`
- Secondary text: `#b3bbc5`
- Accent: `#e8bd45`
- Primary typeface: Poppins 400/500/600/700/800
- Desktop sidebar: 238 px
- Desktop navbar: 66 px
- Clean, minimal, modern, advanced, professional operating UI

## Implementation scope

REV19 is a final authenticated-product visual authority layer loaded after REV18. It deliberately preserves all existing business logic, media, hotel logos/photos, login behavior, QR lifecycle, tenant isolation, billing behavior, OCR provider boundaries and provider hold policy.

### Global parity

- Locks the approved REV18 palette and Poppins typography across authenticated surfaces.
- Removes blur-producing glass/backdrop effects from operating surfaces.
- Raises small operational copy to a readable mobile/desktop baseline.
- Normalizes buttons, inputs, cards, tabs, tables, drawers, status pills and spacing.
- Keeps hotel media/assets instead of stripping the product to text-only UI.
- Refines mobile breakpoints so wide desktop tables become readable cards where appropriate.
- Keeps reduced-motion accessibility.

### Booking Calendar

- Rebuilds the header and primary controls around the approved REV18 hierarchy.
- Keeps room type as the fast filter.
- Moves reservation statuses, date jump and room-block history under one compact `Filters` menu.
- Moves the large color legend under a compact `Legend` menu.
- Moves refresh and room-block creation under `More` while keeping `Today` and `New reservation` prominent.
- Hides the empty assignment queue instead of reserving blank screen space.
- Keeps the desktop room timeline and the mobile agenda view.

### Housekeeping

- Reduces summary density to four operational metrics.
- Uses compact task cards and modern custom checklist controls.
- A normal checklist tap updates optimistically in place and does **not** reload the workspace or lose scroll position.
- Adds `Complete all` / `Clear all` per task.
- Bulk success does not reload the workspace; an authoritative reload occurs only if a bulk persistence failure must be reconciled.
- Existing assign/start/complete/inspection/room-ready workflow is preserved.

### Additional parity/declutter surfaces

REV19 contains responsive refinements for Dashboard, Rooms, Guests, Payments, Guest Bills, Reports, Invoices, check-in/OCR scanner, Guest Guide and food/cart surfaces. These are presentation changes only.

## Explicitly untouched

- Login page redesign: retained as already approved.
- Database / migrations: no change.
- Meta WhatsApp automation: on hold / untouched.
- Cashfree / AutoPay: on hold / untouched.
- Online UIDAI launch: untouched.
- Production deployment: not part of the staging package.
- Git remote: package does not push.

## Release gate

The package may be called complete only after:

1. REV9/10/11/12/13/14 source regressions pass.
2. REV19 parity validator passes 31/31.
3. Responsive, commercial-ready, manual-billing and relative-import gates pass.
4. ESLint passes.
5. Vite production build passes.
6. Staging Netlify deployment passes.
7. Staging home/login HTTP smoke passes.
8. One authenticated desktop/tablet/mobile visual acceptance is completed against the approved REV18 prototype.
