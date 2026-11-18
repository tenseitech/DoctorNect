# Production RDS cutover runbook

**Branch:** `migration-cutover-fixes`  
**Hard stops:** No `--execute` / bootstrap on prod without exact phrase **`APPROVED FOR PROD`**. TLS required; never disable SSL. Host/port in commands below are **placeholders** — use your SSM tunnel values from `.env`.

| Step | Who | Credentials | Reversible? |
|------|-----|-------------|-------------|
| 0 Snapshot | DBA / AWS console | RDS IAM | Yes (restore to new instance) |
| 1 Bootstrap 01 | DBA | **RDS master** via tunnel | Partially |
| 2 Bootstrap 02–03 | Migrator | **`doctornect_admin`** | Partially |
| 3 Preflight | Engineer | Read-only tunnel | Yes |
| 4 `dry-run-all` | Engineer | **`doctornect_admin`** | Yes |
| 5 `execute` | Engineer (after **APPROVED FOR PROD**) | **`doctornect_admin`** | **No** (ledger append-only) |
| 6 Bootstrap 04 | DBA / migrator | **`rdsadmin`** or master | Partially |
| 7 Gates | Engineer | tunnel roles | Yes (read-only) |

---

## 0 — RDS snapshot (cannot skip)

**Who:** DBA  
**Action:** Manual snapshot of `doctornect` in AWS console or CLI before any bootstrap/migrate.  
**Expected:** Snapshot status `available`.  
**On failure:** Abort cutover; do not mutate prod.

---

## 1 — Bootstrap `01_roles_and_extensions.sql` (master)

**Who:** DBA with cluster **master** user (not `doctornect_admin`).  
**Masked command:**

```powershell
$env:PROD_RDS_SSLMODE='require'
psql "$env:PROD_RDS_MASTER_URL" -v ON_ERROR_STOP=1 -f db/rds_bootstrap/01_roles_and_extensions.sql
```

Or: `node scripts/db/rds_bootstrap_apply.js --target=production --file=01 --confirm-live-data --confirm-db=doctornect` (if script supports master URL).

**Expected:** Roles `anon`, `authenticated`, `service_role`, `doctornect_admin`, `authenticator` exist; `pg_cron` if available.  
**On failure:** Stop; rollback = no DB deletion — fix SQL and retry only if nothing partial applied.  
**Undo:** Limited — dropping roles is destructive; prefer new rehearsal DB.

---

## 2 — Bootstrap `02_auth_shim.sql`, `03_legacy_compat.sql`

**Who:** Engineer with **`doctornect_admin`**.  
**Masked command:**

```powershell
node scripts/db/rds_bootstrap_apply.js --target=production --files=02,03 --confirm-live-data --confirm-db=doctornect
```

**Expected:** `auth` stub, `private` schema, `GRANT USAGE ON SCHEMA private TO authenticated`.  
**On failure:** Stop; capture error line; do not run migrate.

---

## 3 — Preflight (read-only)

**Who:** Engineer  
**Commands:**

```powershell
Test-NetConnection 127.0.0.1 -Port $env:PROD_RDS_PORT
node scripts/audit/_prod_greenfield_readonly.js
node scripts/db/migrate.js --target=production --dry-run --confirm-live-data
```

**Expected:** Tunnel up; forensics not Docker bleed; pending migrations list matches repo (currently **77** files on shared+rds track including `19000005` when on this branch).  
**On failure:** Fix tunnel/credentials; refresh forensics.

---

## 4 — `dry-run-all`

```powershell
node scripts/db/migrate.js --target=production --dry-run-all --confirm-live-data
```

**Expected:** **0** checksum/parse errors for every pending file.  
**On failure:** Stop — fix branch; never hand-edit prod.

---

## 5 — Migrate execute (requires **APPROVED FOR PROD**)

```powershell
node scripts/db/migrate.js --target=production --execute --confirm-live-data --confirm-db=doctornect --confirm=APPROVED_FOR_PROD
```

**Expected:** All pending versions applied; `_schema_migrations` max = repo head.  
**On failure:** **Stop immediately** — record version, error, ledger; no re-run without human triage.  
**Undo:** Restore snapshot or logical restore from pre-cutover `pg_dump` — **not** automatic.

---

## 6 — Bootstrap `04_rds_runtime_grants.sql` (post-migrate)

**Who:** DBA / `rdsadmin`  
**Masked command:**

```powershell
psql "postgresql://rdsadmin:****@127.0.0.1:${PROD_RDS_PORT}/doctornect?sslmode=require" -v ON_ERROR_STOP=1 -f db/rds_bootstrap/04_rds_runtime_grants.sql
```

**Expected:** `REVOKE ALL … FROM anon` on public routines; `service_role` table grants present.  
**On failure:** Prod may be live but API path broken — do not run app traffic until fixed.

---

## 7 — Readiness + gates

```powershell
node scripts/db/definer_force_rls_audit.js --target=production --confirm-live-data
node scripts/db/gateway_rls_authorization_suite.js --target=production --confirm-live-data
node scripts/db/rls_sql_harness.js --target=production --confirm-live-data
```

**Expected:** Definer **0** hits; gateway **74/0**; harness **210/0** (if `--target=production` supported for harness).  
**On failure:** Triage; may need follow-up migration (not bootstrap 04 rollback).

---

## Gate migrations on prod (from repo ledger)

All four apply on production target: `20261119000001`–`20261119000004`.  
Pending `20261119000005` (system admin EXECUTE grants) applies after staging approval — **does not** change step order; it is one more shared migration before/within the same execute window.

---

## `19000005` impact on this plan

- Insert **after** `19000004` in the same `execute` batch (no separate bootstrap).  
- **No** change to snapshot → 01 → 02 → 03 → dry-run → execute → 04 → gates sequence.  
- Staging should run `19000005` first to confirm harness **210/0** before prod execute includes it.