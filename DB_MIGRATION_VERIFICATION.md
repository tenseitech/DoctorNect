# DB Migration Verification — DoctorNect

**Branch audited:** `fix/pre-accept-gate-lab-auth`  
**Date:** 2026-11-13 (re-audit; prior pass 2026-11-12)  
**Auditor:** Automated repo audit + live staging probes (no destructive DB ops on Supabase/RDS)  
**Target architecture:** Staging = Supabase Postgres · Production = AWS RDS Postgres · Auth = Firebase · OTP = MSG91 · Cache = Redis · Files = S3 · Scope = Doctor, Patient, Pharmacy, Lab, Ambulance (not Admin app)

---

## (a) Status summary

| # | Area | Status | Notes |
|---|------|--------|-------|
| 1 | DB touchpoints inventory | **PASS** | Documented below; single routing via `APP_ENV` + gateway |
| 2 | Environment selection | **FIXED** | Added `assertAppEnvDatabaseRouting`; see §2 |
| 3 | Staging Supabase | **PASS** | Live: PostgreSQL **17.11**, `_schema_migrations` **59** rows, **0 pending** SQL files (`migrate.js --dry-run-all --confirm-live-data` 2026-11-13) |
| 4 | Production RDS | **FAIL (network)** | Config present in `.env`; `db_connectivity_smoke --env=production` → `ECONNREFUSED 127.0.0.1:5433` (SSM tunnel down); `schema_diff` not run |
| 12 | RDS grant matrix | **PASS (staging read)** | Live compare: **64** `service_role`-only diffs (staging superset); **0** `anon`/`authenticated` diffs; **0** anon surprises local |
| 13 | Service-role paths | **PASS (local)** | `service_role_paths_test.js` — **10/10** incl. `book_appointment_atomic`, admin audit, outbox (`20261113000002`) |
| 14 | RLS coverage | **PASS (local)** | `rls_coverage_audit.js` — 67 public tables, **0** errors |
| 15 | Auth matrix (5×6 + medical) | **PASS (local)** | `gateway_rls_authorization_suite.js` — **49/49** on `doctornect_fresh_zero` (`20261113000003` support_tickets fix) |
| 16 | Real HTTP path | **PASS (local)** | `real_path_authorization_e2e.js` — PostgREST 12.2.3 + Gateway **7/7** |
| 5 | PostgREST / supabase-js on prod | **PASS*** | *By design:* prod client uses **Auth Gateway + PostgREST over RDS**, not Supabase cloud; not raw `pg` from Flutter |
| 6 | Authorization (Firebase UID) | **PASS** (design) | Gateway mints JWT → `auth.uid()` shim on RDS; RLS harness docs exist — **re-run on RDS after apply** |
| 7 | Connection pooling / SSL | **PASS** (config) | Supabase session pooler documented; RDS SSL via `global-bundle.pem` in `migrate.js` |
| 8 | Secrets in repo | **PASS*** | `scan_passwords.js`: no real private keys; 5 placeholder patterns in docs/tests only |
| 9 | Staging/prod isolation | **PASS** | `backend/functions/src/config/app_resources.js` — `getS3BucketName()` / `getRedisHost()` + `assertStagingProductionResourceIsolation()` on Functions cold start (`index.js` ~L122–134) |
| 10 | Migration tooling | **FIXED** | **58** shared `db/migrations/*.sql` + **1** RDS-only `db/migrations/rds/*.sql`; `migrate.js` applies `rds/` on `production`/`rehearsal`/`replay*` only (`scripts/lib/migration_file_list.js`) |
| 11 | Backup / health | **FIXED** | Gateway `/healthz` now checks PostgREST upstream; staging smoke script added |

**Final go/no-go for RDS production traffic:** **NO-GO** until operator runs [RDS_CUTOVER_STEPS.md](docs/runbooks/RDS_CUTOVER_STEPS.md): rehearsal migrate + `04` grants + live `schema_diff` (needs network) + VPC gateway smoke. **Staging read-only verification done 2026-11-12** after `20261113000003` (§Staging verified).

---

## Staging verified after `20261113000003` (read-only)

Operator applied `20261112000006`, `20261113000002`, `20261113000003`. Automated read-only checks (no writes):

| Check | Result |
|-------|--------|
| `grant_matrix_audit.js --compare-staging --confirm-live-data` | **64** table diffs, all `service_role` staging **≥** local (Supabase default `REFERENCES`/`TRIGGER`/`TRUNCATE`); **0** staging grant gaps for app paths |
| `anon` / `authenticated` table grants | **0** diffs vs local replay — RDS inherits migrations; `04` only re-tightens `anon` |
| `rpc_body_parity_staging.js --confirm-live-data` | **11/11** RPC bodies **normalized MATCH** vs `doctornect_fresh_zero` |
| Cached `fresh_local_vs_staging_schema_diff.json` | **11** `FUNCTION_BODY` + **1** `FUNCTION_MISSING` (`rls_auto_enable`) — stale vs current staging / catalog text noise (**not** “PG15 vs PG17”; staging is **17.11**); live RPC check supersedes |

Detail: [docs/reports/STAGING_VERIFIED_AFTER_20261113000003.md](docs/reports/STAGING_VERIFIED_AFTER_20261113000003.md).

---

## Production RDS setup (2026-11-12)

| Step | Item | Status | Notes |
|------|------|--------|-------|
| 1 | Env template (repo root `.env.example`) | **PASS** | [PRODUCTION_ENV_WIRING.md](docs/reports/PRODUCTION_ENV_WIRING.md), [ENV_CONSOLIDATION_REPORT.md](ENV_CONSOLIDATION_REPORT.md) |
| 2 | Tunnel + TLS (`RDS_PROD_TUNNEL_WINDOWS.md`, `rds_pool_config.js`) | **PASS** | `verify-full` + `servername` = `PROD_RDS_HOST` |
| 3 | CA bundle `infra/aws/global-bundle.pem` | **PENDING** | Operator download ([README_CA_BUNDLE.md](infra/aws/README_CA_BUNDLE.md)) |
| 4 | `db_connectivity_smoke.js --env=production --mode=postgres` | **FAIL (network)** | `ENOTFOUND` / timeout without tunnel; set `PROD_RDS_CONNECT_HOST=127.0.0.1` |
| 5 | `rds_readiness_probe.js` (version/extensions) | **PENDING** | After tunnel + CA + `--confirm=<PROD_RDS_HOST>` |
| 6 | `rds_bootstrap_apply.js` 01–04 | **PENDING** | **Requires your explicit OK** — not executed |
| 7 | `migrate.js --target=production` | **PENDING** | Dry-run then execute — **Requires your explicit OK** |
| 8 | Parity/tests on RDS | **PENDING** | After migrate + `04` |
| 9 | Gateway `/healthz` + PostgREST on RDS | **PENDING** | ECS/env deploy (operator) |
| 10 | RDS backup/PITR/alarms | **PENDING** | Manual AWS console checklist in runbook |

Add production RDS host fingerprint to `docs/audit/allowed_host_hashes.txt` before `--confirm-live-data` mutating runs.

---

## (b) Issues found (with paths)

### Critical / cutover blockers

1. **Staging at repo migration head** — **PASS 2026-11-13**: ledger **59** rows (**58** shared files + ghost `20261104000001` duplicate of `20261103000008`; no repo file `20261104000001_*.sql`; harmless for fresh RDS).
2. **RDS schema parity unverified on rehearsal** — `schema_diff --target=rehearsal` still requires bastion/SSM (not run here). Staging at migration head; grants/RPC logic match local replay (§Staging verified).
3. **Staging vs production PG** — Staging **17.11**; production target **18.3**. Mandatory prod gate: PG18.3 local replay (`rds_scratch_replay.js`, port **5440**). **BLOCKED 2026-11-13:** Docker Desktop engine not running (`npipe://dockerDesktopLinuxEngine` missing).
4. ~~**Windows `migrate.js --dry-run` TLS / `40D01C23`**~~ **CLARIFIED** — `40D01C23` is the **live-data guard** host fingerprint (`scripts/lib/live_data_guard.js`), not an OpenSSL error. Add `--confirm-live-data`; for apply add `--execute --confirm-staging`. `migrate.js` sets `rejectUnauthorized: false` for Supabase on Windows when needed.
5. ~~**Staging grant matrix diff**~~ **RESOLVED (read-only 2026-11-12)** — see §Staging verified; `docs/reports/grant_matrix_local.json`.
6. **Firestore server paths** — **FIXED (production template):** `FIRESTORE_FORBIDDEN=1` + `legacy_db.getLegacyFirestoreDb()`; callables use Postgres/Redis. Legacy Firestore code remains for **tests/emulator** (`__TEST_FORCE_LEGACY_DOCTOR_PATIENT=1`, `FIRESTORE_FORBIDDEN=0`). See §Firestore inventory below.
7. **Production data path is PostgREST, not direct `pg`** — Aligns with repo design (`services/api-gateway`, `backend/functions/src/db/client.js`) but differs from literal “direct Postgres connection” for apps. Direct `pg` is for **operators/migrations** only.

### Medium

6. **`assertAppEnvDatabaseRouting` skipped in tests** — `backend/functions/index.js` (~L118–128): skipped when `APP_ENV=test` or `NODE_ENV=test`; production/staging deploys must set real `APP_ENV`.
7. **Gateway allowlist drift** — **FIXED:** scanner failed on **unregistered dynamic table resolvers** (not missing tables). Added `knownNonLiteralResolvers` for `profile_completion_service.dart` (`users`, role tables) and `admin_platform_actions.js` (`roleTable()` → same 5 module tables). Root cause: dynamic `.from(table)` must be explicitly mapped to allowlisted names.
8. **Health check did not probe DB** — **FIXED** `services/api-gateway/src/server.js` (~L178–198): `/healthz` includes `postgrest` upstream status (503 if unreachable).
9. **Hardcoded staging project ref in release script** — **FIXED** `frontend/scripts/release_build.ps1` (~L163): removed hardcoded staging Supabase URL; uses `STAGING_SUPABASE_URL` / `SUPABASE_URL` only.
10. **Env template gaps** — **FIXED** env templates + `check_env_parity.js` concept groups for staging/production S3 & Redis.
14. **`db/migrations/rds/` skipped by `migrate.js` on production** — **FIXED** `scripts/lib/migration_file_list.js` + `migrate.js` (2026-11-13).
15. **`03_legacy_compat.sql` hard `GRANT … TO postgres`** — **FIXED** conditional block when role exists (`db/rds_bootstrap/03_legacy_compat.sql` ~L61–66).
16. **`infra/aws/global-bundle.pem` missing locally** — **FAIL (operator)** — required for RDS TLS verify-full.

### Low / informational

11. **`scan_passwords.js` FAIL on placeholders** — `docs/audit/STAGING_APPLY_RUNBOOK.md`, e2e test fixtures (`<password>`, `authenticator_pass`). No live secrets in git history scan (0 private keys).
12. **Duplicate `20261104000001` vs `20261103000008` staging_anon** — Staging-only ghost: Supabase `schema_migrations` row `20261104000001` is the **same SQL body** as repo `20261103000008` (only the header comment differed). There is **no** `db/migrations/20261104000001_*.sql`; fresh RDS/local replay runs `20261103000008` once. `migrate.js` no longer imports `20261104000001` from `supabase_migrations` into `_schema_migrations` (existing staging row untouched).
13. **Admin SQL migrations in shared `db/migrations/`** — `20261112000001`–`05` protect admin audit tables; required for gateway security but outside “5 modules” app scope (still apply on both DBs).

---

## 1. Where the app talks to databases

| Layer | Mechanism | Staging | Production |
|-------|-----------|---------|------------|
| Flutter client | `supabase_flutter` (`SupabaseBootstrap`, repositories) | Supabase URL + anon key | `SUPABASE_URL` dart-define = **`PROD_GATEWAY_URL`** (`frontend/scripts/release_build.ps1`) |
| Flutter streams | `supabase_stream_table.dart` | Native Realtime | Polling (`APP_ENV=production`) |
| Cloud Functions | `getDatabaseClient()` → `@supabase/supabase-js` | `STAGING_SUPABASE_*` | `PROD_GATEWAY_*` (`backend/functions/src/db/client.js:17–60`) |
| Migration / ops | `pg` Pool | `STAGING_SUPABASE_DB_URL` | `PROD_RDS_*` (`scripts/db/migrate.js`) |
| Auth Gateway | HTTP → PostgREST → RDS | N/A (staging uses Supabase PostgREST) | `services/api-gateway` |
| Legacy | Firebase **Firestore** | Emulator/tests + **server paths when `FIRESTORE_FORBIDDEN=0`** | Should be 0 in prod |
| Legacy | Firebase Storage | KYC paths; S3 cutover via `USE_S3_STORAGE` | S3 primary when enabled |

**Postgres-primary modules (5):** doctor/patient/pharmacy/lab/ambulance repos under `frontend/lib/features/*` and `frontend/lib/core/supabase/` — gated by `DoctorPatientCutoverFlag.isEnabled` (always true in release).

---

## 2. Environment switches (all variables)

| Variable | Where | Role |
|----------|-------|------|
| **`APP_ENV`** | `staging` \| `production` | **Primary switch** — Functions: `client.js`, `assert_app_env.js`; Flutter: `AppEnvironment`, `SupabaseBootstrap` |
| `STAGING_SUPABASE_URL` / `STAGING_SUPABASE_SERVICE_ROLE_KEY` | Functions | Staging PostgREST |
| `STAGING_SUPABASE_DB_URL` | `scripts/db/*` | Direct Postgres (migrations, harness) |
| `PROD_GATEWAY_URL` / `PROD_GATEWAY_SERVICE_KEY` / `PROD_GATEWAY_ANON_KEY` | Functions, Flutter prod build, smoke scripts | Production API surface |
| `PROD_RDS_HOST`, `PROD_RDS_PORT`, `PROD_RDS_DB`, `PROD_RDS_USER`, `PROD_RDS_PASSWORD`, `PROD_RDS_SSL_ROOT_CERT` | Migration scripts | Direct RDS |
| `SUPABASE_URL` / `SUPABASE_ANON_KEY` | Flutter dart-defines (staging build) | Staging client |
| `ENABLE_SUPABASE` | Release scripts | Gate Supabase defines |
| `FIRESTORE_FORBIDDEN` | Flutter + Functions | Block Firestore in client; server default still permissive |
| `S3_BUCKET_STAGING` / `S3_BUCKET_PRODUCTION` (+ legacy `S3_BUCKET`) | Functions | `app_resources.js` → `s3_bucket.js` |
| `REDIS_HOST_STAGING` / `REDIS_HOST_PRODUCTION` (+ legacy `REDIS_HOST`) | Functions | `redis.js` `resolveRedisHostForAppEnv()` |
| `OTP_REDIS_MIRROR`, `RATE_LIMIT_BACKEND` | Functions | Redis-first when cutover / `FIRESTORE_FORBIDDEN=1` |
| `OTP_TEST_MODE`, `ENFORCE_*_APP_CHECK` | Functions | Safety guards |

Compile-time Flutter: `--dart-define=APP_ENV=...`, `verify_production_build_config.js` (staging ref guard).

---

## 3. Staging verification (live probe, 2026-11-13)

Command: `node scripts/db/db_connectivity_smoke.js --env=staging`

| Check | Result |
|-------|--------|
| TCP + SSL to session pooler (5432) | OK |
| `server_version` | **17.11** |
| `_schema_migrations` rows | **59** |
| Pending migrations (`migrate.js --dry-run-all --confirm-live-data`) | **0** |
| Module table reads | `doctors` 2, `medical_stores` 2, `patients`/`labs`/`ambulances` 0 (test data) |
| `validate_migration_sql.js` | **59** files (58 shared + 1 RDS-only SQL validated), **0** parse failures |

---

## 4. Production RDS verification

| Check | Result |
|-------|--------|
| Config present in repo root `.env` (local, not committed) | `PROD_RDS_HOST` configured |
| `schema_diff.js --target=rehearsal` | **BLOCKED: ETIMEDOUT** (private VPC) |
| `schema_diff.js --target=production` | Same |
| Docker RDS SQL rehearsal | Script exists: `scripts/db/rds_scratch_replay.js`, `rds_system_admin_docker_test.js` |

---

## 5. Supabase-only features on RDS (behavior)

| Feature | Staging | Production (RDS path) |
|---------|---------|------------------------|
| Supabase Auth | Firebase third-party JWT | **Firebase only**; gateway verifies token (`token_verifier.js`) |
| PostgREST | Supabase-hosted | Self-hosted + `auth` shim (`db/rds_bootstrap/02_auth_shim.sql`) |
| Realtime | WebSocket | **Polling** (`supabase_stream_table.dart:57–71`) |
| Storage API | Supabase Storage | **S3** (`USE_S3_STORAGE`, `s3_storage.js`) |
| `auth.uid()` in RLS | Supabase JWT | JWT claims via gateway-minted PostgREST role |
| Edge Functions | Supabase | Cloud Functions + gateway |

---

## 6. Authorization

- **Client:** Firebase ID token → Gateway → short-lived PostgREST JWT with `app_role` / `sub` (UID).
- **RLS:** Policies use `auth.uid()` shim; validated by `scripts/db/rls_sql_harness.js` (documented 208 PASS on staging 2026-10-31).
- **Gateway allowlist:** `config.js` `clientDirectAllowedTables`, `serviceRoleOnlyTables`, `clientAllowedRpcs` — **PASS** (scanner 2026-11-13).
- **Admin tables:** service-role only on gateway; not exposed to anon.

---

## 7. Connection handling

- Staging migrations: **session pooler port 5432** (`RDS_MIGRATION_RUNBOOK.md`, `SESSION_CONNECTION_DOC` in migrate).
- RDS: SSL `rejectUnauthorized: true` + `infra/aws/global-bundle.pem`.
- Functions: supabase-js HTTP client (no long-lived PG pool in Node for app traffic).
- PostgREST pool: container config; optional RDS Proxy noted in runbooks.

---

## 8. Secrets

- Template: **repo root `.env.example`** only (all variable names).
- Real values: gitignored **repo root `.env`**, `.secret.local`, GCP Secret Manager (production Functions secrets).
- **Do not commit** `.env` (user workspace has local copy).

---

## 9. Isolation staging vs production

| Resource | Isolated? | Evidence |
|----------|-----------|----------|
| DB | **Yes** (when configured) | Separate URLs; `assert_app_env.js` blocks `*.supabase.co` gateway |
| S3 | **Yes** | `getS3BucketName()` → `S3_BUCKET_STAGING` \| `S3_BUCKET_PRODUCTION` (`s3_bucket.js`) |
| Redis | **Yes** | `getRedisHost()` → `REDIS_HOST_STAGING` \| `REDIS_HOST_PRODUCTION` (`redis.js`) |
| Firebase | Shared project possible | Release script blocks staging URL in prod builds |

---

## 10. Migration tooling (single source of truth)

| Action | Command |
|--------|---------|
| Validate SQL parses | `node scripts/db/validate_migration_sql.js` |
| Staging dry-run | `node scripts/db/migrate.js --target=staging --dry-run-all` |
| Staging apply | `node scripts/db/migrate.js --target=staging` (requires `--confirm` guards per `env_guard.js`) |
| RDS bootstrap | `db/rds_bootstrap/01..03.sql` then `migrate.js --target=production` |
| Full scratch replay | `node scripts/db/rds_scratch_replay.js` (see runbook) |
| Parity diff | `node scripts/db/schema_diff.js --target=rehearsal` |
| Connectivity smoke | `node scripts/db/db_connectivity_smoke.js --env=staging\|production` |

**Seed:** `scripts/db/seed_production_minimum.js` — production should start **clean** (no staging data migration unless requested).

**Rollback:** migration ledger append-only; restore from `scripts/db/generate_backup.js` / RDS snapshot (documented in `docs/runbooks/RDS_MIGRATION_RUNBOOK.md`).

---

## 11. Backup & ops

| Item | Status |
|------|--------|
| Migration backup script | `scripts/db/generate_backup.js`, `staging_logical_backup.js` |
| RDS PITR | `infra/aws/rds.tf` + runbooks |
| Health | Gateway `/healthz` + PostgREST probe (**FIXED**) |
| Prod smoke | `scripts/verify/prod_smoke.js`, `scripts/db/db_connectivity_smoke.js --env=production` |

---

## (c) Changes made in this audit (code/docs)

| File | Change |
|------|--------|
| `scripts/lib/migration_file_list.js` | **NEW** — single list: staging = shared SQL only; RDS targets include `db/migrations/rds/` |
| `scripts/db/migrate.js` | Use `migration_file_list`; RDS-only file applied on production/rehearsal/replay |
| `scripts/db/validate_migration_sql.js` | Validate all **59** migration paths (incl. `rds/`) |
| `scripts/db/verify_migration_files_ledger.js` | Delegate file list to `migration_file_list.js` |
| `scripts/test/migration_file_list.test.js` | **NEW** — staging excludes `rds/` |
| `db/rds_bootstrap/03_legacy_compat.sql` | Conditional grant to `postgres` role (replay/RDS bootstrap) |
| `DB_MIGRATION_VERIFICATION.md` | Re-audit 2026-11-13 (this document) |

*(Earlier on this branch: `assert_app_env.js`, `db_connectivity_smoke.js`, gateway `/healthz`, `.env.example`, release build guards.)*

---

## (d) Schema diff result

| Run | Outcome |
|-----|---------|
| `schema_diff.js --target=rehearsal` | **Not completed** — RDS unreachable (`ECONNREFUSED` tunnel) |
| `schema_diff.js --target=production` | **Not completed** — same |
| Staging vs repo SQL | **At head** (0 pending) |
| Expected RDS-only delta | After shared migrations, prod applies `rds/20261113000001_*` (not on Supabase staging ledger — intentional policy/trigger hardening for plain Postgres) |

**Re-run after fixes (from VPC/bastion):**

```bash
node scripts/db/schema_diff.js --target=rehearsal
# Expect: "ZERO UNEXPLAINED DIFFERENCES"
```

---

## (e) Manual steps (ordered)

1. ~~Staging migrations~~ **done** (optional re-check): `node scripts/db/migrate.js --target=staging --dry-run-all --confirm-live-data`
2. **Download RDS CA:** `infra/aws/global-bundle.pem` per [README_CA_BUNDLE.md](infra/aws/README_CA_BUNDLE.md).
3. **SSM tunnel** — [RDS_PROD_TUNNEL_WINDOWS.md](docs/runbooks/RDS_PROD_TUNNEL_WINDOWS.md); `PROD_RDS_CONNECT_HOST=127.0.0.1`, `PROD_RDS_PORT=5433`.
4. Add host hash to `docs/audit/allowed_host_hashes.txt` (see cutover runbook).
5. **RDS bootstrap pre-migrate** (empty DB):
   ```bash
   node scripts/db/rds_bootstrap_apply.js --target=production --execute --pre-migrate-only --confirm-live-data --confirm=<PROD_RDS_HOST>
   ```
6. **Apply migrations to RDS** (includes `db/migrations/rds/` automatically):
   ```bash
   node scripts/db/migrate.js --target=production --dry-run-all --confirm-live-data --confirm=<PROD_RDS_HOST>
   node scripts/db/migrate.js --target=production --execute --confirm-live-data --confirm=<PROD_RDS_HOST>
   node scripts/db/rds_bootstrap_apply.js --target=production --execute --confirm-live-data --confirm=<PROD_RDS_HOST>
   ```
7. **PG18.3 replay gate** (local Docker): `node scripts/db/rds_scratch_replay.js` — start Docker Desktop first.
8. **Schema parity** (from tunnel/VPC):
   ```bash
   node scripts/db/schema_diff.js --target=production --confirm-live-data --confirm=<PROD_RDS_HOST>
   ```
9. **Deploy Auth Gateway + PostgREST** against RDS; set `PROD_GATEWAY_URL`, secrets in GCP/AWS.
10. **Production smoke** (non-destructive):
   ```bash
   node scripts/db/db_connectivity_smoke.js --env=production
   node scripts/verify/prod_smoke.js
   ```
11. **Cloud Functions** — `APP_ENV=production`, `PROD_GATEWAY_*`, `FIRESTORE_FORBIDDEN=1`, `REDIS_HOST_PRODUCTION`, `S3_BUCKET_PRODUCTION`; remove plain-env duplicates that overlap Secret Manager (`node scripts/predeploy_secret_check.js` must pass).
12. **Flutter release** — `APP_ENV=production`, gateway URL/anon via `frontend/scripts/release_build.ps1`; `node backend/scripts/verify_production_build_config.js`.

---

## (f) Go / no-go

| Verdict | **NO-GO** for production user traffic on RDS |
|---------|---------------------------------------------|
| Blockers (2026-11-13) | RDS never migrated from this machine (tunnel down); `global-bundle.pem` missing locally; `schema_diff` not run; PG18.3 Docker replay not run (Docker engine stopped); prod gateway HTTP smoke fails (`fetch failed` — endpoint not deployed/reachable) |

**Local pre-checks done:** `04_rds_runtime_grants.sql`, **10/10** service paths, **49/49** auth matrix, **7/7** real-path e2e, **67/67** RLS coverage.

**Conditional GO** after: [RDS_CUTOVER_STEPS.md](docs/runbooks/RDS_CUTOVER_STEPS.md) (migrate + `04` + live `schema_diff` + prod smoke), staging at repo head including `20261113000002`–`000003`, `FIRESTORE_FORBIDDEN=1` on Functions prod.

---

## Verification runs (latest)

| Command | Result |
|---------|--------|
| `backend/functions` `npm test` | **PASS** (0 fail) — 2026-11-13 |
| `services/api-gateway` `npm test` | **PASS** (68 tests) — 2026-11-13 |
| `node scripts/db/db_connectivity_smoke.js --env=staging` | **PASS** — PG 17.11, 59 ledger rows, 5 modules |
| `node scripts/db/db_connectivity_smoke.js --env=production` | **FAIL** — tunnel `127.0.0.1:5433` refused; gateway fetch failed |
| `node scripts/check_env_parity.js` | **PASS** |
| `node scripts/db/validate_migration_sql.js` | **PASS** — 59 files |
| `node scripts/test/migration_file_list.test.js` | **PASS** |
| `node scripts/predeploy_secret_check.js` (local `.env`) | **FAIL** — Secret Manager overlap warnings (staging deploy hygiene; fix before prod `firebase deploy`) |
| `node scripts/db/schema_diff.js` | **BLOCKED** — RDS private network |

---

## Firestore inventory (Cloud Functions) — follow-up 2026-11-12

| Area | Runtime with `FIRESTORE_FORBIDDEN=1` | Notes |
|------|--------------------------------------|-------|
| `index.js` callables | **Postgres via `db()` → `getLegacyFirestoreDb()` (null)** | Abuse limits → Redis; business logic uses `getDatabaseClient()` where cutover |
| `registration_otp.js` | **Postgres + Redis** | `isDoctorPatientSupabasePrimary()` always true |
| `s3_storage.js` | **Postgres** (`resolveStorageContext` forces Supabase when forbidden) | Legacy `db.collection` branches unused |
| `appointment_slots.js` callables | **Fail-fast** → client uses `book_appointment_atomic` / `reschedule_appointment_atomic` RPC |
| `promoted_ads.js` | **Postgres when cutover** | Firestore webhook path only if `__TEST_FORCE_LEGACY` / tests set `FIRESTORE_FORBIDDEN=0` |
| `cross_role_sync.js` | **Postgres**; DLQ Firestore fallback **skipped** if forbidden |
| `delete_my_account.js` | **Postgres** primary | Firestore branch only when legacy cutover off |
| `security_logger.js` | **Postgres `security_events`** | Firestore audit skipped when forbidden |
| `caller_identity.js` | **Postgres** | Firestore profile path throws if forbidden |
| `backend/functions/scripts/*` | Operator tools only | Not loaded in production deploy |

---

## Gateway authorization (production)

| Step | Implementation |
|------|----------------|
| Firebase JWT | `services/api-gateway/src/token_verifier.js` — JWKS RS256, `iss`/`aud`/`exp` |
| Revocation | `firebase_revocation.js` — `verifyIdToken(..., checkRevoked=true)` when `APP_ENV=production` |
| PostgREST JWT | `jwt_minter.js` — short-lived JWT with `sub` = Firebase UID, `app_role` / `user_role` claims |
| RLS on RDS | Policies use `auth.jwt() ->> 'sub'` and helpers; `db/rds_bootstrap/02_auth_shim.sql` defines **`auth.uid()` → TEXT** (Firebase UID) |
| Table exposure | `config.js` — `clientDirectAllowedTables` vs `serviceRoleOnlyTables`; embed-only tables blocked as top-level |
| Gaps | **Service-role** Cloud Functions bypass gateway RLS (by design); clients never get service key. Re-run `rls_sql_harness.js` on RDS after migrations. |

---

*Re-audited 2026-11-13 on `fix/pre-accept-gate-lab-auth`. Staging schema at repo head; RDS cutover steps remain operator-blocked on network/TLS/Docker.*
