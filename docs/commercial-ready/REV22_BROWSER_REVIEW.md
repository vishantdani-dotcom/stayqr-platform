# REV22 Browser Review

After staging deployment, review these screens in this order:

- Dashboard: metric icons and Quick Actions must be neutral dark; gold may appear as text/accent, not a card wash.
- Room QR Guides: QR assets must remain; cards/panels must be neutral dark.
- Guest Guide Builder: hotel logo/media remains; editor shell must be neutral dark.
- Menu Management: images/content remain; admin offer/language studio must not use brown/gold washes.
- Housekeeping: checked boxes show a clean green square with a crisp dark check; no broken glyph.
- Staff / Operations Centre / Hotel Setup / Amenities: neutral dark operational hierarchy like Subscription & Billing.
- Rooms: card grid, room photo/actual hotel fallback image, status, rate, QR state, menu; verify Edit room and Upload/Replace photo.
- Mobile/tablet: card grid collapses cleanly; controls do not overflow.

Do not lock until the user visually approves this staging build.


### FIX1 acceptance addition
Confirm Dashboard metric cards render with neutral black/blue-black surfaces even when the underlying JSX uses the newer analytics-card markup. Confirm no large gold/brown metric-card wash remains.
