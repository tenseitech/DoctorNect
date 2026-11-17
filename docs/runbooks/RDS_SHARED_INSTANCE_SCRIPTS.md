# RDS scripts — rehearsal vs production on one instance

**Warning:** In DoctorNect production, **rehearsal** (`doctornect_rehearsal`) and **production** (`doctornect`) databases often live on the **same RDS cluster**. PostgreSQL **roles and grants are cluster-wide**, not per-database.

Scripts that mutate roles, extensions, or connect with admin credentials:

- `scripts/db/migrate.js`
- `scripts/db/schema_diff.js`
- `scripts/db/rds_scratch_replay.js`

Implications:

1. A rehearsal migrate that changes a **ROLE** or **GRANT** affects production on that cluster.
2. Always pass explicit `--target=` and live-data confirmations (`--confirm-live-data`, `--confirm-db`, `--confirm=`).
3. Scratch replay must use an isolated **loopback** `REPLAY_DB_URL` on `LOCAL_REPLAY_PG_PORT` (default **5440**), never the RDS tunnel port (`PROD_RDS_PORT`).

See also: `docs/runbooks/RDS_MIGRATION_RUNBOOK.md` (if present), `scripts/lib/live_data_guard.js`.