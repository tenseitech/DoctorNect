# DoctorNect database migration status

**Branch:** `fix/pre-accept-gate-lab-auth` (ahead of `origin` by 2 local commits; working tree dirty this session)  
**Audit time:** 2026-11-15  
**Evidence:** file paths / command output in this repo; live RDS/Supabase state marked **UNVERIFIED** where no connection was made.

---

## Overall completion: **~85%**

| Area | Weight | Score | Notes |
|------|--------|------:|-------|
| Firestore removal | 35% | **90%** | **Client SDK grep = 0** — `docs/audit/FIRESTORE_GREP_INDEPENDENT.txt`. Backend strip **STOPPED** (regression reverted); **141 grep lines** classified post-release — `docs/audit/BACKEND_RECOVERY_STOP_STRIP.md`. Prod guard: `FIRESTORE_FORBIDDEN=1` + `legacy_db` null. |
| Postgres / RDS | 25% | **82%** | `pg_pool.js` production fail-fast + RDS CA; tests green |
| Staging Supabase isolation | 15% | 78% | Prod client: **Auth Gateway** PostgREST (`PROD_GATEWAY_*`), not `*.supabase.co` |
| Redis / S3 | 10% | 85% | `s3_storage.js` Firestore fallback still in Functions |
| Env / secrets policy | 10% | 92% | `npm run env:verify` green |
| Build & unit tests | 5% | **100%** | `backend/functions`: **551 pass / 0 fail** (~26s) — `docs/audit/npm_test_post_otp_guard.txt`; OTP Lua lockout + prod guard suite; `flutter test`: **677 pass** |

**Formula:** `Σ(weight × score)` ≈ `0.35×88 + 0.25×82 + …` → **~85%** (client Firestore SDK removed).

**Scanner (this session):** `git diff scripts/audit/scan_firestore_release_reachability.js` = **empty** (rules unchanged since `4f1e3ea`). Row drop **138 → 37** = fewer matching app lines (migrations to Supabase/`AppDataService`) + more `DEAD_IN_RELEASE`, not scanner rule edits.

---

## Module matrix (Doctor / Patient / Pharmacy / Lab / Ambulance)

| Module | Auth | DB reads | DB writes | Storage | Cache |
|--------|------|----------|-----------|---------|-------|
| **Doctor** | DONE | **DONE** (release: 0 LIVE_AND_THROWS) | **DONE** via repositories | DONE | DONE |
| **Patient** | DONE | **DONE** (release scan) | PARTIAL (support tickets still Firestore code — dead path) | DONE | DONE |
| **Pharmacy** | DONE | **DONE** (release scan) | **DONE** via `AppDataService` | DONE | DONE |
| **Lab** | DONE | **DONE** | **DONE** | DONE | DONE |
| **Ambulance** | DONE | TODO in UI (routes gated `AMBULANCE_ENABLED=false`) | PARTIAL (callables still accept legacy Firestore param name `firestore`) | DONE | DONE |

**Auth DONE** = Firebase Auth + MSG91 OTP (`registration_otp.js`, `backend/functions/index.js` callables).  
**PARTIAL** = primary path is Postgres (Supabase staging / Auth Gateway production) but Firestore wrappers or dual-write bridge code remains.

---

## Client data path (AppDataService / `*Repository`)

**Architecture today (verified in code):** Flutter uses **`supabase_flutter`** → HTTPS PostgREST with Firebase ID token. **Not** `Client → Cloud Function → pg_pool → RDS` per entity.

| Layer | Staging | Production |
|-------|---------|------------|
| HTTP base | `SUPABASE_URL` = staging Supabase / pooler | `SUPABASE_URL` = **`PROD_GATEWAY_URL`** (Auth Gateway PostgREST on RDS) |
| Auth header | Firebase ID token | Firebase ID token |
| SQL execution | Supabase Postgres | RDS (behind gateway) |
| Cloud Functions `pg_pool` | Optional / DLQ / scripts | Direct SQL for server jobs only |

| File (gateway) | Production data source | Staging data source |
|----------------|------------------------|---------------------|
| `app_data_service.dart` | Composes Postgres repos below | Same |
| `doctor_profile_repository.dart` | → `SupabaseDoctorRepository` (PostgREST) | Same URL = Supabase |
| `patient_profile_repository.dart` | → `SupabasePatientProfileRepository` | Same |
| `appointment_repository.dart` | → `SupabaseAppointmentRepository` | Same |
| `lab_order_repository.dart` | → `SupabaseLabRepository` | Same |
| `prescription_repository.dart` | → `SupabasePrescriptionRepository` | Same |
| `review_repository.dart` / `medical_directory_repository.dart` | → matching `Supabase*` | Same |
| `ambulance_repository.dart` | **Mixed** — callables + legacy Firestore branches | Mixed |
| `promoted_ads_service.dart` / admin | **Firestore** (`FirestoreClient`) — not production-safe | Same |

**Implication:** Production is **not** exposing RDS to the client; it exposes **Auth Gateway PostgREST**. Migrating off `supabase_flutter` to a bespoke HTTP API would be a **separate** project; current cutover target is gateway URL + no Firestore.

---

## 1. Firestore remnants

### 1.1 Config / rules / CI

| Item | Path | Status |
|------|------|--------|
| Firestore rules deployed config | `firebase.json` | **DONE** — `firestore` section removed |
| Rules body | `backend/firestore.rules` | **DONE** — deny-all (deployed rules file retained; client blocked) |
| Indexes | `backend/firestore.indexes.json` | **DONE** — deleted |
| Emulator / rules tests | `package.json:6-7`, `backend/functions/package.json` `test:rules`, `test:firestore-*` | **TODO** (test-only but keeps Firestore dependency) |
| Storage rules (Firebase) | `firebase.json:6-8`, `backend/storage.rules` | **TODO** (S3 is primary; Firebase Storage rules legacy) |

### 1.2 Feature flags (current template defaults in `.env.example`)

| Flag | Default | Effect |
|------|---------|--------|
| `FIRESTORE_FORBIDDEN` | `1` | `legacy_db.js` returns `null`; client guard throws on `FirestoreClient` |
| `ENABLE_SUPABASE` | `1` | Flutter initializes Supabase/PostgREST client |
| `ENABLE_SUPABASE_SYNC` | `0` | Firestore→Supabase bridge triggers **off** |
| `isDoctorPatientSupabasePrimary()` | always `true` | `backend/functions/sync_flags.js:47-51` — no Remote Config; Postgres primary |
| `AMBULANCE_ENABLED` | `false` | Ambulance UI not mounted in release |

### 1.3 Backend runtime (non-test, representative)

| File | Lines (sample) | Module |
|------|----------------|--------|
| `backend/functions/index.js` | 10, 185-186, 277-343, 460-843, 801-802, 1212-1296 | Auth, ambulance invite fallback, OTP |
| `backend/functions/registration_otp.js` | 6, 502+, 671+ | Auth / OTP |
| `backend/functions/s3_storage.js` | 7, 789, 1464-1465 | Storage / health_records Firestore fallback |
| `backend/functions/cross_role_sync.js` | 20-21, 80-82 (DLQ Firestore fallback) | Sync bridge (legacy) |
| `backend/functions/abuse_rate_limit.js` | FieldValue paths when `RATE_LIMIT_BACKEND=firestore` | Auth |
| `backend/functions/delete_my_account.js` | mixed | All modules |
| `backend/functions/legacy_db.js` | 4-15 | Shared |
| `backend/functions/firestore_forbidden_guard.js` | guard | Shared |

**Cloud Functions:** No `onDocumentWritten` / `sync*ToSupabase` exports in `index.js` (comment at `index.js:1314`). Triggers removed from deploy surface.

### 1.4 Frontend release reachability

Generated: `node scripts/audit/scan_firestore_release_reachability.js` → `docs/audit/FIRESTORE_REACHABLE_RELEASE.md`

| Class | Count |
|-------|------:|
| LIVE_AND_THROWS | **0** |
| DEAD_IN_RELEASE | 32 |
| TEST_ONLY | 5 |

**Full LIVE_AND_THROWS list:** see `docs/audit/FIRESTORE_REACHABLE_RELEASE.md` (table `file:line | module | …`). Regenerate after further client migrations.

**Modules with LIVE paths (doctor/patient/pharmacy/lab):** doctor profile, medical directory, patients service, clinical loaders, referrals, availability, patient doctor profile, pharmacy screens, lab profile/walk-in, notifications, invites, `firebase_bootstrap.dart`, etc.

---

## 2. Supabase in production paths

| Concern | Evidence | Severity |
|---------|----------|----------|
| Production DB API | `assert_app_env.js:27-52` requires `PROD_GATEWAY_URL` + `PROD_GATEWAY_SERVICE_KEY`; rejects `*.supabase.co` as prod gateway | **LOW** (guard present) |
| Direct Postgres URL in functions | `getPgPool()` **was** staging-first (`cross_role_sync.js`); **fixed** to `src/db/pg_pool.js` APP_ENV routing | **MEDIUM** → mitigated |
| `cross_role_sync.js` PostgREST | `getSupabaseConfig()` uses gateway in production (`cross_role_sync.js:27-35`) | **OK** (PostgREST over RDS) |
| Flutter `supabase_flutter` | Staging + production builds use PostgREST with Firebase JWT — not Supabase Auth | **OK** per target arch |
| Supabase-only SQL | RLS, `auth.uid()`, `pg_cron` in `db/migrations/*` | **MEDIUM** — RDS overrides under `db/migrations/rds/` + `db/rds_overrides/` |
| Edge `sync-to-firestore` | `backend/supabase/functions/sync-to-firestore/` | **HIGH** — reverse bridge; cutover should not need it |
| Deployed function env drift | `docs/archive/verification/ARCHITECTURE_AUDIT_REPORT.md` (44 functions stale ref) | **MEDIUM** — **UNVERIFIED** on live GCP today |

---

## 3. RDS readiness

| Item | Status | Proof |
|------|--------|-------|
| Migration runner | **DONE** | `scripts/db/migrate.js` (ledger, checksums, staging vs production targets, `libpg-query` split) |
| Ordered migrations | **DONE** | `db/migrations/` — 58 versioned files; RDS-specific: `db/migrations/rds/20261113000001_rds_system_admin_and_audit.sql` |
| SSL / CA | **DONE** in scripts | `scripts/lib/rds_pool_config.js` → `infra/aws/global-bundle.pem` |
| Cloud Functions pool | **PARTIAL** | `backend/functions/src/db/pg_pool.js` (this session); **`pg` added** to `backend/functions/package.json` |
| Health check | **PARTIAL** | Gateway: `scripts/db/db_connectivity_smoke.js` hits `/healthz`; no dedicated Functions HTTP health for Postgres pool |
| PG 18.3 compatibility | **UNVERIFIED** | `PROD_PG_VERSION=18.3` in `.env.example`; run `node scripts/db/rds_readiness_probe.js` against tunnel |
| Schema parity staging vs RDS | **UNVERIFIED** | `node scripts/db/schema_diff.js` (not run — no prod tunnel in audit) |
| Migrations applied on RDS | **UNVERIFIED** | requires operator `node scripts/db/migrate.js --target production` |

### Data migration Firestore → Postgres

| Script | Purpose | Complete? |
|--------|---------|-----------|
| `backend/scripts/backfill_users_to_supabase.js` | Users → `public.users` | **PARTIAL** — Firestore source; dry-run/apply |
| `backend/scripts/backfill_supabase_custom_claims.js` | Auth claims | **PARTIAL** |
| `backend/scripts/backfill_doctor_slots.js` | Slots from Firestore | **LEGACY** |
| `backend/scripts/reverse_sync_supabase_to_firestore.js` | Reverse bridge | **Should deprecate** |

Note: testing data only; no production user cutover in scope.

---

## 4. Redis

| Item | Path |
|------|------|
| Client | `backend/functions/src/config/redis.js`, `redis.js` |
| OTP mirror | `OTP_REDIS_MIRROR=on`, tests `otp_retry_fallback.test.js` |
| Rate limits | `RATE_LIMIT_BACKEND=redis`, `abuse_rate_limit.js` |
| Production TLS guard | `assert_app_env.js` `assertProductionRedisTls` |
| Permanent data in Redis only? | **No** — OTP challenges, rate limits, URL cache (`S3_URL_CACHE`); not sole source of truth for domain entities |

---

## 5. S3

| Item | Status |
|------|--------|
| Callables | `backend/functions/s3_storage.js` |
| Env | `S3_BUCKET_STAGING`, `S3_BUCKET_PRODUCTION`, `USE_S3_STORAGE=true` |
| Firebase Storage | Rules in `backend/storage.rules`; CSP still allows `firebasestorage.googleapis.com` in `firebase.json:174` |
| Supabase Storage | **No** active app usage found in frontend |

---

## 6. Env / secrets

| Check | Result |
|-------|--------|
| Allowed env files | `.env` (gitignored) + `.env.example` only — `scripts/env/verify_env_file_policy.js` |
| Key parity | 130 keys — `verify_env_key_parity.js` **PASS** |
| Committed secrets scan | `guard_env_example_secrets.js` **PASS** |
| Git history scan | **NOT RUN** this session — use `node scripts/audit/pre_push_history_scan.js` before push |
| Hardcoded credentials in repo | **UNVERIFIED** full history; workspace `.env` present locally (not read for audit) |

Unused / duplicate highlights: legacy aliases documented in `check_env_parity.js` (`SUPABASE_SECRET_KEY` → `SUPABASE_SERVICE_ROLE_KEY`, etc.).

---

## 7. Tests / build (this session)

| Command | Result |
|---------|--------|
| `cd backend/functions && npm test` | **551 pass, 0 fail**, 17 skipped (~26s) — `npm_test_post_otp_guard.txt` |
| `npm run env:verify` (repo root) | **PASS** |
| `npm run build` (functions) | **NOT RUN** separately; `node --check` part of `npm run build` in package.json |
| Flutter `analyze` / `test` | **NOT RUN** (time budget) |
| Firestore emulator rules suites | **NOT RUN** (require Firebase emulators) |

---

## Blockers & risks

| ID | Severity | Description |
|----|----------|-------------|
| B1 | **CRITICAL** | **79→~74** client `LIVE_AND_THROWS` Firestore paths — user-visible `StateError` on doctor/patient/pharmacy/lab flows |
| B2 | **CRITICAL** | `firebase.json` still deploys Firestore rules/indexes — violates “Firestore completely removed” |
| B3 | **HIGH** | `cross_role_sync.js` + `s3_storage.js` still contain Firestore reads/writes and DLQ fallback |
| B4 | **HIGH** | Production RDS migration apply **UNVERIFIED** — cutover blocked until `migrate.js --target production` succeeds |
| B5 | **HIGH** | `pg` was missing from Functions `package.json` — **fixed this session**; redeploy required |
| B6 | **MEDIUM** | Supabase-specific migrations / `pg_cron` — must use RDS overrides; staging-only files skipped per `shouldSkipMigrationFile` |
| B7 | **MEDIUM** | Data backfill scripts still Firestore-sourced |
| B8 | **LOW** | `ENABLE_SUPABASE_DATABASE_WEBHOOK=0` — edge reverse sync dormant |
| B9 | **LOW** | Admin `features/admin/*` Firestore if super-admin opens routes (out of 5-module scope but reachable) |

---

## Priority checklist (remaining)

| # | Task | Est. |
|---|------|-----:|
| 1 | Migrate all `LIVE_AND_THROWS` Dart files to Supabase repositories (use `docs/audit/FIRESTORE_REACHABLE_RELEASE.md` as backlog) | 3–5 d |
| 2 | Remove Firestore from `firebase.json`, delete/stop deploying rules & indexes; drop `cloud_firestore` from Flutter when references = 0 | 0.5 d |
| 3 | Strip Firestore from `s3_storage.js`, `registration_otp.js`, `index.js` callables (Postgres-only OTP + invites) | 1–2 d |
| 4 | Delete or gate `cross_role_sync.js` / `sync-to-firestore` edge function | 1 d |
| 5 | Apply `node scripts/db/migrate.js --target staging` then production tunnel + `--target production` | 0.5 d |
| 6 | Run `schema_diff.js` + `rds_readiness_probe.js`; fix drift | 0.5 d |
| 7 | Run Firestore→Postgres backfills on staging; retire Firestore scripts | 1 d |
| 8 | Flutter `flutter test` + release build with production dart-defines (`PROD_GATEWAY_*`) | 0.5 d |
| 9 | Redeploy Cloud Functions with `pg` dep + `pg_pool` routing | 0.25 d |

---

## Work completed this session (PART 3)

1. **`backend/functions/src/db/pg_pool.js`** — APP_ENV-aware pool (staging Supabase DB URL vs production `DATABASE_URL` / `PROD_RDS_*`).
2. **`cross_role_sync.js`** — uses shared pool module (no staging URL leak in production).
3. **`pg` dependency** added to `backend/functions/package.json`.
4. **`lab_order_store.dart`** — uses `LabOrderRepository` + `PatientProfileRepository` (removes 5 `LIVE_AND_THROWS` lines).
5. **`.env.example`** — `PG_POOL_MAX`, `PG_POOL_IDLE_MS`, `PG_POOL_CONNECT_MS`.
6. **`scripts/test/rds_scratch_replay.test.js`** — placeholder RDS host for infra fingerprint guard.
7. **`backend/functions/test/pg_pool_routing.test.js`** — routing unit tests.

---

## MANUAL STEPS FOR YOU

### A. Staging — backup + migrations

```powershell
cd C:\Users\khije\Downloads\DoctorNect\doctor
# Ensure .env: APP_ENV=staging, STAGING_SUPABASE_DB_URL=... (session pooler :5432)
node scripts/db/migrate.js --target staging --dry-run
node scripts/db/migrate.js --target staging
node scripts/db/schema_diff.js --target staging
```

### B. RDS network: Cloud Functions → Postgres

**Recommendation (pick one):**

1. **Preferred:** Functions **do not** open direct RDS. Use **Auth Gateway (PostgREST)** + `DATABASE_URL` only on gateway/ECS; Functions call gateway REST (already `getSupabaseConfig()` in production).
2. **If Functions need direct SQL (DLQ, batch):** RDS in **private subnet** + **VPC connector** on Cloud Functions (same region `ap-south-1`) + security group allowing **only** connector CIDR → RDS:5432 + TLS `verify-full` (`PROD_RDS_*` / hardened `pg_pool.js`).
3. **Operator scripts:** SSM port forward / bastion tunnel (`PROD_RDS_CONNECT_HOST=127.0.0.1`) — **not** for runtime Functions.

### C. Production RDS — tunnel + migrations (no DROP/TRUNCATE)

See `docs/runbooks/RDS_PROD_TUNNEL_WINDOWS.md`. Example:

```powershell
# Start SSM/SSH tunnel so PROD_RDS_CONNECT_HOST=127.0.0.1 PROD_RDS_PORT=5433
$env:APP_ENV='production'
node scripts/db/db_connectivity_smoke.js
node scripts/db/migrate.js --target production --dry-run
node scripts/db/migrate.js --target production
node scripts/db/rds_readiness_probe.js
```

### D. Cloud Functions redeploy (after merge)

```powershell
cd C:\Users\khije\Downloads\DoctorNect\doctor
node scripts/env/materialize_functions_env.js
cd backend\functions
npm ci
firebase deploy --only functions --project medibond-45fad
node ..\..\scripts\env\cleanup_functions_env.js
```

Ensure deployed env: `APP_ENV=production`, `FIRESTORE_FORBIDDEN=1`, `PROD_GATEWAY_URL`, `PROD_GATEWAY_SERVICE_KEY`, `DATABASE_URL` (RDS, not Supabase), Redis `rediss://`, `OTP_HMAC_SECRET`, S3 buckets.

### E. Secrets / GCP / AWS

- Set Cloud Functions env: `APP_ENV=production`, `PROD_GATEWAY_URL`, `PROD_GATEWAY_SERVICE_KEY`, `DATABASE_URL` (or full `PROD_RDS_*`), `FIRESTORE_FORBIDDEN=1`, Redis TLS URLs, S3 buckets, `OTP_HMAC_SECRET`, MSG91 keys (Secret Manager).
- RDS security group: allow tunnel/bastion only; SSL `verify-full` with `infra/aws/global-bundle.pem`.
- **Redeploy functions** after this branch: `firebase deploy --only functions` (from repo with materialized env).

### D. Firebase console

- When client migration complete: disable Firestore API / remove rules deploy from release pipeline.
- Keep **Authentication** + App Check; remove Firestore from client apps in Firebase console when usage is zero.

### E. Data backfill (staging test data)

```powershell
node backend/scripts/backfill_users_to_supabase.js
node backend/scripts/backfill_users_to_supabase.js --apply
```

### F. Pre-push security

```powershell
node scripts/audit/pre_push_history_scan.js
```

---

## OPEN QUESTIONS

| Topic | Question | Default in code | Owner |
|-------|----------|-----------------|-------|
| Slot capacity | Product wants **1 patient per slot** (race script expectation) or **3** (current RPC + JS)? | **3** — `appointment_slots.js` `MAX_PATIENTS_PER_SLOT`, SQL `SLOT_CAPACITY_REACHED … capacity of 3` | **main** (product) |

## GO / NO-GO (release blockers — 2026-11-15)

| # | Gate | Status | Owner | Evidence |
|---|------|--------|-------|----------|
| 1 | OTP Redis lockout + parallel brute cap | **PASS** | Cursor | `reserveOtpVerifyAttemptSlot` Lua (re-applied) — `otp_redis_integration_only_6390.txt`, `otp_lockout_root_cause.txt` |
| 2 | Slot capacity rule documented | **PASS** (code=3) | main decides | `backend/functions/appointment_slots.js:6`, `db/migrations/20261026000001_rpc_null_safe_authz.sql` |
| 3 | Production boot guards (`APP_ENV`, `FIRESTORE_FORBIDDEN`, DB/gateway/Redis/MSG91) | **PARTIAL** | Cursor + **main** | `runtime_firestore_blocked` + legacy entrypoint suite **PASS** — `production_legacy_firestore_guard_test.txt`; deploy env **UNVERIFIED** on live Firebase |
| 3b | Legacy `bookAppointment` / webhooks | **PASS** (path map) | Cursor | Client: Supabase RPC primary (`shared_appointments_store.dart:863-889`); callable fallback if cutover off. `razorpayWebhook` HTTP export `index.js:1304` — Razorpay → Postgres (`phase_e3_razorpay_ads.test.js`, `docs/audit/razorpay_webhook_pg_test.txt`) |
| 4 | Production AAB (no `-AllowStaging`) | **FAIL** | **main** | `release_build_prod_skipinc.txt` — preflight blocked (`APP_ENV=staging` + supabase.co URL); set prod gateway defines per `MANUAL_STEPS.md` |
| 5 | Gateway rate limit / CORS; RDS TLS/SG | **PARTIAL** | Cursor + **main** | Staging gateway reads OK (`db_connectivity_smoke_staging.txt`). AWS RDS CLI **AccessDenied** (`aws_rds_cli_access_denied.txt`); live SG/TLS **UNVERIFIED** |
| 6 | Client Firestore SDK grep = 0 | **PASS** | Cursor | `docs/audit/FIRESTORE_GREP_INDEPENDENT.txt` (0 matches); `pubspec.yaml` has no `cloud_firestore` |
| 6b | Client `flutter analyze` / full test | **PASS** | Cursor | **0 warnings**; **677 pass / 0 fail** — `flutter_analyze_post_firestore_strip.txt`, `flutter_test_full_post_firestore_strip.txt` |
| 6c | Release dry-run (prod profile) | **PASS** | Cursor | `FIRESTORE_FORBIDDEN` in defines; dry-run — `release_build_dryrun_post_firestore_strip.txt` |
| 7 | Staging migrations `20261115000001` + live write smoke | **PASS** | Cursor + **main** | Write smoke **staging** `staging_e2e_write_flow_staging_run3.txt` (all steps rows≥1 + tagged cleanup). Hardening applied per operator |
| 8 | Live prod gateway / RDS wire | **UNVERIFIED** | **main** | Tunnel down (`prod_rds_preflight_readonly.txt`); `/healthz` **UNVERIFIED** (`db_connectivity_smoke_production.txt`) |

**Release recommendation:** **NO-GO** until prod AAB full Gradle on operator machine, Firebase production env materialized (`APP_ENV`/`FIRESTORE_FORBIDDEN`), and staging hardening migration + live write smoke (**UNVERIFIED**). Backend Firestore grep **not** a blocker when guard + `FIRESTORE_FORBIDDEN=1` (strip deferred post-release).

---

## RELEASE GATE (2026-11-15 — proof or UNVERIFIED)

| Gate | Status | Evidence |
|------|--------|----------|
| Authoritative runtime grep `firestore` = 0 | **POST-RELEASE** | **141 lines** — `docs/audit/BACKEND_RUNTIME_FIRESTORE_GREP.txt`; prod **NOT-REACHABLE** with guard — `BACKEND_RECOVERY_STOP_STRIP.md` |
| `backend/functions/src` grep (subset) | **PASS** | **0 lines** — `docs/audit/BACKEND_SRC_FIRESTORE_GREP.txt` |
| Production imports `test/lib` | **PASS** | `docs/audit/VERIFY_NO_TEST_IMPORTS.txt` — functions runtime clean; backfill → `user_supabase_payload.js` |
| `npm test` (Functions) | **PASS** | **551 pass / 0 fail / 568 tests** (17 skipped emulator, ~26s) — `docs/audit/npm_test_post_otp_guard.txt` |
| Production legacy Firestore guard | **PASS** | 5/5 — `docs/audit/production_legacy_firestore_guard_test.txt` (`APP_ENV=production`, `FIRESTORE_FORBIDDEN=1`) |
| `backend/functions/test` firestore grep (separate) | **INFO** | see audit when re-run |
| `backend/functions/scripts` firestore grep | **INFO** | see audit when re-run |
| API Gateway unit tests | **PASS** | `services/api-gateway` → 68 pass (token verify, 401 anon, forged header rejected) |
| RLS inventory (migrations) | **PASS** | `node scripts/audit/rls_table_inventory.js` → 67 tables, **0** without `ENABLE RLS` in SQL |
| RDS replay migrations (PG17 `:5440`) | **PASS** | **62 migrations / 1546 statements / 0 failures** — `docs/audit/rds_scratch_replay_5440_rerun.txt` (incl. `20261115000001`–`003` + RDS overrides) |
| Gateway RLS + admin escalation matrix (PG `:5440`) | **PASS** | **60 PASS / 0 FAIL** — `docs/audit/gateway_rls_authorization_suite_5440.txt`, `docs/reports/gateway_rls_authorization_suite.json`; migration `20261115000001_harden_super_admin_no_jwt_email_bypass.sql` removes email-only admin bypass |
| Staging admin bypass ledger | **PASS** | Operator: staging hardening applied; re-audit with `staging_migration_exposure_audit.js` if needed |
| Staging write-flow smoke + tagged cleanup | **PASS** | Local `staging_e2e_write_flow_local_5440.txt`; staging `staging_e2e_write_flow_staging_run3.txt` (lab seed fix + per-step row asserts) |
| Concurrent slot race (PG `:5440`) | **PASS** | **3 wins / 17 rejects** (RPC slot max=3) — `docs/audit/concurrent_slot_booking_race_5440.txt`; script `scripts/db/concurrent_slot_booking_race.js` |
| OTP Redis integration (`:6390`) | **PASS** | **1 pass / 0 fail** (lockout + 20 parallel wrong guesses) — `docs/audit/otp_redis_integration_only_6390.txt`, `otp_lockout_root_cause.txt` |
| Release AAB build | **PASS** | **~98MB** `app-release.aab` — `docs/audit/release_build_aab_proof.txt`, log `release_build_real_aab_log.txt`; **staging-permitted** (`-AllowStaging`) |
| Release build FIRESTORE_FORBIDDEN dart-define | **PASS** | Build log includes `FIRESTORE_FORBIDDEN=***`; gate — `frontend/scripts/test_release_firestore_define_gate.ps1` |
| Backend runtime Firestore inventory | **PASS (guard)** | **141 grep lines** + inventory — `BACKEND_RUNTIME_FIRESTORE_GREP.txt`, `BACKEND_RUNTIME_FIRESTORE_INVENTORY.json`; **no reachable prod I/O** under `FIRESTORE_FORBIDDEN=1` |
| Flutter release Firestore smoke | **PASS** | `docs/audit/release_firestore_forbidden_flutter_test.txt` — **19 tests** |
| npm skipped tests inventory | **PASS** | `docs/audit/npm_test_skipped_18.txt` (2 release-watch, 0 blocking emulator rules) |
| Client Firestore DEAD (release) | **PASS** | SDK removed; grep 0; compile-time `FIRESTORE_FORBIDDEN` default true |
| Client bundle: no service-role / DB password | **PASS** | `rg` on `frontend/lib` → 0 hits for `service_role` / `DATABASE_URL` / JWT-shaped secrets |
| Client Firestore SDK grep = 0 | **PASS** | `docs/audit/FIRESTORE_GREP_INDEPENDENT.txt` |
| `flutter test` / `flutter analyze` | **PASS** | **677 pass / 0 fail**; **analyze 0 issues** — `docs/audit/flutter_*_post_firestore_strip.txt` |
| Release dry-run (no `cloud_firestore`) | **PASS** | `docs/audit/release_build_dryrun_post_firestore_strip.txt` |
| PROD gateway deploy / TLS / rate limit / RDS wire | **UNVERIFIED** | Code in `services/api-gateway` + `infra/aws/ecs.tf`; live AWS not probed this session |
| `migrate.js --target production` | **UNVERIFIED** | Dry-run needs `--confirm-live-data` + tunnel; preflight `ECONNREFUSED 127.0.0.1:5433` — `prod_rds_preflight_readonly.txt` |
| `assertProductionCutoverBoot` unit tests | **PASS** | `assert_production_cutover_boot_test.txt` (dummy prod env pass/fail) |
| AWS RDS describe (CLI) | **FAIL** (access) | `aws_rds_cli_access_denied.txt` — operator IAM or console |
| `db_connectivity_smoke` staging | **PASS** | `db_connectivity_smoke_staging.txt` |

**Overall completion:** `Σ(weight×score)` → **~79%** (backend OTP path improved; client + full backend strip still open).

## Production cutover — final gate (checklist)

- [x] `FIRESTORE_REACHABLE_RELEASE.md` shows **0** `LIVE_AND_THROWS`
- [x] Client Firestore **SDK** grep on `frontend/**/*.dart` (`!build`) = **0**
- [x] `flutter analyze` 0 warnings + full `flutter test` (**677 pass**)
- [x] `backend/functions` tests green (**551 pass / 0 fail**, OTP Lua + prod guard)
- [x] `flutter analyze` 0 warnings + full `flutter test` (**677 pass**)
- [ ] `migrate.js --target production` applied; `schema_diff` clean
- [ ] `db_connectivity_smoke.js` + gateway `/healthz` OK
- [x] Staging **write** smoke (OTP → pharmacy) with SELECT proofs
- [ ] Cloud Functions redeployed with Postgres-only runtime (`FIRESTORE_FORBIDDEN=1` on deploy env; legacy Admin SDK may remain in bundle until post-release strip)

## FIRESTORE REMAINING (release: reachable vs dead)

| Area | Lines (grep) | Release reachability | Proof |
|------|-------------|----------------------|--------|
| `index.js` + callables | **many refs** | **BLOCKED in prod** | `getLegacyFirestoreDb()` → **null** when forbidden; `assertFirestoreNotForbidden` on raw Admin SDK; Postgres/gateway callables primary |
| `appointment_slots.js` | **0** | **DEAD** (deploy) | No `onDocumentWritten` export in `index.js`; booking/reschedule fail-fast to gateway RPC when cutover |
| `test/lib/cross_role_sync_bridge.js` | (test only) | **DEAD** | Not in deploy bundle; sync via Postgres triggers / gateway |
| `registration_otp.js` | ~8 | **DEAD** when `OTP_REDIS_MIRROR=on` + forbidden flag | Paths guarded by `hasLegacyDocumentDb`; `npm test` + Redis integration skip |
| `promoted_ads.js` | **0** runtime vars | **PARTIAL** | Postgres path when `!useLegacyDocumentDb`; legacy webhook branch only if mock `db.collection` injected (tests) |
| `seed_demo_accounts.js` | 8 | **DEAD** in prod | Maintenance script only; not `index.js` export |
| `fcm_push.js` / `caller_identity` | comments + legacy branch | **DEAD** on cutover | `isDoctorPatientSupabasePrimary()` → Supabase token lookup |
| `package.json` emulator scripts | 11 | **DEAD** | Dev/CI only; not Cloud Functions runtime |
| `package-lock.json` transitive | ~21 | **DEAD** (npm metadata) | `firebase-admin` dep; hot path must not `require('firebase-admin/firestore')` — grep JS still **FAIL** until stripped |
| Flutter client | 0 (SDK) | **DEAD** for app data | `cloud_firestore` removed; `FirestoreForbiddenGuard` remains |

**RDS migration fixes this session (plain PG17 `:5440`):**

1. `db/rds_overrides/20260930000002_admin_users_table.sql` — was `SELECT 1` skip; now creates TEXT `private.admin_users`.
2. `db/rds_overrides/20261008000002_super_admin_from_admin_users.sql` — joins `public.users.firebase_uid` (not `auth.users` UUID).

**Next:** prod AAB + staging migrations/smoke (operator); post-release backend grep cleanup; do **not** resume aggressive Firestore strip without green suite gate.

**Recovery doc:** `docs/audit/BACKEND_RECOVERY_STOP_STRIP.md`

---

## REAL RDS CUTOVER (operator runbook — no destructive prod from CI)

### 1. Backup (before any apply)

```bash
# From bastion with RDS connectivity (replace host/db; use IAM or Secrets Manager password — never commit)
pg_dump "postgresql://USER@HOST:5432/doctornect?sslmode=verify-full" \
  --format=custom --file="doctornect_pre_cutover_$(date -u +%Y%m%dT%H%M%SZ).dump"
```

### 2. Apply migrations (`migrate.js --target production`)

```bash
# Tunnel: SSM/bastion → RDS (see infra/aws docs)
export APP_ENV=production
# DATABASE_URL or PROD_RDS_* from secrets — not from client .env
node scripts/db/migrate.js --target production --dry-run
node scripts/db/migrate.js --target production
```

RDS replay uses `db/rds_overrides/` (e.g. TEXT `private.admin_users`, `is_super_admin` on `public.users.firebase_uid`).

### 3. Schema parity check

```sql
SELECT schemaname, tablename, rowsecurity
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY tablename;
-- Expect ENABLE RLS on app tables (inventory: scripts/audit/rls_table_inventory.js)
```

```bash
node scripts/db/schema_diff.js --target production   # when configured
```

### 4. RLS suite on RDS copy / restored snapshot

```bash
# Restore snapshot to scratch instance or use read replica clone — NOT production writes
export LOCAL_FRESH_DB_URL="postgresql://USER@RDS_SCRATCH_HOST:5432/doctornect"
node scripts/db/gateway_rls_authorization_suite.js | tee docs/audit/gateway_rls_rds_scratch.txt
```

### 5. Gateway + PostgREST deploy and connectivity

```bash
node scripts/smoke/db_connectivity_smoke.js --target production   # UNVERIFIED until tunnel
curl -fsS "https://<PROD_GATEWAY_HOST>/healthz"
# PostgREST env must keep PGRST_DB_SCHEMAS=public only (see db/postgrest/postgrest.conf, infra/aws/ecs.tf)
```

```bash
# From ECS task / bastion inside RDS SG:
psql "$DATABASE_URL" -c "SELECT 1 AS rds_ok;"
```

---

*Regenerate Firestore inventory:* `npm run audit:firestore-reachability`