# Local env dedupe (names and line counts only)

**Backup confirmed:** `%USERPROFILE%\doctornect-env-backup\20261031-170022\` exists.

## Line counts (2026-11-01)

| File | Lines |
|------|------:|
| `.env` | 14 |
| `.env.example` | 15 |
| `.env.migration` | 46 (after removing duplicate empty `STAGING_SUPABASE_URL=` line) |
| `backend/functions/.env` | 87 |
| `backend/functions/.env.example` | 81 |
| `backend/.env.migration.example` | 30 |
| `frontend/.env.example` | 28 |

## Keys appearing in more than one file (cross-file duplicates)

`ACCOUNT_APPROVAL_ADMIN_EMAILS`, `AMBULANCE_HTTP_ALLOWED_ORIGINS`, `APP_CHECK_DEBUG_TOKEN`, `APP_ENV`, `AWS_ACCESS_KEY_ID`, `AWS_REGION`, `AWS_SECRET_ACCESS_KEY`, `BACKFILL_ADMIN_EMAILS`, `ENABLE_SUPABASE_SYNC`, `ENFORCE_ABUSE_APP_CHECK`, `ENFORCE_AMBULANCE_HTTP_APP_CHECK`, `ENFORCE_OTP_APP_CHECK`, `FIREBASE_API_KEY_ANDROID`, `FIREBASE_API_KEY_IOS`, `FIREBASE_API_KEY_WEB`, `FIREBASE_PROJECT_ID`, `FIRESTORE_FORBIDDEN`, `FIRESTORE_TEST_COLLECTION_PREFIX`, `MSG91_AUTH_KEY`, `MSG91_EMAIL_DOMAIN`, `MSG91_FROM_EMAIL`, `MSG91_PROXY_URL`, `MSG91_SENDER_ID`, `MSG91_TEMPLATE_ID`, `MSG91_TEMPLATE_ID_LOGIN`, `MSG91_TEMPLATE_ID_PASSWORD_RESET`, `MSG91_TEMPLATE_ID_REGISTRATION`, `OTP_REDIS_MIRROR`, `OTP_TEST_MODE`, `PROD_GATEWAY_ANON_KEY`, `PROD_GATEWAY_SERVICE_KEY`, `PROD_GATEWAY_URL`, `PROD_RDS_DB`, `PROD_RDS_HOST`, `PROD_RDS_PASSWORD`, `PROD_RDS_PORT`, `PROD_RDS_SSL_ROOT_CERT`, `PROD_RDS_USER`, `RATE_LIMIT_BACKEND`, `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET`, `RECAPTCHA_SITE_KEY`, `REDIS_HOST`, `REDIS_PASSWORD`, `REDIS_PORT`, `REDIS_TLS`, `REPLAY_DB_URL`, `REVIEW_ACCESS_UNTIL`, `REVIEW_FIXED_OTP`, `REVIEW_TEST_NUMBERS`, `S3_BUCKET`, `S3_URL_CACHE`, `STAGING_SUPABASE_ANON_KEY`, `STAGING_SUPABASE_DB_URL`, `STAGING_SUPABASE_SERVICE_ROLE_KEY`, `STAGING_SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_URL`, `USE_S3_STORAGE`

## Within-file duplicate keys (action)

| File | Key | Action |
|------|-----|--------|
| `.env.migration` | `STAGING_SUPABASE_URL` | **Done** — removed empty duplicate; kept non-empty line |
| `.env.migration` | `STAGING_SUPABASE_SERVICE_ROLE_KEY` | **Pending human** — empty placeholder line + second line (invalid placeholder URL in manifest audit); fix using backup, not git |

## Not deduped in this pass

- No value merges across `backend/functions/.env` vs examples  
- `USE_SUPABASE_DB_DOCTOR_PATIENT` still only in live functions `.env` (removed from examples on branch)  
- Canonical naming: see `docs/audit/SECRETS_MIGRATION_PLAN.md`, `scripts/check_env_parity.js`
