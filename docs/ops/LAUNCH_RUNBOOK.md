# DoctorNect 24-Hour Production Launch Runbook

> **Document Type:** Manual Operator Runbook  
> **Target Release:** DoctorNect Launch-Ready Build (Doctor, Patient, Pharmacy, Lab, Ambulance)  
> **Database:** Primary Supabase PostgreSQL (`DRNECT-DB`, Project Ref: `staging-project-ref`)  
> **Identity:** Firebase Authentication (`medibond-45fad`)  
> **Cache/Rate Limiting:** Redis / Google Cloud Memorystore  
> **Storage Mode for Launch:** Firebase Storage (Default, Safe; `use_s3_storage=false`)  
> **Strategy:** Clean cutover (Zero live users, no dual-sync bridge needed)  
> **Safety Rule:** No secrets printed. All operations performed by authorized operators.

---

## Table of Contents
1. [Pre-Requisites & Verification](#1-pre-requisites--verification)
2. [Step 1: Remote Supabase Migration Check](#step-1-remote-supabase-migration-check)
3. [Step 2: Enable Supabase Third-Party Auth (Firebase)](#step-2-enable-supabase-third-party-auth-firebase)
4. [Step 3: Staged Cloud Functions Redeployment](#step-3-staged-cloud-functions-redeployment)
5. [Step 4: Configure Razorpay Webhook](#step-4-configure-razorpay-webhook)
6. [Step 5: Activate Firebase Remote Config Flags](#step-5-activate-firebase-remote-config-flags)
7. [Step 6: Build Production Mobile Packages](#step-6-build-production-mobile-packages)
8. [Step 7: Post-Review Step — Decommission Reviewer Bypass](#step-7-post-review-step--decommission-reviewer-bypass)
9. [Emergency Rollback Procedures (Reversibility Matrix)](#emergency-rollback-procedures-reversibility-matrix)

---

## 1. Pre-Requisites & Verification

Before executing any commands, verify that your local environment is clean and passing all tests:

```powershell
# 1. Verify working directory
cd c:\Users\khije\Downloads\DoctorNect\doctor

# 2. Check environment parity
node scripts/check_env_parity.js
# Expected: Exit code 0 (0 undocumented core variables)

# 3. Verify client build pre-flight validator
node backend/scripts/verify_production_build_config.js --client-only
# Expected: All Critical Pre-Flight Checks PASSED!

# 4. Verify function tests and dependency audit
cd backend/functions
npm test
npm audit
cd ../..
# Expected: 0 high/critical vulnerabilities, all suites passing

# 5. Verify Flutter tests and static analysis
cd frontend
dart analyze lib
flutter test
cd ..
# Expected: 0 analyzer issues, all tests passing
```

---

## Step 1: Remote Supabase Migration Check
- **Operator Action:** Run CLI command
- **Estimated Time:** 1-2 minutes
- **Reversibility:** Fully non-destructive (Read-only check)

Verify that all 31 database migrations are applied on remote production Supabase:

```bash
npx supabase migration list --workdir backend --project-ref staging-project-ref
```

**Expected Result:**
All 31 migrations (`20260923000001` through `20261022000001`) must appear with timestamps in both `Local` and `Remote` columns. If any migration is missing, do NOT run destructive resets; inspect `db/migrations/` and apply missing migrations strictly via `npx supabase db push --workdir backend --project-ref staging-project-ref`.

---

## Step 2: Enable Supabase Third-Party Auth (Firebase)
- **Operator Action:** Web Dashboard Toggle
- **Estimated Time:** 3 minutes
- **Reversibility:** Fully Reversible (Can be disabled in Dashboard)

Supabase PostgreSQL verifies Firebase Auth JWTs. PostgREST must be authorized to decode tokens minted by Firebase:

1. Open your browser and navigate to:
   `https://supabase.com/dashboard/project/staging-project-ref/settings/auth`
2. Scroll to **Third-Party Auth** (or **Custom JWT Providers** / **Firebase Auth**).
3. Toggle **Firebase Auth** to **ON**.
4. Configure the settings:
   - **Project ID:** `medibond-45fad`
   - **Token Issuer:** `https://securetoken.google.com/medibond-45fad`
   - **Key Set URL (JWKS):** `https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com`
5. Click **Save Changes**.

---

## Step 3: Staged Cloud Functions Redeployment
- **Operator Action:** Run CLI commands in batches
- **Estimated Time:** 15-20 minutes total
- **Reversibility:** Fully Reversible (Can redeploy previous code or roll back)

The 50 Cloud Functions currently in production carry stale references to `legacy-staging-ref`. They must be redeployed to inject production configuration (`staging-project-ref`) from `backend/functions/.env`.

### Secret Sourcing Architecture & Overlap Invariants (Cloud Functions 2nd Gen)

#### The Secret Overlap Issue & Root Cause
During deployment of `deleteMyAccount`, Cloud Functions 2nd gen failed with:
```
Secret environment variable overlaps non secret environment variable: SUPABASE_URL
```
In Google Cloud Functions v2 (backed by Cloud Run), an environment variable name cannot exist simultaneously in both:
1. `serviceConfig.environmentVariables` (injected from plain `backend/functions/.env`), and
2. `serviceConfig.secretEnvironmentVariables` (injected via `defineSecret(...)` / Google Secret Manager).

#### Sourcing Decision (Smallest Safe Change)
- **`SUPABASE_URL`**: Sourced **exclusively from `backend/functions/.env`** as a plain environment variable across all functions. It is a public, non-sensitive URL (`https://staging-project-ref.supabase.co`) identical to the client app endpoint. Removing `defineSecret('SUPABASE_URL')` from `delete_my_account.js` eliminated the overlap with zero impact on other functions.
- **`SUPABASE_SERVICE_ROLE_KEY`**: Sourced **exclusively from Google Secret Manager (`medibond-45fad`, version 2)** via `defineSecret('SUPABASE_SERVICE_ROLE_KEY')`. It was deliberately removed from `backend/functions/.env` to avoid baking the master administrative secret into Cloud Run plain environment variables.
- **`AWS_ACCESS_KEY_ID` & `AWS_SECRET_ACCESS_KEY`**: Sourced **exclusively from Google Secret Manager (`medibond-45fad`, version 1)** via `defineSecret(...)` on `deleteMyAccount` and S3 storage endpoints. Commented out from `backend/functions/.env` to prevent overlap errors.
- **`RAZORPAY_WEBHOOK_SECRET`**: Sourced **exclusively from Google Secret Manager** on `razorpayWebhook`.

#### Secret Sourcing Matrix

| Function / Module | Reads SUPABASE_URL How | Reads SERVICE_ROLE_KEY How | Bound as Secret? | Breaks Without Key in .env? | Status / Sourcing Note |
|:---|:---|:---|:---:|:---:|:---|
| **deleteMyAccount** | `process.env.SUPABASE_URL` | `readBoundSecret()` / `process.env` | `supabaseServiceRoleKey` | No | Overlap fixed: removed `defineSecret('SUPABASE_URL')`. Key sourced from Secret Manager v2. |
| **getS3UploadUrl** | `process.env.SUPABASE_URL` | `process.env.SUPABASE_SERVICE_ROLE_KEY` | `supabaseServiceRoleKey` | No | Bound `supabaseServiceRoleKey` in `CALLABLE_OPTIONS` with AWS credentials. |
| **getS3DownloadUrl** | `process.env.SUPABASE_URL` | `process.env.SUPABASE_SERVICE_ROLE_KEY` | `supabaseServiceRoleKey` | No | Bound `supabaseServiceRoleKey` in `CALLABLE_OPTIONS` with AWS credentials. |
| **getS3DownloadUrls** | `process.env.SUPABASE_URL` | `process.env.SUPABASE_SERVICE_ROLE_KEY` | `supabaseServiceRoleKey` | No | Bound `supabaseServiceRoleKey` in `CALLABLE_OPTIONS` with AWS credentials. |
| **deleteS3Object** | `process.env.SUPABASE_URL` | `process.env.SUPABASE_SERVICE_ROLE_KEY` | `supabaseServiceRoleKey` | No | Bound `supabaseServiceRoleKey` in `CALLABLE_OPTIONS` with AWS credentials. |
| **confirmS3Upload** | `process.env.SUPABASE_URL` | `process.env.SUPABASE_SERVICE_ROLE_KEY` | `supabaseServiceRoleKey` | No | Bound `supabaseServiceRoleKey` in `CALLABLE_OPTIONS` with AWS credentials. |
| **caller_identity.js** | `process.env.SUPABASE_URL` | `process.env.SUPABASE_SERVICE_ROLE_KEY` | Inherited from caller | No | Uses client passed by caller or process.env populated by Cloud Run secret mount. |
| **cross_role_sync.js** | `process.env.SUPABASE_URL` | `process.env.SUPABASE_SERVICE_ROLE_KEY` | `SYNC_SECRETS` | No | Sync bridge is disabled (`ENABLE_SUPABASE_SYNC=0`). Not deployed for launch. |
| **promoted_ads.js** | `process.env.SUPABASE_URL` | `process.env.SUPABASE_SERVICE_ROLE_KEY` | None (reads .env / caller) | No | Razorpay webhook uses Firestore ledger; admin approval uses caller identity. |
| **registration_otp.js** | `process.env.SUPABASE_URL` | `process.env.SUPABASE_SERVICE_ROLE_KEY` | None | No | OTP flow uses Redis/Firestore. User account verification updates Supabase via caller. |

### Pre-Deployment Environment Guard
Before deploying any batch, verify that all required secrets and configuration are present:
```bash
# Verify core credentials (Supabase, MSG91, Redis, Razorpay ID/Secret)
node scripts/predeploy_secret_check.js --core-only

# Verify specific batch readiness:
node scripts/predeploy_secret_check.js --batch=batch1
```

---

### Batch 1: Auth & Account Security (8 Functions)
```bash
node scripts/predeploy_secret_check.js --batch=batch1
cd backend/functions
firebase deploy --only \
  functions:completeMobileOtpLogin,\
  functions:completeAmbulanceMobileOtpLogin,\
  functions:finalizePatientOtpVerification,\
  functions:lookupMobileRegistration,\
  functions:resetAmbulanceDriverPin,\
  functions:resetUserPasswordWithOtp,\
  functions:resyncAmbulanceAuthUid,\
  functions:verifyAmbulanceDriverLogin \
  --project medibond-45fad
```
**Post-Batch Verification:**
```bash
gcloud functions describe completeMobileOtpLogin --gen2 --region asia-south1 --project medibond-45fad --format="value(serviceConfig.environmentVariables.SUPABASE_URL)"
# Expected Output: https://staging-project-ref.supabase.co
```

---

### Batch 2: Abuse Prevention & Account Lifecycle (8 Functions)
```bash
node scripts/predeploy_secret_check.js --batch=batch2
cd backend/functions
firebase deploy --only \
  functions:assertLoginAllowed,\
  functions:recordFailedLogin,\
  functions:clearFailedLogins,\
  functions:assertAccountCreationAllowed,\
  functions:approveUserAccount,\
  functions:approvePatientAccount,\
  functions:deleteMyAccount,\
  functions:getAmbulanceInvite \
  --project medibond-45fad
```
**Post-Batch Verification:**
```bash
gcloud functions describe approveUserAccount --gen2 --region asia-south1 --project medibond-45fad --format="value(serviceConfig.environmentVariables.SUPABASE_URL)"
# Expected Output: https://staging-project-ref.supabase.co
```

---

### Batch 3: Clinical Validation & Advisory Rules (6 Functions)
```bash
node scripts/predeploy_secret_check.js --batch=batch3
cd backend/functions
firebase deploy --only \
  functions:getValidationRules,\
  functions:getValidationRulesHttp,\
  functions:validateField,\
  functions:validateFormFields,\
  functions:validateVitalAdvisory,\
  functions:consumeAiGenerationQuota \
  --project medibond-45fad
```
**Post-Batch Verification:**
```bash
gcloud functions describe validateField --gen2 --region asia-south1 --project medibond-45fad --format="value(serviceConfig.environmentVariables.SUPABASE_URL)"
# Expected Output: https://staging-project-ref.supabase.co
```

---

### Batch 4: Reviews, Ratings & Mail (7 Functions)
```bash
node scripts/predeploy_secret_check.js --batch=batch4
cd backend/functions
firebase deploy --only \
  functions:submitAmbulanceRating,\
  functions:aggregateDoctorRatingOnReviewCreate,\
  functions:aggregateDoctorRatingOnReviewWrite,\
  functions:syncReviewHelpfulCount,\
  functions:backfillPatientCareTeams,\
  functions:processMailQueueMsg91,\
  functions:sendMsg91EmailCallable \
  --project medibond-45fad
```
**Post-Batch Verification:**
```bash
gcloud functions describe aggregateDoctorRatingOnReviewCreate --gen2 --region asia-south1 --project medibond-45fad --format="value(serviceConfig.environmentVariables.SUPABASE_URL)"
# Expected Output: https://staging-project-ref.supabase.co
```

---

### Batch 5: Ambulance Dispatch & Referral Triggers (5 Functions)
```bash
node scripts/predeploy_secret_check.js --batch=batch5
cd backend/functions
firebase deploy --only \
  functions:notifyAmbulanceDriverOnNewRequest,\
  functions:markAmbulanceSiblingRequestsTakenOnAccept,\
  functions:markAmbulanceSiblingRequestsOnBroadcastCancelled,\
  functions:verifyAmbulanceDriverLoginHttp,\
  functions:notifyDoctorOnReferralCreated \
  --project medibond-45fad
```
**Post-Batch Verification:**
```bash
gcloud functions describe notifyAmbulanceDriverOnNewRequest --gen2 --region asia-south1 --project medibond-45fad --format="value(serviceConfig.environmentVariables.SUPABASE_URL)"
# Expected Output: https://staging-project-ref.supabase.co
```

---

### Batch 6: Clinical & Service FCM Push Notifications (10 Functions)
```bash
node scripts/predeploy_secret_check.js --batch=batch6
cd backend/functions
firebase deploy --only \
  functions:notifyDoctorOnAppointmentCreated,\
  functions:notifyPatientOnAppointmentStatusChanged,\
  functions:notifyDoctorOnPharmacyConnectionChanged,\
  functions:notifyPatientOnPharmacyDeliveryCreated,\
  functions:notifyDoctorOnPharmacyDeliveryUpdated,\
  functions:notifyPatientOnPharmacyDeliveryUpdated,\
  functions:notifyDoctorOnLabConnectionChanged,\
  functions:notifyPatientOnLabBookingUpdate,\
  functions:notifyPatientOnLabReportReady,\
  functions:notifyPatientOnLabOrderCreated \
  --project medibond-45fad
```
**Post-Batch Verification:**
```bash
gcloud functions describe notifyDoctorOnAppointmentCreated --gen2 --region asia-south1 --project medibond-45fad --format="value(serviceConfig.environmentVariables.SUPABASE_URL)"
# Expected Output: https://staging-project-ref.supabase.co
```

---

### Batch 7: AWS S3 Presigned URL Services (4 Functions)
> [!IMPORTANT]
> **Pre-requisite:** Before deploying Batch 7, ensure AWS S3 credentials (`AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`) are populated in `backend/functions/.env`. Running deploy without them will deploy empty strings and break S3 uploads.
```bash
node scripts/predeploy_secret_check.js --batch=batch7
cd backend/functions
firebase deploy --only \
  functions:getS3UploadUrl,\
  functions:getS3DownloadUrl,\
  functions:getS3DownloadUrls,\
  functions:deleteS3Object \
  --project medibond-45fad
```
**Post-Batch Verification:**
```bash
gcloud functions describe getS3UploadUrl --gen2 --region asia-south1 --project medibond-45fad --format="value(serviceConfig.environmentVariables.S3_BUCKET)"
# Expected Output: doctornect-672027759702-ap-south-1-an
```

---

### Batch 8: Razorpay Payments (2 Functions)
```bash
node scripts/predeploy_secret_check.js --batch=batch8
cd backend/functions
firebase deploy --only \
  functions:createRazorpayOrder,\
  functions:verifyRazorpayPayment \
  --project medibond-45fad
```
**Post-Batch Verification:**
```bash
gcloud functions describe createRazorpayOrder --gen2 --region asia-south1 --project medibond-45fad --format="value(serviceConfig.environmentVariables.RAZORPAY_KEY_ID)"
# Expected: Valid live key ID starting with rzp_live_
```

---

### Final Post-Deployment Verification
```bash
cd ../..
firebase functions:list --project medibond-45fad --json > baseline_functions.json
node backend/scripts/verify_production_build_config.js
# Expected: All Critical Pre-Flight Checks PASSED! 0 stale staging references remaining.
```

---

## Step 4: Configure Razorpay Webhooks (Optional for Launch)
- **Operator Action:** Razorpay Merchant Dashboard Config
- **Estimated Time:** 3 minutes
- **Reversibility:** Fully Reversible (Can update or delete endpoint in Razorpay)

> [!NOTE]
> Webhooks are optional for launch day. Client verification is handled synchronously via `verifyRazorpayPayment`.
> If enabling asynchronous webhook reconciliation:
> 1. Set `RAZORPAY_WEBHOOK_SECRET` in `backend/functions/.env`.
> 2. Log in to Razorpay Dashboard: `https://dashboard.razorpay.com/app/webhooks`.
> 3. Add endpoint URL and configure secret.

---

## Step 5: Build Production Mobile Packages (Launch Profile First)
- **Operator Action:** Run build scripts
- **Estimated Time:** 5-10 minutes
- **Reversibility:** Reversible (Can recompile without `-Launch` flag)

> [!CRITICAL]
> **Safe Cutover Requirement:** Mobile binaries MUST be compiled with the `-Launch` profile **before** Remote Config is enabled. The launch profile injects `SUPABASE_URL` and `SUPABASE_ANON_KEY` via `--dart-define`.
> If an operator flips Remote Config `use_supabase_db_doctor_patient=true` before users run a build with compiled credentials, the app's `SupabaseBootstrap.isReady` will be `false`, causing blank data and dropped writes.

### On Windows (PowerShell):
```powershell
cd frontend
# 1. Dry-run validation:
./scripts/release_build.ps1 -Launch -DryRun

# 2. Production release build:
./scripts/release_build.ps1 -Launch
```

### On macOS / Linux (Bash):
```bash
cd frontend
# 1. Dry-run validation:
./scripts/release_build.sh --launch --dry-run

# 2. Production release build:
./scripts/release_build.sh --launch
```

**Guard Verification:** The build script automatically aborts if `SUPABASE_SERVICE_ROLE_KEY` is present in the environment or if required client credentials are missing.

---

## Step 6: Execute Pre-Cutover Smoke Test
- **Operator Action:** Manual Verification on Test Device
- **Estimated Time:** 10 minutes
- **Reference:** Follow [docs/ops/SMOKE_TEST.md](file:///c:/Users/khije/Downloads/DoctorNect/doctor/docs/ops/SMOKE_TEST.md)

Install the `-Launch` APK on a test device and verify all 5 user modules:
1. Patient can view doctors and book an appointment.
2. Doctor can accept appointment and issue prescription.
3. Pharmacy receives prescription for fulfillment.
4. Lab receives diagnostic test booking.
5. Ambulance driver receives emergency dispatch broadcast.

---

## Step 7: Activate Firebase Remote Config Flag (Safe Final Cutover)
- **Operator Action:** Firebase Console or gcloud
- **Estimated Time:** 2 minutes
- **Reversibility:** Instant Reversibility (< 30 seconds to toggle back)

Only **after** Steps 1–6 have passed successfully, activate Supabase primary routing:

In Firebase Console (`https://console.firebase.google.com/project/medibond-45fad/config`):
1. Parameter: `use_supabase_db_doctor_patient`
   - **Production Value:** `true`
   - **Description:** Directs Doctor, Patient, Pharmacy, Lab, and Ambulance modules to primary Supabase Postgres.
2. Parameter: `use_s3_storage`
   - **Production Value:** `false`
   - **Description:** Keeps uploads on hardened Firebase Storage for launch day (default safe mode).
3. Click **Publish changes**.

---

## Step 8: Post-Review Step — Decommission Reviewer Bypass
- **Operator Action:** After Google Play Store approval
- **Estimated Time:** 5 minutes
- **Reversibility:** Reversible (Can be re-enabled for future update submissions)

To maintain review safety, fixed test numbers (`9999900001`–`9999900005`, OTP `000000`) are gated by `REVIEW_ACCESS_UNTIL` in `backend/functions/.env`:

1. Once the app is **Approved & Published** on the Google Play Store:
2. In Google Cloud / Firebase Functions environment (or `backend/functions/.env`):
   - Set `REVIEW_ACCESS_UNTIL` to an expired ISO timestamp (e.g., `2020-01-01T00:00:00.000Z`) or remove `REVIEW_TEST_NUMBERS` and `REVIEW_FIXED_OTP`.
3. Redeploy `completeMobileOtpLogin`:
   ```bash
   cd backend/functions
   firebase deploy --only functions:completeMobileOtpLogin --project medibond-45fad
   ```
4. Verify reviewer login is rejected:
   Attempting login with `9999900001` must now trigger standard SMS OTP via MSG91 rather than accepting `000000`.

---

## Emergency Rollback Procedures (Reversibility Matrix)

| Failure Scenario | Action Required | Command / Dashboard Path | Recovery Time |
|:---|:---|:---|:---:|
| **Supabase Postgres Downtime / RLS Block** | Flip Remote Config to Firestore | Set `use_supabase_db_doctor_patient=false` in Firebase Remote Config and publish. All clients switch back to Firestore within Remote Config cache interval. | < 1 minute |
| **Mobile App Regression under Supabase Mode** | Distribute Firestore fallback build | Build fallback APK: `./scripts/release_build.ps1` (without `-Launch`). Produces clean Firestore-only binary. | 5 minutes |
| **Cloud Function Deployment Failure** | Rollback Function Version | In GCP Cloud Functions console, rollback Cloud Run revision for failed function, or redeploy from `audit/full-verify` branch. | 2 minutes |
| **Reviewer Test Account Leakage** | Invalidate Fixed OTP Bypass | Clear `REVIEW_TEST_NUMBERS` in Cloud Function env or set `REVIEW_ACCESS_UNTIL` to past date. | < 2 minutes |
