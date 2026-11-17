#Requires -Version 5.1
<#
.SYNOPSIS
  Build and push DoctorNect Auth Gateway image to ECR (no deploy).

.PARAMETER AwsAccountId
.PARAMETER AwsRegion
  Defaults: placeholders — replace before run.
#>
param(
    [string]$AwsAccountId = 'AWS_ACCOUNT_ID',
    [string]$AwsRegion = 'ap-south-1',
    [string]$Repository = 'doctornect-auth-gateway',
    [string]$ImageTag = 'latest'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '../..')
$dockerfileDir = Join-Path $repoRoot 'services/api-gateway'

$registry = "$AwsAccountId.dkr.ecr.$AwsRegion.amazonaws.com"
$imageUri = "$registry/${Repository}:$ImageTag"

Write-Host "ECR registry: $registry"
Write-Host "Build context: $dockerfileDir"

aws ecr describe-repositories --repository-names $Repository --region $AwsRegion 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Creating ECR repository $Repository ..."
    aws ecr create-repository --repository-name $Repository --region $AwsRegion --image-scanning-configuration scanOnPush=true
}

aws ecr get-login-password --region $AwsRegion | docker login --username AWS --password-stdin $registry

Push-Location $dockerfileDir
try {
    docker build -t "${Repository}:$ImageTag" .
    docker tag "${Repository}:$ImageTag" $imageUri
    docker push $imageUri
} finally {
    Pop-Location
}

Write-Host ""
Write-Host "Terraform gateway_image = `"$imageUri`""
Write-Host "PostgREST (public pull on ECS host): postgrest/postgrest:v16.5"
Write-Host "Terraform postgrest_image = `"postgrest/postgrest:v16.5`""