<#
.SYNOPSIS
  Production deploy gate for the Cloud Functions (project medibond-45fad). Runs the gates in
  order and stops at the first failure. Deploys only when every gate passes, then checks that
  the new code is live.

.DESCRIPTION
  Gate 1  npm run check:boot-env -- .env --target=functions --check-secret-manager   (0 FAIL, 0 CHECK)
  Gate 2  backend/functions tests (npm test)                                          (0 failing)
  Gate 3  services/api-gateway tests (npm test)                                       (0 failing)
  Gate 4  GET https://api.doctornect.com/healthz                                      (HTTP 200)
  Deploy  cd backend/functions; npm run deploy -- --project medibond-45fad
  Verify  the live getValidationRulesHttp answers with the security headers of the new code
          (X-Content-Type-Options: nosniff). The old build does not send it.

  No gate is weakened or skipped. -NoDeploy runs the gates only. Prints names and results, never
  secret values (check:boot-env redacts its own output).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts/env/predeploy_gate.ps1 -NoDeploy
  powershell -ExecutionPolicy Bypass -File scripts/env/predeploy_gate.ps1
#>
[CmdletBinding()]
param(
  [string]$Project = 'medibond-45fad',
  [string]$GatewayHealthUrl = 'https://api.doctornect.com/healthz',
  [switch]$NoDeploy
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$liveProbeUrl = "https://asia-south1-$Project.cloudfunctions.net/getValidationRulesHttp"

function Stop-Gate([string]$gate, [string]$why, [string]$todo) {
  Write-Host ''
  Write-Host "GATE FAILED: $gate" -ForegroundColor Red
  Write-Host "  Why:  $why"
  Write-Host "  Do:   $todo"
  Write-Host 'Nothing was deployed.'
  exit 1
}
function Invoke-Step([string]$dir, [string]$cmd) {
  Push-Location $dir
  try {
    $ErrorActionPreference = 'Continue'
    $out = & cmd.exe /d /c "$cmd 2>&1"
    return @{ Code = $LASTEXITCODE; Out = ($out -join "`n") }
  } finally {
    Pop-Location
    $ErrorActionPreference = 'Stop'
  }
}
function Get-TestSummary([string]$text) {
  $pass = [regex]::Match($text, '(?m)^\S*\s*pass (\d+)').Groups[1].Value
  $fail = [regex]::Match($text, '(?m)^\S*\s*fail (\d+)').Groups[1].Value
  return "pass=$pass fail=$fail"
}

Write-Host "== Gate 1/4: check:boot-env (Secret Manager verified)"
$r = Invoke-Step $repoRoot 'npm run -s check:boot-env -- .env --target=functions --check-secret-manager'
$lines = $r.Out -split "`n" | Where-Object { $_ -match '^(FAIL|CHECK)\s' -or $_ -match '^\d+ FAIL' }
$lines | ForEach-Object { Write-Host "   $_" }
if ($r.Code -ne 0) {
  Stop-Gate 'check:boot-env' 'at least one FAIL or unverified CHECK (lines above)' `
    'fix each FAIL (docs/GATEWAY_DEPLOY.md and PRODUCTION_BOOT_CHECKLIST.md), then rerun this script'
}

Write-Host "== Gate 2/4: backend/functions tests"
$r = Invoke-Step (Join-Path $repoRoot 'backend/functions') 'npm test'
Write-Host "   $(Get-TestSummary $r.Out)"
if ($r.Code -ne 0) { Stop-Gate 'backend tests' 'a backend test failed' 'run: cd backend/functions; npm test  and fix the failing test' }

Write-Host "== Gate 3/4: services/api-gateway tests"
$r = Invoke-Step (Join-Path $repoRoot 'services/api-gateway') 'npm test'
Write-Host "   $(Get-TestSummary $r.Out)"
if ($r.Code -ne 0) { Stop-Gate 'gateway tests' 'a gateway test failed' 'run: cd services/api-gateway; npm test  and fix the failing test' }

Write-Host "== Gate 4/4: $GatewayHealthUrl"
$status = 0
try {
  $status = (Invoke-WebRequest -Uri $GatewayHealthUrl -UseBasicParsing -TimeoutSec 15).StatusCode
} catch {
  $why = $_.Exception.Message
  Stop-Gate 'gateway health' "no HTTP 200 ($why)" `
    'finish docs/GATEWAY_DEPLOY.md (secrets, desired count 1 + apply, DNS CNAME) until this URL returns 200'
}
if ($status -ne 200) { Stop-Gate 'gateway health' "HTTP $status" 'check the ECS task logs in CloudWatch' }
Write-Host '   200'

if ($NoDeploy) { Write-Host ''; Write-Host 'All gates passed (-NoDeploy: not deploying).'; exit 0 }

Write-Host "== Deploy: backend/functions -> $Project"
Push-Location (Join-Path $repoRoot 'backend/functions')
try {
  & cmd.exe /d /c "npm run deploy -- --project $Project"
  if ($LASTEXITCODE -ne 0) { throw "firebase deploy failed (exit $LASTEXITCODE)" }
} finally { Pop-Location }

Write-Host "== Verify: new code is live"
$live = $false
foreach ($i in 1..6) {
  try {
    $resp = Invoke-WebRequest -Uri $liveProbeUrl -UseBasicParsing -TimeoutSec 15
    if ($resp.Headers['X-Content-Type-Options'] -eq 'nosniff') { $live = $true; break }
  } catch {}
  Start-Sleep -Seconds 20
}
if (-not $live) {
  Write-Host 'Deployed, but the live probe does not show the new security headers yet. Re-run the probe in a few minutes.' -ForegroundColor Yellow
  exit 1
}
Write-Host 'New Functions code is live (security headers present).' -ForegroundColor Green
