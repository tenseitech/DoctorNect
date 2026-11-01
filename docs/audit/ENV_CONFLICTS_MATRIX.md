# Env variable conflicts (names only)

Variables defined in more than one env file with **different value hashes** (no secret values).
Regenerate: `node scripts/audit/env_runtime_readers.js` then `node scripts/audit/write_env_conflicts_matrix_md.js`.

| Variable | Files defining it | Values differ | Primary runtime reader |
|----------|-------------------|---------------|-------------------------|
| `ACCOUNT_APPROVAL_ADMIN_EMAILS` | `.env.example`, `backend/functions/.env`, `backend/functions/.env.example` | yes | backend/functions (process.env) |
| `APP_CHECK_DEBUG_TOKEN` | `.env`, `.env.example`, `frontend/.env.example` | yes | frontend (String.fromEnvironment) |
| `APP_ENV` | `.env.example`, `.env.migration`, `backend/functions/.env.example` | yes | backend/functions (process.env) |
| `BACKFILL_ADMIN_EMAILS` | `.env.example`, `backend/functions/.env`, `backend/functions/.env.example` | yes | backend/functions (process.env) |
| `CORS_ALLOWED_ORIGINS` | `.env.example`, `.env.migration` | yes | services/api-gateway (process.env) |
| `ENABLE_SUPABASE` | `.env.example`, `frontend/.env.example` | yes | none scanned (template/docs only) |
| `ENFORCE_OTP_APP_CHECK` | `.env.example`, `backend/functions/.env`, `backend/functions/.env.example` | yes | backend/functions (process.env) |
| `FIREBASE_API_KEY_ANDROID` | `.env`, `.env.example`, `frontend/.env.example` | yes | frontend (String.fromEnvironment) |
| `FIREBASE_API_KEY_IOS` | `.env`, `.env.example`, `frontend/.env.example` | yes | frontend (String.fromEnvironment) |
| `FIREBASE_API_KEY_WEB` | `.env`, `.env.example`, `frontend/.env.example` | yes | frontend (String.fromEnvironment) |
| `FIREBASE_PROJECT_ID` | `.env.migration`, `backend/.env.migration.example` | yes | backend/functions (process.env) |
| `FIREBASE_REVOCATION_CHECK` | `.env.example`, `.env.migration` | yes | services/api-gateway (process.env) |
| `FIRESTORE_FORBIDDEN` | `.env.example`, `backend/functions/.env.example` | yes | backend/functions (process.env) |
| `MSG91_AUTH_KEY` | `.env.example`, `backend/functions/.env`, `backend/functions/.env.example` | yes | backend/functions (process.env) |
| `MSG91_PROXY_URL` | `.env.example`, `backend/functions/.env`, `backend/functions/.env.example` | yes | backend/functions (process.env) |
| `MSG91_TEMPLATE_ID` | `.env.example`, `backend/functions/.env`, `backend/functions/.env.example` | yes | backend/functions (process.env) |
| `MSG91_TEMPLATE_ID_LOGIN` | `.env.example`, `backend/functions/.env`, `backend/functions/.env.example` | yes | none scanned (template/docs only) |
| `MSG91_TEMPLATE_ID_PASSWORD_RESET` | `.env.example`, `backend/functions/.env`, `backend/functions/.env.example` | yes | none scanned (template/docs only) |
| `MSG91_TEMPLATE_ID_REGISTRATION` | `.env.example`, `backend/functions/.env`, `backend/functions/.env.example` | yes | backend/functions (process.env) |
| `OTP_REDIS_MIRROR` | `.env.example`, `backend/functions/.env`, `backend/functions/.env.example` | yes | backend/functions (process.env) |
| `PATIENT_APPROVAL_ADMIN_EMAILS` | `.env.example`, `backend/functions/.env.example` | yes | backend/functions (process.env) |
| `PROD_GATEWAY_ANON_KEY` | `.env.example`, `.env.migration` | yes | none scanned (template/docs only) |
| `PROD_GATEWAY_URL` | `.env.example`, `.env.migration`, `backend/functions/.env.example` | yes | backend/functions (process.env) |
| `PROD_RDS_HOST` | `.env.example`, `.env.migration` | yes | none scanned (template/docs only) |
| `PROD_RDS_PASSWORD` | `.env.example`, `.env.migration` | yes | none scanned (template/docs only) |
| `RAZORPAY_KEY_ID` | `.env.example`, `backend/functions/.env`, `backend/functions/.env.example` | yes | backend/functions (process.env) |
| `RAZORPAY_KEY_SECRET` | `.env.example`, `backend/functions/.env`, `backend/functions/.env.example` | yes | backend/functions (process.env) |
| `RECAPTCHA_SITE_KEY` | `.env`, `frontend/.env.example` | yes | frontend (String.fromEnvironment) |
| `REDIS_HOST` | `.env.example`, `backend/functions/.env`, `backend/functions/.env.example` | yes | backend/functions (process.env) |
| `REDIS_PASSWORD` | `.env.example`, `backend/functions/.env`, `backend/functions/.env.example` | yes | none scanned (template/docs only) |
| `REDIS_PORT` | `.env.example`, `backend/functions/.env`, `backend/functions/.env.example` | yes | none scanned (template/docs only) |
| `REPLAY_DB_URL` | `.env.example`, `.env.migration` | yes | scripts/ (process.env) |
| `REVIEW_ACCESS_UNTIL` | `backend/functions/.env`, `backend/functions/.env.example` | yes | backend/functions (process.env) |
| `REVIEW_FIXED_OTP` | `backend/functions/.env`, `backend/functions/.env.example` | yes | backend/functions (process.env) |
| `REVIEW_TEST_NUMBERS` | `backend/functions/.env`, `backend/functions/.env.example` | yes | backend/functions (process.env) |
| `S3_BUCKET` | `.env.example`, `backend/functions/.env`, `backend/functions/.env.example` | yes | backend/functions (process.env) |
| `S3_URL_CACHE` | `.env.example`, `backend/functions/.env`, `backend/functions/.env.example` | yes | backend/functions (process.env) |
| `STAGING_SUPABASE_ANON_KEY` | `.env.example`, `.env.migration` | yes | scripts/ (process.env) |
| `STAGING_SUPABASE_DB_URL` | `.env.example`, `.env.migration`, `backend/.env.migration.example` | yes | backend/functions (process.env) |
| `STAGING_SUPABASE_URL` | `.env.example`, `.env.migration`, `backend/functions/.env.example` | yes | backend/functions (process.env) |
| `SUPABASE_ANON_KEY` | `backend/functions/.env`, `backend/functions/.env.example`, `frontend/.env.example` | yes | frontend (String.fromEnvironment) |
| `SUPABASE_SERVICE_ROLE_KEY` | `backend/functions/.env.example`, `backend/.env.migration.example` | yes | backend/functions (process.env) |
| `SUPABASE_URL` | `backend/functions/.env`, `backend/functions/.env.example`, `backend/.env.migration.example`, `frontend/.env.example` | yes | backend/functions (process.env) |
| `USE_S3_STORAGE` | `.env.example`, `backend/functions/.env`, `backend/functions/.env.example`, `frontend/.env.example` | yes | frontend (String.fromEnvironment) |
| `USE_SUPABASE_DB_DOCTOR_PATIENT` | `.env.example`, `backend/functions/.env`, `backend/functions/.env.example`, `frontend/.env.example` | yes | backend/functions (process.env) |
