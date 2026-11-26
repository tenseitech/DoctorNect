# Production RDS cutover runbook

**Branch:** `migration-cutover-fixes`  
**Hard stops:** No prod `--execute` without **`APPROVED FOR PROD`** (your verbal/written approval) **and** live-data guards. Production migrate/bootstrap **`--confirm=`** is always the **full `PROD_RDS_HOST` hostname**, not the approval phrase. TLS required (`PROD_RDS_SSLMODE=require`); never disable SSL.

| Step | Who | Credentials | Reversible? |
|------|-----|-------------|-------------|
| 0 Snapshot check | You / DBA | AWS IAM | N/A (read-only) |
| 1 Bootstrap **01** | **You** (master) | RDS **master** via tunnel | Partially |
| 2 Bootstrap **02–03** | Agent / you | **`doctornect_admin`** | Partially |
| 3 Preflight | Agent | tunnel read-only | Yes |
| 4 `dry-run-all` | Agent | **`doctornect_admin`** | Yes |
| 5 `execute` | Agent (after approval) | **`doctornect_admin`** | **No** |
| 6 Bootstrap **04** | **You** or agent | **`rdsadmin`** or master | Partially |
| 7 Gates | Agent | tunnel roles | Yes (read-only) |

---

## 0 — RDS snapshot (read-only; do not create here)

```powershell
Test-NetConnection 127.0.0.1 -Port $env:PROD_RDS_PORT
aws rds describe-db-snapshots --db-instance-identifier <instance-id> --query "DBSnapshots | sort_by(@,&SnapshotCreateTime) | [-1]" 
aws rds describe-db-instances --db-instance-identifier <instance-id> --query "DBInstances[0].BackupRetentionPeriod"
```

**Expected:** Latest snapshot time recorded; `BackupRetentionPeriod` &gt; 0.  
**On failure:** Abort cutover until backup posture is clear.

---

## 1 — Bootstrap `01_roles_and_extensions.sql` (**master only**)

`rds_bootstrap_apply.js` connects as **`doctornect_admin`** from `buildRdsPoolConfig()` — **insufficient for 01**. Use master:

```powershell
psql "postgresql://<master_user>:****@127.0.0.1:$($env:PROD_RDS_PORT)/doctornect?sslmode=require" `
  -v ON_ERROR_STOP=1 -f db/rds_bootstrap/01_roles_and_extensions.sql
```

**Expected:** Roles `anon`, `authenticated`, `service_role`, `doctornect_admin`, `authenticator`; extensions including `pgcrypto`; conditional `GRANT EXECUTE ON pg_stat_statements_reset() TO doctornect_admin` (in **01**, not **04**).  
**Undo:** Hard — role drops are destructive.

---

## 2 — Bootstrap `02` + `03` (`doctornect_admin`)

```powershell
node scripts/db/rds_bootstrap_apply.js --target=production --execute --pre-migrate-only `
  --confirm-live-data --confirm=<PROD_RDS_HOST> --confirm-db=doctornect
```

**Expected:** `auth` shim, `private` schema, `GRANT USAGE ON SCHEMA private TO authenticated`.  
**On failure:** Stop; do not migrate.

---

## 3 — Preflight (read-only)

```powershell
node scripts/audit/_prod_greenfield_readonly.js
node scripts/db/prod_rds_preflight_readonly.js
node scripts/db/migrate.js --target=production --dry-run --confirm-live-data --confirm-db=doctornect --confirm=<PROD_RDS_HOST>
```

---

## 4 — `dry-run-all`

```powershell
node scripts/db/migrate.js --target=production --dry-run-all --confirm-live-data --confirm-db=doctornect --confirm=<PROD_RDS_HOST>
```

**Do not** pass `--allow-no-cron` on production.

---

## 5 — Migrate execute (requires your **`APPROVED FOR PROD`** + host confirm)

```powershell
node scripts/db/migrate.js --target=production --execute --confirm-live-data --confirm-db=doctornect --confirm=<PROD_RDS_HOST>
```

Optional: `node scripts/db/rds_readiness_probe.js --target=production --confirm=<PROD_RDS_HOST>` before/after.

**Expected:** **77** ledger versions (76 shared + `rds/20261113000001`; cron file applies if pg_cron available).  
**Undo:** Restore snapshot / logical restore only.

---

## 6 — Bootstrap `04_rds_runtime_grants.sql` (post-migrate)

**Recommended (script, all of 04 only):**

```powershell
# 04 only: apply via psql as rdsadmin/master (script applies 01–04 if you omit --pre-migrate-only)
psql "postgresql://rdsadmin:****@127.0.0.1:$($env:PROD_RDS_PORT)/doctornect?sslmode=require" `
  -v ON_ERROR_STOP=1 -f db/rds_bootstrap/04_rds_runtime_grants.sql
```

`04` does **not** call `pg_stat_statements_reset()`; replay failures on that function were extension/grant drift in **01**, wrapped in exception handlers.

---

## 7 — Gates

```powershell
node scripts/db/definer_force_rls_audit.js --target=production --confirm-live-data --confirm=<PROD_RDS_HOST>
node scripts/db/gateway_rls_authorization_suite.js   # local replay DB + gateway; not wired to live staging
node scripts/db/rls_sql_harness.js --target=production --confirm-live-data --confirm=<PROD_RDS_HOST>
```

---

## pg_cron (production)

| Requirement | Detail |
|-------------|--------|
| Parameter group | `shared_preload_libraries` includes `pg_cron` |
| | `cron.database_name` = `doctornect` (or `PROD_RDS_DB`) |
| RDS reboot | Required after parameter change |
| Migration | `20260923000003_doctornect_cron.sql` runs `CREATE EXTENSION pg_cron` + schedules |
| **`--allow-no-cron`** | **Forbidden** on prod execute — skips cron migration and jobs |

---

## Staging reference (2026-11-18)

Staging Supabase ledger at **`20261119000005`**; `rls_sql_harness --target=staging` **210/0**.  
`gateway_rls_authorization_suite.js` has **no** `--target=staging` (local gateway + fresh DB only).