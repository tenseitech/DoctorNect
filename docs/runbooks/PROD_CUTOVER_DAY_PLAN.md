# Production cutover — day-of plan (numbered)

**Prerequisites:** SSM tunnel `127.0.0.1:$PROD_RDS_PORT` (e.g. **5434**), `PROD_RDS_SSLMODE=require`, CA bundle configured.  
**No prod writes** until you say **`APPROVED FOR PROD`**.  
**Estimates** are per-step wall time for a prepared operator; **77-file migrate** may take **45–120+ min** depending on RDS size and tunnel stability.

### Automated read-only bundle (Windows)

One command (starts SSM to bastion `i-0248ed3a2aad183be`, local **5434**):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/audit/prod_readonly_bundle.ps1
```

**2026-11-19 Gate 1 DONE:** Bootstrap **01–03** applied on **`doctornect`**. **dry-run** **77** pending. **`--dry-run-all`:** **451** errors — production uses empty **`migrate_scratch_*`** DB without repeating bootstrap **01–03** (environment/gap in `migrate.js`, not a prod DDL failure on `doctornect`). **Gate 2 waiting.** psql **01** TLS: use `host=<logical RDS> hostaddr=127.0.0.1` conn string.

**2026-11-18 evening (tasks 1–4):** Tunnel **5434** OK. Inventory **PARTIAL**; pg_cron preload OK; **2026-11-18-v2** logical dump **3703 B** / **15** TOC (non-superuser roles stub).

**2026-11-18 run (earlier):**

| Signal | Result |
|--------|--------|
| `.env` | `PROD_RDS_HOST=*.rds.amazonaws.com`, `PORT=5434`, `DB=doctornect`, no duplicate keys in file |
| Tunnel | Restart when stale `session-manager-plugin` holds **5434** but TCP fails |
| Auth probe | **28P01** with **discrete** `pg` Client fields (rules out URL special-char parsing) |
| Master vars | **`PROD_RDS_MASTER_USER` / `PROD_RDS_MASTER_PASSWORD` not in .env** — you add for inventory + roles dump |
| AWS RDS CLI | **AccessDenied** — use `docs/audit/iam_rds_readonly_policy.json` or console |
| Bastion `cda2c3fb-…` | **No node/git/tmux/nc**; disk **6.4G** free; runs as **root** |

**Bastion installs (you approve; not run by agent):** e.g. `sudo dnf install -y nodejs git tmux nmap-ncat`, then clone repo. **Simpler fallback:** laptop tunnel + keepalives for forensics; for **77-file execute** prefer installing Node on bastion later.

### Bastion migrate execute (recommended)

| Fact | 2026-11-18 evidence |
|------|----------------------|
| Instance | `i-0248ed3a2aad183be` **running**, private IP `172.31.46.143`, SSM **Online** |
| RDS reach | SSM port-forward from laptop → bastion → RDS **works** (TCP on 5434) |
| Node / git on bastion | **Not probed** (no `ssm:SendCommand` in bundle). **Before cutover:** `aws ssm start-session --target i-0248ed3a2aad183be` then run `node -v`, `git --version`, `test -d /opt/doctornect` |

**If bastion has no Node/repo:** least-risk fallback = **local tunnel** with:

- `prod_readonly_bundle.ps1` env overrides (`PROD_RDS_CONNECT_HOST=127.0.0.1`, `PROD_RDS_PORT=5434`, logical `PROD_RDS_HOST` = RDS endpoint, `verify-full`)
- `powercfg /change standby-timeout-ac 0` for execute window
- PostgreSQL URL/query params: `keepalives=1&keepalives_idle=30&keepalives_interval=10`
- **Preferred:** clone repo on bastion, install Node 20+, set `.env` with **direct** `PROD_RDS_HOST` + VPC security (no double-hop), run `migrate --execute` inside **`tmux`**

**Resume after tunnel drop during execute:** reconnect tunnel; `migrate.js --target=production --dry-run …` → pending = remainder; `--execute` applies only unrecorded versions (per-file commit). If error mid-file, stop — triage ledger `max(version)` and error log; restore snapshot if partial DDL.

**Masked execute command (bastion or local tunnel):**

```powershell
cd <repo>
$env:PROD_RDS_SSLMODE='verify-full'
node scripts/db/migrate.js --target=production --execute `
  --confirm-live-data --confirm-db=doctornect `
  --confirm=<PROD_RDS_HOST-logical-endpoint>
```

**Do not** use `--allow-no-cron` on production.

| # | Who | Action | Masked command | Expected output | Undo / risk | ~min |
|---|-----|--------|----------------|-----------------|-------------|------|
| 0 | **You** | Verify tunnel | `Test-NetConnection 127.0.0.1 -Port $env:PROD_RDS_PORT` | `TcpTestSucceeded : True` | — | 1 |
| 1 | **You** | **Manual RDS snapshot** (console or CLI) | `aws rds create-db-snapshot --db-instance-identifier <id> --db-snapshot-identifier doctornect-pre-cutover-<date>` | Snapshot → `available` | Restore to new instance if needed | 10–30 |
| 2 | **You** | Confirm automated backups | `aws rds describe-db-instances --db-instance-identifier <id> --query "DBInstances[0].[BackupRetentionPeriod,PreferredBackupWindow]"` | Retention ≥ 1 | Read-only | 2 |
| 3 | Agent | Prod forensics (read-only) | `node scripts/audit/_prod_greenfield_readonly.js` | Not Docker bleed; verdict **GREENFIELD/PARTIAL/POPULATED** | — | 2 |
| 4 | Agent | Preflight | `node scripts/db/prod_rds_preflight_readonly.js` | Diagnostic OK | — | 3 |
| 5 | Agent | Migrate dry-run (pending list) | `node scripts/db/migrate.js --target=production --dry-run --confirm-live-data --confirm-db=doctornect --confirm=$env:PROD_RDS_HOST` | **77** pending, incl. `rds/20261113000001` | — | 5 |
| 6 | **You** | **pg_cron parameter group** (if not ready) | See § pg_cron below | `shared_preload_libraries` includes `pg_cron`; `cron.database_name=doctornect` | **Reboot required** after change | 15 + **reboot window** |
| 7 | **You** | **Bootstrap 01** (`doctornect_admin`) | See **Gate 1 — bootstrap 01** below (`PGPASSWORD` + `psql -U doctornect_admin`, `verify-full`) | Roles + extensions | Hard to undo role DDL | 10 |
| 8 | Agent | **Bootstrap 02–03** | `node scripts/db/rds_bootstrap_apply.js --target=production --execute --pre-migrate-only --confirm-live-data --confirm=$env:PROD_RDS_HOST --confirm-db=doctornect` | `✅ Bootstrap complete` | Partial DDL | 5 |
| 9 | Agent | **dry-run-all** (after 02–03) | `node scripts/db/migrate.js --target=production --dry-run-all --confirm-live-data --confirm-db=doctornect --confirm=$env:PROD_RDS_HOST` | **0 errors** across all pending SQL | Safe | 30–90 |
| 10 | **You** | Logical backup v2 | `pg_dump --format=directory … -f C:\Users\khije\Backups\doctornect-prod-<date>-v2` | `pg_restore --list` shows RDS host in TOC | — | 10–60 |
| 11 | **You** | Say **`APPROVED FOR PROD`** | — | Human gate | — | — |
| 12 | Agent | **Migrate execute** | `node scripts/db/migrate.js --target=production --execute --confirm-live-data --confirm-db=doctornect --confirm=$env:PROD_RDS_HOST` | **77** applied (cron file unless policy aborts) | **Irreversible** ledger | 45–120+ |
| 13 | **You** | **Bootstrap 04** | `psql "postgresql://rdsadmin:****@127.0.0.1:$($env:PROD_RDS_PORT)/doctornect?sslmode=require" -v ON_ERROR_STOP=1 -f db/rds_bootstrap/04_rds_runtime_grants.sql` | Grants applied | Partial | 5 |
| 14 | Agent | Gates | `definer_force_rls_audit.js`; `rls_sql_harness.js --target=production …` | **0** / **210/0** | Read-only | 15–25 |

**`dry-run-all` before bootstrap 02/03:** Will fail or mislead (missing `auth.uid`, roles, stubs). Run **only after** step 8.

---

## pg_cron — your manual AWS steps (read-only prep; do before step 12)

From `20260923000003_doctornect_cron.sql` + `scripts/lib/pg_cron_policy.js`:

**2026-11-18 prod read-only:** `shared_preload_libraries` already includes **`pg_cron`**; **`cron.database_name=doctornect`**. Skip param-group work unless a future `SHOW` disagrees. Extension still **uninstalled** until migrate/bootstrap.

1. **Parameter group:** Create a **custom** DB parameter group (default groups are not editable). Attach it to the prod instance.
2. Set **`shared_preload_libraries`** = include **`pg_cron`** (often `pg_stat_statements,pg_cron` — preserve existing values).
3. Set **`cron.database_name`** = **`doctornect`** (match `PROD_RDS_DB`).
4. Apply parameter group → instance shows **`pending-reboot`** → schedule **maintenance reboot**.
5. After reboot, SQL (read-only): `SHOW shared_preload_libraries;` and `SELECT * FROM pg_available_extensions WHERE name='pg_cron';` → `installed=false` is OK before migrate; migration runs `CREATE EXTENSION pg_cron` + four `cron.schedule` jobs.
6. **Do not** use `--allow-no-cron` on prod execute.

**Jobs scheduled:** `expire-promoted-ads` (hourly), `cleanup-expired-otp-challenges` (03:00 UTC), `cleanup-expired-rate-limits` (03:15 UTC), plus any remaining lines in the migration file.

---

## `migrate --execute` — what can go wrong and recovery

| Failure | Symptom | Recovery |
|---------|---------|----------|
| **pg_cron unavailable** | Migrate aborts before/during `20260923000003` (`PG_CRON_NOT_AVAILABLE`) | Fix parameter group + reboot; re-run `--dry-run` then `--execute` (skips applied versions). **Do not** use `--allow-no-cron` on prod. |
| **pg_cron CREATE EXTENSION denied** | Error on `CREATE EXTENSION pg_cron` | Ensure `rds.extensions` / RDS allows `pg_cron`; grant superuser path via master; fix and re-execute. |
| **Tunnel drop mid-run** | TCP reset; partial ledger | Check `_schema_migrations` max version; **never** guess. Reconnect tunnel; run `--dry-run` for pending only; `--execute` continues idempotently **if** last file committed per-file (migrate uses per-migration txn). If broken mid-statement, restore snapshot or fix manually from error line. |
| **Advisory lock held** | `Could not acquire migration advisory lock` | Another session running migrate; or stale lock after crash (wait or identify `pg_locks` holder on bastion). |
| **Long lock / timeout** | Heavy migration waits | Use maintenance window; check `pg_stat_activity`; avoid concurrent app traffic. |
| **CONCURRENTLY / non-transactional** | Rare in this repo; dry-run-all surfaces issues | Fix migration on branch; **no** prod hand-edits. |
| **Wrong DB / bleed** | Script refuses via guards | Fix `PROD_RDS_*` env; forensics must show tunnel port + `rds_superuser`. |
| **Checksum mismatch** | Ledger vs repo | Stop; branch must match what staging ran. |
| **Tripwire (dry-run only)** | Object count changed during dry-run-all | N/A on execute; investigate if dry-run-all mutates (should not). |

**Interrupted 77-file run:** Ledger records each **completed** file. After reconnect: `--dry-run` → pending count &lt; 77; `--execute` applies remainder only. **Cannot undo** applied versions without snapshot restore.

---

## Gate 1 — bootstrap 01 (`doctornect_admin`, not `postgres`)

Requires phrase **`APPROVED FOR PROD: BOOTSTRAP`**. TLS **`verify-full`**; tunnel **`127.0.0.1:5434`**. Set **`PGPASSWORD`** from **`PROD_RDS_MASTER_PASSWORD`** in the shell (never inline in chat).

```powershell
cd <repo>
$LogicalHost = $env:PROD_RDS_HOST   # *.rds.amazonaws.com
$Pem = '<repo>\infra\aws\global-bundle.pem' -replace '\\','/'
$env:PGPASSWORD = <load PROD_RDS_MASTER_PASSWORD in shell only>
$Conn = "host=$LogicalHost hostaddr=127.0.0.1 port=5434 dbname=doctornect user=doctornect_admin sslmode=verify-full sslrootcert=$Pem"
& 'C:\Program Files\PostgreSQL\18\bin\psql.exe' -d $Conn -v ON_ERROR_STOP=1 -f db\rds_bootstrap\01_roles_and_extensions.sql
Remove-Item Env:PGPASSWORD
```

**`--dry-run-all` on production (2026-11-20):** `migrate.js` applies bootstrap **01–03** to each **`migrate_scratch_*`** DB before statement tests; scratch DB is **always dropped** in `finally`. **`20260923000003_doctornect_cron.sql`** is **skipped on scratch** only (RDS: pg_cron only in `PROD_RDS_DB`); it still runs on **`--execute`** in `doctornect`. Latest run: **0 errors**, **1718** statements.

**Gate 2 execute (prepared, not run):**
```powershell
node scripts/db/migrate.js --target=production --execute `
  --confirm-live-data --confirm-db=doctornect --confirm=<logical PROD_RDS_HOST>
```
**Post-execute:** bootstrap **04** as `doctornect_admin` (same psql host/hostaddr pattern as 01). Then `definer_force_rls_audit.js`, `rls_sql_harness.js --target=production`, `rds_readiness_probe.js`.

**Tunnel:** Re-check `Test-NetConnection 127.0.0.1 -Port 5434` before each step. **Prefer bastion** for 77-file execute if laptop sleep/VPN is a risk (install **Node 20+**, clone repo, `.env` with direct RDS or local forward); **local SSM** OK with keepalives + stay awake.

**Mid-run drop:** Each migration file commits separately on `--execute`; reconnect tunnel and re-run the **same** command — only pending versions apply.

**02+03 (agent, after 01 verified):** `node scripts/db/rds_bootstrap_apply.js --target=production --execute --pre-migrate-only --confirm-live-data --confirm-db=doctornect --confirm=<logical PROD_RDS_HOST>`

**Backups:** `node scripts/audit/_prod_backup_once.js C:\Users\khije\Backups\doctornect-prod-<date>-v2` (uses **`PROD_RDS_MASTER_USER`** → `doctornect_admin`, `pg_dumpall --roles-only --no-role-passwords`).

**No `\password doctornect_admin`** when master and **`PROD_RDS_PASSWORD`** already match.

---

## Surviving tunnel idle during execute

| Approach | Pros | Cons |
|----------|------|------|
| **Run migrate on SSM bastion / EC2 in VPC** (recommended) | Same region as RDS; no laptop sleep; stable TCP | One-time setup; copy repo + `.env` carefully (no secrets in logs) |
| **Laptop tunnel + keepalives** | Quick | Sleep/VPN drops risk mid-run |
| **AWS Session Manager port-forward** with active session | No SSH keys | Session timeout if idle |

**Recommendation:** Run **`node scripts/db/migrate.js --target=production --execute …`** from a **VPC bastion** with `PROD_RDS_CONNECT_HOST` pointed at the **RDS endpoint** (or short hop), TLS on, **not** through a fragile local forward. If you must use local `127.0.0.1:5434`, set PostgreSQL client **`keepalives=1`** / **`keepalives_idle=30`** in the connection URL or `PG*` env, keep laptop awake, and use **`screen`/`tmux`** on a Linux jump host—not PuTTY alone without keepalive.

---

## Rollback summary

| Step | Rollback |
|------|----------|
| Snapshot (0–1) | Restore DB instance from snapshot (AWS) |
| Bootstrap 01–03 | Painful; prefer new rehearsal DB |
| **Migrate execute (12)** | **Snapshot / pg_dump restore only** |
| Bootstrap 04 | Re-apply or manual grant fix; not full rollback |