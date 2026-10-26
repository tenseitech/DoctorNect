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
