# PROD RDS forensics (read-only)
Generated: 2026-11-15T16:08:10.067Z
Target: postgresql://doctornect_admin:****@127.0.0.1:5433/doctornect?sslmode=verify-full&servername=<prod-rds-host>

## Session
- User: doctornect_admin
- Database: doctornect
- PG: PostgreSQL 18.3 on aarch64-unknown-linux-gnu

## Catalog counts
- Tables/views/functions listed: 62
- RLS policies: 0
- Triggers: 18
- Extensions: 4
- Tables with rows > 0: 1 / 54
- Total row count (sum): 2
- _schema_migrations exists: false

## Migration footprint heuristic (62 files)
- present: 3 | partial: 1 | absent: 8 | no_ddl_signals: 50

## Hypothesis: dry-run COMMIT leaked early migrations
- **Plausible:** `migrate.js` now skips top-level `COMMIT` in `--dry-run-all` (`migration_txn_sql.js`); older runs without skip could commit DDL inside an open `BEGIN`.
- **Consistent with prod:** ~52 public tables, **no ledger**, partial late objects (e.g. `notification_outbox`, `private.admin_users`) — see `key_objects` in JSON.
- **Reject if:** ledger had rows matching first N migrations only (ledger missing entirely → partial manual/scratch apply).

## 20:17 preflight “0 tables” vs audit 52
- `phase1_rds_preflight.js` defaults `PROD_RDS_DB` to **`postgres`**, not `doctornect` (`phase1_rds_preflight.js:11`).
- `prod_rds_readonly_diagnostic.js` / `buildRdsPoolConfig()` use **`doctornect`** — explains empty vs populated catalog.
- Fix: `prod_rds_preflight_readonly.js` documents DB name; diagnostic now lists `current_database()` in output.

## Databases on instance
- doctornect (owner doctornect_admin)
- doctornect_db (owner doctornect_admin)
- postgres (owner doctornect_admin)
- rdsadmin (owner rdsadmin)

Full JSON: `docs/audit/PROD_RDS_FORENSICS.json` (no cell values).
