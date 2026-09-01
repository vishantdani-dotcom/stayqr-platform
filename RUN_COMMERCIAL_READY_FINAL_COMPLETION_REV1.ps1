$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$PackageRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = 'C:\StayQR_MASTER\01_SOURCE\stayqr-platform'
$BaseCommit = '5f914d4cd049353e9926b26ffb1599e53a6f1772'
$WorkingBranch = 'commercial-ready/final-completion'

if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot '.git'))) {
  throw "StayQR repository was not found at $RepoRoot"
}

Push-Location $RepoRoot
try {
  $dirty = @(git status --porcelain)
  if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect the StayQR repository.' }
  if ($dirty.Count -gt 0) { throw 'The StayQR repository has uncommitted changes. Preserve them before running this consolidated installer.' }

  git cat-file -e "$BaseCommit`^{commit}"
  if ($LASTEXITCODE -ne 0) { throw "Required locked V1.1 base commit $BaseCommit is unavailable." }

  git show-ref --verify --quiet "refs/heads/$WorkingBranch"
  if ($LASTEXITCODE -eq 0) {
    git switch $WorkingBranch
    if ($LASTEXITCODE -ne 0) { throw "Unable to switch to $WorkingBranch." }
    $branchHead = (git rev-parse HEAD).Trim()
    if ($branchHead -ne $BaseCommit) { throw "$WorkingBranch already exists at $branchHead instead of the required untouched base $BaseCommit." }
  } else {
    git switch -c $WorkingBranch $BaseCommit
    if ($LASTEXITCODE -ne 0) { throw "Unable to create $WorkingBranch from $BaseCommit." }
  }

  $Files = @(
    '.env.example',
    'package.json',
    'src\App.jsx',
    'src\components\sidebar\Sidebar.jsx',
    'src\lib\currentStaff.js',
    'src\lib\guestCompliance.js',
    'src\lib\commercialReady.js',
    'src\pages\dashboard\Dashboard.jsx',
    'src\components\cards\ActivationScore.jsx',
    'src\components\cards\ActivationScore.css',
    'src\pages\billing\OwnerBilling.jsx',
    'src\pages\billing\OwnerBilling.css',
    'src\components\guests\GuestIdentityCompliance.jsx',
    'src\components\guests\GuestIdentityCompliance.css',
    'src\pages\operationscenter\OperationsCenter.jsx',
    'src\pages\legal\SupportEscalationPolicy.jsx',
    'scripts\validate-commercial-ready.mjs',
    'supabase\config.toml',
    'supabase\migrations\202609010103_commercial_ready_final_completion_REV1.sql',
    'supabase\staging\202609010103_commercial_ready_FINAL_STAGING_APPLY_AND_ACCEPT.sql',
    'supabase\rollback\202609010103_commercial_ready_ROLLBACK_REV1.sql',
    'supabase\functions\cashfree-recurring\index.ts',
    'supabase\functions\cashfree-subscription-webhook\index.ts',
    'supabase\functions\uidai-online-auth\index.ts',
    'docs\commercial-ready\COMMERCIAL_READY_PROVIDER_CONFIGURATION_REV1.md',
    'docs\commercial-ready\COMMERCIAL_READY_BROWSER_ACCEPTANCE_REV1.md',
    'docs\commercial-ready\COMMERCIAL_READY_ROLLBACK_REV1.md',
    'docs\commercial-ready\COMMERCIAL_READY_24X7_SUPPORT_RUNBOOK_REV1.md',
    'README_COMMERCIAL_READY_FINAL_COMPLETION_REV1.md',
    'RUN_COMMERCIAL_READY_STAGING_FUNCTIONS_REV1.ps1',
    'RUN_COMMERCIAL_READY_FINAL_ACCEPTANCE_AND_LOCK_REV1.ps1'
  )

  foreach ($relative in $Files) {
    $source = Join-Path $PackageRoot $relative
    $target = Join-Path $RepoRoot $relative
    if (-not (Test-Path -LiteralPath $source)) { throw "Package file missing: $relative" }
    $targetDirectory = Split-Path -Parent $target
    if (-not (Test-Path -LiteralPath $targetDirectory)) { New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null }
    Copy-Item -LiteralPath $source -Destination $target -Force
  }

  npm ci
  if ($LASTEXITCODE -ne 0) { throw 'npm ci failed.' }
  npm run validate:commercial-ready
  if ($LASTEXITCODE -ne 0) { throw 'Commercial-Ready source validation failed.' }

  Write-Host ''
  Write-Host 'STAYQR_COMMERCIAL_READY_IMPLEMENTATION: PASS' -ForegroundColor Green
  Write-Host "Branch: $WorkingBranch"
  Write-Host 'Production changed: NO'
  Write-Host 'Next: run the consolidated staging SQL in StayQR Staging.'
}
finally {
  Pop-Location
}
