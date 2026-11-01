# Backend unit tests vs real services

Emulator suites: [EMULATOR_TESTS.md](./EMULATOR_TESTS.md) (`npm run test:emulators`).

## Root cause (ambulance OTP / full-suite hang)

Commit **`92a983c`** added `test/setup_env.js` that **merged `backend/functions/.env`** into `process.env` before tests. That turned on **`OTP_REDIS_MIRROR=on`** and real **`REDIS_HOST`**, so `registration_otp.js` opened **TCP to Memorystore** and OTP session consumption diverged from fake Firestore DB tests.

**Safety commit `5c107e9`:** `complete_ambulance_mobile_otp_login_auth_uid.test.js` — **7/7 pass**, ~13s, **without** `setup_env` (after `npm ci` in worktree).

**With broken setup (load `.env`):** same file **6/7 fail** in &lt;1s or **hang** when Redis/Firebase Auth use live credentials.

## Fix (test harness only)

`test/setup_env.js` now:

- Does **not** read `backend/functions/.env`
- Sets `APP_ENV=test`, `OTP_REDIS_MIRROR=off`, dummy `S3_BUCKET`
- Strips common deploy secret env keys if inherited from the shell
- Registers **`setRedisClientForTesting(noopRedis)`** so `registration_otp` never opens Redis TCP

## When `.env` was loaded (before fix) — modules that could touch real infra

| Surface | Module / path | Trigger |
|---------|---------------|---------|
| Redis | `src/config/redis.js`, `registration_otp.js` | `OTP_REDIS_MIRROR=on`, `REDIS_HOST` from `.env` |
| Firebase Auth | `firebase-admin/auth` via `getAuth().setCustomUserClaims` | ADC / project creds from environment |
| Supabase REST | `@supabase/supabase-js` in tests that call `getDatabaseClient()` without mocks | `SUPABASE_URL` + service key in `.env` |
| S3 | `@aws-sdk/client-s3` | `AWS_*` + `S3_BUCKET` in `.env` |

Default **`npm test`** should use the harness above; integration tests that need emulators use `firebase emulators:exec` scripts (separate from default suite).

## Bisect

Not required: **`5c107e9` passes** ambulance OTP tests; regression isolated to **`92a983c`** `.env` merge in `setup_env.js`, not dedupe doc/script commits.

## Exposure window (`92a983c` … fix): which default `npm test` files could reach real services

When `setup_env.js` merged **`backend/functions/.env`**, typical enables: `OTP_REDIS_MIRROR=on`, `REDIS_HOST`, `MSG91_AUTH_KEY`, `SUPABASE_URL`, `SUPABASE_SECRET_KEY`, `S3_BUCKET`, etc.

| Service | Connecting module | Test files at elevated risk (default suite) |
|---------|-------------------|---------------------------------------------|
| **Redis** | `src/config/redis.js` (ioredis), `registration_otp.js` (`getOtpRedisClient`, session/challenge keys via `src/config/redis_keys.js`) | `otp_retry_fallback.test.js`, `otp_verification_race.test.js`, `otp_send_verify_roundtrip.test.js`, `otp_pure_redis_mode.test.js`, `otp_session_replay.test.js`, `otp_send_abuse_rate_limit.test.js`, `redis.test.js`, `redis_abuse_rate_limit.test.js`, `complete_ambulance_mobile_otp_login_auth_uid.test.js`, `client_read_replay.rules.test.js`, `ambulance_login_lockout.test.js`, `login_failure_tracking.test.js`, `mobile_registration_lookup.test.js`, `s3_url_cache.test.js`, `delete_my_account_supabase.test.js` |
| **Firebase Auth** | `firebase-admin/auth` (`getAuth`) via `registration_otp.js` | `complete_ambulance_mobile_otp_login_auth_uid.test.js`, `client_read_replay.rules.test.js`, `delete_my_account_supabase.test.js`, `user_registration_claims.test.js` |
| **Supabase REST** | `@supabase/supabase-js` in `src/db/client.js` | `db_client.test.js`, `delete_my_account_supabase.test.js`, `production_provisioning_gateway.test.js`, `cross_role_sync.test.js`, `user_identity_bridge.test.js`, sync/delete tests that call `getDatabaseClient()` without stubs |
| **S3** | `@aws-sdk/client-s3` in `s3_storage.js` | `s3_storage.test.js`, `s3_url_cache.test.js`, `delete_my_account_s3.test.js` (mocked in-file when hooks used; **live** if mocks bypassed and `AWS_*` present — local `.env` had **no** AWS keys) |
| **Firebase Admin (Firestore API)** | `firebase-admin/firestore` | Emulator-only `*.rules.test.js` skip without `FIRESTORE_EMULATOR_HOST`; not live Firestore in default suite |

### MSG91 SMS send (`sendMsg91SmsOtp` / HTTP in `registration_otp.js`)

Default-suite OTP tests **mock HTTP** or exercise **fake DB** paths; none import `sendMsg91SmsOtp` directly. **`sendMsg91SmsOtp` could run** only if a test invoked **`sendRegistrationOtp` / `sendOtp`** (or resend helpers) **without** stubbing `fetch`/`https` **and** real `MSG91_AUTH_KEY` was loaded — highest theoretical risk: **`otp_send_verify_roundtrip.test.js`**, **`otp_retry_fallback.test.js`** (they set mock keys; live key from `.env` would override behavior if not cleared). No evidence of successful live SMS sends from test code paths reviewed.

### Redis key scan (after exposure window, prefixes only)

Live Memorystore scan (connection only, **no values**): counts **0** for `staging:otp:*`, `prod:otp:*`, `test:otp:*`, `*:otp:session:*`, `*:otp:challenge:*`, `*:otp:attempts:*`.
