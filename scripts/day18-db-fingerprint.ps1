param(
  [Parameter(Mandatory = $true)]
  [string]$DatabaseUrl,

  [Parameter(Mandatory = $true)]
  [string]$OutputPath
)

$ErrorActionPreference = "Stop"

function Invoke-PsqlText {
  param([string]$Sql)

  $result = & psql `
    --dbname $DatabaseUrl `
    --tuples-only `
    --no-align `
    --set ON_ERROR_STOP=1 `
    --command $Sql

  if ($LASTEXITCODE -ne 0) {
    throw "psql fingerprint query failed."
  }

  return ($result | Out-String).Trim()
}

if (-not (Get-Command psql -ErrorAction SilentlyContinue)) {
  throw "psql was not found in PATH."
}

$tableQuery = @"
select table_name
from information_schema.tables
where table_schema = 'public'
  and table_type = 'BASE TABLE'
order by table_name;
"@

$tableText = Invoke-PsqlText -Sql $tableQuery
$tableNames = @(
  $tableText -split "`r?`n" |
    Where-Object { $_ -and $_.Trim() }
)

if ($tableNames.Count -eq 0) {
  throw "No public base tables were found."
}

$counts = [ordered]@{}
$totalRows = [int64]0

foreach ($tableName in $tableNames) {
  if ($tableName -notmatch '^[A-Za-z0-9_]+$') {
    throw "Unsafe table name returned by metadata query."
  }

  $quoted = $tableName.Replace('"', '""')
  $countText = Invoke-PsqlText `
    -Sql "select count(*) from public.`"$quoted`";"

  $count = [int64]::Parse($countText)
  $counts[$tableName] = $count
  $totalRows += $count
}

$migrationRelationQuery = @"
select case
  when to_regclass('supabase_migrations.schema_migrations') is null
    then 'ABSENT'
  else 'PRESENT'
end;
"@

$migrationRelationState = (
  Invoke-PsqlText -Sql $migrationRelationQuery
).Trim().ToUpperInvariant()

$migrations = @()
$migrationHistoryStatus = "NOT_PRESENT"

if ($migrationRelationState -eq "PRESENT") {
  $migrationQuery = @"
select coalesce(
  string_agg(version::text, ',' order by version),
  ''
)
from supabase_migrations.schema_migrations;
"@

  $migrationText = Invoke-PsqlText -Sql $migrationQuery

  if ($migrationText) {
    $migrations = @(
      $migrationText.Split(',') |
        Where-Object { $_ -and $_.Trim() }
    )
  }

  $migrationHistoryStatus = "PRESENT"
}
elseif ($migrationRelationState -ne "ABSENT") {
  throw "Unexpected migration-history relation state: $migrationRelationState"
}

$payload = [ordered]@{
  generated_at_utc = [DateTime]::UtcNow.ToString("o")
  public_table_count = $counts.Count
  public_total_rows = $totalRows
  public_table_row_counts = $counts
  migration_history_status = $migrationHistoryStatus
  migration_history_relation = "supabase_migrations.schema_migrations"
  migration_versions = $migrations
}

$targetDirectory = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Force -Path $targetDirectory | Out-Null

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$json = $payload | ConvertTo-Json -Depth 20
[System.IO.File]::WriteAllText(
  $OutputPath,
  $json + [Environment]::NewLine,
  $utf8NoBom
)

Write-Host "PASS - database fingerprint written without row content." -ForegroundColor Green
Write-Host "Tables: $($counts.Count)" -ForegroundColor DarkGray
Write-Host "Rows: $totalRows" -ForegroundColor DarkGray
Write-Host "Migration history: $migrationHistoryStatus" -ForegroundColor DarkGray
