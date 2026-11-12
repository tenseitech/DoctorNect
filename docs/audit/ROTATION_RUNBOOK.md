# Secret rotation runbook (operators)

**Sources:** `docs/SECRET_ROTATION_CHECKLIST.md`, `docs/audit/SECRETS_MIGRATION_PLAN.md`, `docs/audit/PLAIN_VS_SECRET_OVERLAP.md`.  
**Rules:** No secret values in git or chat. No history rewrite. **Preflight:** `node scripts/predeploy_secret_check.js` before every functions deploy.  
**Redeploy from an old git commit:** use a **worktree** at that commit and **copy in the current** `firebase.json` `functions.ignore` block (`**/.env*`, `**/*.bak*`, `**/.secret*`, `**/service-account*`) so backup/env files never re-enter the upload bundle. Run predeploy first.

Combine rotation with **plain→secret migration** so each function is redeployed **once** (bind new secret + remove plain name in the same revision).

---

## Recommended order

| Step | Secret / config | Why this order |
|------|-----------------|----------------|
| 1 | Fix **REDIS_*** overlap (plain out of deploy `.env`) | Unblocks deploy; Check 0 |
| 2 | **REDIS_PASSWORD** (+ host/port SM versions) | Isolated; OTP mirror / rate limits |
| 3 | **Supabase service role** (+ URL hash alignment) | Broad dependency; see JWT note below |
| 4 | **MSG91_AUTH_KEY** | OTP SMS; keep `MSG91_AUTHKEY` alias until three legacy callables confirmed on canonical id |
| 5 | **RAZORPAY_KEY_SECRET** | Payments last |
| 6 | **REVIEW_FIXED_OTP** / **REVIEW_TEST_NUMBERS** | Disable bypass or rotate allowlist; no SM required |

---

## 1. Supabase service role / secret key

| Topic | Detail |
|-------|--------|
| **Where used (functions)** | Any export with `supabaseServiceRoleKey` in `secrets:` (`index.js`, `s3_storage.js`, `promoted_ads.js`, `delete_my_account.js`, `supabase_database_webhook.js`); `getDatabaseClient()` in workers and OTP paths. |
| **Where used (scripts)** | Migration / gateway scripts under `scripts/` and `backend/scripts/` — **do not run** staging/service-account scripts in this runbook pass; name-only inventory in repo docs. |
| **Where rotated** | Supabase Dashboard → Project Settings → API → **service_role** key (or new **secret** API key if project migrated off legacy JWT). **Secret Manager:** `SUPABASE_SERVICE_ROLE_KEY`. |
| **Running functions** | Old key works until revision env/secret updated; after redeploy, only new SM version is mounted. In-flight requests on old revision until drain. |
| **App clients** | **Anon/publishable** keys in Flutter env — **not** the service role. Rotating service role **does not** require app store release unless you mistakenly ship service role in the client (forbidden). |
| **Dependencies** | **UNVERIFIED:** Whether production still validates user JWTs with Supabase **legacy JWT secret** vs new API key model — confirm in Supabase project settings before rotation. `SUPABASE_JWKS_URL` in `.env` is **not** read by current backend code (name only). |
| **Verify** | Callable that uses Postgres (`lookupMobileRegistration` smoke); check logs for 401/403 from Supabase; `npm test`. |
| **Rollback** | Re-enable previous Secret Manager version; redeploy same function set; revoke new dashboard key if created. |

**Redeploy:** All functions in `PLAIN_VS_SECRET_OVERLAP.md` with **S**, plus any future `getDatabaseClient()` export without binding.

---

## 2. REDIS_PASSWORD (and REDIS_HOST / REDIS_PORT)

| Topic | Detail |
|-------|--------|
| **Where used** | `src/config/redis.js`, OTP mirror (`registration_otp.js`), `abuse_rate_limit.js`, `s3_storage.js` (URL cache), `notification_outbox_worker.js`, schedulers when mirror on. |
| **Where rotated** | Memorystore / Redis provider console; update SM secrets `REDIS_HOST`, `REDIS_PORT`, `REDIS_PASSWORD`. |
| **Running functions** | Connections pool per instance; password change drops auth on reconnect — redeploy or wait for cold starts after SM update. |
| **App clients** | No direct Redis access. |
| **Verify** | OTP send/verify smoke; rate-limit path; `npm test` (redis mocked in unit tests). |
| **Rollback** | Previous SM version + redeploy `sendUserRegistrationOtp`, `verifyUserRegistrationOtp`, `processNotificationOutboxScheduled`. |

**Redeploy:** Same three when overlap fix applied; see `PLAIN_VS_SECRET_OVERLAP.md`.

---

## 3. MSG91_AUTH_KEY

| Topic | Detail |
|-------|--------|
| **Where used** | `secure_config.readMsg91AuthKey()` → `registration_otp.js` (send/verify OTP), password reset, ambulance PIN reset; email path uses separate MSG91 email config. |
| **Where rotated** | MSG91 dashboard; SM id **`MSG91_AUTH_KEY`** (legacy fleet may still mount **`MSG91_AUTHKEY`** — verify secret **names** in console only). |
| **Running functions** | Plain env or old SM until redeploy; OTP send fails if key revoked before redeploy completes. |
| **App clients** | Unaffected (server-side SMS). |
| **Verify** | Test OTP to internal number; check MSG91 delivery logs. |
| **Rollback** | Restore previous SM version; redeploy OTP tier (`sendUserRegistrationOtp`, `verifyUserRegistrationOtp`, `finalizePatientOtpVerification`, `resetUserPasswordWithOtp`, `resetAmbulanceDriverPin`, login callables as applicable). |

**Retire `MSG91_AUTHKEY` alias** only after `finalizePatientOtpVerification`, `resetUserPasswordWithOtp`, `resetAmbulanceDriverPin` confirmed on canonical binding (`SECRETS_MIGRATION_PLAN.md`).

---

## 4. RAZORPAY_KEY_SECRET

| Topic | Detail |
|-------|--------|
| **Where used** | `promoted_ads.js` — `createRazorpayOrder`, `verifyRazorpayPayment`; webhook uses **`RAZORPAY_WEBHOOK_SECRET`** (separate). |
| **Where rotated** | Razorpay dashboard → API keys; future: SM `RAZORPAY_KEY_SECRET`. |
| **Running functions** | Payment creation fails if secret revoked mid-flight. |
| **App clients** | Uses Razorpay checkout with **key id** only; secret stays server-side. |
| **Verify** | Test order + verify callable in staging; webhook signature test. |
| **Rollback** | Previous key in Razorpay + SM; redeploy `createRazorpayOrder`, `verifyRazorpayPayment`, `razorpayWebhook`. |

---

## 5. REVIEW_FIXED_OTP / REVIEW_TEST_NUMBERS

| Topic | Detail |
|-------|--------|
| **Where used** | `registration_otp.js` — `getReviewerConfig`, `isReviewerPhone`, send OTP (fixed code for reviewer phones), `consumeOtpChallengeAtomically` reviewer branch. Env: `REVIEW_TEST_NUMBERS`, `REVIEW_FIXED_OTP`, `REVIEW_ACCESS_UNTIL`, `ENABLE_REVIEW_DEMO` (production). |
| **Where rotated** | Firebase / Cloud Run **plain env** (not SM today). Prefer **disable** over rotate in production. |
| **Running functions** | New env requires redeploy of OTP callables that loaded old env (or wait for new revisions). |
| **App clients** | Reviewer test accounts only; production users unaffected when bypass off. |
| **Verify** | `npm test -- test/reviewer_login.test.js test/review_fixed_otp_expired.test.js`; confirm production `ENABLE_REVIEW_DEMO` not `true` unless Play review window active. |
| **Rollback** | Re-set previous allowlist + `REVIEW_ACCESS_UNTIL` in future; redeploy OTP functions. |

See `docs/audit/REVIEW_OTP_PATHS.md` for production acceptance conditions and disable steps.

---

## Deploy hygiene checklist

- [ ] `node scripts/predeploy_secret_check.js` (including forbidden path / overlap checks)
- [ ] Worktree redeploys include current `firebase.json` ignore block
- [ ] Secret Manager version added **before** revoking old vendor key
- [ ] One function redeploy covers both new binding and plain env removal
- [ ] Tick `docs/SECRET_ROTATION_CHECKLIST.md` only after old value revoked
