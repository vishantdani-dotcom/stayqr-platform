import fs from 'node:fs'
import path from 'node:path'

const root = process.cwd()
const read = (relative) =>
  fs.readFileSync(path.join(root, relative), 'utf8')

const files = {
  packageJson: 'package.json',
  envExample: '.env.example',
  main: 'src/main.jsx',
  app: 'src/App.jsx',
  monitoring: 'src/lib/day18Monitoring.js',
  operationsPage: 'src/pages/operationscenter/OperationsCenter.jsx',
  operationsCss: 'src/pages/operationscenter/OperationsCenter.css',
  migration:
    'supabase/migrations/202608050059_day18_monitoring_structured_logs_operational_diagnostics_REV1.sql',
  runbook: 'docs/operations/DAY18_MONITORING_RUNBOOK.md',
  performanceBudget: 'scripts/day18-performance-budget.mjs',
  performanceDecision:
    'docs/operations/DAY18_M059_PERFORMANCE_BUDGET_CALIBRATION.md',
}

for (const relative of Object.values(files)) {
  if (!fs.existsSync(path.join(root, relative))) {
    console.error(`FAIL missing — ${relative}`)
    process.exit(1)
  }
}

const packageBytes = fs.readFileSync(path.join(root, files.packageJson))
const packageText = packageBytes.toString('utf8')
const packageJson = JSON.parse(packageText)
const envExample = read(files.envExample)
const main = read(files.main)
const app = read(files.app)
const monitoring = read(files.monitoring)
const page = read(files.operationsPage)
const css = read(files.operationsCss)
const migration = read(files.migration)
const runbook = read(files.runbook)
const performanceBudget = read(files.performanceBudget)
const performanceDecision = read(files.performanceDecision)

const required = [
  [
    'package JSON valid',
    packageJson?.scripts?.['security:day18monitoring'] ===
      'node scripts/day18-monitoring-source-check.mjs',
  ],
  [
    'combined validation command',
    packageJson?.scripts?.['validate:day18monitoring']?.includes(
      'security:day18monitoring'
    ) &&
      packageJson.scripts['validate:day18monitoring'].includes(
        'performance:day18'
      ),
  ],
  ['package JSON no BOM', packageBytes[0] !== 0xef],
  ['environment label documented', envExample.includes('VITE_APP_ENV=')],
  ['release label documented', envExample.includes('VITE_APP_RELEASE=')],
  [
    'monitoring installed before render',
    main.includes('installOperationalMonitoring()') &&
      main.indexOf('installOperationalMonitoring()') <
        main.indexOf('createRoot('),
  ],
  [
    'monitoring performance cap calibrated',
    performanceBudget.includes(
      "positiveNumberFromEnv('STAYQR_MAX_INITIAL_JS_GZIP_KB', 355)"
    ),
  ],
  [
    'monitoring performance decision recorded',
    performanceDecision.includes('349.4 KiB') &&
      performanceDecision.includes('351.1 KiB') &&
      performanceDecision.includes('355 KiB'),
  ],
  [
    'monitoring context wired',
    app.includes('setMonitoringContext({') &&
      app.includes('monitoringHotelId') &&
      app.includes('monitoringUserId'),
  ],
  ['monitoring module Supabase client', monitoring.includes("from './supabase'")],
  [
    'structured writer RPC',
    monitoring.includes("rpc('report_operational_error'"),
  ],
  [
    'diagnostics reader RPC',
    monitoring.includes("rpc('get_operational_diagnostics'"),
  ],
  [
    'incident status RPC',
    monitoring.includes("'set_operational_incident_status'"),
  ],
  [
    'global error listener',
    monitoring.includes("addEventListener('error'"),
  ],
  [
    'unhandled rejection listener',
    monitoring.includes("addEventListener('unhandledrejection'"),
  ],
  [
    'React boundary listener',
    monitoring.includes("addEventListener('stayqr:client-error'"),
  ],
  ['guest route redaction', monitoring.includes("return '/guest/:token'")],
  ['food route redaction', monitoring.includes("return '/food/:token'")],
  [
    'invoice route redaction',
    monitoring.includes("return '/invoice/verify/:token'"),
  ],
  ['email redaction', monitoring.includes('[REDACTED_EMAIL]')],
  ['JWT redaction', monitoring.includes('[REDACTED_JWT]')],
  ['phone redaction', monitoring.includes('[REDACTED_PHONE]')],
  [
    'local duplicate suppression',
    monitoring.includes('recentFingerprints') &&
      monitoring.includes('deduplicated_locally'),
  ],
  [
    'offline-safe transport',
    monitoring.includes('navigator.onLine') &&
      monitoring.includes('offline: true'),
  ],
  [
    'hotel-scoped transport',
    monitoring.includes('p_hotel_id: hotelId'),
  ],
  [
    'release context',
    monitoring.includes('VITE_APP_RELEASE') &&
      monitoring.includes('release:'),
  ],
  [
    'request context',
    monitoring.includes('createRequestId') &&
      monitoring.includes('request_id:'),
  ],
  [
    'fixed safe context',
    ['online', 'visibility_state', 'viewport', 'stack_frames', 'network_type', 'retryable']
      .every((key) => monitoring.includes(key)),
  ],
  [
    'diagnostics tab',
    page.includes("['diagnostics', 'Diagnostics']"),
  ],
  [
    'diagnostics state',
    page.includes('setDiagnostics') &&
      page.includes('diagnosticFilters'),
  ],
  [
    'diagnostics health copy',
    page.includes('Operational Health & Error Diagnostics'),
  ],
  [
    'diagnostics search controls',
    page.includes('Search incident, request or error'),
  ],
  [
    'diagnostics status actions',
    page.includes('Acknowledge') &&
      page.includes('Resolve') &&
      page.includes('Reopen'),
  ],
  [
    'diagnostics query health',
    page.includes('invalid_index_count') &&
      page.includes('day18_index_count'),
  ],
  [
    'diagnostics responsive CSS',
    css.includes('.d18-health-banner') &&
      css.includes('@media(max-width:700px)'),
  ],
  [
    'operational table',
    migration.includes(
      'create table if not exists public.operational_error_events'
    ),
  ],
  [
    'RLS enabled',
    migration.includes(
      'alter table public.operational_error_events enable row level security'
    ),
  ],
  [
    'RLS forced',
    migration.includes(
      'alter table public.operational_error_events force row level security'
    ),
  ],
  [
    'direct table access revoked',
    migration.includes(
      'revoke all on table public.operational_error_events'
    ),
  ],
  [
    'server text sanitizer',
    migration.includes('private.day18_safe_log_text('),
  ],
  [
    'server context allowlist',
    migration.includes('private.day18_safe_log_context('),
  ],
  [
    'trusted report writer',
    migration.includes('public.report_operational_error('),
  ],
  [
    'service role writer grant',
    /grant execute on function public\.report_operational_error\(uuid,\s*jsonb\)\s+to authenticated,\s*service_role;/i.test(
      migration
    ),
  ],
  [
    'manager health snapshot',
    migration.includes('public.get_operational_health_snapshot('),
  ],
  [
    'manager diagnostics',
    migration.includes('public.get_operational_diagnostics('),
  ],
  [
    'manager status transition',
    migration.includes('public.set_operational_incident_status('),
  ],
  [
    'hotel access authority',
    migration.includes('private.user_has_hotel_access(p_hotel_id)'),
  ],
  [
    'hotel management authority',
    migration.includes('private.day17_can_manage_hotel(p_hotel_id)'),
  ],
  [
    'locked search paths',
    (
      migration.match(/set search_path = ''/g) || []
    ).length >= 7,
  ],
  [
    'anonymous RPC closure',
    (
      migration.match(/from public, anon;/g) || []
    ).length >= 4,
  ],
  [
    'deduplication window',
    migration.includes("interval '30 minutes'") &&
      migration.includes('occurrence_count = occurrence_count + 1'),
  ],
  [
    'payload size bound',
    migration.includes('Operational payload exceeds 16 KiB'),
  ],
  [
    'diagnostic range bound',
    migration.includes("interval '31 days'"),
  ],
  [
    'diagnostic page bound',
    migration.includes(
      'greatest(1, least(coalesce(p_limit, 50), 100))'
    ),
  ],
  [
    'Migration 058 query health reused',
    migration.includes('public.get_day18_query_health(p_hotel_id)'),
  ],
  [
    'fixed acceptance helper',
    migration.includes(
      'private.day18_migration_059_acceptance_rev1()'
    ),
  ],
  [
    'fixed acceptance expectation',
    migration.includes('100 rows / 100 passed / 0 failures'),
  ],
  [
    'acceptance cleanup',
    migration.includes(
      "where request_id = 'd18-m059-acceptance'"
    ),
  ],
  [
    'runbook trusted writer contract',
    runbook.includes('report_operational_error'),
  ],
  [
    'runbook privacy boundary',
    runbook.includes('Never log raw guest tokens'),
  ],
  [
    'runbook incident workflow',
    runbook.includes('Acknowledge') &&
      runbook.includes('Resolve') &&
      runbook.includes('Reopen'),
  ],
]

const blocked = [
  [
    'anonymous monitoring writer grant',
    /grant execute on function public\.report_operational_error[\s\S]{0,120}\bto\b[^;]*\banon\b/i,
  ],
  [
    'authenticated direct table insert',
    /grant\s+insert\s+on\s+(table\s+)?public\.operational_error_events\s+to\s+authenticated/i,
  ],
  [
    'authenticated direct table update',
    /grant\s+update\s+on\s+(table\s+)?public\.operational_error_events\s+to\s+authenticated/i,
  ],
  [
    'raw browser URL capture',
    /window\.location\.(href|search|hash)/,
  ],
  [
    'cookie capture',
    /document\.cookie/,
  ],
  [
    'localStorage dump',
    /JSON\.stringify\(\s*window\.localStorage/,
  ],
  [
    'raw stack persistence',
    /error\.stack\s*[,}]/,
  ],
  [
    'direct operational table write',
    /\.from\(['"]operational_error_events['"]\)\s*\.\s*(insert|update|delete)/,
  ],
  [
    'external monitoring fetch',
    /\bfetch\s*\(\s*['"]https?:\/\//,
  ],
  [
    'service-role browser secret',
    /VITE_[A-Z0-9_]*(SERVICE|SECRET)[A-Z0-9_]*/,
  ],
  [
    'hard-coded production hotel UUID',
    /['"][0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}['"]/i,
  ],
  [
    'unbounded diagnostics result',
    /\.from\(['"]operational_error_events['"]\)[\s\S]{0,500}\.select\(/,
  ],
]

let failed = false

for (const [name, passed] of required) {
  if (passed) {
    console.log(`PASS required — ${name}`)
  } else {
    failed = true
    console.error(`FAIL required — ${name}`)
  }
}

const combined = [
  packageText,
  envExample,
  main,
  app,
  monitoring,
  page,
  css,
  migration,
  runbook,
].join('\n')

for (const [name, pattern] of blocked) {
  if (pattern.test(combined)) {
    failed = true
    console.error(`FAIL blocked — ${name}`)
  } else {
    console.log(`PASS blocked — ${name}`)
  }
}

if (failed) {
  process.exit(1)
}

console.log(
  `PASS — Day 18 monitoring source gate (${required.length} required contracts; ${blocked.length} unsafe patterns blocked; fixed 100-row Migration 059 acceptance)`
)
