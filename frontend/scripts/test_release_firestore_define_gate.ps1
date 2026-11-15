# Verifies release build fails closed when FIRESTORE_FORBIDDEN is absent from dart-defines.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-ReleaseFirestoreForbiddenDefine {
    param([string[]]$Defines)
    $hit = @($Defines | Where-Object { $_ -match '^--dart-define=FIRESTORE_FORBIDDEN=(true|1)$' })
    if ($hit.Count -lt 1) {
        throw 'FAIL-FAST SECURITY GATE: Release builds require --dart-define=FIRESTORE_FORBIDDEN=true (compile-time guard).'
    }
}

Write-Host 'Case A: missing FIRESTORE_FORBIDDEN must throw...'
$failed = $false
try {
    Assert-ReleaseFirestoreForbiddenDefine -Defines @('--dart-define=FIREBASE_API_KEY_ANDROID=test')
} catch {
    $failed = $true
    Write-Host "  PASS: $($_.Exception.Message)"
}
if (-not $failed) {
    Write-Error 'Case A FAIL: expected throw'
    exit 1
}

Write-Host 'Case B: FIRESTORE_FORBIDDEN=true must pass...'
try {
    Assert-ReleaseFirestoreForbiddenDefine -Defines @(
        '--dart-define=FIREBASE_API_KEY_ANDROID=test',
        '--dart-define=FIRESTORE_FORBIDDEN=true'
    )
    Write-Host '  PASS: gate accepted FIRESTORE_FORBIDDEN=true'
} catch {
    Write-Error "Case B FAIL: $($_.Exception.Message)"
    exit 1
}

Write-Host 'OK: release Firestore define gate self-test'