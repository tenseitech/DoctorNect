# DoctorNect migration status

**Branch:** `fix/pre-accept-gate-lab-auth`  
**Updated:** 2026-11-17 (`5800216`; harness **210** re-run **UNVERIFIED** — Docker `127.0.0.1:5442` down)  
**Evidence:** `docs/audit/HARNESS_SEED_ROOT_CAUSE.md`; `docs/audit/PG_CRON_MIGRATION_READING.md`; `docs/audit/prod_rds_readonly_diagnostic_2026-11-16T10-41-46-620Z.json`.

---

## Production RDS (read-only, 2026-11-16)

| Fact | Value | Proof |
|------|-------|-------|
| PG version | 18.3 aarch64 | diagnostic JSON `session.version` |
| `_schema_migrations` | **exists**, **0 rows** | diagnostic `ledger`, `migration_count.n=0` |
| `public` tables | **1** (`_schema_migrations` only) | diagnostic `object_inventory` |
| `auth` / `private` | empty (no user tables) | preflight / diagnostic |
| Bootstrap | **missing** (`auth.users` / `auth.uid()` not present) | preflight + diagnostic |
| `cron.database_name` | **UNVERIFIED** | diagnostic printed `undefined` |

---

## Migrations (repo vs ledgers)

| Target | SQL files | Ledger | Notes |
|--------|----------:|-------:|-------|
| **production / rehearsal** | **72** | prod **0**; rehearsal **UNVERIFIED** after 2026-11-17 | Local `:5442` unavailable 2026-11-17 |
| **staging** | **71** | **62** rows (read-only) | Pending (9): `20261116000001`, `20261117000001`–`000004`, `20261118000001`–`000005` |

`20261118000005` — **not** on prod/staging ledger.

---

## Gates

| Gate | Status | Counts / proof |
|------|--------|----------------|
| Harness seed root cause | **PASS** (code) | `09b62dd` — trigger DEFINER on pending `ambulance_broadcasts`; see `docs/audit/HARNESS_SEED_ROOT_CAUSE.md` |
| `000005` + REVOKE CREATE | **PASS** (code) | `9dcc1fa` — `ALTER FUNCTION private.trg_ambulance_broadcast_contact_guard() OWNER TO service_role` + `REVOKE CREATE` |
| **`doctornect_admin` rehearsal harness 210** | **UNVERIFIED** | Fix landed; need fresh `doctornect_rehearsal` + `rls_sql_harness.js` (2026-11-16 baseline: **74/0** gateway, harness **FAIL**) |
| **`doctornect_admin` rehearsal gateway 74** | **UNVERIFIED** | Re-run with harness after Docker up |
| rdsadmin `replay_check` | **PASS** — **NOT prod gate** | Prior **210/0**, **74/0** (see `docs/reports/`) |
| Parity filtered | **UNVERIFIED** | `schema_diff.js` drops `pg_stat_statements` noise; see `docs/audit/PARITY_REPLAY_REHEARSAL_FILTERED.md` |
| pg_cron local apply | **UNVERIFIED** | `rdslike-pg18` image has no `pg_cron`; reading in `docs/audit/PG_CRON_MIGRATION_READING.md` |
| Prod `migrate --execute` | **NO** | — |

---

## Prior rehearsal (2026-11-16, `doctornect_admin`, `:5442`)

| Step | Exit | Notes |
|------|-----:|-------|
| Full migrate + bootstrap 04 | **0** | Ledger **71/72** (`--allow-no-cron`) |
| Gateway | **0** | **74 / 0** |
| Harness | **1** | Seed trip_contacts (pre trigger-owner fix) |

**Post-fix expectation:** seed logs per-step `session_user` / `current_user` / `bypassrls`; verify `has_schema_privilege('service_role', …, 'CREATE')` = false after migrate.

---

## Prod cutover checklist

- [ ] `migrate.js --execute` **72/72** (no `--allow-no-cron` on prod)  
- [ ] Bootstrap 04 post-migrate  
- [ ] **`doctornect_admin`**: gateway **74/0** + harness **210/0** on same rehearsal DB  

---

## Key docs

| Doc | Purpose |
|-----|---------|
| `docs/audit/HARNESS_SEED_ROOT_CAUSE.md` | Seed vs trigger DEFINER |
| `docs/audit/SECURITY_REVIEW_20261118000005.md` | Owner moves + grants |
| `docs/audit/PG_CRON_MIGRATION_READING.md` | Scheduled jobs inventory |
| `docs/audit/PARITY_REPLAY_REHEARSAL_FILTERED.md` | Parity minus stats noise |