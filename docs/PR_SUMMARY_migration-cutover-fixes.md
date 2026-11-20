# PR: migration-cutover-fixes → main (draft — do not push without review)

## Summary

- Prod RDS cutover on **`doctornect`**: Gate 1 bootstrap **01–03**, Gate 2 **`migrate --execute`** **77** files, bootstrap **04**, production gates **210/0**.
- **`migrate.js`**: scratch DB gets bootstrap **01–03** before prod **`--dry-run-all`**; pg_cron migration skipped on scratch only (RDS `cron.database_name=doctornect`).
- Read-only audit helpers: dual login, post-migrate verify, post-dryrunall verify.
- Docs/runbooks updated with **`doctornect_admin`** master path, psql `host`+`hostaddr` TLS, dry-run-all notes.

## Test plan

- [x] Prod `dry-run-all` 0 errors (1718 statements)
- [x] Prod migrate 77/77, ledger head `20261119000005`
- [x] Prod bootstrap 04 + spot grants
- [x] `definer_force_rls_audit.js` exit 0
- [x] `rls_sql_harness.js --target=production` 210/0
- [x] `rds_readiness_probe.js` OK
- [x] Post-cutover pg_dump v2

## Leftovers (operator)

1. Rotate staging DB password if logs touched secrets.
2. Rotate prod passwords if any terminal log exposure.
3. Merge PR to `main` (no force push).
4. Point app/API config to prod RDS (PostgREST/gateway secrets).
5. Monitoring: pg_cron job runs, RDS CPU/storage, error rates.

## Commits (recent)

Include `d7ece9a` (dry-run-all scratch), `d8241e9` (Gate 1), final Gate 2 close-out commit on branch.