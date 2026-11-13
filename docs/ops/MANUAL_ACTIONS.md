# DoctorNect Production Cutover: Operator Manual Actions

**Tracking File:** `docs/ops/MANUAL_ACTIONS.md`  
**Protocol:** When a step requires operator action (AWS console, credentials, Supabase dashboard, etc.), it is recorded here as a numbered checkbox item with:
- **Why it is needed**
- **Exact steps or commands**
- **Verification command**
- **Which task/phase it unblocks**

---

## Active Manual Action Items

### [ ] Item 1: Install Native PostgreSQL 18 Client Tools (`pg_dump`, `pg_restore`, `psql`)
- **Why:** Production RDS runs **PostgreSQL 18.3** (`PROD_PG_MAJOR=18`, `PROD_PG_VERSION=18.3`). Staging Supabase may differ (report-only). Physical dumps/restores against RDS require client binaries with **major version ≥ 18** (prefer **18.3** match). Bastion: `dnf install postgresql18` on Amazon Linux 2023.
- **Exact Steps (Choose Option A or B):**
  - **Option A (Full Package via winget):**
    Run in an elevated PowerShell terminal or user terminal:
    ```powershell
    winget install --id PostgreSQL.PostgreSQL.18 --silent --accept-package-agreements --accept-source-agreements
    ```
  - **Option B (Command Line Tools Only - Lightweight):**
    Download the official EDB Windows installer for **PostgreSQL 18** from `https://www.enterprisedb.com/downloads/postgres-postgresql-downloads` and during component selection, uncheck PostgreSQL Server, pgAdmin 4, and Stack Builder; select **only "Command Line Tools"**.
  *(Note: If installed to `C:\Program Files\PostgreSQL\18\bin`, ensure this directory is in your `PATH` or accessible).*
- **Verification Command:**
  ```powershell
  & "C:\Program Files\PostgreSQL\18\bin\pg_dump.exe" --version
  ```
  *(Or if added to PATH: `pg_dump --version`)*  
  *Expected output:* `pg_dump (PostgreSQL) 18.x` (major version **>= 18**).
- **Unblocks:** Phase 2.1 & 2.2 (`pg_dump` physical backups) and Phase 2 restore verification (which opens the Write Gate for database writes).

---

### [ ] Item 2: Connect Existing Amazon RDS PostgreSQL Instance & Provide Credentials
- **Why:** The production RDS PostgreSQL instance is already created by you. To run read-only preflight (`phase1_rds_preflight.js`), test TLS connectivity, and execute rehearsal migrations, credentials and network access must be configured.
- **Exact Steps:**
  1. Ensure the RDS instance is network-accessible from this development machine:
     - Check Security Group: Inbound TCP port 5432 permitted from your current public IP (never 0.0.0.0/0).
     - Check Public Accessibility: Set to `Yes` (or accessible via your configured VPN/Bastion).
  2. Populate `.env.migration` with the instance details:
     ```env
     PROD_RDS_HOST=<your-existing-rds-endpoint.rds.amazonaws.com>
     PROD_RDS_PORT=5432
     PROD_RDS_DB=<your-database-name>
     PROD_RDS_USER=<your-master-or-admin-user>
     PROD_RDS_PASSWORD=<your-secure-password>
     PROD_RDS_SSL_ROOT_CERT=infra/aws/global-bundle.pem
     ```
- **Verification Command:**
  ```powershell
  node scripts/db/phase1_rds_preflight.js
  ```
  *Expected output:* Reports actual engine version, TLS/SSL connection status, `rds_superuser` membership, `show rds.force_ssl`, and `show max_connections`.
- **Unblocks:** Phase 1.3 (RDS Preflight), Phase 2 restore verification to rehearsal DB, Phase 5 (RDS Bootstrap, Rehearsal, and Production Application).

---

### [ ] Item 3: Install Terraform (for Infrastructure as Code Validation)
- **Why:** To run `terraform init -backend=false` and `terraform validate` against `infra/aws/`.
- **Exact Command:**
  Run in terminal:
  ```powershell
  winget install --id HashiCorp.Terraform --silent --accept-package-agreements --accept-source-agreements
  ```
- **Verification Command:**
  ```powershell
  terraform -version
  ```
  *Expected output:* `Terraform v1.x.x`
- **Unblocks:** Phase 6 Terraform automated linting and validation.

---

### [ ] Item 4: Review and Complete Supabase Dashboard Configuration Checklist
- **Why:** Supabase dashboard settings (Third-Party Auth, JWT expiration, database webhooks, Realtime publications, pooler settings) do not exist in database migrations and must be manually tracked for parity on RDS/PostgREST.
- **Exact Steps:**
  Open and complete the blank entries in:
  `backups/supabase_2026-10-26T07-38-59-229Z/dashboard_config_checklist.md`
- **Verification Command:**
  Verify file has no empty `[ ]` unreviewed items.
- **Unblocks:** Phase 5 & Phase 6 configuration fidelity.

---

### [ ] Item 5: Pre-Launch RDS Production Snapshot (Before Real User Data)
- **Why:** Ensures a clean, zero-data snapshot exists before any real patient or doctor signs up.
- **Exact Command:**
  ```bash
  aws rds create-db-snapshot --db-instance-identifier <your-rds-db-instance-id> --db-snapshot-identifier doctornect-prelaunch-clean-$(date +%Y%m%d%H%M%S)
  ```
- **Verification Command:**
  ```bash
  aws rds describe-db-snapshots --db-instance-identifier <your-rds-db-instance-id> --query "DBSnapshots[*].[DBSnapshotIdentifier,Status]"
  ```
- **Unblocks:** Phase 5.6 Final Production Sign-off.

---

### [ ] Item 6: Build and Push Docker Images to Amazon ECR (When Ready for Cloud Deploy)
- **Why:** Local machine has no Docker daemon running. The Node.js Auth Gateway and PostgREST containers for Option A will run on AWS ECS Fargate.
- **Exact Steps:**
  When deploying infrastructure in `infra/aws/`:
  1. Build Gateway image using `services/api-gateway/Dockerfile`.
  2. Push to ECR repository `doctornect-auth-gateway`.
- **Verification Command:**
  ```bash
  aws ecr describe-images --repository-name doctornect-auth-gateway
  ```
- **Unblocks:** Phase 6 Cloud Deployment.
