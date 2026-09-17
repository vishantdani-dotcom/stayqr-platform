import fs from 'node:fs'

const files = {
  page: 'src/pages/checkin/CheckIn.jsx',
  css: 'src/pages/checkin/CheckIn.css',
  print: 'src/lib/checkInPrintPack.js',
  migration: 'supabase/migrations/202609180120_checkin_print_pack_audit_REV1.sql',
}

for (const [name, path] of Object.entries(files)) {
  if (!fs.existsSync(path)) {
    console.error(`FAIL ${name}_exists :: ${path}`)
    process.exit(1)
  }
}

const page = fs.readFileSync(files.page, 'utf8')
const css = fs.readFileSync(files.css, 'utf8')
const print = fs.readFileSync(files.print, 'utf8')
const migration = fs.readFileSync(files.migration, 'utf8')

const checks = [
  ['page_imports_print_pack', page.includes('printCheckInPack') && page.includes('printRegistrationCard')],
  ['page_loads_current_staff', page.includes('getCurrentStaff') && page.includes('setCurrentStaff')],
  ['success_print_pack_button', page.includes('Print check-in pack')],
  ['success_registration_button', page.includes('Registration card only')],
  ['browser_save_pdf_copy', page.includes('browser print dialog also supports Save as PDF')],
  ['print_pack_uses_saved_doc_ids', page.includes('savedPrintDocuments') && page.includes('documentId: savedDocumentId')],
  ['print_action_is_audited', print.includes("action: 'print'") && print.includes('auditGuestDocumentAccess')],
  ['audit_before_sensitive_print', print.indexOf('auditGuestDocumentAccess') < print.indexOf('prepareDocumentEntries')],
  ['private_document_never_uploaded_by_print_utility', !/\.upload\s*\(/.test(print) && !/fetch\s*\(/.test(print)],
  ['masked_id_reference_copy', print.includes("guest?.id_number") && print.includes('ID reference')],
  ['captured_id_image_print', print.includes('document-image-wrap') && print.includes('readFileAsDataUrl')],
  ['pdf_has_safe_fallback', print.includes('PDF identity document captured')],
  ['signature_areas_present', print.includes('Primary guest signature') && print.includes('Reception / authorized staff') && print.includes('Hotel stamp')],
  ['printed_by_staff_present', print.includes('Printed by') && print.includes("staff?.full_name")],
  ['a4_print_layout', print.includes('@page{size:A4')],
  ['mobile_success_actions', css.includes('.simple-checkin-success-actions') && css.includes('@media(max-width:760px)')],
  ['migration_adds_print_action', migration.includes("'view', 'download', 'print', 'review', 'delete', 'retention_purge'")],
  ['migration_preserves_kyc_permissions', migration.includes("array['guests.manage','checkin.manage','checkout.manage']")],
  ['migration_has_acceptance_marker', migration.includes('CHECKIN_PRINT_PACK_AUDIT_REV1_PASSED')],
  ['no_notification_code_in_scope', !/from\(['\"]notifications['\"]\)|insert\s+into\s+public\.notifications|create\s+or\s+replace\s+function[^;]*notification/i.test(print + '\n' + migration)],
]

let failed = 0
for (const [name, passed] of checks) {
  console.log(`${passed ? 'PASS' : 'FAIL'} ${name}`)
  if (!passed) failed += 1
}

console.log(`\nCheck-in Print Pack REV1: ${checks.length - failed}/${checks.length} passed.`)
if (failed) process.exit(1)
