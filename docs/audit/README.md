# Structure & env audit artifacts (index)

Generated and maintained during the **dedupe / env consolidation** audit on branch `chore/dedupe-structure-audit`. Human decisions (flag cutover option **c**) are **not** applied here.

| Document | Purpose |
|----------|---------|
| [DEDUPE_STRUCTURE_AUDIT_REPORT.md](./DEDUPE_STRUCTURE_AUDIT_REPORT.md) | Phase 0–1 inventory, env matrix summary, test baselines pointer |
| [ENV_CONFLICTS_MATRIX.md](./ENV_CONFLICTS_MATRIX.md) | Cross-surface env name conflicts (from `scripts/audit/env_matrix_conflicts.js`) |
| [ENV_STAGING_RDS_READERS.md](./ENV_STAGING_RDS_READERS.md) | Where `STAGING_*` / `PROD_RDS_*` are read in Functions vs migration scripts |
| [ENV_STEP3_PENDING.md](./ENV_STEP3_PENDING.md) | Open env hash / naming decisions (pending human) |
| [FLAGS_CUTOVER_PROPOSAL.md](./FLAGS_CUTOVER_PROPOSAL.md) | Cutover flag options A/B (do not apply until chosen) |
| [S3_BUCKET_CANONICAL.md](./S3_BUCKET_CANONICAL.md) | Canonical `S3_BUCKET`, deploy parity, fail-fast helper |
| [STAGING_GATING.md](./STAGING_GATING.md) | `STAGING_*` / `APP_ENV` conditions in db client, delete account, sync bridge |
| [SECRETS_VS_CONFIG_PROPOSAL.md](./SECRETS_VS_CONFIG_PROPOSAL.md) | Secret vs public config + `.env.local` / Secret Manager proposal (not applied) |
| [APP_ENV_RISK.md](./APP_ENV_RISK.md) | Unset `APP_ENV` default + fail-closed proposal (separate branch) |
| [TEST_ISOLATION.md](./TEST_ISOLATION.md) | Why `.env` merge broke ambulance OTP tests; harness fix |
| [SUPABASE_SERVICE_KEY_CONCEPT.md](./SUPABASE_SERVICE_KEY_CONCEPT.md) | `SUPABASE_SECRET_KEY` vs `SUPABASE_SERVICE_ROLE_KEY` |
| `_audit_*.json` | Phase 0 raw snapshots (in this folder) |
| [baseline_backend_default_npm_test.txt](./baseline_backend_default_npm_test.txt) | Default `npm test`: **493/0/22** (515 total) |
| [REGISTRATION_ROLLBACK_OPTIONS.md](./REGISTRATION_ROLLBACK_OPTIONS.md) | Rollback design + reclaim-on-retry risks (not implemented) |
| [CLEANUP_CALLABLE_DEPLOY_PLAN.md](./CLEANUP_CALLABLE_DEPLOY_PLAN.md) | `cleanupPendingRegistration` env/deploy canary |
| [APP_BACKEND_CONTRACT.md](./APP_BACKEND_CONTRACT.md) | Frontend ↔ deployed backend gap matrix (read-only) |
| [ENV_EXAMPLE_HISTORY_SCAN.md](./ENV_EXAMPLE_HISTORY_SCAN.md) | Git history heuristic on env example templates (names only) |
| [COMMIT_NOTES.md](./COMMIT_NOTES.md) | `8342580` / `a947d81` scope vs message (no rewrite) |
| [DOCKER_RUN.md](./DOCKER_RUN.md) | Docker Postgres + 4 integration tests + `pg_policies` |
| [ENV_BACKUP_COMMIT_PROPOSAL.md](./ENV_BACKUP_COMMIT_PROPOSAL.md) | `.env*` / `.bak` inventory + pending gitignore/move |
| [FIREBASE_IGNORE_PROPOSAL.md](./FIREBASE_IGNORE_PROPOSAL.md) | Proposed `firebase.json` functions ignore (not applied) |
| [EMULATOR_TESTS.md](./EMULATOR_TESTS.md) | `npm run test:emulators` (Firestore + Storage) |
| [DART_JSCPD_CLUSTERS.md](./DART_JSCPD_CLUSTERS.md) | Dart duplicate clusters (document only) |
| [baseline_failing_tests.txt](./baseline_failing_tests.txt) | Emulator-heavy backend failures (not default `npm test`) |
| [baseline_flutter_failing_tests.txt](./baseline_flutter_failing_tests.txt) | Flutter suite failures at audit baseline |

## Regenerate

- Env conflicts matrix: `node scripts/audit/env_matrix_conflicts.js` then `node scripts/audit/write_env_conflicts_matrix_md.js`
- Env parity CI-style check: `cd backend/functions && npm run test:env-parity`
- Backend failure names from a log: `node scripts/audit/extract_backend_failures.js <log>`

Raw JSON snapshots: `docs/audit/_audit_*.json` (gitignored).
