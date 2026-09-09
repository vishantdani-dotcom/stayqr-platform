import fs from 'node:fs';
import path from 'node:path';
import { extractIdentityFromText, maskSensitiveNumbers } from '../src/lib/idDocumentIntelligence.js';

const ROOT = process.cwd();
const checks = [];
function read(rel){ return fs.readFileSync(path.join(ROOT, rel), 'utf8'); }
function check(name, condition, detail=''){
  const ok = Boolean(condition);
  checks.push({name, ok, detail});
  console.log(`${ok ? 'PASS' : 'FAIL'} - ${name}${detail ? ` :: ${detail}` : ''}`);
}
function includes(rel, text){ return read(rel).includes(text); }

const checkin = read('src/pages/checkin/CheckIn.jsx');
const checkinCss = read('src/pages/checkin/CheckIn.css');
const guestDir = read('src/pages/guests/GuestDirectory.jsx');
const guestCss = read('src/pages/guests/GuestDirectory.css');
const capture = read('src/components/guests/SimpleGuestIdCapture.jsx');
const captureCss = read('src/components/guests/SimpleGuestIdCapture.css');
const intelligence = read('src/lib/idDocumentIntelligence.js');
const migration = read('supabase/migrations/202609050111_simple_front_desk_id_capture_REV1.sql');

check('Check-in uses the simplified scan/upload component', checkin.includes('SimpleGuestIdCapture'));
check('Check-in keeps atomic walk-in RPC', checkin.includes('check_in_walk_in_guest'));
check('Check-in keeps hotel isolation', checkin.includes('getCurrentHotel()') && checkin.includes('target_hotel_id: currentHotel.id'));
check('Room pricing remains wired to room type base rate', checkin.includes('base_rate') && checkin.includes('handleRoomChange'));
check('Main workflow is intentionally minimal', checkin.includes('Guest basics') && checkin.includes('More check-in options') && checkin.includes('Complete check-in'));
check('Advanced travel details remain available without cluttering the main form', ['arrival_mode','arrival_transport_number','departure_mode','departure_transport_number','early_checkin','late_checkout','special_notes'].every((field)=>checkin.includes(field)));
check('Foreign guest / Form C fields are preserved', ['passport_issued_on','visa_issue_place','visa_issued_on','date_of_arrival_in_india','intended_duration_in_india_days','form_c_status'].every((field)=>checkin.includes(field)));
check('Companion ID and Form C fields are preserved', checkin.includes('companion.id_type') && checkin.includes('companion.id_number') && checkin.includes('checked={companion.form_c_required}') && checkin.includes('updateCompanion(companion.client_id, "form_c_required"'));
check('Quick check-in saves captured ID privately after the atomic stay succeeds', checkin.includes('saveCapturedIdsAfterCheckin') && checkin.indexOf('check_in_walk_in_guest') < checkin.indexOf('saveCapturedIdsAfterCheckin(data)'));
check('Quick capture accepts image and PDF files', checkin.includes('application/pdf') && capture.includes('application/pdf'));
check('Raw OCR text is not persisted from check-in', checkin.includes('raw_ocr_text_stored: false'));
check('Government verification is not claimed from scan/upload', checkin.includes('government_verification_claimed: false'));
check('ID OCR uses the authenticated backend provider path', intelligence.includes('functions.invoke("id-document-ocr"') && intelligence.includes('CLIENT_OCR_TIMEOUT_MS'));
check('Retired browser Tesseract path stays absent', !intelligence.includes('tesseract.js') && !intelligence.includes('createWorker('));
check('Raw Aadhaar-like numbers are masked before extracted fields are parsed', intelligence.includes('maskSensitiveNumbers(raw)'));
check('Capture UI is minimal and uses Scan ID / Upload ID', capture.includes('Scan ID') && capture.includes('Upload ID'));
check('Capture UI contains no active UIDAI/OTP workflow copy', !/UIDAI|OTP authentication|Secure QR Reader/i.test(capture));
check('Check-in UI contains no active UIDAI/OTP workflow copy', !/UIDAI|Secure QR Reader|Aadhaar OTP/i.test(checkin));
check('Guest profile uses simplified guest summary and saved ID documents', guestDir.includes('guest-profile-simple') && guestDir.includes('Saved ID documents'));
check('Legacy heavy guest profile is disabled unless explicitly feature-flagged', guestDir.includes('VITE_ENABLE_LEGACY_GUEST_PROFILE === "true"'));
check('Guest directory uses simple ID wording instead of KYC verification wording', guestDir.includes('ID on file') && guestDir.includes('<th>ID docs</th>'));
check('Guest profile shows operational Saved/Scanned document statuses', guestDir.includes('extracted ? "Scanned" : "Saved"'));
check('Guest profile can save a newly scanned ID without a consent ceremony in the active UI', guestDir.includes('Save ID to guest') && !guestDir.slice(guestDir.indexOf('guest-profile-simple'), guestDir.indexOf('VITE_ENABLE_LEGACY_GUEST_PROFILE')).includes('Record consent'));
check('Simplified check-in visual system includes dark cards and gold accent', /#e8b62f/i.test(checkinCss) && /linear-gradient/i.test(checkinCss));
check('Simplified profile visual system includes dark cards and gold accent', /#e8b62f/i.test(guestCss) && guestCss.includes('simple-profile-card'));
check('Scan/upload card has responsive layout', captureCss.includes('@media(max-width:720px)'));

check('Migration 111 keeps authentication guard', migration.includes('actor_id uuid := auth.uid()') && migration.includes("Authentication is required"));
check('Migration 111 keeps tenant permission guard', migration.includes("private.user_has_any_permission(target_hotel_id,array['guests.manage','checkin.manage']::text[])"));
check('Migration 111 keeps exact hotel/guest/document storage prefix enforcement', migration.includes("expected_prefix := target_hotel_id::text||'/'||requested_guest_id::text||'/'||requested_document_id::text||'/'"));
check('Migration 111 verifies uploaded private storage object exists', migration.includes('from storage.objects'));
check('Migration 111 removes mandatory KYC consent from ordinary capture', !/purpose\s*=\s*'kyc_capture'|kyc_capture consent|required.*consent/i.test(migration));
check('Migration 111 blocks full Aadhaar number persistence', migration.includes('Store only a masked Aadhaar reference, never the full Aadhaar number.'));
check('Migration 111 keeps verification status pending', migration.includes("'pending',actor_id"));
check('Migration 111 exposes separate non-verifying scanned-field apply RPC', migration.includes('apply_scanned_guest_identity_fields'));
check('Migration 111 records government_verification_claimed=false', migration.includes("'government_verification_claimed',false"));
check('Migration 111 grants only authenticated/service role execution', migration.includes('revoke all on function public.register_guest_document(uuid,jsonb) from public, anon') && migration.includes('to authenticated, service_role'));

const aadhaarSample = `Government of India\nAARAV MEHTA\nDOB: 22/03/1992\nMale\nAddress: 42 MG Road, Bengaluru, Karnataka 560038\n1234 5678 9012`;
const aadhaar = extractIdentityFromText(aadhaarSample);
check('Aadhaar text is detected', aadhaar.documentType === 'aadhaar', aadhaar.documentType);
check('Aadhaar number is masked to last four', aadhaar.documentNumberMasked === 'XXXX XXXX 9012', aadhaar.documentNumberMasked || 'null');
check('Aadhaar name is extracted', aadhaar.extractedFields.full_name === 'Aarav Mehta', aadhaar.extractedFields.full_name || 'null');
check('Aadhaar DOB is extracted', aadhaar.extractedFields.date_of_birth === '1992-03-22', aadhaar.extractedFields.date_of_birth || 'null');
check('Aadhaar gender is extracted', aadhaar.extractedFields.gender === 'male', aadhaar.extractedFields.gender || 'null');
check('Aadhaar address is extracted', String(aadhaar.extractedFields.address_line1 || '').includes('42 MG Road'), aadhaar.extractedFields.address_line1 || 'null');
check('Aadhaar postal code is extracted', aadhaar.extractedFields.postal_code === '560038', aadhaar.extractedFields.postal_code || 'null');

const panSample = `INCOME TAX DEPARTMENT\nPERMANENT ACCOUNT NUMBER\nABCDE1234F\nName\nARJUN MEHTA\nDate of Birth\n15/09/1990`;
const pan = extractIdentityFromText(panSample);
check('PAN text is detected', pan.documentType === 'pan', pan.documentType);
check('PAN is masked', pan.documentNumberMasked === 'ABCDE••••F', pan.documentNumberMasked || 'null');
check('PAN name is extracted', pan.extractedFields.full_name === 'Arjun Mehta', pan.extractedFields.full_name || 'null');
check('PAN DOB is extracted', pan.extractedFields.date_of_birth === '1990-09-15', pan.extractedFields.date_of_birth || 'null');

const passportSample = `REPUBLIC OF INDIA\nPASSPORT\nSurname\nMEHTA\nGiven Names\nARJUN\nNationality IND\nDate of Birth 15/09/1990\nPassport No. P1234567`;
const passport = extractIdentityFromText(passportSample);
check('Passport text is detected', passport.documentType === 'passport', passport.documentType);
check('Passport number is masked', passport.documentNumberMasked?.endsWith('4567'), passport.documentNumberMasked || 'null');
check('Passport name is extracted', passport.extractedFields.full_name === 'Arjun Mehta', passport.extractedFields.full_name || 'null');
check('Passport DOB is extracted', passport.extractedFields.date_of_birth === '1990-09-15', passport.extractedFields.date_of_birth || 'null');
check('Passport nationality resolves to India', passport.extractedFields.nationality === 'India', passport.extractedFields.nationality || 'null');

const masked = maskSensitiveNumbers('Aadhaar 1234 5678 9012');
check('Sensitive-text helper masks Aadhaar-like numbers', masked === 'Aadhaar XXXX XXXX 9012', masked);

const passed = checks.filter((item)=>item.ok).length;
console.log(`\nSimple Front Desk REV1: ${passed}/${checks.length} PASS`);
if (passed !== checks.length) process.exit(1);
