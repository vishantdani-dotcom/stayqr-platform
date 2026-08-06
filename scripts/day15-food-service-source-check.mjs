import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const read = (relative) => fs.readFileSync(path.join(root, relative), 'utf8')

const sources = {
  migration: read('docs/database/legacy-migrations/pre-day18-canonical-baseline/202608040052_day15_trusted_food_service_workflows_REV1.sql'),
  guestPortal: read('src/lib/guestPortal.js'),
  operations: read('src/lib/day15Operations.js'),
  foodGuest: read('src/pages/food/FoodMenu.jsx'),
  foodStaff: read('src/pages/foodorders/FoodOrders.jsx'),
  services: read('src/pages/services/ServiceRequests.jsx'),
  menu: read('src/pages/menumanagement/MenuManagement.jsx'),
  guide: read('src/pages/guestguide/GuestGuide.jsx'),
}

const combined = Object.values(sources).join('\n')
const required = [
  ['signed menu resolver', /get_guest_food_menu/],
  ['idempotent food placement', /place_guest_food_order/],
  ['modifier selection', /modifier_ids/],
  ['tax snapshot', /tax_inclusive/],
  ['food guest cancellation', /cancel_guest_food_order/],
  ['trusted food transition', /update_food_order_status/],
  ['ready kitchen stage', /['\"]ready['\"]/],
  ['KOT payload', /get_food_order_kot/],
  ['exact-once food folio posting', /post_food_order_to_folio/],
  ['food analytics', /get_food_operations_analytics/],
  ['dynamic guest service catalogue', /get_guest_service_catalog/],
  ['dynamic service request creation', /create_guest_service_request/],
  ['guest service cancellation', /cancel_guest_service_request/],
  ['trusted assignment', /assign_service_request/],
  ['trusted priority', /update_service_request_priority/],
  ['trusted service transition', /update_service_request_status/],
  ['SLA escalation reconciliation', /escalate_overdue_service_requests/],
  ['guest notification history', /get_guest_notifications/],
  ['service analytics', /get_service_operations_analytics/],
  ['food request id generation', /createRequestId/],
  ['guest modifier modal', /selectedModifiers/],
  ['guest food live tracking', /ORDER_RECHECK_INTERVAL_MS/],
  ['kitchen command board', /COLUMNS/],
  ['KOT print UI', /printKot/],
  ['service department queue', /DEPARTMENTS/],
  ['service SLA countdown', /sla_due_at/],
  ['menu tax editor', /tax_rate/],
  ['menu modifier editor', /modifier_group_id/],
  ['guest-guide service cancellation', /cancelGuestServiceRequest/],
  ['signed-token revalidation retained', /ACCESS_RECHECK_INTERVAL_MS/],
  ['Day 11 food synchronizer retained', /day11_sync_food_order/],
  ['Day 11 service synchronizer retained', /day11_post_service_request_charge/],
]

const missing = required.filter(([, pattern]) => !pattern.test(combined))
if (missing.length) {
  console.error('FAIL — missing Day 15 contracts:')
  for (const [label] of missing) console.error(`- ${label}`)
  process.exit(1)
}

const unsafe = [
  ['food staff direct order update', /\.from\(['\"]food_orders['\"]\)[\s\S]{0,280}?\.update\(/, sources.foodStaff],
  ['service staff direct request update', /\.from\(['\"]service_requests['\"]\)[\s\S]{0,280}?\.update\(/, sources.services],
  ['guest direct food insert', /\.from\(['\"]food_orders['\"]\)[\s\S]{0,280}?\.insert\(/, sources.foodGuest],
  ['guest direct service insert', /\.from\(['\"]service_requests['\"]\)[\s\S]{0,280}?\.insert\(/, sources.guide],
  ['legacy guest food array-only RPC', /p_items:\s*items\s*[,}]/, sources.guestPortal],
  ['legacy five-stage food tracker', /pending['\"],\s*['\"]accepted['\"],\s*['\"]preparing['\"],\s*['\"]out_for_delivery/, sources.foodGuest],
  ['hard-coded SQL service allowlist', /normalized_type\s+not\s+in\s*\(/i, sources.migration],
  ['anonymous operational table grant', /grant\s+(insert|update|delete)[\s\S]{0,120}?to\s+anon/i, sources.migration],
  ['authenticated direct food order write grant', /grant\s+(?:insert|update|delete)(?:\s*,\s*(?:insert|update|delete))*\s+on(?:\s+table)?\s+public\.food_orders\s+to\s+authenticated/i, sources.migration],
  ['authenticated direct service request write grant', /grant\s+(?:insert|update|delete)(?:\s*,\s*(?:insert|update|delete))*\s+on(?:\s+table)?\s+public\.service_requests\s+to\s+authenticated/i, sources.migration],
  ['destructive food table drop', /drop\s+table[\s\S]{0,80}?food_/i, sources.migration],
  ['destructive service table drop', /drop\s+table[\s\S]{0,80}?service_/i, sources.migration],
]

const triggered = unsafe.filter(([, pattern, source]) => pattern.test(source))
if (triggered.length) {
  console.error('FAIL — unsafe Day 15 patterns detected:')
  for (const [label] of triggered) console.error(`- ${label}`)
  process.exit(1)
}

console.log(`PASS — Day 15 food/service source gate (${required.length} required contracts; ${unsafe.length} unsafe patterns blocked).`)
