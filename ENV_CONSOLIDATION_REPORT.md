# Environment consolidation report

**Date:** 2026-11-12  
**Branch:** current working branch (`fix/pre-accept-gate-lab-auth` context)  
**Policy:** Exactly two env-style files in the repo tree — **`.env`** (gitignored, real values) and **`.env.example`** (committed, placeholders).

---

## 1. Before → after (files)

| Before (examples) | After |
|---|---|
| `.env`, `.env.example`, `.env.migration`, `.env.migration.example` | **Removed** — merged into root `.env` |
| `backend/.env.migration.example` | **Removed** (`git rm`) |
| `backend/functions/.env`, `backend/functions/.env.example` | **Removed** from tree; deploy-time **generated** only |
| `frontend/.env.example` | **Removed** (`git rm`) |
| Flutter `flutter_native_integration.env` under `ephemeral/` | Build artifact; **ignored** by policy check |

**Verified:** `node scripts/env/verify_env_file_policy.js` → only `.env` + `.env.example` at repo root.

---

## 2. Inventory (readers)

| Consumer | Loads |
|---|---|
| `scripts/lib/env_loader.js` | Repo root `.env` via `bootstrap_root_env.js` |
| `scripts/db/*` (migrate, smoke, schema tools) | Same |
| `backend/functions/index.js` (local) | `loadRootEnv()` at cold start |
| Firebase deploy | `predeploy`: `materialize_functions_env.js` → transient `backend/functions/.env`; `postdeploy`: `cleanup_functions_env.js` |
| `services/api-gateway/src/server.js` | `loadRootEnv()` |
| Flutter release | `frontend/scripts/release_build.ps1` → repo root `.env`; optional `scripts/env/generate_flutter_dart_defines.js` (client-safe keys only) |
| CI | `.github/workflows/env-policy.yml` → `ci_env_checks.js` + `env_parity.test.js` |

Legacy multi-file merge (one-time): `scripts/env/merge_local_env_files.js` (precedence documented in script).

---

## 3. Merge & conflicts

| Metric | Value |
|---|---|
| Keys merged into root `.env` | 71 |
| Name conflicts (different values) | **0** (`docs/reports/env_merge_conflicts.json`) |
| `.env` ↔ `.env.example` key parity | **123** keys (`verify_env_key_parity.js`) |
| Alias removed | `SUPABASE_SECRET_KEY` (use `SUPABASE_SERVICE_ROLE_KEY`) |

**Backup (outside repo):** `C:\Users\khije\env_backup_2026-11-12`  
(flattened copies: `backend__functions__.env`, `.env.migration`, etc.)

---

## 4. Flutter / client safety

- Release script **allowlists** dart-define keys; rejects `SUPABASE_SERVICE_ROLE_KEY` in the build environment.
- `generate_flutter_dart_defines.js` exports only client-safe keys and **fails** if forbidden server keys are non-empty in root `.env`.
- **Finding:** `release_build.ps1` `-Launch` profile still embeds a staging anon JWT for local convenience — treat as public anon key, not service-role; prefer repo root `.env` for releases.

---

## 5. Verification run (this session)

| Check | Result |
|---|---|
| `npm run env:verify` | PASS |
| `scripts/check_env_parity.js` | PASS (0 duplicate concepts) |
| `backend/functions` `npm test` (incl. `env_parity`) | PASS |
| `services/api-gateway` `npm test` | 68 pass |
| `db_connectivity_smoke.js --env=staging` | PASS (read-only) |
| `scripts/test/env_loader.test.js` | PASS |

Production DB / RDS mutating commands were **not** run.

---

## 6. Git history — variable names to review for rotation

`node scripts/audit/scan_env_example_history.js` flagged **names** (not values) that looked real in **old committed templates**:

- `STAGING_SUPABASE_DB_URL`
- `STAGING_SUPABASE_URL`
- `SUPABASE_URL`
- `S3_BUCKET`, `S3_BUCKET_NAME`, `AWS_S3_VAULT_BUCKET`
- `SUPABASE_WEBHOOK_SECRET`

If any of these were ever real production credentials in git history, **rotate** the corresponding secrets and update root `.env` only locally.

---

## 7. Operator manual steps

1. Keep all secrets in **repo root `.env`** (copy from `.env.example` on new machines).
2. After pulling: `npm run env:verify` and `node scripts/env/sync_env_missing_keys.js` if parity fails.
3. Firebase deploy: no manual `backend/functions/.env` — materialize/cleanup runs from `firebase.json`.
4. Optional pre-commit: `node scripts/env/staged_env_file_guard.js`.
5. Flutter release: from `frontend/`, `.\scripts\release_build.ps1` (loads parent repo `.env`).

---

## 8. Docs updated

- `ENVIRONMENTS.md` — §0 single root `.env`
- `DB_MIGRATION_VERIFICATION.md` — secrets §8, RDS config pointers
- `docs/runbooks/RDS_CUTOVER_STEPS.md` — root `.env` (not `.env.migration`)
- Root `.env.example` — unified sections (APP_ENV, Firebase, staging Supabase, RDS, gateway, Redis, S3, MSG91, Razorpay, Flutter, Functions)

Remaining doc references to legacy paths may exist in historical reports under `docs/reports/`; treat root `.env` as authoritative.
