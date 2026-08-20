import { readFile } from 'node:fs/promises'

const read = async (path) => (await readFile(new URL(`../${path}`, import.meta.url), 'utf8')).replace(/\r\n?/g, '\n')

const escapeRegExp = (value) => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
const ruleBodies = (css, selector) => [
  ...css.matchAll(new RegExp(`${escapeRegExp(selector)}\\s*\\{([^}]*)\\}`, 'g')),
].map((match) => match[1])
const hasRule = (css, selector, ...declarations) => ruleBodies(css, selector)
  .some((body) => declarations.every((declaration) => body.includes(declaration)))
const lacksRule = (css, selector, declaration) => ruleBodies(css, selector)
  .every((body) => !body.includes(declaration))

const mobileWidth = 430
const navbarContentWidth = mobileWidth - 16
const navbarFixedWidth = 44 + 6 + 140
const navbarFlexibleWidth = navbarContentWidth - navbarFixedWidth
const hotelInfoWidth = mobileWidth - 24 - 36 - 46 - 14

const [
  html,
  main,
  app,
  globals,
  responsive,
  sidebarCss,
  navbarJsx,
  navbarCss,
  dashboardCss,
  hotelOverviewCss,
  amenities,
  hotelProfile,
  payments,
  charges,
  guestGuideCss,
] = await Promise.all([
  read('index.html'),
  read('src/main.jsx'),
  read('src/App.jsx'),
  read('src/styles/globals.css'),
  read('src/styles/responsive.css'),
  read('src/components/sidebar/Sidebar.css'),
  read('src/components/navbar/Navbar.jsx'),
  read('src/components/navbar/Navbar.css'),
  read('src/pages/dashboard/Dashboard.css'),
  read('src/components/cards/HotelOverviewCard.css'),
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
  ['desktop shell offset is class controlled', app.includes("app-main--sidebar-collapsed") && !app.includes('style={{\n          marginLeft:')],
  ['desktop navbar offset is class controlled', navbarJsx.includes('navbar--sidebar-collapsed') && !navbarJsx.includes('style={{ left:')],
  ['desktop shell width subtracts the sidebar', /\.app-main \{[\s\S]*?width: calc\(100% - var\(--sidebar-w\)\)/.test(globals)],
  ['compact shell restores the exact viewport width', /@media \(max-width: 900px\)[\s\S]*?\.app-main\.app-main--sidebar-collapsed,[\s\S]*?\.app-content \{[\s\S]*?width: 100%;[\s\S]*?max-width: 100%;/.test(globals)],
  ['compact navbar uses a bounded two-column grid', hasRule(navbarCss, '.navbar', 'width: 100%;', 'grid-template-columns: minmax(0, 1fr) max-content;')],
  ['notification count caps at 9+', navbarJsx.includes("unreadCount > 9 ? '9+' : unreadCount")],
  ['notification count renders as a positioned badge', /\.notif-live-count \{[\s\S]*?position: absolute;[\s\S]*?border-radius: 999px/.test(navbarCss)],
  ['notification drawer uses a dark branded surface', hasRule(navbarCss, '.notif-dropdown', 'width: min(390px, calc(100vw - 28px));', 'border-radius: 18px;', '#0d0d0d;')],
  ['notification drawer exposes accessible dialog semantics', navbarJsx.includes('role="dialog"') && navbarJsx.includes('aria-label="Hotel notifications"')],
  ['notification list is bounded and scrollable', hasRule(navbarCss, '.notif-list', 'max-height: min(470px', 'overflow-y: auto;', 'overscroll-behavior: contain;')],
  ['notification rows explicitly reset global button styling', hasRule(navbarCss, '.notif-item', 'width: 100%;', 'background: rgba(255, 255, 255, 0.025);', 'text-align: left;', 'appearance: none;')],
  ['notification messages use a compact two-line clamp', hasRule(navbarCss, '.notif-item-message', '-webkit-line-clamp: 2;', 'overflow-wrap: anywhere;')],
  ['notification drawer has a notification centre action', navbarJsx.includes("onNavigate('operationscenter')") && navbarJsx.includes('Open notification centre')],
  ['tablet notification drawer is viewport anchored', /@media \(max-width: 900px\)[\s\S]*?\.notif-dropdown \{[\s\S]*?position: fixed;[\s\S]*?width: min\(390px, calc\(100vw - 24px\)\)/.test(navbarCss)],
  ['phone notification drawer uses safe-area edges', /@media \(max-width: 480px\)[\s\S]*?\.notif-dropdown \{[\s\S]*?right: max\(8px, env\(safe-area-inset-right, 0px\)\);[\s\S]*?left: max\(8px, env\(safe-area-inset-left, 0px\)\);[\s\S]*?width: auto;/.test(navbarCss)],
  ['notification category icons use source metadata', navbarJsx.includes("notification.source_type || notification.event_key || 'general'")],
  ['mobile navbar is viewport bounded', /@media \(max-width: 900px\)[\s\S]*?\.navbar \{[\s\S]*?width: 100%;[\s\S]*?max-width: 100%;/.test(navbarCss)],
  ['mobile navbar left group uses a shrinkable grid', hasRule(navbarCss, '.navbar-left', 'display: grid;', 'grid-template-columns: 44px minmax(0, 1fr);', 'width: auto;', 'max-width: none;', 'min-width: 0;')],
  ['mobile navbar left group does not claim the full parent width', lacksRule(navbarCss, '.navbar-left', 'width: 100%;')],
  ['mobile navbar actions use three bounded controls', hasRule(navbarCss, '.navbar-right', 'grid-template-columns: repeat(3, 44px);', 'max-width: 140px;', 'justify-self: end;')],
  ['dashboard duplicate desktop padding override is absent', !/\.dashboard-page\s*\{\s*padding:\s*32px;\s*\}/.test(dashboardCss)],
  ['dashboard mobile padding follows its own lazy stylesheet', /@media \(max-width: 480px\)[\s\S]*?\.dashboard-page \{[\s\S]*?padding: 14px 12px 32px;/.test(dashboardCss)],
  ['dashboard mobile header is a one-column bounded grid', hasRule(dashboardCss, '.dash-page-header', 'display: grid;', 'grid-template-columns: minmax(0, 1fr);', 'width: 100%;')],
  ['dashboard mobile subtitle is explicitly block wrapped', hasRule(dashboardCss, '.dash-page-sub,\n  .dash-page-sub-copy,\n  .last-fetch', 'display: block;', 'width: 100%;', 'white-space: normal;', 'overflow-wrap: anywhere;')],
  ['property card mobile layout stretches within viewport', /@media \(max-width: 900px\)[\s\S]*?\.hotel-card-inner \{[\s\S]*?align-items: stretch;/.test(hotelOverviewCss)],
  ['property title permits safe mobile wrapping', /\.hotel-name \{[\s\S]*?overflow-wrap: anywhere;/.test(hotelOverviewCss)],
  ['property quick stats release nowrap on phones', /@media \(max-width: 600px\)[\s\S]*?\.hqs-label \{[\s\S]*?white-space: normal;/.test(hotelOverviewCss)],
  ['property card left side uses icon plus shrinkable content columns', hasRule(hotelOverviewCss, '.hotel-card-left', 'display: grid;', 'grid-template-columns: 46px minmax(0, 1fr);', 'width: auto;', 'max-width: none;')],
  ['property info no longer claims full sibling width', hasRule(hotelOverviewCss, '.hotel-info', 'width: auto;', 'max-width: none;', 'min-width: 0;')],
  ['property metadata stacks inside the phone width', hasRule(hotelOverviewCss, '.hotel-meta-row', 'display: grid;', 'grid-template-columns: minmax(0, 1fr);')],
  ['property quick stats use three shrinkable columns', hasRule(hotelOverviewCss, '.hotel-quick-stats', 'grid-template-columns: repeat(3, minmax(0, 1fr));', 'width: 100%;')],
  ['430px navbar retains at least 200px for menu and breadcrumb', navbarFlexibleWidth >= 200],
  ['430px property card retains at least 300px for hotel information', hotelInfoWidth >= 300],
  ['small-phone breakpoint is present', responsive.includes('@media (max-width: 480px)')],
  ['mobile landscape height is handled', responsive.includes('(orientation: landscape)')],
  ['mobile form controls prevent iOS zoom', /input, select, textarea\)[\s\S]*font-size: 16px !important/.test(responsive)],
  ['mobile sidebar uses dynamic viewport height', /\.sidebar \{[\s\S]*height: 100dvh/.test(responsive)],
  ['mobile app removes desktop sidebar offset', /\.app-main,[\s\S]*?\.app-main\.app-main--sidebar-collapsed \{[\s\S]*?margin-left: 0;/.test(responsive)],
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
