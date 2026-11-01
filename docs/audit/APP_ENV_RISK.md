# APP_ENV risk note (documentation only — no code change on this branch)

## Current behavior

- **Default when unset:** `'staging'` in `src/db/client.js`, `delete_my_account.js`, `cross_role_sync.js` (`(process.env.APP_ENV || 'staging').toLowerCase()`).
- **Production branch:** `APP_ENV === 'production'` selects `PROD_GATEWAY_URL` + `PROD_GATEWAY_SERVICE_KEY`.
- **Non-production branch:** `STAGING_SUPABASE_URL` / `STAGING_SUPABASE_SERVICE_ROLE_KEY` (with `SUPABASE_*` fallbacks).

## What it controls

| Area | Effect |
|------|--------|
| Database client | Staging Supabase REST vs production gateway |
| Account delete Supabase REST | Same split in `getSupabaseServiceConfig()` |
| Sync bridge config | Same split in `getSupabaseConfig()` |
| Supabase sync gate | `isSupabaseSyncEnabled()` hard-off in production unless `FORCE_ENABLE_SUPABASE_SYNC_IN_PROD=1` |

## Observed deploy gap (names only)

Sample production callables may have **`APP_ENV` unset** and **`STAGING_*` absent**, while **`SUPABASE_URL`** is set — runtime follows the **non-production** code path but uses deployed Supabase URL env vars.

## Proposal (separate branch)

1. **Fail closed:** if `FUNCTION_TARGET` is set (Cloud Functions runtime) and `APP_ENV` is missing or not one of `staging` | `production` | `test`, throw at cold start with a clear config error.
2. **Explicit production deploy:** set `APP_ENV=production` and `PROD_GATEWAY_*` on all production functions; remove reliance on `SUPABASE_URL` as implicit prod DB REST.
3. **Local / CI tests:** keep `APP_ENV=test` in `test/setup_env.js` (already set for default `npm test`).

Do not apply until cutover option **(c)** and gateway migration are decided.
