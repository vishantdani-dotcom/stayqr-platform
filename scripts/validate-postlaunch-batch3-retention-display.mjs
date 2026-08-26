import fs from "node:fs";

const file = "src/pages/guests/GuestDirectory.jsx";
const source = fs.readFileSync(file, "utf8");

const checks = [
  [
    "Timestamp-safe retention formatter exists",
    source.includes('const normalized = String(value).trim();')
  ],
  [
    "Date-only branch keeps local-midnight parsing",
    source.includes('.test(normalized)') &&
      source.includes('new Date(`${normalized}T00:00:00`)')
  ],
  [
    "Timestamp values parse directly",
    source.includes(': new Date(normalized);')
  ],
  [
    "Broken legacy timestamp concatenation removed",
    !source.includes('new Date(`${value}T00:00:00`)')
  ],
  [
    "Guest directory reads retention_until",
    source.includes('retention_until')
  ],
  [
    "Saved KYC UI retains retention presentation",
    /retention/i.test(source)
  ],
];

let passed = 0;
checks.forEach(([name, ok], index) => {
  console.log(`${ok ? "PASS" : "FAIL"} ${String(index + 1).padStart(2, "0")} | ${name}`);
  if (ok) passed += 1;
});

if (passed !== checks.length) {
  console.error(`POSTLAUNCH_BATCH3_RETENTION_DISPLAY_ACCEPTANCE: FAIL (${passed}/${checks.length})`);
  process.exit(1);
}

console.log(`POSTLAUNCH_BATCH3_RETENTION_DISPLAY_ACCEPTANCE: PASS (${passed}/${checks.length})`);
