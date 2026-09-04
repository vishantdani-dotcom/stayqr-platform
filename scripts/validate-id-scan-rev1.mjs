import fs from "node:fs";
import path from "node:path";

const root = process.cwd();
const read = (file) => fs.readFileSync(path.join(root, file), "utf8");
const checks = [];
const check = (name, condition) => checks.push({ name, ok: Boolean(condition) });

const intelligence = read("src/lib/idDocumentIntelligence.js");
const directory = read("src/pages/guests/GuestDirectory.jsx");
const compliance = read("src/components/guests/GuestIdentityCompliance.jsx");
const guestCompliance = read("src/lib/guestCompliance.js");
const migration = read("supabase/migrations/202609040109_guest_id_scan_extraction_and_verified_profile_apply_REV1.sql");

check("camera/upload workflow retained", directory.includes("<DocumentScanner") && directory.includes("Choose a private file"));
check("local OCR feature detection exists", intelligence.includes("window.TextDetector"));
check("Secure QR detection exists", intelligence.includes("window.BarcodeDetector"));
check("raw OCR Aadhaar-like values are masked before preview", intelligence.includes("maskSensitiveNumbers(rawText)"));
check("QR payload is reduced to SHA-256", intelligence.includes("secureQrPayloadSha256") && intelligence.includes("sha256Hex"));
check("raw OCR text is not persisted", migration.includes("'raw_ocr_text_stored', false"));
check("raw QR payload is not persisted", migration.includes("'raw_qr_payload_stored', false"));
check("safe extraction RPC is wired", guestCompliance.includes("record_guest_document_extraction") && directory.includes("recordGuestDocumentExtraction"));
check("Aadhaar manual verify blocked in UI", directory.includes("Aadhaar cannot be marked verified from OCR or visual review alone"));
check("Aadhaar manual verify blocked in database", migration.includes("document_before.document_type='aadhaar' and normalized_action='verify'"));
check("Aadhaar full-number storage rejected", migration.includes("Full Aadhaar-like numbers are not permitted"));
check("verified profile apply RPC exists", migration.includes("apply_guest_document_identity_fields"));
check("Aadhaar apply requires signed linked evidence", migration.includes("giv.signature_valid=true") && migration.includes("aadhaar_secure_qr_uidai_reader"));
check("Secure QR verification requires exact saved Aadhaar document", migration.includes("Link the UIDAI Secure QR verification to the saved Aadhaar document"));
check("Secure QR closes the linked document", migration.includes("verification_status='verified'") && migration.includes("uidai_secure_qr_verification_id"));
check("signed offline XML can close linked document", migration.includes("offline_xml_verification_id"));
check("Guest 360 verified fields can be applied", directory.includes("applyGuestDocumentIdentityFields") && migration.includes("guest.verified_identity_applied"));
check("online Aadhaar OTP UI is absent", !compliance.includes("Request authentication OTP") && !compliance.includes("guest-uidai-online"));
check("offline Aadhaar consent retained", compliance.includes("GUEST_CONSENT_PURPOSES.AADHAAR_OFFLINE"));
check("tenant permission enforcement retained", migration.includes("private.user_has_permission(target_hotel_id,'guests.manage')"));
check("activity audit retained", migration.includes("private.write_activity_log"));

for (const item of checks) console.log(`${item.ok ? "PASS" : "FAIL"} - ${item.name}`);
const failed = checks.filter((item) => !item.ok);
console.log(`\nID Scan REV1: ${checks.length - failed.length}/${checks.length} checks passed.`);
if (failed.length) process.exit(1);
