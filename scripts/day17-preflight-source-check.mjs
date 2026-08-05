import fs from 'node:fs'
import path from 'node:path'

const root = process.cwd()

const files = {
  notifications: path.join(root, 'src/lib/notifications.js'),
  navbar: path.join(root, 'src/components/navbar/Navbar.jsx'),
  app: path.join(root, 'src/App.jsx'),
  sidebar: path.join(root, 'src/components/sidebar/Sidebar.jsx'),
  superadmin: path.join(root, 'src/pages/superadmin/SuperAdmin.jsx'),
  commercial: path.join(root, 'src/lib/commercialControl.js'),
  hotelProfile: path.join(root, 'src/pages/hotel/HotelProfile.jsx'),
  currentStaff: path.join(root, 'src/lib/currentStaff.js'),
}

for (const [name, file] of Object.entries(files)) {
  if (!fs.existsSync(file)) {
    console.error(`FAIL missing source — ${name}: ${path.relative(root, file)}`)
    process.exit(1)
  }
}

const read = (key) => fs.readFileSync(files[key], 'utf8')
const notifications = read('notifications')
const navbar = read('navbar')
const app = read('app')
const sidebar = read('sidebar')
const superadmin = read('superadmin')
const commercial = read('commercial')
const hotelProfile = read('hotelProfile')
const currentStaff = read('currentStaff')
const combined = Object.values(files)
  .map((file) => fs.readFileSync(file, 'utf8'))
  .join('\n')

const required = [
  ['legacy notifications helper exists',
    /from\(["']notifications["']\)/.test(notifications)],
  ['legacy notification direct insert inventoried',
    /\.insert\(/.test(notifications)],
  ['legacy mark-read mutation inventoried',
    /markNotificationRead/.test(notifications)
      && /markAllNotificationsRead/.test(notifications)],
  ['Navbar notification inbox exists',
    /notif-dropdown/.test(navbar)
      && /getNotifications/.test(navbar)],
  ['Navbar realtime subscription exists',
    /postgres_changes/.test(navbar)
      && /table:\s*['"]notifications['"]/.test(navbar)],
  ['tenant hotel filter exists',
    /filter:\s*`hotel_id=eq\.\$\{hotelId\}`/.test(navbar)],
  ['hotel switch clears notification state',
    /setNotifications\(\[\]\)/.test(navbar)
      && /setNotifOpen\(false\)/.test(navbar)],
  ['support ticket client exists',
    /createSupportTicket/.test(commercial)
      && /addSupportMessage/.test(commercial)
      && /updateSupportTicketStatus/.test(commercial)],
  ['support ticket Super Admin UI exists',
    /Support/.test(superadmin)
      && /support_tickets/.test(superadmin)],
  ['announcement client exists',
    /createAnnouncement/.test(commercial)
      || /announcement/.test(commercial)],
  ['announcement Super Admin UI exists',
    /AnnouncementForm/.test(superadmin)
      && /announcement/.test(superadmin)],
  ['hotel profile exists',
    /Hotel Profile/.test(hotelProfile)
      || /Hotel Profile/.test(app)],
  ['Settings navigation exists',
    /id:\s*['"]settings['"]/.test(sidebar)],
  ['Settings is still ComingSoon baseline',
    !/case\s+['"]settings['"]/.test(app)],
  ['activity timeline page absent before Day 17',
    !/pages\/activity|ActivityTimeline/.test(app)],
  ['notification preference page absent before Day 17',
    !/NotificationPreferences/.test(app)],
  ['notification template page absent before Day 17',
    !/NotificationTemplates/.test(app)],
  ['email adapter page absent before Day 17',
    !/EmailAdapter/.test(app)],
  ['manual WhatsApp template page absent before Day 17',
    !/WhatsAppTemplates/.test(app)],
  ['role-aware navigation foundation exists',
    /canAccessSection/.test(sidebar)
      && /permission/.test(currentStaff)],
]

const unsafe = [
  ['service-role key in frontend',
    /service[_-]?role|SUPABASE_SERVICE/i.test(combined)],
  ['hard-coded production hotel UUID',
    /[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/i.test(combined)],
  ['unsafe HTML injection',
    /dangerouslySetInnerHTML|\.innerHTML\s*=/.test(combined)],
  ['automatic WhatsApp provider endpoint',
    /api\.whatsapp\.com|graph\.facebook\.com|whatsapp_business_messaging/i.test(combined)],
  ['automatic email provider secret',
    /SENDGRID_API_KEY|RESEND_API_KEY|MAILGUN_API_KEY/i.test(combined)],
  ['external notification webhook in frontend',
    /fetch\(\s*['"]https?:\/\//.test(notifications)],
]

for (const [name, ok] of required) {
  console.log(`${ok ? 'PASS' : 'FAIL'} baseline — ${name}`)
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
  `PASS — Day 17 preflight source inventory `
  + `(${required.length} baseline contracts; `
  + `${unsafe.length} unsafe patterns blocked).`
)
