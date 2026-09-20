# Writes lib/firebase_options.secrets.dart from .env and/or google-services.json.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$envPath = Join-Path $projectRoot '.env'
$googleServicesPath = Join-Path $projectRoot 'android\app\google-services.json'
$outPath = Join-Path $projectRoot 'lib\firebase_options.secrets.dart'

function Import-DotEnv {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    Get-Content -LiteralPath $Path | ForEach-Object {
        $line = $_.Trim()
        if ($line -eq '' -or $line.StartsWith('#')) { return }
        if ($line -match '^(?<name>[^=]+)=(?<value>.*)$') {
            $name = $Matches['name'].Trim()
            $value = $Matches['value'].Trim().Trim('"').Trim("'")
            Set-Item -Path "Env:$name" -Value $value
        }
    }
}

function Read-AndroidApiKey {
    if (-not (Test-Path -LiteralPath $googleServicesPath)) { return '' }
    try {
        $json = Get-Content -LiteralPath $googleServicesPath -Raw | ConvertFrom-Json
        return [string]$json.client[0].api_key[0].current_key
    } catch {
        return ''
    }
}

Import-DotEnv -Path $envPath

$webKey = if ($env:FIREBASE_API_KEY_WEB) { $env:FIREBASE_API_KEY_WEB } else { '' }
$androidKey = if ($env:FIREBASE_API_KEY_ANDROID) { $env:FIREBASE_API_KEY_ANDROID } else { Read-AndroidApiKey }
$iosKey = if ($env:FIREBASE_API_KEY_IOS) { $env:FIREBASE_API_KEY_IOS } else { '' }

$content = @"
// Generated for local development. Do not commit real keys to git.
// Regenerate: .\scripts\run_local.ps1  or  .\scripts\generate_firebase_secrets.ps1
abstract final class FirebaseOptionsSecrets {
  static const String webApiKey = '$webKey';
  static const String androidApiKey = '$androidKey';
  static const String iosApiKey = '$iosKey';
}
"@

Set-Content -LiteralPath $outPath -Value $content -Encoding utf8
Write-Host "Wrote $outPath" -ForegroundColor Green
