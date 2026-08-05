import fs from 'node:fs'
import path from 'node:path'

const root = process.cwd()
const migrationPath = path.join(
  root,
  'supabase/migrations/202608050058_day18_indexes_query_plans_trusted_pagination_REV1.sql'
)

if (!fs.existsSync(migrationPath)) {
  console.error(`FAIL missing — ${migrationPath}`)
  process.exit(1)
}

const sql = fs.readFileSync(migrationPath, 'utf8')

const indexes = [
  'idx_d18_reservations_cursor',
  'idx_d18_reservations_status_cursor',
  'idx_d18_reservations_source_cursor',
  'idx_d18_guests_updated_cursor',
  'idx_d18_guests_name_prefix',
  'idx_d18_guests_phone_prefix',
  'idx_d18_guests_email_prefix',
  'idx_d18_guest_sessions_cursor',
  'idx_d18_guest_sessions_status_cursor',
  'idx_d18_service_requests_status_cursor',
  'idx_d18_service_requests_department_cursor',
  'idx_d18_food_orders_status_cursor',
  'idx_d18_activity_logs_cursor',
  'idx_d18_activity_logs_entity_cursor',
  'idx_d18_notification_deliveries_status_cursor',
  'idx_d18_folios_status_cursor',
  'idx_d18_invoices_cursor',
  'idx_d18_payments_cursor',
  'idx_d18_housekeeping_status_cursor',
  'idx_d18_maintenance_status_cursor',
]

const rpcs = [
  'get_reservations_page',
  'get_guests_page',
  'get_guest_sessions_page',
  'get_service_requests_page',
  'get_food_orders_page',
  'get_activity_logs_page',
  'get_notification_deliveries_page',
  'get_folios_page',
  'get_day18_query_health',
]

const required = [
  ['advisory lock',
    sql.includes("stayqr:202608050058:day18-pagination-rev1")],
  ['page limit helper',
    sql.includes('private.day18_page_limit(')],
  ['cursor encoder',
    sql.includes('private.day18_encode_cursor(')],
  ['cursor decoder',
    sql.includes('private.day18_decode_cursor(')],
  ['tenant access assertion',
    sql.includes('private.day18_assert_page_access(')],
  ['limit clamped to 100',
    sql.includes('least(greatest(coalesce(p_requested, 50), 1), 100)')],
  ['opaque hex cursor',
    sql.includes("decode(trim(p_cursor), 'hex')")
      && sql.includes("'hex'")],
  ['stable tuple cursor',
    /\(r\.created_at,\s*r\.id\)\s*</.test(sql)],
  ['planner statistics',
    (sql.match(/set statistics 250/g) || []).length >= 20],
  ['analyze statements',
    (sql.match(/^analyze public\./gm) || []).length >= 10],
  ['query health diagnostics',
    sql.includes('pg_catalog.pg_stat_user_tables')
      && sql.includes('pg_catalog.pg_stat_user_indexes')],
  ['fixed acceptance helper',
    sql.includes('private.day18_migration_058_acceptance_rev1()')],
  ['fixed acceptance expectation',
    sql.includes('-- 100 rows')
      && sql.includes('-- 100 passed = true')
      && sql.includes('-- 0 failures')],
  ['all 20 indexes present',
    indexes.every((name) => sql.includes(name))],
  ['all 9 RPCs present',
    rpcs.every((name) =>
      sql.includes(`create or replace function public.${name}(`)
    )],
  ['all RPCs security definer',
    (sql.match(/security definer/g) || []).length >= 11],
  ['locked search paths',
    (sql.match(/set search_path = ''/g) || []).length >= 13],
  ['authenticated execute grants',
    rpcs.every((name) =>
      new RegExp(
        `grant execute on function public\\.${name}\\([\\s\\S]*?\\)\\s+to authenticated`,
        'i'
      ).test(sql)
    )],
  ['anonymous closure',
    rpcs.every((name) =>
      new RegExp(
        `revoke all on function public\\.${name}\\([\\s\\S]*?\\)\\s+from public, anon`,
        'i'
      ).test(sql)
    )],
  ['100-row composition',
    sql.includes('-- 12 prerequisite checks')
      && sql.includes('-- 20 index checks')
      && sql.includes('-- 4 private helper checks')
      && sql.includes('-- 9 RPCs × 5 contract checks = 45')
      && sql.includes('-- 9 authorized runtime shape checks')
      && sql.includes('-- 8 hard page-limit checks')
      && sql.includes('-- 2 global index-health checks')],
]

const unsafe = [
  ['business table insert',
    /\binsert\s+into\s+public\.(hotels|reservations|guests|guest_sessions|payments|folios|food_orders|service_requests)\b/i.test(sql)],
  ['business table update',
    /\bupdate\s+public\.(hotels|reservations|guests|guest_sessions|payments|folios|food_orders|service_requests)\b/i.test(sql)],
  ['business table delete',
    /\bdelete\s+from\s+public\.(hotels|reservations|guests|guest_sessions|payments|folios|food_orders|service_requests)\b/i.test(sql)],
  ['authenticated direct table write grant',
    /grant\s+(insert|update|delete)[\s\S]{0,500}\s+to authenticated/i.test(sql)],
  ['anonymous RPC grant',
    /grant execute on function public\.(get_reservations_page|get_guests_page|get_guest_sessions_page|get_service_requests_page|get_food_orders_page|get_activity_logs_page|get_notification_deliveries_page|get_folios_page|get_day18_query_health)[\s\S]{0,250}\s+to anon/i.test(sql)],
  ['unbounded page size',
    /limit\s+p_limit\b/i.test(sql)],
  ['offset pagination',
    /\boffset\s+p_/i.test(sql)],
  ['generic caller SQL execution',
    /execute\s+p_(sql|query)/i.test(sql)],
  ['service-role secret',
    /service[_-]?role[_-]?(key|secret)/i.test(sql)],
  ['external network call',
    /http_post|net\.http|pg_net/i.test(sql)],
  ['cron scheduling',
    /cron\.schedule|pg_cron/i.test(sql)],
  ['unsafe search path',
    /set search_path\s*=\s*public/i.test(sql)],
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
  `PASS — Day 18 Migration 058 source gate `
  + `(${required.length} required contracts; `
  + `${unsafe.length} unsafe patterns blocked; `
  + `20 indexes; 9 trusted RPCs; 100 fixed acceptance checks).`
)
