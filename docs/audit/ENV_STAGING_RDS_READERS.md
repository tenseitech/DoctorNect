# STAGING_SUPABASE_* / PROD_RDS_* — where they are read (names only)

## `backend/functions` runtime (deployed Cloud Functions)

| Variable | Source files | Production path? |
|----------|--------------|------------------|
| `STAGING_SUPABASE_URL` | `src/db/client.js`, `delete_my_account.js`, `cross_role_sync.js` | **Staging only** when `APP_ENV !== 'production'` (uses `PROD_GATEWAY_URL` + `PROD_GATEWAY_SERVICE_KEY` in production). |
| `STAGING_SUPABASE_SERVICE_ROLE_KEY` | same | **Staging only** (production uses gateway service key). |
| `STAGING_SUPABASE_DB_URL` | `cross_role_sync.js` only | Bridge helper when sync enabled; **not** primary DB client (see `getDatabaseClient`). |
| `PROD_RDS_*` | *(none in `backend/functions`)* | **Not read** by Cloud Functions code. |

## Gating / cutover (not `ENABLE_SUPABASE` alone)

- `ENABLE_SUPABASE_SYNC` — `sync_flags.js`; disabled in production unless `FORCE_ENABLE_SUPABASE_SYNC_IN_PROD=1`. Firestore→Supabase bridge (legacy).
- `isDoctorPatientSupabasePrimary()` — always `true` in current postgres-only code (`sync_flags.js`); env fallback exists but is overridden.
- `APP_ENV` — selects live-legacy Supabase (**40D01C23**, often named “staging” in env) vs production gateway in `src/db/client.js` until RDS cutover.

## Migration / scripts only (moved to `backend/.env.migration.example`)

- `STAGING_SUPABASE_DB_URL`, `STAGING_SUPABASE_ANON_KEY`, full `PROD_RDS_*`, `REPLAY_DB_URL` — used under `scripts/`, `backend/scripts/`, Docker integration tests (local Postgres), not Functions deploy bundle.

**Action taken:** removed duplicate migration keys from root `.env.example`; expanded `backend/.env.migration.example`. **Kept** `STAGING_SUPABASE_URL` + `STAGING_SUPABASE_SERVICE_ROLE_KEY` in `backend/functions/.env.example` (live staging deploy path).
