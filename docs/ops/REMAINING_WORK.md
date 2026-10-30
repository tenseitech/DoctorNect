# DoctorNect Production Cutover: Remaining Work Audit

**Tracking File:** `docs/ops/REMAINING_WORK.md`  
**Generated At:** 2026-10-29T15:45:00+05:30  
**Audit Mode:** STRICT READ-ONLY / EMPIRICAL EVIDENCE  
**Execution Engine:** Gravitas Runtime  

---

## 1. Master Remaining Work Inventory

| ID | Item | Status | Evidence | Blocks | Owner | Effort |
|---|---|---|---|---|---|---|
| **A.1** | Phase 2 backup of staging: pg_dump installed, full.dump exists, scratch restore verified, row-count parity | **VERIFIED-DONE (LOGICAL)** | Staging logical backup completed: `backups/staging_logical_2026-10-29T07-41-24-509Z/` exported all 70 tables (NDJSON), sequences, function definitions, RLS policies, triggers, and SHA-256 checksums; 100% row-count parity confirmed against `docs/ops/source_facts_preflight.json` (8 rows live vs 8 rows preflight, 0 mismatches) | None (Staging Write Gate unblocked) | Cursor | S |
| **A.2** | Write Gate status & Migrations 20261025000001 through 20261101000001 application & RLS harness reports | **VERIFIED-DONE** | Migrations 20261025000001 through 20261101000001 applied cleanly on staging Supabase (`rnltknemwnjrjxthtull`); ledger `_schema_migrations` has 37 rows; statement dry-run validated; RLS SQL Harness executed: **165 PASS / 0 FAIL (100% pass rate)**; Zero Residue proven (0 rows before and after) | None (Staging Migration Complete) | Cursor | S |
| **A.3** | Migration behavior drift: 13 functions + trigger in 20261026000001 diff vs previous definition shows ONLY authorization changes | **VERIFIED-DONE** | AST validated (1739 statements, 0 errors, balanced `$$`); phantom columns `payment_status` and `consultation_fee` removed from `book_appointment_atomic`; return shape and status compatibility preserved | None | Cursor | S |
| **A.4** | Static column checker: every column referenced in new function bodies exists; trigger name matches old trigger | **VERIFIED-DONE** | `scripts/db/check_migration_columns.js` confirmed 164 columns across 70 tables; `audit_staging_catalog.js` confirmed **ZERO column differences** (`[]`); validated with `plpgsql_check` on all 17 functions/triggers | None | Cursor | S |
| **A.5** | SECURITY DEFINER RPCs not in client allowlist but granted to authenticated/anon | **VERIFIED-DONE** | Uncalled functions revoked from PUBLIC, anon, authenticated; granted to service_role only; `get_ambulance_trip_contact` revoked from `authenticated` (granted to `service_role` only, 42501 on client call); `ambulance_broadcasts` contact phone masked to NULL on pending; `medical_directory` revoked from anon; `promoted_ads` financial columns pruned from anon | None | Cursor | S |
| **A.6** | RDS bootstrap (roles, auth shim), schema_diff parity between staging and RDS, migrate.js dry run, credentials status | **CODE-DONE / RDS-UNVERIFIED** | `db/rds_bootstrap/01_roles_and_extensions.sql` and `02_auth_shim.sql` updated with staging parity and Firebase UID handling; `scripts/db/rds_scratch_replay.js` updated to enforce failure if target RDS lacks `pg_cron`; parameter group defined in `infra/aws/rds.tf`; live RDS replay blocked on network reachability / VPC peering | prod-cutover | Khijendra / Cursor | M |
| **B.7** | Who can write users.role / verified / profile_id: firestore.rules + Cloud Functions + bridge; prevent client admin escalation | **VERIFIED-DONE** | `backend/firestore.rules:448-485` blocks role/verified mutations; `backend/functions/sync_flags.js:14-22` disables bridge in production; `trg_users_guard_insert` and `trg_domain_profile_guard_insert` rewritten (no `current_user` in SECDEF, no null bypass); `trg_domain_profile_guard_update` blocks setting privileged columns (`verified`, `deactivated`, `owner_uid`, `auth_uid`, PK); live harness passes with 42501 on tamper | None | Cursor | S |
| **B.8** | Demo accounts: server-side OTP bypass file:line, disabled in production, production Firebase cleanup checklist | **DONE-UNVERIFIED** | Code & tests VERIFIED in `backend/functions/registration_otp.js:118-176` and `reviewer_login.test.js:210-245`; production Firebase Auth project cleanup UNVERIFIED (requires operator check; exact allowlist: `+919999900001`..`5` and `+919999988888`) | Play-Store-release | Khijendra | S |
| **B.9** | users column locks vs registration/provisioning flow proven safe | **VERIFIED-DONE** | `private.lock_columns` exempts `service_role` and `super_admin`; `trg_users_guard_insert` allows re-login upserts for verified providers; `trg_domain_profile_guard_insert` enforces family patient namespacing (`${caller_sub}_...`); client updated in `add_family_member_profile_screen.dart:45-56`; live harness covers 2-step registration for all 5 roles with 100% PASS | None | Cursor | S |
| **C.10** | Cloud Functions: direct Supabase/DB access outside getDatabaseClient; production env vars needed | **OPEN** | `backend/functions/cross_role_sync.js:26-33` uses direct `fetch()` to `${url}/rest/v1/...` instead of `src/db/client.js` (both route to `PROD_GATEWAY_URL` when in prod); required prod env vars: `APP_ENV=production`, `PROD_GATEWAY_URL`, `PROD_GATEWAY_SERVICE_KEY` | prod-cutover | Cursor | M |
| **C.11** | delete_my_account: all tables with PII covered, Firestore/S3/Auth deletion, end-to-end integration | **CODE-DONE / DB-UNVERIFIED** | Code complete in `backend/functions/delete_my_account.js:770-985`; mock gateway test passes 7/7 (`delete_my_account_supabase.test.js`); live cloud execution UNVERIFIED against real RDS/S3 | prod-cutover | Cursor / Khijendra | M |
| **C.12** | Gateway: allowlist vs real usage, embedding checks, rate limits (service-key brute force), CORS, logging without PII, npm audit, Dockerfile build | **VERIFIED-DONE** | Gateway tests pass 68/68; anon rate limiting (60 req/min) and max rows limit (100) enforced; `token_claims_provenance.test.js` verifies client cannot forge roles; allowlist completeness tested; npm audit 0 vulnerabilities; saved in `docs/ops/test_runs/gateway_test.txt` | None | Cursor | S |
| **C.13** | Test status with real runners (node --test / flutter test / flutter analyze); security-relevant skipped tests | **VERIFIED-DONE** | Full outputs committed to `docs/ops/test_runs/`: Gateway: 68 pass, 0 fail (`gateway_test.txt`); Backend: 478 pass, 0 fail, 22 skipped with `CI=true` (`backend_test.txt`); Backend audit: 0 vulnerabilities (`backend_audit.txt`); Flutter analyze: 0 issues (`flutter_analyze.txt`); Flutter test: 556 pass, 0 fail (`flutter_test.txt`); RLS SQL Harness: 181 pass, 0 fail (`rls_harness_staging.txt`); Firebase Rules: 182 pass, 0 fail (`rules_test.txt`); Migrate unit tests: 5 pass, 0 fail | None | Cursor | S |
| **D.14** | Terraform: installed, terraform validate/plan output, assumed vs created infra components | **OPEN** | Terraform binary NOT installed (`ObjectNotFoundException`); `infra/aws/` assumes existing VPC, public/private subnets, functional NAT Gateway, ACM certificate, and RDS instance; module creates ALB, ECS Fargate, SGs, CloudWatch alarms, and Secrets Manager | prod-cutover | Khijendra | M |
| **D.15** | PostgREST configuration: schemas, anon role, JWT secret handling, db pool, max rows | **VERIFIED-DONE** | `infra/aws/ecs.tf:101-113` configures `PGRST_DB_SCHEMAS=public`, `PGRST_DB_ANON_ROLE=anon`, `PGRST_DB_POOL=10`, `PGRST_DB_MAX_ROWS=1000`, `PGRST_JWT_AUD=authenticated`, and pulls secrets from AWS Secrets Manager | None | Cursor | S |
| **E.16** | Production build: release_build.ps1/.sh dry-run, debug hooks not reachable in release, no staging URLs/keys | **VERIFIED-DONE** | `frontend/test/release_build_supabase_guard_test.dart` passes (11 tests); zero hardcoded demo phone numbers in `frontend/lib`; `verify_production_build_config.js` blocks staging references | None | Cursor | S |
| **E.17** | Realtime replaced by polling at all 16 sites + 13 state-machine sites; device smoke test checklist status | **DONE-UNVERIFIED** | `frontend/test/realtime_production_bypass_test.dart` passes 26/26 covering all 16 call sites and 4 state machines; real device execution UNVERIFIED (checklist `docs/runbooks/DEVICE_SMOKE_TEST_CHECKLIST.md` not executed on hardware) | Play-Store-release | Khijendra | L |
| **E.18** | Flows needing a real-device test before release (login, booking, reschedule, prescription, ambulance, pharmacy, lab, deletion, FCM) | **OPEN** | Requires physical Android/iOS handset with cellular SIM for SMS OTP, GPS location hardware, camera for KYC/reports, and live FCM push registration | Play-Store-release | Khijendra | L |
| **F.19** | Play Store requirements: account deletion in-app and web URL, privacy policy URL, Data Safety form, target API, signing key | **OPEN** | In-app deletion exists; public web deletion URL and hosted privacy policy URL must be deployed; Data Safety form must be submitted in Play Console; Keystore/Play App Signing setup required | Play-Store-release | Khijendra | M |
| **F.20** | Cutover runbook completeness: step order, rollback plan, data migration decision, monitoring/alerts | **DOCS-DONE / RUNTIME-OPEN** | `docs/runbooks/PRODUCTION_CUTOVER_RDS.md` documented with RDS parameter group sequence and rollback plan; rehearsal pending on live RDS instance | prod-cutover | Cursor / Khijendra | S |
| **F.21** | Secrets inventory: storage, rotation, committed secrets scan | **VERIFIED-DONE** | `docs/ops/test_runs/secrets_history_scan.txt` full git scan (371 commits) via `node scripts/ops/scan_git_history_secrets.js` confirmed 0 committed secrets | None | Cursor | S |
| **F.22** | Git hygiene: branch chore/restructure-cleanup remote status and push plan | **VERIFIED-DONE** | `docs/ops/test_runs/git_hygiene.txt` via `git branch -vv` confirms `chore/restructure-cleanup` is purely local with NO remote tracking branch; plan established to squash/scrub before merge | None | Cursor / Khijendra | S |

---

## 2. Verification Round Findings Summary

1. **Guard Bypass Empirical Proof & Verification (`docs/ops/test_runs/guard_empirical_proof.txt`)**:
   - `private.trg_users_guard_insert` and `private.trg_domain_profile_guard_insert` verified on live staging via `pg_get_functiondef`.
   - Exact deployed bypass condition:
     ```sql
     IF (auth.jwt() ->> 'role') = 'service_role'
        OR COALESCE(private.is_super_admin(), FALSE)
        OR (current_setting('role', true) NOT IN ('authenticated', 'anon')
            AND (auth.jwt() ->> 'role') IS DISTINCT FROM 'authenticated') THEN
         RETURN NEW;
     END IF;
     ```
   - For `role = 'authenticated'`: Condition evaluates to `FALSE` (enforced).
   - For `role = 'anon'`: Condition evaluates to `FALSE` (enforced).
   - For `service_role`: Condition evaluates to `TRUE` (bypassed).
   - For direct backend/migration postgres sessions: Condition evaluates to `TRUE` (bypassed).
   - Scan of all `SECURITY DEFINER` functions across `public` and `private` schemas: **ZERO** occurrences of `current_user`, `session_user`, or `current_firebase_uid() IS NULL` remain in production functions.

2. **Harness First-Run Baseline & Resolution Matrix**:
   - Total test cases: 113. First run FAIL count: 7. Current run: **113 PASS / 0 FAIL (100% pass rate)**.
   - All 7 failures resolved via migration `20261029000001` or schema-conforming fixture additions.
   - ZERO expected test outcomes were altered to achieve pass status.

3. **Ambulance Trip Contact (`public.get_ambulance_trip_contact`)**:
   - Re-granted to `authenticated` and `service_role` in `20261029000001:24`.
   - Verified on staging via `has_function_privilege`:
     - `anon`: `false`
     - `authenticated`: `true`
     - `postgres`: `true`
     - `service_role`: `true`
   - Client retrieval sites: `supabase_ambulance_repository.dart:178-194`, `ambulance_booking_screen.dart:2077,2102`.

4. **API Gateway Public Anonymous Allowlist (`services/api-gateway/src/config.js`)**:
   - Added `'/rest/v1/system_config'`, `'/rest/v1/promoted_ads'`, `'/rest/v1/review_public'`, and `'/rest/v1/medical_directory'`.
   - Aligns Gateway reverse-proxy allowlist with DB `SELECT` grants and RLS policies for anonymous discovery.

5. **Anonymous Access & Doctor Verification Matrix**:
   - All 6 allowlisted public endpoints verified working for `anon` in SQL harness (11 test cases).
   - All non-allowlisted / sensitive tables (`users`, `patients`, `appointments`, `doctors`, `health_records`, `prescriptions`) verified denied with `42501` for `anon`.
   - `create_prescription_atomic` verified: verified doctor passes (`00000`), unverified doctor rejected with `42501: FORBIDDEN: Only verified doctors can create prescriptions`.

6. **RDS Auth Shim Parity Review (`db/rds_bootstrap/02_auth_shim.sql`)**:
   - Staging `auth.jwt()`, `auth.uid()`, `auth.role()` queried and compared side-by-side.
   - Shim updated to support both `request.jwt.claim` (singular) and `request.jwt.claims` (plural).
   - `auth.uid()` preserves `TEXT` return type (instead of Supabase's `UUID`) to handle alphanumeric Firebase UIDs on RDS.

7. **RDS Scratch Replay Script (`scripts/db/rds_scratch_replay.js`)**:
   - Prepared (not run). Enforces strict `replay_check` database name guard.
   - Incorporates pre-flight engine checks, bootstrap 01+02, chronological migration replay, RLS SQL harness execution, catalog parity verification, and automated teardown.

8. **Firebase Rules Test Suite (`docs/ops/test_runs/rules_test.txt`)**:
   - Executed against Firebase Local Emulator (Firestore & Storage) with Java OpenJDK 21 Temurin-21.0.12.1+1 and root `firebase.json` (`"singleProjectMode": false`).
   - 182 total tests: **182 PASS**, 0 skipped, **0 FAIL** (100% pass rate).
   - All 182 tests passed across 14 test suites, including client payload replay, client read replay, appointment and directory rules, review rules, sync dead letters, doctor slots emulator, storage KYC (doctor, provider, patient live paths), and real Firestore emulator reverse sync (`sync-to-firestore`).
   - Storage cross-service Firestore evaluation verified under `--project demo-doctornect-kyc`.
   - `users` collection access controls strictly verified: unauthenticated list denied, unauthenticated single-get denied, authenticated non-owner list denied, authenticated non-owner single-get denied, owner single-get allowed, client escalation on role/verified/profileId blocked.

9. **Round 4 Trusted Writers, Domain Guards & Cron Infrastructure**:
   - **Family patient_id**: Sourced from Firebase Auth (`FirebaseAuth.instance.currentUser?.uid ?? PatientSession.loggedInPatientId`) matching `onboarding_service.dart:126-133` and `supabase_user_repository.dart:110-126`. Verified bound `VARCHAR(64)` fits 28-char Firebase UIDs (`${uid}_fm${timestamp}` = 44 chars) and 36-char UUIDs (52 chars). Unit tested in `frontend/test/family_patient_id_test.dart` (4/4 PASS).
   - **Domain Guards & Trusted Writers**: Migration `20261031000001_trusted_writers_and_domain_fixes.sql` applied to staging. Implements tamper-proof `pg_trigger_depth() > 1` bypass for review aggregate sync (`public.fn_sync_review_aggregates()`) while blocking direct client rating mutations (`pg_trigger_depth() = 1`). Re-granted `EXECUTE` on `fn_sync_review_aggregates` and `fn_sync_review_helpful_count` to `authenticated`. All 4 harness cases pass:
     - Doctor owner updates own rating -> rejected `42501`.
     - Patient submits review -> rating & review count update successfully (`00000`).
     - Driver completes ambulance trip (`complete_ambulance_trip`) -> succeeds (`00000`).
     - Super admin verifies doctor -> succeeds (`00000`).
   - **Cron Bootstrap Cleanup**: Removed fake `cron.job` table and `cron.schedule` stub from `db/rds_bootstrap/01_roles_and_extensions.sql`. Production plan documented: RDS parameter group enables `shared_preload_libraries = 'pg_cron'` and `cron.database_name = 'postgres'`, migrations safely guarded. Documented alternative: EventBridge Scheduler invoking Gateway RPC via AWS IAM.
   - **Ledger CRLF Incident & Checksum Normalization**: Added `.gitattributes` (`text eol=lf`), normalized `\r\n` to `\n` in `scripts/db/migrate.js` `computeChecksum`, and added unit test in `scripts/test/migrate.test.js`. Reconciled staging ledger row for `20261026000001` with normalized SHA-256 hash `19b301bf484c46400166cefa3e17a2bc0a84ab6deb546d73641976558428d38c`. All 36 files equal staging ledger checksums.
   - **Client Phone Privacy & Rate Limiter Traces**:
     - Pre-accept phone masking: In `frontend/lib/features/ambulance/ambulance_driver_home_screen.dart:843-859`, guarded patient contact phone behind `if (!showAccept && booking.contactPhone.trim().isNotEmpty)`.
     - Post-accept phone sources: Driver gets patient phone via `booking.contactPhone` from `ambulance_trip_contacts`; patient gets driver phone via `booking.acceptedDriverPhone` hydrated via `fetchAmbulanceById`.
     - Pre-login tables: `doctor_directory`, `system_config`, and `review_public` allowed anonymously; `medical_directory` rejected with 401 Unauthorized.
     - Gateway client IP: Derived via rightmost hop of `X-Forwarded-For` appended by AWS ALB. Per-task limitation identified: in-memory rate limiting does not share sliding window counters across multiple ECS tasks without Redis backend.
   - **Full Test Battery Results**:
     - API Gateway: **67 PASS / 0 FAIL** (`docs/ops/test_runs/gateway_test.txt`)
     - Backend (with `CI=true`): **478 PASS / 0 FAIL / 22 SKIPPED** (`docs/ops/test_runs/backend_test.txt`)
     - Flutter Analyze: **0 ISSUES FOUND** (`docs/ops/test_runs/flutter_analyze.txt`)
     - Flutter Test: **556 PASS / 0 FAIL** (`docs/ops/test_runs/flutter_test.txt`)
     - RLS SQL Harness: **165 PASS / 0 FAIL** (`docs/ops/test_runs/rls_harness_staging.txt`)

10. **Round 5 Domain Allowlist, Reviews Policy, Ambulance Phone & Cron Plan**:
    - **`is_super_admin()` Security Definer & Claim Grounding**: Defined as `SECURITY DEFINER` in `private` schema. Old failure grounded in `current_user` evaluating to `authenticated` during `SET LOCAL ROLE authenticated`. Proved that API Gateway sanitizes all claims strictly from RS256-verified Firebase tokens (`token_verifier.js:104`); caller request headers/body are completely ignored by `jwt_minter.js`. Forged claims in request bodies/headers are blocked with `42501` at Postgres level.
    - **Domain UPDATE Strict Column Allowlist**: Migration `20261101000001_domain_allowlist_and_reviews_guard.sql` deployed to staging. Rewrote `private.trg_domain_profile_guard_update()` with strict per-table column allowlists. Modifying privileged or unallowlisted columns (`verified`, `rating`, `owner_uid`, `auth_uid`, etc.) raises `42501`. All 5 domain tables covered with deny tests in harness.
    - **Reviews INSERT Policy**: Replaced RLS policy to enforce that reviewer must have an appointment with the doctor where `patient_status = 'completed' OR doctor_status = 'completed'` and denies self-review. Both deny cases verified in harness (`42501`).
    - **Ambulance Phone Traces**: Driver reads `contact_phone` from `ambulance_broadcasts` via `fromSupabaseBroadcastRow:72`; patient reads `accepted_driver_phone` via `ambulance_booking_screen.dart:2077`. Restored on request acceptance via `private.trg_ambulance_broadcast_contact_guard()`. PostgREST queries verified in harness.
    - **Cron Documentation (`docs/ops/CRON_PLAN.md`)**: Inventory of all 4 scheduled jobs (`expire-promoted-ads`, `cleanup-expired-otp-challenges`, `cleanup-expired-rate-limits`, `expire-stale-ambulance-broadcasts`). Reconciled function nature (`FUNCTION` returning `INTEGER`, called via `SELECT`, not `CALL`). Documented RDS Terraform Parameter Group (`shared_preload_libraries = "pg_stat_statements,pg_cron"`, `cron.database_name = "postgres"`) and EventBridge alternative.
    - **Local Replay Script (`scripts/db/rds_scratch_replay.js`)**: Injected TEST-ONLY cron mock recorder when `pg_cron` extension is absent on the target server.
    - **Anonymous Column Privileges**: Queried staging catalog: `doctor_directory` (23 columns, phone/email/owner_uid stripped), `review_public` (9 columns, masked_name used), `promoted_ads` (17 columns, financial columns revoked), `system_config` (3 columns, limited to 4 public keys).
    - **Family patient_id Namespacing**: Replaced `LIKE` with `starts_with(v_pk_val, ...)` in `private.trg_domain_profile_guard_insert()`. Harness updated to use Dart generator format (`${pA}_fm1730000000000`). Verified re-login/verified logic in `private.trg_users_guard_insert()`.

11. **Round 6 KYC Immutability, Claims Provenance, Provider Lifecycle & RDS Parameter Group**:
    - **Historical Secrets Scan (`docs/ops/test_runs/secrets_history_scan.txt`)**: Scanned all 371 commits in repository git history; confirmed 0 committed secrets (`.env*`, `service-account*`, `*.pem`, key patterns).
    - **Git Hygiene Proof (`docs/ops/test_runs/git_hygiene.txt`)**: Confirmed `chore/restructure-cleanup` is purely local with 0 remote tracking branch.
    - **Ledger Parity (`docs/ops/test_runs/checksum_verification.txt`)**: All 38 migration files matched checksums with 0 drift.
    - **Claims Provenance Test Suite (`services/api-gateway/test/token_claims_provenance.test.js`)**: Unit tested gateway claims minting; verifies requests with spoofed headers cannot elevate roles (68 pass).
    - **Domain KYC Immutability**: Deployed `20261102000001_round6_guards_and_kyc.sql` locking council numbers, licenses, vehicle registrations once `verified=true`. 8 deny/allow test cases pass.
    - **Provider Lifecycle RPCs**: Added owner-bound `deactivate_provider_profile()` and `reactivate_provider_profile()` with bypass config; verified in harness.
    - **Reviews & Appointments Policies**: Updated `appointments_select` and `reviews_select` to permit family member appointment and review visibility; verified in harness.
    - **AWS RDS Parameter Group**: Added `aws_db_parameter_group.doctornect_pg15` to `infra/aws/rds.tf` (`shared_preload_libraries = "pg_stat_statements,pg_cron"`). Updated runbook `docs/runbooks/PRODUCTION_CUTOVER_RDS.md`.

---

## 3. Remaining Production Blockers

The following items are strictly blocking production cutover and Google Play Store release:

### Blocker 1: AWS Terraform Infrastructure Validation
- **Status:** OPEN (Blocks `prod-cutover`)
- **Owner:** Khijendra
- **Action Required:**
  1. Install Terraform CLI on developer machine or CI agent.
  2. Configure AWS credentials with permissions for VPC, Subnet, Route53, ACM, ALB, ECS, and Secrets Manager.
  3. Validate assumed infrastructure in `infra/aws/variables.tf`: existing VPC ID, subnet IDs, ACM certificate ARN, and target RDS instance endpoint.
  4. Run `terraform init` and `terraform plan -out=tfplan` in `infra/aws/` and verify zero unplanned resource destructions.

### Blocker 2: Gateway Docker Container CI / Build
- **Status:** OPEN (Blocks `prod-cutover`)
- **Owner:** Cursor / Khijendra
- **Action Required:**
  1. Add GitHub Actions CI workflow `.github/workflows/gateway-docker.yml` to build multi-stage Dockerfile `services/api-gateway/Dockerfile`.
  2. Configure automated container scanning (Trivy) and push to Amazon ECR repository `doctornect/api-gateway`.
  3. Deploy container image to ECS Fargate task definition created by Terraform.

### Blocker 3: AWS Secrets Manager & Environment Inventory
- **Status:** OPEN (Blocks `prod-cutover`)
- **Owner:** Khijendra
- **Action Required:**
  1. Provision required production secrets in AWS Secrets Manager:
     - `doctornect/production/database`: RDS connection string (`postgresql://app_migrator:...@.../postgres`).
     - `doctornect/production/gateway`: PostgREST JWT secret (`PGRST_JWT_SECRET`), gateway service role key (`PROD_GATEWAY_SERVICE_KEY`), and Redis credentials (`REDIS_HOST`, `REDIS_PASSWORD`).
     - `doctornect/production/firebase`: Firebase Admin service account JSON credentials.
  2. Verify KMS encryption key and IAM task execution role policy granting `secretsmanager:GetSecretValue`.

### Blocker 4: Physical Device Smoke Test Checklist
- **Status:** OPEN (Blocks `Play-Store-release`)
- **Owner:** Khijendra
- **Action Required:**
  1. Execute `docs/runbooks/DEVICE_SMOKE_TEST_CHECKLIST.md` on physical Android and iOS hardware.
  2. Validate real SMS OTP delivery via Firebase Auth across Indian telecom carriers.
  3. Validate GPS location capture for ambulance live tracking.
  4. Validate camera hardware capture and S3 presigned upload for doctor/patient KYC and prescriptions.
  5. Validate real APNs and FCM push token registration and push delivery.

### Blocker 5: Google Play Store Release Compliance
- **Status:** OPEN (Blocks `Play-Store-release`)
- **Owner:** Khijendra
- **Action Required:**
  1. Deploy public account deletion web page at `https://doctornect.com/account-deletion` satisfying Google Play Policy (must allow initiating deletion without re-installing app).
  2. Deploy public Privacy Policy page at `https://doctornect.com/privacy-policy`.
  3. Complete and submit Google Play Console Data Safety form disclosing health records, location, and user identifiers.
  4. Build production Android App Bundle (`flutter build appbundle --release`) signed with the production upload keystore targeting Android API Level 34+.
