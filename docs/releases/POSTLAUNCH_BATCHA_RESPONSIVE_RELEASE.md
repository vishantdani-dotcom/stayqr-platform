# StayQR Batch A — Responsive Platform Release

## Scope

This staging-only patch completes the shared responsive and contrast foundation for the StayQR SaaS:

- Desktop and laptop layouts
- Tablet portrait and landscape layouts
- Android phone layouts
- iPhone layouts, including safe-area handling
- Shared navigation, sidebar, global search, forms, grids, tabs, tables, drawers, dialogs and toasts
- Operational modules, Super Admin, onboarding, guest guide and food ordering
- Improved muted-text contrast and official StayQR browser branding

No database migration, Edge Function, Cashfree configuration or production branch change is included.

## Automated acceptance

Run:

```powershell
npm run check
```

Expected final gates:

- Lint: 0 errors; 7 inherited hook warnings
- Relative imports: PASS
- Day 7–18 security/source gates: PASS
- Local QR engine: PASS 5/5
- Batch A source acceptance: PASS 43/43
- Responsive platform source acceptance: PASS 46/46
- Production build: PASS

## Staging viewport matrix

| Device class | Viewport | Required result |
| --- | ---: | --- |
| Desktop | 1440 × 900 | Full sidebar, readable grids, no clipped controls |
| Laptop | 1280 × 800 | Full workflow remains visible and usable |
| Tablet landscape | 1024 × 768 | Grids compress, headers wrap, tables scroll only inside their panels |
| Tablet portrait | 820 × 1180 | Drawer navigation, touch controls and single-column forms work |
| Android | 393 × 852 | No horizontal page overflow, 44px controls, compact toasts |
| iPhone | 390 × 844 | Safe-area spacing, no input zoom, dialogs fit the visible screen |
| Small phone | 360 × 800 | Cards and actions stack without clipping |

Validate at least: Login, Dashboard, Reservations, Calendar, Rooms, Guests, Check-in/out, Payments, Folio, Service Requests, Food Orders, Amenities, Hotel Profile, Guest Guide Builder, Operations Centre, Reports, Super Admin, Onboarding and one signed Guest Guide.

The runtime gate passes only when every viewport has no page-level horizontal scrollbar, invisible text, overlapping navigation, clipped dialog action or unreachable control.

Tablet portrait uses the compact off-canvas navigation shell at widths up to 900px so the fixed desktop sidebar cannot squeeze operational content.

The navbar notification counter is rendered as a compact, high-contrast badge on desktop, tablet and mobile. Counts above nine are displayed as `9+`, while the full unread count remains available to assistive technology.
