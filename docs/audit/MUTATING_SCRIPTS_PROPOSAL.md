# Mutating scripts — STAGING_SUPABASE_* and service account

Scripts listed by **path** only. **Implemented:** `--confirm-live-data` guard (`scripts/lib/live_data_guard.js`).

## Guard behavior

1. When `STAGING_SUPABASE_*`, `SUPABASE_URL`, DB URL, or `GOOGLE_APPLICATION_CREDENTIALS` is configured, mutating scripts **refuse** unless **`--confirm-live-data`** is passed.
2. Refusal prints **one line only:** `<8-CHAR-HOST-HASH> <script-path>` (SHA-256 of hostname, first 8 hex, uppercase). No hostnames or secrets.
3. Optional allowlist: `docs/audit/allowed_host_hashes.txt` (override path: `DOCTORNECT_ALLOWED_HOST_HASHES`).
4. **Dry-run by default:** live writes require **`--confirm-live-data --execute`** (scripts that already had `--dry-run` / `--apply` keep those semantics; migrate/seed treat missing `--execute` as dry-run).

## Marked **mutating** (DB writes, Auth admin, or seed)

### `STAGING_SUPABASE_*` / DB URL

| Script | Mutating? | Guard wired |
|--------|-----------|-------------|
| `scripts/db/migrate.js` | yes | yes |
| `scripts/db/rls_sql_harness.js` | yes | yes |
| `scripts/db/rds_scratch_replay.js` | yes | yes |
| `scripts/db/replay_from_scratch.js` | yes | yes |
| `scripts/db/seed_production_minimum.js` | yes | yes |
| `scripts/db/test_doctor_relogin_upsert.js` | yes | yes |
| `scripts/db/verify_zero_residue.js` | yes | yes |
| `scripts/db/staging_logical_backup.js` | read-heavy | no (read-first) |
| `scripts/db/generate_backup.js` | read + file write | no |
| `scripts/db/audit_staging_catalog.js` | read | no |
| `scripts/db/phase1_preflight.js` | read | no |
| `scripts/db/phase2_catalog_export.js` | read | no |
| `scripts/db/anon_surface_audit.js` | read | no |
| `scripts/db/safe_env_local_fix.js` | **mutating** — rewrites local `.env.migration` | yes |
| `scripts/replay_client_postgrest.js` | yes | yes |
| `scripts/test_live_rls_idor.js` | yes | yes |
| `backend/scripts/backfill_users_to_supabase.js` | yes | yes |
| `backend/scripts/backfill_supabase_custom_claims.js` | yes | yes |
| `backend/scripts/backfill_profile_claims.js` | yes | yes |
| `backend/scripts/backfill_doctor_slots.js` | yes | yes |
| `backend/scripts/reverse_sync_supabase_to_firestore.js` | yes | yes |
| `backend/scripts/supabase_to_firestore_worker.js` | yes (deactivated at top) | yes |
| `backend/scripts/verify_staging_and_rollback.js` | yes | yes |
| `backend/scripts/purge_firebase_test_users_and_s3.js` | yes | yes |

### Service account / `GOOGLE_APPLICATION_CREDENTIALS`

| Script | Mutating? | Guard wired |
|--------|-----------|-------------|
| `scripts/seed_reviewer_accounts.js` | yes | yes |
| `scripts/check_reviewer_users.js` | read | no |
| `scripts/verify-s3-live.js` | yes | yes |
| `scripts/verify-roundtrip.js` | yes | yes |
| `scripts/test_firebase_postgrest.js` | yes | yes |
| `scripts/read_remote_config.js` | read | no |
| `backend/scripts/audit_firestore_users.js` | read | no |
| `backend/scripts/check_sync_parity.js` | read | no |
| `backend/scripts/load_env.js` | helper | no |

## Tests

- `scripts/test/live_data_guard.test.js` — refusal path (hash + script name only).
- `scripts/test/env_guard.test.js` — staging / production DB guards.

**Operator rule:** do not run these against live data without explicit flags; service-account quarantine remains **out of scope** until requested.
