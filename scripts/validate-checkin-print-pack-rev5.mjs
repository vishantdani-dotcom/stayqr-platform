import fs from 'node:fs';

const checkin = fs.readFileSync('src/pages/checkin/CheckIn.jsx', 'utf8');
const printer = fs.readFileSync('src/lib/checkInPrintPack.js', 'utf8');

const checks = [
  ['registered document id resolved before extraction evidence', checkin, /const savedDocumentId = savedDocument\?\.id \|\| documentId;/],
  ['extraction evidence remains attempted', checkin, /await recordGuestDocumentExtraction\(\{/],
  ['extraction evidence isolated by try catch', checkin, /if \(analysis\) \{\s*try \{[\s\S]*?recordGuestDocumentExtraction[\s\S]*?\} catch \(extractionError\)/],
  ['post-save extraction failure is nonfatal', checkin, /Guest ID saved, but extraction metadata could not be recorded:/],
  ['saved document still returns after extraction failure', checkin, /catch \(extractionError\)[\s\S]*?\}\s*\}\s*return savedDocumentId;/],
  ['genuine primary save failure still warns', checkin, /Primary guest checked in, but the ID image could not be saved\./],
  ['genuine companion save failure still warns', checkin, /was checked in, but the ID image could not be saved\./],
  ['full pack readiness still requires all captured IDs', checkin, /capturedIdCount === savedPrintDocuments\.length/],
  ['consent gate remains', checkin, /Confirm KYC \/ identity-document storage consent before completing check-in\./],
  ['companion mapping remains deterministic', checkin, /item\?\.client_id === companion\.client_id/],
  ['A4 page size remains', printer, /@page\{size:A4;margin:10mm\}/],
  ['screen preview break-before remains', printer, /\.page-break\{break-before:page;page-break-before:always\}/],
  ['print mode neutralizes break-before to prevent blank sheets', printer, /\.page-break\{break-before:auto!important;page-break-before:auto!important\}/],
  ['print mode uses one break-after per physical sheet', printer, /\.page,\.document-page\{[^}]*break-after:page;page-break-after:always/],
  ['last ID page suppresses trailing break', printer, /\.document-page:last-child\{break-after:auto;page-break-after:auto\}/],
  // The working REV2/REV3 implementation intentionally prints the already-open
  // secure preview window via popup.print(), not window.print().
  ['print button remains native popup print driven', printer, /popup\.print\(\)/],
];

let passed = 0;
for (const [name, text, pattern] of checks) {
  if (!pattern.test(text)) {
    console.error(`FAIL ${name}`);
    process.exitCode = 1;
  } else {
    console.log(`PASS ${name}`);
    passed++;
  }
}

if (process.exitCode) process.exit(process.exitCode);
console.log(`REV5 save-classification / print-pagination validation: ${passed}/${checks.length} passed.`);
