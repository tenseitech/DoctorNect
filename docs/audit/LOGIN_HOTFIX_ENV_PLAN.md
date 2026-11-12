# Login hotfix — environment names (no values)

Targets: **`verifyUserRegistrationOtp`**, **`completeMobileOtpLogin`** only.  
Reference deploy era: **`9883f00`**. Local template: **`backend/functions/.env.example`** (65 key names) vs **`backend/functions/.env`** today (**38 key names** — counts only, values never listed here).

See also: [LOGIN_HOTFIX_DEPLOY_PLAN.md](./LOGIN_HOTFIX_DEPLOY_PLAN.md), [STALE_REDEPLOY_ENV_DIFF.md](./STALE_REDEPLOY_ENV_DIFF.md).

---

## Callable configuration (from `backend/functions/index.js`)

| Function | Region | App Check | Secret bindings |
|----------|--------|-----------|-----------------|
| `verifyUserRegistrationOtp` | `asia-south1` (`MSG91_VPC_OPTIONS`) | `ENFORCE_OTP_APP_CHECK` | `SUPABASE_SERVICE_ROLE_KEY`; if `OTP_REDIS_MIRROR=on`: `REDIS_HOST`, `REDIS_PORT`, `REDIS_PASSWORD` |
| `completeMobileOtpLogin` | `asia-south1` | `ENFORCE_OTP_APP_CHECK` | `SUPABASE_SERVICE_ROLE_KEY` |

Optional plain env affecting both: **`VPC_CONNECTOR`** (static egress for MSG91).

---

## Plain env names read by OTP code paths (`registration_otp.js` + `index.js`)

| Name | Role |
|------|------|
| `APP_ENV` | Reviewer/demo guards |
| `ENABLE_REVIEW_DEMO` | Production reviewer bypass gate |
| `ENFORCE_OTP_APP_CHECK` | Callable App Check enforcement |
| `ENFORCE_ABUSE_APP_CHECK` | Abuse callables (lookup uses this; not in hotfix deploy) |
| `OTP_REDIS_MIRROR` | Whether Redis secrets are bound |
| `OTP_TEST_MODE` | Must be off in production |
| `ALLOW_LEGACY_UNSALTED_OTP_HASH` | Legacy OTP hash rollback flag |
| `MSG91_AUTH_KEY` | SMS (prefer Secret Manager binding) |
| `MSG91_TEMPLATE_ID` | Default template |
| `MSG91_TEMPLATE_ID_REGISTRATION` | Registration SMS |
| `MSG91_TEMPLATE_ID_LOGIN` | Login SMS |
| `MSG91_TEMPLATE_ID_PASSWORD_RESET` | Reset SMS |
| `MSG91_SENDER_ID` | Sender |
| `MSG91_PROXY_URL` | Optional proxy |
| `PROXY_SECRET` | Proxy auth |
| `REVIEW_TEST_NUMBERS` | Reviewer phones |
| `REVIEW_FIXED_OTP` | Reviewer OTP |
| `REVIEW_ACCESS_UNTIL` | Reviewer window |
| `DEMO_PHONE_PATIENT` | Demo bypass (must be empty prod) |
| `DEMO_PHONE_DOCTOR` | Demo bypass |
| `DEMO_PHONE_MEDICAL_STORE` | Demo bypass |
| `DEMO_PHONE_LAB` | Demo bypass |
| `DEMO_PHONE_AMBULANCE` | Demo bypass |
| `DEMO_PHONE_SUPER_ADMIN` | Demo bypass |
| `VPC_CONNECTOR` | Optional VPC |
| `USE_SUPABASE_DB_DOCTOR_PATIENT` / sync flags | Lookup primary path when cutover |
| `SUPABASE_URL` | Postgres/REST lookup when primary |
| `FIRESTORE_FORBIDDEN` | Firestore guard (Oct-era deploys use Firestore for OTP sessions) |

---

## Secret binding names (Firebase params)

| Secret param | Typical env name |
|--------------|------------------|
| `supabaseServiceRoleKey` | `SUPABASE_SERVICE_ROLE_KEY` |
| Redis (when mirror on) | `REDIS_HOST`, `REDIS_PORT`, `REDIS_PASSWORD` |

---

## Present in today's `backend/functions/.env` (38 names)

Includes: `APP_ENV`, `OTP_TEST_MODE`, `ENFORCE_OTP_APP_CHECK`, `ENFORCE_ABUSE_APP_CHECK`, `MSG91_*` (canonical set), `REDIS_*`, `OTP_REDIS_MIRROR`, `RATE_LIMIT_BACKEND`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_PUBLISHABLE_KEY`, `SUPABASE_SECRET_KEY`, `S3_*`, `RAZORPAY_*`, `PROD_GATEWAY_*`, `VPC_CONNECTOR`, `FIRESTORE_FORBIDDEN`, `ENABLE_REVIEW_DEMO`, etc.

---

## Example template names **missing** from today's `.env` (MISSING-VALUE for redeploy-from-.env)

If you **`firebase deploy --only functions:…`** using **only** today's `.env`, these **deployed-era names** would **not** be set from local `.env` (values must come from **Secret Manager**, **prior Cloud Run revision**, or **console**):

| Name | Where value would come from |
|------|-----------------------------|
| `SUPABASE_SERVICE_ROLE_KEY` | **Secret Manager** / `.secret.local` (not in today's 38-key `.env` list) |
| `DEMO_PHONE_PATIENT` | Optional; empty in prod — set explicitly or inherit from revision |
| `DEMO_PHONE_DOCTOR` | same |
| `DEMO_PHONE_MEDICAL_STORE` | same |
| `DEMO_PHONE_LAB` | same |
| `DEMO_PHONE_AMBULANCE` | same |
| `DEMO_PHONE_SUPER_ADMIN` | same |
| `DATABASE_URL` / `SUPABASE_DB_URL` | Direct PG URLs — often unset when using REST + `SUPABASE_URL` |
| `STAGING_SUPABASE_URL` | Staging only — **do not** use for prod hotfix |
| `STAGING_SUPABASE_SERVICE_ROLE_KEY` | Staging only |
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | IAM role or secrets (not needed for OTP hotfix) |
| `MSG91_TEMPLATE_ID_APPROVAL` / `MSG91_TEMPLATE_ID_REJECTION` | Mail flows — not OTP hotfix |
| `PATIENT_APPROVAL_ADMIN_EMAILS` | Not OTP hotfix |
| `SUPABASE_WEBHOOK_SECRET` | Webhooks — not OTP hotfix |
| `PROXY_SECRET` | Only if `MSG91_PROXY_URL` set |

**Critical for login:** `MSG91_AUTH_KEY`, Redis secrets (if mirror on), and **`SUPABASE_SERVICE_ROLE_KEY`** must be present at runtime — confirm via console/Secret Manager even if absent from flat `.env`.

---

## Deploy methods (env behavior)

| Method | Env effect | Risk |
|--------|------------|------|
| **`firebase deploy --only functions:verifyUserRegistrationOtp,functions:completeMobileOtpLogin`** with project `.env` / dotenv | Firebase CLI merges **declared** params + secrets; **can replace** runtime env for those functions with whatever the deploy bundle declares | **Incomplete `.env`** → missing MSG91/Redis/Supabase → **login broken** |
| **`gcloud run services update … --update-env-vars KEY=…`** (per revision) | **Merges** listed keys; leaves other env vars on the service | Wrong key names or typos; does not add secret bindings |
| **Deploy from `..\doctor-hotfix`** with same secret bindings as prod | Code change only if secrets/env match production | Safest **code-only** path if env/secrets unchanged |

**Recommendation:** Treat hotfix as **non-urgent**; ship **backend + frontend together** (see deploy plan). If you must patch backend alone, prefer **deploy from hotfix worktree** with **pre-flight secret binding parity** (console diff names vs `9883f00` era), not a partial `.env` file. Avoid full `firebase deploy --only functions` from chore branch.

**Warning:** `firebase deploy` for a function **re-binds** secrets listed in `index.js` but **plain env** depends on CLI/project config — deploying without a **complete** env template can drop variables that existed only on the old revision.
