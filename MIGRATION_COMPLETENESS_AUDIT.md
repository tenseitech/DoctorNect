# Migration completeness audit (read-only)

**Date:** 2026-11-12  
**Branch:** `fix/pre-accept-gate-lab-auth` (309 commits ahead of `main`, 0 behind per `git rev-list --left-right --count main...HEAD`)  
**Scope:** Staging Supabase Postgres · Production AWS RDS + Auth Gateway + PostgREST · 5 app modules (doctor, patient, pharmacy, lab, ambulance) · Admin out of scope  
**Constraints honored:** No writes to staging/production; no bootstrap/migrate `--execute`; no code changes in this pass.

---

## F. Verdict summary table

| ID | Item | Status |
|----|------|--------|
| A1 | Staging migration ledger vs repo | **DONE** (staging top-level; RDS-only file separate) |
| A2 | Staging connectivity & auth audits | **DONE** (staging DB) / **PARTIAL** (grant noise) |
| A3 | Module table row counts (staging) | **DONE** |
| B4 | RDS endpoint resolve + connect (tunnel) | **BLOCKED** |
| B5 | RDS bootstrap / ledger / schema parity | **NOT DONE** |
| B6 | RDS force_ssl, backups, deletion protection, encryption | **BLOCKED** (console) |
| C7 | Firestore usage inventory | **PARTIAL** |
| C8 | Supabase-direct / RDS-incompatible paths | **PARTIAL** |
| C9 | Hardcoded hosts, keys, buckets, project IDs | **PARTIAL** |
| C10 | Per-module data path matrix | **PARTIAL** |
| C11 | Auth: Firebase-only, MSG91 OTP, gateway JWT | **PARTIAL** |
| C12 | S3 / Redis env routing & leftovers | **PARTIAL** |
| C13 | Env file policy (2 files only) | **DONE** |
| C14 | Security: RLS, anon grants, client secrets | **PARTIAL** |
| D15 | Automated tests & analyze | **PARTIAL** (e2e 7/7 local; RDS blocked without tunnel) |
| E16 | Git / migration commit parity | **PARTIAL** (migrations **staged**, not committed) |
| **—** | **Migration complete?** | **NO** |

---

## A. Staging (read-only)

### A1. Ledger vs `db/migrations/`

| Check | Evidence | Status |
|-------|----------|--------|
| Pending vs repo | `node scripts/db/migrate.js --target=staging --dry-run-all --confirm-live-data` → **Existing Applied Migrations: 59**, **Pending: 0**, dry-run **0 errors** | **DONE** |
| Repo SQL files (top-level) | 58 × `db/migrations/*.sql` (excludes `db/migrations/rds/` subfolder) | — |
| Repo SQL files (total on disk) | 59 files including `db/migrations/rds/20261113000001_rds_system_admin_and_audit.sql` | — |
| `migrate.js` scanner | Only **top-level** `db/migrations/*.sql` (`scripts/db/migrate.js` L74–75); **RDS subfolder not applied by runner** | **NOT DONE** for RDS-only file |
| Duplicate `20261104000001` | No `db/migrations/20261104000001_*.sql`; `migrate.js` L184 skips import of that version from Supabase; ledger row count **59** vs **58** tracked migration files ⇒ **ghost ledger version** still plausible | **PARTIAL** (handled in tooling, not reconciled on staging) |
| Checksum drift (all applied) | `node scripts/db/verify_migration_files_ledger.js --confirm-live-data` → **58/58** top-level files **OK** on staging; ghost ledger `20261104000001` documented; `rds/20261113000001_*` **RDS-only** (not on staging) | **DONE** (staging) |

### A2. Read-only scripts (this run)

| Script | Result | Status |
|--------|--------|--------|
| `db_connectivity_smoke.js --env=staging` | **PASS**; `_schema_migrations`: **59** rows | **DONE** |
| `rls_coverage_audit.js --target=staging --confirm-live-data` | **68** public tables, **0** issues (`docs/reports/rls_coverage_audit.json`) | **DONE** |
| `grant_matrix_audit.js --compare-staging --confirm-live-data` | Local replay vs staging: **64** live table grant diffs (all classified **class `a`**: staging `GRANT ALL` on `service_role` vs local DML-only — `docs/reports/grant_table_diffs_classified.json`) | **PARTIAL** (expected staging/Supabase noise; not prod-RDS shape) |
| `compare_anon_auth_grants.js` | **0** anon/authenticated table grant diffs vs staging | **DONE** |
| `rpc_body_parity_staging.js --confirm-live-data` | **11/11 MATCH** (normalized RPC bodies vs `doctornect_fresh_zero`) | **DONE** |

### A3. Staging row counts (main module tables)

From `db_connectivity_smoke.js --env=staging` (SELECT count only):

| Module | Table | Rows |
|--------|-------|------|
| doctor | `doctors` | **2** |
| patient | `patients` | **0** |
| pharmacy | `medical_stores` | **2** |
| lab | `labs` | **0** |
| ambulance | `ambulances` | **0** |

---

## B. Production RDS

### B4. Connect / PostgreSQL version

| Check | Evidence | Status |
|-------|----------|--------|
| `rds_readiness_probe.js --target=production --confirm=<fingerprint>` | **Follow-up:** `scripts/lib/rds_connect_guard.js` blocks **localhost:5432** trap when `PROD_RDS_HOST` is RDS; **`PROD_RDS_PORT` required** (no default 5432). Tunnel still required to validate live RDS. | **BLOCKED** (manual tunnel) |
| Likely cause | SSM/SSH tunnel not active; set `PROD_RDS_CONNECT_HOST=127.0.0.1`, **`PROD_RDS_PORT=5433`** (`docs/runbooks/RDS_PROD_TUNNEL_WINDOWS.md`) | **BLOCKED** (manual) |
| PostgreSQL 15.x target | **Not verified** (no successful connect) | **BLOCKED** |

### B5. Bootstrap, ledger, schema diff

| Check | Evidence | Status |
|-------|----------|--------|
| Bootstrap roles / auth shim / grants | Cannot inspect RDS catalog without connection | **NOT DONE** |
| `_schema_migrations` on RDS | Not reachable | **NOT DONE** |
| `schema_diff.js --target=production` | Same SSL error via `127.0.0.1:5432` | **BLOCKED** |
| Staging vs RDS parity | Not run | **NOT DONE** |

### B6. Infra vs AWS console

| Setting | In repo | Status |
|---------|---------|--------|
| `rds.force_ssl` / parameter enforcement | `infra/aws/rds.tf` defines **parameter group** (`postgres17` family) only; **no** `aws_db_instance` with `storage_encrypted`, `backup_retention_period`, `deletion_protection`, or `rds.force_ssl` | **BLOCKED** — confirm in **RDS console** / live Terraform state |
| Deletion protection | `infra/aws/alb.tf` ALB `enable_deletion_protection = true` (ALB only, not RDS) | **BLOCKED** for RDS instance |
| Encryption at rest | Not declared on RDS in tracked `.tf` | **BLOCKED** (console) |
| Automated backups / PITR | Referenced in docs/runbooks; not verifiable from repo alone | **BLOCKED** (console) |
| Engine version | Code/docs target **PostgreSQL 15.x** (audit charter); `infra/aws/rds.tf` comment references **PostgreSQL 17** parameter family | **PARTIAL** (version drift in docs/infra) |

**Manual (AWS console):** Confirm RDS instance encryption, backup window/retention, deletion protection, `rds.force_ssl`, actual engine major version (15 vs 17), security groups, and private subnet reachability.

---

## C. Code completeness (repo grep / inspect)

### C7. Firestore usage (representative inventory)

| Area | Path / pattern | Prod reachable? | `FIRESTORE_FORBIDDEN=1` |
|------|----------------|-----------------|---------------------------|
| Flutter client | `package:cloud_firestore` across `frontend/lib/**` (e.g. `ambulance_repository.dart`, `doctor_profile_store.dart`, `community_*` still import Firestore types) | **Yes** if compile defines allow Firestore | `FirestoreService.instance` → `FirestoreForbiddenGuard.assertNotForbidden` (**throws** in release when forbidden) — `frontend/lib/core/firebase/firestore_service.dart` |
| Flutter tests | `fake_cloud_firestore` in `frontend/test/**` | No (tests only) | N/A |
| Functions | `firebase-admin/firestore` in `backend/functions/index.js`, `appointment_slots.js`, `cross_role_sync.js`, etc. | Call paths use `getLegacyFirestoreDb()` → **null** when forbidden — `backend/functions/legacy_db.js` | **Safe** when `FIRESTORE_FORBIDDEN=1`; legacy branches remain in source |
| Functions exports | No `onDocumentWritten` / `cross_role` exports in `index.js` (grep); slot sync comment: Postgres-only — `index.js` ~L1302 | Staging/prod deploy: **triggers not exported** | N/A |
| Gateway | No Firestore dependency found | — | — |
| Emulator/rules | `backend/firestore.rules`, `npm run test:rules` | Emulator only | — |

**Status:** **PARTIAL** — server guarded; **client still contains large Firestore surface**; production builds must ship `FIRESTORE_FORBIDDEN=1` and Postgres/gateway paths or screens hit guard/runtime errors.

### C8. Supabase-direct / RDS-incompatible (staging OK, prod risk)

| Pattern | Examples | RDS prod impact |
|---------|----------|-----------------|
| `@supabase/supabase-js` in Functions | `backend/functions/src/db/client.js`, `s3_storage.js`, `promoted_ads.js` | **PARTIAL** — production must use **gateway HTTP** (`PROD_GATEWAY_*`), not `*.supabase.co` (`assert_app_env.js`) |
| Flutter `SupabaseBootstrap` / `.channel()` | Multiple repos (e.g. `supabase_prescription_repository.dart`, `support_ticket_supabase_repository.dart`) — **Realtime channels** | **PARTIAL** — on RDS path, realtime is **polling** per architecture docs; channels may no-op or fail |
| Direct `STAGING_SUPABASE_DB_URL` scripts | Migration/smoke tools | Staging-only; not prod app path |
| Supabase Storage API | No active `storage.from` in app code; `storage_audit_logs` is a **Postgres table** insert in `s3_storage.js` | **DONE** for object storage (S3 presign path) |

### C9. Hardcoded identifiers (non-secret but fixed targets)

| Location | What | Risk |
|----------|------|------|
| `frontend/scripts/release_build.ps1` `-Launch` | Hardcoded staging `SUPABASE_URL` host ref + anon JWT material | **PARTIAL** — dev convenience; must not be used for Play release |
| `frontend/scripts/release_build.sh` | Default staging URL ref | Same |
| `scripts/predeploy_secret_check.js` | `PROD_REF = 'rnltknemwnjrjxthtull'` (staging ref used as “prod” label in checker) | **PARTIAL** — naming confusion |
| `scripts/verify-connections.js`, `set-super-admin.js` | Fallback `medibond-45fad` project id | Low (public id) |
| `scripts/verify-s3-live.js` | Default Functions URL host `asia-south1-medibond-45fad.cloudfunctions.net` | Low |
| Docs / comments | Many `rnltknemwnjrjxthtull`, `irpkyedfmdsuvapfnrim` refs | Documentation only |

No AWS access keys or service-role keys found in `frontend/lib/**` (grep `SERVICE_ROLE`).

### C10. Module × data source (high level)

| Module | Primary prod-intent path | Legacy / staging dual path |
|--------|--------------------------|----------------------------|
| **doctor** | Postgres via `SupabaseBootstrap` + gateway when cutover flags on | **FirestoreService** still used for availability, patients, reviews, medical directory, etc. (`frontend/lib/features/doctor/**`) |
| **patient** | Supabase repos (`frontend/lib/core/supabase/**`) for records, profile, notifications | Firestore repositories still present under `frontend/lib/core/firebase/repositories/` |
| **pharmacy** | Mixed: Supabase + `pharmacy_firestore_repository.dart`; connection store touches Firestore | **PARTIAL** cutover |
| **lab** | `lab_repository.dart` Supabase paths; catalog/connections still have Firestore repos | **PARTIAL** |
| **ambulance** | Supabase RPC in driver home; `ambulance_repository.dart` still heavy **Firestore** | **PARTIAL** |

**Status:** **PARTIAL** — no module is 100% Firestore-free on client.

### C11. Auth & OTP

| Check | Evidence | Status |
|-------|----------|--------|
| Firebase JWT verify (gateway) | `services/api-gateway/src/token_verifier.js` (RS256 + JWKS) | **DONE** |
| Revocation | `services/api-gateway/src/firebase_revocation.js` — `verifyIdToken(..., checkRevoked=true)` after JWKS; config notes in `config.js` | **DONE** (when Admin SDK creds configured at runtime) |
| Supabase Auth | No Flutter `supabase_flutter` auth sign-in path as primary; Firebase OTP callables in `backend/functions/index.js` | **DONE** (primary) |
| MSG91 | OTP callables use `MSG91_VPC_OPTIONS`; email via `sendMsg91Email` — `index.js` | **DONE** |
| Test backdoors | `REVIEW_FIXED_OTP`, `REVIEW_TEST_NUMBERS` in `.env.example` / `registration_otp.js`; `ENABLE_DEMO_*` compile guards in docs | **PARTIAL** — reviewer OTP is **intentional**; must stay out of production abuse paths |

### C12. S3 & Redis

| Check | Evidence | Status |
|-------|----------|--------|
| S3 bucket by env | `backend/functions/src/config/app_resources.js` → `S3_BUCKET_STAGING` / `S3_BUCKET_PRODUCTION` | **DONE** (Functions) |
| Firebase Storage | Rules exist; app uploads via **presigned S3** / Functions | **PARTIAL** (rules/emulator legacy) |
| Redis by env | `getRedisHost()` staging/production split; secrets via `defineSecret` in `redis.js` | **DONE** |
| Cached data / TTL | OTP/abuse limits, rate counters (see `registration_otp.js`, Redis helpers in Functions) — exact TTLs vary by key prefix | **PARTIAL** (not fully enumerated here) |

### C13. Environment files

| Check | Evidence | Status |
|-------|----------|--------|
| `git ls-files` env | Only `.env.example` tracked | **DONE** |
| Filesystem (excl. node_modules/build/ephemeral) | **`.env`**, **`.env.example`** only (`verify_env_file_policy.js` + filesystem walk) | **DONE** |
| Single-root consolidation | `ENV_CONSOLIDATION_REPORT.md`; readers load root `.env` | **DONE** |
| Secrets ever committed (names only) | `scripts/audit/scan_env_example_history.js`: `STAGING_SUPABASE_DB_URL`, `STAGING_SUPABASE_URL`, `SUPABASE_URL`, `S3_BUCKET`, `S3_BUCKET_NAME`, `AWS_S3_VAULT_BUCKET`, `SUPABASE_WEBHOOK_SECRET` in historical templates | **PARTIAL** — review rotation |

### C14. Security

| Check | Evidence | Status |
|-------|----------|--------|
| Tables without RLS (staging) | `rls_coverage_audit.js` staging: **0** errors | **DONE** (staging) |
| Anon grants | `20261103000008_staging_anon_security_cleanup.sql` — anon **SELECT** on four public tables + `review_public` | **DONE** (per migration intent) |
| Service role on client | No `SERVICE_ROLE` in `frontend/lib/**` | **DONE** |
| Secrets in Flutter binary | Release script allowlists dart-defines; `-Launch` can inject staging anon JWT — **not** service role | **PARTIAL** |

---

## D. Tests and build (this run)

| Suite | Result | Notes |
|-------|--------|-------|
| `backend/functions` `npm test` | **514 pass**, 0 fail, 22 skip | Includes env parity, `assert_app_env`, etc. |
| `services/api-gateway` `npm test` | **68 pass**, 0 fail | |
| `gateway_rls_authorization_suite.js` | **49 PASS / 0 FAIL** | Local DB `doctornect_fresh_zero`, not live staging |
| `service_role_paths_test.js` | **10 PASS / 0 FAIL** | Local replay |
| `real_path_authorization_e2e.js` | **7 PASS / 0 FAIL** (PostgREST `PGRST_JWT_SECRET` env + conf fix) | **DONE** (local) |
| `run_real_path_authorization_e2e.js` | Wrapper: start/teardown via same script | **DONE** |
| `flutter analyze` | **No issues found** | |
| `flutter test` `release_build_supabase_guard_test.dart` | **6/6 pass** | Client-only `.env` import; endpoint isolation guards; no service-role leakage into build env |

**Status D15:** **PARTIAL**

---

## E. Git and release readiness

| Check | Evidence | Status |
|-------|----------|--------|
| Uncommitted work | Large set of modified + untracked files (`git status` on branch) | **NOT DONE** |
| Untracked migrations (applied on staging, not in git) | `?? db/migrations/20261112000001` … `20261113000003` (8 files) + `?? db/migrations/rds/` | **NOT DONE** — staging ledger at head **includes** these versions; **git only tracks 50** top-level SQL files |
| Branch vs `main` | **309** commits ahead | Merge needs review, not fast-forward only |
| Staging ↔ repo ledger | Staging **pending 0** with **59** ledger rows; repo has **58** top-level + **1** RDS subfolder file not in runner | **PARTIAL** |

---

## F. Final answers

### Migration complete?

**NO.**

**Blocking items (priority order):**

1. **Production RDS not reachable** from this environment (tunnel/SSL/port) — no bootstrap, migrate, or schema parity proof.
2. **Git gap:** Eight migrations (and `db/migrations/rds/`) exist on disk and on **staging ledger** but are **untracked** — must be committed before merge/cutover traceability.
3. **RDS-only migration file** under `db/migrations/rds/` **not** wired into `migrate.js` scanner.
4. **Client Firestore surface** remains broad; production requires `FIRESTORE_FORBIDDEN=1` **and** completion of Postgres/gateway wiring per screen or runtime failures.
5. **`real_path_authorization_e2e`** fails without local Gateway+PostgREST — HTTP path not re-verified live.
6. **Ghost ledger version `20261104000001`** vs repo file `20261103000008` — reconcile before prod ledger hygiene.
7. **Engine/version documentation drift** (15.x charter vs `postgres17` parameter family in `infra/aws/rds.tf`).

### Manual steps (you), in order

1. Start RDS tunnel per `docs/runbooks/RDS_PROD_TUNNEL_WINDOWS.md`; set `PROD_RDS_CONNECT_HOST=127.0.0.1`, `PROD_RDS_PORT=5433` (or your local forward) in root `.env`.
2. Re-run read-only:  
   `node scripts/db/rds_readiness_probe.js --target=production --confirm=<PROD_RDS_HOST fingerprint>`  
   `node scripts/db/schema_diff.js --target=production` (after tunnel up).
3. AWS Console: confirm RDS encryption, backups, deletion protection, `rds.force_ssl`, actual engine version.
4. `git add db/migrations/20261112000001_*.sql` … `20261113000003_*.sql` and `db/migrations/rds/`; commit with migration message; open PR to `main`.
5. (Optional) Reconcile staging ledger duplicate `20261104000001` when approved for a **controlled** staging SQL fix (out of scope for read-only audit).
6. Before Play release: remove reliance on `release_build.ps1 -Launch` hardcoded staging defines; use root `.env` only.

### Follow-up prompt for Cursor (when tunnel + commit are done)

```
Read-only re-audit items B4–B5 and D15 real_path_authorization_e2e only:
1) With PROD_RDS tunnel up, run rds_readiness_probe + schema_diff --target=production (no --execute).
2) Start local PostgREST+gateway per docs/runbooks/RDS_CUTOVER_STEPS.md and re-run real_path_authorization_e2e.js; paste pass/fail into MIGRATION_COMPLETENESS_AUDIT.md §D.
3) Run full ledger checksum audit script if added, or migrate.js enhancement to verify all checksums on --dry-run-all.
4) Grep FirestoreService call sites per module and produce DONE/PARTIAL per screen for production FIRESTORE_FORBIDDEN=1.
Do not modify DB data; do not run migrate --execute.
```

### Go / No-go

| Gate | Decision | Rationale |
|------|----------|-----------|
| **(a) Staging use** | **Conditional GO** | DB at migration head (pending 0), smoke + RLS + RPC parity **PASS**; grant matrix service_role diffs are classified noise. |
| **(b) Production RDS cutover** | **NO-GO** | RDS not connected; bootstrap/migrate/parity unproven. |
| **(c) Merge to main** | **NO-GO** | Untracked migrations + large uncommitted delta + 309-commit divergence. |
| **(d) Store release** | **NO-GO** | Firestore client surface + failed release guard test + production RDS/gateway path unproven. |

---

## Follow-up (2026-11-12 evening) — fixes applied

| Area | Change |
|------|--------|
| **Git** | Staged 8 migration SQL files + `db/migrations/rds/20261113000001_rds_system_admin_and_audit.sql` (not committed). Staged deletions of legacy `*.env.example` templates. **No** `.env`, `*.pem`, or credentials in staged set. |
| **Ledger verify** | `scripts/db/verify_migration_files_ledger.js --confirm-live-data` |
| **Release build** | **Before:** root `.env` loaded `SUPABASE_SERVICE_ROLE_KEY` → dry-run tests failed. **After:** `Import-ClientReleaseDotEnv` (allowlist only) + `Test-ReleaseApiEndpointIsolation` (prod vs staging endpoints). |
| **RDS safety** | `rds_connect_guard.js`, required `PROD_RDS_PORT`, `scripts/test/rds_connect_guard.test.js` |
| **E2E HTTP** | **Root cause of 500:** PostgREST lacked JWT secret (`PGRST300`); fixed `PGRST_JWT_SECRET` + conf `$(PGRST_JWT_SECRET)`. **7/7 PASS.** |
| **Reports** | `docs/reports/*.json` connection strings use `****` masking (e.g. `rls_coverage_audit.json`). |

**E16 staged files (migrations):** `20261112000001` … `20261112000006`, `20261113000002`, `20261113000003`, `db/migrations/rds/20261113000001_rds_system_admin_and_audit.sql`.

---

## Audit commands log (summaries only; no secrets printed)

```
node scripts/db/migrate.js --target=staging --dry-run-all --confirm-live-data
node scripts/db/db_connectivity_smoke.js --env=staging
node scripts/db/rls_coverage_audit.js --target=staging --confirm-live-data
node scripts/db/grant_matrix_audit.js --compare-staging --confirm-live-data
node scripts/db/compare_anon_auth_grants.js
node scripts/db/rpc_body_parity_staging.js --confirm-live-data
node scripts/db/rds_readiness_probe.js --target=production --confirm=<fingerprint>
node scripts/db/schema_diff.js --target=production
node scripts/db/gateway_rls_authorization_suite.js
node scripts/db/service_role_paths_test.js
node scripts/db/real_path_authorization_e2e.js
npm test --prefix backend/functions
npm test --prefix services/api-gateway
flutter analyze (frontend)
flutter test (frontend)
node scripts/env/verify_env_file_policy.js
node scripts/audit/scan_env_example_history.js
```

---

*This report reflects only what was executed and inspected on 2026-11-12; it does not rely on prior chat summaries.*
