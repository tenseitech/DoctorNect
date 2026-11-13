# DB Migration Verification — DoctorNect

**Branch audited:** `fix/pre-accept-gate-lab-auth`  
**Date:** 2026-11-12  
**Auditor:** Automated repo audit + live staging probes (no destructive DB ops)  
**Target architecture:** Staging = Supabase Postgres · Production = AWS RDS Postgres · Auth = Firebase · OTP = MSG91 · Cache = Redis · Files = S3 · Scope = Doctor, Patient, Pharmacy, Lab, Ambulance (not Admin app)

---

## (a) Status summary

| # | Area | Status | Notes |
|---|------|--------|-------|
| 1 | DB touchpoints inventory | **PASS** | Documented below; single routing via `APP_ENV` + gateway |
| 2 | Environment selection | **FIXED** | Added `assertAppEnvDatabaseRouting`; see §2 |
| 3 | Staging Supabase | **PASS** | At repo head incl. `20261112000006`, `20261113000002`, `20261113000003` (operator); read-only grant + RPC parity below |
| 4 | Production RDS | **IN PROGRESS** | Instance created; repo wired (`rds_pool_config.js`, tunnel runbook). **BLOCKED-NET** from laptop until SSM tunnel (§Production RDS setup) |
| 12 | RDS grant matrix | **PASS (staging read)** | Live compare: **64** `service_role`-only diffs (staging superset); **0** `anon`/`authenticated` diffs; **0** anon surprises local |
| 13 | Service-role paths | **PASS (local)** | `service_role_paths_test.js` — **10/10** incl. `book_appointment_atomic`, admin audit, outbox (`20261113000002`) |
| 14 | RLS coverage | **PASS (local)** | `rls_coverage_audit.js` — 67 public tables, **0** errors |
| 15 | Auth matrix (5×6 + medical) | **PASS (local)** | `gateway_rls_authorization_suite.js` — **49/49** on `doctornect_fresh_zero` (`20261113000003` support_tickets fix) |
| 16 | Real HTTP path | **PASS (local)** | `real_path_authorization_e2e.js` — PostgREST 12.2.3 + Gateway **7/7** |
| 5 | PostgREST / supabase-js on prod | **PASS*** | *By design:* prod client uses **Auth Gateway + PostgREST over RDS**, not Supabase cloud; not raw `pg` from Flutter |
| 6 | Authorization (Firebase UID) | **PASS** (design) | Gateway mints JWT → `auth.uid()` shim on RDS; RLS harness docs exist — **re-run on RDS after apply** |
| 7 | Connection pooling / SSL | **PASS** (config) | Supabase session pooler documented; RDS SSL via `global-bundle.pem` in `migrate.js` |
| 8 | Secrets in repo | **PASS*** | `scan_passwords.js`: no real private keys; 5 placeholder patterns in docs/tests only |
| 9 | Staging/prod isolation | **FIXED** | `S3_BUCKET_STAGING` / `S3_BUCKET_PRODUCTION`, `REDIS_HOST_STAGING` / `REDIS_HOST_PRODUCTION` + cross-env guards (`app_resources.js`) |
| 10 | Migration tooling | **PASS** | `db/migrations/` (55 files) + `migrate.js` + RDS bootstrap/overrides |
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

1. ~~**Staging schema behind repo (9 migrations)**~~ **RESOLVED 2026-11-12** — applied via `node scripts/db/migrate.js --target=staging --execute --confirm-live-data --confirm-staging`. Ledger **56** rows; head `20261112000005`. Stray row `20261104000001` (legacy duplicate of anon cleanup) remains — reconcile before prod cutover.
2. **RDS schema parity unverified on rehearsal** — `schema_diff --target=rehearsal` still requires bastion/SSM (not run here). Staging at migration head; grants/RPC logic match local replay (§Staging verified).
3. **Staging vs production PG** — Staging **17.11**; production **18.3**. **Mandatory prod gate:** PG18.3 replay only (see [STAGING_VS_PRODUCTION_PG_GAP.md](docs/reports/STAGING_VS_PRODUCTION_PG_GAP.md)). Cached `schema_diff` / `FUNCTION_BODY` hashes vs staging are **not** authoritative for prod; **11/11** RPC normalized MATCH is read-only on PG17-era local DB. Full PG18.3 replay **BLOCKED** (Docker down on audit machine).
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

## 3. Staging verification (live probe, 2026-11-12)

Command: `node scripts/db/db_connectivity_smoke.js --env=staging`

| Check | Result |
|-------|--------|
| TCP + SSL to session pooler | OK |
| `_schema_migrations` rows | 47 |
| Module table reads | `doctors` 2, `medical_stores` 2, others 0 (test data) |
| Pending migrations | **9 files** (see §b.1) |
| `validate_migration_sql.js` | **55 files, 0 parse failures** |

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
- **Gateway allowlist:** `config.js` `clientDirectAllowedTables`, `serviceRoleOnlyTables`, `clientAllowedRpcs` — **drift test failing** (see §b.7).
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
| S3 | **Partial** | Templates now `STAGING_S3_BUCKET` / `PRODUCTION_S3_BUCKET`; code uses `S3_BUCKET` |
| Redis | **Partial** | Templates added; code uses `REDIS_HOST` |
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
| `backend/functions/src/db/assert_app_env.js` | **NEW** — fail-fast `APP_ENV` DB routing |
| `backend/functions/test/assert_app_env.test.js` | **NEW** — unit tests |
| `backend/functions/index.js` | Wire assert on cold start (skip in test) |
| `scripts/db/db_connectivity_smoke.js` | **NEW** — per-env, per-module read smoke |
| `services/api-gateway/src/server.js` | `/healthz` checks PostgREST upstream |
| Root `.env.example` | Staging/prod RDS, gateway, S3, Redis, Functions (names only) |
| `frontend/scripts/release_build.ps1` | Remove hardcoded staging URL |
| `DB_MIGRATION_VERIFICATION.md` | This document |

---

## (d) Schema diff result

| Run | Outcome |
|-----|---------|
| `schema_diff.js --target=rehearsal` | **Not completed** — RDS `ETIMEDOUT` from audit environment |
| Staging catalog (prior doc) | `docs/ops/staging_migration_drift.json`: 69 tables, 184 policies, 73 functions |
| Pending SQL vs staging | **9 migrations** not applied (list in §b.1) |

**Re-run after fixes (from VPC/bastion):**

```bash
node scripts/db/schema_diff.js --target=rehearsal
# Expect: "ZERO UNEXPLAINED DIFFERENCES"
```

---

## (e) Manual steps (ordered)

1. **Apply staging migrations** (from machine with session pooler access):
   ```bash
   node scripts/db/migrate.js --target=staging --dry-run-all
   node scripts/db/migrate.js --target=staging   # follow env_guard confirmations
   node scripts/db/rls_sql_harness.js --target=staging
   node scripts/db/db_connectivity_smoke.js --env=staging
   ```
2. **RDS reachable host** — VPN/bastion/SSM; security group allows your IP or tunnel.
3. **RDS bootstrap** (empty prod): run `db/rds_bootstrap/01–03.sql` as master user.
4. **Apply migrations to RDS**:
   ```bash
   node scripts/db/migrate.js --target=production --dry-run-all
   node scripts/db/migrate.js --target=production
   ```
5. **Schema parity**:
   ```bash
   node scripts/db/schema_diff.js --target=production
   ```
6. **Deploy Auth Gateway + PostgREST** against RDS; set `PROD_GATEWAY_URL`, secrets in GCP/AWS.
7. **Production smoke** (non-destructive with service key):
   ```bash
   node scripts/db/db_connectivity_smoke.js --env=production
   node scripts/verify/prod_smoke.js
   ```
8. **Cloud Functions** — set `APP_ENV=production`, `PROD_GATEWAY_*`, disable `FIRESTORE_FORBIDDEN=0`, set production Redis/S3.
9. **Flutter release** — `APP_ENV=production`, `PROD_GATEWAY_URL` / anon key via release script; verify `verify_production_build_config.js`.
10. **Fix gateway allowlist test** — align `services/api-gateway/src/config.js` with scanner output.
11. **Optional:** wire `STAGING_S3_BUCKET` / `PRODUCTION_S3_BUCKET` and Redis hosts in `s3_storage.js` / `redis.js`.

---

## (f) Go / no-go

| Verdict | **NO-GO** for production user traffic on RDS |
|---------|---------------------------------------------|
| Blockers (2026-11-12) | RDS `schema_diff` / rehearsal not run from operator network; staging vs local **grant matrix** not compared live; **PG18.3** replay chain not re-run (Docker down on audit machine) |

**Local pre-checks done:** `04_rds_runtime_grants.sql`, **10/10** service paths, **49/49** auth matrix, **7/7** real-path e2e, **67/67** RLS coverage.

**Conditional GO** after: [RDS_CUTOVER_STEPS.md](docs/runbooks/RDS_CUTOVER_STEPS.md) (migrate + `04` + live `schema_diff` + prod smoke), staging at repo head including `20261113000002`–`000003`, `FIRESTORE_FORBIDDEN=1` on Functions prod.

---

## Verification runs (latest)

| Command | Result |
|---------|--------|
| `backend/functions` `npm test` | **PASS** (0 fail; `FIRESTORE_FORBIDDEN=1` default in `setup_env.js`) |
| `services/api-gateway` `npm test` | **PASS** (0 fail; allowlist scanner green) |
| `node scripts/db/db_connectivity_smoke.js --env=staging` | PASS (5 modules) |
| `node scripts/check_env_parity.js` | PASS |
| `node scripts/db/schema_diff.js` | BLOCKED (RDS private network) |

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

*Updated after code-level blocker fixes on `fix/pre-accept-gate-lab-auth`. Re-run after staging migration apply.*
