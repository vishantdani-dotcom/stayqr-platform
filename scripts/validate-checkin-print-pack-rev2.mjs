import fs from 'node:fs'

const printPath = 'src/lib/checkInPrintPack.js'
const rev1Validator = 'scripts/validate-checkin-print-pack-rev1.mjs'
const migration = 'supabase/migrations/202609180120_checkin_print_pack_audit_REV1.sql'

for (const file of [printPath, rev1Validator, migration]) {
  if (!fs.existsSync(file)) {
    console.error(`FAIL required_file_exists :: ${file}`)
    process.exit(1)
  }
}

const source = fs.readFileSync(printPath, 'utf8')
const checks = [
  ['rev1_sensitive_print_audit_preserved', source.includes("action: 'print'") && source.includes('auditGuestDocumentAccess')],
  ['rev1_masked_reference_preserved', source.includes("guest?.id_number") && source.includes('ID reference')],
  ['true_a4_screen_sheet', source.includes('.page,.document-page{width:210mm;min-height:297mm')],
  ['a4_print_page_rule', source.includes('@page{size:A4;margin:10mm}')],
  ['print_media_content_area', source.includes('min-height:277mm') && source.includes('@media print')],
  ['screen_preview_centered', source.includes('margin:0 auto 24px')],
  ['screen_preview_shadow', source.includes('box-shadow:0 22px 60px')],
  ['mobile_preview_safe', source.includes('@media screen and (max-width:860px)')],
  ['button_has_stable_id', source.includes('id="stayqr-print-button"')],
  ['button_bound_programmatically', source.includes("addEventListener('click'") && source.includes('popup.print()')],
  ['no_inline_onclick', !source.includes('onclick="window.print()"')],
  ['no_inline_script_tag', !source.includes('<script>') && !source.includes('</script>')],
  ['no_auto_print_timeout', !source.includes('setTimeout(()=>window.print()')],
  ['write_preview_helper', source.includes('function writePrintPreview(')],
  ['pack_uses_write_preview', source.includes('writePrintPreview(popup, html)')],
  ['image_copy_preserved', source.includes('document-image-wrap') && source.includes('readFileAsDataUrl')],
  ['pdf_fallback_preserved', source.includes('PDF identity document captured')],
  ['signature_areas_preserved', source.includes('Primary guest signature') && source.includes('Reception / authorized staff') && source.includes('Hotel stamp')],
  ['printed_by_preserved', source.includes('Printed by') && source.includes("staff?.full_name")],
  ['no_upload_or_fetch_added', !/\.upload\s*\(/.test(source) && !/fetch\s*\(/.test(source)],
]

let failed = 0
for (const [name, pass] of checks) {
  console.log(`${pass ? 'PASS' : 'FAIL'} ${name}`)
  if (!pass) failed += 1
}
console.log(`\nCheck-in Print Pack REV2 A4/print fix: ${checks.length - failed}/${checks.length} passed.`)
if (failed) process.exit(1)
