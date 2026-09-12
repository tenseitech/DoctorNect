# Deploy Flutter Web App to Firebase Hosting with optimized release settings.
# Run from project root: .\tool\deploy-web.ps1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Push-Location $PSScriptRoot\..

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " Building DoctorNect Web (Release)..." -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

flutter build web --release --tree-shake-icons

if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Flutter web build failed." -ForegroundColor Red
    Pop-Location
    exit $LASTEXITCODE
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " Deploying to Firebase Hosting..." -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

firebase deploy --only hosting

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "✅ Web Deployment successful! Site performance optimized." -ForegroundColor Green
} else {
    Write-Host "Error: Firebase deployment failed." -ForegroundColor Red
}

Pop-Location
