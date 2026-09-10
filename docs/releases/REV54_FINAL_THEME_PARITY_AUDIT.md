# StayQR REV54 — Final Theme Parity Audit

## Scope
Colour/theme correction only. No layout, spacing, typography, workflow, data, permissions, provider configuration, responsive structure, or business logic changes.

## Visual authority
The currently accepted StayQR admin surface system: page `#06080b`, elevated controls `#090c11`, cards/panels `#0f141a`, selected/secondary surface `#131920`, borders `#27303a` / `#36414d`, restrained gold accent `#e8bd45`.

## User-reported areas reviewed
1. Global Search.
2. Service Requests dynamic catalogue.
3. Booking register / walk-in / Reservations.
4. Check-In / Out.
5. Guests — Contact & Consent.
6. Guest Guide Builder — Editing language and Setup summary.
7. Menu Management — Category service windows.
8. Food & Kitchen Operations / Completed activity.
9. Housekeeping — Create task.
10. Maintenance — Report issue.

## Additional residual surfaces found during source audit
The same legacy neutral-grey/warm near-black values were also still declared in Booking Calendar structural cards, invoice tax/configuration cards, responsive Staff cards, and Hotel Setup configuration cards. These are included because they are the same colour-parity defect and can be corrected without touching functionality.

## Intentionally unchanged
- Typography, text content, spacing and layout.
- All responsive breakpoints and card/table geometry.
- Gold primary CTAs.
- Success/warning/error and operational status colours.
- Uploaded photos/videos and guest-facing visual design.
- Public booking / public guest guide / login pages.
- Printed invoice/receipt white paper surfaces.
- Scanner/OCR, notifications, billing, reservations, check-in, food, housekeeping and maintenance logic.
- Database, Supabase Edge Functions and provider secrets.

## Release boundary
REV54 is staging-only. Production remains blocked until browser acceptance and a separate explicit production rollout authorization.

## Final semantic safety refinement
Before packaging, the colour layer was tightened so it does not override already-correct operational semantics: overdue Service Request SLA red state, Reservation/Calendar danger actions, Menu primary/danger actions, Staff Suspend danger styling, provider-readiness status styling, and active Hotel Setup toggle styling remain outside the neutral recolour rules. The final dedicated validator passes these guardrails in addition to the colour-only declaration gate.
