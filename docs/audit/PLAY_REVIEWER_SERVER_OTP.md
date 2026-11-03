# Play Store reviewer login (server-only, default OFF)

No Flutter demo flags. Reviewer bypass lives entirely in **`sendUserRegistrationOtp` / `verifyUserRegistrationOtp`** (`backend/functions/registration_otp.js`).

## Enable for Google Play review

1. Set Cloud Functions secrets / env (Firebase `functions:config` or Secret Manager — match your deploy pipeline):

| Variable | Example | Notes |
|----------|---------|-------|
| `REVIEWER_OTP_ENABLED` | `true` | **Default OFF** if unset. Also accepts legacy `ENABLE_REVIEW_DEMO=true`. |
| `REVIEW_FIXED_OTP` | `654321` | Fixed 6-digit OTP for allowlisted numbers only. |
| `REVIEW_ACCESS_UNTIL` | `2026-12-15T23:59:59Z` | ISO instant; bypass stops immediately after. |
| `REVIEW_PATIENT_PHONES` | `919999900001` | Max **2** comma-separated E.164-ish digits (normalized). |
| `REVIEW_DOCTOR_PHONES` | `919999900002` | Max **2** for doctor role login. |
| `REVIEW_LAB_PHONES` / `REVIEW_PHARMACY_PHONES` / … | optional | Pattern: `REVIEW_{ROLE}_PHONES` where role matches `normalizeRole()`. |
| `REVIEW_TEST_NUMBERS` | fallback | Legacy single list, max 2, used if role-specific list empty. |

2. Deploy **only** the functions bundle to your **staging/review** Firebase project (not production unless review requires it).

3. Seed Postgres (Supabase/RDS) accounts for the same phone numbers:

```sql
-- Patient reviewer (verified phone on users row; patient profile)
INSERT INTO public.users (uid, mobile, role, mobile_verified)
VALUES ('review-patient-uid', '919999900001', 'patient', true)
ON CONFLICT (uid) DO UPDATE SET mobile_verified = true;

INSERT INTO public.patients (patient_id, owner_uid, full_name, verified)
VALUES ('review-patient-1', 'review-patient-uid', 'Play Review Patient', true)
ON CONFLICT (patient_id) DO NOTHING;

-- Doctor reviewer (verified doctor for gated flows)
INSERT INTO public.users (uid, mobile, role, mobile_verified)
VALUES ('review-doctor-uid', '919999900002', 'doctor', true)
ON CONFLICT (uid) DO UPDATE SET mobile_verified = true;

INSERT INTO public.doctors (doctor_id, owner_uid, full_name, verified, deactivated)
VALUES ('review-doctor-1', 'review-doctor-uid', 'Play Review Doctor', true, false)
ON CONFLICT (doctor_id) DO UPDATE SET verified = true, deactivated = false;
```

Adjust IDs to match your Firebase Auth UIDs after first custom-token sign-in (or pre-create Auth users with those UIDs via Admin SDK).

4. Reviewer flow in app: normal registration/login → OTP screen → enter **`REVIEW_FIXED_OTP`** for allowlisted phone + matching **role** selected on login.

5. Monitor logs: `reviewer.otp_send`, `reviewer.login_failure`, `reviewer.rate_limited` (structured security events).

## Disable after review

1. Set `REVIEWER_OTP_ENABLED=false` (or remove variable) and redeploy functions **or** set `REVIEW_ACCESS_UNTIL` to a past date.
2. Remove allowlisted numbers from env.
3. Optional: revoke reviewer Firebase Auth users in Console.

## Safety properties

- Max **2** numbers per role list (truncated server-side).
- Rate limits on send/verify (Redis); fail-closed if Redis unavailable on verify path tests.
- Role-scoped: `isReviewerPhone(digits, role)` must match `getReviewerConfig(role)`.
- No client-side `kDebugMode` bypass for OTP.
