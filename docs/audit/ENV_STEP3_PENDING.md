# Step 3 pending decisions (names only — not applied)

## (a) Secret-class names in `backend/functions/.env` → Firebase Secret Manager

Names present in local `.env` that should not ship as plain deploy env (use `firebase functions:secrets:set` / `.secret.local` for emulator):

- `MSG91_AUTH_KEY`
- `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET`
- `SUPABASE_SECRET_KEY`, `SUPABASE_PUBLISHABLE_KEY` (prefer `SUPABASE_SERVICE_ROLE_KEY` canonical)
- `SUPABASE_JWKS_URL` (if used)
- `REDIS_HOST`, `REDIS_PORT`, `REDIS_PASSWORD`
- `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` (when not using IAM role)
- `SUPABASE_WEBHOOK_SECRET`, `PROD_GATEWAY_SERVICE_KEY`, `PROXY_SECRET` (when set)

Non-secret config (may stay in `.env`): template IDs, `S3_BUCKET` (bucket **name**, not credential), `APP_ENV`, feature flags.

## (b) `STAGING_SUPABASE_*` / `PROD_RDS_*` readers

| Variable | Read in `backend/functions`? | Can run in production deploy? |
|----------|------------------------------|-------------------------------|
| `STAGING_SUPABASE_URL` | yes — `src/db/client.js`, `delete_my_account.js`, `cross_role_sync.js` | **Only when `APP_ENV` is not production** (prod uses `PROD_GATEWAY_*`) |
| `STAGING_SUPABASE_SERVICE_ROLE_KEY` | same | **Staging only** |
| `STAGING_SUPABASE_DB_URL` | yes — `cross_role_sync.js` | **Bridge only**; gated by `ENABLE_SUPABASE_SYNC` (off in prod unless forced) |
| `PROD_RDS_*` | **no** | **Scripts/migration only** (`backend/.env.migration.example`, `scripts/`) |

See [ENV_STAGING_RDS_READERS.md](./ENV_STAGING_RDS_READERS.md).

## (c) `USE_SUPABASE_DB_DOCTOR_PATIENT` / `FIRESTORE_FORBIDDEN` defaults

| Surface | `FIRESTORE_FORBIDDEN` | `USE_SUPABASE_DB_DOCTOR_PATIENT` |
|---------|----------------------|----------------------------------|
| Flutter code | `bool.fromEnvironment(..., defaultValue: **true**)` | not read via `fromEnvironment` in `frontend/lib` |
| Flutter `.env.example` | `true` (dart-define) | `true` |
| Functions `.env.example` | `1` | `1` |
| Functions runtime | `process.env.FIRESTORE_FORBIDDEN === '1'` | `sync_flags.js` env fallback; **`isDoctorPatientSupabasePrimary()` returns true** regardless |

**Proposed per environment (Option A — same names):** local, staging, prod → client `FIRESTORE_FORBIDDEN=true`, functions `FIRESTORE_FORBIDDEN=1`, both cutover flags **on** for postgres-only release.

Alternative Option B (split `CLIENT_*` / server names): [FLAGS_CUTOVER_PROPOSAL.md](./FLAGS_CUTOVER_PROPOSAL.md).
