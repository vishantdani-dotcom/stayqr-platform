import assert from 'node:assert/strict';
import fs from 'node:fs';
import { extractIdentityFromText } from '../src/lib/idDocumentIntelligence.js';

const source = fs.readFileSync(new URL('../src/lib/idDocumentIntelligence.js', import.meta.url), 'utf8');
const capture = fs.readFileSync(new URL('../src/components/guests/SimpleGuestIdCapture.jsx', import.meta.url), 'utf8');

assert.match(source, /workerPath:\s*["']\/ocr\/worker\.min\.js["']/);
assert.match(source, /corePath:\s*["']\/ocr\/core["']/);
assert.match(source, /langPath:\s*["']\/ocr\/lang["']/);
assert.match(source, /workerBlobURL:\s*false/);
assert.match(source, /meaningfulFieldKeys/);
assert.match(source, /ocrRuntimeReady/);
assert.match(capture, /meaningfulKeys/);

const demo = extractIdentityFromText(`
Government of India
Pardeep Yadav
DOB : 18/03/1999
MALE
7284 5137 2806
`, 'auto', { fileName: 'AADHAR CARD.jpg' });

assert.equal(demo.documentType, 'aadhaar');
assert.equal(demo.extractedFields.full_name, 'Pardeep Yadav');
assert.equal(demo.extractedFields.date_of_birth, '1999-03-18');
assert.equal(demo.extractedFields.gender, 'male');
assert.equal(demo.documentNumberMasked, 'XXXX XXXX 2806');

const filenameOnly = extractIdentityFromText('', 'auto', { fileName: 'AADHAR CARD.jpg' });
assert.equal(filenameOnly.documentType, 'aadhaar');
assert.equal(filenameOnly.extractedFields.nationality, 'India');
assert.equal(filenameOnly.documentNumberMasked, null);
assert.equal(Boolean(filenameOnly.extractedFields.full_name), false);

console.log('ID OCR RUNTIME REV2: 14/14 PASS');
