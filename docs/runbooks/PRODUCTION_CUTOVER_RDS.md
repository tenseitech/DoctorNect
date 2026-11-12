# DoctorNect Production Cutover Runbook: Amazon RDS & Option A Access Layer

**Document:** `docs/runbooks/PRODUCTION_CUTOVER_RDS.md`  
**Target Environment:** AWS Amazon RDS PostgreSQL (Production) + AWS ECS Fargate Option A Access Layer  
**Staging Environment:** Supabase `staging-project-ref` (Holds test data only, remains intact)

---

## 1. Prerequisites & Gating Criteria
Before executing cutover, confirm all preceding gates are green:
- [x] Phase 2 Backup verified (Write Gate unlocked).
- [x] Phase 3.6 Least-privilege migration applied and verified on Staging.
- [x] Phase 5 Rehearsal migration on `doctornect_rehearsal` passes with 0 FAIL / 0 ERROR.
- [x] Schema parity (`node scripts/db/schema_diff.js --target=rehearsal`) confirms zero unexplained differences.
- [x] Option A Auth Gateway tests (`npm test` in `services/api-gateway/`) pass 100%.

---

## 2. Ordered Cutover Execution Steps

### Step 1: AWS Infrastructure Deployment
1. Navigate to `infra/aws/`.
2. Populate `terraform.tfvars` with your VPC ID, Subnet IDs, and ACM Certificate ARN.
3. Apply Terraform configuration:
   ```bash
   terraform init
   terraform apply
   ```
4. Record outputs: `alb_dns_name`, `secrets_manager_*`.

### Step 2: Build & Push Gateway Docker Image
1. Authenticate Docker with Amazon ECR:
   ```bash
   aws ecr get-login-password --region ap-south-1 | docker login --username AWS --password-stdin <AWS_ACCOUNT_ID>.dkr.ecr.ap-south-1.amazonaws.com
   ```
2. Build and push image:
   ```bash
   docker build -t doctornect-auth-gateway:latest services/api-gateway/
   docker tag doctornect-auth-gateway:latest <AWS_ACCOUNT_ID>.dkr.ecr.ap-south-1.amazonaws.com/doctornect-auth-gateway:latest
   docker push <AWS_ACCOUNT_ID>.dkr.ecr.ap-south-1.amazonaws.com/doctornect-auth-gateway:latest
   ```

### Step 3: Populate Secrets Manager
Populate the secrets generated in Step 1:
- `rds_credentials`: Connection string for `authenticator` role on RDS.
- `postgrest_jwt_secret`: Shared HS256 secret (minimum 32 characters).
- `gateway_service_key`: Random 64-character token used by Cloud Functions.

### Step 4: Bootstrap & Migrate Production RDS Database
1. **Pre-Flight Inspection: Verify Actual RDS Engine Version & Parameter Group**:
   Run AWS CLI check to confirm the RDS instance identifier (`var.rds_instance_identifier`), engine version (PostgreSQL 17+), and parameter group status:
   ```bash
   aws rds describe-db-instances \
     --db-instance-identifier ${var.rds_instance_identifier} \
     --query "DBInstances[0].{Identifier:DBInstanceIdentifier,Engine:Engine,EngineVersion:EngineVersion,ParameterGroup:DBParameterGroups[0].DBParameterGroupName,Status:DBInstanceStatus}" \
     --output table
   ```
   *Verification criteria:*
   - `Engine`: `postgres`
   - `EngineVersion`: `17.*` (or major version >= 15)
   - `Status`: `available`

2. **Apply RDS Parameter Group for `pg_cron`**:
   Ensure the RDS PostgreSQL instance is associated with `aws_db_parameter_group.doctornect_pg17` (`doctornect-production-pg17-cron` configuring `shared_preload_libraries = "pg_stat_statements,pg_cron"` and `cron.database_name = "postgres"`).
   ```bash
   aws rds modify-db-instance \
     --db-instance-identifier ${var.rds_instance_identifier} \
     --db-parameter-group-name doctornect-production-pg17-cron \
     --apply-immediately
   ```
3. **Reboot RDS Instance**:
   `shared_preload_libraries` changes require an explicit database restart to load background worker processes.
   ```bash
   aws rds reboot-db-instance \
     --db-instance-identifier ${var.rds_instance_identifier}
   ```
   Wait for the instance to transition back to the `available` state before proceeding.
4. **Verify pg_cron Extension Availability**:
   Connect as administrative user (`postgres` or `rds_superuser`) and confirm extension availability:
   ```sql
   SELECT name, default_version, installed_version FROM pg_available_extensions WHERE name = 'pg_cron';
   ```
5. **Run preflight guard** to confirm RDS instance is empty of application tables:
   ```bash
   node scripts/db/phase1_rds_preflight.js
   ```
6. **Run database migration pipeline**:
   ```bash
   node scripts/db/migrate.js --target=production --confirm=<YOUR_RDS_HOST>
   ```
7. **Seed ONLY approved minimal system config and bootstrap first admin** (ZERO user/domain data):
   > [!IMPORTANT]
   > Production starts with exactly ZERO application data: no mock or test users, patients, doctors, appointments, prescriptions, or orders.
   > The only seeded records are operational `system_config` rows (`patient_module_status`, `promoted_ads`) and the initial super-admin UID in `private.admin_users`.
   > The admin UID must be passed via CLI argument and NEVER committed to disk or repository.

   First perform a dry-run (default):
   ```bash
   node scripts/db/seed_production_minimum.js --target=production --admin-uid=<FIRST_SUPER_ADMIN_FIREBASE_UID>
   ```

   Once verified, execute live write:
   ```bash
   node scripts/db/seed_production_minimum.js --target=production --confirm=<YOUR_RDS_HOST> --admin-uid=<FIRST_SUPER_ADMIN_FIREBASE_UID> --execute
   ```
8. **Verify schema parity against staging**:
   ```bash
   node scripts/db/schema_diff.js --target=production
   ```

### Step 5: Pre-Launch Production RDS Snapshot
Capture an immutable snapshot of the clean, zero-user production database:
```bash
aws rds create-db-snapshot \
  --db-instance-identifier ${var.rds_instance_identifier} \
  --db-snapshot-identifier doctornect-prod-clean-baseline-$(date +%Y%m%d)
```

### Step 6: Deploy Cloud Functions to Production
Update Cloud Functions environment to production:
```bash
firebase functions:secrets:set PROD_GATEWAY_URL="https://api.doctornect.com"
firebase functions:secrets:set PROD_GATEWAY_SERVICE_KEY="<YOUR_GATEWAY_SERVICE_KEY>"
firebase functions:config:set app.env="production"
firebase deploy --only functions
```

### Step 7: Build Production Mobile App Artifacts
Build the production Android App Bundle (AAB):
```powershell
.\frontend\scripts\release_build.ps1 -Target prod
```
*Note: The script verifies `PROD_GATEWAY_URL` is set and fails fast if any staging reference or secret leak is detected.*

### Step 8: Execute Production Smoke Verification
Run the automated end-to-end smoke verification script:
```bash
node scripts/verify/prod_smoke.js
```
Expected output:
- `[PASS]` Health check returns HTTP 200 `{ status: "healthy" }`.
- `[PASS]` Anonymous directory read succeeds.
- `[PASS]` Authenticated test flow succeeds.
- `[PASS]` ZERO RESIDUE PROVEN: Test user record removed; row counts unchanged.

---

## 3. Rollback Procedure
If any fatal failure occurs during cutover prior to public DNS transition:
1. **Database:** Since no real user data exists yet on RDS, production database can be wiped or recreated from the clean snapshot.
2. **Staging:** Supabase project `staging-project-ref` remains completely intact and unaffected.
3. **App & Functions:** Revert `APP_ENV` to `staging` in Cloud Functions and rebuild app pointing to Supabase.
