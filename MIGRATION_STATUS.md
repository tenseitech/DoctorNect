# DoctorNect migration status

**Branch:** `fix/pre-accept-gate-lab-auth`  
**Updated:** 2026-11-16 (gate close-out: `000005`, fresh `doctornect_rehearsal`, parity)  
**Evidence:** `docs/audit/prod_rds_readonly_diagnostic_2026-11-16T10-41-46-620Z.json`; `docs/audit/SECURITY_REVIEW_20261118000005.md`; local gate log `docs/audit-local/rehearsal_gate_2026-11-16.txt` (gitignored).

---

## Production RDS (read-only, 2026-11-16)

| Fact | Value | Proof |
|------|-------|-------|
| PG version | 18.3 aarch64 | diagnostic JSON `session.version` |
| `_schema_migrations` | **exists**, **0 rows** | diagnostic `ledger`, `migration_count.n=0` |
| `public` tables | **1** (`_schema_migrations` only) | diagnostic `object_inventory` |
| `auth` / `private` | empty (no user tables) | diagnostic `relkinds`, preflight |
| Bootstrap | **missing** (`auth.users` / `auth.uid()` not present) | preflight + diagnostic |
| `doctornect_admin` | `has_rds_superuser=true` (cluster role membership; not `rolsuper`) | diagnostic `role_exists` |
| pg_cron extension | installed in libraries; extension row `installed_version: null` in diagnostic snapshot | diagnostic `pg_cron`, `shared_preload_libraries` |
| `cron.database_name` | **UNVERIFIED** | diagnostic script printed `undefined` (not a verified prod GUC read) |

*Stale text “52 tables / no ledger” removed — superseded by 2026-11-16 diagnostic.*

---

## Migrations (repo vs ledgers)

| Target | SQL files in repo | Ledger rows | Notes |
|--------|------------------:|------------:|-------|
| **production / rehearsal** | **72** (`listMigrationsForTarget('production')`) | prod **0**; fresh rehearsal **71** after gate run | Rehearsal: `20260923000003_doctornect_cron.sql` **skipped** via `--allow-no-cron` (local engine); all other files applied incl. `20261118000005` (`55bb377+` fix) |
| **staging** | **71** (no `migrations/rds/*.sql`) | **62** rows (operator read-only) | Pending on staging (9): `20261116000001`, `20261117000001`–`000004`, `20261118000001`–`000005` |

`20261118000005` — **not** on prod/staging ledger (verify before cutover).

---

## Gates (path-specific)

| Gate | Status | Counts / proof |
|------|--------|----------------|
| `20261118000005` migrator fix (`doctornect_admin`) | **PASS** (local fresh rehearsal) | Root cause: `ALTER … OWNER TO service_role` needs **`CREATE` on schema `private` (and `public` for trigger fn)** for new owner — not migrator superuser. Commit `fecb472`; see `docs/audit/SECURITY_REVIEW_20261118000005.md` |
| Security review `000005` | **PASS** (design) | Four functions: pinned `search_path`; no `anon`/`PUBLIC` EXECUTE on BYPASSRLS helpers; `review_public` DML for trigger only |
| **rdsadmin** `replay_check` replay | **PASS** — **NOT a prod gate** | Harness **210/0**, gateway **74/0** (prior rdsadmin path; see `docs/reports/`) |
| **`doctornect_admin` rehearsal** (127.0.0.1:5442) | **FAIL** (harness) | Sequence exit **0** except harness **exit 1**: gateway **74/0** ✓; harness seed stops at `ambulance_trip_contacts` RLS (`docs/audit-local/rehearsal_harness2.txt`) — **not 210/0** |
| Parity `replay_check` vs `doctornect_rehearsal` | **UNVERIFIED** (noise) | **170** diffs (`docs/audit-local/schema_diff_gate.txt`); see breakdown below |
| Prod `migrate --execute` | **NO** | Ledger empty + bootstrap missing + cron/RLS gates |
| Go-live | **NO** | Prod catalog partial; rehearsal harness red |

---

## Fresh rehearsal sequence (2026-11-16, new `doctornect_rehearsal`)

Env: `PROD_RDS_*` → `127.0.0.1:5442`, `doctornect_admin`, `PROD_RDS_SSLMODE=disable` (local only).

| Step | Exit | Notes |
|------|-----:|-------|
| Drop/create DB (`docs/audit-local/_recreate_rehearsal_db.js`) | **0** | `OWNER doctornect_admin` |
| `prod_rds_reset_empty.js --execute` | **0** | empty catalog |
| `rds_bootstrap_apply.js --pre-migrate-only` | **0** | 01–03 |
| `migrate.js --execute --allow-no-cron` | **0** | Ledger **71/72**; cron file skipped |
| `rds_bootstrap_apply.js` (incl. 04) | **0** | runtime grants |
| `gateway_rls_authorization_suite.js --target=rehearsal` | **0** | **74 PASS / 0 FAIL** |
| `rls_sql_harness.js --target=rehearsal` | **1** | Seed RLS on `ambulance_trip_contacts` |

**pg_cron (local):** use `--allow-no-cron` only on local replay/rehearsal. Production RDS must run `20260923000003_doctornect_cron.sql` **without** that flag after `pg_cron` is available.

---

## Parity breakdown (replay_check → rehearsal, 170 diffs)

| Category | n | Direction | Expected? |
|----------|--:|-----------|-----------|
| `COLUMN` | 54 | `pg_stat_statements.*` **missing in rehearsal** | **Yes** — extension/view not installed on fresh rehearsal |
| `CONSTRAINT_EXTRA` | 84 | extras on **rehearsal** side (incl. stats view artifacts) | **Yes** / noise |
| `COLUMN_EXTRA` | 18 | rehearsal-only columns (stats) | **Yes** / noise |
| `FUNCTION_BODY` | 5 | body hash mismatch (same names) | **UNVERIFIED** — likely owner/`search_path`/replay skew |
| `GRANT_EXTRA` | 4 | grants present on **rehearsal** only | **UNVERIFIED** — compare table grant lines in diff log |
| `FUNCTION_MISSING` | 3 | `pg_stat_statements`, `pg_stat_statements_info`, `pg_stat_statements_reset` **in replay, missing in rehearsal** | **Yes** — `pg_stat_statements` bootstrap differs |
| `TRIGGER_EXTRA` | 1 | extra on **rehearsal** | **UNVERIFIED** |
| `EXTENSION_MISSING` | 1 | extension in replay not in rehearsal | **Yes** — stats extension |

---

## Prod cutover checklist (migrations)

- [ ] Snapshot + `prod_rds_reset_empty` / DB recreate plan  
- [ ] Bootstrap 01–03 pre-migrate  
- [ ] `migrate.js --execute` **72/72** ledger rows (no `--allow-no-cron` on prod)  
- [ ] Bootstrap 04 post-migrate  
- [ ] Gateway **74/0** + harness **210/0** on **`doctornect_admin`** rehearsal before prod execute  

---

## Key docs

| Doc | Purpose |
|-----|---------|
| `docs/audit/SECURITY_REVIEW_20261118000005.md` | `000005` function + grant review |
| `docs/audit/prod_rds_readonly_diagnostic_2026-11-16T10-41-46-620Z.json` | Prod catalog snapshot |
| `docs/RDS_MIGRATION_NORMALIZE.md` | RDS overrides vs staging SQL |
| `scripts/smoke/MANUAL_STEPS.md` | Rehearsal env (`5442`, `--allow-no-cron` local only) |