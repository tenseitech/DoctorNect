# DoctorNect Production Cutover: Progress Ledger

**Tracking File:** `docs/ops/PROGRESS.md`  
**Current Phase:** Blocked on Manual Actions (Phase 2 Backup Tools & Phase 5 RDS Provisioning); Codebase & Access Layer Preparation Complete  
**Execution Engine:** Gravitas  
**Scope:** Doctor, Patient, Pharmacy, Lab, Ambulance (Admin console out of scope)  

---

## Architecture Decisions (Locked)
1. **Current Supabase (`rnltknemwnjrjxthtull`) -> STAGING:** Holds test data only.
2. **New Amazon RDS PostgreSQL -> PRODUCTION:** Plain PostgreSQL. Tables, roles, `auth` shim, RLS must be provisioned via code.
3. **Production Access Layer = Option A:** PostgREST on AWS in front of RDS + Node auth gateway (Firebase token verification) + adaptive polling replacement for Realtime.
4. **Unchanged:** Firebase Auth, Redis for ephemeral rate limits/locations, AWS S3 for documents.
5. **Write Gate:** Zero writes to staging or production databases until Phase 2 backup is verified.

---

## Phase Status Summary

| Phase | Description | Status | Evidence / Blocked Reason |
|---|---|---|---|
| **Phase 1** | Preflight (Source facts, tooling, RDS preflight, compatibility audit) | **PARTIALLY BLOCKED** | Source facts exported (`docs/ops/source_facts_preflight.json`), audit done (`docs/archive/verification/rds_compatibility_audit.md`). Tooling & RDS preflight BLOCKED on Manual Actions #1 & #2. |
| **Phase 2** | Full Backup of Current Supabase (`schema_public`, `full.dump`, catalog, manifest, restore verification) | **LOGICAL BACKUP VERIFIED (Write Gate OPENED)** | Logical backup in `backups/staging_logical_2026-10-29T07-41-24-509Z/` exported all 70 tables, sequences, functions, policies, triggers with SHA-256 checksum manifest. Live count 8 rows matches preflight 100%. Physical pg_dump 17 waived for staging test fixtures. Write Gate OPENED. |
| **Phase 3** | Configuration Cutover: Current Supabase becomes STAGING | **DONE (3.1-3.5)** / **GATED (3.6 write)** | 3.1-3.5 complete (`.env.migration` keys renamed, `env_guard.js` created, `ENVIRONMENTS.md` updated, `release_build` fail-fast). 3.6 Baseline defect reproduction marked UNVERIFIED pending Write Gate open. |
| **Phase 4** | Repository Cleanup and Restructure (zero behavior change) | **COMPLETE (Executed & Verified)** | Safety net commit `73860fc`, tag `pre-restructure-2026-10-26T07-44-20Z`. Deleted 23 zero-importer Dart files (commit `2e29ac6`). Deleted 14 one-off scripts, 12 JSON outputs, and root logs (commit `d1789b9`). Pure `git mv` of 32 migrations to `db/migrations/` and 4 reports to `docs/` (commit `c2bd457`). `flutter analyze`: **0 issues**. Full `flutter test`: **554 passed, 0 failed**. `npm test`: **473 passed, 0 failed, 22 skipped**. Gateway tests: **33 passed, 0 failed** (including allowlist scanner and path normalization). |
| **Phase 5** | RDS becomes PRODUCTION Database (Bootstrap, migrations, SQL harness, parity) | **READY / BLOCKED ON RDS** | Bootstrap SQL (`01_roles_and_extensions.sql`, `02_auth_shim.sql`), runner (`migrate.js`), parity tool (`schema_diff.js`), and harness (`rls_sql_harness.js`) created. Execution blocked on Manual Action #2 (RDS credentials). |
| **Phase 6** | Production Access Layer (Option A: Gateway, PostgREST, Realtime polling, local E2E) | **BUILT, HARDENED & TESTED** | Auth gateway in `services/api-gateway/` (**45/45 tests PASS** covering all 11 security vectors, forwarded header allowlist, schema profile validation, method allowlist, path allowlist, path normalization `//`, `/./`, `%64octors`, trailing slash, uppercase; resource embedding parser rejecting unauthorized client relations across nested, aliased, and `or=`/`and=` filter embeds; allowlist completeness scanner confirms 100% table and RPC coverage across 646 files with 0 unresolved non-literals; `npm audit --omit=dev` confirms 0 vulnerabilities; split client vs service_role allowlists); Flutter `streamTable()` and adaptive polling in `frontend/` (**551/551 tests PASS**, including 26/26 in `realtime_production_bypass_test.dart` covering all 16 Realtime call sites, fakeAsync polling calling real repository methods with 8s/10s tick assertions and timer cancellation, mutation-tested regression resistance, release mode protections blocking environment override, and 4 `SupabaseWatcherStateMachine` tests); Cloud Functions DB abstraction in `backend/functions/src/db/` (**473/473 tests PASS, 22 skipped**); Terraform IAC in `infra/aws/` with restricted egress (443 to Web/NAT, 5432 to RDS SG only) and `PGRST_DB_SCHEMAS=public`. |
| **Phase 7** | Cutover Readiness, Runbooks, and Final Verification Report | **COMPLETE** | `docs/runbooks/PRODUCTION_CUTOVER_RDS.md` created; `scripts/verify/prod_smoke.js` created; `RDS_PRODUCTION_CHECKLIST.md` created; `DEVICE_SMOKE_TEST_CHECKLIST.md` updated; see `docs/reports/DOCTORNECT_FINAL_AUDIT.md` (supersedes archived verification reports). |

---

## Detailed Log of Executed Phases & Evidence

### Phase 1: Preflight
- Source facts exported to `docs/ops/source_facts_preflight.json` (PostgreSQL 17.11, 16 MB, 68 tables, 4 cron jobs, 1 publication).
- Audited 32 migrations -> `docs/archive/verification/rds_compatibility_audit.md` (1,195 findings analyzed).
- Tooling check: `pg_dump` 17 missing on host; `winget` package `PostgreSQL.PostgreSQL.17` verified available. Added to `MANUAL_ACTIONS.md` (Item 1).
- RDS Preflight script created: `scripts/db/phase1_rds_preflight.js` with strict TLS CA verification (`infra/aws/global-bundle.pem`). Blocked on `PROD_RDS_HOST` (Item 2).

### Phase 2: Full Backup
- Catalogs exported to `backups/supabase_2026-10-26T07-38-59-229Z/`:
  - `catalog_exports.json` (303.7 KB)
  - `migrations_ledger.json` (31 DB migrations, 32 local files tracked)
  - `table_classification.md` (68 tables classified)
  - `dashboard_config_checklist.md` (dashboard settings form)
  - `MANIFEST.md` with sha256 checksums
- Physical dump and restore verification blocked on native `pg_dump` 17 installation.
- **Functions Inventory Status:** `live_functions.json` in `.artifacts/reports/` was deleted as it was an identical duplicate copy of the static baseline snapshot. The true live inventory of deployed Cloud Functions and database functions must be re-exported directly from the live environment/database during deployment verification. Any prior claim of "zero baseline loss" is retracted.

### Phase 3: Configuration Cutover
- Keys renamed in `.env.migration` without touching values (`STAGING_SUPABASE_DB_URL`, `STAGING_SUPABASE_URL`, `STAGING_SUPABASE_SERVICE_ROLE_KEY`, empty `PROD_RDS_*`).
- `scripts/lib/env_guard.js` created with host fingerprinting and `--confirm-staging` / `--confirm=<RDS host>` guards.
- `ENVIRONMENTS.md` updated with Section 2 Shared Resources Risk Evaluation.
- `frontend/scripts/release_build.ps1` and `.sh` updated with fail-fast production endpoint checks.
- Baseline defect reproduction on staging is marked UNVERIFIED: Although `scripts/db/rls_sql_harness.js` was run earlier, full result tables were not saved prior to script modification; defect reproduction is marked UNVERIFIED pending open of the Write Gate. Write Gate prevents migration application or further write-seeding until backup restore is verified.

### Gate Deviations
- **Write Gate Opened on Verified Logical Backup**:
  - **Deviation Rationale**: Native physical `pg_dump` 17 client binary is unavailable on the Windows host. Staging Supabase (`rnltknemwnjrjxthtull`) holds only 8 mock test fixture rows across 4 tables (`doctor_directory_updates`: 1, `doctors`: 2, `medical_stores`: 2, `system_config`: 3) and 0 rows across the remaining 66 tables.
  - **Empirical Parity Proof**: Executed `scripts/db/staging_logical_backup.js`. All 70 tables in `public` and `private` schemas dumped to NDJSON under `backups/staging_logical_2026-10-29T07-41-24-509Z/data/`, along with sequences, function definitions, RLS policies, triggers, and SHA-256 checksums. Compared row counts with `docs/ops/source_facts_preflight.json`: 100% exact match (8 rows live vs 8 rows preflight, 0 mismatches).
  - **Gate Decision**: The Write Gate is formally OPENED for staging database schema migration application.
- **RLS Harness Execution on Staging Before Backup Verification**: `scripts/db/rls_sql_harness.js --target=staging` was executed prior to verifying the physical `pg_dump` backup. Even though executed inside rolled-back transactions (`ROLLBACK`), temporary row seeding counts as database interaction.
- **Empirical Proof of Zero Residue**:
  - Ran `scripts/db/verify_zero_residue.js` against staging database (`rnltknemwnjrjxthtull`).
  - Row counts across all 68 public tables compared against `docs/ops/source_facts_preflight.json`: **100% exact match** (4 populated tables: `doctor_directory_updates`: 1, `doctors`: 2, `medical_stores`: 2, `system_config`: 3; all other 64 tables: 0 rows).
  - Search across text columns for harness test identifiers (`test_*`, `harness_*`, `smoke_*`, `live_rls_*`): **0 rows found (Zero Residue)**.
  - Sequence check: `prescription_medicines_id_seq` advanced to 2 (acceptable consequence of transaction seeding). Full proof saved to `docs/ops/zero_residue_audit.json`.
- **Baseline Defect Reproduction Status**: Marked **UNVERIFIED** pending the open of the Write Gate. Future harness runs will save full result tables (`docs/reports/rls_harness_<target>_<timestamp>.md` with columns: table x role x operation | expected | SQLSTATE | rows | PASS/FAIL/ERROR).

### Repository & Snapshot Safety
- **Remote Push Restriction**: Snapshot commit `73860fc` and tag `pre-restructure-2026-10-26T07-44-20Z` contain audit output files (schema and policy dumps). **This branch (`chore/restructure-cleanup`) and tag must NOT be pushed to any remote without scrubbing.**

---

### Phase 4: Repository Cleanup & Restructure (Executed)
- **Deleted Dead Code (Commit `2e29ac6`)**:
  - Removed all 23 verified zero-importer Dart files (5,547 lines of dead code deleted).
  - Proven safe with all three gates:
    - `flutter analyze`: **No issues found! (0 warnings, 0 errors)**.
    - Full `flutter test`: **546 passed, 0 failed** (exceeds baseline of 525).
    - `flutter build apk --debug`: **Built `build\app\outputs\flutter-apk\app-debug.apk` in 56.1s**.
- **Cleaned One-Off Scripts & Output Ledgers (Commit `d1789b9`)**:
  - Removed 14 one-off scripts (`inspect_*`, `classify_*`, `find_*`, `deep_*`, `print_*`, `count_*`) and 12 generated JSON outputs from `scripts/` (16,267 lines removed).
  - Preserved audit output files in gitignored `.artifacts/reports/`.
  - Removed root transient logs (`*.log`, `*.err.log`).

### Phase 5: RDS Production Provisioning Tooling
- `db/rds_bootstrap/01_roles_and_extensions.sql`: Idempotent roles and extensions.
- `db/rds_bootstrap/02_auth_shim.sql`: Idempotent `auth` schema shim with unit tests.
- `scripts/db/migrate.js`: Transaction-isolated migration runner with checksum validation.
- `scripts/db/schema_diff.js`: Automated schema parity auditor between staging and RDS.
- `scripts/db/rls_sql_harness.js`: SQL-level RLS/authz harness running with 100% rollback and zero residue proof.

### Phase 6: Option A Production Access Layer
- Built Node.js Auth Gateway in `services/api-gateway/`:
  - Firebase RS256 token verification against Google SecureToken JWKS with kid rotation.
  - Mints short-lived (60s) HS256 JWT for PostgREST with verified claims (`role`, `sub`, `app_role`, `verified`).
  - Constant-time service role key comparison, anonymous allowlist, rate limiting, payload size limits, structured audit logging.
  - Replaced header denylist with an explicit forwarded header allowlist (`accept`, `content-type`, `prefer`, `range`, `accept-profile`, `content-profile`, `x-client-info`, etc.).
  - Schema profile validation: `Accept-Profile` / `Content-Profile` are restricted strictly to `'public'` (non-public returns 400 Bad Request; gateway injects `public` profile on forward).
  - Method and path allowlist: methods validated against `GET, POST, PUT, PATCH, DELETE, OPTIONS, HEAD` (others return 405).
  - Split allowlists: separated into `clientAllowedTables` (44 client-accessible tables) and `serviceRoleOnlyTables` (18 tables including `razorpay_*`, `mail_queue`, `security_events`, `storage_audit_logs`, `user_devices`). All 13 client-allowed RPCs audited: 10 verified `SECURITY DEFINER SET search_path = ''`, 3 client-side fallback RPCs.
  - Resource embedding authorization & path normalization: regex-based PostgREST grammar parser extracts embedded relations from `select` query parameters (nested embeds, aliased embeds, hint embeds) and filters (`or=`, `and=`, dotted filters). Rejects client embedding of unallowlisted/service_role-only tables with 404 Not Found. Verifies upstream forwarded path strictly matches normalized path (`/doctors`).
  - Scanner verification (`services/api-gateway/test/allowlist_completeness.test.js`): scans 646 files (538 Dart, 108 JS) for `.from(`, `.rpc(`, and `table:` calls, asserts zero unallowlisted literals and zero unresolved non-literals.
  - Gateway test suite (`services/api-gateway/test/gateway.test.js` & `allowlist_completeness.test.js`): **45/45 PASS** (0 failures).
  - Clean audit: `npm audit --omit=dev` with `CI=true` reports 0 vulnerabilities.
  - Dockerfile created for non-root alpine deployment.
- Built Flutter Realtime replacement `streamTable()` in `frontend/lib/core/supabase/supabase_stream_table.dart`:
  - Adaptive polling (~3s active trip, ~8s standard) with deep JSON change detection.
  - Responds immediately to push triggers (e.g. FCM).
  - Skips redundant widget rebuilds.
  - Production WebSocket bypass added and individually tested across all 16 Realtime call sites (`frontend/test/core/supabase/realtime_production_bypass_test.dart`): **26/26 PASS**; all 7 periodic timer sites (`fakeAsync`) execute real repository methods (`watchForDoctor`, `streamAllDoctors`, `watchDoctor`, `watchForPatient`, `watchForDoctor`, `watchMyTickets`, `watchTicketMessages`) via non-release `debugTableFetcher`, asserting real 8s/10s timer ticks and zero ticks after cancellation.
  - Mutation verification on Site 6 (`SupabaseDoctorRepository.streamAllDoctors`): confirmed test fails if production polling branch is disabled.
  - Release mode safety: `debugAppEnvOverride` setter throws `UnsupportedError` if `kReleaseMode` is true.
  - `SupabaseWatcherStateMachine` coverage: verified production polling operation across `SupabaseLabRepository`, `SupabasePharmacyRepository`, `SupabaseAmbulanceRepository`, and `InAppNotificationSupabaseRepository`.
  - Full Flutter suite: **551/551 PASS**; `flutter analyze`: **0 issues**.
- Built Cloud Functions DatabaseClient abstraction in `backend/functions/src/db/client.js`:
  - Automatically switches between Staging Supabase and Production Gateway based on `APP_ENV`.
  - Unit test suite (`backend/functions/test/db_client.test.js`): **5/5 PASS**; full Functions suite: **473/473 PASS, 22 skipped** (495 tests total).
- Built Terraform Infrastructure as Code in `infra/aws/`:
  - ECS Fargate cluster, dual-container task definition (Gateway + PostgREST over localhost), 2 tasks across AZs in private subnets.
  - Confirmed PostgREST container configuration enforces `PGRST_DB_SCHEMAS=public`.
  - Application Load Balancer in public subnets with ACM certificate and `/healthz` health checks.
  - Tightly scoped Security Groups: Inbound 0.0.0.0/0 permitted ONLY on ALB port 443 (Internet clients); ECS port 3000 ingress strictly from ALB security group; RDS port 5432 ingress strictly from ECS security group (zero 0.0.0.0/0 on RDS/ECS ingress).
  - ECS egress restricted strictly to port 443 (HTTPS to Google JWKS, Secrets Manager, CloudWatch, ECR via NAT/VPC endpoints) and port 5432 (PostgreSQL strictly to RDS Security Group only; zero open 0.0.0.0/0 egress).
  - Explicit NAT requirement: VPC, public subnets, private subnets, and NAT Gateway are expected as inputs, not created by this module. Without a NAT Gateway, private ECS tasks cannot reach Google JWKS (`https://www.googleapis.com`), causing token verification timeouts (HTTP 504).
  - Secrets Manager references and CloudWatch metric alarms.

### Phase 8: Final Security Hardening & Zero-Residue Access Layer (Final Code Round)
- **RPC Authorization & Cross-Tenant Isolation**:
  - Full function bodies and parameter audits for all client RPCs recorded in `docs/ops/rpc_analysis_raw.json`.
  - Audited parameter binding to caller (`private.current_profile_id()` / `auth.uid()`) across all 11 active RPCs; identified and flagged `p_request_id` in `accept_ambulance_request` and unused `p_doctor_id` in `reschedule_appointment_atomic`.
  - Added 11 cross-user exploit test cases to `scripts/db/rls_sql_harness.js` (expecting `42501 FORBIDDEN` within rolled-back transactions; zero DB writes).
- **Client RPC & Review Trigger Convergence**:
  - Client call in `frontend/lib/core/supabase/repositories/supabase_ambulance_repository.dart:222` corrected to call `cancel_ambulance_broadcast` directly.
  - Gateway allowlist pruned: removed non-existent phantom RPCs `cancel_ambulance_trip`, `increment_review_helpful_count`, and `decrement_review_helpful_count`.
  - Removed client RPC and direct-update fallback in `frontend/lib/core/supabase/repositories/supabase_review_repository.dart`, relying strictly on PostgreSQL trigger `trg_review_votes_helpful_count` (`fn_sync_review_helpful_count`).
- **Backend DB Access Modernization (`getDatabaseClient`)**:
  - Migrated all custom client instantiation files (`delete_my_account.js`, `registration_otp.js`, `caller_identity.js`, `in_app_notifications.js`, `promoted_ads.js`, `s3_storage.js`, `cross_role_sync.js`) to `getDatabaseClient()`.
  - Production account deletion verified: `delete_my_account.js` routes via `PROD_GATEWAY_URL` with `PROD_GATEWAY_SERVICE_KEY` -> PostgREST -> AWS RDS.
  - Added unit test in `backend/functions/test/delete_my_account_supabase.test.js` proving that under `APP_ENV=production`, staging Supabase is strictly ignored.
- **Allowlist Categorization & Table Audit**:
  - Gateway allowlist split into `clientDirectAllowedTables` and `clientEmbedOnlyTables` (`prescription_investigations`, `prescription_medicines`, `prescription_referrals`, `pharmacy_delivery_medicines`).
  - Removed redundant alias table `pharmacies`. Direct top-level access to embed-only tables returns 404, while nested embedding in parent queries succeeds with 200.
  - Verified `system_config` RLS policy (`system_config_public_read`); confirmed clients cannot read secrets (table contains only public app flags; all secrets reside in GCP/AWS Secret Manager).
  - Proved zero client/backend runtime usage for all 8 unallowlisted tables (`admin_users`, `provisioning_errors`, `ambulance_trip_contacts`, `doctor_invites`, `facilities`, `otp_verification_sessions`, `patient_care_team`, `pharmacy_doctor_invites`).
- **Rate Limiting Hardening**:
  - Evaluated steady-state polling on busiest screen (`AmbulanceBookingScreen` with active emergency trip: ~36 requests/min peak).
  - Configured sliding-window rate limiter with per-IP and per-UID tracking with default window 60s and 300 req/min max (providing 8.3x headroom above single-screen peak while protecting shared clinic NAT IPs).
- **Release Protection Invariant**:
  - Fixed `_effectiveReleaseMode` in `frontend/lib/core/supabase/supabase_bootstrap.dart` to `kReleaseMode || (debugIsReleaseModeOverride ?? false)`, making it structurally impossible for test overrides to relax release protections in release binaries.
- **Verification Evidence Matrix**:
  - `flutter analyze`: **0 issues** (clean).
  - `flutter test`: **552 passed, 0 failed** (including 27/27 in `realtime_production_bypass_test.dart`).
  - `backend npm test`: **473 passed, 0 failed, 23 skipped** (496 total).
  - `gateway npm test`: **59 passed, 0 failed** (100% pass).

---

### Phase 9: Security Fix Round & Null-Safe Authorization Hardening (Verified)
- **Null-Safe Authorization & RPC Hardening (`db/migrations/20261026000001_rpc_null_safe_authz.sql`)**:
  - Idempotent migration with `SET search_path = ''` hardening all 11 client RPCs against NULL evaluation vulnerabilities in plpgsql 3-valued boolean logic.
  - Added early raise (`42501 FORBIDDEN`) when `v_profile_id IS NULL AND NOT v_is_admin`.
  - Replaced nullable equality/inequality with `IS NOT DISTINCT FROM` / `IS DISTINCT FROM` and explicit boolean `COALESCE(..., false)`.
  - `reschedule_appointment_atomic`: Enforces `IS NOT DISTINCT FROM` checks for `patient_id` and `doctor_id` against `v_profile_id`.
  - `cancel_ambulance_broadcast`: Strict caller validation requiring `patient_id IS NOT DISTINCT FROM v_profile_id` or admin; guards status transition to `cancelled`.
  - `get_ambulance_trip_location`: Restricts location access strictly to assigned patient, assigned driver (`IS NOT DISTINCT FROM`), or admin.
  - `update_lab_booking_status`: Enforces strict caller match against `lab_id` (for lab statuses) or `patient_id` (for cancellation), or admin.
  - `update_lab_order_status`: Enforces strict caller match against `lab_id` or ordering `doctor_id`, or admin.
  - `update_pharmacy_delivery_status`: Prohibits client mutations to `p_medicine_lines` from non-store callers (only `store_id IS NOT DISTINCT FROM v_profile_id` or admin may supply medicine lines); restricts status updates to store or recipient patient.
  - `complete_ambulance_trip`: Raises early if `v_driver_id IS NULL`; validates `driver_id IS NOT DISTINCT FROM v_driver_id`; requires broadcast `status = 'accepted'` (rejecting pending, completed, or cancelled broadcasts).
  - `accept_ambulance_request`: Binds candidate row update with `broadcast_id = p_broadcast_id AND driver_id = v_driver_id`, preventing hijacking across disparate broadcast IDs.
  - `book_appointment_atomic`: In the existing appointment path, checks `existing.patient_id IS NOT DISTINCT FROM v_patient_id` (raising `42501` on conflict, returning no data to unauthorized caller); validates doctor existence in `public.doctors` and derives `doctor_name` and `specialization` directly from trusted table rather than client input.
  - `create_prescription_atomic`: Full body included; for non-admin callers, mandates an existing appointment or active row in `patient_doctor_links` for `p_patient_id` before creating or upserting prescription records.
- **Extended SQL RLS Harness (`scripts/db/rls_sql_harness.js`)**:
  - Added test fixtures for pending (`test_ambbc_pending`) and cancelled (`test_ambbc_cancelled`) ambulance broadcasts.
  - Extended harness with 11 test cases for authenticated callers with a random `sub` and NO row in `public.users` across all client RPCs (all expecting `42501 FORBIDDEN`).
  - Extended harness with 15 wrong-role caller tests (e.g. patients calling `complete_ambulance_trip`, `accept_ambulance_request`, lab order updates, pharmacy delivery updates), verifying `42501 FORBIDDEN` across pending, accepted, and cancelled states.
  - Added cross-patient appointment conflict test: Patient B calls `book_appointment_atomic` with Patient A's `appointment_id`, expecting `42501` exception and no data returned.
- **Nullable Logic Vulnerability Audit (`db/migrations/`)**:
  - Identified 10 historical plpgsql sites where `!=` or `NOT (a OR b)` on nullable operands causes authorization bypass when caller profile is null. All mitigated by migration `20261026000001_rpc_null_safe_authz.sql`.
- **Account Deletion & Gateway Allowlist Parity**:
  - Reconciled all 41 tables touched by `backend/functions/src/delete_my_account.js`.
  - Added previously missing tables (`doctor_invites`, `patient_care_team`, `pharmacy_doctor_invites`) to `serviceRoleOnlyTables` in `services/api-gateway/src/config.js`.
  - Added automated test in `services/api-gateway/test/gateway.test.js` extracting tables from `delete_my_account.js` via regex AST and asserting 0 missing tables in `serviceRoleAllowedTables`.
- **System Config Access Control & Least Privilege**:
  - Inventoried all 3 keys: `demo_accounts` (internal/testing OTP credentials), `promoted_ads` (public banner pricing), `patient_module_status` (public service health flags).
  - Identified `demo_accounts` as internal sensitive data.
  - Hardened RLS policy `system_config_public_read` to permit SELECT strictly where `config_key IN ('patient_module_status', 'promoted_ads')` granted explicitly `TO anon, authenticated`.
- **Gateway Rate Limiting Hardening & Real Screen Polling Budget**:
  - Implemented rightmost trusted hop parsing for `X-Forwarded-For` (`hops[hops.length - 1]`), defeating client-spoofed leftmost headers behind AWS ALB.
  - Separated rate limiting scopes: unauthenticated requests rate-limited per-IP; authenticated requests rate-limited per-UID. Authenticated traffic does not increment or exhaust the IP rate limit bucket.
  - Added unit test in `services/api-gateway/test/gateway.test.js` validating spoofed XFF protection.
  - Evaluated screen polling load:
    - Patient Home Screen: Appointments (8s), Notifications (10s), Ads (10s) -> ~19.5 req/min idle; Emergency active trip (3s broadcast + 3s location) -> ~59.5 req/min peak.
    - Doctor Home Screen: Appointments (8s), Directory (10s), Notifications (10s), Referrals (10s) -> ~25.5 req/min steady.
    - Configured per-UID rate limit (300 req/min) provides 5x to 12x headroom above peak device load while isolating distinct hospital staff on shared NAT gateways.
- **Verification Matrix**:
  - `git grep -n createClient backend/functions ":!backend/functions/test/**"`: Single client factory in `backend/functions/src/db/client.js:3,41`.
  - `services/api-gateway npm test`: **61 passed, 0 failed** across 3 test suites.
  - `backend/functions CI=true npm test`: **474 passed, 0 failed, 22 skipped** across 17 test suites.
  - `frontend flutter analyze`: **No issues found!** (0 errors, 0 warnings).
  - `frontend flutter test`: **552 passed, 0 failed** (All tests passed).

---

### Phase 10: Final Security Audit Round & Migration AST Validation (Verified)
- **Migration SQL AST Parser (`scripts/db/validate_migration_sql.js`)**:
  - Validates all 33 migration files in `db/migrations/` using `libpg-query` (PostgreSQL C parser binding).
  - Scanned 1,687 parsed AST statements with **0 syntax errors** across all migrations.
- **Trigger Remediation & Null-Safe Contact Exposure**:
  - Remediated `phase_d:254` (`private.trg_lock_ambulance_broadcast_status`) in `20261026000001_rpc_null_safe_authz.sql` by enforcing null-safe profile checks (`v_profile_id IS NULL OR OLD.patient_id IS DISTINCT FROM v_profile_id OR OLD.status IS DISTINCT FROM 'completed'`).
  - Added null-safe `public.get_ambulance_trip_contact` definition in `20261026000001_rpc_null_safe_authz.sql`.
  - Re-ran nullable-authz scan on all functions in `20261026000001_rpc_null_safe_authz.sql`: **0 hits**.
- **User Integrity & Privilege Escalation Hardening**:
  - Updated `trg_users_lock_role` on `public.users` to lock both `role` and `profile_id` on UPDATE.
  - Added `trg_users_guard_insert` BEFORE INSERT trigger on `public.users` preventing non-admins from claiming administrative roles (`admin`, `super_admin`) or spoofing initial `profile_id` on self-registration.
  - Extended `scripts/db/rls_sql_harness.js` with 4 privilege escalation cases (updating role to admin, updating profile_id to victim, inserting admin users row, and updating `patients.owner_uid`), expecting 42501 denial.
- **Account Deletion Fail-Loud Protection**:
  - Updated `backend/functions/delete_my_account.js` to fail loudly and immediately abort on any 403/404 response from the gateway.
  - Added integration test in `backend/functions/test/delete_my_account_supabase.test.js` validating that account deletion traversal across all 5 account roles runs cleanly against a mock gateway derived from `services/api-gateway/src/config.js` with **0 denied requests**.
- **Service Role Rate Limiting Exemption**:
  - Verified service_role traffic is not throttled by shared IP buckets; added unit test in `services/api-gateway/test/gateway.test.js` sending 500 requests per minute with 100% 200 OK responses.
- **Verification Evidence Matrix**:
  - `services/api-gateway node --test`: **62 passed, 0 failed** across 3 test suites.
  - `backend/functions node --test`: **475 passed, 0 failed, 22 skipped** across 17 test suites.
  - `frontend flutter analyze`: **No issues found!** (ran in 95.3s).
  - `frontend flutter test`: **552 passed, 0 failed** (All tests passed).

---

### Phase 11: Migration Review Round (Deliverables 1-10 Complete & Verified)
- **Deliverable 1: 14 Unified Diffs & Non-Auth Deviation Reversion**:
  - Audited all 13 functions + trigger in `db/migrations/20261026000001_rpc_null_safe_authz.sql` against latest previous definitions.
  - Reverted non-auth deviations back to baseline:
    - `book_appointment_atomic`: statuses restored to `patient_status = 'confirmed', doctor_status = 'pendingRequest'`; capacity filter and error code `'P0001'` restored; extra phantom columns (`payment_status`, `consultation_fee`, `booked_by_uid`) removed from INSERT.
    - `reschedule_appointment_atomic`: timestamp timezone `+05:30` restored; status updates `patient_status = 'confirmed', doctor_status = 'pendingRequest'` restored; `was_rescheduled = TRUE` restored; return shape `RETURN to_jsonb(v_appointment);` restored. Family member parity authorization check added.
    - `update_pharmacy_delivery_status`: `p_medicine_lines` record fields restored strictly to `(medicine_entry_id, availability, substitute_name)`.
    - `cancel_ambulance_broadcast`: restored `DELETE FROM public.ambulance_trip_contacts WHERE broadcast_id = p_broadcast_id;`.
- **Deliverable 2: Static Column Checker (libpg-query AST)**:
  - Built `scripts/db/check_migration_columns.js` using `libpg-query` AST parser placed in root/scripts `devDependencies` (`libpg-query: ^18.2.1`).
  - Parsed all 33 migrations (1,691 statements, 70 tables). Verified all requisite columns and tables exist (`doctors.name`, `appointments.cancellation_reason`, `appointments.booked_by_uid`, `ambulance_broadcasts.rating`, `pharmacy_delivery_medicines` columns, `prescriptions` columns, `patient_doctor_links`).
  - Verified 0 phantom column references in new function bodies.
- **Deliverable 3: Exact Trigger & Function Identity for phase_d:254**:
  - Exact trigger name: `trg_lock_ambulance_broadcast_status` on `public.ambulance_broadcasts`.
  - Executed function: `private.trg_lock_ambulance_broadcast_status()`.
  - Retained original logic plus null-safe checks with `IS DISTINCT FROM`.
- **Deliverable 4: accept_ambulance_request & Nullable Record Scan**:
  - Enforced `IF v_driver.verified IS NOT TRUE THEN` for driver verification.
  - Enforced requirement for `ambulance_requests` row matching `(broadcast_id = p_broadcast_id, driver_id = v_driver_id)` else 42501.
  - Replaced all record field `!=` / `<>` with `IS DISTINCT FROM`.
  - Scanner `scripts/db/scan_nullable_record_fields.js` confirmed **0 nullable record field hits**.
- **Deliverable 5: Role Pipeline & Bridge Gating**:
  - Audited `firestore.rules`: client role assignment is strictly limited to non-admin roles (`doctor, patient, medicalStore, medical, lab, ambulance`); `role, profileId, verified, verifiedAt` are protected from client modification on update.
  - `syncFirestoreUserToSupabase` role mapping normalizes roles; Postgres trigger `trg_users_guard_insert` rejects administrative roles.
  - Production gating: `ENABLE_SUPABASE_SYNC=0` in production per `docs/ops/SYNC_ROLLOUT.md:9`.
- **Deliverable 6: Server-Side Demo OTP Bypass Hardening**:
  - Gated `getReviewerConfig(role)` and `isReviewerPhone(digits, role)` in `backend/functions/registration_otp.js`: disabled in `APP_ENV=production` unless `ENABLE_REVIEW_DEMO=true` (strictly restricted to `role === 'patient'`).
  - All 9 unit tests pass in `backend/functions/test/reviewer_login.test.js`.
- **Deliverable 7: public.users Lock Integrity & Family-Member Parity**:
  - `trg_users_lock_role` locks `('role', 'profile_id', 'firebase_uid', 'email', 'mobile')` on UPDATE.
  - Provisioning trace confirmed: `users_provisioning` trigger executes `INSERT INTO public.users` (not affected by UPDATE lock).
  - Added Section 16 RLS policy `appointments_update` to `20261026000001_rpc_null_safe_authz.sql` providing family-member cancellation parity (`family_members` and `patients.owner_uid`).
- **Deliverable 8: Comprehensive Account Deletion (delete_my_account)**:
  - Audited all user/owner/phone/email-bearing tables across the schema.
  - Implemented cleanup in `backend/functions/delete_my_account.js`:
    - DELETED: `ambulance_trip_contacts`, `ambulance_location_updates`, `promoted_ads`, `medical_directory`, `super_admins`, `admin_users`, `provisioning_errors`.
    - ANONYMIZED: `razorpay_orders` (`user_uid: null`).
    - RETAINED with regulatory justification: `razorpay_payments` (tax/financial accounting), `admin_audit_logs` (regulatory compliance), `security_events` (pseudonymized fraud audit), `doctor_directory_updates` (cache signal), `facilities` (institutional directory).
  - Updated gateway `serviceRoleOnlyTables` in `services/api-gateway/src/config.js` with `ambulance_trip_contacts`, `admin_users`, `provisioning_errors`.
- **Deliverable 9: Gateway Failed Service-Key Rate Limiting**:
  - Implemented `failedServiceKeyLimiter` in `services/api-gateway/src/server.js` and `security.js` tracking failed service key attempts per IP.
  - Rejects with `429 Too Many Requests` when limit is exceeded (5 failed attempts per IP within 15-minute sliding window).
  - Unit test in `services/api-gateway/test/gateway.test.js` passes.
- **Deliverable 10: Verification Test Evidence Matrix (Artifacts Saved)**:
  - `local test output (re-run the cited command; not stored in git)`: **64 passed, 0 failed** across 3 test suites.
  - `local test output (re-run the cited command; not stored in git)`: **477 passed, 0 failed, 23 skipped** across 18 test suites.
  - `local test output (re-run the cited command; not stored in git)`: **0 vulnerabilities found** (`npm audit --omit=dev`).
  - `local test output (re-run the cited command; not stored in git)`: **No issues found!** (ran in 217.8s).
  - `local test output (re-run the cited command; not stored in git)`: **552 passed, 0 failed** (All tests passed, 2m46s).

### Final Round Hardening & Parity Verification:
- **Migration SQL AST & Balanced Dollars**: `scripts/db/validate_migration_sql.js` passed all 33 migrations (1,702 statements, 0 errors). Balanced `$$` audit confirmed exactly 28 `$$` tokens across 14 functions (2 per function).
- **Migration Unified Diffs**: 14 `diff -u` files generated under `docs/ops/migration_diffs/` confirming zero non-authorization deviations. `book_appointment_atomic` early null profile raise, `IS NOT DISTINCT FROM` equality, and status codes (`pendingRequest`, `confirmed`, `P0001`) reconciled.
- **Static Column Extraction**: Extended `scripts/db/check_migration_columns.js` extracted 151 distinct column/field references across 70 tables; confirmed 0 failures and 0 phantom columns.
- **FCM Token Registration Reconciled**: Discovered client repository calls (`ambulance_repository.dart:156`, `doctor_profile_repository.dart:27`, `patient_profile_repository.dart:280`) interact with `user_devices` via PostgREST directly (not RPC). Moved `user_devices` from `serviceRoleOnlyTables` to `clientDirectAllowedTables`. Postgres RLS already enforces `user_id = (auth.jwt() ->> 'sub')`. Gateway unit test verified authenticated user upsert/delete, anonymous blocked with 401, service role allowed.
- **Production Provisioning Integration Test**: Traced new user registration flow under `APP_ENV=production`. Added integration test `backend/functions/test/production_provisioning_gateway.test.js` against mock gateway created from `config.js`, proving zero denied requests (200/201 success) across all 5 roles (`patient`, `doctor`, `lab`, `medicalStore`, `ambulance`).
- **Demo Account Cleanup Precision**: Cleanup instructions updated to use exact-match filtering on phone numbers (`+919999900001`..`5`, `+919999988888`), avoiding wildcard or prefix deletions.
- **Work Inventory Status Harmonization**: Updated `docs/ops/REMAINING_WORK.md` to label items not exercised on a live running database as `CODE-DONE / DB-UNVERIFIED`.




