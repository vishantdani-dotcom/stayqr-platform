import { readFile } from 'node:fs/promises'

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), 'utf8')

const [
  html,
  main,
  responsive,
  sidebarCss,
  navbarCss,
  amenities,
  hotelProfile,
  payments,
  charges,
  guestGuideCss,
] = await Promise.all([
  read('index.html'),
  read('src/main.jsx'),
  read('src/styles/responsive.css'),
  read('src/components/sidebar/Sidebar.css'),
  read('src/components/navbar/Navbar.css'),
  read('src/pages/amenities/Amenities.jsx'),
  read('src/pages/hotel/HotelProfile.jsx'),
  read('src/pages/payments/Payments.jsx'),
  read('src/pages/charges/Charges.jsx'),
  read('src/pages/guestguide/GuestGuide.css'),
])

const checks = [
  ['viewport includes safe-area cover', html.includes('viewport-fit=cover')],
  ['Android theme colour is declared', html.includes('name="theme-color"')],
  ['mobile web app capability is declared', html.includes('name="mobile-web-app-capable"')],
  ['iOS web app capability is declared', html.includes('name="apple-mobile-web-app-capable"')],
  ['iOS status bar style is declared', html.includes('apple-mobile-web-app-status-bar-style')],
  ['browser title uses StayQR branding', html.includes('<title>StayQR</title>')],
  [
    'responsive layer is imported after globals',
    main.indexOf("./styles/responsive.css") > main.indexOf("./styles/globals.css"),
  ],
  ['iOS text autosizing is controlled', responsive.includes('-webkit-text-size-adjust: 100%')],
  ['safe top inset is declared', responsive.includes('--safe-top: env(safe-area-inset-top')],
  ['safe bottom inset is declared', responsive.includes('--safe-bottom: env(safe-area-inset-bottom')],
  ['dynamic viewport height is supported', responsive.includes('100dvh')],
  ['minimum 320px viewport is protected', responsive.includes('min-width: 320px')],
  ['44px touch target is defined', responsive.includes('--touch-target: 44px')],
  ['coarse pointer devices receive touch targets', responsive.includes('(pointer: coarse)')],
  ['tablet breakpoint is present', responsive.includes('@media (max-width: 1180px)')],
  ['compact shell breakpoint includes tablet portrait', responsive.includes('@media (max-width: 900px)')],
  ['tablet sidebar becomes off-canvas', /@media \(max-width: 900px\)[\s\S]*?\.sidebar \{[\s\S]*?transform: translateX\(-100%\)/.test(sidebarCss)],
  ['tablet navbar exposes the menu control', /@media \(max-width: 900px\)[\s\S]*?\.navbar-menu-btn\s*\{\s*display: flex/.test(navbarCss)],
  ['small-phone breakpoint is present', responsive.includes('@media (max-width: 480px)')],
  ['mobile landscape height is handled', responsive.includes('(orientation: landscape)')],
  ['mobile form controls prevent iOS zoom', /input, select, textarea\)[\s\S]*font-size: 16px !important/.test(responsive)],
  ['mobile sidebar uses dynamic viewport height', /\.sidebar \{[\s\S]*height: 100dvh/.test(responsive)],
  ['mobile app removes desktop sidebar offset', responsive.includes('margin-left: 0 !important')],
  ['wide tables use touch scrolling', responsive.includes('-webkit-overflow-scrolling: touch')],
  ['wide tables retain readable intrinsic width', /\) table \{\s*max-width: none/.test(responsive)],
  ['mobile tabs scroll horizontally', /\.d17-tabs,[\s\S]*overflow-x: auto/.test(responsive)],
  ['mobile dialogs are viewport bounded', responsive.includes('max-height: calc(100dvh - 24px')],
  ['global search is mobile viewport bounded', /\.global-search-dialog \{[\s\S]*100dvh/.test(responsive)],
  ['mobile toasts are compact and bottom anchored', /\.ag-toast[\s\S]*bottom: calc\(76px/.test(responsive)],
  ['reduced motion is respected', responsive.includes('@media (prefers-reduced-motion: reduce)')],
  ['muted text contrast token is raised', responsive.includes('--text-muted: #b8b5ad')],
  ['dashboard is covered by shared mobile layout', responsive.includes('.dashboard-page')],
  ['calendar is covered by shared mobile layout', responsive.includes('.booking-calendar-page')],
  ['guest directory is covered by shared mobile layout', responsive.includes('.guest-directory-shell')],
  ['operations centre is covered by shared mobile layout', responsive.includes('.d17-page')],
  ['super admin is covered by shared mobile layout', responsive.includes('.commercial-shell')],
  ['onboarding is covered by shared mobile layout', responsive.includes('.onboarding-shell')],
  ['guest guide mobile card grids are covered', responsive.includes('.ag-card-grid')],
  ['food ordering mobile grid is covered', responsive.includes('.food-item-grid')],
  ['amenities has a responsive root hook', amenities.includes('className="amenities-page"')],
  ['hotel profile has a responsive root hook', hotelProfile.includes('className="hotel-profile-page"')],
  ['payments has a responsive root hook', payments.includes('className="payments-page"')],
  ['charges has a responsive root hook', charges.includes('className="charges-page"')],
  ['existing compact guest toast correction is preserved', /\.ag-toast[\s\S]*top: auto/.test(guestGuideCss)],
]

let passed = 0
for (const [label, ok] of checks) {
  if (!ok) {
    console.error(`FAIL | ${label}`)
    continue
  }
  passed += 1
  console.log(`PASS | ${label}`)
}

if (passed !== checks.length) {
  console.error(`RESPONSIVE_PLATFORM_SOURCE_ACCEPTANCE: FAIL (${passed}/${checks.length})`)
  process.exit(1)
}

console.log(`RESPONSIVE_PLATFORM_SOURCE_ACCEPTANCE: PASS (${passed}/${checks.length})`)
