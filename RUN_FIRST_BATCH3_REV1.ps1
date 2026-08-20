$ErrorActionPreference = "Stop"

Set-Location "C:\StayQR_MASTER\01_SOURCE\stayqr-platform"

$ExpectedBranch = "feature/postlaunch-batch3-guest-identity-crm"
$Branch = (git branch --show-current).Trim()

if ($Branch -ne $ExpectedBranch) {
    throw "STOP: Expected $ExpectedBranch but current branch is $Branch"
}

Write-Host "`n=== STAYQR BATCH 3 / C CONSOLIDATED LOCAL ACCEPTANCE ===" -ForegroundColor Cyan

npm run validate:postlaunch-batch3
if ($LASTEXITCODE -ne 0) {
    throw "STOP: Batch 3 consolidated validation failed."
}

git diff --check
if ($LASTEXITCODE -ne 0) {
    throw "STOP: git diff --check failed."
}

$StagingSql = ".\supabase\staging\202608210092_postlaunch_batch3_STAGING_APPLY_AND_ACCEPT.sql"
if (-not (Test-Path $StagingSql)) {
    throw "STOP: Batch 3 staging SQL bundle is missing."
}

Get-Content $StagingSql -Raw | Set-Clipboard

Write-Host "`n====================================================" -ForegroundColor Green
Write-Host "BATCH 3 LOCAL ACCEPTANCE: PASS" -ForegroundColor Green
Write-Host "Staging SQL copied to clipboard." -ForegroundColor Green
Write-Host "Expected DB gate: POSTLAUNCH_BATCH3_DATABASE_ACCEPTANCE: PASS (36/36)" -ForegroundColor Green
Write-Host "====================================================" -ForegroundColor Green

git status --short
