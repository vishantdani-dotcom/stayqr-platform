# StayQR Final UI Lock Review — REV22

Visual authority: approved `StayQR_UIUX_FINAL_REV18_PROTOTYPE.html`.

REV22 closes only the four items raised in final staging review:

1. Remove remaining light-gold / brown admin background washes while preserving gold as a restrained text/accent signal.
2. Draw the housekeeping checked state with a stable CSS checkmark instead of relying on browser checkbox glyph rendering.
3. Neutralise Dashboard metric/Quick Actions icon tiles and gold card fills.
4. Replace Rooms register-first presentation with the approved visual room-card design, including live status, rate, QR readiness, edit/status/archive actions, and room photo upload/replacement using the existing tenant-scoped guest-guide media pipeline.

The Subscription & Billing visual treatment is intentionally used as the reference for neutral operational panels. Hotel and room media are preserved; guest-facing media is not stripped.

No database migration. No provider change. No production deployment. Meta and Cashfree remain on hold.


## REV22 FIX1 integration note
The original runner used a brittle exact Dashboard JSX anchor for `analyticsCard`. The current staging source retains the analytics grid but uses a newer card tag/shape. FIX1 makes the grid hook authoritative, treats individual card hooks as optional, and uses CSS fallback neutralisation for all metric cards. This is presentation-only and does not change data, APIs, database schema, providers, room contracts or checkout logic.
