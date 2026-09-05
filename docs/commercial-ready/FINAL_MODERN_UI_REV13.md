# StayQR Final Modern UI REV13

REV13 is the final application visual closure after the accepted REV9–REV11 functional work and REV12 polish pass.

## Scope

- Removes internal-app backdrop blur/compositing from primary chrome and notification surfaces to improve text sharpness.
- Standardizes the product on modern system sans-serif typography; removes editorial/serif styling from Reports and the guest guide.
- Declutters Booking Calendar controls and gives the room timeline full workspace width, moving unallocated bookings below the timeline.
- Simplifies Housekeeping cards and replaces default checkbox visuals with clear custom check controls.
- Adds explicit modern styling hooks to Payments and makes its metrics/table easier to scan.
- Improves Guest Bills/Folio readability and removes tiny supporting text.
- Prevents Reports currency and KPI digits from breaking across lines.
- Cleans invoice/table density and modernizes invoice/receipt typography.
- Modernizes the Guest Guide/thank-you typography while preserving the accepted zero-PIN QR workflow and hospitality functions.
- Standardizes StayQR branding tagline to **Simplifying Checkinn** and removes the alternate "Smart Digital Hospitality / Scan. Stay. Simplified." copy from the patched product UI.
- Removes visible luxury/premium positioning from hotel profile/menu-management defaults where it was being presented as product language.

## Boundaries

No database migration is required. REV13 does not change reservation, QR, billing, OCR, security, RLS, Meta, Cashfree or UIDAI provider behaviour. Meta and Cashfree remain on hold. Production is untouched by the apply script.
