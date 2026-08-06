import fs from 'node:fs'
import path from 'node:path'

const root = process.cwd()
const migration = path.join(
  root,
  'docs/database/legacy-migrations/pre-day18-canonical-baseline/202608050056_day17_notification_activity_support_settings_foundation_REV2_JSON_SYNTAX_FIX.sql'
)

if (!fs.existsSync(migration)) {
  console.error(`FAIL missing migration: ${migration}`)
  process.exit(1)
}

const sql = fs.readFileSync(migration, 'utf8')

const tables = [
  "notification_event_catalog",
  "notification_preferences",
  "notification_templates",
  "notification_template_versions",
  "notification_outbox",
  "notification_deliveries",
  "notification_delivery_attempts",
  "notification_dead_letters",
  "notification_recipients",
  "email_adapter_configs",
  "whatsapp_templates",
  "business_day_settings"
]
const functions = [
  "public.get_notification_inbox(uuid,integer,timestamptz)",
  "public.mark_notification_read(uuid)",
  "public.mark_all_notifications_read(uuid)",
  "public.upsert_notification_preferences(uuid,jsonb)",
  "public.publish_notification_template(uuid,text,text,jsonb)",
  "public.enqueue_notification_event(uuid,text,uuid,jsonb)",
  "public.process_notification_outbox(integer)",
  "public.retry_notification_delivery(uuid)",
  "public.get_activity_timeline(uuid,timestamptz,timestamptz,jsonb)",
  "public.get_hotel_system_settings(uuid)",
  "public.update_hotel_system_settings(uuid,jsonb)",
  "public.get_support_workspace(uuid)",
  "public.get_active_announcements(uuid)",
  "private.day17_can_manage_hotel(uuid)",
  "private.resolve_hotel_business_date(uuid,timestamptz)",
  "private.day17_render_notification_text(text,jsonb)",
  "private.day17_enqueue_notification_event_internal(uuid,text,uuid,jsonb,uuid)",
  "private.day17_capture_critical_event()",
  "private.day17_capture_support_event()",
  "private.day17_capture_announcement_event()"
]
const required = [
  ['all twelve Day 17 tables',
    tables.every((name) => sql.includes(`public.${name}`))],
  ['all trusted and private functions',
    functions.every((signature) => {
      const name = signature.split('(')[0]
      return sql.includes(name)
    })],
  ['reservation trigger', sql.includes('day17_reservation_notification_event')],
  ['payment trigger', sql.includes('day17_payment_notification_event')],
  ['service trigger', sql.includes('day17_service_request_notification_event')],
  ['support event compatibility', sql.includes('support_ticket_events')],
  ['announcement actual column', sql.includes('target_hotel_id')],
  ['support actual created-by column', sql.includes('created_by')],
  ['actual Day 8 tax column', sql.includes('default_tax_percent')],
  ['transactional outbox', sql.includes('day17_enqueue_notification_event_internal')],
  ['idempotency unique', sql.includes('notification_outbox_hotel_idempotency_unique')],
  ['recipient realtime', sql.includes('notification_recipients replica identity full')],
  ['delivery retry ledger', sql.includes('notification_delivery_attempts')],
  ['dead-letter ledger', sql.includes('notification_dead_letters')],
  ['email secret reference only', sql.includes('secret_reference')],
  ['manual WhatsApp template library', sql.includes('whatsapp_templates')],
  ['business-date resolver', sql.includes('resolve_hotel_business_date')],
  ['activity timeline', sql.includes('get_activity_timeline')],
  ['system settings RPCs',
    sql.includes('get_hotel_system_settings')
      && sql.includes('update_hotel_system_settings')],
  ['support workspace', sql.includes('get_support_workspace')],
  ['active announcements', sql.includes('get_active_announcements')],
  ['fixed acceptance', sql.includes('day17_migration_056_acceptance_rev2')],
]

required.push(
  ['JSON seed syntax corrected',
    (sql.match(/jsonb_build_array\('in_app'\)/g) || []).length === 9],
  ['REV2 acceptance helper',
    sql.includes('day17_migration_056_acceptance_rev2')],
)

const unsafe = [
  ['unquoted JSON array cast',
    /(?:^|[,=(]\s*)\[\s*["'][^\]]+\]\s*::\s*jsonb/im.test(sql)],
  ['automatic WhatsApp provider call',
    /graph\.facebook\.com|api\.whatsapp\.com|sendWhatsApp/i.test(sql)],
  ['email secret column definition',
    /(?:^|\n)\s*(api_key|api_secret|access_token|smtp_password)\s+(text|varchar|character varying|jsonb|bytea)\b/i.test(sql)],
  ['support_ticket_messages invention',
    /create\s+table\s+(if\s+not\s+exists\s+)?public\.support_ticket_messages/i.test(sql)],
  ['announcement hotel_id assumption',
    /announcements\.hotel_id|\ba\.hotel_id\b/.test(sql)],
  ['wrong support created_by_user_id',
    /support_tickets\.created_by_user_id/.test(sql)],
  ['wrong hotel_settings tax_rate',
    /hotel_settings\.tax_rate|\bhs\.tax_rate\b/.test(sql)],
  ['service-role secret',
    /service[_-]?role[_-]?(key|secret)/i.test(sql)],
  ['dynamic provider network request',
    /http_post|net\.http|pg_net|fetch\(/i.test(sql)],
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
  `PASS — Migration 056 source gate `
  + `(${required.length} required contracts; `
  + `${unsafe.length} unsafe patterns blocked).`
)
