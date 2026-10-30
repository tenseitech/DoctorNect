# DoctorNect Scheduled Maintenance & Background Jobs (CRON PLAN)

**Status:** APPROVED FOR STAGING & PRODUCTION RUNTIME  
**Document Version:** 1.0.0  
**Updated:** 2026-10-30  
**Target Environments:** AWS RDS PostgreSQL 15+, Supabase Staging, Local Scratch Replay

---

## 1. Overview & Inventory of Cron Jobs

DoctorNect uses automated cron schedules for campaign lifecycle management, ephemeral table pruning, rate limit expiration, and emergency ambulance dispatch timeouts.

### Real Scheduled Jobs in Migration Files

| Job Name | Schedule (UTC) | Source Migration | SQL Invocation | Type | Guard Status |
|---|---|---|---|---|---|
| `expire-promoted-ads` | `0 * * * *` (Hourly) | `20260923000003_doctornect_cron.sql:11` | `UPDATE promoted_ads SET status = 'expired' ...` | Direct SQL | **Unguarded** |
| `cleanup-expired-otp-challenges` | `0 3 * * *` (Daily 03:00) | `20260923000003_doctornect_cron.sql:24` | `DELETE FROM otp_challenges ...; DELETE FROM otp_verification_sessions ...;` | Direct SQL | **Unguarded** |
| `cleanup-expired-rate-limits` | `15 3 * * *` (Daily 03:15) | `20260923000003_doctornect_cron.sql:37` | `DELETE FROM abuse_rate_limits ...;` | Direct SQL | **Unguarded** |
| `expire-stale-ambulance-broadcasts` | `*/5 * * * *` (Every 5 min) | `20261021000002_phase_d_...sql:1265` | `SELECT public.expire_stale_ambulance_broadcasts();` | Function Call | **Guarded** (`IF EXISTS pg_extension`) |

---

## 2. Reconciliation with Round 3 & Round 4 Audits

### FUNCTION vs. PROCEDURE Clarification
- `public.expire_stale_ambulance_broadcasts()` is defined as:
  ```sql
  CREATE OR REPLACE FUNCTION public.expire_stale_ambulance_broadcasts()
  RETURNS INTEGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = ''
  ```
- **Crucial Distinction:** Because it returns `INTEGER` and is declared as `FUNCTION`, PostgreSQL strictly requires calling it via:
  ```sql
  SELECT public.expire_stale_ambulance_broadcasts();
  ```
- Executing `CALL public.expire_stale_ambulance_broadcasts();` throws `42809: expire_stale_ambulance_broadcasts() is a function`. The cron job in `20261021000002` correctly uses `SELECT`.

### Unguarded Extension Risk in Early Migrations
- Migration `20260923000003_doctornect_cron.sql` directly runs:
  ```sql
  CREATE EXTENSION IF NOT EXISTS pg_cron;
  SELECT cron.schedule(...);
  ```
- On standard cloud providers (like Supabase), `pg_cron` is preloaded by default in database `postgres`.
- On bare AWS RDS PostgreSQL instances, `CREATE EXTENSION pg_cron` **fails** unless `pg_cron` has been added to `shared_preload_libraries` in the RDS Parameter Group and the instance rebooted.

---

## 3. Production Deployment Option A: AWS RDS `pg_cron` via Terraform

To enable native `pg_cron` on AWS RDS PostgreSQL 15+, the Terraform RDS parameter group must configure the background worker libraries.

### Terraform Configuration (`infra/terraform/rds.tf`)

```hcl
resource "aws_db_parameter_group" "doctornect_pg15" {
  name   = "doctornect-postgres15-pg-cron"
  family = "postgres15"

  # 1. Mandatory shared preload libraries (requires RDS reboot)
  parameter {
    name         = "shared_preload_libraries"
    value        = "pg_stat_statements,pg_cron"
    apply_method = "pending-reboot"
  }

  # 2. Database where pg_cron extension and job tables are hosted
  parameter {
    name         = "cron.database_name"
    value        = "postgres"
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
}
```

### Multi-Database Scheduling (`cron.schedule_in_database`)
If the application runs in a dedicated database (e.g., `doctornect_prod`) rather than `postgres`:
`pg_cron` metadata stays in `postgres`, but jobs are executed against the target DB:
```sql
SELECT cron.schedule_in_database(
    'expire-stale-ambulance-broadcasts',
    '*/5 * * * *',
    'SELECT public.expire_stale_ambulance_broadcasts();',
    'doctornect_prod'
);
```

---

## 4. Production Deployment Option B: AWS EventBridge Alternative (Recommended for High Availability)

Decoupling scheduled jobs from the database engine eliminates `shared_preload_libraries` reboot requirements, avoids running background workers in the database container, and provides native CloudWatch alerting.

### Architecture

```
Amazon EventBridge (Rules)
       │
       ▼
AWS Step Functions / Lambda Worker
       │
       ▼ (HTTPS with service_role PostgREST token)
API Gateway / PostgREST Internal VPC Endpoint
       │
       ▼
PostgreSQL Stored Functions
```

### EventBridge Rule Matrix

| Rule Name | Cron Expression | Target Endpoint / Handler | Retry Policy |
|---|---|---|---|
| `eb-doctornect-hourly-ads` | `cron(0 * * * ? *)` | `POST /internal/cron/expire-ads` | 3 retries, DLQ |
| `eb-doctornect-daily-otp` | `cron(0 3 * * ? *)` | `POST /internal/cron/cleanup-otp` | 3 retries, DLQ |
| `eb-doctornect-daily-ratelimit` | `cron(15 3 * * ? *)` | `POST /internal/cron/cleanup-rate-limits` | 3 retries, DLQ |
| `eb-doctornect-5min-ambulance` | `cron(0/5 * * * ? *)` | `POST /internal/cron/expire-ambulance` | 1 retry, DLQ |

---

## 5. Local & CI Scratch Replay Strategy

For testing environments lacking `pg_cron` (such as local Docker Postgres or scratch replay databases), `scripts/db/rds_scratch_replay.js` injects a **TEST-ONLY cron recorder schema**:

```sql
-- TEST-ONLY CRON RECORDER (LOCAL SCRATCH REPLAY ONLY — NEVER IN RDS BOOTSTRAP)
CREATE SCHEMA IF NOT EXISTS cron;
CREATE TABLE IF NOT EXISTS cron.job (
    jobid serial PRIMARY KEY,
    schedule text NOT NULL,
    command text NOT NULL,
    jobname text UNIQUE
);
CREATE OR REPLACE FUNCTION cron.schedule(job_name text, schedule text, command text)
RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE v_id bigint;
BEGIN
    INSERT INTO cron.job (jobname, schedule, command)
    VALUES (job_name, schedule, command)
    ON CONFLICT (jobname) DO UPDATE SET schedule = EXCLUDED.schedule, command = EXCLUDED.command
    RETURNING jobid INTO v_id;
    RETURN v_id;
END;
$$;
CREATE OR REPLACE FUNCTION cron.unschedule(job_name text)
RETURNS boolean LANGUAGE plpgsql AS $$
BEGIN
    DELETE FROM cron.job WHERE jobname = job_name;
    RETURN FOUND;
END;
$$;
```

This ensures full migration replay compatibility without external binary dependencies.
