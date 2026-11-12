# Production environment wiring (placeholders only)

| Variable | Read by | Put real value in |
|----------|---------|-------------------|
| `APP_ENV` | Cloud Functions `index.js`, `assert_app_env.js`, `app_resources.js` | repo root `.env` (materialized to `backend/functions/.env` at deploy only) (production deploy: `APP_ENV=production`) |
| `STAGING_SUPABASE_URL` | Staging-only clients/scripts | repo root `.env` (materialized to `backend/functions/.env` at deploy only) when `APP_ENV=staging` |
| `STAGING_SUPABASE_SERVICE_ROLE_KEY` | Functions `getDatabaseClient()` staging | repo root `.env` (materialized to `backend/functions/.env` at deploy only) |
| `STAGING_SUPABASE_DB_URL` | `migrate.js --target=staging`, schema tools | Repo root `.env` |
| `PROD_GATEWAY_URL` | Flutter release, Functions production, `db_connectivity_smoke` | repo root `.env` (materialized to `backend/functions/.env` at deploy only) + `frontend` dart-define / CI |
| `PROD_GATEWAY_SERVICE_KEY` | Functions service-role HTTP to gateway | repo root `.env` (materialized to `backend/functions/.env` at deploy only) + gateway deploy secret |
| `PROD_GATEWAY_ANON_KEY` | Gateway anon mint / smoke | repo root `.env` (materialized to `backend/functions/.env` at deploy only) |
| `PROD_RDS_HOST` | `migrate.js`, `schema_diff`, guards, TLS SNI | Repo root `.env` |
| `PROD_RDS_CONNECT_HOST` | `rds_pool_config.js` (tunnel TCP) | Repo root `.env` (`127.0.0.1` when tunneled) |
| `PROD_RDS_PORT` | All RDS `pg` clients | Repo root `.env` (`5433` local tunnel) |
| `PROD_RDS_DB` | Migrate target DB name | Repo root `.env` (`doctornect`) |
| `PROD_RDS_USER` / `PROD_RDS_PASSWORD` | RDS auth | Repo root `.env` only (never commit) |
| `PROD_RDS_SSL_ROOT_CERT` | TLS verify-full | Download to `infra/aws/global-bundle.pem` |
| `PROD_RDS_SSL_SERVERNAME` | TLS through tunnel | Same as `PROD_RDS_HOST` |
| `PGRST_URL` | Auth Gateway `config.js` | ECS task / gateway host env |
| `PGRST_JWT_SECRET` / `PGRST_JWT_AUD` | Gateway + PostgREST JWT | Secrets Manager / gateway env (match PostgREST container) |
| `PGRST_DB_URI` | PostgREST container only | ECS secret (authenticator → RDS, often no SSL offload at sidecar) |
| `PGRST_DB_SCHEMAS` | PostgREST | `public` (`infra/aws/ecs.tf`) |
| `PGRST_DB_ANON_ROLE` | PostgREST | `anon` |
| `PGRST_DB_POOL` | PostgREST | e.g. `10` |
| `FIREBASE_PROJECT_ID` | Gateway + Functions | repo root `.env` (materialized to `backend/functions/.env` at deploy only) |
| `S3_BUCKET_STAGING` / `S3_BUCKET_PRODUCTION` | `app_resources.js` | repo root `.env` (materialized to `backend/functions/.env` at deploy only) |
| `REDIS_HOST_STAGING` / `REDIS_HOST_PRODUCTION` | OTP / abuse Redis | repo root `.env` (materialized to `backend/functions/.env` at deploy only) |
| `MSG91_*` | OTP callables | Secret Manager + `.secret.local` emulator |

**Routing:** `APP_ENV=production` → Functions **must** use `PROD_GATEWAY_*` (not `*.supabase.co`). Staging keeps `STAGING_SUPABASE_*`.
