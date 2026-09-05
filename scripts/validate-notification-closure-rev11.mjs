import fs from 'node:fs'
import path from 'node:path'

const root = process.cwd()
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8')
const checks = []

function check(name, ok) {
  checks.push({ name, ok: Boolean(ok) })
  console.log(`${ok ? 'PASS' : 'FAIL'} ${name}`)
}

const navbar = read('src/components/navbar/Navbar.jsx')
const navbarCss = read('src/components/navbar/Navbar.css')
const ops = read('src/pages/operationscenter/OperationsCenter.jsx')
const opsCss = read('src/pages/operationscenter/OperationsCenter.css')
const app = read('src/App.jsx')
const presentation = read('src/lib/notificationPresentation.js')

check('Navbar notification icons are SVG-based', navbar.includes('<NotificationTypeIcon') && navbar.includes('function NotificationTypeIcon'))
check('Navbar contains no historical mojibake notification glyphs', !/[Γ≡ƒ]/.test(navbar))
check('Notification footer uses SVG chevron', navbar.includes('<ChevronRightIcon />') && !navbar.includes('ΓåÆ'))
check('Notification popup limits itself to recent items', navbar.includes('notifications.slice(0, 10)'))
check('Notification popup supports mark all as read', navbar.includes('Mark all as read'))
check('Notification popup has retry/error state', navbar.includes('notif-inline-error') && navbar.includes('Retry'))
check('Read notifications remain clickable for routing', navbar.includes('getNotificationDestination(notification)'))
check('Notification click marks unread item before routing', navbar.includes("notification.status === 'unread'") && navbar.includes('markInboxNotificationRead(notification.id)'))
check('Notification presentation helper exists', presentation.includes('getNotificationDestination') && presentation.includes('getNotificationCategory'))
check('Payment notifications route to Payments', presentation.includes("match: ['payment'], section: 'payments'"))
check('Food notifications route to Food Orders', presentation.includes("match: ['food_order', 'food'], section: 'foodorders'"))
check('Service notifications route to Service Requests', presentation.includes("match: ['service_request', 'service'], section: 'services'"))
check('Reservation notifications route to Reservations', presentation.includes("match: ['reservation'], section: 'reservations'"))
check('Housekeeping notifications route to Housekeeping', presentation.includes("match: ['housekeeping'], section: 'housekeeping'"))
check('Maintenance notifications route to Maintenance', presentation.includes("match: ['maintenance'], section: 'maintenance'"))
check('Notification popup styles unread/read states', navbarCss.includes('.notif-item.unread') && navbarCss.includes('.notif-item.read'))
check('Notification popup has mobile drawer treatment', navbarCss.includes('bottom: max(8px, env(safe-area-inset-bottom'))
check('Notification centre uses commercial subtitle', ops.includes('Recent operational activity for this property'))
check('Notification centre uses mark all as read wording', ops.includes('Mark all as read'))
check('Notification centre no longer exposes event_key in card UI', !ops.includes("{item.event_key} ·"))
check('Notification centre supports click-through routing', ops.includes('handleInboxItemClick') && ops.includes('getNotificationDestination(item)'))
check('Notification centre click-through receives App navigation', app.includes('navigationRequestId={navigationRequest?.requestId || null}\n            onNavigate={handleNavigate}'))
check('Notification centre has unread badge treatment', ops.includes('d17-new-badge') && opsCss.includes('.d17-new-badge'))
check('Notification centre has responsive notification treatment', opsCss.includes('@media(max-width:700px)') && opsCss.includes('.d17-notification-toolbar'))

const failed = checks.filter((item) => !item.ok)
console.log(JSON.stringify({ checks: checks.length, passed: checks.length - failed.length, failed: failed.length }))
if (failed.length) process.exit(1)
