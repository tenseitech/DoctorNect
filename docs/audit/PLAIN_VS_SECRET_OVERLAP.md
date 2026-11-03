# Plain `.env` vs Secret Manager overlap (Check 0)

**Policy:** No secret values. Variable **names** only.  
**Local deploy file:** `backend/functions/.env` (ignored from upload via `firebase.json`; still merged on `firebase deploy` as plain env).  
**Preflight:** `node scripts/predeploy_secret_check.js` — **Check 0 must pass** before any functions deploy (do not whitelist or bypass).

---

## Summary (current tree, `OTP_REDIS_MIRROR=on`)

| Name in `backend/functions/.env` (non-empty) | Also bound via `defineSecret` / `secrets: [...]` | Exported functions (from code) |
|-----------------------------------------------|--------------------------------------------------|--------------------------------|
| `REDIS_HOST` | yes (`defineSecret('REDIS_HOST')` in `src/config/redis.js`) | `sendUserRegistrationOtp`, `verifyUserRegistrationOtp`, `processNotificationOutboxScheduled` |
| `REDIS_PORT` | yes | same |
| `REDIS_PASSWORD` | yes | same |

These three names cause **Check 0 failure** today: Cloud Functions v2 rejects the same key in both plain env and Secret Manager on one revision.

### Names in `.env` that are **not** overlap today (different id or not bound)

| Name in `.env` | Notes |
|----------------|--------|
| `SUPABASE_SECRET_KEY` | Plain alias read by `readSupabaseServiceRoleKey()`; **not** the same env key as `defineSecret('SUPABASE_SERVICE_ROLE_KEY')`. Check 0 does not flag it; still rotate/migrate per `SECRETS_MIGRATION_PLAN.md`. |
| `MSG91_AUTH_KEY` | In `.env`; **no** `defineSecret('MSG91_AUTH_KEY')` on exports in `index.js` yet. |
| `RAZORPAY_KEY_SECRET` | In `.env`; read as plain `process.env` in `promoted_ads.js` (no `defineSecret` yet). |
| `REVIEW_*`, `OTP_TEST_MODE` | Plain env only; not Secret Manager bindings. |

### `defineSecret` ids bound in code but **absent** from local `.env` (no Check 0 overlap)

Examples: `SUPABASE_SERVICE_ROLE_KEY`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `SUPABASE_WEBHOOK_SECRET`, `RAZORPAY_WEBHOOK_SECRET` — supplied via Secret Manager on deploy, not duplicated in `.env`.

---

## Per exported function — Secret Manager bindings (code)

Legend: **S** = `SUPABASE_SERVICE_ROLE_KEY`, **R** = `REDIS_HOST` + `REDIS_PORT` + `REDIS_PASSWORD` (only when `OTP_REDIS_MIRROR=on`), **A** = AWS access + secret keys, **W** = `SUPABASE_WEBHOOK_SECRET`, **Z** = `RAZORPAY_WEBHOOK_SECRET`.

| Function | Secrets bound |
|----------|----------------|
| `sendUserRegistrationOtp` | S, R (if mirror on) |
| `lookupMobileRegistration` | S |
| `verifyUserRegistrationOtp` | S, R (if mirror on) |
| `resetUserPasswordWithOtp` | S |
| `completeMobileOtpLogin` | S |
| `assertLoginAllowed` | S |
| `recordFailedLogin` | S |
| `clearFailedLogins` | S |
| `getAmbulanceInvite` | S |
| `approveUserAccount` | S |
| `approvePatientAccount` | S |
| `verifyAmbulanceDriverLogin` | S |
| `verifyAmbulanceDriverLoginHttp` | S |
| `submitAmbulanceRating` | S |
| `resyncAmbulanceAuthUid` | S |
| `deleteMyAccount` | S, A |
| `getS3UploadUrl` / `getS3DownloadUrl` / `getS3DownloadUrls` / `deleteS3Object` / `confirmS3Upload` | S, A |
| `createRazorpayOrder` / `verifyRazorpayPayment` / `reviewPromotedAd` / `expirePromotedAds` | S |
| `razorpayWebhook` | S, Z |
| `processMailQueueScheduled` | S |
| `processNotificationOutboxScheduled` | S, R (if mirror on) |
| `supabaseDatabaseWebhook` | S, W |

Functions with **no** `secrets:` array (MSG91 / Redis / Supabase role from plain env only today): e.g. `finalizePatientOtpVerification`, `cleanupPendingRegistration`, `resetAmbulanceDriverPin`, `completeAmbulanceMobileOtpLogin`, validation callables, `consumeAiGenerationQuota`, etc.

**Preflight note:** `getActiveBoundSecrets()` in `scripts/predeploy_secret_check.js` must stay aligned with `index.js` / `s3_storage.js` / `promoted_ads.js` / `src/config/redis.js` (Redis targets above, not `completeMobileOtpLogin` unless that export gains `OTP_REDIS_SECRET_OPTIONS`).

---

## Proposed fix (no `.env` edits in audit commits)

1. **Deploy-time `backend/functions/.env` (Firebase dotenv merge)**  
   Keep **non-secrets** only: URLs, feature flags (`OTP_REDIS_MIRROR`, `APP_ENV`, App Check toggles, MSG91 template IDs, `S3_BUCKET`, anon/publishable Supabase keys, etc.  
   **Remove** `REDIS_HOST`, `REDIS_PORT`, `REDIS_PASSWORD` from the file used for deploy (or leave keys empty if your process requires the keys to exist — empty values do not trigger Check 0).

2. **Secrets**  
   Ensure Secret Manager versions exist for `REDIS_HOST`, `REDIS_PORT`, `REDIS_PASSWORD` and remain bound on every function in the table that lists **R**.

3. **Local emulator**  
   Put Redis connection values in **`backend/functions/.env.local`** (emulator-only; excluded from upload). Emulator loads `.env` + `.env.local`; production deploy must not rely on plain Redis vars.

4. **Combined migration**  
   When touching a function for Redis overlap fix, also complete any pending `defineSecret` work for that function from `SECRETS_MIGRATION_PLAN.md` (one redeploy per function where possible).

### Functions needing redeploy after Redis plain→secret cutover

When `OTP_REDIS_MIRROR=on`, redeploy at least:

- `sendUserRegistrationOtp`
- `verifyUserRegistrationOtp`
- `processNotificationOutboxScheduled`

Any other export that later adds `REDIS_SECRETS` to its `secrets:` array must be redeployed in the same change.

---

## Verification

```bash
node scripts/predeploy_secret_check.js   # Check 0 clear
npm test                                 # backend baseline
```

Do not deploy until Check 0 passes.
