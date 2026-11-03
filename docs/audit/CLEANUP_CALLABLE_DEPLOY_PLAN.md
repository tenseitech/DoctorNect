# `cleanupPendingRegistration` deploy plan (local prep — not executed)

**Callable:** `cleanupPendingRegistration` (`backend/functions/index.js` → `registration_otp.js`).

**Region:** `asia-south1` (same as other OTP callables via `MSG91_VPC_OPTIONS`).

---

## Deploy command (operator)

```powershell
cd C:\Users\khije\Downloads\DoctorNect\doctor
firebase deploy --only functions:cleanupPendingRegistration --project <FIREBASE_PROJECT_ID>
```

- **Do not** use `--force`.
- **Do not** run `firebase deploy --only functions` from `chore/dedupe-structure-audit` (drops Oct-era Firestore trigger exports).
- Ship the **app release** that calls this callable **after** the function revision is live.

---

## Environment variable names (code path — no values)

Derived from `cleanupPendingRegistration` → `enforceAbuseLimit` / Firestore, `isDoctorPatientSupabasePrimary`, `getDatabaseClient`, Firebase Admin Auth.

| Name | Role |
|------|------|
| `APP_ENV` | Supabase client routing (`src/db/client.js`) |
| `SUPABASE_URL` | PostgREST primary when postgres cutover |
| `SUPABASE_SERVICE_ROLE_KEY` | Service role for orphan row delete (runtime env / Secret Manager on fleet; **this callable export does not add new `secrets:[]` bindings** — same as `finalizePatientOtpVerification`) |
| `PROD_GATEWAY_URL` / `PROD_GATEWAY_SERVICE_KEY` | Production gateway path when `APP_ENV=production` |
| `ENFORCE_OTP_APP_CHECK` | App Check gate (with `request.app`) |
| `ENFORCE_ABUSE_APP_CHECK` | Abuse/App Check policy fallback |
| `VPC_CONNECTOR` | Optional VPC on `MSG91_VPC_OPTIONS` |
| `FIRESTORE_FORBIDDEN` | Cutover guard with remote config |
| `OTP_REDIS_MIRROR` | Only if Redis-backed abuse paths enabled fleet-wide (`on` binds Redis secrets on **other** callables — not required uniquely for cleanup) |

**Not required on this path:** `MSG91_*` (no SMS send).

---

## Secret bindings (compare to `finalizePatientOtpVerification`)

| Callable | `secrets:` in `index.js` |
|----------|---------------------------|
| `finalizePatientOtpVerification` | none (plain env + Admin SDK) |
| `verifyUserRegistrationOtp` | `supabaseServiceRoleKey` + optional Redis |
| **`cleanupPendingRegistration`** | **none** (same pattern as finalize) |

Operator: confirm Cloud Run revision for `cleanupPendingRegistration` inherits the same **non-secret** env set as `finalizePatientOtpVerification` plus service role availability (Secret Manager vs plain env per fleet standard).

---

## Pre-canary env name diff (operator — names only)

Compare **environment variable names** (not values) on a reference OTP callable vs the new revision:

```powershell
# Replace SERVICE names after identifying Cloud Run service IDs in console.
gcloud run services describe finalizepatientotpverification --region=asia-south1 --project=<PROJECT> --format="yaml(spec.template.spec.containers[0].env)"
gcloud run services describe cleanuppendingregistration --region=asia-south1 --project=<PROJECT> --format="yaml(spec.template.spec.containers[0].env)"
```

Expect the **same name set** as `finalizePatientOtpVerification` (no new MSG91 keys). Diff should be empty aside from revision metadata.

---

## Upload bundle / local files

`firebase.json` `functions.ignore` excludes `**/.env*`, `**/*.bak*`, `**/.secret*` from the **upload zip**. Firebase CLI still **loads** `backend/functions/.env` from disk at deploy for env injection ([config-env](https://firebase.google.com/docs/functions/config-env)).

`node scripts/predeploy_secret_check.js` section **6** flags **forbidden backup/service-account paths** under `backend/functions/`; local `.env` and `.secret.local` are **allowed** on disk.
