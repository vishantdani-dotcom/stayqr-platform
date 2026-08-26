import { createHash } from 'node:crypto'
import { existsSync, readFileSync, readdirSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const sourceRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const marketingRoot = resolve(
  process.env.STAYQR_MARKETING_ROOT || join(sourceRoot, '..', 'marketing')
)
const results = []

function read(relativePath, root = sourceRoot) {
  const target = join(root, relativePath)
  if (!existsSync(target)) throw new Error(`Required file is missing: ${target}`)
  return readFileSync(target, 'utf8')
}

function check(name, condition, evidence = '') {
  const passed = Boolean(condition)
  results.push({ name, passed, evidence })
  if (!passed) throw new Error(`${name}${evidence ? ` — ${evidence}` : ''}`)
}

function includesAll(source, values) {
  return values.every((value) => source.includes(value))
}

function sha256(source) {
  // Git may materialize the same locked text as CRLF on Windows and LF in CI.
  // Hash canonical LF text so the gate detects content changes, not checkout style.
  const canonicalText = source.replace(/\r\n/g, '\n')
  return createHash('sha256').update(canonicalText).digest('hex')
}

function parseInlineScripts(html) {
  const scripts = [...html.matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/gi)]
  for (const [index, script] of scripts.entries()) {
    if (!script[1].trim()) continue
    // Parse only. The browser code is never executed by this gate.
    new Function(script[1])
    check(`marketing inline script ${index + 1} parses`, true, 'JavaScript syntax valid')
  }
}

try {
  const marketingCurrent = read('stayqr.in_current.html', marketingRoot)
  const marketingDeploy = read('DEPLOY_stayqr.in/index.html', marketingRoot)
  const pricingBlock = marketingCurrent.match(/<section[^>]+id="pricing"[\s\S]*?<\/section>/i)?.[0] || ''

  check('marketing deployment copies are identical', marketingCurrent === marketingDeploy)
  check('Hotel Login points to the application', marketingCurrent.includes('href="https://app.stayqr.in/login"') && marketingCurrent.includes('Hotel Login'))
  check('pricing contains monthly and yearly controls', includesAll(pricingBlock, ['data-billing="monthly"', 'data-billing="annual"', 'Monthly', 'Yearly']))
  check('pricing no longer books a demo', pricingBlock.length > 0 && !/BOOK DEMO/i.test(pricingBlock))
  check('all three paid plan routes exist', ['starter', 'growth', 'scale'].every((plan) => marketingCurrent.includes(`https://app.stayqr.in/signup?plan=${plan}&amp;billing=monthly&amp;mode=paid`)))
  check('all three trial plan routes exist', ['starter', 'growth', 'scale'].every((plan) => marketingCurrent.includes(`https://app.stayqr.in/signup?plan=${plan}&amp;billing=monthly&amp;mode=trial`)))
  check('yearly route rewriting is wired', includesAll(marketingCurrent, ['button.dataset.billing', "billing === 'annual'", 'plan-paid-link', 'plan-trial-link', 'pricing-billing-toggle']))
  check('deferred platform 24x7 claim is absent from acquisition marketing', !/24\s*(?:×|x|\/|\*)\s*7/i.test(marketingCurrent))
  parseInlineScripts(marketingCurrent)

  const app = read('src/App.jsx')
  const login = read('src/pages/auth/Login.jsx')
  const checkout = read('src/pages/acquisition/SubscriptionCheckout.jsx')
  const acquisition = read('src/lib/acquisition.js')
  check('signup, checkout, success and recovery routes exist', includesAll(app, ["authPath === '/signup'", "'/checkout/success'", "'/checkout/recover'", '<SubscriptionCheckout']))
  check('post-auth checkout selections are preserved', includesAll(login, ["['plan', 'billing', 'mode']", "'/checkout/success'", 'window.location.search']))
  check('checkout supports Cashfree and a separate trial path', includesAll(checkout, ['Continue to Cashfree', 'Start 14-day trial', 'createSelfServiceCheckout(payload)', 'startSelfServiceTrial(payload)']))
  check('checkout requires legal consent', includesAll(checkout, ['Terms', 'Subscription Policy', 'Privacy Policy', 'accepted']))
  check('checkout recovery polls authoritative intent status', includesAll(checkout, ['STATUS_POLLING', 'getMyAcquisitionIntent', '3500']))
  check('acquisition client uses RPC and Edge boundaries', includesAll(acquisition, ["supabase.rpc('get_public_subscription_plans')", "supabase.rpc('start_self_service_trial'", "'cashfree-create-self-service-checkout'", "supabase.rpc('get_my_acquisition_intent'"]))

  const migrationName = '202608180083_postlaunch_batch1_acquisition_search.sql'
  const migration = read(`supabase/migrations/${migrationName}`)
  const migrations = readdirSync(join(sourceRoot, 'supabase/migrations'))
  check('new migration follows locked Day 20 sequence', migrations.includes(migrationName) && migrations.includes('202608180082_day20f_invoice_number_allocator_overflow_hardening_REV1.sql'))
  check('locked Day 20 migration canonical content is identical', sha256(read('supabase/migrations/202608180082_day20f_invoice_number_allocator_overflow_hardening_REV1.sql')) === '5c5b2fc10a27252573746250aad6b93a80568b9825085157e5aea597316e9f3f')
  check('locked support runbook canonical content is identical', sha256(read('docs/launch/DAY20E4_OPERATIONAL_SUPPORT_RUNBOOK.md')) === '1d1f8e1c0ec2e36727b761fc54b82f5cccef4f5d4646202a623a7ec47d539833')
  check('acquisition ledger uses RLS and owner read scope', includesAll(migration, ['enable row level security', 'owner_user_id = (select auth.uid())', 'grant select on table public.self_service_acquisition_intents to authenticated']))
  check('paid provisioning is service-role only', includesAll(migration, ['finalize_self_service_acquisition', "caller_role <> 'service_role'", 'grant execute on function public.finalize_self_service_acquisition(uuid, jsonb) to service_role']))
  check('trial and paid paths reuse locked bootstrap', (migration.match(/public\.bootstrap_hotel_onboarding\(/g) || []).length === 2)
  check('public catalogue filters active public plans', includesAll(migration, ["sp.status = 'active'", 'sp.is_public = true']))
  check('workspace search is tenant and permission guarded', includesAll(migration, ['private.user_has_hotel_access(target_hotel_id)', 'private.user_has_permission', 'Phone ••••']))
  check('KYC deletion regression is server-owned', includesAll(migration, ['soft_delete_guest_document', "private.user_has_permission(target_hotel_id, 'guests.manage')", 'private.write_activity_log']))

  const createCheckout = read('supabase/functions/cashfree-create-self-service-checkout/index.ts')
  const webhook = read('supabase/functions/cashfree-webhook/index.ts')
  check('Cashfree amount comes from the server plan catalogue', includesAll(createCheckout, [".from('subscription_plans')", '.eq(\'is_public\', true)', 'plan.price_annual', 'plan.price_monthly', 'Math.round(amountMajor * 100)']))
  check('Cashfree request is authenticated and idempotent', includesAll(createCheckout, ['auth.getUser(token)', "'x-idempotency-key': requestId", "'x-request-id': requestId"]))
  check('Cashfree retry and restart paths are explicit', includesAll(createCheckout, ['resumeIntent', 'restart_allowed', "providerResponse.status === 409"]) && acquisition.includes('checkoutError.restartAllowed'))
  check('Cashfree mode is fail-closed', includesAll(createCheckout, ["['test', 'live', 'production']", 'CASHFREE_MODE must be test, live or production']))
  check('Cashfree return and webhook URLs are controlled', includesAll(createCheckout, ['/checkout/success?intent=', '/functions/v1/cashfree-webhook']))
  check('webhook retains raw-body signature verification', includesAll(webhook, ['const rawBody = await request.text()', 'hmacBase64(cashfreeClientSecret, `${timestamp}${rawBody}`)', 'constantTimeEqual(expectedSignature, receivedSignature)']))
  check('webhook validates amount, currency and payment identity', includesAll(webhook, ['acquisition currency does not match', 'paid amount is lower', 'missing its payment identity']))
  check('webhook provisions only after paid confirmation', includesAll(webhook, ["linkStatus === 'PAID'", "rpc('finalize_self_service_acquisition'", "status: 'paid'"]))

  const navbar = read('src/components/navbar/Navbar.jsx')
  const globalSearch = read('src/components/search/GlobalSearch.jsx')
  check('search button and keyboard shortcut are live', includesAll(navbar, ['setSearchOpen(true)', "event.key.toLowerCase() === 'k'", '<GlobalSearch']))
  check('search calls the permission-aware RPC', includesAll(globalSearch, ['supabase.rpc(', "'search_hotel_workspace'", 'target_hotel_id: hotelId', 'onNavigate?.(result.section']))

  const sidebar = read('src/components/sidebar/Sidebar.jsx')
  const guestGuide = read('src/pages/guestguide/GuestGuide.jsx')
  const guestDirectory = read('src/pages/guests/GuestDirectory.jsx')
  const copy = read('src/lib/guestGuideI18n.js')
  check('sidebar uses the official StayQR image asset', sidebar.includes("import stayqrLogo from '../../assets/stayqr-logo.png'") && sidebar.includes('src={stayqrLogo}'))
  check('sidebar no longer renders the generic admin lockup', !sidebar.includes('<span>Admin</span>') && !sidebar.includes('StayQR Admin'))
  check('active request action says Cancel', guestGuide.includes('{copy.cancel}') && !guestGuide.includes('{copy.cancelled}\n                    </button>') && copy.includes("cancel: 'Cancel'"))
  check('cancellation asks for confirmation', guestGuide.includes('window.confirm('))
  check('browser no longer writes KYC deletion metadata', guestDirectory.includes('"soft_delete_guest_document"') && !/\.from\(\s*["']guest_documents["']\s*\)[\s\S]{0,220}?\.update\s*\(/.test(guestDirectory))

  const indexCss = read('src/index.css')
  const responsiveCss = read('src/styles/responsive.css')
  const main = read('src/main.jsx')
  check('legacy light heading override was removed', !indexCss.includes('--text-h: #08060d') && !indexCss.includes('width: 1126px'))
  check('responsive correction layer is loaded', main.includes("import './styles/responsive.css'") && responsiveCss.includes('@media (max-width: 768px)'))
  check('mobile shell removes desktop offsets', includesAll(responsiveCss, ['.app-main.app-main--sidebar-collapsed', 'margin-left: 0;', 'left: 0;', 'width: 100%;', 'max-width: 100%;', 'overflow-x: hidden']))
  check('visible muted text contrast is raised', includesAll(responsiveCss, ['--text-muted: #b8b5ad', '--text-dim: #9d9a92']))

  for (const [index, result] of results.entries()) {
    console.log(`PASS ${String(index + 1).padStart(2, '0')} | ${result.name}${result.evidence ? ` | ${result.evidence}` : ''}`)
  }
  console.log(`POSTLAUNCH_BATCH1_SOURCE_ACCEPTANCE: PASS (${results.length}/${results.length})`)
} catch (error) {
  for (const [index, result] of results.entries()) {
    console.log(`${result.passed ? 'PASS' : 'FAIL'} ${String(index + 1).padStart(2, '0')} | ${result.name}${result.evidence ? ` | ${result.evidence}` : ''}`)
  }
  console.error(`POSTLAUNCH_BATCH1_SOURCE_ACCEPTANCE: FAIL | ${error.message}`)
  process.exitCode = 1
}
