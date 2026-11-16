# DoctorNect migration status

**Branch:** `fix/pre-accept-gate-lab-auth`  
**Updated:** 2026-11-16 (local rdslike replay harness; prod/staging ledger wording)  
**Evidence:** `docs/audit/PROD_RDS_FORENSICS.md` / `.json` (read-only prod); harness reports under `docs/reports/`; local proof under `docs/audit-local/` (gitignored).

---

## Overall completion **~78%**

`Σ(weight×score)` ≈ `0.35×84 + 0.25×72 + 0.15×60 + 0.10×85 + 0.10×88 + 0.05×90`  
Weights: Firestore 35%, RDS 25%, demo routing 15%, Redis/S3 10%, env policy 10%, tests 5%.

| Area | Score | Proof |
|------|------:|-------|
| Firestore | 84% | `FIRESTORE_REACHABLE_RELEASE.md` → 0 LIVE |
| RDS | 72% | **Production** RDS: 52 public tables, **`_schema_migrations` absent**, **1 table / 2 rows** — `PROD_RDS_FORENSICS.json`. **Staging** Supabase: migration ledger applied through **20261104000001** (per `live_data_guard.js` ghost baseline; re-verify on staging before apply). Local rdslike replay: **66 migrations**, harness **199/210** (2026-11-16) — `docs/audit-local/harness_run_*.txt` |
| Demo routing | 60% | Code **PASS**; live **UNVERIFIED** |
| Tests | 90% | `backend/functions` **565 pass / 0 fail**; `scripts/test` **102/0**; RLS harness **20+12 FAIL** |
| Env | 88% | `npm run env:verify` **PASS** (infra fingerprints fixed) |

---

## CURRENT GATE TABLE

| Gate | Status | Proof | Owner |
|------|--------|-------|-------|
| `.env` not in git | **PASS** | `.gitignore:65` | Cursor |
| Prod forensics (read-only) | **PASS** | `node scripts/db/prod_rds_forensics.js` → `PROD_RDS_FORENSICS.md` | Cursor |
| Prod partial schema / **no migration ledger** | **FAIL** | Production DB: `ledger_exists: false` (`PROD_RDS_FORENSICS.json`); **not** the staging ledger | Main |
| COMMIT leak hypothesis | **PLAUSIBLE** | Forensics §hypothesis; `migration_txn_sql.js` skips COMMIT today | Cursor |
| Preflight “0 tables” at 20:17 | **EXPLAINED** | `phase1_rds_preflight.js` DB default `postgres` vs `doctornect` | Cursor |
| `migrate --dry-run-all` prod safety | **PASS** (code) | Scratch DB + tripwire — `migrate.js` + `migrate_scratch_db.js` — **live scratch run UNVERIFIED** | Cursor |
| `prod_rds_reset_empty.js` | **PASS** (dry-print) | `node scripts/db/prod_rds_reset_empty.js` (no `--execute`) | Main |
| `normalize` rules documented | **PASS** | `docs/RDS_MIGRATION_NORMALIZE.md` | Cursor |
| RLS harness 210 | **FAIL** | Staging **20** FAIL (UNVERIFIED re-run); rdslike `replay_check` **199 PASS / 11 FAIL** (2026-11-16) — `docs/audit/RLS_HARNESS_FAIL_TRIAGE.md` | Cursor |
| `backend/functions` tests | **PASS** | **565/0** (2026-11-15) | Cursor |
| Gateway provisioning + Functions → gateway | **PASS** | Removed `x-data-plane` client header — `client.js`; tests green | Cursor |
| `scripts/test` + `env:verify` | **PASS** | **102/0**; env verify exit 0 | Cursor |
| Supabase keepalive live | **UNVERIFIED** | Code/tests only | Main |
| Demo/real live isolation | **UNVERIFIED** | — | Main |
| `migrate --execute` prod | **NO** | Ledger missing + row residue + pg_cron + RLS gaps | Main |

---

## `migrate --execute` on production?

**NO** — reset or reconciliation plan required (`PROD_RDS_FORENSICS.md`, `prod_rds_reset_empty.js` + snapshot). Dry-run **must** use scratch DB path only (never mutate `doctornect`).

## Go-live?

**NO** — CRITICAL: ambiguous prod catalog; HIGH: RLS harness; HIGH: live gateway/ECS/keepalive **UNVERIFIED**.

## Key docs

| Doc | Purpose |
|-----|---------|
| `docs/audit/PROD_RDS_FORENSICS.md` | Prod catalog, row counts, migration footprint |
| `docs/audit/RLS_HARNESS_FAIL_TRIAGE.md` | Per-case harness failures |
| `docs/RDS_MIGRATION_NORMALIZE.md` | RDS normalize rules vs staging original SQL |
| `scripts/smoke/MANUAL_STEPS.md` | Operator runbooks |

*Historical module matrices and duplicate release-gate tables removed 2026-11-15 — use this file + audit JSON only.*