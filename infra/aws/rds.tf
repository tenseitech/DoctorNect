# AWS RDS Parameter Group for DoctorNect PostgreSQL 18+
# Enables native pg_cron background worker and performance monitoring.
#
# Attachment to Existing RDS Instance:
# Option A (CLI / Manual Cutover):
#   1. Associate parameter group:
#      aws rds modify-db-instance \
#        --db-instance-identifier ${var.rds_instance_identifier} \
#        --db-parameter-group-name ${aws_db_parameter_group.doctornect_pg18.name} \
#        --apply-immediately
#   2. Reboot instance to load shared_preload_libraries (pending-reboot):
#      aws rds reboot-db-instance \
#        --db-instance-identifier ${var.rds_instance_identifier}
#
# Option B (Terraform-managed DB Instance):
#   Set `parameter_group_name = aws_db_parameter_group.doctornect_pg18.name` on the `aws_db_instance` resource.

resource "aws_db_parameter_group" "doctornect_pg18" {
  name        = "${var.project_name}-${var.environment}-pg18-cron"
  family      = "postgres18"
  description = "Custom RDS parameter group enabling pg_cron and pg_stat_statements for PostgreSQL 18"

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

  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "password_encryption"
    value        = "scram-sha-256"
    apply_method = "pending-reboot"
  }

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# Optional Data Source: Queries existing RDS instance to verify engine version and parameter group family.
data "aws_db_instance" "selected" {
  count                  = var.rds_instance_identifier != "" ? 1 : 0
  db_instance_identifier = var.rds_instance_identifier
}
