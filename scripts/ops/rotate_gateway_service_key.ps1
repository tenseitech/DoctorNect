#Requires -Version 5.1
<#
.SYNOPSIS
  Generate a new gateway service key and sync AWS Secrets Manager + Firebase PROD_GATEWAY_SERVICE_KEY.
  Run this last in the production secrets order (after set_production_gateway_aws_secrets + set_demo_secrets).
  The key value is never printed or logged.

.PARAMETER WhatIf
  Preview actions only (no AWS/Firebase writes).

.PARAMETER AwsSecretName
  Full Secrets Manager name or ARN. If omitted, discovers doctornect/<AwsEnv>/gateway_service_key* .

.PARAMETER AwsEnv
  Path segment in secret name (default: production).

.PARAMETER FirebaseProject
  Firebase project for functions:secrets:set (default: medibond-45fad).
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [string]$AwsSecretName = '',
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

function New-GatewayServiceKeySecure {
  $bytes = New-Object byte[] 32
  [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
  $hex = ([BitConverter]::ToString($bytes) -replace '-', '').ToLowerInvariant()
  return ConvertTo-SecureString -String $hex -AsPlainText -Force
}

function Resolve-AwsGatewaySecretName {
  param([string]$Hint)
  if (-not [string]::IsNullOrWhiteSpace($Hint)) {
    return $Hint.Trim()
  }
  $prefix = "doctornect/$AwsEnv/gateway_service_key"
  if ($WhatIf) {
    Write-Host "[WhatIf] Would list secrets matching $prefix* and use the newest match."
    return $prefix
  }
  $json = aws secretsmanager list-secrets --filters "Key=name,Values=$prefix" --output json
  if ($LASTEXITCODE -ne 0) { throw "list-secrets failed (exit $LASTEXITCODE)" }
  $list = $json | ConvertFrom-Json
  $match = @($list.SecretList | Where-Object { $_.Name -like "$prefix*" } | Sort-Object CreatedDate -Descending)
  if ($match.Count -lt 1) {
    throw "No AWS secret found with prefix $prefix (run terraform apply first or pass -AwsSecretName)."
  }
  if ($match.Count -gt 1) {
    Write-Host "Multiple gateway_service_key secrets; using newest: $($match[0].Name)"
  }
  return $match[0].Name
}

function Set-AwsGatewayServiceKey {
  param(
    [string]$SecretId,
    [SecureString]$KeySecure
  )
  if ($WhatIf) {
    Write-Host "[WhatIf] aws secretsmanager put-secret-value --secret-id $SecretId --secret-string file://<temp>"
    return
  }
  $plain = ConvertFrom-SecurePlain $KeySecure
  $path = $null
  try {
    $payload = @{ service_key = $plain } | ConvertTo-Json -Compress
    $path = Join-Path ([System.IO.Path]::GetTempPath()) ("doctornect-gateway-key-{0}.json" -f [guid]::NewGuid().ToString('N'))
    [System.IO.File]::WriteAllText($path, $payload, [System.Text.UTF8Encoding]::new($false))
    aws secretsmanager put-secret-value --secret-id $SecretId --secret-string "file://$path"
    if ($LASTEXITCODE -ne 0) { throw "put-secret-value failed (exit $LASTEXITCODE)" }
    Write-Host "AWS secret updated: $SecretId (service_key not shown)."
  } finally {
    $payload = $null
    $plain = $null
    if ($path -and (Test-Path -LiteralPath $path)) { Remove-Item -LiteralPath $path -Force }
  }
}

function Set-FirebaseGatewayServiceKey {
  param([SecureString]$KeySecure)
  if ($WhatIf) {
    Write-Host "[WhatIf] firebase functions:secrets:set PROD_GATEWAY_SERVICE_KEY --project $FirebaseProject"
    return
  }
  $plain = ConvertFrom-SecurePlain $KeySecure
  try {
    $plain | firebase functions:secrets:set PROD_GATEWAY_SERVICE_KEY --project $FirebaseProject --data-file -
    if ($LASTEXITCODE -ne 0) { throw "firebase secrets:set failed (exit $LASTEXITCODE)" }
    Write-Host 'Firebase secret set: PROD_GATEWAY_SERVICE_KEY'
  } finally {
    $plain = $null
  }
}

Write-Host "Rotate gateway service key (project=$FirebaseProject, awsEnv=$AwsEnv). Value never echoed."

$keySecure = New-GatewayServiceKeySecure
$secretName = Resolve-AwsGatewaySecretName -Hint $AwsSecretName

$doWrite = $WhatIf -or $PSCmdlet.ShouldProcess($secretName, 'Update AWS gateway_service_key and Firebase PROD_GATEWAY_SERVICE_KEY')
if ($doWrite) {
  Set-AwsGatewayServiceKey -SecretId $secretName -KeySecure $keySecure
  Set-FirebaseGatewayServiceKey -KeySecure $keySecure
}

$keySecure = $null
Write-Host 'Done. Redeploy narrow OTP callables + cycle ECS tasks after secret rotation.'