# Stale Staging Ref Complete Redeployment Plan (CFG-01)

- **Document Version:** 1.0.0
- **Status:** PREPARATION ONLY — NO DEPLOY EXECUTED
- **Audit Branch:** `audit/full-verify`
- **Issue Reference:** CFG-01 (Deployment Configuration Drift)
- **Stale Staging Ref:** `legacy-staging-ref.supabase.co`
- **Target Production Ref:** `staging-project-ref.supabase.co`
- **GCP/Firebase Production Project:** `medibond-45fad`

---

## 1. Executive Summary

During full architecture and configuration audits, inspection of `baseline_functions.json` revealed that **50 deployed Cloud Functions** in production project `medibond-45fad` have their `SUPABASE_URL` environment variable baked in pointing to a stale staging database instance (`legacy-staging-ref.supabase.co`) rather than the production database (`staging-project-ref.supabase.co`).

### Census & Empirical Ground Truth
- **Total Functions in Production (`medibond-45fad`):** 56
- **Functions Pointing to Stale Staging Ref (`legacy-staging-ref`):** **50**
- **Functions Already Pointing to Production (`staging-project-ref`):** **5** (`bookAppointment`, `expirePromotedAds`, `sendUserRegistrationOtp`, `verifyUserRegistrationOtp`, `reconcileAppointmentSlot`)
- **Hosting / SSR Functions (No Supabase URL):** **1** (`ssrmedibond45fad`)

---

## 2. Risk Classification & Backward Compatibility Summary

All 50 functions have been audited for backward compatibility with currently installed mobile client versions (Android releases `1.0.2+1` through `1.0.2+7`).

| Risk Tier | Function Count | Description | Backward-Compatible with Old Clients? |
|:---|:---:|:---|:---:|
| **Tier 1: Low Risk (Async Firestore Triggers)** | 18 | Background document triggers in `asia-south2` (notifications, counters, mail queue). Clients never call these directly. | **YES** |
| **Tier 2: Low Risk (Validation & Schemas)** | 6 | Stateless schema validation callables and HTTP endpoints in `asia-south1`. | **YES** |
| **Tier 3: Medium Risk (Media & Storage)** | 5 | AWS S3 presigned URL generation and account deletion in `asia-south1`. | **YES** |
| **Tier 4: Medium Risk (Payments)** | 2 | Razorpay order creation and client payment verification callables in `asia-south1`. | **YES** |
| **Tier 5: High Risk (Authentication & OTP)** | 11 | Login, PIN reset, and session completion callables in `asia-south1`. | **YES** |
| **Tier 6: High Risk (Admin & Domain Profiles)** | 8 | Provider account approval, ambulance invites, and rating submissions in `asia-south1`. | **YES** |

> [!IMPORTANT]
> **Backward Compatibility Verdict:** Every single one of the 50 functions is **100% backward-compatible with older mobile clients**. Redeployment only updates backend environment variables (`SUPABASE_URL`) and Secret Manager bindings. No client-facing callable schemas, parameter contracts, or return signatures are broken.

---

## 3. Complete 50-Function Redeployment Registry

| # | Function Name | Region | Type / Trigger | Risk Tier | Backward-Compatible? | Compatibility Rationale |
|:---:|:---|:---:|:---|:---:|:---:|:---|
| 1 | `notifyDoctorOnAppointmentCreated` | `asia-south2` | Firestore Create (`appointments/{id}`) | Tier 1 (Low) | **YES** | Server-side push notification trigger; no client RPC interface. |
| 2 | `notifyDoctorOnReferralCreated` | `asia-south2` | Firestore Create (`referrals/{id}`) | Tier 1 (Low) | **YES** | Server-side push notification trigger. |
| 3 | `notifyPatientOnAppointmentStatusChanged` | `asia-south2` | Firestore Update (`appointments/{id}`) | Tier 1 (Low) | **YES** | Server-side push notification trigger. |
| 4 | `notifyPatientOnLabBookingUpdate` | `asia-south2` | Firestore Update (`lab_bookings/{id}`) | Tier 1 (Low) | **YES** | Server-side push notification trigger. |
| 5 | `notifyPatientOnLabReportReady` | `asia-south2` | Firestore Update (`lab_bookings/{id}`) | Tier 1 (Low) | **YES** | Server-side push notification trigger. |
| 6 | `notifyPatientOnLabOrderCreated` | `asia-south2` | Firestore Create (`lab_orders/{id}`) | Tier 1 (Low) | **YES** | Server-side push notification trigger. |
| 7 | `notifyDoctorOnLabConnectionChanged` | `asia-south2` | Firestore Write (`doctor_lab_connections/{id}`) | Tier 1 (Low) | **YES** | Server-side push notification trigger. |
| 8 | `notifyDoctorOnPharmacyConnectionChanged` | `asia-south2` | Firestore Write (`doctor_pharmacy_connections/{id}`) | Tier 1 (Low) | **YES** | Server-side push notification trigger. |
| 9 | `notifyPatientOnPharmacyDeliveryCreated` | `asia-south2` | Firestore Create (`pharmacy_deliveries/{id}`) | Tier 1 (Low) | **YES** | Server-side push notification trigger. |
| 10 | `notifyDoctorOnPharmacyDeliveryUpdated` | `asia-south2` | Firestore Update (`pharmacy_deliveries/{id}`) | Tier 1 (Low) | **YES** | Server-side push notification trigger. |
| 11 | `notifyPatientOnPharmacyDeliveryUpdated` | `asia-south2` | Firestore Update (`pharmacy_deliveries/{id}`) | Tier 1 (Low) | **YES** | Server-side push notification trigger. |
| 12 | `notifyAmbulanceDriverOnNewRequest` | `asia-south2` | Firestore Create (`ambulance_requests/{id}`) | Tier 1 (Low) | **YES** | Server-side push notification trigger. |
| 13 | `markAmbulanceSiblingRequestsTakenOnAccept` | `asia-south2` | Firestore Update (`ambulance_requests/{id}`) | Tier 1 (Low) | **YES** | Background state synchronization. |
| 14 | `markAmbulanceSiblingRequestsOnBroadcastCancelled` | `asia-south2` | Firestore Update (`ambulance_broadcasts/{id}`) | Tier 1 (Low) | **YES** | Background state synchronization. |
| 15 | `aggregateDoctorRatingOnReviewCreate` | `asia-south2` | Firestore Create (`doctor_reviews/{id}`) | Tier 1 (Low) | **YES** | Background rating aggregator. |
| 16 | `aggregateDoctorRatingOnReviewWrite` | `asia-south2` | Firestore Write (`doctor_reviews/{id}`) | Tier 1 (Low) | **YES** | Background rating aggregator. |
| 17 | `syncReviewHelpfulCount` | `asia-south2` | Firestore Write (`review_reactions/{id}`) | Tier 1 (Low) | **YES** | Background reaction counter. |
| 18 | `processMailQueueMsg91` | `asia-south2` | Firestore Create (`mail/{id}`) | Tier 1 (Low) | **YES** | Server-side email dispatcher via MSG91 API v5. |
| 19 | `getValidationRules` | `asia-south1` | Callable v2 | Tier 2 (Low) | **YES** | Returns declarative regex and length constraints. |
| 20 | `getValidationRulesHttp` | `asia-south1` | HTTP (GET) | Tier 2 (Low) | **YES** | Public hosting rewrite proxy for web validation rules. |
| 21 | `validateField` | `asia-south1` | Callable v2 | Tier 2 (Low) | **YES** | Stateless single-field validator. |
| 22 | `validateFormFields` | `asia-south1` | Callable v2 | Tier 2 (Low) | **YES** | Stateless multi-field form validator. |
| 23 | `validateVitalAdvisory` | `asia-south1` | Callable v2 | Tier 2 (Low) | **YES** | Stateless clinical triage rule advisor. |
| 24 | `consumeAiGenerationQuota` | `asia-south1` | Callable v2 | Tier 2 (Low) | **YES** | User quota rate-limiter check. |
| 25 | `getS3UploadUrl` | `asia-south1` | Callable v2 | Tier 3 (Med) | **YES** | Signs S3 PUT URLs with Content-Type & length assertions. |
| 26 | `getS3DownloadUrl` | `asia-south1` | Callable v2 | Tier 3 (Med) | **YES** | Signs S3 GET URLs with access verification. |
| 27 | `getS3DownloadUrls` | `asia-south1` | Callable v2 | Tier 3 (Med) | **YES** | Batch public-media download URL presigning (max 20). |
| 28 | `deleteS3Object` | `asia-south1` | Callable v2 | Tier 3 (Med) | **YES** | S3 object deletion with ownership validation. |
| 29 | `deleteMyAccount` | `asia-south1` | Callable v2 | Tier 3 (Med) | **YES** | Caller account purge across Auth, Firestore, and Supabase. |
| 30 | `createRazorpayOrder` | `asia-south1` | Callable v2 | Tier 4 (Med) | **YES** | Creates Razorpay order ID for ad campaigns. |
| 31 | `verifyRazorpayPayment` | `asia-south1` | Callable v2 | Tier 4 (Med) | **YES** | Verifies payment signature and records ledger. |
| 32 | `lookupMobileRegistration` | `asia-south1` | Callable v2 | Tier 5 (High) | **YES** | Phone number registration intent check (no role leak). |
| 33 | `completeMobileOtpLogin` | `asia-south1` | Callable v2 | Tier 5 (High) | **YES** | Exchanges verified OTP session for Firebase Custom Token. |
| 34 | `finalizePatientOtpVerification` | `asia-south1` | Callable v2 | Tier 5 (High) | **YES** | Links verified phone number to signed-in patient account. |
| 35 | `resetUserPasswordWithOtp` | `asia-south1` | Callable v2 | Tier 5 (High) | **YES** | Verifies password-reset OTP and updates Firebase Auth. |
| 36 | `resetAmbulanceDriverPin` | `asia-south1` | Callable v2 | Tier 5 (High) | **YES** | Verifies OTP and updates driver PIN hash in Firestore. |
| 37 | `completeAmbulanceMobileOtpLogin` | `asia-south1` | Callable v2 | Tier 5 (High) | **YES** | Exchanges ambulance OTP for driver session token. |
| 38 | `verifyAmbulanceDriverLogin` | `asia-south1` | Callable v2 | Tier 5 (High) | **YES** | Verifies username and salted PBKDF2 PIN hash. |
| 39 | `verifyAmbulanceDriverLoginHttp` | `asia-south1` | HTTP (POST) | Tier 5 (High) | **YES** | HTTP fallback for low-bandwidth mobile drivers. |
| 40 | `assertLoginAllowed` | `asia-south1` | Callable v2 | Tier 5 (High) | **YES** | Enforces IP/identifier rate-limiting lockout windows. |
| 41 | `recordFailedLogin` | `asia-south1` | Callable v2 | Tier 5 (High) | **YES** | Increments login failure counter in Firestore/Redis. |
| 42 | `clearFailedLogins` | `asia-south1` | Callable v2 | Tier 5 (High) | **YES** | Resets failed attempt counter upon successful login. |
| 43 | `approveUserAccount` | `asia-south1` | Callable v2 | Tier 6 (High) | **YES** | Admin KYC approval for doctor, lab, pharmacy, ambulance. |
| 44 | `approvePatientAccount` | `asia-south1` | Callable v2 | Tier 6 (High) | **YES** | Admin approval for patient accounts. |
| 45 | `assertAccountCreationAllowed` | `asia-south1` | Callable v2 | Tier 6 (High) | **YES** | Pre-registration IP abuse gate. |
| 46 | `backfillPatientCareTeams` | `asia-south1` | Callable v2 | Tier 6 (High) | **YES** | Super-admin backfill utility for care team mapping. |
| 47 | `getAmbulanceInvite` | `asia-south1` | Callable v2 | Tier 6 (High) | **YES** | Validates ambulance fleet driver invitation tokens. |
| 48 | `resyncAmbulanceAuthUid` | `asia-south1` | Callable v2 | Tier 6 (High) | **YES** | Admin maintenance repair for ambulance auth UID mapping. |
| 49 | `sendMsg91EmailCallable` | `asia-south1` | Callable v2 | Tier 6 (High) | **YES** | Admin transactional email dispatch endpoint. |
| 50 | `submitAmbulanceRating` | `asia-south1` | Callable v2 | Tier 6 (High) | **YES** | Patient rating submission for completed ambulance trips. |

---

## 4. Staged Execution Plan (Ordered by Dependency & Blast Radius)

When management approves deployment, execute in the following exact order. Between batches, check Cloud Monitoring error rates:

### Batch 1: Async Background Triggers (18 Functions)
*Zero client interaction; lowest blast radius.*
```bash
firebase deploy --only \
  functions:notifyDoctorOnAppointmentCreated,\
  functions:notifyDoctorOnReferralCreated,\
  functions:notifyPatientOnAppointmentStatusChanged,\
  functions:notifyPatientOnLabBookingUpdate,\
  functions:notifyPatientOnLabReportReady,\
  functions:notifyPatientOnLabOrderCreated,\
  functions:notifyDoctorOnLabConnectionChanged,\
  functions:notifyDoctorOnPharmacyConnectionChanged,\
  functions:notifyPatientOnPharmacyDeliveryCreated,\
  functions:notifyDoctorOnPharmacyDeliveryUpdated,\
  functions:notifyPatientOnPharmacyDeliveryUpdated,\
  functions:notifyAmbulanceDriverOnNewRequest,\
  functions:markAmbulanceSiblingRequestsTakenOnAccept,\
  functions:markAmbulanceSiblingRequestsOnBroadcastCancelled,\
  functions:aggregateDoctorRatingOnReviewCreate,\
  functions:aggregateDoctorRatingOnReviewWrite,\
  functions:syncReviewHelpfulCount,\
  functions:processMailQueueMsg91 \
  --project medibond-45fad
```

### Batch 2: Validation & Schema Callables (6 Functions)
```bash
firebase deploy --only \
  functions:getValidationRules,\
  functions:getValidationRulesHttp,\
  functions:validateField,\
  functions:validateFormFields,\
  functions:validateVitalAdvisory,\
  functions:consumeAiGenerationQuota \
  --project medibond-45fad
```

### Batch 3: Object Storage & Account Deletion (5 Functions)
```bash
firebase deploy --only \
  functions:getS3UploadUrl,\
  functions:getS3DownloadUrl,\
  functions:getS3DownloadUrls,\
  functions:deleteS3Object,\
  functions:deleteMyAccount \
  --project medibond-45fad
```

### Batch 4: Razorpay Payment Processing (2 Functions)
```bash
firebase deploy --only \
  functions:createRazorpayOrder,\
  functions:verifyRazorpayPayment \
  --project medibond-45fad
```

### Batch 5: Authentication & Session Gateways (11 Functions)
```bash
firebase deploy --only \
  functions:lookupMobileRegistration,\
  functions:completeMobileOtpLogin,\
  functions:finalizePatientOtpVerification,\
  functions:resetUserPasswordWithOtp,\
  functions:resetAmbulanceDriverPin,\
  functions:completeAmbulanceMobileOtpLogin,\
  functions:verifyAmbulanceDriverLogin,\
  functions:verifyAmbulanceDriverLoginHttp,\
  functions:assertLoginAllowed,\
  functions:recordFailedLogin,\
  functions:clearFailedLogins \
  --project medibond-45fad
```

### Batch 6: Administration & Operations (8 Functions)
```bash
firebase deploy --only \
  functions:approveUserAccount,\
  functions:approvePatientAccount,\
  functions:assertAccountCreationAllowed,\
  functions:backfillPatientCareTeams,\
  functions:getAmbulanceInvite,\
  functions:resyncAmbulanceAuthUid,\
  functions:sendMsg91EmailCallable,\
  functions:submitAmbulanceRating \
  --project medibond-45fad
```

---

## 5. Pre-Flight & Post-Flight Verification Gates

Before executing any batch:
1. `node scripts/check_env_parity.js` -> Must report 0 undocumented core variables.
2. `node scripts/check_reviewer_config.js` -> Confirms reviewer window is active and in future.
3. `node backend/scripts/verify_production_build_config.js --client-only` -> Confirms production URLs.

After executing any batch:
1. Check Cloud Functions logs in GCP Console (`gcloud logging read "resource.type=cloud_run_revision AND severity>=ERROR" --limit=20 --project medibond-45fad`).
2. Run mobile app regression tests on physical device or simulator.
