# StayQR Post-Launch Mobile UI Redesign REV2 — Authoritative

## Why REV1 did not visibly fix the browser
The shared `responsive.css` is loaded from the application shell, while many StayQR
route stylesheets are lazy-loaded with their pages. Those route styles can arrive
after the shared responsive layer and override mobile rules even when the source
validator passes.

## REV2 strategy
Mobile presentation rules now live at the end of the actual page/component CSS
files (Dashboard, Rooms, Guest Directory, Staff, Operations Centre, Super Admin,
Navbar, Sidebar and shared dashboard cards). This makes the mobile layer
authoritative for each lazy-loaded route.

## Scope
Presentation only. No API, database, RLS, auth, tenant, payment or production
changes.
