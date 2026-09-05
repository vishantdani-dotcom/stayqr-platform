import fs from "node:fs";
import path from "node:path";

const root = process.cwd();
const read = (relative) => fs.readFileSync(path.join(root, relative), "utf8");

const checkIn = read("src/pages/checkin/CheckIn.jsx");
const checkInCss = read("src/pages/checkin/CheckIn.css");
const guestDirectory = read("src/pages/guests/GuestDirectory.jsx");
const migration = read("supabase/migrations/202609050112_multi_occupant_checkin_result_contract_REV1.sql");

const checks = [];
const expect = (name, condition) => checks.push({ name, pass: Boolean(condition) });

expect("Visible multi-occupant section exists", checkIn.includes("Guests staying in this room"));
expect("Primary guest card exists", checkIn.includes("Primary guest"));
expect("Add another guest action exists", checkIn.includes("+ Add another guest"));
expect("Companion OCR uses shared SimpleGuestIdCapture", /<SimpleGuestIdCapture[\s\S]*?compact[\s\S]*?companion\.id_capture/.test(checkIn));
expect("Companion capture state is stored", checkIn.includes("id_capture: null"));
expect("Companion document UUID is stable", checkIn.includes("id_document_id: createUuid()"));
expect("Companion request UUID is stable", checkIn.includes("id_request_id: createUuid()"));
expect("Companion OCR extraction handler exists", checkIn.includes("handleCompanionIdExtracted"));
expect("Companion name can be OCR-filled", checkIn.includes("full_name: fields.full_name || item.full_name"));
expect("Companion DOB can be OCR-filled", checkIn.includes("date_of_birth: fields.date_of_birth || item.date_of_birth"));
expect("Companion gender can be OCR-filled", checkIn.includes("gender: fields.gender || item.gender"));
expect("Companion nationality can be OCR-filled", checkIn.includes("nationality: fields.nationality || item.nationality"));
expect("Companion masked ID can be OCR-filled", checkIn.includes("analysis.documentNumberMasked || item.id_number"));
expect("Companion payload includes client_id", checkIn.includes("client_id: item.client_id"));
expect("Companion payload includes DOB", checkIn.includes("date_of_birth: item.date_of_birth"));
expect("Companion payload includes gender", checkIn.includes("gender: item.gender"));
expect("Companion payload includes nationality", checkIn.includes("nationality: item.nationality"));
expect("Companion payload excludes capture object", !/compactObject\(\{[\s\S]*?id_capture: item\.id_capture/.test(checkIn));
expect("Primary and companion ID persistence share helper", checkIn.includes("saveCapturedIdForGuest"));
expect("Companion results map by client_id", checkIn.includes("item?.client_id === companion.client_id"));
expect("Companion document attaches to returned guest_id", checkIn.includes("guestId: resultCompanion.guest_id"));
expect("Same guest session is used for companion document", checkIn.includes("guestSessionId: checkinResult?.guest_session_id"));
expect("ID metadata never claims government verification", checkIn.includes("government_verification_claimed: false"));
expect("Raw OCR storage remains false", checkIn.includes("raw_ocr_text_stored: false"));
expect("Room occupancy still counts primary adult", checkIn.includes("adults: companionAdults + 1"));
expect("Child/infant occupancy still counted as children", checkIn.includes('["child", "infant"].includes'));
expect("More options no longer owns companion UI", !checkIn.includes("Charge, language, companions, travel"));
expect("Occupant UI supports adult", checkIn.includes('<option value="adult">Adult</option>'));
expect("Occupant UI supports child", checkIn.includes('<option value="child">Child</option>'));
expect("Occupant UI supports infant", checkIn.includes('<option value="infant">Infant</option>'));
expect("Occupant UI includes relationship", checkIn.includes("Spouse, child, parent"));
expect("Occupant UI includes editable extracted details", checkIn.includes("Contact & extracted details"));
expect("Success state reports room-linked guest count", checkIn.includes("linked to the same room stay"));
expect("Occupant CSS exists", checkInCss.includes(".simple-occupants-card"));
expect("Occupant card responsive styles exist", checkInCss.includes(".simple-occupant-fields"));
expect("Compact companion scanner is styled", checkInCss.includes(".simple-occupant-card .simple-id-capture.compact"));
expect("Companion document session linkage is allowed", migration.includes("gc.guest_session_id=gs.id") && migration.includes("gc.guest_id=requested_guest_id"));
expect("Companion document session validation remains hotel scoped", migration.includes("gc.hotel_id=target_hotel_id"));
expect("Migration preserves same RPC name", migration.includes("create or replace function public.check_in_walk_in_guest"));
expect("Migration accumulates companion results", migration.includes("companion_results jsonb := '[]'::jsonb"));
expect("Migration returns client_id", migration.includes("'client_id', nullif(trim(companion_payload ->> 'client_id'), '')"));
expect("Migration returns companion guest_id", migration.includes("'guest_id', companion_row.id"));
expect("Migration returns companions array", migration.includes("'companions', companion_results"));
expect("Migration preserves authenticated grant", migration.includes("to authenticated, service_role"));
expect("Guest profile queries companion memberships", guestDirectory.includes('.from("guest_companions")'));
expect("Guest profile queries memberships by guest_id", /from\("guest_companions"\)[\s\S]*?\.eq\("guest_id", guest\.id\)/.test(guestDirectory));
expect("Guest profile loads companion sessions", guestDirectory.includes("companionSessionIds"));
expect("Guest profile marks companion stay role", guestDirectory.includes('stay_role: "companion"'));
expect("Guest profile marks primary stay role", guestDirectory.includes('stay_role: "primary"'));
expect("Guest profile displays companion stay role", guestDirectory.includes("Companion${session.stay_relationship"));
expect("Guest profile total stays can include companion stays", guestDirectory.includes("const guestSessions = [...sessionsById.values()]"));

const failed = checks.filter((item) => !item.pass);

for (const item of checks) {
  console.log(`${item.pass ? "PASS" : "FAIL"} ${item.name}`);
}

console.log(JSON.stringify({
  checks: checks.length,
  passed: checks.length - failed.length,
  failed: failed.length,
}));

if (failed.length) process.exit(1);
