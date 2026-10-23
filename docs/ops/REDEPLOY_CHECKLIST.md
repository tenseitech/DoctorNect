# DoctorNect Cloud Functions Redeployment Checklist (CFG-01)

## Executive Summary
During architecture audits, 50 legacy Cloud Functions in `baseline_functions.json` were found to have their `SUPABASE_URL` environment variable baked in pointing to the stale staging project reference (`irpkyedfmdsuvapfnrim.supabase.co`) instead of the active production PostgreSQL database (`rnltknemwnjrjxthtull.supabase.co`).

### Function Count & Discrepancy Resolution (Empirical Ground Truth)
Inspection of `baseline_functions.json` (56 total functions deployed in production project `medibond-45fad`):
- **50 Functions:** Contain `SUPABASE_URL=https://irpkyedfmdsuvapfnrim.supabase.co` (Stale staging ref needing redeployment).
- **5 Functions:** Contain `SUPABASE_URL=https://rnltknemwnjrjxthtull.supabase.co` (`bookAppointment`, `expirePromotedAds`, `sendUserRegistrationOtp`, `verifyUserRegistrationOtp`, `reconcileAppointmentSlot`).
- **1 Function:** Next.js Hosting SSR container (`ssrmedibond45fad`, no Supabase integration).
- **Resolution of 44 vs 50 Discrepancy:** The earlier figure of 44 was an undercount from preliminary regex filters that missed 6 multi-line configuration blocks. The exact, verified count of functions requiring redeployment is **50**.

---

## Pre-Deployment Verification Checklist
1. [ ] Confirm `backend/functions/.env` has `SUPABASE_URL=https://rnltknemwnjrjxthtull.supabase.co`.
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
   node -e "const fs = require('fs'); const data = JSON.parse(fs.readFileSync('baseline_functions.json', 'utf8')).result; const staging = data.filter(f => JSON.stringify(f).includes('irpkyedfmdsuvapfnrim')); console.log('Stale staging refs remaining:', staging.length);"
   ```
   *Expected output: `Stale staging refs remaining: 0`.*
3. [ ] Run pre-flight validator against the updated snapshot:
   ```bash
   node backend/scripts/verify_production_build_config.js
   ```
