import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const read = (rel) => fs.readFileSync(path.join(root, rel), 'utf8');
const fail = (message) => { throw new Error(message); };
const pass = (message) => console.log(`PASS: ${message}`);
const count = (haystack, needle) => haystack.split(needle).length - 1;

const cssPath = 'src/styles/finalRev55UnifiedTheme.css';
const mainPath = 'src/main.jsx';
const rev54Path = 'src/styles/finalRev54ThemeParity.css';
const superAdminPath = 'src/pages/superadmin/SuperAdmin.css';
const servicePath = 'src/pages/services/ServiceRequests.jsx';

for (const rel of [cssPath, mainPath, rev54Path, superAdminPath, servicePath]) {
  if (!fs.existsSync(path.join(root, rel))) fail(`Missing required file: ${rel}`);
}

const css = read(cssPath);
const main = read(mainPath);
const rev54 = read(rev54Path);
const superAdmin = read(superAdminPath);
const service = read(servicePath);

const newImport = "import './styles/finalRev55UnifiedTheme.css'";
const priorImport = "import './styles/finalRev54ThemeParity.css'";
if (count(main, newImport) !== 1) fail('REV55 stylesheet import must appear exactly once.');
if (count(main, priorImport) !== 1) fail('REV54 stylesheet import must remain exactly once.');
if (main.indexOf(newImport) < main.indexOf(priorImport)) fail('REV55 stylesheet must load after REV54.');
pass('REV55 stylesheet loads once and after REV54');

for (const marker of [
  '--sq55-unified-theme',
  '--sq55-danger-bg',
  '#root .app-shell button.danger',
  '#root .commercial-shell',
  '#root .commercial-tabs',
  '#root .commercial-card',
  '#root .plan-card',
  '#root .commercial-dialog',
  'var(--sq54-panel)',
  'var(--sq54-accent)',
  'rgba(255, 92, 92, 0.10)',
]) {
  if (!css.includes(marker)) fail(`REV55 CSS marker missing: ${marker}`);
}
pass('unified Super Admin and destructive-action theme markers present');

if (!rev54.includes('--sq54-theme-parity')) fail('REV54 theme parity marker was lost.');
if (!superAdmin.includes('.commercial-shell')) fail('Super Admin baseline stylesheet no longer has .commercial-shell.');
if (!service.includes('className="danger"') || !service.includes('>Cancel</button>')) fail('Service Requests destructive Cancel contract changed unexpectedly.');
pass('REV54, Super Admin, and Service Requests accepted source contracts preserved');

const allowedProperties = new Set([
  'color', 'background', 'background-color', 'background-image', 'border-color', 'border-top-color',
  'box-shadow', 'outline-color', 'accent-color', 'caret-color',
  'text-decoration-color', 'fill', 'stroke',
]);
const withoutComments = css.replace(/\/\*[\s\S]*?\*\//g, '');
const declaration = /(?:^|[;{])\s*([a-zA-Z-][a-zA-Z0-9-]*)\s*:/gm;
let match;
const forbidden = new Set();
while ((match = declaration.exec(withoutComments))) {
  const property = match[1].toLowerCase();
  if (property.startsWith('--')) continue;
  if (!allowedProperties.has(property)) forbidden.add(property);
}
if (forbidden.size) fail(`REV55 is colour/theme only; forbidden CSS properties found: ${[...forbidden].sort().join(', ')}`);
pass('REV55 CSS contains colour/theme properties only');

for (const forbiddenText of ['@media', '@keyframes', 'font-size:', 'padding:', 'margin:', 'display:', 'width:', 'height:', 'position:', 'transform:', 'transition:', 'border-radius:']) {
  if (css.includes(forbiddenText)) fail(`REV55 stylesheet contains forbidden layout/typography token: ${forbiddenText}`);
}
pass('no layout, typography, responsive, animation, or geometry overrides added');

console.log('REV55 UNIFIED THEME CONTRACT: PASS');
