import fs from 'node:fs';

const read = (p) => fs.readFileSync(p, 'utf8');
const main = read('src/main.jsx');
const css = read('src/styles/finalRev58ScannerRework.css');
const scanner = read('src/components/guests/DocumentScanner.jsx');
const capture = read('src/components/guests/SimpleGuestIdCapture.jsx');

const checks = [
  ['REV58 stylesheet imported', main.includes("import './styles/finalRev58ScannerRework.css'")],
  ['REV58 import follows REV57', main.indexOf('finalRev58ScannerRework.css') > main.indexOf('finalRev57ScannerPolish.css')],
  ['REV58 marker exists', css.includes('--sq58-scanner-rework: 1')],
  ['Scanner uses React portal', scanner.includes('import { createPortal } from "react-dom";') && scanner.includes('createPortal(') && scanner.includes('document.body')],
  ['Scanner preview has dedicated positioning wrapper', scanner.includes('className="document-camera-preview"')],
  ['Portal CSS is body-scoped', css.includes('body > .document-scanner-modal')],
  ['Mobile scanner is true viewport width', css.includes('width: 100dvw !important') && css.includes('height: 100dvh !important')],
  ['Camera frame is constrained to preview wrapper', css.includes('.document-camera-preview') && css.includes('inset: 10% 6% !important')],
  ['Camera status is outside overlay and responsive', css.includes('.document-camera-status') && css.includes('grid-template-columns: auto minmax(0, 1fr)')],
  ['Remove has explicit usable width', css.includes('.simple-id-clear') && css.includes('min-width: 78px !important')],
  ['Narrow-phone Remove gets a full-width row', css.includes('@media (max-width: 480px)') && css.includes('width: 100% !important')],
  ['Review badge remains no-wrap', css.includes('.simple-id-result-head > span') && css.includes('white-space: nowrap !important')],
  ['Existing camera capture flow preserved', scanner.includes('navigator.mediaDevices?.getUserMedia') && scanner.includes('tryHighResolutionStill(track)') && scanner.includes('onCapture?.({')],
  ['Native phone camera fallback preserved', scanner.includes('capture="environment"') && scanner.includes('useNativeCameraFile')],
  ['Torch / zoom preserved', scanner.includes('toggleTorch') && scanner.includes('changeZoom')],
  ['Crop / rotate preserved', scanner.includes('applyCrop') && scanner.includes('rotatePreview')],
  ['Existing OCR pipeline preserved', capture.includes('analyzeIdentityDocument') && capture.includes('processFile')],
  ['Existing destructive clear workflow preserved', capture.includes('function clearDocument()') && capture.includes('className="simple-id-clear"')],
  ['Existing Review required logic preserved', capture.includes('Review required') && capture.includes('needsReview')],
];

let passed = 0;
for (const [name, ok] of checks) {
  console.log(`${ok ? 'PASS' : 'FAIL'} - ${name}`);
  if (ok) passed += 1;
}
console.log(`REV58_SCANNER_UI_REWORK: ${passed}/${checks.length} PASS`);
if (passed !== checks.length) process.exit(1);
