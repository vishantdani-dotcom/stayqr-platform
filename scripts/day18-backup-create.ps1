param(
  [string]$RepoRoot = (Get-Location).Path,
  [string]$OutputRoot = ""
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

function Write-Utf8NoBom {
  param(
    [string]$Path,
    [string]$Content
  )

  [System.IO.File]::WriteAllText(
    $Path,
    $Content,
    (New-Object System.Text.UTF8Encoding($false))
  )
}

$sourceDbUrl = ([string]$env:STAYQR_SOURCE_DB_URL).Trim()

if (-not $sourceDbUrl) {
  throw "Set STAYQR_SOURCE_DB_URL in the current PowerShell session."
}

Assert-Command "supabase"
Assert-Command "docker"
Assert-Command "psql"

Invoke-Checked "Checking Docker..." {
  docker info --format "{{.ServerVersion}}" | Out-Null
}

if (-not $OutputRoot) {
  $OutputRoot = Join-Path `
    $RepoRoot `
    ".stayqr-evidence\day18-backup"
}

$timestamp = [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss")
$backupDirectory = Join-Path $OutputRoot $timestamp
New-Item -ItemType Directory -Force -Path $backupDirectory | Out-Null

$rolesPath = Join-Path $backupDirectory "roles.sql"
$schemaPath = Join-Path $backupDirectory "schema.sql"
$dataPath = Join-Path $backupDirectory "data.sql"
$historySchemaPath = Join-Path $backupDirectory "history_schema.sql"
$historyDataPath = Join-Path $backupDirectory "history_data.sql"
$historyStatusPath = Join-Path $backupDirectory "migration_history_status.txt"
$fingerprintPath = Join-Path $backupDirectory "source-fingerprint.json"

try {
  Invoke-Checked "Dumping roles..." {
    supabase db dump `
      --db-url $sourceDbUrl `
      -f $rolesPath `
      --role-only
  }

  Invoke-Checked "Dumping schema..." {
    supabase db dump `
      --db-url $sourceDbUrl `
      -f $schemaPath
  }

  Invoke-Checked "Dumping data..." {
    supabase db dump `
      --db-url $sourceDbUrl `
      -f $dataPath `
      --use-copy `
      --data-only `
      -x "storage.buckets_vectors" `
      -x "storage.vector_indexes"
  }

  Write-Host "Checking migration-history schema..." -ForegroundColor Cyan
  $historySchemaState = & psql `
    --dbname $sourceDbUrl `
    -X `
    -v ON_ERROR_STOP=1 `
    -tAc "select case when exists (select 1 from pg_namespace where nspname = 'supabase_migrations') then 'PRESENT' else 'ABSENT' end;"

  if ($LASTEXITCODE -ne 0) {
    throw "Checking migration-history schema failed with exit code $LASTEXITCODE."
  }

  $historySchemaState = (($historySchemaState | Out-String).Trim()).ToUpperInvariant()
  $historyArtifactMode = ""

  if ($historySchemaState -eq "PRESENT") {
    Invoke-Checked "Dumping migration-history schema..." {
      supabase db dump `
        --db-url $sourceDbUrl `
        -f $historySchemaPath `
        --schema supabase_migrations
    }

    Invoke-Checked "Dumping migration-history data..." {
      supabase db dump `
        --db-url $sourceDbUrl `
        -f $historyDataPath `
        --use-copy `
        --data-only `
        --schema supabase_migrations
    }

    $historyArtifactMode = "DUMPED"

    Write-Utf8NoBom `
      -Path $historyStatusPath `
      -Content ("status=PRESENT_DUMPED" + [Environment]::NewLine + "schema=supabase_migrations" + [Environment]::NewLine)
  }
  elseif ($historySchemaState -eq "ABSENT") {
    $historyArtifactMode = "NOT_PRESENT_NO_OP_MARKERS"

    $historySchemaMarker = @"
-- STAYQR DAY 18 MIGRATION HISTORY STATUS: NOT_PRESENT
-- Source schema supabase_migrations did not exist at backup time.
-- This is an intentional no-op SQL artifact for a SQL-Editor-managed project.
"@

    $historyDataMarker = @"
-- STAYQR DAY 18 MIGRATION HISTORY STATUS: NOT_PRESENT
-- No supabase_migrations data existed to export at backup time.
-- This is an intentional no-op SQL artifact for a SQL-Editor-managed project.
"@

    Write-Utf8NoBom `
      -Path $historySchemaPath `
      -Content ($historySchemaMarker + [Environment]::NewLine)

    Write-Utf8NoBom `
      -Path $historyDataPath `
      -Content ($historyDataMarker + [Environment]::NewLine)

    Write-Utf8NoBom `
      -Path $historyStatusPath `
      -Content ("status=NOT_PRESENT" + [Environment]::NewLine + "schema=supabase_migrations" + [Environment]::NewLine + "artifacts=intentional_no_op_sql_markers" + [Environment]::NewLine)

    Write-Host "Migration-history schema was absent; intentional no-op evidence markers were created." -ForegroundColor Yellow
  }
  else {
    throw "Unexpected migration-history schema state: $historySchemaState"
  }

  $fingerprintScript = Join-Path `
    $RepoRoot `
    "scripts\day18-db-fingerprint.ps1"

  if (-not (Test-Path $fingerprintScript)) {
    throw "Database fingerprint script was not found: $fingerprintScript"
  }

  & $fingerprintScript `
    -DatabaseUrl $sourceDbUrl `
    -OutputPath $fingerprintPath

  if ($LASTEXITCODE -ne 0) {
    throw "Creating source database fingerprint failed with exit code $LASTEXITCODE."
  }

  $requiredFiles = @(
    $rolesPath,
    $schemaPath,
    $dataPath,
    $historySchemaPath,
    $historyDataPath,
    $historyStatusPath,
    $fingerprintPath
  )

  foreach ($requiredFile in $requiredFiles) {
    if (-not (Test-Path $requiredFile)) {
      throw "Required backup file is missing: $requiredFile"
    }

    if ((Get-Item $requiredFile).Length -eq 0) {
      throw "Required backup file is empty: $requiredFile"
    }
  }

  $storageNotice = @"
Database backup created successfully.

IMPORTANT:
Supabase database backups include Storage metadata but do not include the
actual object bytes stored through the Storage API. Storage object migration
or export must be performed separately before Day 18 can be fully locked.
"@

  Write-Utf8NoBom `
    -Path (Join-Path $backupDirectory "STORAGE_OBJECT_BYTES_NOT_INCLUDED.txt") `
    -Content ($storageNotice + [Environment]::NewLine)

  $hashEntries = foreach (
    $file in Get-ChildItem $backupDirectory -File |
      Sort-Object Name
  ) {
    $hash = (Get-FileHash $file.FullName -Algorithm SHA256).Hash.ToLower()
    "$hash  $($file.Name)"
  }

  Write-Utf8NoBom `
    -Path (Join-Path $backupDirectory "SHA256SUMS.txt") `
    -Content (($hashEntries -join [Environment]::NewLine) + [Environment]::NewLine)

  $manifest = [ordered]@{
    created_at_utc = [DateTime]::UtcNow.ToString("o")
    backup_format = "supabase-cli-logical-sql"
    roles = "roles.sql"
    schema = "schema.sql"
    data = "data.sql"
    migration_history_schema = "history_schema.sql"
    migration_history_data = "history_data.sql"
    migration_history_status = "migration_history_status.txt"
    migration_history_schema_present = ($historySchemaState -eq "PRESENT")
    migration_history_artifact_mode = $historyArtifactMode
    source_fingerprint = "source-fingerprint.json"
    storage_object_bytes_included = $false
  }

  $manifestPath = Join-Path $backupDirectory "manifest.json"
  $manifestJson = $manifest | ConvertTo-Json -Depth 10

  Write-Utf8NoBom `
    -Path $manifestPath `
    -Content ($manifestJson + [Environment]::NewLine)

  Write-Host ""
  Write-Host "DAY 18 LOGICAL BACKUP CREATED" -ForegroundColor Green
  Write-Host "Evidence: $backupDirectory" -ForegroundColor Green
  Write-Host "Migration history: $historyArtifactMode" -ForegroundColor Green
  Write-Host "Database URL was not written to evidence." -ForegroundColor Yellow
  Write-Host "Storage object bytes require a separate controlled export." -ForegroundColor Yellow
}
catch {
  Write-Host ""
  Write-Host "BACKUP FAILED - evidence was not accepted." -ForegroundColor Red
  throw
}
