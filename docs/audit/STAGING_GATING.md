# STAGING_* read gating (names only)

Committed defaults: `ENABLE_SUPABASE_SYNC=0`, `FORCE_ENABLE_SUPABASE_SYNC_IN_PROD=0`, `APP_ENV=staging` in **`.env.example`** only. Production deploy sample (`completeMobileOtpLogin`): **`APP_ENV` unset**, **`STAGING_*` absent**, `SUPABASE_URL` present.

## `src/db/client.js`

| Read | Condition |
|------|-----------|
| `APP_ENV` | `(process.env.APP_ENV \|\| 'staging').toLowerCase()` — default **`staging`** if unset |
| `PROD_GATEWAY_URL`, `PROD_GATEWAY_SERVICE_KEY` | Used when `APP_ENV === 'production'` |
| `STAGING_SUPABASE_URL` | Used when **not** production; fallback `SUPABASE_URL` |
| `STAGING_SUPABASE_SERVICE_ROLE_KEY` | Used when **not** production; fallbacks `SUPABASE_SERVICE_ROLE_KEY` |

**With defaults in `.env.example` only:** local checkout without `APP_ENV` uses staging branch + `STAGING_*` or `SUPABASE_*` fallbacks. **Does not connect to staging** if those vars are empty and nothing else provides URL/key (throws).

## `delete_my_account.js` (`getSupabaseServiceConfig`)

| Read | Condition |
|------|-----------|
| `APP_ENV` | Same default **`staging`** |
| `PROD_GATEWAY_*` | Production branch |
| `STAGING_SUPABASE_URL` | Non-production; fallback `SUPABASE_URL` |
| `STAGING_SUPABASE_SERVICE_ROLE_KEY` | Non-production; then bound secret / `readSupabaseServiceRoleKey` / `SUPABASE_SERVICE_ROLE_KEY` |

## `cross_role_sync.js`

| Read | Condition |
|------|-----------|
| `APP_ENV` | Same default **`staging`** in `getSupabaseConfig()` |
| `STAGING_SUPABASE_URL`, `STAGING_SUPABASE_SERVICE_ROLE_KEY` | Non-production branch of `getSupabaseConfig()` |
| `STAGING_SUPABASE_DB_URL` | `getPgPool()` — **no `APP_ENV` guard**; first non-empty among `STAGING_SUPABASE_DB_URL`, `SUPABASE_DB_URL`, `DATABASE_URL` |

**Bridge execution:** Firestore→Supabase exports are not registered from `index.js` in postgres-only mode; `isSupabaseSyncEnabled()` in `sync_flags.js` returns **false** when `ENABLE_SUPABASE_SYNC` is off (default **0**) and **always false** in `APP_ENV=production` unless `FORCE_ENABLE_SUPABASE_SYNC_IN_PROD=1`.

## Cutover flags (related)

| Flag | Default (`.env.example`) | Effect |
|------|--------------------------|--------|
| `ENABLE_SUPABASE_SYNC` | `0` | Off → `isSupabaseSyncEnabled()` false (non-prod) |
| `FORCE_ENABLE_SUPABASE_SYNC_IN_PROD` | `0` | Keeps bridge off in production |
| `USE_SUPABASE_DB_DOCTOR_PATIENT` | `1` | Env fallback only; code forces postgres-primary |

**Conclusion:** With committed flag defaults, **no staging DB bridge** runs. Deployed S3 callables carry **no `STAGING_*`**. Sample production callable uses **`SUPABASE_URL`** with unset `APP_ENV` (non-production code path in `client.js`) — operational implication: set `APP_ENV=production` + `PROD_GATEWAY_*` on production functions when gateway cutover is intended (pending human flag option **c**).
