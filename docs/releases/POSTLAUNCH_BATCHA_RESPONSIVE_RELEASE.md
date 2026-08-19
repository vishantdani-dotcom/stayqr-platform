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
- Responsive platform source acceptance: PASS 68/68
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

## 430px overflow regression hotfix

The final staging hotfix removes the remaining iPhone-width clipping that was visible after the notification-badge correction:

- Navbar breadcrumb may shrink while menu, search, notifications and profile controls retain usable widths.
- Dashboard lazy-loaded CSS no longer restores desktop padding after the shared responsive layer.
- Dashboard headings and property names wrap inside the viewport instead of expanding the page.
- Property overview and quick-stat groups stretch and reflow safely at 430px and below.

The final structural correction removes JSX inline sidebar offsets and replaces them with explicit desktop state classes. At widths up to 900px, the shell, main region, content region and fixed navbar now resolve to the same bounded `100%` viewport width. The mobile navbar uses a two-column grid so its breadcrumb shrinks without pushing search, notifications or the profile control off-screen.

The confirmed root cause was additive child sizing inside two mobile flex layouts: a `width: 100%` child was rendered beside fixed-width siblings, so the combined width exceeded the 430px viewport. Hiding overflow concealed the excess without fixing the layout. The corrected navbar and property card use explicit shrinkable grid tracks (`minmax(0, 1fr)`) and bounded fixed-control columns. The dashboard subtitle and property metadata now wrap as deterministic mobile blocks.

The acceptance script now checks the exact mobile selector bodies and a 430px width budget, preventing broad regular-expression matches from producing a false pass.

Expected source gate: `RESPONSIVE_PLATFORM_SOURCE_ACCEPTANCE: PASS (68/68)`.
