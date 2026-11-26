#Requires -Version 5.1
<#
  Set Terraform-created AWS secrets (no values printed).
  Targets exact secret names from: aws secretsmanager list-secrets --filter doctornect/production

  Usage (interactive secure prompts):
    .\scripts\ops\set_production_gateway_aws_secrets.ps1 -WhatIf   # preview key names only
    .\scripts\ops\set_production_gateway_aws_secrets.ps1           # put-secret-value

  Optional overrides:
    -RdsCredentialsSecretName
    -PostgrestJwtSecretName
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [string]$RdsCredentialsSecretName = 'doctornect/production/rds_credentials_20261123074100176100000004',
  [string]$PostgrestJwtSecretName = 'doctornect/production/postgrest_jwt_secret_20261123074100176100000006',
  [string]$Region = 'ap-south-1'
)

$WhatIf = $WhatIfPreference
$ErrorActionPreference = 'Stop'

function ConvertFrom-SecurePlain {
  param([SecureString]$Secure)
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
  try { return [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

function Put-JsonSecret {
  param([string]$SecretId, [hashtable]$Object, [string]$Label)
  if ($WhatIf) {
    Write-Host "[WhatIf] aws secretsmanager put-secret-value --secret-id $SecretId --secret-string file://<temp> (keys: $($Object.Keys -join ', '))"
    return
  }
  $path = Join-Path ([System.IO.Path]::GetTempPath()) ("doctornect-sm-{0}.json" -f [guid]::NewGuid().ToString('N'))
  $json = $Object | ConvertTo-Json -Compress
  try {
    [System.IO.File]::WriteAllText($path, $json, [System.Text.UTF8Encoding]::new($false))
    aws secretsmanager put-secret-value --region $Region --secret-id $SecretId --secret-string "file://$path"
    if ($LASTEXITCODE -ne 0) { throw "put-secret-value failed for $Label" }
    Write-Host "Updated $Label on $SecretId (value not shown)."
  } finally {
    $json = $null
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
  }
}

Write-Host "Production AWS gateway secrets (keys only in WhatIf). Values never echoed."

if ($WhatIf) {
  Write-Host "[WhatIf] put-secret-value $RdsCredentialsSecretName keys: connection_string"
  Write-Host "[WhatIf] put-secret-value $PostgrestJwtSecretName keys: jwt_secret"
  exit 0
}

$connSecure = Read-Host 'connection_string (postgresql://authenticator@RDS host — password via your secure flow)' -AsSecureString
$jwtSecure = Read-Host 'jwt_secret (new random min 32 chars)' -AsSecureString

if ($PSCmdlet.ShouldProcess($RdsCredentialsSecretName, 'Put database_credentials JSON')) {
  $conn = ConvertFrom-SecurePlain $connSecure
  try {
    Put-JsonSecret -SecretId $RdsCredentialsSecretName -Object @{ connection_string = $conn } -Label 'database_credentials'
  } finally { $conn = $null }
}

if ($PSCmdlet.ShouldProcess($PostgrestJwtSecretName, 'Put postgrest_jwt_secret JSON')) {
  $jwt = ConvertFrom-SecurePlain $jwtSecure
  try {
    Put-JsonSecret -SecretId $PostgrestJwtSecretName -Object @{ jwt_secret = $jwt } -Label 'postgrest_jwt_secret'
  } finally { $jwt = $null }
}

$connSecure = $null
$jwtSecure = $null
Write-Host 'Done. Next: set_demo_secrets.ps1, then rotate_gateway_service_key.ps1 (gateway key last).'