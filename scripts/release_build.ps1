# Auto-increment versionCode in pubspec.yaml, then build a Play Store release AAB.
# Run from project root: .\scripts\release_build.ps1
#
# Optional:
#   -DryRun          Preview the next versionCode and build command without changing pubspec or building
#   -SkipIncrement    Build with the current versionCode (no pubspec change)

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$SkipIncrement
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
            Set-Item -Path "Env:$name" -Value $value
        }
    }
}

function Get-FlutterDartDefines {
    $defines = [System.Collections.Generic.List[string]]::new()

    $androidKey = $env:FIREBASE_API_KEY_ANDROID
    if ([string]::IsNullOrWhiteSpace($androidKey)) {
        $rootEnv = Join-Path (Get-ProjectRoot) '.env'
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

    return ,$defines.ToArray()
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
    Import-DotEnv -Path (Join-Path $projectRoot '.env')
    $dartDefines = Get-FlutterDartDefines
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

    $buildArgs = @('build', 'appbundle', '--release') + $dartDefines
    $buildCommand = 'flutter ' + ($buildArgs -join ' ')
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
