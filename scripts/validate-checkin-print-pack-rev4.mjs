import fs from 'node:fs';
import crypto from 'node:crypto';

const read = (path) => fs.readFileSync(path, 'utf8');
const sha256 = (path) => crypto.createHash('sha256').update(fs.readFileSync(path)).digest('hex');
const assert = (condition, message) => {
  if (!condition) {
    console.error(`FAIL ${message}`);
    process.exitCode = 1;
  } else {
    console.log(`PASS ${message}`);
  }
};

const checkIn = read('src/pages/checkin/CheckIn.jsx');
const checkInCss = read('src/pages/checkin/CheckIn.css');
const guests = read('src/pages/guests/Guests.jsx');
const guestsCss = read('src/pages/guests/Guests.css');
const migration121 = read('supabase/migrations/202609180121_checkin_companion_mapping_consent_guard_REV1.sql');

assert(checkIn.includes('GUEST_CONSENT_PURPOSES'), '01_checkin_imports_consent_purpose');
assert(checkIn.includes('setGuestConsent'), '02_checkin_records_consent');
assert(checkIn.includes('kycCaptureConsentConfirmed'), '03_checkin_has_consent_state');
assert(checkIn.includes('Confirm KYC / identity-document storage consent before completing check-in.'), '04_checkin_blocks_without_consent');
assert(checkIn.includes('KYC / identity-document storage consent'), '05_checkin_renders_consent_ui');
assert(checkIn.includes('confirmed_before_checkin: true'), '06_consent_evidence_records_precheckin_confirmation');
assert(checkIn.includes('checkin_guest_session_id'), '07_consent_evidence_links_stay_reference');
assert(checkIn.includes('recordKycCaptureConsents'), '08_consent_recorded_before_document_registration');
assert(checkInCss.includes('.simple-kyc-consent-card'), '09_consent_ui_theme_present');
assert(checkInCss.includes('@media(max-width:640px)'), '10_consent_ui_mobile_rule_present');

assert(migration121.includes('KYC capture consent is required before storing an identity document.'), '11_migration_preserves_backend_consent_guard');
assert(migration121.includes('guest_companions'), '12_migration_allows_companion_stay_document_linkage');
assert(migration121.includes("'client_id'"), '13_migration_returns_deterministic_companion_mapping');
assert(migration121.includes('CHECKIN_REV4_ID_CONSENT_COMPANION_MAPPING_PASSED'), '14_migration_has_acceptance_gate');

assert(guests.includes('getActiveStayTiming'), '15_guests_has_overdue_timing_helper');
assert(guests.includes('Overdue by'), '16_guests_has_overdue_duration');
assert(guests.includes('guest-session-status ${isOverdue ? "overdue"'), '17_guests_renders_overdue_status');
assert(guests.includes('.eq("status", "active")'), '18_active_stay_source_remains_authoritative_status');
assert(guests.includes('Final Bill & Checkout'), '19_manual_checkout_workflow_preserved');
assert(guestsCss.includes('.guest-session-status.overdue'), '20_overdue_theme_present');
assert(!guests.includes('autoCheckout') && !guests.includes('automatic checkout'), '21_no_automatic_checkout_added');

assert(
  sha256('supabase/migrations/202609180120_checkin_print_pack_audit_REV1.sql') === 'caab70395dd1208a63776b0ea56e02e47f5138f61b629e31ae25b771b20b3765',
  '22_migration120_unchanged'
);
assert(
  sha256('src/lib/checkInPrintPack.js') === 'e9f288c5bd8c300c0109bfba6f8ea85ee0f6749f8478b48cd41b5ce94be31248',
  '23_working_a4_print_engine_unchanged'
);
assert(
  sha256('scripts/validate-checkin-print-pack-rev3.mjs') === '4047780364b110155bfcd41c51dd6e62f491952e973f1aa26c5238beeab2b14a',
  '24_rev3_validator_unchanged'
);

if (process.exitCode) {
  console.error('\nCHECK-IN PRINT PACK REV4 VALIDATION FAILED');
  process.exit(process.exitCode);
}
console.log('\nCHECK-IN PRINT PACK REV4 VALIDATION: 24/24 PASSED');
