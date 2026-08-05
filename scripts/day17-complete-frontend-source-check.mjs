import fs from 'node:fs'
import path from 'node:path'

const root = process.cwd()
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8')
const app = read('src/App.jsx')
const sidebar = read('src/components/sidebar/Sidebar.jsx')
const navbar = read('src/components/navbar/Navbar.jsx')
const role = read('src/lib/currentStaff.js')
const client = read('src/lib/day17Operations.js')
const page = read('src/pages/operationscenter/OperationsCenter.jsx')
const css = read('src/pages/operationscenter/OperationsCenter.css')

const required = [
  ['operations centre route', app.includes("case 'operationscenter'")],
  ['operations centre sidebar', sidebar.includes("id: 'operationscenter'")],
  ['operations centre permission', role.includes("operationscenter: 'hotel.manage'")],
  ['trusted inbox RPC', client.includes("rpc('get_notification_inbox'")],
  ['read RPC', client.includes("rpc('mark_notification_read'")],
  ['mark all read RPC', client.includes("rpc('mark_all_notifications_read'")],
  ['preferences RPC', client.includes("rpc('upsert_notification_preferences'")],
  ['template publish RPC', client.includes("rpc('publish_notification_template'")],
  ['activity RPC', client.includes("rpc('get_activity_timeline'")],
  ['settings get RPC', client.includes("rpc('get_hotel_system_settings'")],
  ['settings update RPC', client.includes("rpc('update_hotel_system_settings'")],
  ['support RPC', client.includes("rpc('get_support_workspace'")],
  ['announcements RPC', client.includes("rpc('get_active_announcements'")],
  ['retry RPC', client.includes("rpc('retry_notification_delivery'")],
  ['recipient realtime', client.includes("table: 'notification_recipients'")],
  ['delivery realtime', client.includes("table: 'notification_deliveries'")],
  ['all eight tabs', ['notifications','activity','preferences','templates','support','announcements','delivery','settings'].every((x) => page.includes(`['${x}'`))],
  ['email adapter UI', page.includes('Email Adapter')],
  ['manual WhatsApp UI', page.includes('Manual WhatsApp Template')],
  ['business day controls', page.includes('business_day_cutoff')],
  ['responsive CSS', css.includes('@media(max-width:700px)')],
  ['navbar trusted inbox', navbar.includes("from '../../lib/day17Operations'")],
]

const unsafe = [
  ['legacy notifications table in navbar', /\.from\(['"]notifications['"]\)/.test(navbar)],
  ['service-role key', /service[_-]?role[_-]?(key|secret)/i.test(client + page)],
  ['hard-coded hotel UUID', /[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/i.test(client + page)],
  ['automatic WhatsApp provider call', /graph\.facebook\.com|api\.whatsapp\.com/i.test(client + page)],
  ['provider secret field', /\b(api_key|api_secret|smtp_password|access_token)\b/i.test(client + page)],
  ['unsafe HTML', /dangerouslySetInnerHTML|innerHTML\s*=/.test(page)],
  ['external fetch', /\bfetch\s*\(/.test(client + page)],
  ['direct outbox insert', /\.from\(['"]notification_outbox['"]\)\s*\.insert/.test(client)],
  ['direct recipient insert', /\.from\(['"]notification_recipients['"]\)\s*\.insert/.test(client)],
  ['direct activity insert', /\.from\(['"]activity_logs['"]\)\s*\.insert/.test(client)],
]

for (const [name, ok] of required) console.log(`${ok ? 'PASS' : 'FAIL'} required — ${name}`)
for (const [name, hit] of unsafe) console.log(`${hit ? 'FAIL' : 'PASS'} blocked — ${name}`)

const failures = [...required.filter(([,ok]) => !ok), ...unsafe.filter(([,hit]) => hit)]
if (failures.length) process.exit(1)

console.log(`PASS — Day 17 complete frontend source gate (${required.length} required contracts; ${unsafe.length} unsafe patterns blocked).`)
