#Requires -Version 5.1
<#
  Read-only: list doctornect-production infra for import decisions. No secret values printed.
#>
param(
  [string]$Region = 'ap-south-1',
  [string]$Project = 'doctornect',
  [string]$Environment = 'production'
)

$ErrorActionPreference = 'Continue'
$prefix = "$Project-$Environment"

Write-Host "Caller:"
aws sts get-caller-identity --output table

function Try-Aws {
  param([string]$Label, [scriptblock]$Block)
  Write-Host "`n=== $Label ==="
  try {
    & $Block
  } catch {
    Write-Host "DENIED or ERROR: $($_.Exception.Message)"
  }
}

Try-Aws 'ECS clusters' {
  aws ecs list-clusters --region $Region --query "clusterArns[?contains(@,``$prefix``)]" --output text
}
Try-Aws 'ECS services' {
  $c = aws ecs list-clusters --region $Region --query "clusterArns[?contains(@,``$prefix``)]" --output text
  if ($c) {
    aws ecs list-services --region $Region --cluster $c --output text
    aws ecs describe-services --region $Region --cluster $c --services "$Project-$Environment-service" --query "services[0].{name:serviceName,taskDef:taskDefinition,status:status}" --output table 2>$null
  }
}
Try-Aws 'ALB' {
  aws elbv2 describe-load-balancers --region $Region --query "LoadBalancers[?contains(LoadBalancerName,``$Project``)].{Name:LoadBalancerName,Arn:LoadBalancerArn,DNS:DNSName}" --output table
}
Try-Aws 'Log groups' {
  aws logs describe-log-groups --region $Region --log-group-name-prefix "/ecs/$Project" --query "logGroups[].logGroupName" --output text
}
Try-Aws 'Secrets names' {
  aws secretsmanager list-secrets --region $Region --query "SecretList[?contains(Name,``$Project``)].Name" --output text
}
Try-Aws 'IAM execution role' {
  aws iam get-role --role-name "$prefix-ecs-execution-role" --query "Role.Arn" --output text
}
Try-Aws 'WAF' {
  aws wafv2 list-web-acls --scope REGIONAL --region $Region --query "WebACLs[?contains(Name,``$Project``)].{Name:Name,Arn:ARN}" --output table
}
Try-Aws 'RDS doctornect-prod SG' {
  aws rds describe-db-instances --region $Region --db-instance-identifier doctornect-prod --query "DBInstances[0].VpcSecurityGroups[0].VpcSecurityGroupId" --output text
}
Try-Aws 'ACM api.doctornect.com ISSUED' {
  aws acm list-certificates --region $Region --certificate-statuses ISSUED --query "CertificateSummaryList[?contains(DomainName,``doctornect``)].{Domain:DomainName,Arn:CertificateArn}" --output table
}
Try-Aws 'ECR gateway repo' {
  aws ecr describe-repositories --region $Region --repository-names "$Project-auth-gateway" --query "repositories[0].repositoryUri" --output text 2>$null
  aws ecr describe-images --repository-name "$Project-auth-gateway" --region $Region --query "sort_by(imageDetails,&imagePushedAt)[-1].imageTags" --output text 2>$null
}