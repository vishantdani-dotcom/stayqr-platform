import assert from 'node:assert/strict';
import { extractIdentityFromText } from '../src/lib/idDocumentIntelligence.js';

const demoAadhaarOcr = `
Government of India
Pardeep Yadav
DOB : 18/03/1999
MALE
7284 5137 2806
`;
const aadhaar = extractIdentityFromText(demoAadhaarOcr, 'auto', { fileName: 'AADHAR CARD.jpg' });
assert.equal(aadhaar.documentType, 'aadhaar');
assert.equal(aadhaar.extractedFields.full_name, 'Pardeep Yadav');
assert.equal(aadhaar.extractedFields.date_of_birth, '1999-03-18');
assert.equal(aadhaar.extractedFields.gender, 'male');
assert.equal(aadhaar.extractedFields.nationality, 'India');
assert.equal(aadhaar.documentNumberMasked, 'XXXX XXXX 2806');

const noisyAadhaarOcr = `
¥ aT BSN -
Government of India
walu area
Pardeep Yadav
rt fafa / DOB : 18 / 03 / 1999 »
yeu / MALLE
7284   5137   2806
`;
const noisy = extractIdentityFromText(noisyAadhaarOcr, 'auto', { fileName: 'camera-capture.jpg' });
assert.equal(noisy.documentType, 'aadhaar');
assert.equal(noisy.extractedFields.full_name, 'Pardeep Yadav');
assert.equal(noisy.extractedFields.date_of_birth, '1999-03-18');
assert.equal(noisy.extractedFields.gender, 'male');
assert.equal(noisy.documentNumberMasked, 'XXXX XXXX 2806');

const filenameFallback = extractIdentityFromText('Pardeep Yadav\nDOB 18/03/1999\nMALE', 'auto', { fileName: 'aadhaar-front.jpg' });
assert.equal(filenameFallback.documentType, 'aadhaar');
assert.equal(filenameFallback.extractedFields.full_name, 'Pardeep Yadav');

const qrOnly = extractIdentityFromText('', 'auto', { fileName: 'capture.jpg' });
assert.equal(qrOnly.documentType, 'other');
assert.deepEqual(qrOnly.extractedFields, {});

console.log('ID OCR AUTOFILL REV1: 17/17 PASS');
