<#
.SYNOPSIS
  Store the Cloud Functions secrets in Firebase Secret Manager (project medibond-45fad) without
  ever printing a value or putting it on a command line.

.DESCRIPTION
  Name                            Source
  OTP_HMAC_SECRET                 generated here: 48 random bytes, base64 (skipped if it already
                                  exists, unless -Replace; rotating invalidates OTPs sent in the last
                                  10 minutes only)

  A secret that already exists in Secret Manager is skipped unless you pass -Replace.
  REVIEW_FIXED_OTP                hidden prompt, must be exactly 6 digits
  DEMO_SUPABASE_SERVICE_ROLE_KEY  STAGING_SUPABASE_SERVICE_ROLE_KEY from .env (same staging project),
                                  otherwise hidden prompt
  AWS_ACCESS_KEY_ID               .env value, otherwise hidden prompt (-PromptAll forces prompts, e.g.
  AWS_SECRET_ACCESS_KEY           for the NEW key of the doctornect-functions-s3-production IAM user)
  RAZORPAY_WEBHOOK_SECRET         .env value, otherwise hidden prompt
  REDIS_PASSWORD                  .env value, otherwise hidden prompt
  SUPABASE_SERVICE_ROLE_KEY       .env value, otherwise hidden prompt

  PROD_GATEWAY_SERVICE_KEY is NOT set here: infra/aws/set_gateway_secrets.ps1 generates it and
  stores the same value in AWS (gateway) and Firebase (Functions).

  Each value is written to a temporary file in your user temp folder, passed with
  `firebase functions:secrets:set NAME --project medibond-45fad --data-file <file>`, and the file
  is deleted immediately. Output shows names and actions only.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts/env/set_functions_secrets.ps1 -DryRun
  powershell -ExecutionPolicy Bypass -File scripts/env/set_functions_secrets.ps1
  powershell -ExecutionPolicy Bypass -File scripts/env/set_functions_secrets.ps1 -Only AWS_ACCESS_KEY_ID,AWS_SECRET_ACCESS_KEY -PromptAll -Replace
#>
[CmdletBinding()]
param(
  [string]$Project = 'medibond-45fad',
  [string[]]$Only = @(),
  [switch]$PromptAll,
  [switch]$Replace,
  [switch]$DryRun
)
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$envFile = Join-Path $repoRoot '.env'
if (-not (Get-Command firebase -ErrorAction SilentlyContinue)) { throw 'firebase CLI not found (npm install -g firebase-tools, then firebase login).' }

function Get-EnvFileValue([string]$name) {
  if (-not (Test-Path $envFile)) { return '' }
  $found = ''
  foreach ($line in Get-Content -LiteralPath $envFile) {
    if ($line -match "^\s*$name\s*=\s*(.*)$") {
      $v = $Matches[1].Trim().Trim('"').Trim("'")
      if ($v) { $found = $v }
    }
  }
  return $found
}
function Read-Hidden([string]$prompt) {
  $s = Read-Host -AsSecureString $prompt
  $p = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
  try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($p) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($p) }
}
function New-RandomBase64([int]$bytes) {
  $b = New-Object byte[] $bytes
  [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
  return [Convert]::ToBase64String($b)
}
function Test-SecretExists([string]$name) {
  $ErrorActionPreference = 'Continue'
  & firebase functions:secrets:get $name --project $Project *> $null
  return ($LASTEXITCODE -eq 0)
}
function Set-FirebaseSecret([string]$name, [string]$value) {
  $tmp = [System.IO.Path]::GetTempFileName()
  try {
    [System.IO.File]::WriteAllText($tmp, $value, (New-Object System.Text.UTF8Encoding($false)))
    $ErrorActionPreference = 'Continue'
    & firebase functions:secrets:set $name --project $Project --data-file $tmp *> $null
    if ($LASTEXITCODE -ne 0) { throw "firebase functions:secrets:set $name failed (are you logged in? firebase login)" }
  } finally {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
  }
}

# name -> how to obtain the value
$plan = [ordered]@{
  'OTP_HMAC_SECRET'                = 'generate'
  'REVIEW_FIXED_OTP'               = 'prompt-otp'
  'DEMO_SUPABASE_SERVICE_ROLE_KEY' = 'env:STAGING_SUPABASE_SERVICE_ROLE_KEY'
  'AWS_ACCESS_KEY_ID'              = 'env:AWS_ACCESS_KEY_ID'
  'AWS_SECRET_ACCESS_KEY'          = 'env:AWS_SECRET_ACCESS_KEY'
  'RAZORPAY_WEBHOOK_SECRET'        = 'env:RAZORPAY_WEBHOOK_SECRET'
  'REDIS_PASSWORD'                 = 'env:REDIS_PASSWORD'
  'SUPABASE_SERVICE_ROLE_KEY'      = 'env:SUPABASE_SERVICE_ROLE_KEY'
}

Write-Host "Firebase project: $Project$(if ($DryRun) { '  (DRY RUN: nothing is read from prompts or written)' })"
$done = @()
foreach ($name in $plan.Keys) {
  if ($Only.Count -and ($Only -notcontains $name)) { continue }
  $how = $plan[$name]
  $exists = Test-SecretExists $name

  if ($how -eq 'generate') {
    if ($exists -and -not $Replace) { Write-Host "skip  $name : already in Secret Manager (use -Replace to rotate it)"; continue }
    if ($DryRun) { Write-Host "would set  $name : generated 48 random bytes (base64)"; continue }
    Set-FirebaseSecret $name (New-RandomBase64 48)
    Write-Host "set   $name : generated"
    $done += $name
    continue
  }

  if ($exists -and -not $Replace) { Write-Host "skip  $name : already in Secret Manager (use -Replace to overwrite)"; continue }
  $source = ''
  $value = ''
  if ($how -like 'env:*' -and -not $PromptAll) {
    $value = Get-EnvFileValue ($how.Substring(4))
    if ($value) { $source = ".env ($($how.Substring(4)))" }
  }
  if ($DryRun) {
    Write-Host ("would set  {0} : from {1}{2}" -f $name, $(if ($source) { $source } else { 'hidden prompt' }), $(if ($exists) { ' (replaces the current version)' } else { '' }))
    continue
  }
  if (-not $value) {
    $value = Read-Hidden "$name (input hidden; Enter on empty input skips)"
    $source = 'prompt'
  }
  if ([string]::IsNullOrWhiteSpace($value)) { Write-Host "skip  $name : empty"; continue }
  if ($how -eq 'prompt-otp' -and $value -notmatch '^\d{6}$') { throw 'REVIEW_FIXED_OTP must be exactly 6 digits.' }
  Set-FirebaseSecret $name $value.Trim()
  $value = $null
  Write-Host "set   $name : from $source"
  $done += $name
}

if ($done.Count) {
  Write-Host ''
  Write-Host "Stored: $($done -join ', ')"
  Write-Host 'Check (metadata only, no values): npm run check:boot-env -- .env --target=functions --check-secret-manager'
  Write-Host 'Then remove these lines from .env (the deploy never uses them from .env): AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, RAZORPAY_WEBHOOK_SECRET, REDIS_PASSWORD, SUPABASE_SERVICE_ROLE_KEY'
}
