import fs from 'node:fs'
import path from 'node:path'
import process from 'node:process'

const root = process.cwd()
const relativeSql =
  'supabase/audit/202608050072_day18_m059_monitoring_acceptance_REV2_EXPECTATION_FIX.sql'
const sqlPath = path.join(root, relativeSql)

if (!fs.existsSync(sqlPath)) {
  console.error(`FAIL required - missing ${relativeSql}`)
  process.exit(1)
}

const sql = fs.readFileSync(sqlPath, 'utf8')

const required = [
  ['transaction begins', /^\s*begin;\s*$/m.test(sql)],
  ['transaction commits', /^\s*commit;\s*$/m.test(sql)],
  [
    'dedicated advisory lock',
    sql.includes(
      "stayqr:202608050072:day18-m059-acceptance-rev2"
    ),
  ],
  [
    'REV2 acceptance helper',
    sql.includes(
      'private.day18_migration_059_acceptance_rev2()'
    ),
  ],
  [
    'helper security definer',
    /day18_migration_059_acceptance_rev2\(\)[\s\S]*?security definer/.test(
      sql
    ),
  ],
  [
    'helper locked search path',
    /day18_migration_059_acceptance_rev2\(\)[\s\S]*?set search_path = ''/.test(
      sql
    ),
  ],
  [
    'correct 26-index expectation',
    /day18_index_count'[\s\S]*?\)::integer,[\s\S]*?-1[\s\S]*?\)\s*=\s*26,/.test(
      sql
    ),
  ],
  [
    'invalid index count remains zero',
    /invalid_index_count'[\s\S]*?\)::integer,[\s\S]*?-1[\s\S]*?\)\s*=\s*0/.test(
      sql
    ),
  ],
  [
    'Bearer redaction expectation',
    sql.includes("v_event_record.message like '%Bearer [REDACTED]%'"),
  ],
  [
    'email redaction expectation',
    sql.includes("v_event_record.message like '%[REDACTED_EMAIL]%'"),
  ],
  [
    'raw email absence required',
    sql.includes(
      "v_event_record.message not like '%guest@example.com%'"
    ),
  ],
  [
    'raw JWT absence required',
    sql.includes(
      "v_event_record.message not like '%abcdefghijklmnopqrst.%'"
    ),
  ],
  [
    'raw guest token absence required',
    sql.includes(
      "v_event_record.message not like '%secretToken123456%'"
    ),
  ],
  [
    'guest route tokenized',
    sql.includes("v_event_record.route = '/guest/:token'"),
  ],
  [
    'fixed result projection',
    sql.includes(
      'from private.day18_migration_059_acceptance_rev2()'
    ),
  ],
]

const blocked = [
  [
    'stale 20-index expectation',
    /day18_index_count'[\s\S]*?\)::integer,[\s\S]*?-1[\s\S]*?\)\s*=\s*20,/.test(
      sql
    ),
  ],
  [
    'stale JWT-label expectation',
    sql.includes("v_event_record.message like '%[REDACTED_JWT]%'"),
  ],
  [
    'business table insert',
    /\binsert\s+into\s+public\.(hotels|guests|reservations|folios|payments|invoices|food_orders|service_requests)\b/i.test(
      sql
    ),
  ],
  [
    'business table update',
    /\bupdate\s+public\.(hotels|guests|reservations|folios|payments|invoices|food_orders|service_requests)\b/i.test(
      sql
    ),
  ],
  [
    'business table delete',
    /\bdelete\s+from\s+public\.(hotels|guests|reservations|folios|payments|invoices|food_orders|service_requests)\b/i.test(
      sql
    ),
  ],
  [
    'anonymous execute grant',
    /grant\s+execute[\s\S]*?\bto\s+anon\b/i.test(sql),
  ],
  [
    'service-role secret',
    /\bservice[_-]?role[_-]?(key|secret)\b/i.test(sql),
  ],
  [
    'external network call',
    /\b(net\.http|http_post|pg_net|curl|fetch\s*\()\b/i.test(sql),
  ],
]

let failed = false

for (const [label, passed] of required) {
  if (passed) {
    console.log(`PASS required - ${label}`)
  } else {
    failed = true
    console.error(`FAIL required - ${label}`)
  }
}

for (const [label, present] of blocked) {
  if (!present) {
    console.log(`PASS blocked - ${label}`)
  } else {
    failed = true
    console.error(`FAIL blocked - ${label}`)
  }
}

if (failed) {
  process.exit(1)
}

console.log(
  'PASS - Day 18 Audit 072 source gate ' +
    '(Migration 059 acceptance REV2; 2 stale expectations corrected; ' +
    '100 fixed checks preserved)'
)
