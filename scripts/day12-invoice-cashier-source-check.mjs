import fs from 'node:fs'
import path from 'node:path'
import process from 'node:process'

const root = process.cwd()
const files = [
  'src/App.jsx',
  'src/components/sidebar/Sidebar.jsx',
  'src/lib/day12Finance.js',
  'src/pages/invoices/Invoices.jsx',
  'src/pages/invoices/Invoices.css',
  'src/pages/invoices/InvoiceVerification.jsx',
  'src/pages/invoices/InvoiceVerification.css',
  'package.json',
]

const source = Object.fromEntries(
  files.map((file) => [
    file,
    fs.readFileSync(path.join(root, file), 'utf8'),
  ])
)

const all = Object.values(source).join('\n')

const required = [
  ['public verification route', source['src/App.jsx'].includes('/invoice/verify/')],
  ['verification component route', source['src/App.jsx'].includes('<InvoiceVerification />')],
  ['invoice audit navigation', source['src/components/sidebar/Sidebar.jsx'].includes('Invoices & Audit')],
  ['day12 security script registered', source['package.json'].includes('security:day12')],
  ['workspace loader', all.includes('loadDay12Workspace')],
  ['invoice snapshot RPC', all.includes("invoke('get_invoice_snapshot'")],
  ['invoice preview RPC', all.includes("invoke('preview_folio_invoice'")],
  ['invoice issuance RPC', all.includes("invoke('issue_folio_invoice'")],
  ['tax rate RPC', all.includes("invoke('upsert_tax_rate'")],
  ['cashier open RPC', all.includes("invoke('open_cashier_shift'")],
  ['cashier close RPC', all.includes("invoke('close_cashier_shift'")],
  ['cashier report RPC', all.includes("invoke('get_cashier_shift_report'")],
  ['day close preview RPC', all.includes("invoke('preview_day_close'")],
  ['night audit close RPC', all.includes("invoke('close_night_audit'")],
  ['accounting CSV RPC', all.includes("invoke('generate_accounting_csv'")],
  ['night audit snapshot RPC', all.includes("invoke('get_night_audit_snapshot'")],
  ['request id generator', all.includes('createDay12RequestId')],
  ['invoices tab', all.includes("{ id: 'invoices', label: 'Invoices' }")],
  ['receipts tab', all.includes("{ id: 'receipts', label: 'Receipts' }")],
  ['cashier tab', all.includes("{ id: 'cashier', label: 'Cashier Shifts' }")],
  ['night audit tab', all.includes("{ id: 'night-audit', label: 'Night Audit' }")],
  ['tax setup tab', all.includes("{ id: 'tax-rates', label: 'GST / Tax Setup' }")],
  ['invoice search', all.includes('Search invoice, guest, phone or room')],
  ['receipt search', all.includes('Search receipt, guest, room, method or reference')],
  ['eligible folio guard', all.includes('eligibleFolios')],
  ['supply modes', all.includes('DAY12_SUPPLY_MODES')],
  ['intra-state support', all.includes('intra_state')],
  ['inter-state support', all.includes('inter_state')],
  ['exempt support', all.includes('exempt')],
  ['invoice preview line table', all.includes('preview.lines')],
  ['immutable issue warning', all.includes('permanently locks')],
  ['invoice PDF', all.includes('downloadElementPdf')],
  ['invoice print', all.includes('printElement')],
  ['WhatsApp delivery', all.includes('shareWhatsApp')],
  ['email delivery', all.includes('shareEmail')],
  ['local invoice QR', all.includes('<LocalQrCode')],
  ['public verification URL', all.includes('/invoice/verify/${invoice.verification_token}')],
  ['snapshot hash display', all.includes('snapshot_hash')],
  ['receipt PDF/print/share', all.includes('ReceiptModal')],
  ['receipt source register', all.includes('One immutable receipt per posted collection')],
  ['opening cash', all.includes('opening_cash')],
  ['declared cash', all.includes('declared_cash')],
  ['expected cash', all.includes('expected_cash')],
  ['cash variance', all.includes('cash_variance')],
  ['method shift entries', all.includes('report.entries')],
  ['blocker preview', all.includes('blocker_count')],
  ['warning preview', all.includes('warning_count')],
  ['explicit acknowledgement', all.includes('acknowledge')],
  ['night audit immutable snapshot', all.includes('Immutable audit snapshot')],
  ['accounting CSV download', all.includes('downloadCsvRecord')],
  ['CSV blob local download', all.includes("type: 'text/csv;charset=utf-8'")],
  ['tax category room', all.includes("{ value: 'room', label: 'Room' }")],
  ['tax category food', all.includes("{ value: 'food', label: 'Food' }")],
  ['tax category service', all.includes("{ value: 'service', label: 'Service' }")],
  ['tax category manual', all.includes("{ value: 'manual', label: 'Manual charge' }")],
  ['tax category other', all.includes("{ value: 'other', label: 'Other' }")],
  ['role-aware management', all.includes('canManage')],
  ['realtime invoice updates', all.includes("table,\n          filter: `hotel_id=eq.${currentHotelId}`")],
  ['public verify RPC', all.includes("supabase.rpc('verify_invoice'")],
  ['verified hash language', all.includes('SHA-256')],
  ['responsive frontend CSS', all.includes('@media (max-width: 760px)')],
]

const unsafe = [
  ['direct invoice insert', /\.from\(['"]invoices['"]\)[\s\S]{0,120}\.insert\(/],
  ['direct invoice update', /\.from\(['"]invoices['"]\)[\s\S]{0,120}\.update\(/],
  ['direct invoice delete', /\.from\(['"]invoices['"]\)[\s\S]{0,120}\.delete\(/],
  ['direct receipt insert', /\.from\(['"]receipts['"]\)[\s\S]{0,120}\.insert\(/],
  ['direct receipt update', /\.from\(['"]receipts['"]\)[\s\S]{0,120}\.update\(/],
  ['direct cashier write', /\.from\(['"]cashier_shifts['"]\)[\s\S]{0,120}\.(insert|update|delete)\(/],
  ['direct night audit write', /\.from\(['"]night_audits['"]\)[\s\S]{0,120}\.(insert|update|delete)\(/],
  ['direct tax rate write', /\.from\(['"]tax_rates['"]\)[\s\S]{0,120}\.(insert|update|delete)\(/],
  ['service role key', /service[_-]?role/i],
  ['remote QR endpoint', /api\.qrserver|chart\.googleapis|quickchart\.io/i],
  ['dangerous HTML injection', /dangerouslySetInnerHTML/],
  ['hard-coded VD hotel UUID', /77d850d0-016d-4155-bc44-a6207d30e7b9/],
  ['hard-coded actor UUID', /a3d5f5a6-6fff-40fe-8fe0-b0b6c436effd/],
]

const missing = required.filter(([, passed]) => !passed)
const unsafeFound = unsafe.filter(([, pattern]) => pattern.test(all))

if (missing.length || unsafeFound.length) {
  for (const [label] of missing) {
    console.error(`FAIL — missing Day 12 contract: ${label}`)
  }

  for (const [label] of unsafeFound) {
    console.error(`FAIL — unsafe Day 12 pattern: ${label}`)
  }

  process.exit(1)
}

console.log(
  `PASS — Day 12 invoice, receipt, cashier and night-audit frontend source gate (${required.length} required contracts; ${unsafe.length} unsafe patterns blocked).`
)
