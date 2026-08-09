$ErrorActionPreference = 'Stop'

$RepoRoot = 'C:\StayQR_D18_WORK'
$Checker = Join-Path $RepoRoot 'scripts\day18-canonical-baseline-source-check.mjs'
$Audit078 = Join-Path $RepoRoot 'supabase\audit\202608090078_day19_full_crud_storage_isolation_REV7_STORAGE_API_POSITIVE_CONTROL_FIX.sql'
$Audit079 = Join-Path $RepoRoot 'supabase\audit\202608090079_day19_gate19c_final_post_state_REV3_STORAGE_MODEL_FIX.sql'
$Db = 'host=aws-0-ap-southeast-2.pooler.supabase.com port=5432 dbname=postgres user=postgres.eecinuhvkxlbdvyuazal sslmode=require'

Set-Location $RepoRoot

Write-Host ''
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host 'STAYQR DAY 19 - GATE 19C FINAL REV9' -ForegroundColor Cyan
Write-Host 'Storage positive-control correction only.' -ForegroundColor Cyan
Write-Host 'NO migration. NO production deploy. NO Git push.' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan

foreach ($Required in @($Checker, $Audit078, $Audit079)) {
  if (-not (Test-Path -LiteralPath $Required)) {
    throw ('Missing required file: ' + $Required)
  }
}

Write-Host ''
Write-Host '=== 1. CANONICAL / REPOSITORY PRECHECK ===' -ForegroundColor Yellow

$Branch = (& git branch --show-current).Trim()
$Head = (& git rev-parse --short HEAD).Trim()
Write-Host ('Branch: ' + $Branch)
Write-Host ('HEAD:   ' + $Head)

if ($Branch -ne 'feature/day19-full-qa-uat') {
  throw ('Unexpected branch: ' + $Branch)
}

& node --check $Checker
if ($LASTEXITCODE -ne 0) {
  throw 'Canonical checker JavaScript syntax failed.'
}

& node $Checker
if ($LASTEXITCODE -ne 0) {
  throw 'Canonical source checker failed.'
}

& git diff --check
if ($LASTEXITCODE -ne 0) {
  throw 'git diff --check failed.'
}

Write-Host 'PASS - canonical source + repository integrity' -ForegroundColor Green

Write-Host ''
Write-Host '=== 2. STAGING FINAL AUDIT 078 REV7 + 079 REV3 ===' -ForegroundColor Yellow
Write-Host 'Audit 077 REV7 already passed 18/18 in the immediately previous REV8 run.' -ForegroundColor Yellow
Write-Host 'No migration is executed.' -ForegroundColor Yellow
Write-Host 'Enter the StayQR Staging DATABASE password once.' -ForegroundColor Yellow

$PsqlArgs = @(
  $Db,
  '-W',
  '-v', 'ON_ERROR_STOP=1',
  '-P', 'pager=off',
  '-f', $Audit078,
  '-f', $Audit079
)

$ErrorActionPreference = 'Continue'
$DbOutput = @(& psql @PsqlArgs 2>&1)
$DbExitCode = $LASTEXITCODE
$ErrorActionPreference = 'Stop'

$DbOutput

Write-Host ''
Write-Host ('PSQL EXIT CODE: ' + $DbExitCode) -ForegroundColor Yellow

if ($DbExitCode -ne 0) {
  $Failures = @(
    $DbOutput | Select-String -Pattern 'ERROR:|FATAL:|PANIC:|SECURITY BREACH|\|\s*f\s*\|'
  )

  if ($Failures.Count -gt 0) {
    Write-Host ''
    Write-Host '=== FINAL FAILURE LINES ===' -ForegroundColor Red
    $Failures
  }

  throw ('Gate 19C FINAL REV9 failed with psql exit code ' + $DbExitCode)
}

$A078Pass = @(
  $DbOutput |
    Select-String -SimpleMatch '=== AUDIT 078 REV7 PASS - GATE 19C FULL CRUD STORAGE ISOLATION 28/28 ==='
).Count -gt 0

$A079Pass = @(
  $DbOutput |
    Select-String -SimpleMatch '=== AUDIT 079 REV3 PASS - GATE 19C FINAL POST-STATE 12/12 ==='
).Count -gt 0

if (-not $A078Pass) {
  throw 'Audit 078 REV7 did not emit 28/28 PASS.'
}

if (-not $A079Pass) {
  throw 'Audit 079 REV3 did not emit 12/12 PASS.'
}

Write-Host ''
Write-Host '============================================================' -ForegroundColor Green
Write-Host 'GATE 19C FINAL REV9 PASS' -ForegroundColor Green
Write-Host 'Audit 077 REV7 tenant isolation: PREVIOUSLY 18/18 PASS' -ForegroundColor Green
Write-Host 'Audit 078 REV7 full CRUD + Storage: 28/28 PASS' -ForegroundColor Green
Write-Host 'Audit 079 REV3 final post-state: 12/12 PASS' -ForegroundColor Green
Write-Host 'Hotel A -> Hotel B hotel_onboarding attack: BLOCKED' -ForegroundColor Green
Write-Host 'Cross-tenant Storage attacks: BLOCKED' -ForegroundColor Green
Write-Host 'Own-tenant Storage RLS positive predicates: PASS' -ForegroundColor Green
Write-Host 'All temporary Gate 19C fixtures: ROLLED BACK' -ForegroundColor Green
Write-Host 'No migration, production deploy or Git push was performed.' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Green
