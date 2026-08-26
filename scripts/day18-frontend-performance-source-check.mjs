import fs from 'node:fs'
import path from 'node:path'

const root = process.cwd()

function read(relativePath) {
  const target = path.join(root, relativePath)
  if (!fs.existsSync(target)) {
    throw new Error(`Missing required source file: ${relativePath}`)
  }
  return fs.readFileSync(target, 'utf8')
}

function pass(label) {
  console.log(`PASS required - ${label}`)
}

function passBlocked(label) {
  console.log(`PASS blocked - ${label}`)
}

function requireContract(label, condition) {
  if (!condition) {
    throw new Error(`FAIL required - ${label}`)
  }
  pass(label)
}

function blockPattern(label, condition) {
  if (!condition) {
    throw new Error(`FAIL blocked - ${label}`)
  }
  passBlocked(label)
}

const app = read('src/App.jsx')
const main = read('src/main.jsx')
const boundary = read('src/components/system/AppErrorBoundary.jsx')
const loading = read('src/components/system/RouteLoadingFallback.jsx')
const statesCss = read('src/components/system/SystemStates.css')
const vite = read('vite.config.js')
const budget = read('scripts/day18-performance-budget.mjs')
const packageJson = JSON.parse(read('package.json').replace(/^\uFEFF/, ''))

const lazyImports = [...app.matchAll(/lazy\(\(\)\s*=>\s*import\(['"]\.\/pages\//g)]
const expectedRoutes = [
  './pages/dashboard/Dashboard',
  './pages/rooms/Rooms',
  './pages/checkin/CheckIn',
  './pages/guests/Guests',
  './pages/guestguide/GuestGuide',
  './pages/food/FoodMenu',
  './pages/foodorders/FoodOrders',
  './pages/services/ServiceRequests',
  './pages/payments/Payments',
  './pages/folios/FolioSettlement',
  './pages/amenities/Amenities',
  './pages/charges/Charges',
  './pages/housekeeping/Housekeeping',
  './pages/maintenance/Maintenance',
  './pages/auth/Login',
  './pages/auth/AuthAction',
  './pages/hotel/HotelProfile',
  './pages/guestbuilder/GuestGuideBuilder',
  './pages/reports/Reports',
  './pages/operationscenter/OperationsCenter',
  './pages/invoices/Invoices',
  './pages/invoices/InvoiceVerification',
  './pages/qr/QRGenerator',
  './pages/superadmin/SuperAdmin',
  './pages/menumanagement/MenuManagement',
  './pages/staff/StaffManagement',
  './pages/reservations/Reservations',
  './pages/calendar/BookingCalendar',
  './pages/operations/ReservationOperations',
  './pages/onboarding/HotelOnboarding',
  './pages/acquisition/SubscriptionCheckout',
]

let requiredCount = 0
let blockedCount = 0
const required = (label, condition) => {
  requireContract(label, condition)
  requiredCount += 1
}
const blocked = (label, condition) => {
  blockPattern(label, condition)
  blockedCount += 1
}

required('React lazy import', /import\s*\{[^}]*\blazy\b[^}]*\}\s*from\s*['"]react['"]/.test(app))
required('React Suspense import', /import\s*\{[^}]*\bSuspense\b[^}]*\}\s*from\s*['"]react['"]/.test(app))
required('required route-level lazy imports', lazyImports.length >= expectedRoutes.length)

for (const routePath of expectedRoutes) {
  required(`lazy route ${routePath}`, app.includes(`import('${routePath}')`))
}

required('sidebar remains eager shell', /import Sidebar from ['"]\.\/components\/sidebar\/Sidebar['"]/.test(app))
required('navbar remains eager shell', /import Navbar from ['"]\.\/components\/navbar\/Navbar['"]/.test(app))
required('application error boundary import', app.includes("import AppErrorBoundary from './components/system/AppErrorBoundary'"))
required('route loading fallback import', app.includes("import RouteLoadingFallback from './components/system/RouteLoadingFallback'"))
required('standalone public route boundary', app.includes('function StandaloneRouteBoundary'))
required('invoice verification boundary', app.includes('routeKey="invoice-verification"'))
required('guest guide boundary', app.includes('routeKey="guest-guide"'))
required('guest food boundary', app.includes('routeKey="guest-food-menu"'))
required('login boundary', app.includes('routeKey="login"'))
required('required onboarding boundary', app.includes('routeKey="required-onboarding"'))
required('authenticated section boundary', app.includes('scope={`section:${activeSection}`}'))
required('section boundary resets by tenant', app.includes("tenantContext?.selectedHotelId || 'none'"))
required('section suspense fallback', app.includes('<RouteLoadingFallback') && app.includes('{renderPage()}'))
required('root shell boundary', main.includes('scope="application-shell"'))
required('root boundary encloses App', /<AppErrorBoundary[\s\S]*<App\s*\/>[\s\S]*<\/AppErrorBoundary>/.test(main))
required('boundary derives error state', boundary.includes('static getDerivedStateFromError'))
required('boundary catches render failures', boundary.includes('componentDidCatch'))
required('boundary resets on navigation', boundary.includes('previousProps.resetKey !== this.props.resetKey'))
required('boundary user retry', boundary.includes('handleRetry'))
required('boundary controlled reload', boundary.includes('handleReload'))
required('boundary safe incident reference', boundary.includes('Support reference:'))
required('boundary safe structured diagnostic', boundary.includes("console.error('[StayQR boundary]', safeDiagnostic)"))
required('guest token route redaction', boundary.includes("return '/guest/:token'") && boundary.includes("return '/food/:token'") && boundary.includes("return '/invoice/verify/:token'"))
required('boundary diagnostic event foundation', boundary.includes("new CustomEvent('stayqr:client-error'"))
required('loading status semantics', loading.includes('role="status"'))
required('loading polite live region', loading.includes('aria-live="polite"'))
required('loading busy state', loading.includes('aria-busy="true"'))
required('responsive system states', statesCss.includes('@media (max-width: 560px)'))
required('reduced motion handling', statesCss.includes('@media (prefers-reduced-motion: reduce)'))
required('Vite build manifest', /manifest:\s*true/.test(vite))
required('Vite CSS code splitting', /cssCodeSplit:\s*true/.test(vite))
required('Vite compressed-size report', /reportCompressedSize:\s*true/.test(vite))
required('React vendor chunk', vite.includes("return 'vendor-react'"))
required('Supabase vendor chunk', vite.includes("return 'vendor-supabase'"))
required('document vendor chunk', vite.includes("return 'vendor-documents'"))
required('performance source script', packageJson.scripts?.['security:day18frontend'] === 'node scripts/day18-frontend-performance-source-check.mjs')
required('performance budget script', packageJson.scripts?.['performance:day18'] === 'node scripts/day18-performance-budget.mjs')
required('combined frontend validation script', packageJson.scripts?.['validate:day18frontend'] === 'npm run security:day17final && node scripts/day18-m058-source-check.mjs && npm run security:day18frontend && npm run build && npm run performance:day18 && npm run lint')
required('gzip performance measurement', budget.includes('gzipSync'))
required('initial dependency closure budget', budget.includes('collectStaticImports'))
required('dynamic-entry minimum', budget.includes('MIN_DYNAMIC_ENTRIES'))
required('entry gzip budget', budget.includes('MAX_INITIAL_JS_GZIP_KB'))
required('largest chunk budget', budget.includes('MAX_SINGLE_JS_GZIP_KB'))
required('total JavaScript budget', budget.includes('MAX_TOTAL_JS_GZIP_KB'))

blocked('eager page imports', !/^import\s+.+\s+from\s+['"]\.\/pages\//m.test(app))
blocked('unbounded dynamic import expression', !/import\(\s*[^'"`]/.test(app))
blocked('raw error message rendered by boundary', !/\{\s*this\.state\.error(Name)?\s*\}/.test(boundary))
blocked('raw Error object boundary logging', !/console\.error\([^\n]*,\s*error\s*\)/.test(boundary))
blocked('raw public token route logging', !/route:\s*window\.location\.pathname/.test(boundary))
blocked('dangerous HTML in system states', !/dangerouslySetInnerHTML/.test(`${boundary}\n${loading}`))
blocked('global error suppression', !/(window\.onerror\s*=|unhandledrejection[^\n]*preventDefault)/i.test(`${boundary}\n${main}`))
blocked('production source maps', !/sourcemap:\s*(true|['"]inline['"])/.test(vite))
blocked('eval execution', !/\beval\s*\(/.test(`${app}\n${boundary}\n${loading}\n${budget}`))
blocked('service-role secret', !/(service_role|SUPABASE_SERVICE_ROLE)/i.test(`${app}\n${boundary}\n${loading}\n${vite}\n${budget}`))
blocked('external performance upload', !/\b(fetch|XMLHttpRequest)\s*\(/.test(budget))

console.log(
  `PASS - Day 18 frontend performance source gate (${requiredCount} required contracts; ${blockedCount} unsafe patterns blocked; ${lazyImports.length} lazy routes)`
)
