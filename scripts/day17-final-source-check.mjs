import fs from 'node:fs'
import path from 'node:path'

const root = process.cwd()
const read = (relative) => fs.readFileSync(path.join(root, relative), 'utf8')

const files = {
  app: 'src/App.jsx',
  sidebar: 'src/components/sidebar/Sidebar.jsx',
  navbar: 'src/components/navbar/Navbar.jsx',
  currentStaff: 'src/lib/currentStaff.js',
  operations: 'src/lib/day17Operations.js',
  page: 'src/pages/operationscenter/OperationsCenter.jsx',
  css: 'src/pages/operationscenter/OperationsCenter.css',
  m056: 'docs/database/legacy-migrations/pre-day18-canonical-baseline/202608050056_day17_notification_activity_support_settings_foundation_REV2_JSON_SYNTAX_FIX.sql',
  a070: 'supabase/audit/202608050070_day17_reversible_notification_runtime_acceptance_REV2_STATE_ORDER_FIX.sql',
  m057: 'docs/database/legacy-migrations/pre-day18-canonical-baseline/202608050057_day17_rls_helper_trusted_config_rpc_hotfix_REV1.sql',
  a071: 'supabase/audit/202608050071_day17_final_consolidated_acceptance_REV1.sql',
  packageJson: 'package.json',
}

for (const relative of Object.values(files)) {
  if (!fs.existsSync(path.join(root, relative))) {
    console.error(`FAIL missing — ${relative}`)
    process.exit(1)
  }
}

const app = read(files.app)
const sidebar = read(files.sidebar)
const navbar = read(files.navbar)
const currentStaff = read(files.currentStaff)
const operations = read(files.operations)
const page = read(files.page)
const css = read(files.css)
const m056 = read(files.m056)
const a070 = read(files.a070)
const m057 = read(files.m057)
const a071 = read(files.a071)

const packageBytes = fs.readFileSync(path.join(root, files.packageJson))
const packageText = packageBytes.toString('utf8')

const finalMarkers = a071.match(/-- FINAL_CHECK_\d{2}/g) || []

const required = [
  ['operations centre route',
    app.includes("case 'operationscenter'")],
  ['operations centre import',
    (app.includes("import OperationsCenter from './pages/operationscenter/OperationsCenter'") || app.includes("const OperationsCenter = lazy(() => import('./pages/operationscenter/OperationsCenter'))"))],
  ['operations centre sidebar',
    sidebar.includes("id: 'operationscenter'")],
  ['operations centre role permission',
    currentStaff.includes("operationscenter: 'hotel.manage'")],
  ['platform admin route access',
    currentStaff.includes("'operationscenter'")],
  ['all eight workspaces',
    [
      "['notifications', 'Notifications']",
      "['activity', 'Activity']",
      "['preferences', 'Preferences']",
      "['templates', 'Templates']",
      "['support', 'Support']",
      "['announcements', 'Announcements']",
      "['delivery', 'Delivery']",
      "['settings', 'System settings']",
    ].every((contract) => page.includes(contract))],
  ['notification centre copy',
    page.includes('Notification Centre')],
  ['activity timeline copy',
    page.includes('Activity Timeline')],
  ['preferences copy',
    page.includes('My Notification Preferences')],
  ['versioned templates copy',
    page.includes('Publish Notification Template')],
  ['support workspace copy',
    page.includes('Support Workspace')],
  ['announcements copy',
    page.includes('Active Announcements')],
  ['delivery retry copy',
    page.includes('Delivery Failures & Retry')],
  ['email adapter copy',
    page.includes('Email Adapter')],
  ['manual WhatsApp copy',
    page.includes('Manual WhatsApp Template')],
  ['system settings copy',
    page.includes('Hotel System Settings')],
  ['responsive CSS',
    css.includes('@media(max-width:700px)')],
  ['trusted inbox RPC',
    operations.includes("rpc('get_notification_inbox'")],
  ['trusted read RPC',
    operations.includes("rpc('mark_notification_read'")],
  ['trusted mark-all RPC',
    operations.includes("rpc('mark_all_notifications_read'")],
  ['trusted preferences RPC',
    operations.includes("rpc('upsert_notification_preferences'")],
  ['trusted template RPC',
    operations.includes("rpc('publish_notification_template'")],
  ['trusted activity RPC',
    operations.includes("rpc('get_activity_timeline'")],
  ['trusted settings read RPC',
    operations.includes("rpc('get_hotel_system_settings'")],
  ['trusted settings update RPC',
    operations.includes("rpc('update_hotel_system_settings'")],
  ['trusted support RPC',
    operations.includes("rpc('get_support_workspace'")],
  ['trusted announcements RPC',
    operations.includes("rpc('get_active_announcements'")],
  ['trusted retry RPC',
    operations.includes("rpc('retry_notification_delivery'")],
  ['trusted email writer RPC',
    operations.includes("rpc('upsert_email_adapter_config'")],
  ['trusted WhatsApp writer RPC',
    operations.includes("'upsert_manual_whatsapp_template'")],
  ['notification recipient realtime',
    operations.includes("table: 'notification_recipients'")],
  ['notification delivery realtime',
    operations.includes("table: 'notification_deliveries'")],
  ['navbar trusted inbox cutover',
    navbar.includes("from '../../lib/day17Operations'")],
  ['navbar unread state',
    navbar.includes("item.status === 'unread'")],
  ['Migration 056 accepted helper',
    m056.includes('private.day17_migration_056_acceptance_rev2()')],
  ['Migration 056 notification inbox',
    m056.includes('public.get_notification_inbox(')],
  ['Migration 056 activity timeline',
    m056.includes('public.get_activity_timeline(')],
  ['Migration 056 support workspace',
    m056.includes('public.get_support_workspace(')],
  ['Migration 056 announcements',
    m056.includes('public.get_active_announcements(')],
  ['Migration 056 business date',
    m056.includes('private.resolve_hotel_business_date(')],
  ['Audit 070 REV2 helper',
    a070.includes('private.day17_a070_runtime_acceptance_rev2()')],
  ['Audit 070 75-row expectation',
    a070.includes('75 rows / 75 passed / 0 failures')],
  ['Audit 070 post-read state fix',
    a070.includes("nd.status in ('delivered', 'read')")],
  ['Audit 070 retry state-order fix',
    a070.includes('v_retry_cleared_dead_letter')],
  ['Migration 057 helper grant',
    /grant execute on function private\.day17_can_manage_hotel\(uuid\)\s+to authenticated/i.test(m057)],
  ['Migration 057 email writer',
    m057.includes('public.upsert_email_adapter_config(')],
  ['Migration 057 WhatsApp writer',
    m057.includes('public.upsert_manual_whatsapp_template(')],
  ['Migration 057 37-row expectation',
    m057.includes('37 rows / 37 passed / 0 failures')],
  ['Audit 071 helper',
    a071.includes('private.day17_a071_final_consolidated_acceptance_rev1()')],
  ['Audit 071 replays Migration 056',
    a071.includes('private.day17_migration_056_acceptance_rev2() accepted')],
  ['Audit 071 replays Audit 070',
    a071.includes('private.day17_a070_runtime_acceptance_rev2() accepted')],
  ['Audit 071 replays Migration 057',
    a071.includes('private.day17_migration_057_acceptance_rev1() accepted')],
  ['Audit 071 final fixed markers',
    finalMarkers.length === 33],
  ['Audit 071 accurate expectation',
    a071.includes('-- 420 rows')
      && a071.includes('-- 420 passed = true')
      && a071.includes('-- 0 failures')],
  ['Audit 071 authorized real reads',
    a071.includes('notification_inbox_real_authorized_read')
      && a071.includes('activity_timeline_real_authorized_read')
      && a071.includes('system_settings_real_authorized_read')
      && a071.includes('support_workspace_real_authorized_read')
      && a071.includes('announcements_real_authorized_read')],
  ['Audit 071 JWT restoration',
    a071.includes("current_setting('request.jwt.claim.sub', true)")
      && a071.includes("set_config(\n    'request.jwt.claim.sub'")],
  ['package JSON valid',
    (() => {
      try {
        JSON.parse(packageText)
        return true
      } catch {
        return false
      }
    })()],
  ['package JSON no BOM',
    !(
      packageBytes.length >= 3
      && packageBytes[0] === 0xef
      && packageBytes[1] === 0xbb
      && packageBytes[2] === 0xbf
    )],
]

const combinedFrontend = [
  app,
  sidebar,
  navbar,
  currentStaff,
  operations,
  page,
].join('\n')

const unsafe = [
  ['legacy notifications table in navbar',
    /\.from\(['"]notifications['"]\)/.test(navbar)],
  ['direct email adapter upsert',
    /\.from\(['"]email_adapter_configs['"]\)[\s\S]{0,600}\.upsert\(/.test(operations)],
  ['direct WhatsApp template upsert',
    /\.from\(['"]whatsapp_templates['"]\)[\s\S]{0,600}\.upsert\(/.test(operations)],
  ['direct notification outbox insert',
    /\.from\(['"]notification_outbox['"]\)[\s\S]{0,400}\.insert\(/.test(operations)],
  ['direct notification recipient insert',
    /\.from\(['"]notification_recipients['"]\)[\s\S]{0,400}\.insert\(/.test(operations)],
  ['direct activity log insert',
    /\.from\(['"]activity_logs['"]\)[\s\S]{0,400}\.insert\(/.test(operations)],
  ['automatic WhatsApp provider call',
    /graph\.facebook\.com|api\.whatsapp\.com/i.test(combinedFrontend + m056 + m057)],
  ['provider secret field',
    /\b(api_key|api_secret|smtp_password|access_token)\b/i.test(combinedFrontend)],
  ['service-role key',
    /service[_-]?role[_-]?(key|secret)/i.test(combinedFrontend)],
  ['hard-coded production hotel UUID',
    /[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/i.test(combinedFrontend)],
  ['unsafe HTML',
    /dangerouslySetInnerHTML|\.innerHTML\s*=/.test(combinedFrontend)],
  ['external frontend fetch',
    /\bfetch\s*\(['"]https?:\/\//.test(combinedFrontend)],
  ['anon management-helper grant',
    /grant execute on function private\.day17_can_manage_hotel\(uuid\)\s+to anon/i.test(m057)],
  ['direct authenticated config write grant',
    /grant\s+(insert|update|delete)[\s\S]*?(email_adapter_configs|whatsapp_templates)[\s\S]*?to authenticated/i.test(m057)],
  ['provider secret accepted by Migration 057',
    /p_payload\s*->>\s*['"]secret_reference['"]/i.test(m057)],
  ['Audit 071 business data insert',
    /\binsert\s+into\s+public\.(reservations|payments|service_requests|food_orders|guest_sessions)\b/i.test(a071)],
]

for (const [name, ok] of required) {
  console.log(`${ok ? 'PASS' : 'FAIL'} required — ${name}`)
}
for (const [name, hit] of unsafe) {
  console.log(`${hit ? 'FAIL' : 'PASS'} blocked — ${name}`)
}

const failures = [
  ...required.filter(([, ok]) => !ok),
  ...unsafe.filter(([, hit]) => hit),
]

if (failures.length) {
  process.exit(1)
}

console.log(
  `PASS — Day 17 final source gate `
  + `(${required.length} required contracts; `
  + `${unsafe.length} unsafe patterns blocked; `
  + `420 fixed database checks).`
)
