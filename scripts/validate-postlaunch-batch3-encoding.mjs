import fs from "node:fs";

const uiPath = "src/components/guests/GuestIdentityCompliance.jsx";
const fnPath = "supabase/functions/verify-aadhaar-offline/index.ts";

const ui = fs.readFileSync(uiPath, "utf8");
const fn = fs.readFileSync(fnPath, "utf8");

const checks = [
  ["Secure QR evidence normalizes masked reference", ui.includes("displayMaskedReference(item.reference_id_masked)")],
  ["Display mask is ASCII-only", ui.includes("`****${digits.slice(-4)}`")],
  ["Offline XML future reference mask is ASCII-only", fn.includes("`****${digits.slice(-4)}`")],
  ["Legacy bullet mask removed from Aadhaar Edge Function", !fn.includes("`••••${digits.slice(-4)}`")],
];

let failed = 0;
checks.forEach(([label, pass], index) => {
  console.log(`${pass ? "PASS" : "FAIL"} ${String(index + 1).padStart(2, "0")} | ${label}`);
  if (!pass) failed += 1;
});

if (failed) {
  console.error(`POSTLAUNCH_BATCH3_ENCODING_ACCEPTANCE: FAIL (${checks.length - failed}/${checks.length})`);
  process.exit(1);
}

console.log(`POSTLAUNCH_BATCH3_ENCODING_ACCEPTANCE: PASS (${checks.length}/${checks.length})`);
