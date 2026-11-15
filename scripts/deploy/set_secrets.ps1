#Requires -Version 5.1
<#
.SYNOPSIS
  Interactive Firebase Functions v2 secret setup (no values stored in git).

.DESCRIPTION
  Prompts for each secret defined via defineSecret() in backend/functions.
  Run from repo root after: firebase login --reauth && firebase use <prod-project>

  Production note: bind PROD_GATEWAY_SERVICE_KEY value to SUPABASE_SERVICE_ROLE_KEY
  secret for deploy metadata compatibility (runtime uses PROD_GATEWAY_* env).
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$secrets = @(
    @{ Name = 'SUPABASE_SERVICE_ROLE_KEY'; Note = 'Production: same value as PROD_GATEWAY_SERVICE_KEY (gateway service key, not Supabase JWT).' },
    @{ Name = 'RAZORPAY_WEBHOOK_SECRET'; Note = 'Razorpay dashboard webhook HMAC secret.' },
    @{ Name = 'AWS_ACCESS_KEY_ID'; Note = 'S3 presign / storage audit IAM user access key id.' },
    @{ Name = 'AWS_SECRET_ACCESS_KEY'; Note = 'Matching secret for AWS_ACCESS_KEY_ID.' },
    @{ Name = 'SUPABASE_WEBHOOK_SECRET'; Note = 'HMAC for optional DB webhook handler.' },
    @{ Name = 'REDIS_HOST'; Note = 'Memorystore host (rediss://hostname or hostname only per your env).' },
    @{ Name = 'REDIS_PORT'; Note = 'Usually 6379 or TLS port from Memorystore.' },
    @{ Name = 'REDIS_PASSWORD'; Note = 'Redis AUTH string if enabled; empty string if none.' }
)

function Test-FirebaseCli {
    if (-not (Get-Command firebase -ErrorAction SilentlyContinue)) {
        throw 'firebase CLI not found. Install: npm i -g firebase-tools'
    }
}

Test-FirebaseCli

Write-Host "Firebase project:" -ForegroundColor Cyan
firebase use

foreach ($item in $secrets) {
    Write-Host ""
    Write-Host "Secret: $($item.Name)" -ForegroundColor Yellow
    Write-Host "  $($item.Note)"
    $value = Read-Host "Enter value (input hidden)" -AsSecureString
    $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($value)
    )
    if ([string]::IsNullOrWhiteSpace($plain)) {
        Write-Host "  Skipped (empty)." -ForegroundColor DarkGray
        continue
    }
    $tmp = [System.IO.Path]::GetTempFileName()
    try {
        [System.IO.File]::WriteAllText($tmp, $plain, [System.Text.UTF8Encoding]::new($false))
        firebase functions:secrets:set $item.Name --data-file $tmp --force
        if ($LASTEXITCODE -ne 0) {
            throw "firebase functions:secrets:set failed for $($item.Name)"
        }
    } finally {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR(
            [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($value)
        )
    }
    Write-Host "  Set OK." -ForegroundColor Green
}

Write-Host ""
Write-Host "Done. Next: set non-secret production env (see MANUAL_STEPS ECS runbook) then deploy when ready." -ForegroundColor Green