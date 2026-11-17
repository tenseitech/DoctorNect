# DoctorNect Cloud Functions Redeployment Checklist (CFG-01)

## Executive Summary
During architecture audits, 50 legacy Cloud Functions in `baseline_functions.json` were found to have their `SUPABASE_URL` environment variable baked in pointing to the stale staging project reference (`legacy-staging-ref.supabase.co`) instead of the active production PostgreSQL database (`staging-project-ref.supabase.co`).

### Function Count & Discrepancy Resolution (Empirical Ground Truth)
Inspection of `baseline_functions.json` (56 total functions deployed in production project `medibond-45fad`):
- **50 Functions:** Contain `SUPABASE_URL=https://legacy-staging-ref.supabase.co` (Stale staging ref needing redeployment).
- **5 Functions:** Contain `SUPABASE_URL=https://staging-project-ref.supabase.co` (`bookAppointment`, `expirePromotedAds`, `sendUserRegistrationOtp`, `verifyUserRegistrationOtp`, `reconcileAppointmentSlot`).
- **1 Function:** Next.js Hosting SSR container (`ssrmedibond45fad`, no Supabase integration).
- **Resolution of 44 vs 50 Discrepancy:** The earlier figure of 44 was an undercount from preliminary regex filters that missed 6 multi-line configuration blocks. The exact, verified count of functions requiring redeployment is **50**.

### Secret Management Architecture: DEFERRED TO NEXT RELEASE
> [!WARNING]
> **Secret Manager Migration is DEFERRED to next release:**
> Attempting to bind secrets via `defineSecret()` while the same keys exist in `backend/functions/.env` causes Firebase CLI deployment to abort with a fatal namespace collision:
> `Error: A secret cannot have the same name as an environment variable: <KEY_NAME>`.
> In this release, Cloud Functions continue to load secrets from `backend/functions/.env` as verified in baseline production. Full migration to Google Secret Manager must be performed as a dedicated DevOps operation (populating Secret Manager versions, removing overlapping keys from `.env`, and switching local emulators to `.secret.local`).

---

## Pre-Deployment Verification Checklist
1. [ ] Confirm `backend/functions/.env` has `SUPABASE_URL=https://staging-project-ref.supabase.co`.
2. [ ] Confirm `backend/functions/.env` has `USE_SUPABASE_DB_DOCTOR_PATIENT=false` (safe default during cutover phase).
3. [ ] Verify environment parity locally:
   ```bash
   node scripts/check_env_parity.js
   node backend/scripts/verify_production_build_config.js --client-only
   ```
4. [ ] Run automated function unit and security test suites:
   ```bash
   cd backend/functions && npm test
   ```
5. [ ] **Verify Reviewer Account Configuration in Deploy `.env` and Live Environment:**
   Reviewer accounts (`9999900001`–`9999900005`, OTP `000000`) are required for Google Play app review. Server bypass relies **100% on environment variables** (no code defaults, no Firestore fallback).
   - Check deploy `.env`:
     ```bash
     node scripts/check_reviewer_config.js
     ```
     *Must pass:* `REVIEW_ACCESS_UNTIL` (valid future date), `REVIEW_TEST_NUMBERS` (5 comma-separated numbers), and `REVIEW_FIXED_OTP` configured.
   - Confirm live function environment before deploy:
     ```bash
     gcloud functions describe completeMobileOtpLogin --gen2 --region asia-south1 --project medibond-45fad --format="value(serviceConfig.environmentVariables.REVIEW_ACCESS_UNTIL)"
     ```
     *If missing:* Ensure `backend/functions/.env` includes `REVIEW_ACCESS_UNTIL`, `REVIEW_TEST_NUMBERS`, and `REVIEW_FIXED_OTP` so the deploy transmits them to Cloud Run. A deploy without these variables will lock Google Play reviewers out and cause app rejection.
6. [ ] Confirm no secret name collisions exist between `.env` and any `defineSecret()` bindings.

---

## Staged Redeployment Batches (DO NOT RUN WITHOUT USER APPROVAL)

### Batch 1: Auth & OTP Functions (4 Functions)
Redeploys customer authentication and onboarding services:
```bash
firebase deploy --only \
  functions:sendUserLoginOtp,\
  functions:verifyUserLoginOtp,\
  functions:requestDoctorRegistrationOtp,\
  functions:verifyDoctorRegistrationOtp \
  --project medibond-45fad
```

### Batch 2: Doctor & Clinical Management (10 Functions)
Redeploys doctor profiles, schedules, prescriptions, and catalog management:
```bash
firebase deploy --only \
  functions:createDoctorProfile,\
  functions:updateDoctorProfile,\
  functions:getDoctorProfile,\
  functions:getDoctorSchedule,\
  functions:updateDoctorSchedule,\
  functions:generatePrescriptionPdf,\
  functions:fetchCommunityCatalog,\
  functions:addCommunityCatalogItem,\
  functions:getDoctorEarnings,\
  functions:recordDoctorWithdrawal \
  --project medibond-45fad
```

### Batch 3: Patient, Health Records & Booking (10 Functions)
Redeploys patient records, digital health card, family members, and appointment actions:
```bash
firebase deploy --only \
  functions:createPatientProfile,\
  functions:updatePatientProfile,\
  functions:getPatientProfile,\
  functions:addFamilyMember,\
  functions:removeFamilyMember,\
  functions:uploadHealthRecordMetadata,\
  functions:getHealthRecordsList,\
  functions:deleteHealthRecord,\
  functions:cancelAppointment,\
  functions:rescheduleAppointment \
  --project medibond-45fad
```

### Batch 4: Pharmacy, Lab & Ambulance Services (12 Functions)
Redeploys secondary healthcare provider modules:
```bash
firebase deploy --only \
  functions:createPharmacyProfile,\
  functions:updatePharmacyProfile,\
  functions:createLabProfile,\
  functions:updateLabProfile,\
  functions:uploadLabReport,\
  functions:getLabReports,\
  functions:createAmbulanceProfile,\
  functions:updateAmbulanceLocation,\
  functions:requestEmergencyAmbulance,\
  functions:acceptAmbulanceRequest,\
  functions:completeAmbulanceTrip,\
  functions:cancelAmbulanceRequest \
  --project medibond-45fad
```

### Batch 5: Admin, Review, Notifications & Cleanup (14 Functions)
Redeploys admin callables, reviews, ratings, system maintenance, and account deletion:
```bash
firebase deploy --only \
  functions:approveUserAccount,\
  functions:rejectUserAccount,\
  functions:getAdminVerificationQueue,\
  functions:reviewPromotedAd,\
  functions:submitDoctorReview,\
  functions:getDoctorReviews,\
  functions:voteHelpfulReview,\
  functions:createSupportTicket,\
  functions:replySupportTicket,\
  functions:sendInAppNotification,\
  functions:markNotificationRead,\
  functions:deleteMyAccount,\
  functions:razorpayWebhook,\
  functions:dailySystemAudit \
  --project medibond-45fad
```

---

## Post-Deployment Validation
1. [ ] Export updated functions baseline:
   ```bash
   firebase functions:list --project medibond-45fad --json > baseline_functions.json
   ```
2. [ ] Verify zero occurrences of stale staging reference:
   ```bash
   node -e "const fs = require('fs'); const data = JSON.parse(fs.readFileSync('baseline_functions.json', 'utf8')).result; const staging = data.filter(f => JSON.stringify(f).includes('legacy-staging-ref')); console.log('Stale staging refs remaining:', staging.length);"
   ```
   *Expected output: `Stale staging refs remaining: 0`.*
3. [ ] Run pre-flight validator against the updated snapshot:
   ```bash
   node backend/scripts/verify_production_build_config.js
   ```
