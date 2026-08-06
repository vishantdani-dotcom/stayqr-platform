import fs from 'node:fs'
import path from 'node:path'

const root = process.cwd()
const sql = fs.readFileSync(
  path.join(
    root,
    'docs/database/legacy-migrations/pre-day18-canonical-baseline/202608050057_day17_rls_helper_trusted_config_rpc_hotfix_REV1.sql'
  ),
  'utf8'
)
const client = fs.readFileSync(
  path.join(root, 'src/lib/day17Operations.js'),
  'utf8'
)

const required = [
  ['helper authenticated execute grant',
    /grant execute on function private\.day17_can_manage_hotel\(uuid\)\s+to authenticated/i.test(sql)],
  ['helper anon revoke',
    /revoke all on function private\.day17_can_manage_hotel\(uuid\)[\s\S]*?from public, anon, authenticated/i.test(sql)],
  ['email writer RPC definition',
    sql.includes('public.upsert_email_adapter_config(')],
  ['email writer security definer',
    /create or replace function public\.upsert_email_adapter_config[\s\S]*?security definer/i.test(sql)],
  ['email writer authorization',
    /upsert_email_adapter_config[\s\S]*?private\.day17_can_manage_hotel\(p_hotel_id\)/i.test(sql)],
  ['email secret ignored',
    /secret_reference,\s*\n\s*endpoint_name[\s\S]*?\n\s*null,/i.test(sql)],
  ['WhatsApp writer RPC definition',
    sql.includes('public.upsert_manual_whatsapp_template(')],
  ['WhatsApp writer security definer',
    /create or replace function public\.upsert_manual_whatsapp_template[\s\S]*?security definer/i.test(sql)],
  ['WhatsApp writer authorization',
    /upsert_manual_whatsapp_template[\s\S]*?private\.day17_can_manage_hotel\(p_hotel_id\)/i.test(sql)],
  ['trusted RPC execute grants',
    /grant execute on function[\s\S]*?upsert_email_adapter_config\(uuid,jsonb\)[\s\S]*?upsert_manual_whatsapp_template\(uuid,jsonb\)[\s\S]*?to authenticated/i.test(sql)],
  ['direct config writes revoked',
    /revoke insert, update, delete on table[\s\S]*?email_adapter_configs[\s\S]*?whatsapp_templates[\s\S]*?from public, anon, authenticated/i.test(sql)],
  ['fixed acceptance count',
    sql.includes('37 rows / 37 passed / 0 failures')],
  ['frontend email RPC',
    client.includes("rpc('upsert_email_adapter_config'")],
  ['frontend WhatsApp RPC',
    client.includes("'upsert_manual_whatsapp_template'")],
  ['frontend hotel scope',
    client.includes('p_hotel_id: hotelId')],
  ['frontend safe payload',
    client.includes('metadata: payload.metadata || {}')],
]

const unsafe = [
  ['frontend direct email upsert',
    /\.from\(['"]email_adapter_configs['"]\)[\s\S]{0,500}\.upsert\(/.test(client)],
  ['frontend direct WhatsApp upsert',
    /\.from\(['"]whatsapp_templates['"]\)[\s\S]{0,500}\.upsert\(/.test(client)],
  ['automatic WhatsApp provider call',
    /graph\.facebook\.com|api\.whatsapp\.com/i.test(sql + client)],
  ['provider secret accepted from payload',
    /p_payload\s*->>\s*['"]secret_reference['"]/i.test(sql)],
  ['service-role secret',
    /service[_-]?role[_-]?(key|secret)/i.test(sql + client)],
  ['external fetch',
    /\bfetch\s*\(/.test(client)],
  ['direct config table grant',
    /grant\s+(insert|update|delete)[\s\S]*?(email_adapter_configs|whatsapp_templates)[\s\S]*?to authenticated/i.test(sql)],
  ['hard-coded hotel UUID',
    /[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/i.test(client)],
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
if (failures.length) process.exit(1)

console.log(
  `PASS — Day 17 Migration 057/frontend hotfix source gate `
  + `(${required.length} required contracts; `
  + `${unsafe.length} unsafe patterns blocked).`
)
