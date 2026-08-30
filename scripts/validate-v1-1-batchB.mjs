import fs from 'node:fs'
import path from 'node:path'

const root = process.cwd()
const read = (p) => fs.readFileSync(path.join(root,p),'utf8')
const exists = (p) => fs.existsSync(path.join(root,p))
const checks=[]
const expect=(name,ok)=>checks.push([name,Boolean(ok)])

const migration='supabase/migrations/202608300098_v1_1_batchB_operations_automation.sql'
const audit='supabase/audit/202608300099_v1_1_batchB_ACCEPTANCE.sql'
const page='src/pages/opsautomation/OperationsAutomation.jsx'
const css='src/pages/opsautomation/OperationsAutomation.css'
const lib='src/lib/v11Operations.js'
const app='src/App.jsx'
const sidebar='src/components/sidebar/Sidebar.jsx'
const staff='src/lib/currentStaff.js'

for (const p of [migration,audit,page,css,lib]) expect(`exists ${p}`,exists(p))

const m=read(migration), a=read(audit), p=read(page), l=read(lib), ap=read(app), sb=read(sidebar), st=read(staff)
expect('laundry schema',m.includes('create table if not exists public.laundry_orders'))
expect('lost found schema',m.includes('create table if not exists public.lost_found_items'))
expect('inventory schema',m.includes('create table if not exists public.inventory_items')&&m.includes('public.inventory_movements'))
expect('inventory request idempotency',m.includes('unique(hotel_id,request_key)'))
expect('inventory negative stock guard',m.includes("Inventory movement would create negative stock"))
expect('kot printer schema',m.includes('public.kitchen_printer_profiles')&&m.includes('public.kitchen_print_events'))
expect('existing Day15 KOT reused',m.includes('public.get_food_order_kot(p_hotel_id,p_order_id)'))
expect('scheduled report schema',m.includes('public.scheduled_report_jobs')&&m.includes('public.scheduled_report_runs'))
expect('existing Day16 report reused',m.includes('public.get_report_export_rows(p_hotel_id'))
expect('report run idempotency',m.includes('unique(job_id,scheduled_for)'))
expect('all new tables RLS',[
 'laundry_orders','lost_found_items','inventory_items','inventory_movements','kitchen_printer_profiles','kitchen_print_events','scheduled_report_jobs','scheduled_report_runs'
].every((t)=>m.includes(`alter table public.${t} enable row level security`)))
expect('anonymous tables revoked',m.includes('revoke all on table public.laundry_orders from public,anon'))
expect('authenticated writes RPC only',m.includes('revoke insert,update,delete on table public.inventory_movements from authenticated'))
expect('ops workspace RPC',m.includes('public.get_v11_operations_workspace'))
expect('laundry lifecycle RPCs',m.includes('public.create_v11_laundry_order')&&m.includes('public.update_v11_laundry_status'))
expect('lost found lifecycle RPCs',m.includes('public.create_v11_lost_found_item')&&m.includes('public.transition_v11_lost_found_item'))
expect('inventory movement RPC',m.includes('public.post_v11_inventory_movement'))
expect('KOT prepare RPC',m.includes('public.prepare_v11_kot_print'))
expect('scheduled report runner RPC',m.includes('public.run_due_v11_scheduled_reports'))
expect('audit expects 44 checks',a.includes("(44,'no_anon_rpc_execution'"))
expect('UI all five modules', ['Laundry','Lost & Found','Inventory','KOT / Printers','Scheduled Reports'].every((x)=>p.includes(x)))
expect('UI no direct new-table writes', !/\.from\(['"](?:laundry_orders|lost_found_items|inventory_items|inventory_movements|kitchen_printer_profiles|kitchen_print_events|scheduled_report_jobs|scheduled_report_runs)['"]\)[\s\S]{0,180}\.(?:insert|update|delete)\(/.test(p+l))
expect('lib RPC workspace',l.includes("rpc('get_v11_operations_workspace'"))
expect('lib inventory RPC',l.includes("rpc('post_v11_inventory_movement'"))
expect('lib KOT RPC',l.includes("rpc('prepare_v11_kot_print'"))
expect('lib report runner RPC',l.includes("rpc('run_due_v11_scheduled_reports'"))
expect('App lazy loads module',ap.includes("./pages/opsautomation/OperationsAutomation"))
expect('App route renders module',ap.includes("case 'opsautomation'"))
expect('Sidebar exposes module',sb.includes("id: 'opsautomation'")&&sb.includes("label: 'Ops Automation'"))
expect('Permission layer handles module',st.includes("section === 'opsautomation'"))
expect('Owner manager base includes module',st.includes("'opsautomation'"))
expect('Responsive CSS exists',read(css).includes('@media(max-width:640px)'))
expect('No production URL hardcoded in new module',!(p+l).includes('app.stayqr.in'))

const failed=checks.filter(([,ok])=>!ok)
for (const [name,ok] of checks) console.log(`${ok?'PASS':'FAIL'}  ${name}`)
console.log(`\nV1.1-B SOURCE ACCEPTANCE: ${checks.length-failed.length}/${checks.length} PASS`)
if (failed.length) process.exit(1)
