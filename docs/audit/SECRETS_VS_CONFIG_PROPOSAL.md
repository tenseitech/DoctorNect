# Secrets vs config — classification & migration proposal (not applied)

Based on `backend/functions/.env.example`, live key **names** in `backend/functions/.env`, and [Firebase env docs](https://firebase.google.com/docs/functions/config-env).

## Firebase dotenv behavior (official)

| File | Deploy (`firebase deploy --only functions`) | Emulator (`firebase emulators:start`) |
|------|---------------------------------------------|----------------------------------------|
| `.env` | Loaded; vars applied to **deployed** function runtime (not bundled in upload if listed in `firebase.json` `ignore`) | Loaded |
| `.env.<projectId>` / `.env.<alias>` | Loaded with `.env` for that target project | Loaded |
| `.env.local` | **Not** deployed | Loaded **after** `.env`; overrides for local/emulator |
| `.secret.local` | Ignored in deploy bundle (also in `ignore`) | Used by params/secrets emulator flows when configured |

This repo’s `firebase.json` ignores `.env`, `.env.local`, and `.secret.local` from the upload artifact; the CLI still **reads** `.env` at deploy time and sends values to Cloud Functions configuration.

## Classification (`backend/functions/.env` keys observed)

### Public / non-secret config (safe as plain env vars)

| Name | Notes |
|------|--------|
| `OTP_TEST_MODE`, `ENFORCE_*_APP_CHECK`, `AMBULANCE_HTTP_ALLOWED_ORIGINS` | Feature toggles |
| `DEMO_PHONE_*`, `REVIEW_*`, `ENABLE_REVIEW_DEMO` | Reviewer/demo routing (still treat as sensitive in prod) |
| `MSG91_TEMPLATE_ID*`, `MSG91_SENDER_ID`, `MSG91_FROM_EMAIL`, `MSG91_EMAIL_DOMAIN`, `MSG91_PROXY_URL` | Template/routing metadata |
| `VPC_CONNECTOR`, `FIRESTORE_TRIGGER_REGION`, `FIRESTORE_FORBIDDEN` | Infra flags |
| `AWS_REGION`, `S3_BUCKET`, `S3_URL_CACHE`, `USE_S3_STORAGE` | Resource identifiers / toggles |
| `REDIS_HOST`, `REDIS_PORT`, `REDIS_TLS`, `REDIS_CA_*` | Host/TLS config (not password) |
| `RATE_LIMIT_BACKEND`, `OTP_REDIS_MIRROR`, `NOTIFICATION_DISPATCH_MODE` | Behavior flags |
| `ENABLE_SUPABASE_SYNC`, `FORCE_ENABLE_SUPABASE_SYNC_IN_PROD`, `USE_SUPABASE_DB_DOCTOR_PATIENT` | Cutover flags |
| `APP_ENV` | Environment selector |
| `STAGING_SUPABASE_URL`, `PROD_GATEWAY_URL` | URLs (still protect from tampering) |
| `SUPABASE_URL`, `SUPABASE_JWKS_URL`, `SUPABASE_PUBLISHABLE_KEY`, `SUPABASE_ANON_KEY` | Public Supabase surface |
| `RAZORPAY_KEY_ID` | Public merchant id |
| `ACCOUNT_APPROVAL_ADMIN_EMAILS`, `PATIENT_APPROVAL_ADMIN_EMAILS`, `BACKFILL_ADMIN_EMAILS` | Operational lists |

### Secrets (move off committed `.env` for local; Secret Manager or bound secrets for deploy)

| Name | Already bound via `defineSecret` in some handlers? |
|------|-----------------------------------------------------|
| `MSG91_AUTH_KEY` | Historically yes; verify fleet bindings before dual-sourcing |
| `RAZORPAY_KEY_SECRET`, `RAZORPAY_WEBHOOK_SECRET` | Yes on payment paths |
| `SUPABASE_SECRET_KEY` / service role aliases | Yes (`SUPABASE_SERVICE_ROLE_KEY`) |
| `REDIS_PASSWORD` | Yes (`REDIS_SECRETS` in redis config) |
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | Yes on S3 callables |
| `PROXY_SECRET`, `MSG91_PROXY_URL` (if carries shared secret) | Partial |
| `STAGING_SUPABASE_SERVICE_ROLE_KEY`, `PROD_GATEWAY_SERVICE_KEY` | Service credentials |
| `SUPABASE_WEBHOOK_SECRET` | Yes on webhook handler |
| `SUPABASE_DB_URL`, `DATABASE_URL` | Connection strings |

## Proposed layout (do not apply yet)

1. **`backend/functions/.env`** — commit-safe template + **non-secret** defaults only (mirror `.env.example`).
2. **`backend/functions/.env.local`** (gitignored) — local emulator overrides + **all secrets** for developer machines.
3. **`backend/functions/.secret.local`** — keep for Firebase params emulator compatibility where already documented.
4. **Deploy** — bind secrets via `firebase functions:secrets:set` / `defineSecret` + `secrets: [...]`; keep **only** public config in deploy-time `.env` or Firebase project env UI.

## Naming clash check (Secret Manager names only)

Before migrating, reconcile env var names with existing Secret Manager ids (sample list from project — extend with `gcloud secrets list`):

Typical bindings in code: `SUPABASE_SERVICE_ROLE_KEY`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `RAZORPAY_WEBHOOK_SECRET`, Redis-related secrets from `src/config/redis.js`.

**Rule:** For each secret, either (a) env var populated only from Secret Manager binding, or (b) plain env — not both with different values. `check_env_parity.js` already guards duplicate *concepts* in examples.

## Local `backend/functions/.env` hygiene

- **`S3_BUCKET` appears twice** in the live file (duplicate assignment); harmless last-wins but should dedupe manually.
- Live file lacks `APP_ENV` / `STAGING_*` / `PROD_GATEWAY_*`; deployed production uses `SUPABASE_URL` + secret key paths when `APP_ENV` is unset (see STAGING gating audit).
