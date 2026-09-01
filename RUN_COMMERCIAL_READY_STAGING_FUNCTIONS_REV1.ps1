$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoRoot = 'C:\StayQR_MASTER\01_SOURCE\stayqr-platform'
$StagingProjectRef = 'eecinuhvkxlbdvyuazal'

if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot 'supabase\config.toml'))) {
  throw "StayQR source was not found at $RepoRoot"
}

Push-Location $RepoRoot
try {
  $branch = (git branch --show-current).Trim()
  if ($branch -ne 'commercial-ready/final-completion') { throw 'Switch to commercial-ready/final-completion before deploying staging functions.' }

  supabase functions deploy cashfree-recurring --project-ref $StagingProjectRef --no-verify-jwt
  if ($LASTEXITCODE -ne 0) { throw 'cashfree-recurring staging deployment failed.' }
  supabase functions deploy cashfree-subscription-webhook --project-ref $StagingProjectRef --no-verify-jwt
  if ($LASTEXITCODE -ne 0) { throw 'cashfree-subscription-webhook staging deployment failed.' }
  supabase functions deploy uidai-online-auth --project-ref $StagingProjectRef --no-verify-jwt
  if ($LASTEXITCODE -ne 0) { throw 'uidai-online-auth staging deployment failed.' }

  Write-Host 'STAYQR_COMMERCIAL_READY_STAGING_FUNCTIONS: PASS' -ForegroundColor Green
  Write-Host 'Safety flags remain OFF until provider-specific staging activation is approved.'
  Write-Host 'Production changed: NO'
}
finally { Pop-Location }
