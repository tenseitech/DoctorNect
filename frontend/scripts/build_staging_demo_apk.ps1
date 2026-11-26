<#
.SYNOPSIS
  Builds the STAGING test APK (App Check debug provider) wired to the staging Supabase project.

.DESCRIPTION
  A release APK built with plain `flutter build apk` has no SUPABASE_URL / SUPABASE_ANON_KEY
  dart-defines, so after a successful OTP login the app cannot read any profile and shows
  "Account profile not found for this mobile number." This script passes the staging data plane
  (STAGING_SUPABASE_URL / STAGING_SUPABASE_ANON_KEY) and the Firebase client config
  (FIREBASE_API_KEY_ANDROID, FIREBASE_PROJECT_ID) from the repo-root .env or the shell, plus
  APP_ENV=staging and APP_CHECK_DEBUG_PROVIDER=true (plus APP_CHECK_DEBUG_TOKEN when set). It stops before building when any of
  them is missing. Values are never printed.

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

# Every client variable this APK needs. Missing names are listed together and the build stops
# before Flutter runs, so an APK without Firebase or data-plane config is never produced.
$required = [ordered]@{
  'FIREBASE_API_KEY_ANDROID'  = 'Firebase Android API key (Firebase console > Project settings > Your apps > Android)'
  'FIREBASE_PROJECT_ID'       = 'Firebase project id (must match android/app/google-services.json)'
  'STAGING_SUPABASE_URL'      = 'staging Supabase project URL'
  'STAGING_SUPABASE_ANON_KEY' = 'staging Supabase anon (public) key'
}
$values = @{}
$missing = @()
foreach ($name in $required.Keys) {
  $values[$name] = Get-EnvValue $name
  if ([string]::IsNullOrWhiteSpace($values[$name])) { $missing += $name }
}
if ($missing.Count -gt 0) {
  $lines = $missing | ForEach-Object { "  - $_ : $($required[$_])" }
  throw ("Missing required variables (repo-root .env or shell); nothing was built:`n" + ($lines -join "`n"))
}

$googleServices = Join-Path $frontend 'android\app\google-services.json'
$gsProject = ((Get-Content -Raw -LiteralPath $googleServices) | ConvertFrom-Json).project_info.project_id
if ($values['FIREBASE_PROJECT_ID'] -ne $gsProject) {
  throw "FIREBASE_PROJECT_ID does not match android/app/google-services.json (project_id). Fix .env; nothing was built."
}

$url = $values['STAGING_SUPABASE_URL']
$anon = $values['STAGING_SUPABASE_ANON_KEY']
if ($url -notmatch '^https://[a-z0-9-]+\.supabase\.co/?$') {
  throw 'STAGING_SUPABASE_URL must be the staging https://<ref>.supabase.co URL (refusing anything else).'
}
$prodGateway = Get-EnvValue 'PROD_GATEWAY_URL'
if ($prodGateway -and ($url.TrimEnd('/') -eq $prodGateway.TrimEnd('/'))) {
  throw 'STAGING_SUPABASE_URL equals PROD_GATEWAY_URL; refusing to build a staging APK against production.'
}

$defines = @(
  '--dart-define=APP_ENV=staging',
  '--dart-define=APP_CHECK_DEBUG_PROVIDER=true',
  '--dart-define=FIRESTORE_FORBIDDEN=true',
  "--dart-define=FIREBASE_API_KEY_ANDROID=$($values['FIREBASE_API_KEY_ANDROID'])",
  "--dart-define=FIREBASE_PROJECT_ID=$($values['FIREBASE_PROJECT_ID'])",
  "--dart-define=SUPABASE_URL=$url",
  "--dart-define=SUPABASE_ANON_KEY=$anon"
)
# Optional: a fixed App Check debug token already registered in Firebase Console (App Check >
# Manage debug tokens). Without it the debug provider makes a new random token per install, so
# after a fresh install every callable (OTP send/verify) fails with UNAUTHENTICATED until that
# new token is registered. Value never printed.
$appCheckToken = Get-EnvValue 'APP_CHECK_DEBUG_TOKEN'
if ($appCheckToken) {
  $defines += "--dart-define=APP_CHECK_DEBUG_TOKEN=$appCheckToken"
} else {
  Write-Host 'APP_CHECK_DEBUG_TOKEN not set: register the debug secret DebugAppCheckProvider prints in logcat after install.'
}
# Names only, never values.
$provided = $defines | ForEach-Object { (($_ -replace '^--dart-define=', '') -split '=')[0] }
Write-Host "Provided dart-defines: $($provided -join ', ')"

Write-Host 'Building staging demo APK (APP_ENV=staging, App Check debug provider, staging Supabase)...'
Push-Location $frontend
try {
  & flutter build apk --release @defines
  if ($LASTEXITCODE -ne 0) { throw "flutter build failed with exit code $LASTEXITCODE" }
  $out = Join-Path $frontend 'build\app\outputs\flutter-apk'
  Copy-Item (Join-Path $out 'app-release.apk') (Join-Path $out 'app-staging-demo.apk') -Force
  Write-Host "Built: $(Join-Path $out 'app-staging-demo.apk')"
} finally {
  Pop-Location
}
