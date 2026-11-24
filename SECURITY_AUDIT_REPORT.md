# DoctorNect — Security Audit & Fix Report

**Date:** 2026-11-24
**Scope:** Doctor, Patient, Pharmacy, Lab, Ambulance modules. Covers Firebase Cloud Functions (`backend/functions`), the API gateway (`services/api-gateway`), SQL migrations (`db/migrations`), the Flutter client (`frontend`), infra and env config. Admin is out of scope; shared code it touches is noted.
**Branch:** I could not create `security/full-audit-fix` or commit anything: **`git` is not installed on this machine**. All changes are in the working tree, uncommitted, on the current checkout (`migration-cutover-fixes`). See "Commit plan" at the end.

---

## 1. Summary

The codebase already had a lot of hardening in place:
- Firebase ID tokens verified in the gateway, with revocation checks
- OTPs from a CSPRNG, HMAC-hashed in Redis, with constant-time compare
- Razorpay HMAC checks on the raw body
- RLS enabled on every table
- SECURITY DEFINER functions all pin `search_path`
- Deny-all Firebase Storage and Firestore rules
- Strong hosting CSP and HSTS
- No secrets in git

I still found **2 Critical**, **6 High**, **9 Medium** and **6 Low** issues that were exploitable or would break production. They are fixed in code or migrations, except where noted as manual.

Top issues:
1. **Critical: payment and approval bypass on promoted ads.** The `promoted_ads_write` RLS policy is FOR ALL with an owner predicate, so an owner could PATCH `status='active', payment_status='verified'` and get a live banner without paying or approval. Fixed with a guard-trigger migration.
2. **Critical: Razorpay order creation and verification were Firestore-only.** With `FIRESTORE_FORBIDDEN=1` in production they crash, so ad payments couldn't work. Both are ported to Postgres with server-side pricing and an ownership check.
3. **High: IP rate-limit bypass.** Every Functions rate limit keyed on the leftmost `X-Forwarded-For` value, which the attacker controls. That allowed unlimited OTP SMS (SMS pumping), login and PIN brute force. Now uses the rightmost, proxy-appended hop.
4. **High: IDOR file deletion in `confirmS3Upload`.** Any signed-in user could trigger deletion of other patients' prescription or lab-report files, and any lab could do it for any booking. Now authorized before any S3 call, with purpose↔prefix matching and magic-byte checks.
5. **High: prescription injection and deletion.** Any verified doctor could insert prescriptions into any patient's chart through PostgREST, and delete prescriptions. Now requires a care relationship; client DELETE is revoked.

---

## 2. Findings table

| # | Severity | File:line | Issue | Impact | Fix | Status |
|---|----------|-----------|-------|--------|-----|--------|
| 1 | Critical | `db/migrations/20261021000005_phase_e3_razorpay_and_promoted_ads.sql:29` (`promoted_ads_write` FOR ALL) | Owner can UPDATE `status`, `payment_status`, `razorpay_*`, `amount_paid`, `start/end_time`. The carousel policy (`20261119000001`) then shows the ad to everyone. | Free paid advertising; approved creative can be swapped after approval; duration extended after payment. | New migration `20261124000001_promoted_ads_payment_state_guard.sql`: a BEFORE INSERT/UPDATE trigger makes payment and lifecycle columns server-owned. Paid, live or under-review ads can't be edited by clients. Policies are split into insert/update/delete; delete is limited to unpaid drafts. | **Fixed (migration must be applied)** |
| 2 | Critical | `backend/functions/promoted_ads.js` `createRazorpayOrder` / `verifyRazorpayPayment` | Read and write Firestore `promotedAds/*` only. The app writes ads to Postgres, and production sets `FIRESTORE_FORBIDDEN=1`, so `getLegacyFirestoreDb()` returns null and the calls crash. | Ad payments broken in production; leftover Firestore dependency. | Added a Postgres path (`createRazorpayOrderPostgres`, `loadOwnedPromotedAdRow`). Amount comes from `AD_PRICING_TABLE`, never the client. Ownership and non-patient role are checked against `users`. Writes the `razorpay_orders` ledger. Routed through `getDatabaseClient({ firebaseUid })` so demo users stay on staging and real users on RDS. | **Fixed** |
| 3 | High | `abuse_rate_limit.js:52`, `index.js:234`, `index.js:1074`, `security_logger.js:28` | Client IP taken from the **leftmost** `X-Forwarded-For` value. | Rotate a fake header and every per-IP OTP-send, verify, login, ambulance PIN, payment and lookup limit resets. SMS-pumping cost abuse and brute force. | `clientIpFromRawRequest()` uses the rightmost hop, matching the gateway and admin module. All four call sites use it. | **Fixed** |
| 4 | High | `s3_storage.js` `confirmS3UploadHandler` | No ownership check for `lab_reports` (any lab), `prescriptions`, `promoted_ads` or unknown prefixes. On a type or size mismatch the handler **deletes** the object, and `purpose` was never tied to the key. | Any user could delete other patients' records over 5 MB by passing an image purpose; any lab could delete any booking's report. | Purpose must match the key prefix (`CONFIRM_PURPOSE_PREFIX`). Authorization reuses `authorizeDelete` (booking ownership for labs, owner for everything else). Unknown prefixes are denied. All checks run before any S3 call. | **Fixed** |
| 5 | High | `db/migrations/20261020000001…:prescriptions_insert/update`, `20260930000004…:prescriptions_write` | Permissive policies OR together: `prescriptions_insert` needs only "verified doctor and own doctor_id", with **no doctor–patient relationship**. `prescriptions_write` (FOR ALL) let doctors DELETE prescriptions. | Any verified doctor could inject prescriptions into any patient's record via PostgREST, bypassing `create_prescription_atomic`. Medical records could be deleted. | Migration `20261124000002_prescriptions_require_care_relationship.sql`: insert and update require `private.doctor_has_relationship(patient_id)`; `prescriptions_write` dropped; DELETE revoked from clients. | **Fixed (migration must be applied)** |
| 6 | High | `registration_otp.js` `sendUserRegistrationOtp` | Rate limits ran **after** the account-existence lookup, which returns distinct "already registered" / "no account" errors. | Unlimited phone-number enumeration (which numbers are patients or doctors). | Rate limits now run first, before any lookup. | **Fixed** |
| 7 | High | `registration_otp.js` `enforceSendOtpRateLimits` | Per-mobile bucket keyed by `role + digits`, so each of the 5 roles had its own bucket. No daily cap. | 5× the intended SMS per number per hour; unbounded daily SMS cost. | Bucket keyed by number only. Added daily caps: 10 per number and 50 per IP per 24 h. | **Fixed** |
| 8 | High | `.env:PROD_RDS_SSLMODE=require` | Production RDS TLS without certificate verification. | MITM on DB traffic from operator scripts and Functions `pg_pool`. | Set to `verify-full` in `.env`; `pg_pool` already refuses insecure SSL in production. Added a test. | **Fixed** |
| 9 | Medium | `promoted_ads.js` `activatePromotedAdPayment` (Postgres) | Supabase `{ error }` ignored (a DB error looked like "not processed"); non-atomic check-then-update; webhook event row written before processing. | Double activation under concurrent verify plus webhook; a failed run marked as processed and never retried. | Fail closed on DB errors. Compare-and-set update (`status='pending_payment' AND razorpay_order_id=…`). Event recorded last. Webhook returns 503 on DB errors so Razorpay retries. Ownership is always required. | **Fixed** |
| 10 | Medium | `promoted_ads.js` `makeRazorpayRequest` | No timeout; parse errors echoed the full gateway body into errors and logs. | Hung Functions; payment payloads in logs. | 10 s timeout; body no longer echoed. | **Fixed** |
| 11 | Medium | `db/…phase_e3…:razorpay_orders_insert` | Clients could INSERT ledger rows with any `order_id` or amount. | Ledger poisoning. | Insert and update policies dropped; INSERT, UPDATE and DELETE revoked on all 3 payment ledgers. | **Fixed (migration)** |
| 12 | Medium | `registration_otp.js:23` | OTP lifetime 10 min. | Longer brute-force and replay window. | 5 min (Redis TTL follows). | **Fixed** |
| 13 | Medium | `registration_otp.js` `logMsg91Otp` and send-path logs | Logged `templateId`, `dltId`, `senderId`, the full mobile (`requestPayload.mobile`) and the raw client IP. | Provider config and PII in Cloud Logging. | A central redactor removes template, sender, OTP and authkey fields, masks mobiles and sanitizes response bodies. IP is hashed. | **Fixed** |
| 14 | Medium | `registration_otp.js` MSG91 error path | Users saw "Server IP not whitelisted in MSG91… Cloud Run proxy". | Infrastructure disclosure. | Generic user message; detail goes to logs only. | **Fixed** |
| 15 | Medium | `index.js` `lookupMobileRegistration` | Existence oracle under the generic `api` limit (120 per minute per IP). | Bulk enumeration. | New `account_lookup` bucket: 20 per 15 min per IP and 10 per 15 min per number. | **Fixed** |
| 16 | Medium | `s3_storage.js` `getS3DownloadUrlHandler` | With `S3_URL_CACHE=on`, PHI URLs (health records, lab reports, KYC) lasted 1 h and were cached. | Long-lived bearer links to medical files. | PHI and KYC keys always get a fresh, uncached 300 s URL; the cache only applies to public media. | **Fixed** |
| 17 | Medium | `s3_storage.js` confirm | Only the client-declared Content-Type was checked. | HTML or other polyglots uploaded as "PDF/JPEG". | Magic-byte check (JPEG, PNG, WebP, PDF) via a 16-byte ranged GET; deletes on mismatch. | **Fixed** |
| 18 | Low | `src/config/redis.js` | Production allowed Redis with no AUTH password. | Unauthenticated OTP / rate-limit store if the network is exposed. | Production now requires verified TLS **and** `REDIS_PASSWORD` (`REDIS_INSECURE_CONFIG`). | **Fixed** |
| 19 | Low | `services/api-gateway/src/proxy.js`, `server.js` | No security headers on gateway responses; PostgREST `details` and `hint` (SQL internals) passed through; `/healthz` and body errors echoed internal error text. | Information disclosure; possible caching of PHI responses. | `nosniff`, `DENY`, `no-store`, HSTS and `no-referrer` on every response. Error bodies cut to `{code, message}`. Healthz and body-read errors are generic. | **Fixed** |
| 20 | Low | `frontend/lib/main.dart` | `debugPrint` stays active in release; error strings can contain phone numbers or ids. | PII in logcat. | `debugPrint` is a no-op in `kReleaseMode`. | **Fixed** |
| 21 | Low | `backend/functions/seed_demo_accounts.js`, `backend/functions/scripts/seed_demo_accounts.js` | Legacy Firestore seeding hard-wired to the **production** project `medibond-45fad`. | Demo accounts could be written into production; leftover Firestore code. | Deleted (they're in git history if needed). | **Fixed** |
| 22 | Low | `.env.example` | `ENFORCE_OTP_APP_CHECK=false` default; `PROD_RDS_USER=postgres`; service-account path inside the repo; duplicate `REVIEW_TEST_NUMBERS`; 6 variables the code reads were missing. | Insecure copy-paste defaults; failed env-parity CI. | Secure defaults, least-privilege role placeholder, path outside the repo, duplicate removed, all missing keys added with comments. | **Fixed** |
| 23 | Low | Repo hygiene | `backend/functions/.secret.local.example` (a 3rd env file); `firestore-debug.log` ×3; `_rpc_diff_*.sql`; tracked `_smoke_fail.txt`; dead `src/config/redis.ts`; `tfplan` not ignored. | Policy violation ("only .env + .env.example"); clutter; possible secrets in plan files. | Removed; `.gitignore` now covers `tfplan`. | **Fixed** |

### Verified as already correct (no change needed)
- **Gateway auth:** Firebase ID token checked against Google JWKS with `checkRevoked` in production. Role and uid come only from the verified token and DB (forged `x-user-role` is ignored; there's a test for it). Constant-time service-key compare with lockout. Table, RPC and embed allowlists. `public` schema only. Client routing hints rejected.
- **Signup roles:** `trg_users_guard_insert` blocks admin roles and enforces `id = jwt.sub`.
- **OTP core:** `crypto.randomInt`; HMAC(role:digits:code) hashes; `timingSafeEqual`; 5-attempt atomic lockout (Lua INCR+PEXPIRE); 60 s resend cooldown; single use (deleted on success); `OTP_TEST_MODE` blocked in production; E.164/Indian mobile normalization (`^[6-9]\d{9}$`).
- **Reviewer OTP bypass:** needs `REVIEWER_OTP_ENABLED=true` plus `REVIEW_FIXED_OTP` (Secret Manager) and `REVIEW_ACCESS_UNTIL`; at most 2 numbers per role; own rate limit; numbers are in the fictitious `99999000xx` range.
- **Razorpay:** HMAC-SHA256 of `order_id|payment_id` and of the raw webhook body, constant-time compare; payment re-fetched from Razorpay (captured, INR, order notes match); dedupe by event id and payment id; amount checked against the server price table; key secret only on the server, only `key_id` returned to the client.
- **Environment separation:** `resolveDataPlane` uses a server-side allowlist (client hints ignored); `pg_pool` refuses Supabase URLs in production; Redis keys are prefixed `prod:` / `staging:`; S3 prefixes are `demo/` / `prod/`.
- **RLS:** All 186 policies were reconstructed from the 76 ordered migrations. RLS is enabled on every table and every SECURITY DEFINER function sets `search_path`. The only `USING (true)` policies are on directory and catalog tables (doctor education, facilities and availability, community catalogs, `lab_catalog_tests`, `medical_directory`, `review_votes`). PHI tables (`patients`, `health_records`, `lab_bookings`, `ambulance_requests`, `prescriptions` SELECT) are limited to owner, assigned provider, care relationship, or admin.
- **Mobile:** `allowBackup=false`; release minify and shrink on; only the launcher activity is exported; no secrets in Dart (only the public Firebase web config); Firestore SDK fully removed from `frontend/lib`.
- **Hosting:** strict CSP, HSTS preload, `X-Frame-Options: DENY`, `nosniff`, Permissions-Policy.
- **Secrets in git:** the tracked file index has no service accounts, `.env`, keystores, `google-services.json` or tfvars. The repo's own history scan (371 commits) found only public CA certs.

---

## 3. What could NOT be fixed in code (and why)

| Item | Reason |
|------|--------|
| Branch, commits, push | `git` isn't installed on this machine. |
| `npm audit` / dependency upgrades | `npm` isn't installed; only a bundled Node 24 binary is available. Run `npm audit --omit=dev` in `backend/functions` and `services/api-gateway`. |
| `flutter analyze` / `flutter test` / release build | The Flutter SDK isn't installed. |
| Remaining Firestore code in `backend/functions` (`cross_role_sync.js`, legacy branches in `registration_otp.js`, `index.js` ambulance helpers, `abuse_rate_limit.assertBucket`) | At runtime `isDoctorPatientSupabasePrimary()` always returns true, so these branches only run under `__TEST_FORCE_LEGACY_DOCTOR_PATIENT=1` (tests). Removing about 300 KB of dual-path code safely needs its own PR and the emulator suites. **Your `.env` doesn't set `FIRESTORE_FORBIDDEN=1`**; set it once you've confirmed with `npm run audit:firestore-reachability`. |
| `confirmS3Upload` for `prescriptions/` keys | Now denied by default. If an upload flow ever uses that prefix, add an explicit owner rule there. |
| Live DB checks (Supabase Security Advisor, RDS grants, `pg_policies` diff) | No DB access from here. Run `scripts/db/rls_coverage_audit.js` and `scripts/db/grant_matrix_audit.js` against staging and RDS after applying the migrations. |
| S3, RDS, Redis, security groups, WAF | Created in the console, not in Terraform (`infra/aws/rds.tf` says so). See the manual steps. |
| Hardcoded `admin@doctornect.com` super-admin fallback in `promoted_ads.js` / `s3_storage.js` | Admin is out of scope. It's gated on `email_verified === true`; make sure email/password sign-up is off for that domain or remove the fallback. |

---

## 4. MANUAL STEPS FOR YOU

### 4.1 Secrets to rotate / remove
1. **Firebase Admin service-account key** (`medibond-45fad`, private key on disk at `scripts/service-account.json` and `.artifacts/reports/service-account.json`). Neither is in git, but both are unencrypted private keys inside the project folder. **Rotate it in GCP IAM → Service Accounts → Keys, delete the old key, store the new one outside the repo** (`FIREBASE_SERVICE_ACCOUNT_PATH`), then delete both copies.
2. **MSG91 authkey in `backend/functions/.secret.local`.** It differs from the key in `.env`, so it's either stale or a second live key. Revoke it in MSG91 if it's still active, then delete the file (it's the 3rd env file the policy forbids; I didn't delete it because it may be your only copy).
3. **`upload-keystore.jks` and `frontend/android/key.properties`** are untracked but sit in the repo folder. Move them to a secure location. They don't need rotating unless they've been shared.
4. **RDS master credentials** (`PROD_RDS_MASTER_USER/PASSWORD` in `.env`). Keep them only in AWS Secrets Manager; remove them from `.env`.
5. Prior rotation list (`docs/ops/test_runs/secrets_rotation_audit.txt`) still applies if any key has ever been shared outside Secret Manager.

### 4.2 Apply migrations (staging Supabase first, then RDS)
```
db/migrations/20261124000001_promoted_ads_payment_state_guard.sql
db/migrations/20261124000002_prescriptions_require_care_relationship.sql
```
Use the usual runner (`scripts/db` migrate, dry-run then execute), on staging first, then RDS through the tunnel. Both files are idempotent and parse cleanly with libpg-query (PG grammar). After applying, re-run `scripts/db/rls_coverage_audit.js` and the RLS harness.

### 4.3 AWS console
- **RDS:** attach parameter group `*-pg18-cron` (has `rds.force_ssl=1`) and reboot. Publicly accessible = **No**. Storage encryption (KMS) **on**. Automated backups ≥ 7 days. Deletion protection on. SG inbound 5432 **only** from the ECS gateway SG and your SSM bastion. Runtime traffic goes through PostgREST `authenticator`; create a least-privilege login (e.g. `app_migrator` / `doctornect_app`) and stop using `doctornect_admin` / master for scripts and `pg_pool`.
- **S3 (separate staging and production buckets):** Block Public Access = all four on; no public ACLs or policies; default encryption SSE-S3 or SSE-KMS; versioning on; CORS `AllowedOrigins` limited to your app and web origins with PUT/GET only; server access logging on; lifecycle rule to expire unconfirmed uploads. Separate IAM user or role per environment, limited to `s3:GetObject/PutObject/DeleteObject` on `arn:aws:s3:::<bucket>/*` (no `*`). Prefer workload identity over long-lived keys and rotate `AWS_ACCESS_KEY_ID`.
- **Redis (Memorystore / ElastiCache / Upstash):** no public IP; AUTH or ACL password set (Functions now refuse to start without one in production); in-transit TLS on; `rename-command FLUSHALL/FLUSHDB/KEYS/CONFIG ""` if your provider allows it.
- **WAF / ALB:** keep `waf.tf` rate rules attached to the gateway ALB.

### 4.4 Firebase console
- Authentication → Sign-in methods: enable only **Phone** and Custom Token flows. Disable Email/Password, Anonymous (unless the ambulance flow still needs it), and other providers you don't use.
- Authentication → Settings → Authorized domains: remove `localhost` and preview domains from production.
- Google Cloud → API keys: restrict Android keys (package plus SHA-256), iOS keys (bundle id) and the web key (HTTP referrers), each to only the needed APIs.
- **App Check:** enforce for Cloud Functions (Play Integrity / App Attest / reCAPTCHA Enterprise). Keep `ENFORCE_OTP_APP_CHECK=true` and `ENFORCE_ABUSE_APP_CHECK=true`; set `ENFORCE_AMBULANCE_HTTP_APP_CHECK=true` once the ambulance client sends tokens.
- Firestore: deploy the deny-all `backend/firestore.rules` one last time, export if needed, then **delete the Firestore database**. Do the same for Firebase Storage if it's empty.
- Secret Manager: confirm `REVIEW_FIXED_OTP`, `PROD_GATEWAY_SERVICE_KEY`, `DEMO_SUPABASE_SERVICE_ROLE_KEY`, `RAZORPAY_*`, `MSG91_AUTH_KEY`, `OTP_HMAC_SECRET` and `REDIS_PASSWORD` are bound. After review is over, set `REVIEWER_OTP_ENABLED=false` (the access window ends 2026-12-31).

### 4.5 MSG91
- IP allowlist set to the static egress IP (VPC connector or proxy) only.
- DLT templates and sender ID set; OTP expiry on the MSG91 side ≤ 5 min.
- Turn on the account's daily spend and SMS caps and low-balance alerts (SMS-pumping guard).

### 4.6 Razorpay
- Live keys in production Secret Manager only; test keys in staging only.
- Webhook URL → `razorpayWebhook`, events `payment.captured` and `order.paid` only, with a unique secret per environment.
- Turn on payment auto-capture.

### 4.7 Supabase (staging)
- Run Security Advisor and fix any new warnings after applying the migrations.
- Confirm the `anon` role has no grants on `promoted_ads`, `razorpay_*` or PHI tables.
- Storage: no public buckets (files are in S3).
- Store the service-role key only in Secret Manager and CI secrets.

---

## 5. Verification

| Check | Result |
|-------|--------|
| Backend tests `node --test` (`backend/functions`) | **605 tests: 581 pass, 0 fail, 24 skipped** (the skips need the Firestore/Storage emulator). The 3 tests failing at baseline (M-5 regex, ENV-01 parity, pg_pool SSL) now pass. |
| Gateway tests (`services/api-gateway`) | 96 / 96 pass (one earlier run hit a timing flake in the allowlist scanner under concurrency; it passes alone and on re-run). |
| New regression suite `test/security_audit_2026_11_fixes.test.js` | 9 / 9 pass. |
| `node --check` build (`npm run build` equivalent) | Pass. |
| Env guards: duplicate keys, file policy, `.env.example` secret heuristic, key parity, `check_env_parity` | Pass. `guard_committed_infra_fingerprints` needs `git`, so it wasn't run. |
| New SQL migrations | Parse cleanly with libpg-query, including the PL/pgSQL trigger body. |
| `flutter analyze` / `flutter test` / `npm audit` | **Not run.** The toolchains aren't installed here. |

---

## 6. Commit plan (run once git is available)

```
git switch -c security/full-audit-fix
git add db/migrations/20261124000001_promoted_ads_payment_state_guard.sql db/migrations/20261124000002_prescriptions_require_care_relationship.sql
git commit -m "fix(db): server-owned promoted_ads payment state; prescriptions require care relationship"
git add backend/functions/promoted_ads.js backend/functions/test/helpers/promoted_ads_supabase_mock.js backend/functions/test/razorpay_webhook_security.test.js
git commit -m "fix(payments): Postgres Razorpay order/verify, CAS activation, fail-closed ledger"
git add backend/functions/abuse_rate_limit.js backend/functions/index.js backend/functions/security_logger.js backend/functions/registration_otp.js backend/functions/test/backend_audit_fixes.test.js
git commit -m "fix(otp): rightmost XFF, limits before lookup, per-number + daily caps, 5-min OTP, log redaction"
git add backend/functions/s3_storage.js backend/functions/test/s3_url_cache.test.js
git commit -m "fix(s3): authorize confirm before S3, magic bytes, short-lived PHI URLs"
git add backend/functions/src/config/redis.js backend/functions/test/assert_app_env.test.js backend/functions/test/pg_pool_routing.test.js services/api-gateway/src frontend/lib/main.dart
git commit -m "fix: redis auth required in prod, gateway headers/error sanitizing, release log mute"
git add -A .env.example .gitignore SECURITY_AUDIT_REPORT.md backend/functions/test/security_audit_2026_11_fixes.test.js
git rm --cached -r --ignore-unmatch backend/functions/.secret.local.example backend/functions/seed_demo_accounts.js backend/functions/scripts/seed_demo_accounts.js backend/functions/src/config/redis.ts _smoke_fail.txt
git commit -m "chore: env template parity, remove legacy seeds/debug files, audit report"
```
