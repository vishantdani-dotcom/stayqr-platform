import fs from 'node:fs';

const read = (p) => fs.readFileSync(p, 'utf8');
const main = read('src/main.jsx');
const css = read('src/styles/finalRev57ScannerPolish.css');
const scannerJsx = read('src/components/guests/DocumentScanner.jsx');
const captureJsx = read('src/components/guests/SimpleGuestIdCapture.jsx');

const checks = [
  ['REV57 stylesheet is imported', main.includes("import './styles/finalRev57ScannerPolish.css'")],
  ['REV57 import follows REV55', main.indexOf("finalRev57ScannerPolish.css") > main.indexOf("finalRev55UnifiedTheme.css")],
  ['REV57 marker exists', css.includes('--sq57-scanner-polish: 1')],
  ['Simple ID capture uses REV54 panel', css.includes('.simple-id-capture') && css.includes('background: var(--sq54-panel) !important')],
  ['Scan action uses accepted accent', css.includes('.simple-id-action--scan') && css.includes('rgba(232, 189, 69, 0.055)')],
  ['Remove uses REV55 danger semantics', css.includes('.simple-id-clear') && css.includes('var(--sq55-danger-bg)') && css.includes('var(--sq55-danger-text)')],
  ['Review badge uses warning semantic treatment', css.includes('.simple-id-result-head > span.review') && css.includes('--sq57-warning-bg')],
  ['Review badge is protected from vertical wrapping', css.includes('white-space: nowrap')],
  ['Scanner modal uses REV54 panel system', css.includes('.document-scanner-card') && css.includes('background: var(--sq54-panel) !important')],
  ['Mobile scanner uses full viewport', css.includes('height: 100dvh !important') && css.includes('width: 100vw !important')],
  ['Mobile scanner header is sticky', css.includes('.document-scanner-head') && css.includes('position: sticky')],
  ['Mobile live preview has usable height', css.includes('height: clamp(220px, 39dvh, 340px) !important')],
  ['Mobile scanner actions remain accessible', css.includes('grid-template-columns: repeat(2, minmax(0, 1fr))')],
  ['Existing camera capture flow preserved', scannerJsx.includes('getUserMedia') && scannerJsx.includes('tryHighResolutionStill') && scannerJsx.includes('onCapture?.({')],
  ['Existing native phone camera fallback preserved', scannerJsx.includes('capture="environment"') && scannerJsx.includes('useNativeCameraFile')],
  ['Existing scan/upload OCR flow preserved', captureJsx.includes('analyzeIdentityDocument') && captureJsx.includes('processFile')],
  ['Existing Remove action preserved', captureJsx.includes('className="simple-id-clear"') && captureJsx.includes('Remove')],
  ['Existing Review required semantics preserved', captureJsx.includes('Review required') && captureJsx.includes('className={hasFields && !needsReview ? "auto" : "review"}')],
];

let passed = 0;
for (const [name, ok] of checks) {
  console.log(`${ok ? 'PASS' : 'FAIL'} - ${name}`);
  if (ok) passed += 1;
}
console.log(`REV57_SCANNER_UI_POLISH: ${passed}/${checks.length} PASS`);
if (passed !== checks.length) process.exit(1);
