import fs from 'node:fs'
import path from 'node:path'

const root = process.cwd()
const files = {
  app: fs.readFileSync(path.join(root, 'src/App.jsx'), 'utf8'),
  access: fs.readFileSync(path.join(root, 'src/lib/currentStaff.js'), 'utf8'),
  sidebar: fs.readFileSync(path.join(root, 'src/components/sidebar/Sidebar.jsx'), 'utf8'),
  lib: fs.readFileSync(path.join(root, 'src/lib/v11Revenue.js'), 'utf8'),
  revenue: fs.readFileSync(path.join(root, 'src/pages/revenue/RevenueGrowth.jsx'), 'utf8'),
  publicBooking: fs.readFileSync(path.join(root, 'src/pages/publicbooking/PublicBooking.jsx'), 'utf8'),
  migration: fs.readFileSync(path.join(root, 'supabase/migrations/202608280095_v1_1_batchA_revenue_reservation_finance.sql'), 'utf8'),
  audit: fs.readFileSync(path.join(root, 'supabase/audit/202608280096_v1_1_batchA_ACCEPTANCE.sql'), 'utf8'),
}

const expectations = [
  ['public booking route', files.app.includes("startsWith('/book/')") && files.app.includes('<PublicBooking />')],
  ['Revenue Growth route', files.app.includes("case 'revenue'") && files.app.includes('<RevenueGrowth')],
  ['Revenue Growth sidebar', files.sidebar.includes("id: 'revenue'")],
  ['Revenue Growth access map', files.access.includes("revenue: 'reservations.view'")],
  ['public booking client RPCs', /get_public_booking_hotel/.test(files.lib) && /get_public_booking_options/.test(files.lib) && /create_public_booking/.test(files.lib)],
  ['corporate client RPCs', /upsert_v11_corporate_account/.test(files.lib) && /upsert_v11_corporate_rate/.test(files.lib)],
  ['split stay client RPCs', /create_v11_stay_move_plan/.test(files.lib) && /verify_v11_stay_move_plan/.test(files.lib)],
  ['split bill client RPCs', /replace_v11_folio_split_plan/.test(files.lib) && /post_v11_split_share_collection/.test(files.lib)],
  ['accounting connector client RPC', /generate_v11_accounting_export/.test(files.lib)],
  ['Revenue Growth five modules', ['Direct Booking','Corporate Rates','Split Stay','Split Bill','Accounting'].every((label) => files.revenue.includes(label))],
  ['public booking honeypot', files.publicBooking.includes('public-booking-honeypot') && files.publicBooking.includes("website: ''")],
  ['public booking request idempotency', files.publicBooking.includes("createV11RequestId('public-booking')")],
  ['migration public booking disabled default', /enabled boolean not null default false/.test(files.migration) && /select h.id, false/.test(files.migration)],
  ['migration new tables', ['public_booking_settings','corporate_accounts','corporate_rates','stay_move_plans','folio_split_shares','accounting_export_profiles'].every((name) => files.migration.includes(`public.${name}`))],
  ['migration preserves existing core by additive functions', !/create or replace function public\.post_folio_collection\(/i.test(files.migration) && !/create or replace function public\.move_active_walkin_guest_room\(/i.test(files.migration)],
  ['anon direct table access revoked', /revoke all on table public\.public_booking_settings from public, anon/i.test(files.migration)],
  ['anon safe RPC grants only', /grant execute on function public\.get_public_booking_options/i.test(files.migration) && /grant execute on function public\.create_public_booking/i.test(files.migration)],
  ['internal workspace not anon', /revoke all on function public\.get_v11_revenue_workspace\(uuid\) from public/i.test(files.migration)],
  ['split bill uses authoritative Day 11 collection helper', files.migration.includes('private.day11_post_collection')],
  ['accounting uses authoritative Day 12 helpers', files.migration.includes('private.day12_build_accounting_csv') && files.migration.includes('private.day12_hash_text')],
  ['audit requires 34 checks', files.audit.includes('select 34') && files.audit.includes('public_booking_rpcs_security_definer')],
]

let failed = 0
for (const [name, pass] of expectations) {
  console.log(`${pass ? 'PASS' : 'FAIL'}  ${name}`)
  if (!pass) failed += 1
}

if (failed > 0) {
  console.error(`\nV1.1-A source validation failed: ${failed} check(s).`)
  process.exit(1)
}

console.log(`\nV1.1-A source validation passed: ${expectations.length}/${expectations.length}`)
