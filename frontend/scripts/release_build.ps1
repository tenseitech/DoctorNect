# Auto-increment versionCode in pubspec.yaml, then build a Play Store release AAB.
# Run from frontend root: .\scripts\release_build.ps1
#
# Supabase Cutover Release:
#   To build a cutover release with Supabase connectivity enabled, pass ENABLE_SUPABASE=1:
#     $env:ENABLE_SUPABASE="1"; .\scripts\release_build.ps1
#   Requires SUPABASE_URL and SUPABASE_ANON_KEY to be set in .env or shell environment.
#   NEVER set SUPABASE_SERVICE_ROLE_KEY in client environment (build will fail).
#
# Optional:
#   -DryRun          Preview the next versionCode and build command without changing pubspec or building
#   -SkipIncrement   Build with the current versionCode (no pubspec change)
#   -AllowStaging    Allow staging Supabase URL during build verification

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$SkipIncrement,
    [switch]$AllowStaging,
    [switch]$Launch,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ExtraArgs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ProjectRoot {
    $root = Resolve-Path (Join-Path $PSScriptRoot '..')
    return $root.Path
}

function Import-DotEnv {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    Get-Content -LiteralPath $Path | ForEach-Object {
        $line = $_.Trim()
        if ($line -eq '' -or $line.StartsWith('#')) {
            return
        }
        if ($line -match '^(?<name>[^=]+)=(?<value>.*)$') {
            $name = $Matches['name'].Trim()
            $value = $Matches['value'].Trim()
            if (($value.StartsWith('"') -and $value.EndsWith('"')) -or
                ($value.StartsWith("'") -and $value.EndsWith("'"))) {
                $value = $value.Substring(1, $value.Length - 2)
            }
            if (-not (Test-Path -Path "Env:$name")) {
                Set-Item -Path "Env:$name" -Value $value
            }
        }
    }
}

function Get-FlutterDartDefines {
    param(
        [string[]]$ExtraArgs = @()
    )

    $defines = [System.Collections.Generic.List[string]]::new()

    $androidKey = $env:FIREBASE_API_KEY_ANDROID
    if ([string]::IsNullOrWhiteSpace($androidKey)) {
        $rootEnv = Join-Path (Get-ProjectRoot) '.env'
        if (-not (Test-Path -LiteralPath $rootEnv)) {
            $parentEnv = Join-Path (Get-ProjectRoot) '..\.env'
            if (Test-Path -LiteralPath $parentEnv) {
                $rootEnv = $parentEnv
            }
        }
        $hint = if (-not (Test-Path -LiteralPath $rootEnv)) {
@"

Project root .env is missing (functions/.env is for Cloud Functions only).
Create it from the template, then set your Android Firebase API key:

  Copy-Item .env.example .env
  # Edit .env and set FIREBASE_API_KEY_ANDROID=<Android app API key from Firebase Console>
"@
        } else {
@"

Set FIREBASE_API_KEY_ANDROID in project root .env (not functions/.env), or export it in your shell.
"@
        }

        throw "Missing FIREBASE_API_KEY_ANDROID.$hint`n`nRe-run: .\scripts\release_build.ps1"
    }
    $defines.Add("--dart-define=FIREBASE_API_KEY_ANDROID=$androidKey")

    foreach ($name in @('GOOGLE_MAPS_API_KEY', 'RECAPTCHA_SITE_KEY')) {
        $item = Get-Item -Path "Env:$name" -ErrorAction SilentlyContinue
        if ($null -eq $item) {
            continue
        }
        $value = $item.Value
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            $defines.Add("--dart-define=$name=$value")
        }
    }

    # Guard: SUPABASE_SERVICE_ROLE_KEY must NEVER be present in client release build environment
    if (-not [string]::IsNullOrWhiteSpace($env:SUPABASE_SERVICE_ROLE_KEY)) {
        throw "SECURITY ERROR: SUPABASE_SERVICE_ROLE_KEY detected in environment. Service role keys must NEVER be present during client builds."
    }

    # Never pass USE_SUPABASE_AUTH. Inject Supabase compile-time config only when
    # ENABLE_SUPABASE=1 is set explicitly for this release.
    if ($env:ENABLE_SUPABASE -eq '1') {
        Write-Host 'WARNING: ENABLE_SUPABASE=1 — injecting SUPABASE_URL and SUPABASE_ANON_KEY dart-defines into this release build.' -ForegroundColor Yellow
        
        if ([string]::IsNullOrWhiteSpace($env:SUPABASE_URL)) {
            throw "Missing required environment variable: SUPABASE_URL (required when ENABLE_SUPABASE=1)"
        }
        if ([string]::IsNullOrWhiteSpace($env:SUPABASE_ANON_KEY)) {
            throw "Missing required environment variable: SUPABASE_ANON_KEY (required when ENABLE_SUPABASE=1)"
        }

        $defines.Add("--dart-define=SUPABASE_URL=$($env:SUPABASE_URL)")
        $defines.Add("--dart-define=SUPABASE_ANON_KEY=$($env:SUPABASE_ANON_KEY)")
        if ($Launch -or ($env:USE_SUPABASE_DB_DOCTOR_PATIENT -eq 'true')) {
            $defines.Add("--dart-define=USE_SUPABASE_DB_DOCTOR_PATIENT=true")
        }
    }

    # Guard: APP_CHECK_DEBUG_TOKEN or any *DEBUG_TOKEN* must NEVER be passed as a --dart-define in release builds
    $extraDefines = @($ExtraArgs | Where-Object { $_ -like '--dart-define*' })
    $allDefines = @($defines) + $extraDefines
    $debugDefines = $allDefines | Where-Object { $_ -match '(?i)DEBUG_TOKEN' }
    if ($debugDefines) {
        throw "SECURITY ERROR: Debug token would be passed as a --dart-define in release build ($debugDefines). Debug tokens must NEVER be passed to release builds."
    }

    # Strict allowlist: confirm only intended keys reach dart-defines
    $allowedDefineKeys = @('FIREBASE_API_KEY_ANDROID', 'GOOGLE_MAPS_API_KEY', 'RECAPTCHA_SITE_KEY', 'SUPABASE_URL', 'SUPABASE_ANON_KEY', 'USE_SUPABASE_DB_DOCTOR_PATIENT')
    foreach ($def in $allDefines) {
        $key = (($def -replace '^--dart-define=', '') -split '=')[0]
        if ($allowedDefineKeys -notcontains $key) {
            throw "SECURITY ERROR: Unintended dart-define key '$key' detected. Only allowlisted keys ($($allowedDefineKeys -join ', ')) may reach release builds."
        }
    }

    $intendedNames = $defines | ForEach-Object { (($_ -replace '^--dart-define=', '') -split '=')[0] }
    Write-Host "Configured Dart define keys: $($intendedNames -join ', ')" -ForegroundColor Cyan

    return ,$defines.ToArray()
}

function Test-ProductionBuildConfig {
    param(
        [switch]$AllowStaging
    )

    $stagingUrl = if (-not [string]::IsNullOrWhiteSpace($env:STAGING_SUPABASE_URL)) { $env:STAGING_SUPABASE_URL } else { "https://rnltknemwnjrjxthtull.supabase.co" }
    $prodEndpoint = if (-not [string]::IsNullOrWhiteSpace($env:PROD_GATEWAY_URL)) { $env:PROD_GATEWAY_URL } else { $env:SUPABASE_URL }

    if (-not $AllowStaging -and ($env:ALLOW_STAGING_BUILD -ne 'true')) {
        if ([string]::IsNullOrWhiteSpace($prodEndpoint)) {
            throw "FAIL-FAST SECURITY GATE: Production release build requires a dedicated production API endpoint (PROD_GATEWAY_URL). None configured. Release build aborted."
        }
        if ($prodEndpoint.Trim().ToLower() -eq $stagingUrl.Trim().ToLower() -or $prodEndpoint -like "*rnltknemwnjrjxthtull*") {
            throw "FAIL-FAST SECURITY GATE: Production release build detected STAGING endpoint ($prodEndpoint). Production build must point to dedicated production access layer and differ from staging. Pass -AllowStaging if building a staging artifact."
        }
    }

    # Validate Supabase production configuration independently before compiling
    $validatorScript = Join-Path $PSScriptRoot 'verify_production_build_config.js'
    if (-not (Test-Path -LiteralPath $validatorScript)) {
        $validatorScript = Join-Path (Join-Path (Get-ProjectRoot) '..\backend\scripts') 'verify_production_build_config.js'
    }
    if (Test-Path -LiteralPath $validatorScript) {
        $validatorArgs = @($validatorScript, '--client-only')
        if ($AllowStaging -or ($env:ALLOW_STAGING_BUILD -eq 'true')) {
            $validatorArgs += '--allow-staging'
        }
        if (-not [string]::IsNullOrWhiteSpace($env:SUPABASE_URL)) {
            $validatorArgs += "--supabase-url=$($env:SUPABASE_URL)"
        }
        if (-not [string]::IsNullOrWhiteSpace($env:SUPABASE_ANON_KEY)) {
            $validatorArgs += "--supabase-anon-key=$($env:SUPABASE_ANON_KEY)"
        }

        & node @validatorArgs | Out-Host
        if ($LASTEXITCODE -ne 0) {
            throw "Production Supabase build configuration validation failed. Release build aborted."
        }
    }
}

function Get-PubspecVersion {
    param([string]$PubspecPath)

    $content = Get-Content -LiteralPath $PubspecPath -Raw
    if ($content -notmatch '(?m)^version:\s*(?<name>[^\s+]+)\+(?<code>\d+)\s*$') {
        throw "Could not parse version line in pubspec.yaml (expected: version: X.Y.Z+N)."
    }

    return [pscustomobject]@{
        VersionName = $Matches['name']
        VersionCode = [int]$Matches['code']
    }
}

function Set-PubspecVersionCode {
    param(
        [string]$PubspecPath,
        [string]$VersionName,
        [int]$VersionCode
    )

    $content = Get-Content -LiteralPath $PubspecPath -Raw
    $newLine = "version: $VersionName+$VersionCode"
    $updated = [regex]::Replace(
        $content,
        '(?m)^version:\s*[^\s+]+\+\d+\s*$',
        $newLine,
        1
    )

    if ($updated -eq $content) {
        throw 'Failed to update version line in pubspec.yaml.'
    }

    Set-Content -LiteralPath $PubspecPath -Value $updated -NoNewline
    if (-not $updated.EndsWith("`n")) {
        Add-Content -LiteralPath $PubspecPath -Value ''
    }
}

$projectRoot = Get-ProjectRoot
Push-Location $projectRoot

try {
    if ($Launch) {
        $env:ENABLE_SUPABASE = '1'
        $env:USE_SUPABASE_DB_DOCTOR_PATIENT = 'true'
        if ([string]::IsNullOrWhiteSpace($env:SUPABASE_URL)) {
            $env:SUPABASE_URL = 'https://rnltknemwnjrjxthtull.supabase.co'
        }
        if ([string]::IsNullOrWhiteSpace($env:SUPABASE_ANON_KEY)) {
            $env:SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJubHRrbmVtd25qcmp4dGh0dWxsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTA5NjM3MjIsImV4cCI6MjEwNjUzOTcyMn0.d4bALRDReFuGSNKpxz0iOTyHpaE95Tlpd3DfDxvzvAY'
        }
        Write-Host "LAUNCH PROFILE ACTIVE: Building release with Supabase primary database enabled." -ForegroundColor Green
    }
    Import-DotEnv -Path (Join-Path $projectRoot '.env')
    if (-not (Test-Path -LiteralPath (Join-Path $projectRoot '.env'))) {
        Import-DotEnv -Path (Join-Path $projectRoot '..\.env')
    }
    Test-ProductionBuildConfig -AllowStaging:$AllowStaging
    $dartDefines = Get-FlutterDartDefines -ExtraArgs $ExtraArgs
    $pubspecPath = Join-Path $projectRoot 'pubspec.yaml'

    Write-Host '==========================================' -ForegroundColor Cyan
    Write-Host ' Medibond Android release build' -ForegroundColor Cyan
    Write-Host '==========================================' -ForegroundColor Cyan

    $current = Get-PubspecVersion -PubspecPath $pubspecPath
    $targetVersionCode = if ($SkipIncrement) {
        $current.VersionCode
    } else {
        $current.VersionCode + 1
    }

    if ($DryRun) {
        Write-Host "Current pubspec.yaml version: $($current.VersionName)+$($current.VersionCode)" -ForegroundColor Yellow
        if ($SkipIncrement) {
            Write-Host 'Dry run - would build without changing versionCode.' -ForegroundColor Yellow
        } else {
            Write-Host "Dry run - next versionCode would be: $targetVersionCode" -ForegroundColor Green
        }
    } elseif (-not $SkipIncrement) {
        Set-PubspecVersionCode -PubspecPath $pubspecPath -VersionName $current.VersionName -VersionCode $targetVersionCode
        Write-Host "Updated pubspec.yaml -> version: $($current.VersionName)+$targetVersionCode" -ForegroundColor Green
    } else {
        Write-Host "Using existing version: $($current.VersionName)+$targetVersionCode" -ForegroundColor Yellow
    }

    $buildArgs = @('build', 'appbundle', '--release') + $dartDefines + $ExtraArgs
    $maskedArgs = $buildArgs | ForEach-Object {
        if ($_ -match '^--dart-define=(?<k>[^=]+)=.*$') {
            "--dart-define=$($Matches['k'])=***"
        } else {
            $_
        }
    }
    $buildCommand = 'flutter ' + ($maskedArgs -join ' ')
    Write-Host "Build command: $buildCommand" -ForegroundColor DarkGray

    if ($DryRun) {
        Write-Host ''
        Write-Host 'Dry run only - pubspec.yaml unchanged and no build executed.' -ForegroundColor Yellow
        Write-Host "Next versionCode for Play Console upload: $targetVersionCode" -ForegroundColor Green
        exit 0
    }

    Write-Host ''
    Write-Host 'Building release app bundle...' -ForegroundColor Cyan
    & flutter @buildArgs
    if ($LASTEXITCODE -ne 0) {
        throw "flutter build appbundle failed with exit code $LASTEXITCODE."
    }

    $aabPath = Join-Path $projectRoot 'build\app\outputs\bundle\release\app-release.aab'
    Write-Host ''
    Write-Host 'Release build complete.' -ForegroundColor Green
    Write-Host "  versionName:  $($current.VersionName)"
    Write-Host "  versionCode:  $targetVersionCode" -ForegroundColor Green
    Write-Host "  AAB output:   $aabPath"
    Write-Host ''
    Write-Host "Upload to Play Console using versionCode $targetVersionCode." -ForegroundColor Green
}
finally {
    Pop-Location
}
