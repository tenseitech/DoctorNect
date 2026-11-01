# STALE_REF / **800DB356** redeploy — env **name** diff (no values)

**Sources:** local `backend/functions/.env` (key names only), **`docs/audit/DEPLOY_HASH_COHORT.md`** (800DB356 cohort = STALE_REF 50 + **`fb8e2e13`** / git proxy **`4fc3a6b`**), `git show 4fc3a6b:backend/functions/.env.example`, `git grep process.env 4fc3a6b -- backend/functions`.

**Not verified:** per-function Cloud Run env exports from gcloud (operator must diff names in console). No secret values in this doc.

---

## Counts

| Set | Count | Meaning |
|-----|------:|---------|
| **`backend/functions/.env` today** | **38** | Local deploy template actually merged for next redeploy |
| **Oct 6 cohort deployed (proxy)** | **36** | **`4fc3a6b` `.env.example` keys** ∪ documented bake-ins (`SUPABASE_URL`, S3/Razorpay/review/sync flags per STALE_REF era) |
| **`4fc3a6b` `.env.example` alone** | **26** | Committed template at proxy commit |
| **`process.env.*` in `backend/functions` at `4fc3a6b`** | **~55** | Static grep (includes test/emulator-only names) |

**800DB356 cohort deployed key names (proxy):** treat as **baked Cloud Run env** from the **2026-10-06** deploy file. DEPLOY_HASH_COHORT documents **`SUPABASE_URL`** hash **800DB356** on unredeployed STALE_REF functions; CFG-01 baseline described the same non-secret keys merged from `backend/functions/.env` at deploy time (not re-listed here as values).

---

## Today `.env` vs Oct 6 cohort deployed (proxy) — symmetric diff

**Only in today `.env` (not in cohort proxy set):**

- `AWS_REGION`
- `MSG91_AUTH_KEY` (canonical; cohort proxy still lists legacy `MSG91_AUTHKEY`)
- `MSG91_PROXY_URL`
- `OTP_REDIS_MIRROR`
- `RATE_LIMIT_BACKEND`
- `S3_URL_CACHE`
- `SUPABASE_ANON_KEY`
- `SUPABASE_JWKS_URL`
- `SUPABASE_PUBLISHABLE_KEY`
- `SUPABASE_SECRET_KEY`

**Only in cohort deployed proxy (not in today `.env`):**

- `DEMO_PHONE_AMBULANCE`
- `DEMO_PHONE_DOCTOR`
- `DEMO_PHONE_LAB`
- `DEMO_PHONE_MEDICAL_STORE`
- `DEMO_PHONE_PATIENT`
- `DEMO_PHONE_SUPER_ADMIN`
- `GOOGLE_PLAY_REVIEW_PHONE`
- `MSG91_AUTHKEY`

**Shared names (both sets):** remaining overlap includes `SUPABASE_URL`, Redis/S3/Razorpay/MSG91 template IDs, enforcement flags, `REVIEW_*`, `USE_SUPABASE_DB_DOCTOR_PATIENT`, `ENABLE_SUPABASE_SYNC`, etc. (26-way core overlap between templates).

---

## Code at **`4fc3a6b`** reads but **missing from today `.env`** (runtime-relevant)

Exclude emulator/test-only grep hits (`FUNCTION_TARGET`, `GOOGLE_APPLICATION_CREDENTIALS`, etc.).

| Name | Note |
|------|------|
| `AWS_ACCESS_KEY_ID` | S3 callables; may be IAM role in prod instead |
| `AWS_SECRET_ACCESS_KEY` | same |
| `DATABASE_URL` / `SUPABASE_DB_URL` / `STAGING_SUPABASE_DB_URL` | direct PG URLs; today uses REST keys + `SUPABASE_URL` |
| `STAGING_SUPABASE_URL` | code path when `APP_ENV` staging; today uses `SUPABASE_URL` only |
| `SUPABASE_SERVICE_ROLE_KEY` / `SUPABASE_SERVICE_KEY` | today sets `SUPABASE_SECRET_KEY` alias instead |
| `MSG91_AUTHKEY` | legacy fallback in `readMsg91AuthKey()`; today `MSG91_AUTH_KEY` |
| `MSG91_SENDER` | legacy alias |
| `MSG91_TEMPLATE_ID_APPROVAL` / `MSG91_TEMPLATE_ID_REJECTION` | admin email paths |
| `PATIENT_APPROVAL_ADMIN_EMAILS` | approval callables |
| `PROXY_SECRET` | MSG91 proxy |
| `REDIS_CA_CERT` / `REDIS_CA_PATH` | TLS to Memorystore |
| `VPC_CONNECTOR` | optional Gen2 connector |
| `DEMO_PHONE_PATIENT` | demo seed (blank in prod) |

---

## In today `.env` but **not** referenced as `process.env.*` in **`4fc3a6b`** `backend/functions` tree

Static grep under-estimates keys consumed via **`secure_config.js`**, **`getEnv`**, or nested `src/` modules. Treat as **post–Oct 6 additions** or **indirect** reads until re-grepped at redeploy commit.

- `AMBULANCE_HTTP_ALLOWED_ORIGINS`
- `ENABLE_SUPABASE_SYNC`
- `ENFORCE_AMBULANCE_HTTP_APP_CHECK`
- `MSG91_TEMPLATE_ID_LOGIN`
- `MSG91_TEMPLATE_ID_PASSWORD_RESET`
- `OTP_REDIS_MIRROR`
- `REDIS_HOST` / `REDIS_PASSWORD` / `REDIS_PORT` (likely via `redis.js` / config module, not literal `process.env.REDIS_HOST` in top-level files at proxy)
- `REVIEW_ACCESS_UNTIL` / `REVIEW_FIXED_OTP` / `REVIEW_TEST_NUMBERS`
- `SUPABASE_ANON_KEY` / `SUPABASE_JWKS_URL` / `SUPABASE_PUBLISHABLE_KEY` / `SUPABASE_SECRET_KEY`
- `USE_S3_STORAGE`
- `USE_SUPABASE_DB_DOCTOR_PATIENT`

---

## Redeploy implication (names only)

1. **`SUPABASE_URL`** must rebake to **40D01C23** (live-legacy) on STALE_REF tiers — primary CFG-01 fix.  
2. Align **`MSG91_AUTH_KEY`** vs deployed **`MSG91_AUTHKEY`** secret id before OTP tier (see `docs/audit/SECRETS_MIGRATION_PLAN.md`).  
3. Ensure **`SUPABASE_SERVICE_ROLE_KEY`** or alias expected by **`getDatabaseClient()`** is present in the deploy file under the name the **proxy** code reads (`SUPABASE_SERVICE_ROLE_KEY` / `STAGING_*`), not only `SUPABASE_SECRET_KEY`, unless redeploy commit’s reader accepts the alias.  
4. Re-run `node scripts/check_env_parity.js` after renaming keys in **`.env.example`** only — do not commit `.env`.
