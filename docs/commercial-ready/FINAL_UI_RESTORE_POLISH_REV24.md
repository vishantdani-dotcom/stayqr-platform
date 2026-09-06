# StayQR Final UI Restore + Surgical Polish — REV24

## Authority
1. `StayQR_UIUX_FINAL_REV18_PROTOTYPE.html`
2. Accepted staging state `REV22 FIX4` / HEAD `28b5198`

REV23 is explicitly rejected and is removed by this package.

## Non-negotiable visual contract
- Keep the approved black / blue-black neutral surfaces.
- Keep StayQR gold (`#e8bd45`) as the accent.
- Keep the existing Poppins / approved typography.
- Do not introduce a new accent colour.
- Do not recolour Dashboard, Sidebar, Login, or guest-facing UI.

## Surgical corrections only
- Replace the Housekeeping bright-green checkbox with a dark neutral checkbox using a restrained gold border/check when selected.
- Improve inactive Housekeeping tab readability without changing the accent language.
- Neutralise excessive inline-gold field labels on legacy admin forms while retaining gold section cues and primary emphasis.
- Neutralise only legacy warm/brown fills, not gold text/buttons.
- Ensure legacy 42px operational headings remain visible and scale cleanly on mobile.
- Add narrow mobile sizing/padding improvements for Day13 and legacy inline-layout pages.

## Safety
Presentation-only. No database, auth, RLS, provider, billing, guest-media, operations logic, or production app changes.
