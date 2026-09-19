import fs from 'node:fs';

const printer = fs.readFileSync('src/lib/checkInPrintPack.js', 'utf8');

const checks = [
  ['A4 sheet declaration preserved', /@page\{size:A4;margin:10mm\}/],
  ['screen preview remains real A4', /\.page,\.document-page\{width:210mm;min-height:297mm/],
  ['print sheet height has safe headroom', /@media print\{[\s\S]*?\.page,\.document-page\{width:auto;min-height:245mm;height:auto/],
  ['old exact printable-height trap removed', /@media print\{[\s\S]*?min-height:277mm/ , true],
  ['print break-before is neutralized', /\.page-break\{break-before:auto!important;page-break-before:auto!important\}/],
  ['one explicit break-after remains', /\.page,\.document-page\{[^}]*break-after:page;page-break-after:always/],
  ['last ID sheet suppresses trailing break', /\.document-page:last-child\{break-after:auto;page-break-after:auto\}/],
  ['print ID image height leaves pagination headroom', /@media print\{[\s\S]*?\.document-image-wrap\{height:185mm;padding:6mm 2mm\}/],
  ['native popup print remains unchanged', /popup\.print\(\)/],
];

let passed = 0;
for (const [name, pattern, shouldBeAbsent = false] of checks) {
  const matched = pattern.test(printer);
  const ok = shouldBeAbsent ? !matched : matched;
  if (!ok) {
    console.error(`FAIL ${name}`);
    process.exitCode = 1;
  } else {
    console.log(`PASS ${name}`);
    passed++;
  }
}

if (process.exitCode) process.exit(process.exitCode);
console.log(`REV6 final print-pagination validation: ${passed}/${checks.length} passed.`);
