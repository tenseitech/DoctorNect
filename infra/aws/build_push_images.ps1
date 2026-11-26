<#
.SYNOPSIS
  Build the auth-gateway and PostgREST (RDS CA) images, push them to ECR with an immutable tag,
  and write the two image names into infra/aws/terraform.tfvars (local, git-ignored).

.DESCRIPTION
  Needs: Docker Desktop running, AWS CLI v2 signed in (aws configure / aws sso login) to the
  production account, and the ECR repositories created by `terraform apply` (ecr.tf).
  Tag = current git commit (short). Tags are immutable, so a commit is pushed only once.
  Prints image names only; no credentials are printed (the ECR login token goes straight
  from the AWS CLI into docker login through a pipe).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File infra/aws/build_push_images.ps1 -DryRun
  powershell -ExecutionPolicy Bypass -File infra/aws/build_push_images.ps1
#>
[CmdletBinding()]
param(
  [string]$Region = 'ap-south-1',
  [switch]$DryRun
)
$ErrorActionPreference = 'Stop'

$infra = $PSScriptRoot
$repoRoot = Split-Path -Parent (Split-Path -Parent $infra)
$tfvars = Join-Path $infra 'terraform.tfvars'

foreach ($tool in 'docker', 'aws', 'git') {
  if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "$tool is not installed or not on PATH." }
}
if (-not (Test-Path $tfvars)) { throw 'infra/aws/terraform.tfvars not found (copy terraform.tfvars.example first).' }

$sha = (& git -C $repoRoot rev-parse --short=12 HEAD).Trim()
$dirty = (& git -C $repoRoot status --porcelain -- services/api-gateway services/postgrest)
if ($dirty) { throw 'services/api-gateway or services/postgrest has uncommitted changes; commit first so the tag matches the code.' }

$account = (& aws sts get-caller-identity --query Account --output text).Trim()
if ($account -notmatch '^\d{12}$') { throw 'AWS CLI is not signed in (aws sts get-caller-identity failed).' }
$registry = "$account.dkr.ecr.$Region.amazonaws.com"
$gatewayImage = "$registry/doctornect-auth-gateway:$sha"
$postgrestImage = "$registry/doctornect-postgrest:v16.5-rdsca-$sha"

Write-Host "Account: $account  Region: $Region"
Write-Host "Gateway image:   $gatewayImage"
Write-Host "PostgREST image: $postgrestImage"
if ($DryRun) { Write-Host 'Dry run: nothing built, pushed or written.'; return }

$ErrorActionPreference = 'Continue'
& aws ecr get-login-password --region $Region | & docker login --username AWS --password-stdin $registry | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'docker login to ECR failed.' }
$ErrorActionPreference = 'Stop'

# Fargate tasks run linux/amd64 (ecs_cpu_architecture = X86_64).
& docker build --platform linux/amd64 -t $gatewayImage (Join-Path $repoRoot 'services/api-gateway')
if ($LASTEXITCODE -ne 0) { throw 'gateway image build failed.' }
& docker build --platform linux/amd64 -t $postgrestImage (Join-Path $repoRoot 'services/postgrest')
if ($LASTEXITCODE -ne 0) { throw 'PostgREST image build failed.' }
& docker push $gatewayImage
if ($LASTEXITCODE -ne 0) { throw 'gateway image push failed.' }
& docker push $postgrestImage
if ($LASTEXITCODE -ne 0) { throw 'PostgREST image push failed.' }

$text = Get-Content -Raw -LiteralPath $tfvars
$text = [regex]::Replace($text, '(?m)^gateway_image\s*=.*$', "gateway_image   = `"$gatewayImage`"")
$text = [regex]::Replace($text, '(?m)^postgrest_image\s*=.*$', "postgrest_image = `"$postgrestImage`"")
Set-Content -LiteralPath $tfvars -Value $text -Encoding utf8 -NoNewline
Write-Host 'Pushed both images and updated gateway_image / postgrest_image in terraform.tfvars.'
Write-Host 'Next: terraform plan -out tfplan (docs/GATEWAY_DEPLOY.md step 6).'
