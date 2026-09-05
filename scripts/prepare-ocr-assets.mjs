import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const publicRoot = path.join(projectRoot, 'public', 'ocr');

function packageRoot(packageName) {
  let current = path.dirname(require.resolve(packageName));
  while (current && current !== path.dirname(current)) {
    const candidate = path.join(current, 'package.json');
    if (fs.existsSync(candidate)) return current;
    current = path.dirname(current);
  }
  throw new Error(`Unable to locate package root for ${packageName}`);
}

function copyFileRequired(source, destination) {
  if (!fs.existsSync(source)) throw new Error(`Required OCR asset missing: ${source}`);
  fs.mkdirSync(path.dirname(destination), { recursive: true });
  fs.copyFileSync(source, destination);
}

const tesseractRoot = packageRoot('tesseract.js');
const coreRoot = packageRoot('tesseract.js-core');
const dataRoot = path.join(projectRoot, 'node_modules', '@tesseract.js-data', 'eng');
const trainedData = path.join(dataRoot, '4.0.0_best_int', 'eng.traineddata.gz');

fs.rmSync(publicRoot, { recursive: true, force: true });
fs.mkdirSync(publicRoot, { recursive: true });

copyFileRequired(
  path.join(tesseractRoot, 'dist', 'worker.min.js'),
  path.join(publicRoot, 'worker.min.js'),
);

const coreNames = fs.readdirSync(coreRoot)
  .filter((name) => /^tesseract-core.*\.(?:js|wasm)$/.test(name));

if (!coreNames.some((name) => name.endsWith('.wasm.js')) || !coreNames.some((name) => name.endsWith('.wasm'))) {
  throw new Error('Tesseract core package does not contain the expected WebAssembly assets.');
}

for (const name of coreNames) {
  copyFileRequired(path.join(coreRoot, name), path.join(publicRoot, 'core', name));
}

copyFileRequired(trainedData, path.join(publicRoot, 'lang', 'eng.traineddata.gz'));

console.log(`StayQR OCR assets prepared: ${publicRoot}`);
console.log(`Core assets: ${coreNames.length}`);
