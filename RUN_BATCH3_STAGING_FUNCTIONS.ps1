$ErrorActionPreference = "Stop"

Set-Location "C:\StayQR_MASTER\01_SOURCE\stayqr-platform"

$ProjectRef = "eecinuhvkxlbdvyuazal"
$Functions = @(
    "verify-aadhaar-offline",
    "whatsapp-send",
    "whatsapp-status-webhook",
    "purge-guest-retention"
)

Write-Host "`n=== DEPLOY BATCH 3 EDGE FUNCTIONS TO STAYQR STAGING ===" -ForegroundColor Cyan
Write-Host "Project ref: $ProjectRef" -ForegroundColor Yellow

foreach ($Fn in $Functions) {
    Write-Host "`nDeploying $Fn..." -ForegroundColor Cyan

    npx supabase functions deploy $Fn --project-ref $ProjectRef --no-verify-jwt

    if ($LASTEXITCODE -ne 0) {
        throw "STOP: Deployment failed for $Fn."
    }
}

Write-Host "`n====================================================" -ForegroundColor Green
Write-Host "BATCH 3 STAGING EDGE FUNCTIONS: DEPLOYED" -ForegroundColor Green
Write-Host "Production was not targeted." -ForegroundColor Green
Write-Host "====================================================" -ForegroundColor Green
