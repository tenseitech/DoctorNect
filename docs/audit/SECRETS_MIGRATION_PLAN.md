# Secrets migration plan (documentation only — no implementation)

**Scope:** Cloud Functions in `backend/functions` as exported today (postgres-only tree).  
**Goal:** Move sensitive values from plain `process.env` / dotenv deploy injection to **`defineSecret` bindings**, without downtime or dual-source drift.

**Canonical names (code):**

| Concept | Canonical env / Secret Manager id | Legacy plain / alias (runtime today) |
|---------|-----------------------------------|--------------------------------------|
| MSG91 | `MSG91_AUTH_KEY` | `MSG91_AUTHKEY`, `AUTH_KEY` via `readMsg91AuthKey()` |
| Supabase service role | `SUPABASE_SERVICE_ROLE_KEY` (defineSecret) | `SUPABASE_SECRET_KEY`, `SUPABASE_SERVICE_KEY` via `readSupabaseServiceRoleKey()`; `getDatabaseClient()` reads **`STAGING_SUPABASE_SERVICE_ROLE_KEY` / `SUPABASE_SERVICE_ROLE_KEY` only** (not `SUPABASE_SECRET_KEY`) |
| Redis | `REDIS_HOST`, `REDIS_PORT`, `REDIS_PASSWORD` (defineSecret) | same keys via `process.env` fallback in `src/config/redis.js` |
| Razorpay | (planned) `RAZORPAY_KEY_SECRET` | `process.env.RAZORPAY_KEY_SECRET` direct in `promoted_ads.js` |

---

## Current state vs target (by secret)

### MSG91_AUTH_KEY

| Area | Today | Target |
|------|-------|--------|
| Code | `secure_config.readMsg91AuthKey()` | unchanged; remove `MSG91_AUTHKEY` fallback **after** fleet redeploy |
| Deploy binding | Most OTP callables: plain dotenv only; **no** `defineSecret('MSG91_AUTH_KEY')` in `index.js` | `defineSecret('MSG91_AUTH_KEY')` on every function that calls `readMsg91AuthKey` |
| Local `.env` | Key present as `MSG91_AUTH_KEY` (name only; value not documented here) | keep for emulator; production from Secret Manager |

**Legacy fleet note:** Archived audits describe some production functions still bound to Secret Manager id **`MSG91_AUTHKEY`** (not `MSG91_AUTH_KEY`). Until **three** high-traffic OTP callables are redeployed with the canonical secret id, **keep** `MSG91_AUTHKEY` in `readMsg91AuthKey()`:

1. `finalizePatientOtpVerification`
2. `resetUserPasswordWithOtp`
3. `resetAmbulanceDriverPin`

(Confirm exact set with `gcloud functions describe` env/secret names — do not paste values.)

### SUPABASE_SERVICE_ROLE_KEY / SUPABASE_SECRET_KEY

| Area | Today | Target |
|------|-------|--------|
| defineSecret | `supabaseServiceRoleKey = defineSecret('SUPABASE_SERVICE_ROLE_KEY')` on many v2 options in `index.js`, `promoted_ads.js`, `s3_storage.js`, `delete_my_account.js`, webhook | extend to any function calling `getDatabaseClient()` without binding today |
| Plain dotenv | Local `.env` often sets **`SUPABASE_SECRET_KEY`** (alias) but not `SUPABASE_SERVICE_ROLE_KEY` | production: **only** Secret Manager; staging dotenv must set **`SUPABASE_SERVICE_ROLE_KEY`** or `STAGING_SUPABASE_SERVICE_ROLE_KEY` for `getDatabaseClient()` |
| `getDatabaseClient()` | Uses URL + service role keys by `APP_ENV` | unchanged; ensure deploy injects matching URL hash before cutover |

### REDIS_PASSWORD

| Area | Today | Target |
|------|-------|--------|
| defineSecret | `REDIS_SECRETS` on OTP callables when `OTP_REDIS_MIRROR=on`; outbox scheduler when mirror on | all code paths using `getRedisClient()` / abuse Redis backend |
| Plain dotenv | `REDIS_HOST`, `REDIS_PORT`, `REDIS_PASSWORD` in `.env` | remove plain `REDIS_PASSWORD` from deployed env after bind + redeploy |

### RAZORPAY_KEY_SECRET

| Area | Today | Target |
|------|-------|--------|
| Code | `promoted_ads.js` reads `process.env.RAZORPAY_KEY_SECRET` directly | `defineSecret('RAZORPAY_KEY_SECRET')` + thin reader in `secure_config.js` |
| Functions | `createRazorpayOrder`, `verifyRazorpayPayment` | add secret to `onCall` / `onRequest` options |

---

## Per-function matrix (secrets needed vs plain env today)

Legend: **M** = MSG91 via `readMsg91AuthKey`, **R** = `REDIS_PASSWORD` (via `getRedisClient` / OTP mirror / rate limit), **Z** = `RAZORPAY_KEY_SECRET`, **S** = Supabase service role (`getDatabaseClient` and/or `readSupabaseServiceRoleKey` / defineSecret `SUPABASE_SERVICE_ROLE_KEY`).

| Function | Needs (code) | defineSecret bound today | Plain dotenv typically merged on deploy |
|----------|--------------|---------------------------|----------------------------------------|
| `getValidationRules` | — | — | non-secret config only |
| `getValidationRulesHttp` | — | — | non-secret |
| `validateField` | — | — | non-secret |
| `validateFormFields` | — | — | non-secret |
| `sendUserRegistrationOtp` | M, R, S | S, R (if mirror) | M, R, S keys if in `.env` |
| `lookupMobileRegistration` | S | S | S, `SUPABASE_URL` |
| `verifyUserRegistrationOtp` | M, R, S | S, R (if mirror) | M, R, S |
| `finalizePatientOtpVerification` | M | — | M |
| `resetAmbulanceDriverPin` | M | — | M |
| `resetUserPasswordWithOtp` | M, S | S | M, S |
| `completeMobileOtpLogin` | M, S | S | M, S |
| `assertLoginAllowed` | R, S | S | R, S |
| `recordFailedLogin` | R, S | S | R, S |
| `clearFailedLogins` | R, S | S | R, S |
| `getAmbulanceInvite` | S | S | S |
| `approveUserAccount` | S | S | S |
| `approvePatientAccount` | S | S | S |
| `validateVitalAdvisory` | — | — | non-secret |
| `consumeAiGenerationQuota` | R | — | R |
| `assertAccountCreationAllowed` | R | — | R |
| `verifyAmbulanceDriverLogin` | S | S | S |
| `verifyAmbulanceDriverLoginHttp` | S | S | S |
| `completeAmbulanceMobileOtpLogin` | M | — | M |
| `submitAmbulanceRating` | S | S | S |
| `resyncAmbulanceAuthUid` | S | S | S |
| `backfillPatientCareTeams` | S | — | S |
| `createRazorpayOrder` | Z, S | S | Z, S |
| `verifyRazorpayPayment` | Z, S | S | Z, S |
| `reviewPromotedAd` | S | S | S |
| `expirePromotedAds` | S | S | S |
| `razorpayWebhook` | Z (webhook secret), S | S + webhook secret | Z, S |
| `bookAppointment` | R | — | R |
| `rescheduleAppointment` | R | — | R |
| `deleteMyAccount` | R, S (+ AWS secrets) | S, AWS | R, S, AWS |
| `sendMsg91EmailCallable` | — (email dispatch disabled in code) | — | MSG91_* template config only |
| `processMailQueueScheduled` | S | S | S |
| `processNotificationOutboxScheduled` | S, R (if mirror) | S, R (if mirror) | S, R |
| `supabaseDatabaseWebhook` | S (+ webhook secret) | S, webhook | S |
| `getS3UploadUrl` | S (+ AWS) | S, AWS | S, AWS |
| `getS3DownloadUrl` | S (+ AWS) | S, AWS | S, AWS |
| `getS3DownloadUrls` | S (+ AWS) | S, AWS | S, AWS |
| `deleteS3Object` | S (+ AWS) | S, AWS | S, AWS |
| `confirmS3Upload` | S (+ AWS) | S, AWS | S, AWS |

**Not exported on this branch (still listed in `STALE_REF_REDEPLOY_PLAN.md`):** legacy Firestore notification triggers, `processMailQueueMsg91`, etc. — treat that doc as **historical fleet census**, not current `index.js` exports.

---

## defineSecret rollout order (no code changes in this doc pass)

For each secret **S**:

1. **Create / enable** Secret Manager version under canonical id (e.g. `MSG91_AUTH_KEY`).
2. **Bind** `defineSecret` on **all** functions in the matrix that need **S** (same deploy revision).
3. **Deploy** those functions (prefer tiered batches from `STALE_REF_REDEPLOY_PLAN.md` where still applicable).
4. **Remove plain name** from function environment config (Console / `firebase functions:config` / dotenv) **in the same deploy** so only the secret binding supplies **S**.
5. **Rotate** Secret Manager version after confirming logs clean (new version → redeploy bound functions → disable old version).

Recommended secret order (lowest coupling first):

1. `REDIS_PASSWORD` (+ host/port) — OTP mirror + rate limits  
2. `SUPABASE_SERVICE_ROLE_KEY` — align URL hash first (see `PROD_WIRING_CHECK.md`)  
3. `MSG91_AUTH_KEY` — after OTP tier deploy; drop `MSG91_AUTHKEY` fallback only after the **three** callables above are confirmed on canonical id  
4. `RAZORPAY_KEY_SECRET` — payment tier last  

---

## MSG91_AUTHKEY fallback retirement gate

Do **not** remove `process.env.MSG91_AUTHKEY` from `secure_config.js` until:

- `finalizePatientOtpVerification`, `resetUserPasswordWithOtp`, and `resetAmbulanceDriverPin` have been redeployed with **`MSG91_AUTH_KEY`** bound (verify secret **names** in GCP only), and  
- OTP smoke tests pass in production.

Until then, examples/tests use **`MSG91_AUTH_KEY`** only; runtime keeps alias read for backward compatibility with old bindings.

---

## Verification before any deploy

- `node scripts/check_env_parity.js`  
- Match local `SUPABASE_URL` **hash** to deployed function env hashes (`PROD_WIRING_CHECK.md` — user-supplied gcloud output)  
- `npm test` / `flutter test` baselines unchanged on the release commit  

**Do not implement** defineSecret / env removals on the chore-only commit range without the full cutover branch.
