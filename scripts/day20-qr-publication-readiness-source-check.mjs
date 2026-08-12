import fs from 'node:fs'
import path from 'node:path'
import process from 'node:process'

const root = process.cwd()
const migrationPath = path.join(
  root,
  'supabase',
  'migrations',
  '202608120070_day20_guest_guide_publication_readiness_hardening_REV1.sql'
)

function fail(message) {
  console.error(`FAIL required - ${message}`)
  process.exit(1)
}

function pass(message) {
  console.log(`PASS required - ${message}`)
}

if (!fs.existsSync(migrationPath)) {
  fail('Day 20 Migration 070 source file is missing')
}

const sql = fs.readFileSync(migrationPath, 'utf8')
const helperMatch = sql.match(
  /CREATE OR REPLACE FUNCTION private\.day20_guest_guide_has_published_version_20260812[\s\S]*?\$function\$;/i
)

const checks = [
  ['Day 20 QR readiness repair is transactional', /\bbegin\s*;/i],
  ['Day 20 QR readiness repair uses advisory lock', /pg_advisory_xact_lock\s*\(/i],
  ['Published-version helper exists', Boolean(helperMatch)],
  ['Published-version helper resolves immutable version row', /join\s+public\.guest_guide_versions[\s\S]*?s\.published_version\s*>=\s*1/i],
  ['Published-version helper does not depend on current draft flag', Boolean(helperMatch) && !/publish_status/i.test(helperMatch[0])],
  ['QR readiness retains signed guest-access infrastructure', /qr_ready\s*:=\s*[\s\S]*?guest_access_tokens[\s\S]*?get_guest_access_links[\s\S]*?resolve_guest_portal/i],
  ['QR readiness requires immutable published version', /qr_ready\s*:=\s*[\s\S]*?day20_guest_guide_has_published_version_20260812\s*\(\s*target_hotel_id\s*\)/i],
  ['Refresh has non-QR publication gate', /non_qr_ready\s*:=[\s\S]*?ensure_guest_guide_foundation_20260811/i],
  ['Refresh publishes only when no published version exists', /non_qr_ready[\s\S]*?not\s+private\.day20_guest_guide_has_published_version_20260812[\s\S]*?ensure_guest_guide_foundation_20260811/i],
  ['Premium resolver fails closed when unpublished', /raise\s+exception\s+'Guest Guide is not published yet\.'/i],
  ['Premium resolver live-draft fallback removed', !/if\s+v_snapshot\s+is\s+null\s+then[\s\S]{0,220}?v_snapshot\s*:=\s*private\.day14_build_guide_snapshot/i.test(sql)],
  ['Completed-hotel publication invariant verified', /completed hotel has no immutable published Guest Guide version/i],
  ['Browser execution is revoked from publication helper', /revoke\s+all\s+on\s+function\s+private\.day20_guest_guide_has_published_version_20260812\s*\(\s*uuid\s*\)[\s\S]*?from\s+public\s*,\s*anon\s*,\s*authenticated\s*;/i],
  ['Day 20 QR readiness repair commits after verification', /\bcommit\s*;/i],
]

for (const [label, contract] of checks) {
  const ok = contract instanceof RegExp ? contract.test(sql) : Boolean(contract)
  if (!ok) fail(label)
  pass(label)
}

console.log(`PASS - Day 20 Gate 20A-3 QR publication source gate (${checks.length}/${checks.length})`)
