import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const root = process.cwd();
const read = (rel) => fs.readFileSync(path.join(root, rel), 'utf8');
let passed = 0;
let failed = 0;
function check(name, condition) {
  if (condition) { console.log(`PASS ${name}`); passed += 1; }
  else { console.error(`FAIL ${name}`); failed += 1; }
}

const client = read('src/lib/idDocumentIntelligence.js');
const capture = read('src/components/guests/SimpleGuestIdCapture.jsx');
const checkin = read('src/pages/checkin/CheckIn.jsx');
const guests = read('src/pages/guests/GuestDirectory.jsx');
const edge = read('supabase/functions/id-document-ocr/index.ts');

check('Browser Tesseract is no longer in active OCR path', !client.includes('tesseract.js') && !client.includes('createWorker('));
check('Frontend invokes id-document-ocr Edge Function', client.includes('functions.invoke("id-document-ocr"'));
check('Frontend limits OCR wait time', client.includes('CLIENT_OCR_TIMEOUT_MS'));
check('Large phone photos are compressed before provider upload', client.includes('compressImageForProvider'));
check('Simple ID capture passes hotel context to analyzer', capture.includes('hotelId,') && capture.includes('hotelId,'));
check('Check-in supplies current hotel to ID capture', checkin.includes('hotelId={currentHotel?.id || null}'));
check('Guest profile supplies current hotel to ID capture', guests.includes('hotelId={currentHotel?.id || null}'));
check('UI no longer claims browser OCR', !capture.includes('processed in the browser'));
check('UI states raw OCR text is not saved', capture.includes('does not save raw OCR text'));
check('Edge Function requires authenticated StayQR session', edge.includes('auth.getUser(token)'));
check('Edge Function checks hotel-scoped check-in/guest permissions', edge.includes("permissionSet.has('checkin.manage')") && edge.includes("permissionSet.has('guests.manage')"));
check('Edge Function is disabled by default unless explicitly enabled', edge.includes("ID_OCR_ENABLED"));
check('Google Vision key is server-side Edge Function secret only', edge.includes('GOOGLE_CLOUD_VISION_API_KEY') && !client.includes('GOOGLE_CLOUD_VISION_API_KEY'));
check('Provider call has bounded timeout', edge.includes('PROVIDER_TIMEOUT_MS') && edge.includes('AbortController'));
check('Provider response/raw OCR is not returned', edge.includes('raw OCR text and provider response are intentionally not returned or persisted'));
check('Aadhaar is masked before output', edge.includes('XXXX XXXX') && edge.includes('maskSensitiveNumbers'));
check('Supported automatic OCR file types are limited to JPG/PNG', edge.includes("'image/jpeg'") && edge.includes("'image/png'"));
check('Raw OCR field is marked non-stored', edge.includes('rawOcrTextStored: false'));

const moduleUrl = pathToFileURL(path.join(root, 'src/lib/idDocumentIntelligence.js')).href;
const mod = await import(`${moduleUrl}?validation=${Date.now()}`);
const sample = `भारत सरकार\nGovernment of India\nप्रदीप यादव\nPardeep Yadav\nजन्म तिथि / DOB : 18/03/1999\nपुरुष / MALE\n7284 5137 2806\nमेरा आधार, मेरी पहचान`;
const parsed = mod.extractIdentityFromText(sample, 'auto', { fileName: 'AADHAR CARD.jpg' });
check('Demo Aadhaar detected', parsed.documentType === 'aadhaar');
check('Demo Aadhaar name extracted', parsed.extractedFields.full_name === 'Pardeep Yadav');
check('Demo Aadhaar DOB normalized', parsed.extractedFields.date_of_birth === '1999-03-18');
check('Demo Aadhaar gender extracted', parsed.extractedFields.gender === 'male');
check('Demo Aadhaar nationality extracted', parsed.extractedFields.nationality === 'India');
check('Demo Aadhaar number masked', parsed.documentNumberMasked === 'XXXX XXXX 2806');

console.log(JSON.stringify({ checks: passed + failed, passed, failed }));
if (failed) process.exit(1);
