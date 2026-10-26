# Amazon RDS PostgreSQL Production Hardening & Verification Checklist

**Document:** `RDS_PRODUCTION_CHECKLIST.md`  
**Purpose:** Pre-launch security and resilience audit for DoctorNect's production database on AWS RDS.  
**Rule:** Every check specifies a non-destructive, read-only AWS CLI command and the exact expected value.

---

## Hardening Verification Matrix

| # | Security / Reliability Control | Read-Only AWS CLI Audit Command | Expected Compliant Value | Compliant? |
|---|---|---|---|---|
| **1** | **Storage Encryption (KMS)** | `aws rds describe-db-instances --db-instance-identifier <DB_ID> --query "DBInstances[0].StorageEncrypted"` | `true` (encrypted with AWS KMS customer-managed or default key) | [ ] |
| **2** | **Force SSL / TLS Only** | `aws rds describe-db-parameters --db-parameter-group-name <PARAM_GROUP> --query "Parameters[?ParameterName=='rds.force_ssl'].ParameterValue" --output text` | `1` (unencrypted connections rejected) | [ ] |
| **3** | **Network Isolation (No Public IP)** | `aws rds describe-db-instances --db-instance-identifier <DB_ID> --query "DBInstances[0].PubliclyAccessible"` | `false` (in private subnets; reachable only from ECS Tasks and Bastion) | [ ] |
| **4** | **Security Group Scoping** | `aws ec2 describe-security-groups --group-ids <RDS_SG_ID> --query "SecurityGroups[0].IpPermissions"` | Inbound 5432 permitted ONLY from ECS Security Group or explicit Admin IP. **Zero `0.0.0.0/0` entries**. | [ ] |
| **5** | **Automated Backups & PITR** | `aws rds describe-db-instances --db-instance-identifier <DB_ID> --query "DBInstances[0].BackupRetentionPeriod"` | `>= 14` days (enables Point-in-Time Recovery) | [ ] |
| **6** | **Deletion Protection** | `aws rds describe-db-instances --db-instance-identifier <DB_ID> --query "DBInstances[0].DeletionProtection"` | `true` (guards against accidental termination) | [ ] |
| **7** | **Multi-AZ Availability** | `aws rds describe-db-instances --db-instance-identifier <DB_ID> --query "DBInstances[0].MultiAZ"` | `true` (automatic failover to standby replica in second AZ) | [ ] |
| **8** | **Auto Minor Version Upgrade** | `aws rds describe-db-instances --db-instance-identifier <DB_ID> --query "DBInstances[0].AutoMinorVersionUpgrade"` | `true` (automatic patching of PostgreSQL CVEs) | [ ] |
| **9** | **Performance Insights** | `aws rds describe-db-instances --db-instance-identifier <DB_ID> --query "DBInstances[0].PerformanceInsightsEnabled"` | `true` (enables query bottleneck diagnostics) | [ ] |
| **10** | **Enhanced Monitoring** | `aws rds describe-db-instances --db-instance-identifier <DB_ID> --query "DBInstances[0].MonitoringInterval"` | `60` (or `30` seconds granularity) | [ ] |
| **11** | **CloudWatch Log Export** | `aws rds describe-db-instances --db-instance-identifier <DB_ID> --query "DBInstances[0].EnabledCloudwatchLogsExports"` | `["postgresql", "upgrade"]` (audit logs streamed to CloudWatch) | [ ] |
| **12** | **pgaudit Extension** | `aws rds describe-db-parameters --db-parameter-group-name <PARAM_GROUP> --query "Parameters[?ParameterName=='shared_preload_libraries'].ParameterValue" --output text` | Contains `pgaudit` (for HIPAA/DPDP medical record access auditing) | [ ] |
| **13** | **Max Connections vs Pool** | `aws rds describe-db-parameters --db-parameter-group-name <PARAM_GROUP> --query "Parameters[?ParameterName=='max_connections'].ParameterValue" --output text` | Sized comfortably above PostgREST pool size (e.g. `200` vs `10` per task) | [ ] |
| **14** | **Master Password in Secrets Manager** | `aws secretsmanager describe-secret --secret-id <SECRET_ARN> --query "RotationEnabled"` | `true` (managed rotation enabled) | [ ] |
| **15** | **Runtime Least-Privilege Roles** | Run in SQL: `SELECT rolname, rolcanlogin, rolsuper FROM pg_roles WHERE rolname IN ('anon', 'authenticated', 'service_role', 'authenticator', 'app_migrator');` | Only `authenticator` and `app_migrator` can login; NONE have superuser rights. | [ ] |

---

## Audit Execution Script

You can run the entire audit in one command once your AWS CLI credentials are configured:

```bash
#!/usr/bin/env bash
DB_ID="<your-rds-db-instance-identifier>"

echo "--- 1. Storage Encryption ---"
aws rds describe-db-instances --db-instance-identifier "$DB_ID" --query "DBInstances[0].StorageEncrypted"

echo "--- 2. Public Accessibility ---"
aws rds describe-db-instances --db-instance-identifier "$DB_ID" --query "DBInstances[0].PubliclyAccessible"

echo "--- 3. Backup Retention ---"
aws rds describe-db-instances --db-instance-identifier "$DB_ID" --query "DBInstances[0].BackupRetentionPeriod"

echo "--- 4. Deletion Protection ---"
aws rds describe-db-instances --db-instance-identifier "$DB_ID" --query "DBInstances[0].DeletionProtection"

echo "--- 5. Multi-AZ ---"
aws rds describe-db-instances --db-instance-identifier "$DB_ID" --query "DBInstances[0].MultiAZ"

echo "--- 6. CloudWatch Logs ---"
aws rds describe-db-instances --db-instance-identifier "$DB_ID" --query "DBInstances[0].EnabledCloudwatchLogsExports"
```
