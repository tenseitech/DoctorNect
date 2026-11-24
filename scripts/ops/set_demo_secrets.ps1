#Requires -Version 5.1
<#
.SYNOPSIS
  Set production demo-login secrets (Firebase REVIEW/DEMO + AWS demo-routing) without printing values.
  PROD_GATEWAY_SERVICE_KEY is set only by rotate_gateway_service_key.ps1 (run that script last).

.PARAMETER WhatIf
  Show planned actions only; do not call Firebase/AWS or write .env.

.PARAMETER AwsEnv
  Environment segment in secret name doctornect/<AwsEnv>/demo-routing (default: prod).

.PARAMETER FirebaseProject
  Default: medibond-45fad
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [string]$AwsEnv = 'production',
  [string]$FirebaseProject = 'medibond-45fad'
)

$WhatIf = $WhatIfPreference

$ErrorActionPreference = 'Stop'

function ConvertFrom-SecurePlain {
  param([SecureString]$Secure)
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
  try {
    return [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
  } finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
  }
}

function Set-EnvLine {
  param(
    [string]$FilePath,
    [string]$Key,
    [string]$Value
  )
  if (-not (Test-Path -LiteralPath $FilePath)) {
    throw "Missing .env at $FilePath"
  }
  $lines = Get-Content -LiteralPath $FilePath -Encoding utf8
  $pattern = "^\s*#?\s*$([regex]::Escape($Key))\s*="
  $newLine = "$Key=$Value"
  $found = $false
  $out = foreach ($line in $lines) {
    if ($line -match $pattern) {
      $found = $true
      $newLine
    } else {
      $line
    }
  }
  if (-not $found) {
    $out += $newLine
  }
  if ($WhatIf) {
    Write-Host "[WhatIf] Would update $Key in $FilePath"
  } else {
    Set-Content -LiteralPath $FilePath -Value $out -Encoding utf8
    Write-Host "Updated $Key in .env (value not shown)."
  }
}

function Invoke-FirebaseSecretSet {
  param(
    [string]$Name,
    [SecureString]$SecureValue
  )
  if ($WhatIf) {
    Write-Host "[WhatIf] firebase functions:secrets:set $Name --project $FirebaseProject"
    return
  }
  $plain = ConvertFrom-SecurePlain $SecureValue
  try {
    $plain | firebase functions:secrets:set $Name --project $FirebaseProject --data-file -
    if ($LASTEXITCODE -ne 0) { throw "firebase secrets:set failed for $Name (exit $LASTEXITCODE)" }
    Write-Host "Firebase secret set: $Name"
  } finally {
    $plain = $null
  }
}

function Write-TempJsonFile {
  param([hashtable]$Object)
  $path = Join-Path ([System.IO.Path]::GetTempPath()) ("doctornect-demo-routing-{0}.json" -f [guid]::NewGuid().ToString('N'))
  $json = $Object | ConvertTo-Json -Compress
  if ($WhatIf) {
    Write-Host "[WhatIf] Would write AWS JSON to temp file and delete after put-secret-value"
    return $null
  }
  try {
    [System.IO.File]::WriteAllText($path, $json, [System.Text.UTF8Encoding]::new($false))
    return $path
  } catch {
    if (Test-Path $path) { Remove-Item -LiteralPath $path -Force }
    throw
  }
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$envFile = Join-Path $repoRoot '.env'

Write-Host "DoctorNect demo secret setup (project=$FirebaseProject, awsEnv=$AwsEnv)"
Write-Host "Secrets are never echoed. Use -WhatIf to preview."

$awsSecretName = "doctornect/$AwsEnv/demo-routing"
if ($WhatIf) {
  Write-Host '[WhatIf] firebase functions:secrets:set REVIEW_FIXED_OTP --project' $FirebaseProject
  Write-Host '[WhatIf] firebase functions:secrets:set DEMO_SUPABASE_SERVICE_ROLE_KEY --project' $FirebaseProject
  Write-Host "[WhatIf] aws secretsmanager put-secret-value --secret-id $awsSecretName --keys DEMO_FIREBASE_UID_ALLOWLIST,DEMO_PGRST_URL,DEMO_PGRST_JWT_SECRET"
  Write-Host '[WhatIf] .env updates: STAGING_SUPABASE_DB_URL, DEMO_SUPABASE_URL, DEMO_PGRST_URL (non-secret URLs only)'
  Write-Host 'Done (WhatIf).'
  exit 0
}

$reviewOtp = Read-Host 'REVIEW_FIXED_OTP (6-digit Play Store reviewer OTP)' -AsSecureString
$demoSupabaseKey = Read-Host 'DEMO_SUPABASE_SERVICE_ROLE_KEY (Supabase staging API service_role)' -AsSecureString

$demoPgrstUrl = Read-Host 'DEMO_PGRST_URL (e.g. https://<ref>.supabase.co/rest/v1)'
$demoPgrstJwt = Read-Host 'DEMO_PGRST_JWT_SECRET (Supabase JWT signing secret for PostgREST)' -AsSecureString

$stagingDbUrlSecure = Read-Host 'STAGING_SUPABASE_DB_URL (read-only doctornect_audit pooler URI)' -AsSecureString
$stagingDbUrl = ConvertFrom-SecurePlain $stagingDbUrlSecure
$stagingDbUrlSecure = $null
$demoSupabaseUrl = Read-Host 'DEMO_SUPABASE_URL (Supabase project URL, https://<ref>.supabase.co)'
if ([string]::IsNullOrWhiteSpace($demoPgrstUrl)) {
  $trim = $demoSupabaseUrl.TrimEnd('/')
  $demoPgrstUrl = "$trim/rest/v1"
  Write-Host "DEMO_PGRST_URL derived from DEMO_SUPABASE_URL (not logged)."
}

$allowlist = 'rev_fb_pat_001,rev_fb_doc_001,rev_fb_store_001,rev_fb_lab_001,rev_fb_amb_001'

Invoke-FirebaseSecretSet -Name 'REVIEW_FIXED_OTP' -SecureValue $reviewOtp
Invoke-FirebaseSecretSet -Name 'DEMO_SUPABASE_SERVICE_ROLE_KEY' -SecureValue $demoSupabaseKey

$awsPayload = @{
  DEMO_FIREBASE_UID_ALLOWLIST = $allowlist
  DEMO_PGRST_URL              = $demoPgrstUrl.Trim()
  DEMO_PGRST_JWT_SECRET       = (ConvertFrom-SecurePlain $demoPgrstJwt)
}
$awsSecretName = "doctornect/$AwsEnv/demo-routing"

$tempFile = Write-TempJsonFile -Object $awsPayload
try {
  if ($WhatIf) {
    Write-Host "[WhatIf] aws secretsmanager put-secret-value --secret-id $awsSecretName --secret-string file://<temp>"
  } else {
    $exists = $false
    try {
      aws secretsmanager describe-secret --secret-id $awsSecretName 2>$null | Out-Null
      if ($LASTEXITCODE -eq 0) { $exists = $true }
    } catch { $exists = $false }

    if (-not $exists) {
      aws secretsmanager create-secret --name $awsSecretName --description 'Demo routing for auth-gateway ECS' --secret-string "file://$tempFile"
    } else {
      aws secretsmanager put-secret-value --secret-id $awsSecretName --secret-string "file://$tempFile"
    }
    if ($LASTEXITCODE -ne 0) { throw "AWS Secrets Manager update failed (exit $LASTEXITCODE)" }
    Write-Host "AWS secret updated: $awsSecretName"
  }
} finally {
  if ($tempFile -and (Test-Path -LiteralPath $tempFile)) {
    Remove-Item -LiteralPath $tempFile -Force
  }
  $awsPayload.DEMO_PGRST_JWT_SECRET = $null
}

Set-EnvLine -FilePath $envFile -Key 'STAGING_SUPABASE_DB_URL' -Value $stagingDbUrl.Trim()
Set-EnvLine -FilePath $envFile -Key 'DEMO_SUPABASE_URL' -Value $demoSupabaseUrl.Trim()
Set-EnvLine -FilePath $envFile -Key 'DEMO_PGRST_URL' -Value $demoPgrstUrl.Trim()

Write-Host 'Done. Firebase reviewer/demo secrets + AWS demo-routing updated; .env has only non-secret audit URLs.'
Write-Host 'Next: rotate_gateway_service_key.ps1 (last), then reply "secrets set" in Cursor.'