import assert from 'node:assert/strict';
import fs from 'node:fs';

const source = fs.readFileSync(new URL('../src/lib/idDocumentIntelligence.js', import.meta.url), 'utf8');
const capture = fs.readFileSync(new URL('../src/components/guests/SimpleGuestIdCapture.jsx', import.meta.url), 'utf8');

assert.match(source, /sharedTesseractWorkerPromise/);
assert.match(source, /export function prewarmIdentityOcrRuntime/);
assert.match(source, /getSharedTesseractWorker/);
assert.match(source, /bestScore < 4/);
assert.match(source, /minLongEdge = 1200/);
assert.match(source, /maxLongEdge = 1600/);
assert.doesNotMatch(source, /finally\s*\{\s*try\s*\{\s*await worker\?\.terminate/);
assert.match(capture, /useEffect/);
assert.match(capture, /prewarmIdentityOcrRuntime/);
assert.match(capture, /requestIdleCallback/);

console.log('ID OCR PERFORMANCE REV3: 10/10 PASS');
