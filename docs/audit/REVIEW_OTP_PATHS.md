# Review / demo OTP env paths (names only)

---

## Environment variables

| Name | File:line (representative) | Role |
|------|----------------------------|------|
| `REVIEW_TEST_NUMBERS` | `registration_otp.js:141`, `:120` (comment) | Comma-separated reviewer mobiles |
| `REVIEW_FIXED_OTP` | `registration_otp.js:142` | Fixed six-digit code for allowlisted numbers |
| `REVIEW_ACCESS_UNTIL` | `registration_otp.js:143`, `:155-157` | ISO expiry; bypass off after timestamp |
| `ENABLE_REVIEW_DEMO` | `registration_otp.js:132`, `:181` | Production gate for reviewer bypass |
| `OTP_TEST_MODE` | `secure_config.js:40`, `:60`; `production_otp_guard.js:52-53`, `:70-71` | Dev/test OTP shortcuts (blocked in prod runtime) |
| `DEMO_PHONE_PATIENT` | `production_otp_guard.js:7`, `:57-58` | Demo phone env keys — cold-start block in prod |
| `GOOGLE_PLAY_REVIEW_PHONE` | `production_otp_guard.js:8` | Same |
| `DEMO_PHONE_DOCTOR` | `production_otp_guard.js:10` | Same |
| `DEMO_PHONE_MEDICAL_STORE` | `production_otp_guard.js:11` | Same |
| `DEMO_PHONE_PHARMACY` | `production_otp_guard.js:12` | Same |
| `DEMO_PHONE_LAB` | `production_otp_guard.js:13` | Same |
| `DEMO_PHONE_AMBULANCE` | `production_otp_guard.js:14` | Same |
| `DEMO_PHONE_SUPER_ADMIN` | `production_otp_guard.js:15` | Same |
| `TEST_PHONE_NUMBER` | `production_otp_guard.js:9` | Same |

Tests touching reviewer/demo env: `test/reviewer_login.test.js`, `test/demo_bypass_removal.test.js`, `test/otp_send_verify_roundtrip.test.js`, `test/production_otp_guard.test.js`, `test/review_fixed_otp_expired.test.js`.

---

## Code paths — fixed OTP (`REVIEW_*`)

| Step | Location | Behavior |
|------|----------|----------|
| Config load | `getReviewerConfig()` `registration_otp.js:129-174` | Returns `null` unless all reviewer env set and not expired; production requires `ENABLE_REVIEW_DEMO=true` and role **patient** only |
| Phone check | `isReviewerPhone()` `:176-187` | Same production gates |
| Send OTP | `:1797-1798`, `:1932-1933` | Reviewer account gets `fixedOtp` instead of random |
| Verify OTP | `:2108-2109`, `:2224-2225` | `isReviewerValid` accepts `otp === reviewerCfg.fixedOtp` for allowlisted phone + role |

`production_otp_guard.js` **does not** read `REVIEW_*`; reviewer bypass is independent of `OTP_TEST_MODE` / demo phone keys for cold-start blocking.

---

## When is a fixed OTP accepted in **production**?

All must hold:

1. **Cloud Run / Functions runtime** for project `medibond-45fad` (see `production_otp_guard.js` — blocks `OTP_TEST_MODE` and demo phone env keys on cold start; does not block `REVIEW_*`).
2. `APP_ENV=production` → `ENABLE_REVIEW_DEMO=true`.
3. `REVIEW_TEST_NUMBERS`, `REVIEW_FIXED_OTP`, and `REVIEW_ACCESS_UNTIL` set; `REVIEW_ACCESS_UNTIL` parses and is **in the future**.
4. Request role normalizes to **`patient`**.
5. Mobile digits match allowlist; submitted OTP equals `REVIEW_FIXED_OTP`.
6. Reviewer rate limit (`checkReviewerRateLimit`, `:272-273`) not exceeded.

Otherwise verification follows normal hashed OTP path (`consumeOtpChallengeAtomically`).

---

## How to disable fixed OTP in production

Pick one (prefer 1+2):

1. Unset or remove `REVIEW_TEST_NUMBERS`, `REVIEW_FIXED_OTP`, and/or `REVIEW_ACCESS_UNTIL` from **deployed** function env; redeploy OTP exports.
2. Set `REVIEW_ACCESS_UNTIL` to a **past** ISO timestamp (immediate off without removing keys).
3. Ensure `ENABLE_REVIEW_DEMO` is **not** `true` when `APP_ENV=production` (default safe).
4. For Play review windows only: enable all three `REVIEW_*` + `ENABLE_REVIEW_DEMO=true` with a short `REVIEW_ACCESS_UNTIL`; disable after review.

After config change, redeploy at least `sendUserRegistrationOtp` and `verifyUserRegistrationOtp`.
