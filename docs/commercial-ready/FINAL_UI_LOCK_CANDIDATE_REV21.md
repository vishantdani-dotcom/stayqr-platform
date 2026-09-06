# StayQR Final UI Lock Candidate — REV21

Visual authority: `StayQR_UIUX_FINAL_REV18_PROTOTYPE.html`.

REV21 is the final review candidate before the user-approved UI/UX lock. It does not redesign business logic. It closes remaining visual mismatches visible after REV20 staging:

- exact approved Poppins font is loaded instead of silently falling back to Segoe;
- legacy `#111/#121212` and brown/gold-wash operational panels are remapped to the approved `#06080b / #090c11 / #0f141a / #131920` hierarchy;
- Reservations cards, filters, tables and modal surfaces use the approved neutral panel system;
- Revenue Growth and Operations Automation no longer use full-panel gold gradients;
- Reports, Owner Billing, Dashboard support/readiness surfaces and common operational cards use the same approved hierarchy;
- dashboard Room Status has a real **View in Rooms** button that navigates into the Rooms workspace;
- Housekeeping keeps green completed checkboxes and compact task density;
- notifications remove the legacy warm radial cast;
- hotel cover photos/logos/media remain preserved;
- light gold `#e8bd45` remains an accent for CTAs, active navigation, focus and small emphasis — not a page background.

Boundaries: database untouched; Meta/WhatsApp hold untouched; Cashfree/AutoPay hold untouched; online UIDAI untouched; real production app untouched; Git remote not pushed.
