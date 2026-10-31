# DoctorNect — Dedupe & Structure Audit Report

**Branch:** `chore/dedupe-structure-audit`  
**Safety baseline commit:** `5c107e9` (`chore: safety snapshot before dedupe-structure audit`)  
**Env file backup (outside repo):** `C:\Users\khije\doctornect-env-backup\20261031-170022\`  
**Rules:** No secret values in this document. Local-only; nothing pushed.

---

## Baseline metrics (before dedupe actions)

| Metric | Value |
|--------|--------|
| Git tracked files | 1670 |
| Working tree files (excl. node_modules, build, .dart_tool, .git) | 1906 files, 418 dirs |
| SQL migrations (`db/migrations/*.sql`) | 48 |
| Exact duplicate content groups (code/text, excl. large binaries) | 47 |
| `flutter analyze` | **PASS** — 0 issues (after commit `fff59e4`) |
| `flutter test` | **FAIL** — 546 pass / 13 fail (unchanged; `auth_flows_test.dart`) |
| Backend `npm test` (default, no emulators) | **PASS** — 471 pass / 0 fail / **22 skipped** (493 total) |
| Backend `npm test` + Firestore/Storage emulators | **Mixed** — 591 pass / 139 fail / **5 skipped** (735 total); **17** of 22 former skips now execute (emulator-gated rules/emulator suites). Remaining **5 skips** = local Docker Postgres on `127.0.0.1:54322` (Docker Desktop was **not running** on audit machine). Command: `npx firebase-tools emulators:exec --only firestore,storage --project demo-doctornect-test "npm test --prefix backend/functions"`. Re-run after SQL/rules/config phases with emulators + `npx supabase start` in `backend/` when Docker is available. |
| `check_env_parity.js` | **PASS** (0 undocumented core vars at last run on parent branch) |

---

## Phase 0 — Inventory

### Entry points

| Component | Path | Present |
|-----------|------|---------|
| Flutter app | `frontend/lib/main.dart` | yes |
| Cloud Functions | `backend/functions/index.js` | yes |
| Firebase config | `firebase.json` → `backend/functions`, `backend/firestore.rules` | yes |
| Flutter deps | `frontend/pubspec.yaml` | yes |
| DB migrations | `db/migrations/` | yes (48) |
| API gateway | `services/api-gateway/` | yes |
| Terraform | `infra/` (e.g. `infra/aws/secrets.tf`) | yes |
| Supabase folder | `supabase/` | yes |

### Top-level layout (production-relevant)

```
doctor/
  frontend/          # Flutter app
  backend/           # firestore.rules, functions/, indexes
  db/migrations/     # Postgres/RLS migrations
  services/api-gateway/
  scripts/           # ops, db, codemods, audit
  docs/
  infra/
  firebase.json
```

**Structural anomalies (Phase 1 input):**

- **`functions/` at repo root** — not tracked by git; contains `node_modules/` + `firestore-debug.log` only. Canonical functions path is **`backend/functions`** per `firebase.json`. **Action pending:** quarantine/remove local orphan (proof: zero tracked files under `functions/`).
- **`backups/`** — staging logical backup NDJSON + manifests (2026-10-29). **Human decision:** keep outside git / move to external storage; may contain operational data.
- **`.agent/` vs `.cursor/`** — duplicate `ui-ux-pro-max` skill CSV trees (47 exact-hash duplicate groups include these paths).
- **Dot/tool dirs:** `.agent`, `.agents`, `.artifacts`, `.bin`, `.cursor`, `.firebase`, `.gemini`, `.gsd`, `.vscode` — mostly IDE/agent metadata; not app runtime.

### Reference graph (how “unused” is proved)

- **Dart:** `frontend/lib/**` import graph + `pubspec.yaml` assets + tests under `frontend/test/`.
- **Functions:** `backend/functions/index.js` exports + `require()` graph + `npm test`.
- **Firebase:** `firebase.json` paths → `backend/firestore.rules`, `backend/firestore.indexes.json`, `backend/storage.rules`.
- **SQL:** ordered filenames in `db/migrations/`; applied ledger via `scripts/db/migrate.js` (not run in this audit).
- **Scripts:** references from `package.json`, `docs/`, CI under `.github/`.

Audit automation added:

- `scripts/audit/phase0_inventory.js`
- `scripts/audit/env_matrix_conflicts.js`

---

## Phase 2 — Env files (names only)

### Files discovered

| Path | Exists | Git tracked | Role |
|------|--------|-------------|------|
| `.env` | yes | **no** (ignored) | Local dev / release build keys (client Firebase keys only in scan) |
| `.env.example` | yes | yes | Root template (client + infra names) |
| `.env.migration` | yes | **no** | Migration/infra operator file |
| `backend/functions/.env` | yes | **no** | Functions runtime secrets |
| `backend/functions/.env.example` | yes | yes | Functions template |
| `backend/.env.migration.example` | yes | yes | Migration CLI template |
| `frontend/.env.example` | yes | yes | Client public config template |

**Git tracked secret files:** none of `.env` / `.env.migration` / `backend/functions/.env`.  
**Tracked examples only:** `*.env.example`, `.secret.local.example`, `firebase_options.secrets.example.dart`.

### Variable name inventory by file (keys only)

<details>
<summary>`.env` (untracked) — 5 keys</summary>

`FIREBASE_API_KEY_WEB`, `FIREBASE_API_KEY_ANDROID`, `FIREBASE_API_KEY_IOS`, `RECAPTCHA_SITE_KEY`, `APP_CHECK_DEBUG_TOKEN`
</details>

<details>
<summary>`.env.example` (root) — 58 unique keys</summary>

Includes: `APP_ENV`, gateway vars (`PROD_GATEWAY_*`, `STAGING_SUPABASE_*`), Firebase/App Check, MSG91, Razorpay, AWS/S3, Redis, RDS (`PROD_RDS_*`), feature flags (`USE_SUPABASE_DB_DOCTOR_PATIENT`, `FIRESTORE_FORBIDDEN`, `NOTIFICATION_DISPATCH_MODE`, `ENABLE_SUPABASE_SYNC`, …), admin email allowlists.
</details>

<details>
<summary>`.env.migration` — 27 keys (note duplicate key names in file: `STAGING_SUPABASE_URL`, `STAGING_SUPABASE_SERVICE_ROLE_KEY` appear twice)</summary>

`STAGING_SUPABASE_DB_URL`, `STAGING_SUPABASE_URL`, `STAGING_SUPABASE_ANON_KEY`, `STAGING_SUPABASE_SERVICE_ROLE_KEY`, `FIRESTORE_TEST_COLLECTION_PREFIX`, `PROD_RDS_*`, `REPLAY_DB_URL`, `APP_ENV`, `FIREBASE_PROJECT_ID`, `PROD_GATEWAY_*`, `PGRST_*`, `SERVICE_ROLE_KEY`, `ANON_KEY`, `FIREBASE_REVOCATION_CHECK`, `CORS_ALLOWED_ORIGINS`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`
</details>

<details>
<summary>`backend/functions/.env` — 36 keys</summary>

OTP/App Check, reviewer vars, MSG91, Razorpay, S3 (`S3_BUCKET`, `S3_BUCKET_NAME`, `AWS_S3_VAULT_BUCKET`), Supabase (`SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `SUPABASE_SECRET_KEY`, `SUPABASE_ANON_KEY`, …), Redis, `RATE_LIMIT_BACKEND`, sync flags, `USE_SUPABASE_DB_DOCTOR_PATIENT`
</details>

<details>
<summary>`backend/functions/.env.example` — canonical functions template (69 keys)</summary>

Superset of functions runtime; includes `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_WEBHOOK_SECRET`, `DATABASE_URL`, `SUPABASE_DB_URL`, demo/reviewer placeholders.
</details>

<details>
<summary>`frontend/.env.example` — 14 keys</summary>

`FIREBASE_*`, `RECAPTCHA_SITE_KEY`, `APP_CHECK_DEBUG_TOKEN`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `USE_SUPABASE_AUTH`, `ENABLE_SUPABASE`, `USE_SUPABASE_DB_DOCTOR_PATIENT`, demo flags, `USE_S3_STORAGE`
</details>

### Cross-file matrix summary

- **104** distinct variable names across 7 files.
- **76** names appear in more than one file (expected overlap between examples and live `.env`).
- **44** names have **different value hashes** across files (includes empty-placeholder vs filled `.env` — **not all are true conflicts**).

### Alias / duplicate naming (needs one convention)

| Concept | Names found | Proposed canonical |
|---------|-------------|-------------------|
| Supabase service role | `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_SECRET_KEY`, `SUPABASE_SERVICE_KEY`, `SERVICE_ROLE_KEY` | `SUPABASE_SERVICE_ROLE_KEY` |
| Supabase URL | `SUPABASE_URL`, `STAGING_SUPABASE_URL` | `SUPABASE_URL` (runtime); staging prefix in examples only |
| S3 bucket | ~~triple alias~~ | **`S3_BUCKET` only** in examples; legacy reads in `src/config/s3_bucket.js` until 2026-06-30 — see `docs/S3_BUCKET_CANONICAL.md` |
| MSG91 auth | `MSG91_AUTH_KEY`, (legacy `MSG91_AUTHKEY`, `AUTH_KEY` in code) | `MSG91_AUTH_KEY` |

### Human decisions required (values differ — hashes only in `docs/_audit_env_conflicts.json`)

1. **`USE_SUPABASE_DB_DOCTOR_PATIENT`** — root/frontend examples vs `backend/functions/.env` (different hashes).
2. **`FIRESTORE_FORBIDDEN`** — root `.env.example` vs `backend/functions/.env.example`.
3. **`STAGING_SUPABASE_DB_URL`** — root `.env.example` vs `.env.migration` vs `backend/.env.migration.example`.
4. **`PROD_RDS_HOST`** — root example vs `.env.migration`.
5. **`S3_BUCKET` vs `S3_BUCKET_NAME`** — same logical bucket, three names in functions env.
6. **`ENABLE_SUPABASE` vs `USE_SUPABASE_DB_DOCTOR_PATIENT`** — frontend build uses `ENABLE_SUPABASE=1` in `release_build.ps1`; align naming in examples.
7. **`USE_SUPABASE_AUTH`** — still in `frontend/.env.example`; verify dead in code before removal.

### Target env layout (planned — not merged yet)

| Purpose | Canonical file | Secrets in file? |
|---------|----------------|------------------|
| Client public config | `frontend/.env.example` + root `.env` for local build keys only | **Never** service role |
| Functions runtime | `backend/functions/.env` + `.env.example` | Yes (local); SM in prod |
| Migration/infra CLI | `.env.migration` + `backend/.env.migration.example` | Yes (local only) |
| Root index | `.env.example` points to frontend / functions / migration templates; **zero runtime keys** | Names + comments only |

---

## Phase 1 — Duplicate detection (initial)

| Category | Finding | Action |
|----------|---------|--------|
| A Exact duplicates | 47 groups (includes IDE skill mirrors) | **Out of scope:** `.agent/`, `.agents/`, `.cursor/` skill trees excluded from dedupe |
| B Near-duplicates | No `*_old` / `.bak` suffix files found in scan | — |
| G Config | Single `backend/firestore.rules`; single `firebase.json` | OK |
| I Backups | `backups/staging_logical_*` duplicates DB snapshot | **Quarantine / externalize** (not delete without approval) |
| Structure | Root `functions/` orphan | **Deleted** locally (2026-10-31); canonical `backend/functions` |
| I Backups | `backups/` untracked (~84 files) | **`backups/` in .gitignore**; folder kept on disk |
| A Exact duplicates | `.artifacts/reports/baseline_functions.json` = `docs/ops/baseline_cloud_functions.json` | **No local copy** at audit time; canonical tracked path `docs/ops/baseline_cloud_functions.json` per `docs/ops/baselines.json` |
| A Exact duplicates | `.agent/skills/ui-ux-pro-max/**` mirrors `.cursor/skills/ui-ux-pro-max/**` (55 vs 28 tracked) | **Pending human** — pick one IDE skill root before delete |

### Phase 1 batch — docs / SQL / Dart (2026-10-31)

| Category | Finding | Action |
|----------|---------|--------|
| I Docs | 21 audit/verification/report markdown files (`FINAL_VERIFICATION`, `FULL_AUDIT`, `SECURITY_AUDIT_v2`, archive planning, etc.) | **Flag only** — supersession order TBD; no deletes |
| H SQL | 48 migrations; **199** unique policy names; many names appear in 2–6 files (e.g. `users_*`, `doctors_*` across `20260923…`, `20261008…`, `20261020…`) | **Flag only** — idempotent `DROP POLICY IF EXISTS` pattern; do not edit applied migrations |
| C Dart | Cross-role duplicate basenames under `features/{doctor,patient,pharmacy,lab,ambulance}/` | **0 groups** (same filename in multiple roles) — deeper AST dedupe deferred |
| Env | Templates collapsed — see `docs/ENV_STAGING_RDS_READERS.md`, `docs/FLAGS_CUTOVER_PROPOSAL.md` | Root index only; disjoint function/frontend/migration templates |

**Test baselines:** No new Flutter or emulator failures vs `docs/baseline_flutter_failing_tests.txt` / `docs/baseline_failing_tests.txt` (no full flutter test re-run this batch; `flutter analyze` **0 issues**).

### Phase 1 verification policy (this branch)

- Per batch: `dart analyze` on touched Dart paths only.
- End of each phase: full `flutter analyze`.
- Backend: default `npm test` must stay **471 pass / 0 fail / 22 skip**; optional emulator+Docker matrix documented above (not a merge gate while Docker off).

---

## Rollback

```powershell
git checkout feature/postgres-only-architecture
git branch -D chore/dedupe-structure-audit   # optional
git reset --hard 5c107e9                       # safety snapshot
# Restore env files from:
# C:\Users\khije\doctornect-env-backup\20261031-170022\
```

---

## Commit log (this audit branch)

| Commit | Message |
|--------|---------|
| `5c107e9` | Safety snapshot (empty commit on parent HEAD) |
| `a3c39dd` | Phase 0 audit scripts + initial report |
| `fff59e4` | fix: clear pre-existing analyze issues |
| (pending) | Phase 1 structure gitignore + report baseline updates |

---

*Report updated continuously through phases 1–4.*
