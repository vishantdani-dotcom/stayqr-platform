import fs from "node:fs";
import path from "node:path";

const root = process.cwd();
const script = path.join(root, "scripts", "day18-storage-object-recovery.cjs");
const doc = path.join(root, "docs", "operations", "DAY18_STORAGE_OBJECT_RECOVERY.md");

const required = [
  [fs.existsSync(script), "recovery runner exists"],
  [fs.existsSync(doc), "storage recovery runbook exists"],
];

const text = fs.existsSync(script) ? fs.readFileSync(script, "utf8") : "";

for (const bucket of ["hotel-assets", "guest-guide-media", "guest-documents"]) {
  required.push([text.includes(`"${bucket}"`), `required bucket contract: ${bucket}`]);
}

required.push([text.includes("ggtcvgteefcrlwvxkfwf.supabase.co"), "dedicated staging target guard"]);
required.push([text.includes("source.storage.listBuckets"), "source list-buckets read"]);

/*
  The source download is deliberately routed through the reusable downloadBytes()
  helper. Prove both halves of that call chain instead of requiring a direct
  `.download()` call on the source expression.
*/
const hasDownloadHelper = text.includes("async function downloadBytes(bucketApi, objectPath)") &&
                          text.includes("bucketApi.download(objectPath");
const sourceUsesDownloadHelper = text.includes("downloadBytes(source.storage.from(bucketName), fullPath)");
required.push([hasDownloadHelper && sourceUsesDownloadHelper, "source object download read via audited helper"]);

required.push([text.includes("target.storage.createBucket"), "isolated target bucket creation"]);
required.push([text.includes("target.storage.from(tempBucket).upload"), "isolated target upload"]);
required.push([text.includes("sha256Buffer"), "SHA-256 verification"]);
required.push([text.includes("sourceWriteOperationsExecuted: false"), "source write assertion in report"]);

required.push([!text.includes("source.storage.createBucket"), "blocked source createBucket"]);
required.push([!text.includes("source.storage.deleteBucket"), "blocked source deleteBucket"]);
required.push([!text.includes("source.storage.emptyBucket"), "blocked source emptyBucket"]);
required.push([!text.includes("source.storage.from(bucketName).upload"), "blocked source upload"]);
required.push([!text.includes("source.storage.from(bucketName).remove"), "blocked source remove"]);

let failed = 0;
for (const [ok, name] of required) {
  console.log(`${ok ? "PASS" : "FAIL"} - ${name}`);
  if (!ok) failed++;
}
if (failed) {
  console.error(`DAY 18 STORAGE RECOVERY SOURCE GATE FAILED (${failed})`);
  process.exit(1);
}
console.log(`DAY 18 STORAGE RECOVERY SOURCE GATE PASSED (${required.length}/${required.length})`);
