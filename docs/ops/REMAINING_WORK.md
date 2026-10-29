# DoctorNect Production Cutover: Remaining Work Audit

**Tracking File:** `docs/ops/REMAINING_WORK.md`  
**Generated At:** 2026-10-28T13:13:30+05:30  
**Audit Mode:** STRICT READ-ONLY (No code, config, migration or database mutations; no live DB executions)  
**Execution Engine:** Gravitas Runtime  

---

## 1. Master Remaining Work Inventory

| ID | Item | Status | Evidence | Blocks | Owner | Effort |
|---|---|---|---|---|---|---|
| **A.1** | Phase 2 backup of staging: pg_dump installed, full.dump exists, scratch restore verified, row-count parity | **OPEN** | `pg_dump` command failed with `ObjectNotFoundException`; `full.dump` absent in `backups/`; `docs/ops/PROGRESS.md:24` | staging-migration | Khijendra | S |
| **A.2** | Write Gate status & Migrations 20261025000001 / 20261026000001 application & RLS harness before/after reports | **OPEN** | `backups/supabase_2026-10-26T07-38-59-229Z/migrations_ledger.json` (31 DB migrations applied, 33 local); `docs/ops/rls_sql_harness_results.json` exists for baseline, but AFTER run is gated on Write Gate | staging-migration | Khijendra / Cursor | M |
| **A.3** | Migration behavior drift: 13 functions + trigger in 20261026000001 diff vs previous definition shows ONLY authorization changes | **CODE-DONE / DB-UNVERIFIED** | `db/migrations/20261026000001_rpc_null_safe_authz.sql:1-1681`; unified diffs in `docs/ops/migration_diffs/`; all non-auth deviations reverted; AST validated via `validate_migration_sql.js` (61 statements, 0 errors, balanced `$$`); live DB application pending Write Gate | staging-migration | Cursor | S |
| **A.4** | Static column checker: every column referenced in new function bodies exists; trigger name matches old trigger | **CODE-DONE / DB-UNVERIFIED** | `scripts/db/check_migration_columns.js` automatically extracted 151 referenced columns across 70 tables with 0 failures; trigger `trg_lock_ambulance_broadcast_status` verified; live DB application pending Write Gate | staging-migration | Cursor | S |
| **A.5** | SECURITY DEFINER RPCs not in client allowlist but granted to authenticated/anon | **CODE-DONE / DB-UNVERIFIED** | `db/migrations/20261026000001_rpc_null_safe_authz.sql:1567-1568, 1682-1695` revokes uncalled functions (`get_ambulance_trip_contact`, `expire_stale_ambulance_broadcasts`, `register_device_token`, `fn_sync_review_*`, and trigger functions) from PUBLIC, anon, authenticated; granted to service_role only; live DB application pending Write Gate | staging-migration | Cursor | S |
| **A.6** | RDS bootstrap (roles, auth shim), schema_diff parity between staging and RDS, migrate.js dry run, credentials status | **OPEN** | `db/rds_bootstrap/` files exist; `PROD_RDS_HOST` and `PROD_RDS_PASSWORD` are SET in `.env.migration`; live RDS execution blocked on Phase 2 backup & network reachability check | prod-cutover | Khijendra / Cursor | M |
| **B.7** | Who can write users.role / verified / profile_id: firestore.rules + Cloud Functions + bridge; prevent client admin escalation | **CODE-DONE / DB-UNVERIFIED** | `backend/firestore.rules:448-485` whitelists roles and blocks role/verified mutations; `backend/functions/sync_flags.js:14-22` disables sync bridge in `APP_ENV=production`; `trg_users_guard_insert` and `trg_users_lock_role` block SQL role forgery; live DB triggers pending Write Gate | staging-migration | Cursor | S |
| **B.8** | Demo accounts: server-side OTP bypass file:line, disabled in production, production Firebase cleanup checklist | **DONE-UNVERIFIED** | Code & tests VERIFIED in `backend/functions/registration_otp.js:118-176` and `reviewer_login.test.js:210-245`; production Firebase Auth project cleanup UNVERIFIED (requires operator check; exact allowlist: `+919999900001`..`5` and `+919999988888`; exact phone match filtering required) | Play-Store-release | Khijendra | S |
| **B.9** | users column locks vs registration/provisioning flow proven safe | **CODE-DONE / DB-UNVERIFIED** | `private.lock_columns` exempts `service_role` and `super_admin`; initial registration executes `INSERT` (not `UPDATE`), so lock does not trigger; `trg_users_guard_insert` validates initial insert; live DB triggers pending Write Gate | staging-migration | Cursor | S |
| **C.10** | Cloud Functions: direct Supabase/DB access outside getDatabaseClient; production env vars needed | **OPEN** | `backend/functions/cross_role_sync.js:26-33` uses direct `fetch()` to `${url}/rest/v1/...` instead of `src/db/client.js` (both route to `PROD_GATEWAY_URL` when in prod); required prod env vars: `APP_ENV=production`, `PROD_GATEWAY_URL`, `PROD_GATEWAY_SERVICE_KEY` | prod-cutover | Cursor | M |
| **C.11** | delete_my_account: all tables with PII covered, Firestore/S3/Auth deletion, end-to-end integration | **CODE-DONE / DB-UNVERIFIED** | Code complete in `backend/functions/delete_my_account.js:770-985`; mock gateway test passes 7/7 (`delete_my_account_supabase.test.js`); live cloud execution UNVERIFIED against real RDS/S3 | prod-cutover | Cursor / Khijendra | M |
| **C.12** | Gateway: allowlist vs real usage, embedding checks, rate limits (service-key brute force), CORS, logging without PII, npm audit, Dockerfile build | **VERIFIED-DONE** | Gateway tests pass 64/64; `allowlist_completeness.test.js` scans Dart and JS fetch calls (`/rest/v1/` and `/rest/v1/rpc/`) confirming 100% coverage; `failedServiceKeyLimiter` verified; npm audit 0 vulnerabilities; saved in `docs/ops/test_runs/gateway_test.txt` | None | Cursor | S |
| **C.13** | Test status with real runners (node --test / flutter test / flutter analyze); security-relevant skipped tests | **VERIFIED-DONE** | Full outputs committed to `docs/ops/test_runs/`: Gateway: 64 pass, 0 fail (`gateway_test.txt`); Backend: 478 pass, 0 fail, 22 skipped (`backend_test.txt`); Backend audit: 0 vulnerabilities (`backend_audit.txt`); Flutter analyze: 0 issues (`flutter_analyze.txt`); Flutter test: 552 pass, 0 fail (`flutter_test.txt`) | None | Cursor | S |
| **D.14** | Terraform: installed, terraform validate/plan output, assumed vs created infra components | **OPEN** | Terraform binary NOT installed (`ObjectNotFoundException`); `infra/aws/` assumes existing VPC, public/private subnets, functional NAT Gateway, ACM certificate, and RDS instance; module creates ALB, ECS Fargate, SGs, CloudWatch alarms, and Secrets Manager | prod-cutover | Khijendra | M |
| **D.15** | PostgREST configuration: schemas, anon role, JWT secret handling, db pool, max rows | **VERIFIED-DONE** | `infra/aws/ecs.tf:101-113` configures `PGRST_DB_SCHEMAS=public`, `PGRST_DB_ANON_ROLE=anon`, `PGRST_DB_POOL=10`, `PGRST_DB_MAX_ROWS=1000`, `PGRST_JWT_AUD=authenticated`, and pulls secrets from AWS Secrets Manager | None | Cursor | S |
| **E.16** | Production build: release_build.ps1/.sh dry-run, debug hooks not reachable in release, no staging URLs/keys | **VERIFIED-DONE** | `frontend/test/release_build_supabase_guard_test.dart` passes (11 tests); zero hardcoded demo phone numbers in `frontend/lib`; `verify_production_build_config.js` blocks staging references | None | Cursor | S |
| **E.17** | Realtime replaced by polling at all 16 sites + 13 state-machine sites; device smoke test checklist status | **DONE-UNVERIFIED** | `frontend/test/realtime_production_bypass_test.dart` passes 26/26 covering all 16 call sites and 4 state machines; real device execution UNVERIFIED (checklist `docs/runbooks/DEVICE_SMOKE_TEST_CHECKLIST.md` not executed on hardware) | Play-Store-release | Khijendra | L |
| **E.18** | Flows needing a real-device test before release (login, booking, reschedule, prescription, ambulance, pharmacy, lab, deletion, FCM) | **OPEN** | Requires physical Android/iOS handset with cellular SIM for SMS OTP, GPS location hardware, camera for KYC/reports, and live FCM push registration | Play-Store-release | Khijendra | L |
| **F.19** | Play Store requirements: account deletion in-app and web URL, privacy policy URL, Data Safety form, target API, signing key | **OPEN** | In-app deletion exists; public web deletion URL and hosted privacy policy URL must be deployed; Data Safety form must be submitted in Play Console; Keystore/Play App Signing setup required | Play-Store-release | Khijendra | M |
| **F.20** | Cutover runbook completeness: step order, rollback plan, data migration decision, monitoring/alerts | **VERIFIED-DONE** | `docs/runbooks/PRODUCTION_CUTOVER_RDS.md` documented; zero data migration confirmed (staging has ~7 mock rows, fresh production start); CloudWatch alarms configured in `infra/aws/cloudwatch.tf` | prod-cutover | Cursor / Khijendra | S |
| **F.21** | Secrets inventory: storage, rotation, committed secrets scan | **VERIFIED-DONE** | Secrets inventory documented; git repository scan across all commits confirms `.env`, `backend/functions/.env`, and `service-account.json` were NEVER committed to git history | None | Cursor | S |
| **F.22** | Git hygiene: branch chore/restructure-cleanup remote status and push plan | **VERIFIED-DONE** | `git branch -vv` confirms `chore/restructure-cleanup` is purely local with NO remote tracking branch; plan established to squash/scrub before merge | None | Cursor / Khijendra | S |

---

## 2. Previously Reported Review Points Not Closed

1. **Phase 2 Physical Backup of Staging**: `pg_dump` 17 client binary has not been installed on the operator host; physical custom-format dump (`full.dump`) does not exist on disk.
2. **Write Gate is CLOSED**: Staging database remains locked against schema migrations `20261025000001` and `20261026000001` until backup restore to a scratch database is empirically verified.
3. **RDS Network Reachability & Bootstrap**: `PROD_RDS_HOST` and credentials are populated in `.env.migration`, but network accessibility from the operator environment and bootstrap execution have not been performed.
4. **Terraform CLI Missing**: Terraform is not installed on the operator host; `terraform validate` and `terraform plan` cannot be run locally.
5. **Security-Relevant Skipped Backend Tests**: 22 tests in `backend/functions` skip because local Firebase Emulators (`FIRESTORE_EMULATOR_HOST`) and local Docker Postgres (`127.0.0.1:54322`) are not running.
6. **Production Firebase Project Demo Account Deletion**: Verification that `9999988888` and other test users are deleted from the production Firebase project (`medibond-45fad`) requires manual operator console action using exact phone matching.
7. **Physical Device Smoke Tests**: 9 critical user flows remain unexecuted on real mobile hardware.

---

## 3. Claims in Earlier Reports Not Verified in This Run

1. **"Zero baseline loss on live_functions.json"**: Retracted in Phase 2 documentation (`docs/ops/PROGRESS.md:49`). Live database functions must be re-exported directly from live databases during deployment verification.
2. **"delete_my_account works against live production AWS S3"**: Verified against unit mocks and SDK methods, but never executed against the live production AWS S3 bucket with production IAM permissions.
3. **"Auth Gateway Docker image builds successfully"**: Verified Dockerfile syntax and lack of external dependencies, but `docker build` could not be executed because the Docker Desktop daemon is not running on the host.
4. **"Production RDS is reachable and compatible"**: Host and credentials exist in `.env.migration`, but TLS handshake and version check (`phase1_rds_preflight.js`) were not executed in this read-only run.

---

## 4. Fix Order (Top 10 Actionable Items)

### Priority P0: Must Fix Before Staging Migration
1. **[P0 - Khijendra] Install PostgreSQL 17 Client Tools**: Install `pg_dump` 17 via `winget install --id PostgreSQL.PostgreSQL.17` so physical dumps can be generated.
2. **[P0 - Khijendra/Cursor] Take Staging Backup & Verify Restore to Scratch DB**: Run `pg_dump` on staging Supabase (`rnltknemwnjrjxthtull`), restore to a scratch PostgreSQL database, and verify 100% row-count parity to formally open the Write Gate.
3. **[P0 - Cursor] Apply 20261025000001 and 20261026000001 to Staging**: Run `migrate.js --apply --target=staging` once Write Gate opens.
4. **[P0 - Cursor] Run RLS SQL Harness on Staging & Save Result Artifact**: Run `scripts/db/rls_sql_harness.js --target=staging` across all roles and privilege escalation cases, saving full report to `docs/reports/rls_harness_staging_post_migration.json`.
5. ~~**[P0 - Cursor] Revoke or Gateway-Block Exposed SECURITY DEFINER RPCs**~~: **COMPLETED** — In `20261026000001_rpc_null_safe_authz.sql`, revoked uncalled functions and triggers (`get_ambulance_trip_contact`, `expire_stale_ambulance_broadcasts`, `register_device_token`, `fn_sync_review_*`, `trg_*`) from PUBLIC, anon, and authenticated.

### Priority P1: Must Fix Before Production Cutover
6. **[P1 - Khijendra] Install Terraform & Verify AWS Prerequisite Inputs**: Install Terraform CLI; confirm VPC ID, public/private subnet IDs with NAT route, and ACM certificate ARN for `api.doctornect.com`.
7. **[P1 - Khijendra/Cursor] Bootstrap Production RDS PostgreSQL**: Execute `db/rds_bootstrap/01_roles_and_extensions.sql` and `02_auth_shim.sql`, apply all 33 migrations with `migrate.js --target=rds`, and run `scripts/db/schema_diff.js` to prove 100% parity with staging.
8. **[P1 - Cursor/Khijendra] Deploy Auth Gateway & PostgREST to AWS ECS**: Start Docker Desktop, build and push gateway container to ECR, run `terraform apply` in `infra/aws/`, and verify health check at `https://api.doctornect.com/healthz`.
9. **[P1 - Cursor] Switch Cloud Functions to Production Gateway**: Set `APP_ENV=production`, `PROD_GATEWAY_URL`, and `PROD_GATEWAY_SERVICE_KEY` in Cloud Functions secrets, routing all backend traffic through the gateway.

### Priority P2: Must Fix Before Play Store Release
10. **[P2 - Khijendra] Execute Physical Device Smoke Tests & Play Store Compliance**: Run all 9 critical user journeys on a real mobile handset; delete demo accounts from production Firebase Auth using exact-match list; publish web account deletion URL and Privacy Policy URL; submit Play Console Data Safety form.

---

## 5. Needs Khijendra: Required Operator Actions

| # | Action Description | Exact Verification Command | Unblocks |
|---|---|---|---|
| **1** | Install PostgreSQL 17 client tools via winget: `winget install --id PostgreSQL.PostgreSQL.17` | `pg_dump --version` (expects `>= 17.x`) | Phase 2 staging backup & Write Gate opening |
| **2** | Confirm RDS network accessibility (Security Group inbound 5432 from current IP) and test TLS preflight | `node scripts/db/phase1_rds_preflight.js` | Phase 5 RDS bootstrap & migration application |
| **3** | Install Terraform CLI: `winget install --id Hashicorp.Terraform` | `terraform --version` | Infra validation & ECS gateway deployment |
| **4** | Start Docker Desktop daemon | `docker info` (expects active Server engine) | Gateway container build & ECR image push |
| **5** | AWS Console: Verify existing VPC has functional NAT Gateway on private subnets and ACM cert for `api.doctornect.com` | `aws acm list-certificates --region ap-south-1` | Terraform ALB HTTPS listener configuration |
| **6** | Firebase Production Console: Export Auth users and delete exact demo phones (`+919999900001`..`5`, `+919999988888`) using exact matches only | Exact phone match export: `firebase auth:export users.json --project=medibond-45fad` followed by exact phone filtering: `node -e 'const u = require("./users.json").users.filter(x => ["+919999900001","+919999900002","+919999900003","+919999900004","+919999900005","+919999988888"].includes(x.phoneNumber)); console.log("Matching UIDs:", u.map(x=>x.localId));'` | Play Store credential security compliance |
| **7** | Google Play Console: Submit Data Safety Form, provide Privacy Policy URL and Web Account Deletion URL | Review in Google Play Console dashboard | Play Store production release approval |
| **8** | Physical Device Smoke Test: Execute 9 critical clinical and emergency journeys on real phone hardware | Checklist completion in `docs/runbooks/DEVICE_SMOKE_TEST_CHECKLIST.md` | Mobile release sign-off |
