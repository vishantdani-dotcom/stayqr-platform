import fs from 'node:fs'
import path from 'node:path'
import process from 'node:process'

const root = process.cwd()
const read = (relativePath) =>
  fs.readFileSync(path.join(root, relativePath), 'utf8')

const app = read('src/App.jsx')
const page = read('src/pages/folios/FolioSettlement.jsx')
const api = read('src/lib/folioSettlement.js')
const sidebar = read('src/components/sidebar/Sidebar.jsx')
const navbar = read('src/components/navbar/Navbar.jsx')
const access = read('src/lib/currentStaff.js')
const combined = [app, page, api, sidebar, navbar, access].join('\n')

const required = [
  ['Folio route', /case\s+['"]folios['"]/],
  ['Folio page import', /pages\/folios\/FolioSettlement/],
  ['Folio sidebar navigation', /id:\s*['"]folios['"][\s\S]{0,100}Folio & Settlement/],
  ['Navbar section label', /folios:\s*['"]Folio & Settlement['"]/],
  ['Payments-view route permission', /folios:\s*['"]payments\.view['"]/],
  ['Hotel-scoped folio query', /\.from\(['"]folios['"]\)[\s\S]{0,120}\.eq\(['"]hotel_id['"],\s*hotelId\)/],
  ['Folio item ledger query', /\.from\(['"]folio_items['"]\)/],
  ['Collection ledger query', /\.from\(['"]folio_collections['"]\)/],
  ['Discount ledger query', /\.from\(['"]discount_approvals['"]\)/],
  ['Refund ledger query', /\.from\(['"]refunds['"]\)/],
  ['Credit-note ledger query', /\.from\(['"]credit_notes['"]\)/],
  ['Adjustment ledger query', /\.from\(['"]folio_adjustments['"]\)/],
  ['Gateway ledger query', /\.from\(['"]payment_webhook_events['"]\)/],
  ['Immutable event ledger query', /\.from\(['"]folio_events['"]\)/],
  ['Source-exception ledger query', /\.from\(['"]folio_source_exceptions['"]\)/],
  ['Single collection RPC', /invoke\(['"]post_folio_collection['"]/],
  ['Split collection RPC', /invoke\(['"]post_folio_split_collection['"]/],
  ['Discount request RPC', /invoke\(['"]request_folio_discount['"]/],
  ['Discount review RPC', /invoke\(['"]review_folio_discount['"]/],
  ['Refund request RPC', /invoke\(['"]request_folio_refund['"]/],
  ['Refund process RPC', /invoke\(['"]process_folio_refund['"]/],
  ['Credit-note issue RPC', /invoke\(['"]issue_folio_credit_note['"]/],
  ['Credit-note void RPC', /invoke\(['"]void_folio_credit_note['"]/],
  ['Service pricing RPC', /invoke\(['"]configure_service_request_charge['"]/],
  ['Service charge RPC', /invoke\(['"]post_service_request_charge['"]/],
  ['Stable collection request ID', /singleRequestId/],
  ['Stable split request ID', /splitRequestId/],
  ['Stable discount request ID', /discountRequestId/],
  ['Stable refund request ID', /refundRequestId/],
  ['Stable credit request ID', /creditRequestId/],
  ['Split line JSON contract', /collection_lines:\s*lines\.map/],
  ['Refund collection selection', /target_collection_id:\s*values\.collection_id/],
  ['Non-negative client collection guard', /cannot exceed the current open balance/],
  ['Refundable collection guard', /getRefundableAmount/],
  ['Service pricing defaults visible', /charge_posting_policy/],
  ['Browser webhook read-only copy', /Browser access is read-only/],
  ['Realtime folio subscription', /table:\s*['"]folios['"]/],
  ['Realtime settlement subscription', /table:\s*['"]folio_collections['"]/],
  ['Realtime gateway subscription', /table:\s*['"]payment_webhook_events['"]/],
  ['Authoritative equation UI', /Charges[\s\S]{0,160}Discounts[\s\S]{0,160}Taxes[\s\S]{0,160}Collections[\s\S]{0,160}Refunds[\s\S]{0,160}Credits[\s\S]{0,160}Balance/],
  ['Role-aware management guard', /canManage/],
]

const forbidden = [
  ['service-role credential in browser source', /service[_-]?role/i],
  ['fixed tenant UUID', /[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/i],
  [
    'direct folio write',
    /\.from\(['"]folios['"]\)[\s\S]{0,180}\.(?:insert|update|upsert|delete)\s*\(/,
  ],
  [
    'direct item write',
    /\.from\(['"]folio_items['"]\)[\s\S]{0,180}\.(?:insert|update|upsert|delete)\s*\(/,
  ],
  [
    'direct collection write',
    /\.from\(['"]folio_collections['"]\)[\s\S]{0,180}\.(?:insert|update|upsert|delete)\s*\(/,
  ],
  [
    'direct discount write',
    /\.from\(['"]discount_approvals['"]\)[\s\S]{0,180}\.(?:insert|update|upsert|delete)\s*\(/,
  ],
  [
    'direct refund write',
    /\.from\(['"]refunds['"]\)[\s\S]{0,180}\.(?:insert|update|upsert|delete)\s*\(/,
  ],
  [
    'direct credit-note write',
    /\.from\(['"]credit_notes['"]\)[\s\S]{0,180}\.(?:insert|update|upsert|delete)\s*\(/,
  ],
  [
    'direct adjustment write',
    /\.from\(['"]folio_adjustments['"]\)[\s\S]{0,180}\.(?:insert|update|upsert|delete)\s*\(/,
  ],
  [
    'browser webhook reconciliation',
    /\.rpc\(\s*['"]reconcile_payment_webhook_event['"]/,
  ],
  ['browser gateway secret', /webhook[_-]?secret|client[_-]?secret|signature[_-]?secret/i],
]

const failures = []

for (const [label, pattern] of required) {
  if (!pattern.test(combined)) failures.push(`Missing: ${label}`)
}

for (const [label, pattern] of forbidden) {
  if (pattern.test(combined)) failures.push(`Unsafe source detected: ${label}`)
}

if (failures.length > 0) {
  console.error('FAIL — Day 11 folio and settlement frontend source gate')
  failures.forEach((failure) => console.error(`- ${failure}`))
  process.exit(1)
}

console.log(
  `PASS — Day 11 folio and settlement frontend source gate (${required.length} required contracts; ${forbidden.length} unsafe patterns blocked).`
)
