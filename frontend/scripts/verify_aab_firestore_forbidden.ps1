# Compile-time smoke: release kernel must reference FIRESTORE_FORBIDDEN guard (not a secret).
param(
    [string]$DartDefineValue = 'true'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '..')
Push-Location $root
try {
    flutter build aot --release --target=lib/main.dart `
        "--dart-define=FIRESTORE_FORBIDDEN=$DartDefineValue" `
        "--dart-define=FIREBASE_API_KEY_ANDROID=$($env:FIREBASE_API_KEY_ANDROID)" 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'flutter build aot failed' }
    $kernel = Join-Path $root 'build\app\intermediates\flutter\release\app.dill'
    if (-not (Test-Path $kernel)) {
        throw "Kernel not found at $kernel — run full release_build.ps1 first."
    }
    $bytes = [System.IO.File]::ReadAllBytes($kernel)
    $text = [System.Text.Encoding]::UTF8.GetString($bytes)
    if ($text -notmatch 'FIRESTORE_FORBIDDEN') {
        throw 'FIRESTORE_FORBIDDEN string not found in release kernel (app.dill).'
    }
    Write-Host 'PASS: FIRESTORE_FORBIDDEN present in release kernel.'
} finally {
    Pop-Location
}