<#
.SYNOPSIS
  Fill the auth-gateway / PostgREST secrets in AWS Secrets Manager (created empty by Terraform)
  and store the matching PROD_GATEWAY_SERVICE_KEY in Firebase Secret Manager. No value is ever
  printed, written to the repo, or passed on a command line.

.DESCRIPTION
  Secret (AWS, name prefix doctornect/production/...)  JSON keys            Source
  gateway_service_key_*                                service_key          generated: 48 random bytes, base64
                                                       anon_key             generated: 24 random bytes, hex
  postgrest_jwt_secret_*                               jwt_secret           generated: 48 random bytes, base64
  rds_credentials_*                                    connection_string    built from terraform.tfvars + hidden
                                                                            prompt for the RDS "authenticator"
                                                                            password; sslmode=verify-full with
                                                                            the CA baked into the PostgREST image
  demo-routing                                         DEMO_PGRST_URL       STAGING_SUPABASE_URL from .env + /rest/v1
                                                       DEMO_PGRST_JWT_SECRET hidden prompt (staging Supabase JWT secret)
                                                       DEMO_FIREBASE_UID_ALLOWLIST  empty (the 5 demo UIDs are built in)
  gateway-firebase-admin                               firebase_service_account_json  file you downloaded (-FirebaseKeyFile)

  service_key is also stored in Firebase as PROD_GATEWAY_SERVICE_KEY (project medibond-45fad):
  the Functions and the gateway must hold the same value.

  A secret that already has a value is skipped unless you pass -Overwrite (which rotates it;
  for the service key, both sides are rotated together; redeploy gateway and Functions after).
  Values go to the CLIs through a temporary file in your user temp folder that is deleted
  immediately (AWS: file://, Firebase: --data-file).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File infra/aws/set_gateway_secrets.ps1 -DryRun
  powershell -ExecutionPolicy Bypass -File infra/aws/set_gateway_secrets.ps1 -FirebaseKeyFile C:\Users\me\Downloads\gateway-revocation.json
#>
[CmdletBinding()]
param(
  [string]$Region = 'ap-south-1',
  [string]$FirebaseProject = 'medibond-45fad',
  [string]$FirebaseKeyFile = '',
  [string[]]$Only = @(),
  [switch]$Overwrite,
  [switch]$DryRun
)
$ErrorActionPreference = 'Stop'

$infra = $PSScriptRoot
$repoRoot = Split-Path -Parent (Split-Path -Parent $infra)
foreach ($tool in 'aws', 'firebase') {
  if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "$tool is not installed or not on PATH." }
}

function Get-FileValue([string]$file, [string]$name) {
  if (-not (Test-Path $file)) { return '' }
  foreach ($line in Get-Content -LiteralPath $file) {
    if ($line -match "^\s*$name\s*=\s*(.*)$") { $v = $Matches[1].Trim().Trim('"').Trim("'"); if ($v) { return $v } }
  }
  return ''
}
function New-RandomBase64([int]$bytes) {
  $b = New-Object byte[] $bytes
  [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
  return [Convert]::ToBase64String($b)
}
function New-RandomHex([int]$bytes) {
  $b = New-Object byte[] $bytes
  [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
  return -join ($b | ForEach-Object { $_.ToString('x2') })
}
function Read-Hidden([string]$prompt) {
  $s = Read-Host -AsSecureString $prompt
  $p = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
  try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($p) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($p) }
}
function Invoke-WithTempFile([string]$content, [scriptblock]$action) {
  $tmp = [System.IO.Path]::GetTempFileName()
  try {
    [System.IO.File]::WriteAllText($tmp, $content, (New-Object System.Text.UTF8Encoding($false)))
    & $action $tmp
  } finally {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
  }
}

$account = (& aws sts get-caller-identity --query Account --output text).Trim()
if ($account -notmatch '^\d{12}$') { throw 'AWS CLI is not signed in (aws sts get-caller-identity failed).' }
Write-Host "AWS account $account, region $Region, Firebase project $FirebaseProject$(if ($DryRun) { ' (DRY RUN)' })"

function Find-Secret([string]$prefix) {
  $json = & aws secretsmanager list-secrets --region $Region --filters "Key=name,Values=$prefix" --query 'SecretList[].{arn:ARN,name:Name}' --output json
  $list = @($json | ConvertFrom-Json)
  if ($list.Count -ne 1) { throw "Expected exactly one secret named $prefix* (found $($list.Count)). Run terraform apply first." }
  return $list[0]
}
function Test-HasValue([string]$arn) {
  $meta = & aws secretsmanager describe-secret --region $Region --secret-id $arn --output json | ConvertFrom-Json
  return [bool]($meta.VersionIdsToStages -and ($meta.VersionIdsToStages.PSObject.Properties | Where-Object { $_.Value -contains 'AWSCURRENT' }))
}
function Set-AwsSecret([string]$label, [string]$prefix, [scriptblock]$buildJson) {
  if ($Only.Count -and ($Only -notcontains $label)) { return $null }
  $s = Find-Secret $prefix
  if ((Test-HasValue $s.arn) -and -not $Overwrite) { Write-Host "skip  $label ($($s.name)): already has a value (use -Overwrite to rotate)"; return $null }
  if ($DryRun) { Write-Host "would set  $label ($($s.name))"; return 'dry' }
  $payload = & $buildJson
  Invoke-WithTempFile ($payload | ConvertTo-Json -Compress) {
    param($f)
    & aws secretsmanager put-secret-value --region $Region --secret-id $s.arn --secret-string "file://$f" --output text --query VersionId | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "put-secret-value failed for $label" }
  }
  Write-Host "set   $label ($($s.name))"
  return 'set'
}

$prefix = 'doctornect/production'

# 1) Service key + anon key, and the same service key in Firebase.
$serviceKey = $null
$r = Set-AwsSecret 'gateway_service_key' "$prefix/gateway_service_key_" {
  $script:serviceKey = New-RandomBase64 48
  @{ service_key = $script:serviceKey; anon_key = (New-RandomHex 24) }
}
if ($r -eq 'set') {
  Invoke-WithTempFile $serviceKey {
    param($f)
    & firebase functions:secrets:set PROD_GATEWAY_SERVICE_KEY --project $FirebaseProject --data-file $f | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'firebase functions:secrets:set PROD_GATEWAY_SERVICE_KEY failed (AWS side is already set: rerun with -Only gateway_service_key -Overwrite).' }
  }
  Write-Host 'set   PROD_GATEWAY_SERVICE_KEY (Firebase Secret Manager, same value as service_key)'
} elseif ($r -eq 'dry') {
  Write-Host 'would set  PROD_GATEWAY_SERVICE_KEY (Firebase Secret Manager, same value)'
}
$serviceKey = $null

# 2) PostgREST JWT secret (shared by gateway and PostgREST inside the same task).
Set-AwsSecret 'postgrest_jwt_secret' "$prefix/postgrest_jwt_secret_" { @{ jwt_secret = (New-RandomBase64 48) } } | Out-Null

# 3) RDS connection string for PostgREST (verify-full against the baked-in AWS RDS CA).
Set-AwsSecret 'rds_credentials' "$prefix/rds_credentials_" {
  $tfvars = Join-Path $infra 'terraform.tfvars'
  $endpoint = Get-FileValue $tfvars 'rds_endpoint'
  $db = Get-FileValue $tfvars 'rds_db_name'; if (-not $db) { $db = 'doctornect' }
  $port = Get-FileValue $tfvars 'rds_port'; if (-not $port) { $port = '5432' }
  if (-not $endpoint) { throw 'rds_endpoint missing in infra/aws/terraform.tfvars' }
  $pw = Read-Hidden 'RDS password for the "authenticator" role (input hidden)'
  if ([string]::IsNullOrWhiteSpace($pw)) { throw 'empty password' }
  $uri = "postgres://authenticator:$([uri]::EscapeDataString($pw))@${endpoint}:$port/${db}?sslmode=verify-full&sslrootcert=/etc/ssl/rds/global-bundle.pem"
  @{ connection_string = $uri }
} | Out-Null

# 4) Demo plane (staging Supabase PostgREST) for the five demo accounts.
Set-AwsSecret 'demo_routing' "$prefix/demo-routing" {
  $staging = Get-FileValue (Join-Path $repoRoot '.env') 'STAGING_SUPABASE_URL'
  if ($staging -notmatch '^https://[a-z0-9]+\.supabase\.co/?$') { throw 'STAGING_SUPABASE_URL in .env must be https://<ref>.supabase.co' }
  $jwt = Read-Hidden 'Staging Supabase JWT secret (Dashboard > Project Settings > API > JWT secret; input hidden)'
  if ($jwt.Length -lt 32) { throw 'JWT secret looks too short (expected 32+ characters)' }
  @{ DEMO_PGRST_URL = ($staging.TrimEnd('/') + '/rest/v1'); DEMO_PGRST_JWT_SECRET = $jwt; DEMO_FIREBASE_UID_ALLOWLIST = '' }
} | Out-Null

# 5) Firebase Admin service-account JSON for the revocation check.
Set-AwsSecret 'gateway_firebase_admin' "$prefix/gateway-firebase-admin" {
  if (-not $FirebaseKeyFile -or -not (Test-Path $FirebaseKeyFile)) { throw 'Pass -FirebaseKeyFile <path to the downloaded service-account JSON> (docs/GATEWAY_DEPLOY.md step 4).' }
  $raw = Get-Content -Raw -LiteralPath $FirebaseKeyFile
  $sa = $raw | ConvertFrom-Json
  if ($sa.type -ne 'service_account' -or $sa.project_id -ne $FirebaseProject) { throw "Key file is not a service-account key of $FirebaseProject." }
  @{ firebase_service_account_json = $raw.Trim() }
} | Out-Null

Write-Host 'Done. No values were printed. Delete the downloaded service-account JSON file now.'
