output "alb_dns_name" {
  value       = aws_lb.api.dns_name
  description = "Application Load Balancer DNS Name (point your CNAME record to this)"
}

output "alb_zone_id" {
  value       = aws_lb.api.zone_id
  description = "Application Load Balancer Route53 Canonical Zone ID"
}

output "ecs_service_name" {
  value       = aws_ecs_service.main.name
  description = "ECS Fargate Service Name"
}

output "ecs_cluster_name" {
  value       = aws_ecs_cluster.main.name
  description = "ECS Cluster Name"
}

output "secrets_manager_db_credentials_arn" {
  value       = aws_secretsmanager_secret.database_credentials.arn
  description = "Secrets Manager Secret ARN for PostgREST Database Credentials"
}

output "secrets_manager_jwt_secret_arn" {
  value       = aws_secretsmanager_secret.postgrest_jwt_secret.arn
  description = "Secrets Manager Secret ARN for PostgREST JWT Secret"
}

output "secrets_manager_service_key_arn" {
  value       = aws_secretsmanager_secret.gateway_service_key.arn
  description = "Secrets Manager Secret ARN for Gateway Service Role Key"
}

output "rds_parameter_group_id" {
  value       = aws_db_parameter_group.doctornect_pg18.id
  description = "RDS DB Parameter Group ID configuring pg_cron"
}

output "rds_parameter_group_name" {
  value       = aws_db_parameter_group.doctornect_pg18.name
  description = "RDS DB Parameter Group Name configuring pg_cron"
}


output "ecr_auth_gateway_url" {
  value       = aws_ecr_repository.auth_gateway.repository_url
  description = "Push the auth-gateway image here"
}

output "ecr_postgrest_url" {
  value       = aws_ecr_repository.postgrest.repository_url
  description = "Push the PostgREST (RDS CA) image here"
}

output "secrets_manager_gateway_firebase_admin_arn" {
  value       = aws_secretsmanager_secret.gateway_firebase_admin.arn
  description = "Secrets Manager Secret ARN for the gateway Firebase Admin service-account JSON"
}

output "s3_production_bucket" {
  value       = aws_s3_bucket.vault_production.bucket
  description = "Put this name in .env as S3_BUCKET_PRODUCTION"
}

output "functions_s3_production_iam_user" {
  value       = aws_iam_user.functions_s3_production.name
  description = "Create an access key for this user in the IAM console; store it only in Firebase Secret Manager"
}

output "functions_s3_staging_policy_arn" {
  value       = aws_iam_policy.functions_s3_vault["staging"].arn
  description = "Attach to the IAM user used by the staging Functions"
}
