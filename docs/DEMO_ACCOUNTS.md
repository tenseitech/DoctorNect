# Demo / store-reviewer accounts

DoctorNect has exactly five demo accounts, one per module. They exist so that Play Store / App
Store reviewers (and you) can log in without a real SIM. They live **only** in the staging
Supabase database. Every other phone number is a real user and lives only in AWS RDS.

| Number | Role | Firebase UID | Profile id |
|---|---|---|---|
| 9999900001 | Doctor | `rev_fb_doc_001` | `demo_doctor_001` |
| 9999900002 | Patient | `rev_fb_pat_001` | `demo_patient_001` |
| 9999900003 | Pharmacy (`medicalStore`) | `rev_fb_store_001` | `demo_medicalstore_001` |
| 9999900004 | Lab | `rev_fb_lab_001` | `demo_lab_001` |
| 9999900005 | Ambulance | `rev_fb_amb_001` | `demo_ambulance_001` |

The list is code, not configuration: `scripts/lib/demo_accounts.js` (deployed copy:
`backend/functions/lib/demo_accounts.js`, kept identical by a test). No environment variable or
client value can add a number, change a role or move an account to another database.

> Earlier versions mapped 9999900001 to the patient and 9999900002 to the doctor. Staging still
> holds that old mapping until you run the seed with `--reset` (see below).

## How login works for everyone

1. The app has one phone field. The user enters the number and gets an OTP (`otpType: 'auth'`).
   The server does not look the number up before the OTP is verified, so the response is the
   same for existing, unknown and demo numbers (rate limits still run first).
2. After the OTP is verified the server answers:
   - account exists: a Firebase custom token for that account and its role, so the app signs in
     straight into the right module;
   - no account: a short-lived, role-less registration session; the app continues into role
     selection and the profile form.
3. Demo numbers always end in step 2's "account exists" branch. They can never register: the
   server refuses a registration session for them, the registration finalisation refuses them,
   and the API gateway refuses any client write to RDS that contains a demo number.

## Demo OTP

- The OTP for the five numbers is the value of the `REVIEW_FIXED_OTP` secret (you chose
  `000000`). It is never in code or in a plain env file.
- No SMS is ever sent for a demo number. Every other number gets a random OTP by MSG91 SMS;
  `000000` does not work for any other number.
- The bypass is active only when **all** of these hold, otherwise demo numbers get
  "Demo sign-in is not available right now." (still no SMS):
  - `REVIEWER_OTP_ENABLED=true`
  - `REVIEW_FIXED_OTP` is set (6 digits) for the OTP functions
  - `REVIEW_ACCESS_UNTIL` is a future ISO 8601 timestamp (for example `2026-12-31T23:59:59Z`)
- Numbers are matched strictly: `9999900001`, `+919999900001`, `919999900001` and spaced
  versions of these count; `09999900001`, `199999900001` or any longer/shorter number is
  rejected as an invalid number before any OTP is created.
- Own rate limit (5 sends per number per 15 min), constant-time comparison, and a per-number
  lockout: 5 wrong OTPs within 30 minutes lock that demo number for 30 minutes.
- The OTP functions refuse to start (cold-start error) when `REVIEWER_OTP_ENABLED=true` but
  the `REVIEW_FIXED_OTP` secret is missing or not 6 digits.

## Data plane routing (enforced server-side)

| Who | Cloud Functions lookups | API gateway (PostgREST) | S3 prefix | Razorpay |
|---|---|---|---|---|
| The five demo numbers / UIDs | staging Supabase (`DEMO_SUPABASE_URL`) | demo upstream (`DEMO_PGRST_URL`) | `demo/` | test mode only |
| Every other number / UID | RDS (`PROD_GATEWAY_URL`) | RDS upstream (`PGRST_URL`) | `prod/` | live keys |

The demo UIDs route to staging even if `DEMO_REAL_ROUTING_ENABLED` is unset, and RDS refuses
them (`demo_uid_rds_forbidden`). Real numbers can never be routed to staging because the
decision comes only from the fixed allowlist.

Demo accounts never: get live Razorpay keys (`RAZORPAY_TEST_KEY_*` or test main keys only, or
payments are refused), send SMS, send e-mail through the e-mail callable, or receive mail
(their addresses are on the reserved `.invalid` domain).

## Configuration

### Deployed production Cloud Functions (`medibond-45fad`)

| Name | Value | Kind |
|---|---|---|
| `REVIEWER_OTP_ENABLED` | `true` while a review runs, otherwise `false` | plain env |
| `REVIEW_ACCESS_UNTIL` | future ISO timestamp, e.g. `2026-12-31T23:59:59Z` | plain env |
| `REVIEW_FIXED_OTP` | `000000` | **secret** (Firebase Secret Manager) |
| `DEMO_SUPABASE_URL` | staging Supabase URL `https://<ref>.supabase.co` | plain env (not secret) |
| `DEMO_SUPABASE_SERVICE_ROLE_KEY` | staging service-role key | **secret** |
| `RAZORPAY_TEST_KEY_ID` / `RAZORPAY_TEST_KEY_SECRET` | Razorpay test-mode keys (optional; without them demo payments are refused) | ID plain, secret **secret** |

No longer used (ignored, safe to remove): `REVIEW_PATIENT_PHONES`, `REVIEW_DOCTOR_PHONES`,
`REVIEW_MEDICAL_STORE_PHONES`, `REVIEW_LAB_PHONES`, `REVIEW_AMBULANCE_PHONES`,
`REVIEW_TEST_NUMBERS`, `DEMO_PHONE_NUMBERS`, `DEMO_FIXED_OTP`. `DEMO_FIREBASE_UID_ALLOWLIST`
only adds extra UIDs; the five demo UIDs are built in.

### API gateway (production ECS)

| Name | Value | Kind |
|---|---|---|
| `DEMO_PGRST_URL` | PostgREST for the staging Supabase project (`https://<ref>.supabase.co/rest/v1` base) | plain env |
| `DEMO_PGRST_JWT_SECRET` | staging JWT secret | **secret** |
| `DEMO_PGRST_JWT_AUD` | `authenticated` | plain env |

Without these, signed-in demo users get `503 Demo data plane is not configured.` from the gateway.

### Staging

Staging Functions (`APP_ENV=staging`) use the staging database for everyone; the same three
reviewer variables enable the demo OTP there.

## Enable / disable

- **Enable** (production): set `REVIEW_FIXED_OTP` as a secret, set `REVIEWER_OTP_ENABLED=true`
  and a future `REVIEW_ACCESS_UNTIL`, run `npm run check:boot-env`, deploy the OTP functions.
- **Disable**: set `REVIEWER_OTP_ENABLED=false` (or let `REVIEW_ACCESS_UNTIL` pass) and redeploy.
  Demo numbers then cannot get an OTP; nothing else changes.

## Seed / reset the demo data (staging only)

`scripts/db/seed_staging_demo_accounts.js` creates the five users with full, verified profiles
(doctor with weekly availability, patient with sample records and appointments, pharmacy, lab
with demo catalog tests, ambulance). It refuses production, RDS hosts and your local RDS tunnel.

```powershell
node scripts/db/seed_staging_demo_accounts.js
$env:DEMO_SEED_TARGET = 'staging'; node scripts/db/seed_staging_demo_accounts.js --reset
```

The connection string is read from `STAGING_SUPABASE_DB_URL` in the repo-root `.env` (never
printed). `--execute` is create-only; `--reset` deletes only demo-owned rows and seeds again.

End-to-end check on a throwaway database (Docker): `npm run test:demo-login`.
