<#
.SYNOPSIS
  Builds the STAGING test APK (App Check debug provider) wired to the staging Supabase project.

.DESCRIPTION
  A release APK built with plain `flutter build apk` has no SUPABASE_URL / SUPABASE_ANON_KEY
  dart-defines, so after a successful OTP login the app cannot read any profile and shows
  "Account profile not found for this mobile number." This script passes the staging data plane
  (STAGING_SUPABASE_URL / STAGING_SUPABASE_ANON_KEY from the repo-root .env or the shell), plus
  APP_ENV=staging and APP_CHECK_DEBUG_PROVIDER=true. Values are never printed.

  This build is for testing the five demo accounts (docs/DEMO_ACCOUNTS.md). Real users must use
  the production build (scripts/release_build.ps1), which talks to the API gateway / RDS.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File frontend/scripts/build_staging_demo_apk.ps1
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'

$frontend = Split-Path -Parent $PSScriptRoot
$repoRoot = Split-Path -Parent $frontend
$envFile = Join-Path $repoRoot '.env'

function Get-EnvValue([string]$name) {
  $fromShell = [Environment]::GetEnvironmentVariable($name)
  if (-not [string]::IsNullOrWhiteSpace($fromShell)) { return $fromShell.Trim() }
  if (Test-Path $envFile) {
    foreach ($line in Get-Content -LiteralPath $envFile) {
      if ($line -match "^\s*$name\s*=\s*(.*)$") {
        return $Matches[1].Trim().Trim('"').Trim("'")
      }
    }
  }
  return ''
}

$url = Get-EnvValue 'STAGING_SUPABASE_URL'
$anon = Get-EnvValue 'STAGING_SUPABASE_ANON_KEY'
if ([string]::IsNullOrWhiteSpace($url) -or [string]::IsNullOrWhiteSpace($anon)) {
  throw 'STAGING_SUPABASE_URL and STAGING_SUPABASE_ANON_KEY are required (repo-root .env or shell).'
}
if ($url -notmatch '^https://[a-z0-9-]+\.supabase\.co/?$') {
  throw 'STAGING_SUPABASE_URL must be the staging https://<ref>.supabase.co URL (refusing anything else).'
}
$prodGateway = Get-EnvValue 'PROD_GATEWAY_URL'
if ($prodGateway -and ($url.TrimEnd('/') -eq $prodGateway.TrimEnd('/'))) {
  throw 'STAGING_SUPABASE_URL equals PROD_GATEWAY_URL; refusing to build a staging APK against production.'
}

Write-Host 'Building staging demo APK (APP_ENV=staging, App Check debug provider, staging Supabase)...'
Push-Location $frontend
try {
  & flutter build apk --release `
    "--dart-define=APP_ENV=staging" `
    "--dart-define=APP_CHECK_DEBUG_PROVIDER=true" `
    "--dart-define=SUPABASE_URL=$url" `
    "--dart-define=SUPABASE_ANON_KEY=$anon"
  if ($LASTEXITCODE -ne 0) { throw "flutter build failed with exit code $LASTEXITCODE" }
  $out = Join-Path $frontend 'build\app\outputs\flutter-apk'
  Copy-Item (Join-Path $out 'app-release.apk') (Join-Path $out 'app-staging-demo.apk') -Force
  Write-Host "Built: $(Join-Path $out 'app-staging-demo.apk')"
} finally {
  Pop-Location
}
