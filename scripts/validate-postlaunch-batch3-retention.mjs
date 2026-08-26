import fs from "node:fs";

const file = "supabase/migrations/202608260093_postlaunch_batch3_retention_deadline_enforcement.sql";
const sql = fs.readFileSync(file, "utf8");

const checks = [
  ["Historical null deadlines backfilled", sql.includes("created_at + interval '365 days'")],
  ["Historical blank bases normalized", sql.includes("retention_basis = 'hotel_policy'")],
  ["Future retention trigger exists", sql.includes("trg_guest_documents_retention_batch3")],
  ["Future null deadlines are defaulted", sql.includes("new.retention_until := effective_created_at + interval '365 days'")],
  ["Invalid chronological deadlines rejected", sql.includes("retention deadline must be later than its creation time")],
  ["Retention deadline made mandatory", sql.includes("alter column retention_until set not null")],
  ["Retention basis made mandatory", sql.includes("alter column retention_basis set not null")],
  ["RLS acceptance preserved", sql.includes("guest_documents RLS is not enabled")],
];

let passed = 0;
for (let i = 0; i < checks.length; i += 1) {
  const [name, ok] = checks[i];
  console.log(`${ok ? "PASS" : "FAIL"} ${String(i + 1).padStart(2, "0")} | ${name}`);
  if (ok) passed += 1;
}

if (passed !== checks.length) {
  console.error(`POSTLAUNCH_BATCH3_RETENTION_SOURCE_ACCEPTANCE: FAIL (${passed}/${checks.length})`);
  process.exit(1);
}
console.log(`POSTLAUNCH_BATCH3_RETENTION_SOURCE_ACCEPTANCE: PASS (${passed}/${checks.length})`);
