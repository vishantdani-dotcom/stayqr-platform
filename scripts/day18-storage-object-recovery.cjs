/* StayQR Day 18 storage object backup / isolated restore drill.
   Source project is strictly read-only in this script.
   Target is the dedicated StayQR Staging project only.
*/
const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");
const { createClient } = require("@supabase/supabase-js");

const REQUIRED_BUCKETS = ["hotel-assets", "guest-guide-media", "guest-documents"];
const EXPECTED_STAGING_HOST = "ggtcvgteefcrlwvxkfwf.supabase.co";

function fail(message) {
  console.error(`FAIL - ${message}`);
  process.exitCode = 1;
  throw new Error(message);
}

function normalizeProjectUrl(value, label) {
  let u;
  try {
    u = new URL(String(value || "").trim());
  } catch {
    fail(`${label} is not a valid URL.`);
  }
  if (u.protocol !== "https:") fail(`${label} must use HTTPS.`);
  if (!u.hostname.endsWith(".supabase.co")) fail(`${label} must be a Supabase project URL.`);
  u.pathname = "";
  u.search = "";
  u.hash = "";
  return u.toString().replace(/\/$/, "");
}

function validateElevatedKey(key, label) {
  const k = String(key || "").trim();
  if (!k) fail(`${label} is missing.`);
  if (k.startsWith("sb_publishable_")) fail(`${label} is a publishable key; an elevated secret/service-role key is required.`);
  if (k.startsWith("sb_secret_")) return;
  const parts = k.split(".");
  if (parts.length === 3) {
    try {
      const payload = JSON.parse(Buffer.from(parts[1].replace(/-/g, "+").replace(/_/g, "/"), "base64").toString("utf8"));
      if (payload.role !== "service_role") fail(`${label} JWT is not role=service_role.`);
      return;
    } catch {
      fail(`${label} is not a valid secret/service-role key.`);
    }
  }
  fail(`${label} is not a recognized Supabase secret/service-role key.`);
}

function sha256Buffer(buffer) {
  return crypto.createHash("sha256").update(buffer).digest("hex");
}
function sha256Text(text) {
  return crypto.createHash("sha256").update(text, "utf8").digest("hex");
}
function canonicalObjectSetHash(objects) {
  const rows = objects
    .map((o) => `${o.bucket}\u0000${o.objectPath}\u0000${o.size}\u0000${o.sha256}`)
    .sort();
  return sha256Text(rows.join("\n"));
}
function ensureDir(p) {
  fs.mkdirSync(p, { recursive: true });
}
function writeJson(p, value) {
  fs.writeFileSync(p, JSON.stringify(value, null, 2) + "\n", "utf8");
}
function safeBucketSlug(name) {
  return String(name).toLowerCase().replace(/[^a-z0-9-]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 38) || "bucket";
}
function localBlobName(bucket, objectPath) {
  const keyHash = sha256Text(`${bucket}\u0000${objectPath}`);
  return `${keyHash}.blob`;
}
function toArrayBuffer(buffer) {
  return buffer.buffer.slice(buffer.byteOffset, buffer.byteOffset + buffer.byteLength);
}
function getMime(item, blob) {
  const m = item?.metadata || {};
  return m.mimetype || m.contentType || m.content_type || blob?.type || "application/octet-stream";
}
function getCacheControl(item) {
  const m = item?.metadata || {};
  const raw = m.cacheControl || m.cache_control || "3600";
  const digits = String(raw).match(/\d+/);
  return digits ? digits[0] : "3600";
}

async function listAllEntries(bucketApi, prefix = "") {
  const output = [];
  let offset = 0;
  const limit = 100;
  while (true) {
    const { data, error } = await bucketApi.list(prefix, {
      limit,
      offset,
      sortBy: { column: "name", order: "asc" },
    });
    if (error) throw error;
    const rows = data || [];
    for (const item of rows) {
      const fullPath = prefix ? `${prefix}/${item.name}` : item.name;
      const isFolder = item.id == null && item.metadata == null;
      if (isFolder) {
        output.push(...await listAllEntries(bucketApi, fullPath));
      } else {
        output.push({ fullPath, item });
      }
    }
    if (rows.length < limit) break;
    offset += limit;
  }
  return output;
}

async function downloadBytes(bucketApi, objectPath) {
  const { data, error } = await bucketApi.download(objectPath, {}, { cache: "no-store" });
  if (error) throw error;
  if (!data || typeof data.arrayBuffer !== "function") {
    throw new Error(`Download did not return a Blob for ${objectPath}`);
  }
  return { blob: data, buffer: Buffer.from(await data.arrayBuffer()) };
}

async function removeInChunks(bucketApi, paths) {
  for (let i = 0; i < paths.length; i += 100) {
    const { error } = await bucketApi.remove(paths.slice(i, i + 100));
    if (error) throw error;
  }
}

async function main() {
  const repoRoot = path.resolve(process.env.STAYQR_REPO_ROOT || "C:\\StayQR_D18_WORK");
  const sourceUrl = normalizeProjectUrl(process.env.STAYQR_STORAGE_SOURCE_URL, "Source project URL");
  const targetUrl = normalizeProjectUrl(process.env.STAYQR_STORAGE_TARGET_URL, "Target project URL");
  const sourceKey = process.env.STAYQR_STORAGE_SOURCE_SECRET;
  const targetKey = process.env.STAYQR_STORAGE_TARGET_SECRET;

  validateElevatedKey(sourceKey, "Source key");
  validateElevatedKey(targetKey, "Target key");

  const sourceHost = new URL(sourceUrl).hostname;
  const targetHost = new URL(targetUrl).hostname;
  if (sourceHost === targetHost) fail("Source and target projects must be different.");
  if (sourceHost === EXPECTED_STAGING_HOST) fail("Source project is the staging project. The recovery drill requires the production source.");
  if (targetHost !== EXPECTED_STAGING_HOST) fail(`Target must be the dedicated StayQR Staging project (${EXPECTED_STAGING_HOST}).`);

  const stamp = new Date().toISOString().replace(/[-:]/g, "").replace(/\..+/, "Z").replace("T", "_");
  const evidenceRoot = path.join(repoRoot, ".stayqr-evidence", "day18-storage-recovery", stamp);
  const privateBackupRoot = path.join(evidenceRoot, "PRIVATE_SOURCE_BACKUP_DO_NOT_SHARE");
  const blobRoot = path.join(privateBackupRoot, "objects");
  ensureDir(blobRoot);

  fs.writeFileSync(
    path.join(privateBackupRoot, "SENSITIVE_BACKUP_DO_NOT_SHARE.txt"),
    "This directory can contain private hotel and guest/KYC object bytes. Do not commit, upload, email, or share it. Keep it only on a trusted encrypted device.\n",
    "utf8"
  );

  const source = createClient(sourceUrl, sourceKey, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });
  const target = createClient(targetUrl, targetKey, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });

  console.log("=== DAY 18 STORAGE RECOVERY PREFLIGHT ===");
  console.log(`Source host: ${sourceHost} (READ ONLY)`);
  console.log(`Target host: ${targetHost} (ISOLATED STAGING RESTORE ONLY)`);

  const { data: sourceBucketsRaw, error: sourceBucketError } = await source.storage.listBuckets({ limit: 100, offset: 0 });
  if (sourceBucketError) fail(`Source bucket listing failed: ${sourceBucketError.message}`);
  const sourceBuckets = sourceBucketsRaw || [];
  const sourceBucketNames = new Set(sourceBuckets.map((b) => b.id || b.name));

  const missingRequired = REQUIRED_BUCKETS.filter((b) => !sourceBucketNames.has(b));
  if (missingRequired.length) {
    fail(`Required production Storage bucket(s) missing: ${missingRequired.join(", ")}`);
  }
  console.log(`PASS - required production buckets exist: ${REQUIRED_BUCKETS.join(", ")}`);
  console.log(`PASS - discovered ${sourceBuckets.length} production bucket(s)`);

  const manifest = {
    version: 1,
    createdAt: new Date().toISOString(),
    sourceHost,
    targetHost,
    requiredBuckets: REQUIRED_BUCKETS,
    buckets: [],
    objects: [],
  };

  let sourceTotalBytes = 0;
  for (const bucket of sourceBuckets) {
    const bucketName = bucket.id || bucket.name;
    if (!bucketName) continue;
    console.log(`BACKUP - listing bucket ${bucketName}`);
    const entries = await listAllEntries(source.storage.from(bucketName), "");
    manifest.buckets.push({
      id: bucketName,
      public: Boolean(bucket.public),
      fileSizeLimit: bucket.file_size_limit ?? bucket.fileSizeLimit ?? null,
      allowedMimeTypes: bucket.allowed_mime_types ?? bucket.allowedMimeTypes ?? null,
      objectCount: entries.length,
    });
    for (const { fullPath, item } of entries) {
      const { blob, buffer } = await downloadBytes(source.storage.from(bucketName), fullPath);
      const digest = sha256Buffer(buffer);
      const bucketDir = path.join(blobRoot, sha256Text(bucketName).slice(0, 16));
      ensureDir(bucketDir);
      const localName = localBlobName(bucketName, fullPath);
      const localRel = path.relative(privateBackupRoot, path.join(bucketDir, localName)).replace(/\\/g, "/");
      fs.writeFileSync(path.join(privateBackupRoot, localRel), buffer);
      const written = fs.readFileSync(path.join(privateBackupRoot, localRel));
      if (sha256Buffer(written) !== digest) fail(`Local backup checksum failed for ${bucketName}/${fullPath}`);
      manifest.objects.push({
        bucket: bucketName,
        objectPath: fullPath,
        size: buffer.length,
        sha256: digest,
        contentType: getMime(item, blob),
        cacheControl: getCacheControl(item),
        localFile: localRel,
      });
      sourceTotalBytes += buffer.length;
    }
    console.log(`PASS - ${bucketName}: ${entries.length} object(s) backed up`);
  }

  if (manifest.objects.length === 0) {
    fail("Production Storage has zero object bytes. A real object-byte recovery drill cannot be accepted.");
  }

  const sourceSetHash = canonicalObjectSetHash(manifest.objects);
  manifest.sourceObjectCount = manifest.objects.length;
  manifest.sourceTotalBytes = sourceTotalBytes;
  manifest.sourceObjectSetSha256 = sourceSetHash;

  const manifestPath = path.join(privateBackupRoot, "source-object-manifest.json");
  writeJson(manifestPath, manifest);
  fs.writeFileSync(
    path.join(privateBackupRoot, "source-object-manifest.sha256.txt"),
    sha256Buffer(fs.readFileSync(manifestPath)) + "\n",
    "ascii"
  );

  console.log(`PASS - source backup: ${manifest.objects.length} object(s), ${sourceTotalBytes} byte(s)`);
  console.log(`PASS - source object-set SHA-256: ${sourceSetHash}`);

  console.log("\n=== ISOLATED STAGING RESTORE ===");
  const suffix = crypto.randomBytes(4).toString("hex");
  const restoreMap = new Map();
  const createdBuckets = [];

  try {
    for (const bucket of manifest.buckets) {
      const tempName = `d18r-${suffix}-${safeBucketSlug(bucket.id)}`.slice(0, 80);
      const { error } = await target.storage.createBucket(tempName, { public: false });
      if (error) fail(`Could not create isolated staging bucket ${tempName}: ${error.message}`);
      createdBuckets.push(tempName);
      restoreMap.set(bucket.id, tempName);
      console.log(`PASS - created private isolated restore bucket ${tempName}`);
    }

    for (const obj of manifest.objects) {
      const localPath = path.join(privateBackupRoot, obj.localFile);
      const bytes = fs.readFileSync(localPath);
      if (sha256Buffer(bytes) !== obj.sha256) fail(`Backup changed before restore: ${obj.bucket}/${obj.objectPath}`);
      const tempBucket = restoreMap.get(obj.bucket);
      const { error } = await target.storage.from(tempBucket).upload(
        obj.objectPath,
        toArrayBuffer(bytes),
        {
          contentType: obj.contentType || "application/octet-stream",
          cacheControl: obj.cacheControl || "3600",
          upsert: false,
        }
      );
      if (error) fail(`Restore upload failed for ${obj.bucket}/${obj.objectPath}: ${error.message}`);
    }
    console.log(`PASS - uploaded ${manifest.objects.length} backed-up object(s) into isolated staging buckets`);

    console.log("\n=== RESTORE CHECKSUM / COUNT VERIFICATION ===");
    const restoredObjects = [];
    let restoredTotalBytes = 0;
    for (const sourceBucket of manifest.buckets) {
      const tempBucket = restoreMap.get(sourceBucket.id);
      const entries = await listAllEntries(target.storage.from(tempBucket), "");
      for (const { fullPath } of entries) {
        const { buffer } = await downloadBytes(target.storage.from(tempBucket), fullPath);
        restoredObjects.push({
          bucket: sourceBucket.id,
          objectPath: fullPath,
          size: buffer.length,
          sha256: sha256Buffer(buffer),
        });
        restoredTotalBytes += buffer.length;
      }
    }

    const restoredSetHash = canonicalObjectSetHash(restoredObjects);
    if (restoredObjects.length !== manifest.objects.length) fail(`Restored object count mismatch. Source=${manifest.objects.length} restored=${restoredObjects.length}`);
    if (restoredTotalBytes !== sourceTotalBytes) fail(`Restored byte count mismatch. Source=${sourceTotalBytes} restored=${restoredTotalBytes}`);
    if (restoredSetHash !== sourceSetHash) fail(`Restored checksum-set mismatch. Source=${sourceSetHash} restored=${restoredSetHash}`);

    const sourceIndex = new Map(manifest.objects.map((o) => [`${o.bucket}\u0000${o.objectPath}`, o]));
    for (const restored of restoredObjects) {
      const src = sourceIndex.get(`${restored.bucket}\u0000${restored.objectPath}`);
      if (!src || src.size !== restored.size || src.sha256 !== restored.sha256) {
        fail(`Per-object verification failed for ${restored.bucket}/${restored.objectPath}`);
      }
    }

    const report = {
      version: 1,
      result: "PASS",
      createdAt: new Date().toISOString(),
      sourceHost,
      targetHost,
      sourceMode: "READ_ONLY",
      targetMode: "TEMPORARY_PRIVATE_ISOLATED_BUCKETS",
      requiredBucketsVerified: REQUIRED_BUCKETS,
      sourceBucketCount: manifest.buckets.length,
      sourceObjectCount: manifest.objects.length,
      restoredObjectCount: restoredObjects.length,
      sourceTotalBytes,
      restoredTotalBytes,
      sourceObjectSetSha256: sourceSetHash,
      restoredObjectSetSha256: restoredSetHash,
      perObjectChecksumsMatched: true,
      rawObjectBytesStoredOnlyInIgnoredLocalEvidence: true,
      sourceWriteOperationsExecuted: false,
      cleanupPending: true,
    };

    console.log(`PASS - object count: ${restoredObjects.length}/${manifest.objects.length}`);
    console.log(`PASS - total bytes: ${restoredTotalBytes}/${sourceTotalBytes}`);
    console.log(`PASS - object-set SHA-256: ${restoredSetHash}`);
    console.log("PASS - every restored object matched source path, size and SHA-256");

    for (const sourceBucket of manifest.buckets) {
      const tempBucket = restoreMap.get(sourceBucket.id);
      const objectPaths = manifest.objects.filter((o) => o.bucket === sourceBucket.id).map((o) => o.objectPath);
      if (objectPaths.length) await removeInChunks(target.storage.from(tempBucket), objectPaths);
      const { error: deleteError } = await target.storage.deleteBucket(tempBucket);
      if (deleteError) fail(`Could not delete isolated restore bucket ${tempBucket}: ${deleteError.message}`);
    }
    report.cleanupPending = false;
    report.isolatedStagingCleanup = "PASS";

    const reportPath = path.join(evidenceRoot, "storage-recovery-report.json");
    writeJson(reportPath, report);
    fs.writeFileSync(
      path.join(evidenceRoot, "storage-recovery-report.sha256.txt"),
      sha256Buffer(fs.readFileSync(reportPath)) + "\n",
      "ascii"
    );

    console.log("\nDAY 18 STORAGE OBJECT BACKUP / ISOLATED RESTORE / CHECKSUM VERIFICATION PASSED");
    console.log(`Evidence: ${evidenceRoot}`);
    console.log(`Objects: ${manifest.objects.length}`);
    console.log(`Bytes: ${sourceTotalBytes}`);
    console.log(`Object-set SHA-256: ${sourceSetHash}`);
    console.log("Source writes executed: NO");
    console.log("Temporary staging restore buckets cleaned: YES");
  } catch (err) {
    for (const tempBucket of createdBuckets) {
      try {
        const entries = await listAllEntries(target.storage.from(tempBucket), "");
        if (entries.length) await removeInChunks(target.storage.from(tempBucket), entries.map((x) => x.fullPath));
        await target.storage.deleteBucket(tempBucket);
      } catch {}
    }
    throw err;
  }
}

main().catch((err) => {
  console.error("\nDAY 18 STORAGE RECOVERY STOPPED");
  console.error(err?.message || String(err));
  console.error("No source/production write operation exists in this recovery runner.");
  process.exit(1);
});
