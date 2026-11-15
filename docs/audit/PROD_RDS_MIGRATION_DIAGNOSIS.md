# Production RDS migration dry-run diagnosis (2026-11-15)

## Read-only facts (`prod_rds_readonly_diagnostic.js`)

| Item | Value |
|------|--------|
| Session | `doctornect_admin` @ `doctornect`, PG **18.3** |
| `_schema_migrations` | **missing** (ledger empty) |
| `public` objects | **52** tables, **140** indexes, **6** sequences, **2** views — owner **`doctornect_admin`** |
| `auth` / `private` | bootstrap schemas present (auth.users, private table) |
| `postgres` login role | **absent** (expected on RDS) |
| `pg_cron` | available, **not installed**; `shared_preload_libraries` lacks `pg_cron` |
| Preload | `rdsutils,pg_tle,pg_stat_statements,rds_casts` |

## Why dry-run reported **98× `already exists`** (pre-fix)

- Ledger **empty** → runner treated all **62** files as pending and executed **every statement** in rollback test mode.
- Schema from **`20260923000001_doctornect_schema.sql`** was **already on disk** (tables + indexes + triggers from an earlier apply **without** `_schema_migrations`), almost certainly a **partial / ledger-less cutover attempt**.
- Tables use `IF NOT EXISTS` (pass) but **indexes/triggers did not** → **42P07 / 42710** on ~98 statements in file 1 only.
- **Not** a harness bug: objects pre-exist under **`public`**, owner **`doctornect_admin`**.

## Fixes applied (this commit)

1. `scripts/lib/rds_migration_sql_normalize.js` — RDS SQL rewrite (`postgres` role, idempotent index/trigger, routine REVOKE guard).
2. Bootstrap `01_roles_and_extensions.sql` — `doctornect_admin` SET grants, `service_role BYPASSRLS`, publication owner.
3. RDS-like PG18 Docker (`scripts/docker/rdslike-pg18`) — no `postgres` role.
4. Post-fix production dry-run: **`62` files, `1626` statements, `0` errors** (`docs/audit/prod_dry_run_all_post_fix2.txt`), `--allow-no-cron` (pg_cron still awaiting parameter group).

## Before `--execute` on production

Backfill or create `public._schema_migrations` to match on-disk schema **or** accept full re-apply idempotency; do **not** assume empty DB when ledger is empty.