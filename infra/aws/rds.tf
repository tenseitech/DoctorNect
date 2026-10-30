# AWS RDS Parameter Group for DoctorNect PostgreSQL 15+
# Enables native pg_cron background worker and performance monitoring.

resource "aws_db_parameter_group" "doctornect_pg15" {
  name        = "${var.project_name}-${var.environment}-pg15-cron"
  family      = "postgres15"
  description = "Custom RDS parameter group enabling pg_cron and pg_stat_statements"

  # 1. Mandatory shared preload libraries (requires RDS reboot)
  parameter {
    name         = "shared_preload_libraries"
    value        = "pg_stat_statements,pg_cron"
    apply_method = "pending-reboot"
  }

  # 2. Database where pg_cron extension and metadata tables are hosted
  parameter {
    name         = "cron.database_name"
    value        = var.rds_db_name == "postgres" ? "postgres" : var.rds_db_name
    apply_method = "pending-reboot"
  }

  # 3. Maximum concurrent worker jobs (default 8)
  parameter {
    name         = "cron.max_running_jobs"
    value        = "8"
    apply_method = "immediate"
  }

  # 4. Standard timezone
  parameter {
    name         = "cron.timezone"
    value        = "UTC"
    apply_method = "immediate"
  }

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

