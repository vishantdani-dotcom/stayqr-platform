param(
  [Parameter(Mandatory = $true)]
  [string]$BackupDirectory,

  [string]$RepoRoot = (Get-Location).Path,

  [string]$EvidenceRoot = "",

  [string]$TargetIdentityPath = "C:\StayQR_D18_DISPOSABLE_RESTORE\DISPOSABLE_TARGET_IDENTITY.txt",

  [switch]$PreflightOnly
)

$ErrorActionPreference = "Stop"

function Assert-Command {
  param([string]$Name)

  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "$Name was not found in PATH."
  }
}

function Invoke-Checked {
  param(
    [string]$Label,
    [scriptblock]$Command
  )

  Write-Host $Label -ForegroundColor Cyan
  & $Command

  if ($LASTEXITCODE -ne 0) {
    throw "$Label failed with exit code $LASTEXITCODE."
  }
}

function Invoke-PsqlText {
  param(
    [string]$DatabaseUrl,
    [string]$Sql
  )

  $result = & psql `
    --dbname $DatabaseUrl `
    -X `
    --tuples-only `
    --no-align `
    --set ON_ERROR_STOP=1 `
    --command $Sql

  if ($LASTEXITCODE -ne 0) {
    throw "psql validation query failed."
  }

  return (($result | Out-String).Trim())
}

function Read-KeyValueEvidence {
  param([string]$Path)

  $map = @{}

  foreach ($line in Get-Content -LiteralPath $Path) {
    if ([string]::IsNullOrWhiteSpace($line)) {
      continue
    }

    if ($line -notmatch '^\s*(?<key>[^=]+)=(?<value>.*)$') {
      throw "Invalid key/value evidence line in $Path"
    }

    $map[$Matches.key.Trim()] = $Matches.value.Trim()
  }

  return $map
}

# Source and restore target URLs must be different.
# Source and restore target database hosts must be different.
# REV2 enforces a stronger rule: no source credential may be loaded and the
# only permitted target is the local disposable Supabase Postgres endpoint.

$sourceDbUrl = ([string]$env:STAYQR_SOURCE_DB_URL).Trim()
$targetDbUrl = ([string]$env:STAYQR_RESTORE_DB_URL).Trim()
$confirmation = ([string]$env:STAYQR_RESTORE_CONFIRM).Trim()
$ambientPgPassword = ([string]$env:PGPASSWORD).Trim()

if ($sourceDbUrl) {
  throw "STAYQR_SOURCE_DB_URL must be absent during the restore drill."
}

if ($ambientPgPassword) {
  throw "PGPASSWORD must be absent during the restore drill."
}

if (-not $targetDbUrl) {
  throw "Set STAYQR_RESTORE_DB_URL to the local disposable target."
}

if ($confirmation -ne "RESTORE_TO_DISPOSABLE_TARGET") {
  throw "Set STAYQR_RESTORE_CONFIRM=RESTORE_TO_DISPOSABLE_TARGET."
}

try {
  $targetUri = [Uri]$targetDbUrl
}
catch {
  throw "Restore target database URL must be a valid PostgreSQL URL."
}

if ($targetUri.Scheme -notin @("postgres", "postgresql")) {
  throw "Restore target must use the postgres or postgresql scheme."
}

if ($targetUri.Host -notin @("127.0.0.1", "localhost")) {
  throw "Unsafe restore target: only localhost is permitted."
}

if ($targetDbUrl -match '(?i)supabase\.com') {
  throw "Unsafe restore target: remote Supabase host detected."
}

if ($targetUri.Port -ne 54322) {
  throw "Unsafe restore target: expected local host port 54322."
}

if ($targetUri.AbsolutePath.TrimStart('/') -ne "postgres") {
  throw "Unsafe restore target: expected database postgres."
}

$targetUser = [Uri]::UnescapeDataString(($targetUri.UserInfo -split ':', 2)[0])

if ($targetUser -ne "postgres") {
  throw "Unsafe restore target: expected local postgres user."
}

Assert-Command "psql"
Assert-Command "docker"

$repo = (Resolve-Path -LiteralPath $RepoRoot).Path
$backup = (Resolve-Path -LiteralPath $BackupDirectory).Path

$requiredNames = @(
  "roles.sql",
  "schema.sql",
  "data.sql",
  "history_schema.sql",
  "history_data.sql",
  "migration_history_status.txt",
  "source-fingerprint.json",
  "SHA256SUMS.txt",
  "manifest.json",
  "STORAGE_OBJECT_BYTES_NOT_INCLUDED.txt"
)

foreach ($requiredName in $requiredNames) {
  $requiredPath = Join-Path $backup $requiredName

  if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
    throw "Backup is missing $requiredName."
  }

  if ((Get-Item -LiteralPath $requiredPath).Length -le 0) {
    throw "Backup file is empty: $requiredName."
  }
}

$manifest = Get-Content `
  -LiteralPath (Join-Path $backup "manifest.json") `
  -Raw | ConvertFrom-Json -ErrorAction Stop

$sourceFingerprint = Get-Content `
  -LiteralPath (Join-Path $backup "source-fingerprint.json") `
  -Raw | ConvertFrom-Json -ErrorAction Stop

if ($manifest.backup_format -ne "supabase-cli-logical-sql") {
  throw "Unsupported backup format."
}

if ($manifest.storage_object_bytes_included -ne $false) {
  throw "Backup storage boundary is not explicit."
}

$historyStatus = Read-KeyValueEvidence `
  -Path (Join-Path $backup "migration_history_status.txt")

$historyMode = [string]$historyStatus["status"]

if ($historyStatus["schema"] -ne "supabase_migrations") {
  throw "Migration-history schema evidence is invalid."
}

if ($historyMode -eq "NOT_PRESENT") {
  if ($historyStatus["artifacts"] -ne "intentional_no_op_sql_markers") {
    throw "Migration-history no-op evidence is invalid."
  }

  if ($manifest.migration_history_schema_present -ne $false) {
    throw "Manifest migration-history state does not match evidence."
  }

  if ($manifest.migration_history_artifact_mode -ne "NOT_PRESENT_NO_OP_MARKERS") {
    throw "Manifest migration-history artifact mode is invalid."
  }

  if ($sourceFingerprint.migration_history_status -ne "NOT_PRESENT") {
    throw "Source fingerprint migration-history state is invalid."
  }

  if (@($sourceFingerprint.migration_versions).Count -ne 0) {
    throw "Source fingerprint unexpectedly contains migration versions."
  }
}
elseif ($historyMode -eq "PRESENT_DUMPED") {
  if ($manifest.migration_history_schema_present -ne $true) {
    throw "Manifest migration-history state does not match evidence."
  }

  if ($manifest.migration_history_artifact_mode -ne "DUMPED") {
    throw "Manifest migration-history artifact mode is invalid."
  }

  if ($sourceFingerprint.migration_history_status -ne "PRESENT") {
    throw "Source fingerprint migration-history state is invalid."
  }
}
else {
  throw "Unsupported migration-history status: $historyMode"
}

$expectedHashedNames = @(
  "roles.sql",
  "schema.sql",
  "data.sql",
  "history_schema.sql",
  "history_data.sql",
  "migration_history_status.txt",
  "source-fingerprint.json",
  "STORAGE_OBJECT_BYTES_NOT_INCLUDED.txt"
)

$hashMap = @{}

foreach ($line in Get-Content -LiteralPath (Join-Path $backup "SHA256SUMS.txt")) {
  if ([string]::IsNullOrWhiteSpace($line)) {
    continue
  }

  if ($line -notmatch '^(?<hash>[A-Fa-f0-9]{64})\s+\*?(?<name>.+)$') {
    throw "Invalid SHA256SUMS line."
  }

  $name = $Matches.name.Trim()
  $hashMap[$name] = $Matches.hash.ToLowerInvariant()
}

foreach ($name in $expectedHashedNames) {
  if (-not $hashMap.ContainsKey($name)) {
    throw "Hash manifest is missing $name."
  }

  $path = Join-Path $backup $name
  $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()

  if ($actual -ne $hashMap[$name]) {
    throw "Backup integrity check failed for $name."
  }
}

$credentialLeaks = Get-ChildItem -LiteralPath $backup -File |
  Where-Object {
    Select-String `
      -LiteralPath $_.FullName `
      -Pattern '(?i)postgres(?:ql)?://[^:\s]+:[^@\s]+@' `
      -Quiet
  }

if ($credentialLeaks) {
  throw "Database credential URI found inside backup evidence."
}

if (-not (Test-Path -LiteralPath $TargetIdentityPath -PathType Leaf)) {
  throw "Disposable target identity evidence was not found."
}

$targetIdentity = Read-KeyValueEvidence -Path $TargetIdentityPath

if (
  $targetIdentity["target_type"] -ne "local_supabase_postgres_docker" -or
  $targetIdentity["connection_host"] -ne "127.0.0.1" -or
  $targetIdentity["host_port"] -ne "54322" -or
  $targetIdentity["container_port"] -ne "5432" -or
  $targetIdentity["database"] -ne "postgres" -or
  $targetIdentity["production_target"] -ne "false" -or
  $targetIdentity["source_database_credentials_loaded"] -ne "false"
) {
  throw "Disposable target identity evidence is invalid."
}

$containerName = "supabase_db_StayQR_D18_DISPOSABLE_RESTORE"
$containerHealth = & docker inspect `
  --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' `
  $containerName

if ($LASTEXITCODE -ne 0) {
  throw "Disposable Postgres container was not found."
}

$containerHealth = (($containerHealth | Out-String).Trim()).ToLowerInvariant()

if ($containerHealth -ne "healthy") {
  throw "Disposable Postgres container is not healthy."
}

$targetStateSql = @"
select
  current_database() || '|' ||
  current_user || '|' ||
  inet_server_port()::text || '|' ||
  current_setting('server_version_num') || '|' ||
  (
    select count(*)::text
    from information_schema.tables
    where table_schema = 'public'
      and table_type = 'BASE TABLE'
  );
"@

$targetState = Invoke-PsqlText `
  -DatabaseUrl $targetDbUrl `
  -Sql $targetStateSql

$targetParts = $targetState.Split('|')

if ($targetParts.Count -ne 5) {
  throw "Unexpected disposable target identity response."
}

if ($targetParts[0] -ne "postgres" -or $targetParts[1] -ne "postgres") {
  throw "Disposable target database identity is invalid."
}

if ([int]$targetParts[2] -ne 5432) {
  throw "Disposable target container port is invalid."
}

if ([int]$targetParts[3] -lt 170000) {
  throw "Disposable target must run PostgreSQL 17 or newer."
}

if ([int]$targetParts[4] -ne 0) {
  throw "Disposable target is not empty; public base tables already exist."
}

Write-Host "PASS - accepted backup evidence and localhost target validated." -ForegroundColor Green
Write-Host "Backup: $backup" -ForegroundColor DarkGray
Write-Host "Target: 127.0.0.1:54322/postgres" -ForegroundColor DarkGray
Write-Host "Public tables before restore: 0" -ForegroundColor DarkGray
Write-Host "Migration history source state: $historyMode" -ForegroundColor DarkGray

if ($PreflightOnly) {
  Write-Host "DAY 18 RESTORE PREFLIGHT PASSED - NO RESTORE EXECUTED" -ForegroundColor Green
  return
}

if (-not $EvidenceRoot) {
  $EvidenceRoot = Join-Path $repo ".stayqr-evidence\day18-restore"
}

$timestamp = [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss")
$evidenceDirectory = Join-Path $EvidenceRoot $timestamp
New-Item -ItemType Directory -Force -Path $evidenceDirectory | Out-Null

Copy-Item `
  -LiteralPath $TargetIdentityPath `
  -Destination (Join-Path $evidenceDirectory "DISPOSABLE_TARGET_IDENTITY.txt") `
  -Force

$rolesPath = Join-Path $backup "roles.sql"
$schemaPath = Join-Path $backup "schema.sql"
$dataPath = Join-Path $backup "data.sql"
$historySchemaPath = Join-Path $backup "history_schema.sql"
$historyDataPath = Join-Path $backup "history_data.sql"

Invoke-Checked "Restoring roles, schema and data to localhost disposable target..." {
  psql `
    --single-transaction `
    --variable ON_ERROR_STOP=1 `
    --command "ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES FROM anon, authenticated" `
    --file $rolesPath `
    --file $schemaPath `
    --command "SET session_replication_role = replica" `
    --file $dataPath `
    --dbname $targetDbUrl
}

if ($historyMode -eq "PRESENT_DUMPED") {
  Invoke-Checked "Restoring migration history..." {
    psql `
      --single-transaction `
      --variable ON_ERROR_STOP=1 `
      --file $historySchemaPath `
      --file $historyDataPath `
      --dbname $targetDbUrl
  }
}
else {
  Write-Host "Source migration history was absent; no migration-history SQL was applied." -ForegroundColor Yellow
}

$targetFingerprintPath = Join-Path $evidenceDirectory "target-fingerprint.json"
$fingerprintScript = Join-Path $repo "scripts\day18-db-fingerprint.ps1"

if (-not (Test-Path -LiteralPath $fingerprintScript -PathType Leaf)) {
  throw "Database fingerprint script was not found."
}

& $fingerprintScript `
  -DatabaseUrl $targetDbUrl `
  -OutputPath $targetFingerprintPath

$targetFingerprint = Get-Content `
  -LiteralPath $targetFingerprintPath `
  -Raw | ConvertFrom-Json -ErrorAction Stop

$sourceCounts = $sourceFingerprint.public_table_row_counts
$targetCounts = $targetFingerprint.public_table_row_counts

$sourceNames = @($sourceCounts.PSObject.Properties.Name | Sort-Object)
$targetNames = @($targetCounts.PSObject.Properties.Name | Sort-Object)

if (@(Compare-Object $sourceNames $targetNames).Count -ne 0) {
  throw "Public table sets do not match after restore."
}

foreach ($tableName in $sourceNames) {
  $sourceCount = [int64]$sourceCounts.$tableName
  $targetCount = [int64]$targetCounts.$tableName

  if ($sourceCount -ne $targetCount) {
    throw "Row-count mismatch for public.$tableName."
  }
}

$migrationHistoryMatches = $false
$migrationComparisonMode = ""

if ($historyMode -eq "NOT_PRESENT") {
  $migrationHistoryMatches = $true
  $migrationComparisonMode = "SOURCE_NOT_PRESENT_TARGET_LOCAL_HISTORY_NOT_APPLICABLE"
}
else {
  $sourceMigrations = @($sourceFingerprint.migration_versions | ForEach-Object { [string]$_ } | Sort-Object)
  $targetMigrations = @($targetFingerprint.migration_versions | ForEach-Object { [string]$_ } | Sort-Object)

  if (@(Compare-Object $sourceMigrations $targetMigrations).Count -ne 0) {
    throw "Migration history does not match after restore."
  }

  $migrationHistoryMatches = $true
  $migrationComparisonMode = "PRESENT_VERSIONS_MATCH"
}

$report = [ordered]@{
  completed_at_utc = [DateTime]::UtcNow.ToString("o")
  source_backup_directory = $backup
  target_type = "local_supabase_postgres_docker"
  target_host = "127.0.0.1"
  target_host_port = 54322
  target_database = "postgres"
  target_public_table_count = $targetNames.Count
  target_public_total_rows = [int64]$targetFingerprint.public_total_rows
  public_table_counts_match = $true
  source_migration_history_status = [string]$sourceFingerprint.migration_history_status
  migration_comparison_mode = $migrationComparisonMode
  migration_history_matches = $migrationHistoryMatches
  storage_object_bytes_restored = $false
  production_target = $false
  accepted = $true
}

$reportPath = Join-Path $evidenceDirectory "restore-report.json"
[System.IO.File]::WriteAllText(
  $reportPath,
  ($report | ConvertTo-Json -Depth 10) + [Environment]::NewLine,
  (New-Object System.Text.UTF8Encoding($false))
)

Write-Host ""
Write-Host "DAY 18 DATABASE RESTORE DRILL PASSED" -ForegroundColor Green
Write-Host "Evidence: $evidenceDirectory" -ForegroundColor Green
Write-Host "Public table counts and migration history match." -ForegroundColor Green
Write-Host "Target was localhost-only and production credentials were absent." -ForegroundColor Green
Write-Host "Storage object bytes were not part of this database drill." -ForegroundColor Yellow
