param(
  [switch]$ProductionRolloutAuthorized,
  [Parameter(Mandatory=$false)][string]$ExpectedCommit = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$RepoRoot = 'C:\StayQR_MASTER\01_SOURCE\stayqr-platform'
$Branch = 'commercial-ready/final-completion'
$Tag = 'stayqr-commercial-ready-final-locked'

if (-not $ProductionRolloutAuthorized) {
  throw 'Commercial-Ready production rollout is NOT authorized. Staging work may continue; no branch/tag push was performed.'
}
if ($ExpectedCommit -notmatch '^[0-9a-f]{40}$') { throw 'ExpectedCommit must be the exact 40-character commit accepted for production.' }

Push-Location $RepoRoot
try {
  if ((git branch --show-current).Trim() -ne $Branch) { throw "Current branch must be $Branch." }
  if (@(git status --porcelain).Count -gt 0) { throw 'Repository must be clean before final lock.' }
  $head = (git rev-parse HEAD).Trim()
  if ($head -ne $ExpectedCommit) { throw "HEAD $head does not match the explicitly accepted commit $ExpectedCommit." }

  npm run validate:commercial-ready
  if ($LASTEXITCODE -ne 0) { throw 'Commercial-Ready final source validation failed.' }

  $confirmation = Read-Host 'Type exactly: AUTHORIZE STAYQR COMMERCIAL READY FINAL LOCK'
  if ($confirmation -cne 'AUTHORIZE STAYQR COMMERCIAL READY FINAL LOCK') { throw 'Final lock confirmation did not match. Nothing was pushed.' }

  git tag -a $Tag $ExpectedCommit -m 'StayQR Commercial-Ready final locked'
  if ($LASTEXITCODE -ne 0) { throw 'Final annotated tag creation failed.' }
  git push origin $Branch
  if ($LASTEXITCODE -ne 0) { throw 'Final branch push failed.' }
  git push origin $Tag
  if ($LASTEXITCODE -ne 0) { throw 'Final tag push failed.' }

  Write-Host 'STAYQR_COMMERCIAL_READY_FINAL_LOCK: PASS' -ForegroundColor Green
  Write-Host "Commit: $ExpectedCommit"
  Write-Host "Tag: $Tag"
}
finally { Pop-Location }
