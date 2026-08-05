import fs from 'node:fs'
import path from 'node:path'

const root = process.cwd()
const sqlPath = path.join(
  root,
  'supabase/audit/202608050070_day17_reversible_notification_runtime_acceptance_REV2_STATE_ORDER_FIX.sql'
)

if (!fs.existsSync(sqlPath)) {
  console.error(`FAIL missing Audit 070 SQL: ${sqlPath}`)
  process.exit(1)
}

const sql = fs.readFileSync(sqlPath, 'utf8')

const required = [
  ['Migration 056 prerequisite',
    sql.includes('Migration 056 REV2 acceptance passed 275/275')],
  ['controlled rollback marker',
    sql.includes('DAY17_A070_ROLLBACK_COMPLETE')],
  ['temporary reservation source',
    sql.includes('create temporary table reservations')],
  ['temporary payment source',
    sql.includes('create temporary table payments')],
  ['temporary service source',
    sql.includes('create temporary table service_requests')],
  ['installed trigger function',
    sql.includes('private.day17_capture_critical_event()')],
  ['exact-once replay',
    sql.includes('day17_enqueue_notification_event_internal')],
  ['notification inbox RPC',
    sql.includes('get_notification_inbox')],
  ['read-state RPCs',
    sql.includes('mark_notification_read')
      && sql.includes('mark_all_notifications_read')],
  ['authorization denials',
    sql.includes('foreign_hotel_access_denied')
      && sql.includes('anonymous_inbox_denied')],
  ['preference runtime',
    sql.includes('upsert_notification_preferences')],
  ['template runtime',
    sql.includes('publish_notification_template')],
  ['manual WhatsApp runtime',
    sql.includes(`'manual_whatsapp'`)
      && sql.includes('manual_action_url')],
  ['email failure runtime',
    sql.includes('EMAIL_ADAPTER_NOT_CONFIGURED')],
  ['retry and dead letter runtime',
    sql.includes('retry_notification_delivery')
      && sql.includes('notification_dead_letters')],
  ['activity timeline runtime',
    sql.includes('get_activity_timeline')],
  ['support runtime',
    sql.includes('get_support_workspace')],
  ['announcement runtime',
    sql.includes('get_active_announcements')],
  ['settings runtime',
    sql.includes('get_hotel_system_settings')],
  ['business-day runtime',
    sql.includes(`business_day_cutoff = '06:00'::time`)
      && sql.includes('resolve_hotel_business_date')],
  ['JWT claim restoration',
    sql.includes('v_previous_sub')
      && sql.includes('jwt_claims_restored')],
  ['fixed runtime count',
    sql.includes('75 rows / 75 passed / 0 failures')],
]

required.push(
  ['valid post-read delivery state',
    sql.includes("nd.status in ('delivered', 'read')")],
  ['retry state captured before second processing',
    sql.includes('into v_retry_cleared_dead_letter')
      && sql.indexOf('into v_retry_cleared_dead_letter')
         < sql.indexOf('v_email_process_2 := public.process_notification_outbox(1)')],
  ['retry assertion uses captured state',
    /'retry_cleared_dead_letter'[\s\S]*?\(v_retry_cleared_dead_letter\)/i.test(sql)],
  ['REV2 runtime helper',
    sql.includes('day17_a070_runtime_acceptance_rev2')],
)

const unsafe = [
  ['REV1 delivered-only assertion',
    sql.includes("and nd.status='delivered'")],
  ['production reservation fixture insert',
    /insert\s+into\s+public\.reservations/i.test(sql)],
  ['production payment fixture insert',
    /insert\s+into\s+public\.payments/i.test(sql)],
  ['production service fixture insert',
    /insert\s+into\s+public\.service_requests/i.test(sql)],
  ['automatic WhatsApp provider call',
    /graph\.facebook\.com|api\.whatsapp\.com/i.test(sql)],
  ['provider secret column definition',
    /(?:^|\n)\s*(api_key|api_secret|access_token|smtp_password)\s+(text|varchar|character varying|jsonb|bytea)\b/im.test(sql)],
  ['service-role secret',
    /service[_-]?role[_-]?(key|secret)/i.test(sql)],
  ['external network extension',
    /http_post|net\.http|pg_net|fetch\(/i.test(sql)],
  ['persistent fixture prefix',
    /D17-RT-(RES|PAY|SVC).*insert\s+into\s+public/i.test(sql)],
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
  `PASS — Day 17 Audit 070 source gate `
  + `(${required.length} required contracts; `
  + `${unsafe.length} unsafe patterns blocked; `
  + `75 fixed runtime checks).`
)
