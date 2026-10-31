# Structure cleanup report (no secrets)

**Branch:** `cleanup/structure` (from committed audit/security work on `cleanup/remove-unused`)  
**Date:** 2026-10-31  
**Scope:** File/folder audit, deletion, and doc reorganization only — no app logic, migrations, infra, or CI changes.

## Summary

| Metric | Before | After |
|--------|--------|-------|
| Tracked files (`git ls-files`) | 1729 | 1746 |
| Git pack size | ~1.42 GiB | ~1.42 GiB (unchanged; no large blob removal) |
| `check_env_parity.js` | 0 undocumented (after prior env doc commit) | 0 undocumented |
| Backend tests (`CI=true`) | 475 pass / 0 fail | 475 pass / 0 fail |
| Gateway tests | 68 pass / 0 fail | 68 pass / 0 fail |

Renames preserve history via `git mv`. No `db/migrations/*` files edited or renamed.

## Step 0 — Pre-structure commits (on `cleanup/remove-unused`)

Logical commits landing audit/security work before structure branch:

- DB migration `20261103000008_staging_anon_security_cleanup.sql` + anon audit tooling  
- API gateway CORS / revocation  
- Functions Redis keys + deny-all Firestore rules  
- Flutter Postgres cutover + docs deliverables (commit message overlap — docs landed in same series as flutter)  
- Flutter source follow-up commit  

Then: `git checkout -b cleanup/structure`.

## Classification audit (top-level)

| Path | Class | Notes |
|------|-------|-------|
| `frontend/` | USED | Flutter app; `pubspec.yaml`, CI, Firebase |
| `backend/functions/` | USED | `firebase.json` `"source": "backend/functions"` |
| `services/api-gateway/` | USED | Production PostgREST proxy |
| `db/` | USED | Migrations + bootstrap — **frozen names** |
| `infra/` | USED | Terraform |
| `scripts/` | USED | migrate, harness, parity, e2e |
| `docs/` | USED | Runbooks, ops evidence |
| `adapters/`, `.agent/`, `.cursor/`, `.gemini/` | USED | Referenced by PROJECT_RULES / GEMINI docs |
| Root `functions/` (local only) | JUNK | Not tracked; orphan `.env` removed locally only |
| `leaks.json` | JUNK | Untracked scan output; gitignored |
| Root milestone `*.md` (13 files) | SUPERSEDED | Moved to `docs/archive/planning/` — grep: not in README/CI; cited in historical `docs/ops/test_runs/*` only |
| 23 Dart files in CLEANUP_MANIFEST | UNSURE | Zero static importers per manifest; **kept** (operator decision) |
| `docs/ops/test_runs/*` | USED | Linked from `docs/ops/REMAINING_WORK.md`, runbooks |
| `docs/reports/DOCTORNECT_AUDIT_REPORT.md` | DUPLICATE? | Superseded by verification report — **kept** (linked in ops docs) |

## Deleted / removed from git

| Path | Category | Evidence |
|------|----------|----------|
| (none new this pass) | — | Prior branch already removed `run_plpgsql_check.sql`, `docs/ops/rls_sql_harness_results.json` |

## Moved (git mv)

| Old path | New path |
|----------|----------|
| `ENV_MATRIX.md` | `docs/ENV_MATRIX.md` |
| `RDS_MIGRATION_RUNBOOK.md` | `docs/runbooks/RDS_MIGRATION_RUNBOOK.md` |
| `DOCTORNECT_FINAL_AUDIT.md` | `docs/reports/DOCTORNECT_FINAL_AUDIT.md` |
| `AUDIT_REPORT.md` | `docs/archive/planning/AUDIT_REPORT.md` |
| `FIRESTORE_REMAINING.md` | `docs/archive/planning/FIRESTORE_REMAINING.md` |
| `GSD-STYLE.md` | `docs/archive/planning/GSD-STYLE.md` |
| `implementation_plan.md` | `docs/archive/planning/implementation_plan.md` |
| `MIGRATION_PLAN.md` | `docs/archive/planning/MIGRATION_PLAN.md` |
| `PHASE_A_REPORT.md` | `docs/archive/planning/PHASE_A_REPORT.md` |
| `PHASE_D_REPORT.md` | `docs/archive/planning/PHASE_D_REPORT.md` |
| `PHASE_E_PLAN.md` | `docs/archive/planning/PHASE_E_PLAN.md` |
| `PLATFORMS.md` | `docs/archive/planning/PLATFORMS.md` |
| `PRE_LAUNCH_CUTOVER.md` | `docs/archive/planning/PRE_LAUNCH_CUTOVER.md` |
| `PROJECT_RULES.md` | `docs/archive/planning/PROJECT_RULES.md` |
| `STEP2_VERIFICATION.md` | `docs/archive/planning/STEP2_VERIFICATION.md` |
| `STEP3_VERIFICATION.md` | `docs/archive/planning/STEP3_VERIFICATION.md` |

Link updates in same commit: `docs/ENV_MATRIX.md`, `docs/reports/DOCTORNECT_FINAL_AUDIT.md`, `scripts/db/safe_env_local_fix.js` (comment path only), `README.md` (structure pointer).

## `.gitignore` additions

- `**/firestore-debug.log`
- `flutter_*.log`, `flutter-web-*.log`
- `backend/functions/.env.bak*`
- (existing) `leaks.json`, `docs/ops/rls_harness_results.json`

## Env variables

No env **values** read or changed. No variables removed from `.env.example` in this pass.

## Needs your decision

1. **`docs/ops/test_runs/`** (~80+ tracked logs) — historical evidence vs repo size; many runbook links.  
2. **`docs/reports/DOCTORNECT_AUDIT_REPORT.md`** vs `DOCTORNECT_VERIFICATION_REPORT.md` — likely duplicate; ops docs still mention both.  
3. **23 zero-importer Dart widgets** — listed in `docs/ops/CLEANUP_MANIFEST.md` (deleting = behavior/UI scope).  
4. **`.agent/` / `.agents/` / `adapters/`** — IDE/agent tooling; safe to keep unless you want a slim public fork.  
5. **`scripts/codemods/`** — manual one-shot; referenced in audit report.  
6. **Duplicate `backend/functions/.env.example` path** in glob (single file) — no action.

## Verification (after structure commit)

| Check | Result |
|-------|--------|
| `node scripts/check_env_parity.js` | PASS — 0 undocumented core vars |
| `backend/functions` `CI=true npm test` | PASS — 475 / 0 |
| `services/api-gateway npm test` | PASS — 68 / 0 |
| `node --test scripts/db/anon_surface_audit.test.js scripts/lib/db_connection_guard.test.js` | PASS — 4 / 0 |
| `firebase.json` functions source | PASS — still `backend/functions` |
| `flutter test` (full) / `flutter analyze` | Not re-run in this pass — run before merge |
| `migrate.js --dry-run-all` | Not re-run post-move (no script path changes) |

## Out of scope (not changed)

- Application logic, dependencies, Terraform, CI workflows, migration SQL content  
- Admin module  
- Firestore repository fallback branches in Flutter  
- Comment removal pass  

See **PROJECT_STRUCTURE.md** for the target layout going forward.
