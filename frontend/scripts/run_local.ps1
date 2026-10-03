# Local Flutter run helper — loads Firebase keys from .env and/or google-services.json.
# Usage (from project root):
#   .\scripts\run_local.ps1
#   .\scripts\run_local.ps1 -Device "SM S921E"
#   .\scripts\run_local.ps1 -ExtraArgs @("-d", "chrome")

[CmdletBinding()]
param(
    [string]$Device,
    [string[]]$ExtraArgs = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ProjectRoot {
    return (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
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

function Get-AndroidFirebaseApiKeyFromJson {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    try {
        $json = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
        return $json.client[0].api_key[0].current_key
    } catch {
        return $null
    }
}

function Add-DartDefine {
    param(
        [System.Collections.Generic.List[string]]$Defines,
        [string]$Name,
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return
    }
    $Defines.Add("--dart-define=$Name=$Value")
}

$projectRoot = Get-ProjectRoot
Push-Location $projectRoot

try {
    & (Join-Path $PSScriptRoot 'generate_firebase_secrets.ps1')
    Import-DotEnv -Path (Join-Path $projectRoot '.env')

    $defines = [System.Collections.Generic.List[string]]::new()

    $androidKey = $env:FIREBASE_API_KEY_ANDROID
    if ([string]::IsNullOrWhiteSpace($androidKey)) {
        $androidKey = Get-AndroidFirebaseApiKeyFromJson -Path (Join-Path $projectRoot 'android\app\google-services.json')
    }

    Add-DartDefine -Defines $defines -Name 'FIREBASE_API_KEY_ANDROID' -Value $androidKey
    Add-DartDefine -Defines $defines -Name 'FIREBASE_API_KEY_WEB' -Value $env:FIREBASE_API_KEY_WEB
    Add-DartDefine -Defines $defines -Name 'FIREBASE_API_KEY_IOS' -Value $env:FIREBASE_API_KEY_IOS

    foreach ($name in @('GOOGLE_MAPS_API_KEY', 'RECAPTCHA_SITE_KEY', 'APP_CHECK_DEBUG_TOKEN')) {
        $item = Get-Item -Path "Env:$name" -ErrorAction SilentlyContinue
        if ($null -ne $item) {
            Add-DartDefine -Defines $defines -Name $name -Value $item.Value
        }
    }

    if ([string]::IsNullOrWhiteSpace($androidKey)) {
        throw @"
Missing FIREBASE_API_KEY_ANDROID.

Fix one of:
  1) Copy .env.example to .env and set FIREBASE_API_KEY_ANDROID
  2) Place android/app/google-services.json (then re-run this script)
  3) flutter run --dart-define=FIREBASE_API_KEY_ANDROID=<Android API key from Firebase Console>
"@
    }

    $runArgs = @('run') + $defines.ToArray()
    if (-not [string]::IsNullOrWhiteSpace($Device)) {
        $runArgs += @('-d', $Device)
    }
    if ($ExtraArgs.Count -gt 0) {
        $runArgs += $ExtraArgs
    }

    Write-Host 'Starting Flutter with Firebase dart-defines...' -ForegroundColor Cyan
    Write-Host ('flutter ' + ($runArgs -join ' ')) -ForegroundColor DarkGray
    & flutter @runArgs
    if ($LASTEXITCODE -ne 0) {
        throw "flutter run failed with exit code $LASTEXITCODE."
    }
}
finally {
    Pop-Location
}
