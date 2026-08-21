import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';

const root = process.cwd();
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');
const exists = (file) => fs.existsSync(path.join(root, file));
const checks = [];
function check(name, condition, evidence = '') { checks.push({ name, passed: Boolean(condition), evidence }); }
function has(file, needle) { return read(file).includes(needle); }

const migration = 'supabase/migrations/202608210092_postlaunch_batch3_guest_identity_crm.sql';
const guestDirectory = 'src/pages/guests/GuestDirectory.jsx';
const guestComms = 'src/pages/guests/GuestCommunications.jsx';
const scanner = 'src/components/guests/DocumentScanner.jsx';
const identity = 'src/components/guests/GuestIdentityCompliance.jsx';
const guestDirectoryCss = 'src/pages/guests/GuestDirectory.css';
const identityCss = 'src/components/guests/GuestIdentityCompliance.css';
const compliance = 'src/lib/guestCompliance.js';
const aadhaarFn = 'supabase/functions/verify-aadhaar-offline/index.ts';
const waSend = 'supabase/functions/whatsapp-send/index.ts';
const waWebhook = 'supabase/functions/whatsapp-status-webhook/index.ts';
const purgeFn = 'supabase/functions/purge-guest-retention/index.ts';

for (const file of [migration, guestDirectory, guestDirectoryCss, guestComms, scanner, identity, identityCss, compliance, aadhaarFn, waSend, waWebhook, purgeFn]) {
  check(`File exists: ${file}`, exists(file), file);
}

check('Camera capture uses rear-facing camera', has(scanner, 'facingMode: { ideal: "environment" }'));
check('Camera scanner has edge alignment frame', has(scanner, 'document-scanner-frame'));
check('Scanner has manual crop controls', has(scanner, 'Crop document edges') && has(scanner, 'applyCrop'));
check('Scanner has rotate control', has(scanner, 'Rotate 90°'));
check('Scanner compresses camera capture to JPEG', has(scanner, 'JPEG_QUALITY') && has(scanner, 'canvas.toBlob'));
check('Scanner assesses blur/glare/lighting', ['possible_blur','possible_glare','too_dark','too_bright'].every((v) => has(scanner, v)));
check('Scanner explicitly excludes biometric matching', has(scanner, 'does not perform face recognition or biometric matching'));
check('Scanner keyboard escape closes modal', has(scanner, 'event.key === "Escape"'));
check('Scanner attaches MediaStream after video mount', has(scanner, 'streamVersion') && has(scanner, 'video.srcObject = stream') && has(scanner, '[open, preview, streamVersion]') && !has(scanner, 'window.setTimeout(async () =>'));
check('Scanner high-resolution still capture present', has(scanner, 'window.ImageCapture') && has(scanner, 'takePhoto()') && has(scanner, 'high_res_still'));
check('Scanner preserves higher capture resolution', has(scanner, 'MAX_CAPTURE_DIMENSION = 3200') && has(scanner, 'JPEG_QUALITY = 0.94'));
check('Scanner native phone-camera fallback present', has(scanner, 'capture="environment"') && has(scanner, 'native_camera_file'));
check('Scanner advanced torch and zoom controls present', has(scanner, 'torchSupported') && has(scanner, 'zoomRange') && has(scanner, 'applyConstraints'));

check('Guest KYC uses private guest-documents bucket', has(guestDirectory, 'const KYC_BUCKET = "guest-documents"'));
check('Guest KYC supports front/back grouping', has(guestDirectory, 'documentSide') && has(guestDirectory, 'kycDocumentGroupId'));
check('Guest KYC captures retention metadata', has(guestDirectory, 'retention_until') && has(guestDirectory, 'retention_basis'));
check('Guest KYC stores masked number only in Batch 3 payload', has(guestDirectory, 'document_number_masked') && has(guestDirectory, 'raw_document_number_stored: false'));
check('Private KYC signed URL is short-lived', has(guestDirectory, 'createSignedUrl(documentRecord.storage_path, 60)'));
check('KYC view is audited before signed URL', has(guestDirectory, 'auditGuestDocumentAccess') && has(guestDirectory, 'action: "view"'));

check('KYC workspace has clear 3-step workflow', ['KYC & IDENTITY WORKSPACE','Consent','Capture','Review'].every((value) => has(guestDirectory, value)));
check('KYC capture form is grouped into document and retention sections', has(guestDirectory, 'Document details') && has(guestDirectory, 'Dates & retention'));
check('KYC capture supports clean camera-or-upload choice', has(guestDirectory, 'Capture or upload') && has(guestDirectory, 'Choose a private file'));
check('KYC technical request details are collapsible', has(guestDirectory, 'guest-kyc-technical') && has(guestDirectory, '<summary>Technical request details</summary>'));
check('Saved KYC metadata is collapsible', has(guestDirectory, 'guest-document-details') && has(guestDirectory, 'View document metadata'));
check('Identity consent is the first workflow step', has(identity, 'guest-identity-step-head') && has(identity, 'Identity consent'));
check('Aadhaar methods are progressively disclosed', has(identity, 'guest-identity-methods') && has(identity, 'Open only when Aadhaar verification is required.'));
check('Verification evidence history is collapsible', has(identity, 'guest-verification-evidence') && has(identity, 'View history'));
check('KYC desktop layout uses grouped responsive grid', has(guestDirectoryCss, '.guest-kyc-form-layout') && has(guestDirectoryCss, 'grid-template-columns: repeat(2, minmax(0, 1fr))'));
check('KYC mobile layout collapses to one column', has(guestDirectoryCss, '@media (max-width: 680px)') && has(guestDirectoryCss, '.guest-kyc-capture-layout') && has(guestDirectoryCss, 'grid-template-columns: 1fr'));
check('Identity compliance mobile layout is responsive', has(identityCss, '@media (max-width: 680px)') && has(identityCss, '.guest-consent-card-clean'));

check('Consent ledger exists', has(migration, 'create table if not exists public.guest_consents'));
check('KYC access audit exists', has(migration, 'create table if not exists public.guest_document_access_audit'));
check('Identity verification evidence exists', has(migration, 'create table if not exists public.guest_identity_verifications'));
check('Export audit exists', has(migration, 'create table if not exists public.guest_export_audit'));
check('Retention legal hold exists', has(migration, 'legal_hold boolean not null default false'));
check('Retention queue RPC exists', has(migration, 'get_guest_documents_due_for_retention'));
check('Retention purge Edge Function exists', exists(purgeFn));

check('Paperless Offline XML verification UI exists', has(identity, 'UIDAI Paperless Offline e-KYC verification'));
check('Secure QR official-reader evidence UI exists', has(identity, 'UIDAI Secure QR verification') && has(identity, 'official UIDAI Secure QR Reader'));
check('Secure QR evidence RPC exists', has(migration, 'record_uidai_secure_qr_reader_verification'));
check('Aadhaar photo is not described as authentication', has(identity, 'A photo/PDF of Aadhaar is never treated as Aadhaar authentication'));
check('UIDAI XML function verifies digital signature', has(aadhaarFn, 'verifyXmlSignature') && has(aadhaarFn, 'SignedXml'));
check('UIDAI XML function rejects DTD/entities', has(aadhaarFn, '/<!DOCTYPE|<!ENTITY/i'));
check('UIDAI raw XML is not persisted', has(aadhaarFn, 'raw_xml_stored: false'));
check('UIDAI Aadhaar number is not persisted', has(aadhaarFn, 'aadhaar_number_stored: false'));

check('Guest 360 RPC exists', has(migration, 'create or replace function public.get_guest_360_directory'));
for (const keyword of ['dateFrom','dateTo','stay','nationality','room','repeat','kyc','whatsapp']) {
  check(`Guest 360 filter present: ${keyword}`, has(guestDirectory, keyword));
}
check('Controlled export RPC exists', has(migration, 'create or replace function public.export_guest_directory_360'));
check('Export requires explicit reason', has(migration, 'An export reason of at least 3 characters is required.'));
check('Selected-column export UI exists', has(guestDirectory, 'EXPORT_COLUMN_OPTIONS') && has(guestDirectory, 'exportColumns'));
check('Privileged KYC summary export exists', has(guestDirectory, 'exportIncludeKyc') && has(migration, 'KYC-summary export requires guests.manage.'));
check('CSV injection guard exists', has(guestDirectory, "/^[=+\\-@]/") && has(guestDirectory, "trimStart()"));

check('WhatsApp consent ledger purposes exist', has(migration, "'whatsapp_transactional'") && has(migration, "'whatsapp_marketing'"));
check('WhatsApp suppression ledger exists', has(migration, 'guest_communication_suppressions'));
check('WhatsApp campaign/recipient/event evidence exists', ['guest_communication_campaigns','guest_communication_recipients','guest_communication_events'].every((v) => has(migration, v)));
check('Manual one-recipient WhatsApp fallback exists', has(guestComms, 'Manual / click-to-chat') && has(guestComms, 'prepareManualWhatsAppContact'));
check('Consent confirmation required in UI', has(guestComms, 'explicitly consented'));
check('Hotel-owned provider profile exists', has(migration, 'hotel_whatsapp_provider_profiles'));
check('Provider-approved template metadata exists', has(migration, 'provider_status') && has(migration, "'approved'"));
check('Meta template selection and preview exists', has(guestComms, 'Approved template preview') && has(guestComms, 'provider-approved template'));
check('Meta mode stays unavailable without readiness', has(guestComms, 'disabled={!metaReady}'));
check('WhatsApp automation is feature-flagged', has(waSend, 'WHATSAPP_AUTOMATION_ENABLED'));
check('WhatsApp sender uses hotel provider profile', has(waSend, "from('hotel_whatsapp_provider_profiles')"));
check('WhatsApp sender rechecks approved template', has(waSend, ".eq('provider_status', 'approved')"));
check('WhatsApp sender rechecks consent and suppression', has(waSend, "requiredPurpose") && has(waSend, "guest_communication_suppressions"));
check('WhatsApp retry attempt evidence exists', has(waSend, 'attempt_count') && has(migration, 'attempt_count integer not null default 0'));
check('WhatsApp webhook verifies Meta HMAC', has(waWebhook, 'x-hub-signature-256') && has(waWebhook, 'HMAC'));
check('WhatsApp delivery states persist', ['sent','delivered','read','failed'].every((v) => has(waWebhook, `'${v}'`)));

const failed = checks.filter((item) => !item.passed);
checks.forEach((item, index) => console.log(`${item.passed ? 'PASS' : 'FAIL'} ${String(index + 1).padStart(2, '0')} | ${item.name}${item.evidence ? ` | ${item.evidence}` : ''}`));
console.log(`POSTLAUNCH_BATCH3_SOURCE_ACCEPTANCE: ${failed.length ? 'FAIL' : 'PASS'} (${checks.length - failed.length}/${checks.length})`);
if (failed.length) process.exit(1);
