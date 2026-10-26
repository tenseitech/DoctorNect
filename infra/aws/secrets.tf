# AWS Secrets Manager: Production Credential References (Zero plaintext secrets in git)
resource "aws_secretsmanager_secret" "database_credentials" {
  name_prefix             = "${var.project_name}/${var.environment}/rds_credentials_"
  description             = "PostgreSQL authenticator credentials for PostgREST"
  recovery_window_in_days = 7

  tags = {
    Name = "${var.project_name}-${var.environment}-db-credentials"
  }
}

resource "aws_secretsmanager_secret" "postgrest_jwt_secret" {
  name_prefix             = "${var.project_name}/${var.environment}/postgrest_jwt_secret_"
  description             = "Shared HS256 secret between Auth Gateway and PostgREST (min 32 chars)"
  recovery_window_in_days = 7

  tags = {
    Name = "${var.project_name}-${var.environment}-jwt-secret"
  }
}

resource "aws_secretsmanager_secret" "gateway_service_key" {
  name_prefix             = "${var.project_name}/${var.environment}/gateway_service_key_"
  description             = "Service role key for internal Cloud Functions to Gateway"
  recovery_window_in_days = 7

  tags = {
    Name = "${var.project_name}-${var.environment}-service-key"
  }
}
