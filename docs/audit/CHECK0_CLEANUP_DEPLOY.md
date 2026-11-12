# Check 0 and first `cleanupPendingRegistration` deploy

**Do not whitelist or bypass** `scripts/predeploy_secret_check.js` Check 0.

---

## Does Firebase apply `.env` overlap only to functions being deployed?

Firebase documents **parameterized configuration and dotenv** for Cloud Functions: when you deploy, the CLI loads `backend/functions/.env` (and related env files) and applies variables to **the function(s) included in that deploy operation**. Overlap between a **plain** env var and a **secret** binding for the **same name** is rejected for affected Gen2 revisions (same variable cannot be both `environmentVariables` and `secretEnvironmentVariables`).

Official reference: [Configure your environment (Firebase — Cloud Functions)](https://firebase.google.com/docs/functions/config-env) (dotenv / deploy-time env and Secret Manager params).

**Practical rule:** Even `firebase deploy --only functions:cleanupPendingRegistration` still merges **`backend/functions/.env`** into that function’s config. Check 0 validates the **whole** local `.env` against **all** secret bindings declared in code (not only the target export). Fix overlap **before any** functions deploy.

---

## Variable **names** that must leave deploy `.env` (non-empty) before first `cleanupPendingRegistration` deploy

When `OTP_REDIS_MIRROR=on` (current local deploy profile):

| Remove from deploy `.env` (use Secret Manager + `.env.local` for emulator) |
|----------------------------------------------------------------------------|
| `REDIS_HOST` |
| `REDIS_PORT` |
| `REDIS_PASSWORD` |

Also ensure **`SUPABASE_SERVICE_ROLE_KEY`** is not present in deploy `.env` (separate Check 1 rule; already required for secret-only binding).

No other Check 0 overlaps with current `defineSecret` bindings and typical deploy `.env` keys (`MSG91_AUTH_KEY`, `RAZORPAY_KEY_SECRET`, `SUPABASE_SECRET_KEY` use different ids or plain-only today).

---

## Does `cleanupPendingRegistration` need `REDIS_*`?

| Layer | Uses Redis? |
|-------|-------------|
| `cleanupPendingRegistration()` in `registration_otp.js` | **No** direct Redis (profile snapshot + Auth delete only). |
| `exports.cleanupPendingRegistration` wrapper | Calls `enforceAbuseLimit(..., 'api')` → `abuse_rate_limit.js` may use Redis when `RATE_LIMIT_BACKEND=redis`, postgres cutover flags, or `FIRESTORE_FORBIDDEN=1`. |
| `defineSecret('REDIS_*')` on this export | **No** — not in `OTP_REDIS_SECRET_OPTIONS` / `secrets:` array in `index.js`. |

**Deploy implication:** The callable does **not** require Redis **secret bindings** on its export. It may still **read** Redis at runtime if env + code path enable unified rate limits. Clearing plain `REDIS_*` from deploy `.env` requires Secret Manager versions for functions that **do** bind Redis secrets, not necessarily for this callable alone.

**Order:** Resolve Check 0 (remove plain `REDIS_*` from deploy `.env`, secrets mounted on OTP/outbox exports) → then `firebase deploy --only functions:cleanupPendingRegistration` (no `--force`).

See `docs/audit/PLAIN_VS_SECRET_OVERLAP.md`.
