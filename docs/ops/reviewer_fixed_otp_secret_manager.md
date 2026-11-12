# Play Store & App Store Reviewer Fixed OTP — Secret Manager Runbook

## Overview
To satisfy Google Play Console and Apple App Store review guidelines without compromising security or storing plain-text test credentials in codebase or unencrypted environment files, DoctorNect employs server-side allowlisting with rate-limited OTP bypass.

The reviewer flow enforces:
1. **Server-Side Allowlist Only**: Only phone numbers listed in `REVIEW_TEST_NUMBERS` are eligible.
2. **Hard Expiry Timestamp**: The bypass automatically deactivates after `REVIEW_ACCESS_UNTIL` (ISO 8601).
3. **Secret Manager Encryption**: `REVIEW_FIXED_OTP` is stored exclusively in Google Cloud Secret Manager and mounted as a secret in Cloud Functions v2.
4. **Redis-Backed Atomic Rate Limiter (Fail-Closed)**: Max 5 attempts per allowlisted number per 15-minute window via Google Cloud Memorystore Redis. If Redis is unreachable, requests fail closed (HTTP 503 Unavailable).
5. **Production Default is OFF**: If any of `REVIEW_TEST_NUMBERS`, `REVIEW_FIXED_OTP`, or `REVIEW_ACCESS_UNTIL` is unset or expired, reviewer bypass is completely inactive.

---

## 1. Secret Manager Configuration

### Step 1.1: Create the Secret in Google Cloud Secret Manager
Run the following Google Cloud CLI command (replace project ID if needed):

```bash
# Create the secret definition
gcloud secrets create REVIEW_FIXED_OTP \
  --replication-policy="automatic" \
  --project="doctornect-prod"
```

### Step 1.2: Add Secret Version
Provide the 6-digit review OTP without a trailing newline:

```bash
# Example: storing the 6-digit fixed OTP securely
echo -n "YOUR_6_DIGIT_REVIEW_OTP" | gcloud secrets versions add REVIEW_FIXED_OTP \
  --data-file=- \
  --project="doctornect-prod"
```

> [!WARNING]
> Never hardcode or echo plaintext secret values into terminal history without clearing it, and never commit values to `.env` or Git.

### Step 1.3: Grant Access to the Cloud Functions Service Account
Ensure the App Engine / Cloud Functions runtime service account has `roles/secretmanager.secretAccessor`:

```bash
PROJECT_NUMBER=$(gcloud projects describe doctornect-prod --format="value(projectNumber)")

gcloud secrets add-iam-policy-binding REVIEW_FIXED_OTP \
  --project="doctornect-prod" \
  --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"

gcloud secrets add-iam-policy-binding REVIEW_FIXED_OTP \
  --project="doctornect-prod" \
  --member="serviceAccount:doctornect-prod@appspot.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"
```

---

## 2. Cloud Functions v2 Code Binding

In `backend/functions`, declare `REVIEW_FIXED_OTP` via `defineSecret`:

```javascript
const { defineSecret } = require('firebase-functions/params');

const reviewFixedOtp = defineSecret('REVIEW_FIXED_OTP');
```

Mount `reviewFixedOtp` in the callable options for functions serving the registration / login OTP endpoints:

```javascript
exports.sendUserRegistrationOtp = onCall(
  {
    secrets: [reviewFixedOtp, ...REDIS_SECRETS],
    // ...
  },
  handler
);

exports.verifyUserRegistrationOtp = onCall(
  {
    secrets: [reviewFixedOtp, ...REDIS_SECRETS],
    // ...
  },
  handler
);
```

Within the function runtime, read via:
```javascript
const fixedOtp = reviewFixedOtp.value() || process.env.REVIEW_FIXED_OTP || '';
```

---

## 3. Companion Environment Variables

Set non-secret parameters in `backend/functions/.env` or runtime environment:

| Variable | Example Value | Description |
|---|---|---|
| `REVIEW_TEST_NUMBERS` | `9999900001,9999900002,9999900003,9999900004,9999900005` | Comma-separated allowlist of 10-digit test phone numbers |
| `REVIEW_ACCESS_UNTIL` | `2026-12-31T23:59:59Z` | Strict ISO 8601 timestamp after which bypass shuts down |

---

## 4. Verification & Testing

### Verification Checklist
- [ ] Try a non-allowlisted phone number with the fixed OTP: must fail with `Invalid OTP`.
- [ ] Try an allowlisted phone number with a wrong OTP: must fail with `Invalid OTP`.
- [ ] Try an allowlisted phone number with the fixed OTP: succeeds and signs in.
- [ ] Send 6 consecutive attempts for an allowlisted number within 15 minutes: 6th attempt must be blocked with `resource-exhausted`.
- [ ] Disconnect Redis or pass broken client: must fail closed (`unavailable`), never allowing unrestricted bypass.
- [ ] Change `REVIEW_ACCESS_UNTIL` to a past timestamp: bypass immediately stops working.
