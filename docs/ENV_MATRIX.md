# DoctorNect Environment Variable Matrix

**Generated:** 2026-10-31 (audit session)  
**Policy:** Example values only — never commit real secrets.

Legend: **S** = required in staging, **P** = required in production, **O** = optional.

| Variable | Purpose | Used by | S | P | Example format |
|---|---|---|:--:|:--:|---|
| `APP_ENV` | Selects staging Supabase vs production gateway/RDS routing | Flutter, Cloud Functions, scripts | **S** | **P** | `staging` \| `production` |
| `STAGING_SUPABASE_URL` | Staging PostgREST base URL | Functions, scripts | **S** | O | `https://<ref>.supabase.co` |
| `STAGING_SUPABASE_ANON_KEY` | Staging public anon JWT (client) | Flutter (staging build) | **S** | O | JWT string |
| `STAGING_SUPABASE_SERVICE_ROLE_KEY` | Staging server DB access | Functions (staging), scripts | **S** | O | JWT string (secret) |
| `STAGING_SUPABASE_DB_URL` | Postgres URL for migrations/harness (**session pooler port 5432** or direct host; not transaction pooler **6543**) | `scripts/db/migrate.js`, `rls_sql_harness.js`, `anon_surface_audit.js` | **S** | O | `postgresql://postgres.<ref>:****@...pooler...:5432/postgres?sslmode=require` |
| `PROD_GATEWAY_URL` | Production Auth Gateway + PostgREST proxy | Flutter (prod), Functions | O | **P** | `https://api.doctornect.com` |
| `PROD_GATEWAY_ANON_KEY` | Public gateway anon key (client) | Flutter (prod) | O | **P** | opaque string |
| `PROD_GATEWAY_SERVICE_KEY` | Service-role gateway key (server only) | Functions (`getDatabaseClient`) | O | **P** | 64+ char secret |
| `PROD_RDS_HOST` | RDS endpoint hostname | Terraform, scripts | O | **P** | `*.rds.amazonaws.com` |
| `PROD_RDS_PORT` | RDS port | scripts | O | **P** | `5432` |
| `PROD_RDS_DB` | Database name | scripts | O | **P** | `postgres` |
| `PROD_RDS_USER` | Migration/admin user | scripts (manual) | O | **P** | `postgres` |
| `PROD_RDS_PASSWORD` | RDS password | scripts (manual) | O | **P** | secret |
| `PROD_RDS_SSL_ROOT_CERT` | RDS CA bundle path | `scripts/lib/env_loader` | O | **P** | `infra/aws/global-bundle.pem` |
| `REPLAY_DB_URL` | Local/RDS scratch replay DB | `migrate.js --target=replay` | O | O | `postgresql://...@127.0.0.1:5432/replay_check` |
| `FIREBASE_PROJECT_ID` | Firebase Auth project | Gateway, Functions, Flutter | **S** | **P** | `medibond-45fad` |
| `FIREBASE_REVOCATION_CHECK` | Gateway Admin `checkRevoked` after JWKS | `services/api-gateway` | O | **P** | `true` (default) |
| `GOOGLE_APPLICATION_CREDENTIALS` | ADC path for Gateway revocation / Admin | Gateway ECS task | O | **P** | path to service account JSON (secret mount) |
| `MSG91_AUTH_KEY` | MSG91 API auth key | Functions, proxy | **S** | **P** | secret |
| `MSG91_SENDER_ID` | DLT sender header | Functions | **S** | **P** | `DRNECT` |
| `MSG91_TEMPLATE_ID` | Default OTP DLT template | Functions | **S** | **P** | numeric string |
| `MSG91_TEMPLATE_ID_REGISTRATION` | Registration OTP template | Functions | O | O | numeric string |
| `MSG91_TEMPLATE_ID_LOGIN` | Login OTP template | Functions | O | O | numeric string |
| `MSG91_TEMPLATE_ID_PASSWORD_RESET` | Password reset template | Functions | O | O | numeric string |
| `MSG91_PROXY_URL` | Static-egress Cloud Run proxy | Functions | O | O | `https://...run.app/...` |
| `PROXY_SECRET` | Shared secret for MSG91 proxy | Functions, proxy | O | O | secret |
| `REDIS_HOST` | Redis endpoint | Functions | **S** | **P** | hostname |
| `REDIS_PORT` | Redis port | Functions | O | O | `6379` |
| `REDIS_PASSWORD` | Redis AUTH | Functions | **S** | **P** | secret |
| `REDIS_TLS` | Enable TLS | Functions | O | O | `true` |
| `REDIS_CA_PATH` | Custom CA for Redis TLS | Functions | O | O | file path |
| `OTP_HMAC_SECRET` | HMAC pepper for OTP challenge hashing (replaces unsalted SHA-256) | Functions (`registration_otp.js`) | **S** | **P** | 32+ random bytes via **GCP Secret Manager** / Firebase params (never commit). **Rotation:** rotating invalidates in-flight OTP challenges still in Redis/Postgres until TTL expires — plan maintenance window. |
| `OTP_REDIS_MIRROR` | Mirror OTP challenges to Redis | Functions | O | O | `on` \| `off` |
| `RATE_LIMIT_BACKEND` | Rate limit store | Functions | **S** | **P** | `redis` (preferred) |
| `AWS_REGION` | S3 region | Functions | **S** | **P** | `ap-south-1` |
| `AWS_ACCESS_KEY_ID` | S3 IAM access | Functions | **S** | **P** | `AKIA...` (secret) |
| `AWS_SECRET_ACCESS_KEY` | S3 IAM secret | Functions | **S** | **P** | secret |
| `S3_BUCKET` | Private vault bucket | Functions (presign/delete) | **S** | **P** | bucket name |
| `S3_URL_CACHE` | Cache presigned URLs in Redis | Functions | O | O | `on` \| `off` |
| `USE_S3_STORAGE` | Client compile-time S3 vs Firebase Storage | Flutter | O | O | `true` \| `false` |
| `RAZORPAY_KEY_ID` | Payments | Flutter, Functions | **S** | **P** | `rzp_test_*` / `rzp_live_*` |
| `RAZORPAY_KEY_SECRET` | Payment verification | Functions | **S** | **P** | secret |
| `RAZORPAY_WEBHOOK_SECRET` | Webhook HMAC | Functions | **S** | **P** | secret |
| `ENFORCE_OTP_APP_CHECK` | Require App Check on OTP callables | Functions | O | **P** | `true` |
| `ENFORCE_ABUSE_APP_CHECK` | App Check on abuse endpoints | Functions | O | O | `true` |
| `OTP_TEST_MODE` | Disable real SMS (non-prod only) | Functions | O | O | `false` in prod |
| `ENABLE_SUPABASE_SYNC` | Firestore→Postgres forward sync | Functions | O | O | `0` |
| `FORCE_ENABLE_SUPABASE_SYNC_IN_PROD` | Emergency sync bridge | Functions | O | O | `0` |
| `ENABLE_SUPABASE` | Flutter compile: enable Postgres REST client | Flutter build | O | **P** | `1` in prod |
| `PROD_GATEWAY_URL` | Production API gateway base (PostgREST via gateway) | Flutter build | O | **P** | `https://api…` |
| `RATE_LIMIT_BACKEND` | Abuse limits store | Functions | O | **P** | `redis` |
| `DEMO_PHONE_*` / `REVIEW_*` | Store-review OTP bypass | Functions | O | O | empty in prod |
| `ENABLE_REVIEW_DEMO` | Staging reviewer demo flag | Functions | O | O | empty in prod |
| `SUPABASE_WEBHOOK_SECRET` | HMAC for DB webhooks | Functions | O | O | secret |
| `PGRST_URL` | PostgREST upstream (gateway container) | Gateway | O | **P** | `http://127.0.0.1:3001` |
| `PGRST_JWT_SECRET` | HS256 secret for minted PostgREST JWT | Gateway | O | **P** | 32+ chars |
| `PGRST_JWT_AUD` | PostgREST JWT audience | Gateway | O | O | `authenticated` |
| `SERVICE_ROLE_KEY` | Gateway service key env name | Gateway | O | **P** | secret |
| `ANON_KEY` | Gateway public anon key | Gateway | O | **P** | public |
| `FIRESTORE_TRIGGER_REGION` | Legacy (triggers removed); unused in postgres-only | Functions | O | O | n/a |
| `FIRESTORE_FORBIDDEN` | Block Cloud Functions Firestore (OTP → Redis only) | Functions | O | **P** | `1` |
| `OTP_REDIS_MIRROR` | Store OTP challenges in Redis | Functions | O | **P** | `on` |
| `CORS_ALLOWED_ORIGINS` | Gateway browser CORS allow-list (comma-separated) | Gateway | O | **P** | `https://doctornect.com,...` |
| `REDIS_KEY_PREFIX` | Implicit via `APP_ENV` → `staging:` / `prod:` | Functions | auto | auto | (see `redis_keys.js`) |
| `FIREBASE_PROJECT_ID` | Override compile-time Firebase project | Flutter | O | O | `medibond-staging` / `medibond-45fad` |
| `FIREBASE_STORAGE_BUCKET` | Override Firebase Storage bucket (unused for PHI) | Flutter | O | O | env-specific bucket |

See also: [ENVIRONMENTS.md](../ENVIRONMENTS.md), root [.env.example](../.env.example), [backend/functions/.env.example](../backend/functions/.env.example).

**Validator:** `node scripts/check_env_parity.js` → **0 undocumented core variables** (2026-10-31).
