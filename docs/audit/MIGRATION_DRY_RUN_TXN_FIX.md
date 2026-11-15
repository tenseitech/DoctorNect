# Migration dry-run `ROLLBACK TO SAVEPOINT` fix

## Root cause (production dry-run)

| Layer | Detail |
|-------|--------|
| **Harness** | `migrate.js` `--dry-run-all` opens outer `BEGIN` and wraps each statement in `SAVEPOINT sp_stmt` (`scripts/db/migrate.js` ~420–451). |
| **Migration** | `db/rds_overrides/20260930000002_admin_users_table.sql` had top-level `BEGIN;` / `COMMIT;` (lines 2 and 14). |
| **Failure** | Inner `COMMIT` ended the outer harness transaction; next `ROLLBACK TO SAVEPOINT` → `25P01` *can only be used in transaction blocks*. |

**Verdict:** both — migration must not emit file-level txn control; harness now skips `BEGIN`/`COMMIT`/`SAVEPOINT` like `rds_scratch_replay.js`.

## Fixes

1. `scripts/lib/migration_txn_sql.js` — shared skip list for txn-control statements.
2. `migrate.js` — dry-run-all + `applySingleMigration` skip those statements; execute path runs DDL + ledger in **one** outer `BEGIN`/`COMMIT`.
3. Removed `BEGIN`/`COMMIT` from RDS override `20260930000002_admin_users_table.sql`.
4. `pg_cron_policy.js` — `--allow-no-cron` skips cron migration on **replay** (local Docker lacks pg_cron).

## Execute safety

- Each pending migration: `BEGIN` → statements (no nested COMMIT) → `INSERT _schema_migrations` → optional supabase_mig savepoint → `COMMIT`.
- Failure: `ROLLBACK` — no ledger row; resume retries same version.
- Production without pg_cron preload: use `--allow-no-cron` **only** emergency; otherwise enable `shared_preload_libraries=pg_cron` first.

## Local proof (`:5440`, 2026-11-15)

| Step | Result |
|------|--------|
| `--dry-run-all --allow-no-cron` | **62 files**, **1541 statements**, **0 errors** (`migrate_dry_run_all_replay_5440.txt`) |
| `--execute --allow-no-cron` | **61 applied** (cron file skipped) (`migrate_execute_replay_5440.txt`) |
| Gateway RLS | **74 PASS / 0 FAIL** |

## TLS (`servername`)

- Real TLS: `scripts/lib/rds_pool_config.js` `buildRdsPoolConfig()` sets `ssl.servername` from `PROD_RDS_SSL_SERVERNAME` or `PROD_RDS_HOST` (lines 17–18, 52–64), **not** tunnel TCP host.
- `maskRdsTarget()` redacts to `servername=<prod-rds-host>` placeholder only in **logs** (line 80).
- Tests: `scripts/test/rds_pool_config_tls.test.js`.