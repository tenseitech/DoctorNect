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

resource "aws_secretsmanager_secret" "demo_routing" {
  name        = "${var.project_name}/${var.environment}/demo-routing"
  description = "Demo UID allowlist + Supabase PostgREST upstream for auth-gateway"
}

# Firebase Admin service-account key for the gateway's token revocation check (ECS has no Google
# credentials). JSON key: firebase_service_account_json. Use a dedicated service account with only
# the "Firebase Authentication Viewer" role (docs/GATEWAY_DEPLOY.md).
resource "aws_secretsmanager_secret" "gateway_firebase_admin" {
  name                    = "${var.project_name}/${var.environment}/gateway-firebase-admin"
  description             = "Firebase Admin service-account JSON (Firebase Authentication Viewer only) for auth-gateway"
  recovery_window_in_days = 7

  tags = {
    Name = "${var.project_name}-${var.environment}-gateway-firebase-admin"
  }
}

# JSON keys: service_key (same value as the Firebase secret PROD_GATEWAY_SERVICE_KEY, 48 random
# bytes base64) and anon_key (random public identifier, not the default placeholder).
resource "aws_secretsmanager_secret" "gateway_service_key" {
  name_prefix             = "${var.project_name}/${var.environment}/gateway_service_key_"
  description             = "Service role key for internal Cloud Functions to Gateway"
  recovery_window_in_days = 7

  tags = {
    Name = "${var.project_name}-${var.environment}-service-key"
  }
}
