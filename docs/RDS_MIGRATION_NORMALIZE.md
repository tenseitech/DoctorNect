# RDS migration SQL normalization

Applied in `scripts/lib/rds_migration_sql_normalize.js` when `target ∈ {production, rehearsal, replay*}` and `REPLAY_RDS_LIKE=1`.

**Staging** and **replay without REPLAY_RDS_LIKE** run **original** SQL files (or `db/rds_overrides/` bodies unchanged except path).

## Rewrite rules (in order)

| # | Rule | Justification |
|---|------|----------------|
| 1 | `CREATE INDEX` / `CREATE UNIQUE INDEX` → add `IF NOT EXISTS` | Ledger-less replays on partial catalogs (prod dry-run accident / re-apply) |
| 2 | `CREATE TRIGGER` → prepend `DROP TRIGGER IF EXISTS … ON …` | Idempotent trigger recreation on RDS replay |
| 3 | Blanket `REVOKE ALL ON ALL ROUTINES IN SCHEMA public` → `DO` block catching `insufficient_privilege` | `doctornect_admin` is not `postgres` role |
| 4 | `OWNER TO postgres` → `OWNER TO <migrator>` (`PROD_RDS_USER` / `doctornect_admin`) | RDS has no login role `postgres` |
| 5 | `OWNER postgres` (shorthand) → `OWNER <migrator>` | Same |
| 6 | `ALTER DEFAULT PRIVILEGES FOR ROLE postgres` → `FOR ROLE <migrator>` | Same |
| 7 | `FOR ROLE postgres` → `FOR ROLE <migrator>` | Same |
| 8 | Strip `postgres` from grant role lists | Same |
| 9 | `TO postgres` → `TO <migrator>` | Same |
| 10 | `current_user IN ('service_role','postgres')` → include migrator + `rds_master` + `app_migrator` | Superuser checks on RDS |

## Drift risk

Prod **execute** uses normalized SQL checksums in `_schema_migrations`; staging uses originals → **checksums differ by design**. Parity must be validated with `schema_diff.js` / scratch replay, not byte-identical SQL.

## Verification (local, not production)

- RDS-like PG18 `5442` with `REPLAY_RDS_LIKE=1`: `migrate.js --target=replay --execute` (see `MANUAL_STEPS.md`).
- Scratch replay: `rds_scratch_replay.js` applies normalized production target SQL to `replay_check`.