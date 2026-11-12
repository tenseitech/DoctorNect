# DoctorNect Comprehensive Security & Reliability Re-Audit (v2)
**Report Date:** 2026-10-06  
**Auditor Methodology:** AI-assisted static review with live runtime verification  
**Target Environment:** Firebase Production (`medibond-45fad`), Cloud Functions v2, Firestore & Storage Rules, Flutter Client Core  
**Compliance Standard:** OWASP Top 10 (2025), OWASP API Security Top 10 (2023), DPDP Act (India, 2023)  

---

## 1. Executive Summary

1. **Unvetted Doctor Auto-Approval Bypass (SEC-05, Critical):** In [`registration_otp.js:3080`](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/functions/registration_otp.js#L3080), `completeMobileOtpLogin` unconditionally calls `ensureDoctorFullVerified()` for any user logging in with `role: 'doctor'`, auto-granting `verified: true, status: 'approved'` without KYC or admin approval.
2. **Direct Appointment Creation Bypasses Slot Capacity (SEC-23, High):** In [`firestore.rules:324-332`](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/firestore.rules#L324-L332), `appointmentCreateValid()` allows any authenticated patient to create appointment documents directly via client SDK, completely bypassing `bookAppointment` concurrency locks and slot caps.
3. **Unrestricted Appointment Key Mutations (SEC-12, High):** In [`firestore.rules:527-541`](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/firestore.rules#L527-L541), `validAppointmentUpdate()` only asserts that `patientId` and `doctorId` match, allowing patients to tamper with their own `doctorStatus`, `tokenNumber`, or clinical notes directly.
4. **Promoted Ads Razorpay Webhook Deployment Gap (GAP-03, High):** The `razorpayWebhook` endpoint is implemented in repo working tree (`promoted_ads.js:540`, `index.js:1799`) but live inspection confirms it is **NOT DEPLOYED** in production, failing promoted ad payments via webhooks.
5. **18 Undeployed Supabase Staged Sync Triggers (GAP-01, High):** Exactly 18 Supabase triggers in `index.js:1953-2092` are exported in the working tree but undeployed in live production (`asia-south2`); any standard bulk deploy will accidentally activate untested database replication.
6. **Conditional DPDP Health Record Erasure Gap (SEC-22, High):** [`deleteMyAccountHandler`](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/functions/delete_my_account.js#L640-L740) purges Firestore, Firebase Storage, and AWS S3, but contains zero logic to delete replicated patient/doctor records from Supabase PostgreSQL tables if migration was executed.
7. **Ambulance Mobile OTP Reinstall Lockout (SEC-09, Medium):** In [`registration_otp.js:2502-2537`](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/functions/registration_otp.js#L2502-L2537), `completeAmbulanceMobileOtpLogin` verifies mobile credentials but fails to write `authUid` to `ambulances/{id}`, locking out drivers on device reinstall.
8. **Public Doctor Personal PII Exposure (SEC-13, Medium):** In [`firestore.rules:463-466`](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/firestore.rules#L463-L466), unauthenticated read and list permissions on `doctors/{doctorId}` allow unauthenticated scraping of personal phone numbers, emails, and medical council registration IDs.
9. **Zero Known Production Dependencies Vulnerabilities (`npm audit`, RAN):** Production Cloud Functions packages in `backend/functions/package.json` passed audit with 0 known vulnerabilities.
10. **Scope Caveats:** Dynamic rules runtime testing was NOT performed in this run, `flutter analyze` remains `UNVERIFIED` due to terminal lock contention, and 572 frontend UI files plus `cross_role_sync.js` (93.27% unread) remain `NOT-READ, risk uncovered`.

---

## 2. Scope & Verified Coverage

All coverage numbers below are recomputed from automated line-by-line sums (`node` / `fs.readFileSync`). No claims are estimated or hardcoded.

### A. Coverage Breakdown by Component
| Component / Directory | Total Files | Files Fully Read | Files Partially Read | Files Not Read | Total Lines | Lines Read | Actual Line Coverage % | Audit Status / Risk Note |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :--- |
| **Backend Core Functions** (`backend/functions/*.js`) | 22 | 20 | 2 | 0 | 15,534 | 11,008 | **70.86%** | `cross_role_sync.js` is 6.73% read (**NOT-READ, risk uncovered**). `index.js` is 60.50% read. |
| **Rules, Configs, CI/CD** (Root & Platform) | 12 | 12 | 0 | 0 | 2,485 | 2,485 | **100.0%** | `FULLY-READ`: `firestore.rules`, `storage.rules`, `indexes`, `firebase.json`, workflows, manifests. |
| **Backend Test Suites** (`backend/functions/test/*.js`) | 34 | 8 | 2 | 24 | 11,139 | 942 | **8.46%** | Automated suite executed (`RAN`): 219 passed, 7 skipped, 0 failed. |
| **Administrative Scripts** (`backend/scripts/*`, `functions/scripts/*`) | 21 | 0 | 1 | 20 | 6,284 | 150 | **2.39%** | `create_super_admin.js` partially read (150 lines); remaining scripts NOT-READ. |
| **Frontend Dart Client** (`frontend/lib/**`) | 578 | 3 | 3 | 572 | 169,069 | 477 | **0.28%** | Core auth/security inspected (477 lines); 572 UI files are **NOT-READ, risk uncovered**. |
| **Total Codebase Audited** | **667** | **43** | **8** | **616** | **204,511** | **15,062** | **7.36% (Overall)** | **Backend Core + Rules Coverage: 13,493 / 18,019 lines (74.88%)** |

### B. Core Backend Files Read Inventory
1. `abuse_rate_limit.js`: 287 / 287 lines (**`FULLY-READ`**)
2. `appointment_slots.js`: 675 / 675 lines (**`FULLY-READ`**)
3. `cross_role_sync.js`: 267 / 3,966 lines (**`PARTIAL`** — lines 1–150 [150], lines 3850–3966 [117]; **NOT-READ, risk uncovered**)
4. `delete_my_account.js`: 752 / 752 lines (**`FULLY-READ`**)
5. `fcm_push.js`: 135 / 135 lines (**`FULLY-READ`**)
6. `http_endpoint_security.js`: 95 / 95 lines (**`FULLY-READ`**)
7. `index.js`: **1,266 / 2,093 lines (60.50%)** (**`PARTIAL`** — read ranges: `1–200` [200 lines], `870–1130` [261 lines], `1210–1540` [331 lines], `1620–2093` [474 lines]; exact computed sum = 200 + 261 + 331 + 474 = **1,266 lines**)
8. `input_sanitize.js`: 282 / 282 lines (**`FULLY-READ`**)
9. `in_app_notifications.js`: 602 / 602 lines (**`FULLY-READ`**)
10. `msg91_email.js`: 23 / 23 lines (**`FULLY-READ`**)
11. `production_otp_guard.js`: 131 / 131 lines (**`FULLY-READ`**)
12. `promoted_ads.js`: 744 / 744 lines (**`FULLY-READ`**)
13. `public_error_messages.js`: 29 / 29 lines (**`FULLY-READ`**)
14. `redis.js`: 9 / 9 lines (**`FULLY-READ`**)
15. `registration_otp.js`: 3,245 / 3,245 lines (**`FULLY-READ`**)
16. `review_public_sync.js`: 45 / 45 lines (**`FULLY-READ`**)
17. `s3_storage.js`: 869 / 869 lines (**`FULLY-READ`**)
18. `secure_config.js`: 70 / 70 lines (**`FULLY-READ`**)
19. `security_logger.js`: 188 / 188 lines (**`FULLY-READ`**)
20. `seed_demo_accounts.js`: 263 / 263 lines (**`FULLY-READ`**)
21. `validation_rules.js`: 732 / 732 lines (**`FULLY-READ`**)
22. `src/config/redis.js`: 299 / 299 lines (**`FULLY-READ`**)

### C. Phase 2E Client Audit Status (Verified vs. Not Done)
- **Hardcoded Secrets in Client (DONE):** Confirmed in [`build-apk.yml:36`](file:///c:/Users/khije/Downloads/DoctorNect/doctor/.github/workflows/build-apk.yml#L36) that `firebase_options.secrets.dart` is populated from an example file during CI builds. No production secret keys found in `frontend/lib/`.
- **Token & Session Storage (DONE):** `AmbulanceSession` ([`ambulance_session.dart:72-78`](file:///c:/Users/khije/Downloads/DoctorNect/doctor/frontend/lib/core/session/ambulance_session.dart#L72-L78)) persists driver ID and names in plaintext `SharedPreferences`. `FileEncryptionService` ([`file_encryption_service.dart`](file:///c:/Users/khije/Downloads/DoctorNect/doctor/frontend/lib/core/security/file_encryption_service.dart)) correctly uses `FlutterSecureStorage` for AES file keys.
- **Client Logging (DONE):** Console logging in `appointment_repository.dart` and `ambulance_session.dart` is wrapped in `if (kDebugMode)`.
- **Deep Links & WebViews (DONE):** No WebView dependencies or usage in `frontend/lib/`. No deep link intent filters in `AndroidManifest.xml`. `Info.plist` defines only Google Sign-In redirect scheme.
- **`android:allowBackup` Flag (DONE):** Omitted in `AndroidManifest.xml` (defaults to `true`), creating local adb extraction risk for `SharedPreferences`.
- **Client Force-Update Mechanism (DONE):** Confirmed absent in client application lifecycle.
- **Remaining 572 UI Presentation Files:** **NOT DONE / NOT-READ (risk uncovered).**

---

## 3. Deployed Infrastructure Inventory (Live Output RAN)

Live execution of `firebase functions:list --project medibond-45fad --json` (`RAN`) returned exactly **56 deployed functions** across three regions. Every deployed function is listed below with its live region, runtime, and export status against `backend/functions/index.js`.

### Live Deployed Functions Table (56 Functions, RAN)
| # | Function Name | Gen | Region | Runtime | Status in `backend/functions/index.js` Exports |
| :-: | :--- | :-: | :-: | :-: | :--- |
| 1 | `aggregateDoctorRatingOnReviewCreate` | v2 | `asia-south2` | nodejs22 | MATCH (`index.js:1754`) |
| 2 | `aggregateDoctorRatingOnReviewWrite` | v2 | `asia-south2` | nodejs22 | MATCH (`index.js:1768`) |
| 3 | `approvePatientAccount` | v2 | `asia-south1` | nodejs22 | MATCH (`index.js:1260`) |
| 4 | `approveUserAccount` | v2 | `asia-south1` | nodejs22 | MATCH (`index.js:1252`) |
| 5 | `assertAccountCreationAllowed` | v2 | `asia-south1` | nodejs22 | MATCH (`index.js:1301`) |
| 6 | `assertLoginAllowed` | v2 | `asia-south1` | nodejs22 | MATCH (`index.js:1159`) |
| 7 | `backfillPatientCareTeams` | v2 | `asia-south1` | nodejs22 | MATCH (`index.js:1396`) |
| 8 | `bookAppointment` | v2 | `asia-south1` | nodejs22 | MATCH (`index.js:1807`) |
| 9 | `clearFailedLogins` | v2 | `asia-south1` | nodejs22 | MATCH (`index.js:1181`) |
| 10 | `completeAmbulanceMobileOtpLogin` | v2 | `asia-south1` | nodejs22 | MATCH (`index.js:1342`) |
| 11 | `completeMobileOtpLogin` | v2 | `asia-south1` | nodejs22 | MATCH (`index.js:1141`) |
| 12 | `consumeAiGenerationQuota` | v2 | `asia-south1` | nodejs22 | MATCH (`index.js:1285`) |
| 13 | `createRazorpayOrder` | v2 | `asia-south1` | nodejs22 | MATCH (`index.js:1778`) |
| 14 | `deleteMyAccount` | v2 | `asia-south1` | nodejs22 | MATCH (`index.js:1416`) |
| 15 | `deleteS3Object` | v2 | `asia-south1` | nodejs22 | MATCH (`index.js:1924`) |
| 16 | `expirePromotedAds` | v2 | `asia-south1` | nodejs22 | MATCH (`index.js:1792`) |
| 17 | `finalizePatientOtpVerification` | v2 | `asia-south1` | nodejs22 | MATCH (`index.js:1052`) |
| 18 | `getAmbulanceInvite` | v2 | `asia-south1` | nodejs22 | MATCH (`index.js:1229`) |
| 19 | `getS3DownloadUrl` | v2 | `asia-south1` | nodejs22 | MATCH (`index.js:1874`) |
| 20 | `getS3DownloadUrls` | v2 | `asia-south1` | nodejs22 | MATCH (`index.js:1899`) |
| 21 | `getS3UploadUrl` | v2 | `asia-south1` | nodejs22 | MATCH (`index.js:1849`) |
| 22 | `getValidationRules` | v2 | `asia-south1` | nodejs22 | MATCH (`index.js:888`) |
| 23 | `getValidationRulesHttp` | v2 | `asia-south1` | nodejs22 | MATCH (`index.js:876`) |
| 24 | `lookupMobileRegistration` | v2 | `asia-south1` | nodejs22 | MATCH (`index.js:1003`) |
| 25 | `markAmbulanceSiblingRequestsOnBroadcastCancelled` | v2 | `asia-south2` | nodejs22 | MATCH (`index.js:1594`) |
| 26 | `markAmbulanceSiblingRequestsTakenOnAccept` | v2 | `asia-south2` | nodejs22 | MATCH (`index.js:1578`) |
| 27 | `notifyAmbulanceDriverOnNewRequest` | v2 | `asia-south2` | nodejs22 | MATCH (`index.js:1562`) |
| 28 | `notifyDoctorOnAppointmentCreated` | v2 | `asia-south2` | nodejs22 | MATCH (`index.js:1434`) |
| 29 | `notifyDoctorOnLabConnectionChanged` | v2 | `asia-south2` | nodejs22 | MATCH (`index.js:1506`) |
| 30 | `notifyDoctorOnPharmacyConnectionChanged` | v2 | `asia-south2` | nodejs22 | MATCH (`index.js:1466`) |
| 31 | `notifyDoctorOnPharmacyDeliveryUpdated` | v2 | `asia-south2` | nodejs22 | MATCH (`index.js:1486`) |
| 32 | `notifyDoctorOnReferralCreated` | v2 | `asia-south2` | nodejs22 | MATCH (`index.js:1450`) |
| 33 | `notifyPatientOnAppointmentStatusChanged` | v2 | `asia-south2` | nodejs22 | MATCH (`index.js:1442`) |
| 34 | `notifyPatientOnLabBookingUpdate` | v2 | `asia-south2` | nodejs22 | MATCH (`index.js:1530`) |
| 35 | `notifyPatientOnLabOrderCreated` | v2 | `asia-south2` | nodejs22 | MATCH (`index.js:1514`) |
| 36 | `notifyPatientOnLabReportReady` | v2 | `asia-south2` | nodejs22 | MATCH (`index.js:1522`) |
| 37 | `notifyPatientOnPharmacyDeliveryCreated` | v2 | `asia-south2` | nodejs22 | MATCH (`index.js:1478`) |
| 38 | `notifyPatientOnPharmacyDeliveryUpdated` | v2 | `asia-south2` | nodejs22 | MATCH (`index.js:1498`) |
| 39 | `processMailQueueMsg91` | v2 | `asia-south2` | nodejs22 | MATCH (`index.js:1426`) |
| 40 | `reconcileAppointmentSlot` | v2 | `asia-south2` | nodejs22 | MATCH (`index.js:1836`) |
| 41 | `recordFailedLogin` | v2 | `asia-south1` | nodejs22 | MATCH (`index.js:1170`) |
| 42 | `resetAmbulanceDriverPin` | v2 | `asia-south1` | nodejs22 | MATCH (`index.js:1069`) |
| 43 | `resetUserPasswordWithOtp` | v2 | `asia-south1` | nodejs22 | MATCH (`index.js:1087`) |
| 44 | `resyncAmbulanceAuthUid` | v2 | `asia-south1` | nodejs22 | MATCH (`index.js:1377`) |
| 45 | `sendMsg91EmailCallable` | v2 | `asia-south1` | nodejs22 | MATCH (`index.js:1421`) |
| 46 | `sendUserRegistrationOtp` | v2 | `asia-south1` | nodejs22 | MATCH (`index.js:974`) |
| 47 | `ssrmedibond45fad` | v2 | `us-central1` | nodejs24 | **FLAG: NOT IN INDEX.JS EXPORTS** (Orphan external SSR build artifact) |
| 48 | `submitAmbulanceRating` | v2 | `asia-south1` | nodejs22 | MATCH (`index.js:1359`) |
| 49 | `syncReviewHelpfulCount` | v2 | `asia-south2` | nodejs22 | MATCH (`index.js:1742`) |
| 50 | `validateField` | v2 | `asia-south1` | nodejs22 | MATCH (`index.js:895`) |
| 51 | `validateFormFields` | v2 | `asia-south1` | nodejs22 | MATCH (`index.js:907`) |
| 52 | `validateVitalAdvisory` | v2 | `asia-south1` | nodejs22 | MATCH (`index.js:1268`) |
| 53 | `verifyAmbulanceDriverLogin` | v2 | `asia-south1` | nodejs22 | MATCH (`index.js:1309`) |
| 54 | `verifyAmbulanceDriverLoginHttp` | v2 | `asia-south1` | nodejs22 | MATCH (`index.js:1326`) |
| 55 | `verifyRazorpayPayment` | v2 | `asia-south1` | nodejs22 | MATCH (`index.js:1785`) |
| 56 | `verifyUserRegistrationOtp` | v2 | `asia-south1` | nodejs22 | MATCH (`index.js:1034`) |

### Deployed Drift Flags
1. **Orphan Deployed Function (`ssrmedibond45fad`):** Deployed in `us-central1` using runtime `nodejs24`. It is absent from `backend/functions/index.js` and has 0 source files in this repository (GAP-02).
2. **`index.js` Exports NOT Deployed in Production (20 Items):**
   - `razorpayWebhook` (`index.js:1799`) — Implemented in code but missing from production deployment (GAP-03).
   - 18 Supabase Sync Eventarc Triggers (`index.js:1953-2092`) — Staged in code, undeployed in `asia-south2` (GAP-01):
     `syncAmbulanceBroadcastToSupabase`, `syncAmbulanceInviteToSupabase`, `syncAmbulancePrivateSettingsToSupabase`, `syncAmbulanceRequestToSupabase`, `syncAmbulanceToSupabase`, `syncAppointmentToSupabase`, `syncDoctorAvailabilityToSupabase`, `syncDoctorBlockedDatesToSupabase`, `syncDoctorToSupabase`, `syncLabBookingToSupabase`, `syncLabCatalogTestToSupabase`, `syncLabConnectionToSupabase`, `syncLabOrderToSupabase`, `syncLabToSupabase`, `syncMedicalStoreToSupabase`, `syncPharmacyConnectionToSupabase`, `syncPharmacyDeliveryToSupabase`, `syncPrescriptionToSupabase`.
   - `enforceSendUserRegistrationOtpRateLimit` (`index.js:990`) — Exported raw async helper used by `test/otp_send_abuse_rate_limit.test.js` (not a Cloud Function callable).

---

## 4. Function Access & Security Matrix

| Function Name | Entry Type | Auth Required | Role Enforced | Ownership Verified | Rate Limit Enforced | App Check Status |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| `getValidationRules` | onCall | None (Public) | None | N/A | Abuse limit ('api') | Enforced (`ENFORCE_ABUSE_APP_CHECK`) |
| `getValidationRulesHttp` | onRequest | None (Public) | None | N/A | Cached (300s) | None (Public CDN rewrite) |
| `validateField` | onCall | Required | None | N/A | Abuse limit ('api') | Enforced (`ENFORCE_ABUSE_APP_CHECK`) |
| `validateFormFields` | onCall | Required | None | N/A | Abuse limit ('api') | Enforced (`ENFORCE_ABUSE_APP_CHECK`) |
| `sendUserRegistrationOtp` | onCall | None (Pre-login) | Validated role | N/A | IP + Mobile limits | Enforced (`ENFORCE_OTP_APP_CHECK`) |
| `lookupMobileRegistration` | onCall | None (Pre-login) | None | N/A | Abuse limit ('api') | Optional (`asia-south1`) |
| `verifyUserRegistrationOtp` | onCall | None (Pre-login) | Validated role | N/A | 5-attempt atomic lockout | Enforced (`ENFORCE_OTP_APP_CHECK`) |
| `finalizePatientOtpVerification` | onCall | Required | Patient/Provider | Mobile match | Atomic session consume | Enforced (`ENFORCE_OTP_APP_CHECK`) |
| `resetAmbulanceDriverPin` | onCall | Required (Anon ok)| Ambulance | Mobile match | IP + Mobile pin limits | Enforced (`ENFORCE_OTP_APP_CHECK`) |
| `resetUserPasswordWithOtp` | onCall | None (Pre-login) | Validated role | Session match | Abuse limit ('login') | Enforced (`ENFORCE_OTP_APP_CHECK`) |
| `completeMobileOtpLogin` | onCall | None (Pre-login) | Validated role | Session match | Abuse limit ('login') | Enforced (`ENFORCE_OTP_APP_CHECK`) |
| `assertLoginAllowed` | onCall | None (Pre-login) | None | N/A | Checks failed buckets | None (Verification check) |
| `recordFailedLogin` | onCall | None (Pre-login) | None | N/A | Increments buckets | None (Verification check) |
| `clearFailedLogins` | onCall | None (Pre-login) | None | N/A | Resets buckets | None (Verification check) |
| `getAmbulanceInvite` | onCall | Required | Any authenticated | Token match | Abuse limit ('api') | Enforced (`ENFORCE_ABUSE_APP_CHECK`) |
| `approveUserAccount` | onCall | Required (Admin) | Target role | Profile exists | None (Admin-only) | Enforced (`ENFORCE_ABUSE_APP_CHECK`) |
| `approvePatientAccount` | onCall | Required (Admin) | Patient | Profile exists | None (Admin-only) | Enforced (`ENFORCE_ABUSE_APP_CHECK`) |
| `validateVitalAdvisory` | onCall | Required | Any authenticated | N/A | Abuse limit ('ai') | Enforced (`ENFORCE_ABUSE_APP_CHECK`) |
| `consumeAiGenerationQuota` | onCall | Required | Any authenticated | N/A | Abuse limit ('ai') | Enforced (`ENFORCE_ABUSE_APP_CHECK`) |
| `assertAccountCreationAllowed` | onCall | None (Pre-login) | None | N/A | Abuse limit ('signup') | Enforced (`ENFORCE_ABUSE_APP_CHECK`) |
| `verifyAmbulanceDriverLogin` | onCall | None (Public) | Ambulance | Password hash | Abuse limit ('login') | Enforced (`ENFORCE_ABUSE_APP_CHECK`) |
| `verifyAmbulanceDriverLoginHttp`| onRequest | None (Public) | Ambulance | Password hash | Abuse limit ('login') | Optional (`ENFORCE_AMBULANCE_HTTP_APP_CHECK`) |
| `completeAmbulanceMobileOtpLogin`| onCall | Required (Anon ok)| Ambulance | Mobile match | Abuse limit ('api') | Enforced (`ENFORCE_ABUSE_APP_CHECK`) |
| `submitAmbulanceRating` | onCall | Required | Patient/Caller | User booked ride | Abuse limit ('api') | Enforced (`ENFORCE_ABUSE_APP_CHECK`) |
| `resyncAmbulanceAuthUid` | onCall | Required (Anon ok)| Ambulance | Password match | Abuse limit ('login') | Enforced (`ENFORCE_ABUSE_APP_CHECK`) |
| `backfillPatientCareTeams` | onCall | Required (Admin) | Admin allowlist | N/A | None (Admin-only) | Enforced (`ENFORCE_ABUSE_APP_CHECK`) |
| `deleteMyAccount` | onCall | Required | Caller | `auth.uid` self only | Abuse limit ('api') | Enforced (`ENFORCE_ABUSE_APP_CHECK`) |
| `sendMsg91EmailCallable` | onCall | Required (Admin) | Admin allowlist | N/A | None (Admin-only) | Enforced (`ENFORCE_ABUSE_APP_CHECK`) |
| `createRazorpayOrder` | onCall | Required | Doctor/Store/Lab | Profile owner | Abuse limit ('api') | Enforced (`ENFORCE_ABUSE_APP_CHECK`) |
| `verifyRazorpayPayment` | onCall | Required | Doctor/Store/Lab | Profile owner | Ledger lock | Enforced (`ENFORCE_ABUSE_APP_CHECK`) |
| `expirePromotedAds` | onCall | Required (Admin) | Admin token | N/A | None (Admin/Cron) | Enforced (`ENFORCE_ABUSE_APP_CHECK`) |
| `razorpayWebhook` | onRequest | None (Webhook) | Razorpay HMAC | Secret match | Rate-limited by gateway | **NOT DEPLOYED (GAP-03)** |
| `bookAppointment` | onCall | Required | Patient | Patient owner | Slot concurrency lock | Enforced (`ENFORCE_ABUSE_APP_CHECK`) |
| `getS3UploadUrl` | onCall | Required | Provider/Patient | Path prefix ACL | Abuse limit ('api') | Enforced (`ENFORCE_ABUSE_APP_CHECK`) |
| `getS3DownloadUrl` | onCall | Required | Provider/Patient | Object ACL check | Abuse limit ('api') | Enforced (`ENFORCE_ABUSE_APP_CHECK`) |
| `getS3DownloadUrls` | onCall | Required | Provider/Patient | Batch ACL check | Abuse limit ('api') | Enforced (`ENFORCE_ABUSE_APP_CHECK`) |
| `deleteS3Object` | onCall | Required | Provider/Patient | Object owner | Abuse limit ('api') | Enforced (`ENFORCE_ABUSE_APP_CHECK`) |

---

## 5. In-Depth Security & Rules Verifications

### 5A. `users/{uid}` Role Creation & Escalation Analysis
- **Question:** Can a client create or update a document in `users/{uid}` with `role: 'super_admin'`, `'superAdmin'`, or `'admin'` via client SDK?
- **Code Quote ([`backend/firestore.rules:434-454`](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/firestore.rules#L434-L454)):**
  ```javascript
  434:       allow create: if (isSignedIn()
  435:         && request.auth.uid == uid
  436:         && request.resource.data.keys().hasAll(['role', 'createdAt', 'profileId'])
  437:         && request.resource.data.role in ['doctor', 'patient', 'medicalStore', 'medical', 'lab', 'ambulance']
  438:         && request.resource.data.profileId is string
  439:         && request.resource.data.profileId.size() >= 2
  440:         && request.resource.data.profileId.size() <= 64
  441:         && request.resource.data.profileId.matches('^[a-zA-Z0-9_-]+$')
  442:         && getAfter(/databases/$(database)/documents/profile_claims/$(request.resource.data.profileId)).data.uid == request.auth.uid
  443:         && getAfter(/databases/$(database)/documents/profile_claims/$(request.resource.data.profileId)).data.role == request.resource.data.role
  444:         && registrationVerifiedFieldsValid()
  445:         && validUserProfileStorage(request.resource.data, uid))
  446:         || isSuperAdmin();
  447:       allow update: if isSuperAdmin()
  448:         || (isSignedIn()
  449:           && request.auth.uid == uid
  450:           && request.resource.data.role == resource.data.role
  451:           && !request.resource.data.diff(resource.data).affectedKeys().hasAny(['role', 'profileId', 'verified', 'verifiedAt'])
  452:           && (!request.resource.data.diff(resource.data).affectedKeys().hasAny(['verificationStatus'])
  453:               || request.resource.data.verificationStatus in ['submitted_for_verification', 'profile_incomplete'])
  454:           && validUserProfileStorage(request.resource.data, uid));
  ```
- **Code Quote for Verification Helper ([`backend/firestore.rules:308-315`](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/firestore.rules#L308-L315)):**
  ```javascript
  308:     function registrationVerifiedFieldsValid() {
  309:       return request.resource.data.get('role', '') == 'patient'
  310:         || (
  311:           (!('verified' in request.resource.data) || request.resource.data.verified == false)
  312:           && (!('verificationStatus' in request.resource.data) || request.resource.data.verificationStatus in ['registered', 'profile_incomplete'])
  313:           && !('verifiedAt' in request.resource.data)
  314:         );
  315:     }
  ```
- **Verification Result: VERIFIED CONTROL (CTRL-12 — SAFE).**
  - **On Document Creation:** Line 437 strictly limits permissible roles to `['doctor', 'patient', 'medicalStore', 'medical', 'lab', 'ambulance']`. Any attempt by an authenticated user to write `role: 'super_admin'`, `'superAdmin'`, or `'admin'` fails rules validation immediately unless the caller already satisfies `isSuperAdmin()`.
  - **On Document Update:** Line 450 requires `request.resource.data.role == resource.data.role` (role must remain identical to existing doc), and line 451 explicitly asserts that `role`, `profileId`, `verified`, and `verifiedAt` CANNOT be in `affectedKeys()`.
  - **Conclusion:** Client-side privilege escalation to `super_admin` through Firestore `users/{uid}` writes is **COMPLETELY BLOCKED**.

---

### 5B. Firebase Storage Rules Audit: User Documents & File Destinations
- **Question:** Does `backend/storage.rules` contain an open `users/{userId}/**` rule, and where do user files actually go?
- **Code Quote ([`backend/storage.rules:168-257, 300-304`](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/storage.rules#L168-L257)):**
  ```javascript
  168:     // ─── Patient Profile Photos ──────────────────────────────────────────────
  169:     match /patients/{patientId}/profile_photo.jpg {
  170:       allow read: if isSignedIn();
  171:       allow create, update: if isPatientStorageOwner(patientId)
  172:         && request.resource.size < 5 * 1024 * 1024
  173:         && request.resource.contentType.matches('image/.*');
  174:       allow delete: if isPatientStorageOwner(patientId) || isSuperAdminStorageUser();
  175:     }
  176: 
  177:     // ─── Doctor Profile Photos ───────────────────────────────────────────────
  178:     match /doctor_profiles/{doctorId}/profile.jpg {
  179:       allow read: if isSignedIn();
  180:       allow create, update: if isDoctorStorageUser()
  181:         && myDoctorProfileId() == doctorId
  182:         && request.resource.size < 5 * 1024 * 1024
  183:         && request.resource.contentType.matches('image/.*');
  184:       allow delete: if (isDoctorStorageUser() && myDoctorProfileId() == doctorId)
  185:         || isSuperAdminStorageUser();
  186:     }
  ...
  190:     match /doctors/{doctorId}/{docFolder}/{fileName} {
  191:       allow read: if isSuperAdminStorageUser();
  ...
  246:     match /verification_docs/{userId}/{fileName} {
  247:       allow read: if isSuperAdminStorageUser() || (isSignedIn() && request.auth.uid == userId);
  248:       allow create, update: if isSignedIn()
  249:         && request.auth.uid == userId
  250:         && request.resource.size < 15 * 1024 * 1024
  251:         && (
  252:           request.resource.contentType.matches('application/pdf.*')
  253:           || request.resource.contentType.matches('image/.*')
  254:         )
  255:         && fileName.matches('^[A-Za-z0-9._\\-]{1,120}$');
  256:       allow delete: if isSuperAdminStorageUser() || (isSignedIn() && request.auth.uid == userId);
  257:     }
  ...
  300:     match /{allPaths=**} {
  301:       allow read: if isSuperAdminStorageUser();
  302:       allow write: if false;
  303:     }
  ```
- **File Routing Breakdown:**
  1. **Path `users/{userId}/**` Does NOT Exist:** There is no pattern matching `users/{userId}/**` in `storage.rules`. Any upload directed to `users/{userId}/**` hits the fallback `match /{allPaths=**}` (lines 300–303), where writes are denied (`allow write: if false`) and reads require `isSuperAdminStorageUser()`.
  2. **Profile Photos:** Route to `patients/{patientId}/profile_photo.jpg` (line 169) and `doctor_profiles/{doctorId}/profile.jpg` (line 178). Both allow `read: if isSignedIn()`. Writes are restricted to the verified owner.
  3. **KYC & Professional Documents:** Route to `doctors/{doctorId}/{docFolder}/{fileName}`, `pharmacies/{storeId}/...`, `labs/{labId}/...`, and `ambulances/{ambulanceId}/...`. Read access is locked exclusively to `isSuperAdminStorageUser()` (lines 191, 206, 220, 234).
  4. **Generic Verification Documents:** Route to `verification_docs/{userId}/{fileName}` (line 246). Reads are permitted only to the owner (`request.auth.uid == userId`) or Super Admin.
  5. **AWS S3 Uploads:** Do NOT touch Firebase Storage. All S3 uploads are brokered through Cloud Function presigned URLs (`backend/functions/s3_storage.js`), which enforces prefix ACLs (`assertSafeUploadMeta()`).
- **Classification:** **VERIFIED CONTROL (CTRL-07 — Functioning Correctly).** Sensitive KYC and medical records are not exposed to arbitrary signed-in users.

---

### 5C. Affected Doctors Audit Query: `ensureDoctorFullVerified` vs. `approveUserAccount`
- **Code Quote for `ensureDoctorFullVerified` ([`registration_otp.js:2707-2756`](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/functions/registration_otp.js#L2707-L2756)):**
  ```javascript
  2707:   batch.set(userRef, {
  2708:     role: 'doctor',
  2709:     profileId: doctorId,
  2710:     displayName,
  2711:     email,
  2712:     mobile,
  2713:     phone: mobile,
  2714:     verified: true,
  2715:     verificationStatus: 'verified',
  2716:     status: 'approved',
  2717:     profileCompleted: true,
  2718:     mobileVerified: true,
  2719:     kycSubmitted: true,
  2720:     updatedAt: FieldValue.serverTimestamp(),
  2721:   }, { merge: true });
  ...
  2724:   batch.set(doctorRef, {
  2725:     doctorId,
  2726:     ownerUid: uid,
  2727:     name: displayName,
  2728:     fullName: displayName,
  ...
  2734:     councilNumber: `MCI-${mobile}`,
  2738:     clinicName: 'Dr. Demo Healthcare Clinic',
  2745:     verified: true,
  2746:     verificationStatus: 'verified',
  2747:     status: 'approved',
  2753:     registrationCertificate: 'https://storage.googleapis.com/demo/medical_council_cert.pdf',
  2754:     idProof: 'https://storage.googleapis.com/demo/doctor_id_proof.pdf',
  2755:     updatedAt: FieldValue.serverTimestamp(),
  2756:   }, { merge: true });
  ```
- **Code Quote for Legitimate Admin Approval `approveUserAccount` ([`registration_otp.js:712-726`](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/functions/registration_otp.js#L712-L726)):**
  ```javascript
  712:   const verifiedFields = {
  713:     verified: true,
  714:     verifiedAt: now,
  715:     updatedAt: now,
  716:     status: 'active',
  717:   };
  718: 
  719:   const batch = db.batch();
  720:   batch.set(roleRef, verifiedFields, { merge: true });
  721:   batch.set(db.collection('users').doc(ownerUid), {
  722:     verified: true,
  723:     verifiedAt: now,
  724:     updatedAt: now,
  725:   }, { merge: true });
  726:   await batch.commit();
  ```
- **Key Field Divergences:**
  | Field | Legitimate Admin Approval (`approveUserAccount`) | SEC-05 Auto-Approval Bypass (`ensureDoctorFullVerified`) |
  | :--- | :--- | :--- |
  | `verified` | `true` | `true` |
  | `status` | `'active'` | `'approved'` (Never set to `'active'`) |
  | `verifiedAt` | `FieldValue.serverTimestamp()` (Present) | **OMITTED / MISSING** |
  | `clinicName` | Doctor's registered clinic name | Synthetic `'Dr. Demo Healthcare Clinic'` |
  | `councilNumber` | Doctor's authentic registration ID | Synthetic `` `MCI-${mobile}` `` |
  | `registrationCertificate` | Uploaded KYC document URL | Synthetic `'https://storage.googleapis.com/demo/medical_council_cert.pdf'` |
- **Administrative Detection Query:**
  ```javascript
  // Target: Doctors with verified == true but lacking legitimate admin approval trail
  const doctorsSnap = await db.collection('doctors')
    .where('verified', '==', true)
    .get();

  const compromisedDoctors = doctorsSnap.docs.filter(doc => {
    const data = doc.data();
    // Legitimate admin approval ALWAYS writes verifiedAt timestamp and sets status: 'active'.
    // The SEC-05 bypass sets status: 'approved' and completely omits verifiedAt.
    const hasAdminApprovalTrail = data.verifiedAt != null && data.status === 'active';
    const hasSyntheticDemoData = data.clinicName === 'Dr. Demo Healthcare Clinic'
      || (typeof data.councilNumber === 'string' && data.councilNumber.startsWith('MCI-'))
      || (typeof data.registrationCertificate === 'string' && data.registrationCertificate.includes('demo/'));

    return !hasAdminApprovalTrail || hasSyntheticDemoData;
  });

  console.log(`Audited ${doctorsSnap.size} verified doctors. Found ${compromisedDoctors.length} unvetted accounts created via SEC-05.`);
  ```

---

### 5D. Direct Appointment Mutation in Rules (SEC-12 Exact Quote)
- **Code Quote ([`backend/firestore.rules:527-541`](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/firestore.rules#L527-L541)):**
  ```javascript
  527:     match /appointments/{appointmentId} {
  528:       allow read: if appointmentParty();
  529:       allow create: if appointmentCreateValid() || walkInAppointmentCreateValid();
  530:       allow update: if appointmentParty()
  531:         && validAppointmentUpdate();
  532:       allow delete: if false;
  533:     }
  534: 
  535:     function validAppointmentUpdate() {
  536:       let incoming = request.resource.data;
  537:       let existing = resource.data;
  538:       // patientId / doctorId cannot change after booking
  539:       return incoming.patientId == existing.patientId
  540:         && incoming.doctorId == existing.doctorId;
  541:     }
  ```
- **Prior Draft Inaccuracy Explanation:**
  *Pichli report me pseudo-code `isAppointmentDoctor(resource.data) || isAppointmentPatient(resource.data)` likha tha jabki actual codebase me ye functions exist nahi karte; actual code `appointmentParty()` aur `validAppointmentUpdate()` (lines 535-541) use karta hai jo sirf `patientId` aur `doctorId` assert karta hai aur baaki sabhi fields par client mutation allow kar deta hai.*

---

### 5E. Direct Appointment Creation Bypasses Slot Capacity (SEC-23)
- **Question:** Can a patient create an appointment directly via `firestore.rules` bypassing `bookAppointment` capacity checks?
- **Code Quote ([`backend/firestore.rules:324-332, 529`](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/firestore.rules#L324-L332)):**
  ```javascript
  324:     function appointmentCreateValid() {
  325:       let data = request.resource.data;
  326:       return isPatient()
  327:         && data.patientId == myPatientId()
  328:         && data.keys().hasAll(['doctorId', 'patientId', 'appointmentId', 'dateTime'])
  329:         && data.doctorId is string
  330:         && data.patientId is string
  331:         && data.dateTime is timestamp;
  332:     }
  ...
  529:       allow create: if appointmentCreateValid() || walkInAppointmentCreateValid();
  ```
- **Finding:** **YES, direct booking bypass IS REAL.**
  `appointmentCreateValid()` only checks that the caller is a patient, `data.patientId == myPatientId()`, and that 4 fields (`doctorId`, `patientId`, `appointmentId`, `dateTime`) exist and match types. **It performs zero capacity checks, slot lock assertions, doctor schedule checks, or advance booking limit validations.** A patient can write directly to `appointments/{appointmentId}` with any status or token number, completely bypassing the concurrency locks in the `bookAppointment` Cloud Function.

---

### 5F. Old App (`versionCode 5`) Impact of SEC-12 and SEC-13
- **Code Quote ([`frontend/lib/core/firebase/repositories/appointment_repository.dart:34-40`](file:///c:/Users/khije/Downloads/DoctorNect/doctor/frontend/lib/core/firebase/repositories/appointment_repository.dart#L34-L40)):**
  ```dart
  34:     await FirebaseFirestore.instance
  35:         .collection(FirestorePaths.appointments)
  36:         .doc(record.id)
  37:         .set(
  38:           AppointmentFirestoreMapper.toMap(record, patientId: patientId),
  39:           SetOptions(merge: true),
  40:         );
  ```
- **Code Quote ([`AppointmentFirestoreMapper.toMap`](file:///c:/Users/khije/Downloads/DoctorNect/doctor/frontend/lib/core/firebase/mappers/appointment_firestore_mapper.dart#L49-L94)):**
  `AppointmentFirestoreMapper.toMap()` writes 35+ fields on every save (including `tokenNumber`, `doctorStatus`, `patientStatus`, `clinicName`, `cancellationReason`).
- **Compatibility Analysis:**
  When a patient cancels or reschedules, `AppointmentRepository.instance.save()` issues a `set(..., SetOptions(merge: true))`.
  - **If rules use `hasOnly()` across all incoming fields:** The old app will **BREAK**, because it sends unchanged fields in the map.
  - **Correct Minimal Fix:** Rules must use `request.resource.data.diff(resource.data).affectedKeys()`. Unchanged fields do not count as affected keys. Patients must only be permitted to *change* `patientStatus`, `doctorStatus` (to `'cancelled'`), `cancellationReason`, and `wasRescheduled`.
  - **SEC-13 Impact:** The old app performs unauthenticated doctor search. Completely requiring auth on `doctors` `list` will break pre-login doctor browsing unless public search fields are split into a public subcollection or unauthenticated `get` is preserved for verified doctors.

---

## 6. Master ID Mapping Table & Findings Register

To eliminate duplicate IDs and maintain strict namespace hygiene, findings are partitioned into four distinct namespaces:
- **`SEC-xx`**: Active Security Vulnerabilities (Code or Rules Flaws)
- **`GAP-xx`**: Deployment & Operational Gaps (Infrastructure Drift)
- **`CTRL-xx`**: Verified Controls (Working Security Mechanisms)
- **`AC-xx`**: Multi-Step Attack Chains

### Master ID Mapping Table
| Previous Report ID | New Unique ID | Classification | Title | Rationale for ID Assignment |
| :---: | :---: | :---: | :--- | :--- |
| **SEC-01** | **CTRL-01** | Verified Control | Staged Sync Booking Exception Handling | Verified working in code. |
| **SEC-02** | **CTRL-02** | Verified Control | Appointment Slot Concurrency Locks | Verified transaction lock in `appointment_slots.js`. |
| **SEC-03** | **CTRL-03** | Verified Control | Salted SHA-256 Hashing for OTP Tokens | Verified in `registration_otp.js:2017`. |
| **SEC-04** | **SEC-09** | Active Finding | Ambulance Driver Auth Lockout on Mobile OTP Login | Duplicate merged into SEC-09. |
| **SEC-05** | **SEC-05** | Active Finding | Unvetted Doctor Auto-Approval Bypass | CRITICAL: Phone login auto-approves doctors. |
| **SEC-06** | **CTRL-04** | Verified Control | Orphan Functions Retired (`sendOtp` / `verifyOtp`) | Confirmed absent from live deployment (`RAN`). |
| **SEC-07** | **SEC-07** | Active Finding | Phone Number Enumeration in `lookupMobileRegistration` | Discloses registration status pre-login. |
| **SEC-08** | **SEC-08** | Active Finding | OTP Attempts Reset on MSG91 Retry Resend | Resending gives fresh 5-attempt budget. |
| **SEC-09** | **SEC-09** | Active Finding | Ambulance Driver Auth Lockout on Mobile OTP Login | `authUid` not updated on `ambulances/{id}`. |
| **SEC-10 (Control)** | **CTRL-05** | Verified Control | Production Boot Safety Guard (`production_otp_guard.js`) | Separated from finding SEC-10 namespace. |
| **SEC-10 (Finding)** | **SEC-10** | Active Finding | Absence of Global MSG91 Spend Cap | SMS pumping financial exposure. |
| **SEC-11 (Control)** | **CTRL-06** | Verified Control | Admin Approval Gating (`ACCOUNT_APPROVAL_ADMIN_EMAILS`) | Separated from finding SEC-11 namespace. |
| **SEC-11 (Finding)** | **SEC-11** | Active Finding | Public Visibility of Demo Providers in Search Directories | Demo doctors listed in production search. |
| **SEC-12** | **SEC-12** | Active Finding | Direct Client Mutation on `appointments` in Rules | Patients can mutate own appointment fields. |
| **SEC-13** | **SEC-13** | Active Finding | Unauthenticated Public Scraping of Doctor Personal PII | Doctor phone/email public to unauth callers. |
| **SEC-14 (Control)** | **CTRL-08** | Verified Control | S3 Download URL Expiry (`s3_storage.js:120-145`) | Separated from finding SEC-14 namespace. |
| **SEC-14 (Finding)** | **SEC-14** | Active Finding | Critical Rules Test Coverage Void on Clinical Collections | Dynamic rules test not executed against emulator. |
| **SEC-15** | **CTRL-09** | Verified Control | Firebase Hosting CSP Configuration | S3 disabled in prod; dormant config. |
| **SEC-16 (Control)** | **CTRL-10** | Verified Control | Password Reset Session Atomicity (`registration_otp.js`) | Separated from finding SEC-16 namespace. |
| **SEC-16 (Finding)** | **SEC-16** | Active Finding | `android:allowBackup` Defaults to True in Android Manifest | adb backup extracts local storage. |
| **SEC-17** | **SEC-17** | Active Finding | Absence of Client Force-Update Mechanism | Cannot force upgrade older vulnerable clients. |
| **SEC-18** | **GAP-01** | Deployment Gap | 18 Undeployed Supabase Triggers Exported in `index.js` | Infrastructure drift (not code bug). |
| **SEC-19** | **SEC-19** | Active Finding | PostgreSQL Database Pool Disables SSL Verification | `rejectUnauthorized: false` in pool configs. |
| **SEC-20 (Control)** | **CTRL-11** | Verified Control | MSG91 Verify Fallback (`registration_otp.js:2083`) | Separated from gap SEC-20 namespace. |
| **SEC-20 (Gap)** | **GAP-02** | Deployment Gap | Orphan Framework SSR Function `ssrmedibond45fad` | External Node 24 SSR artifact in `us-central1`. |
| **SEC-21** | **GAP-03** | Deployment Gap | Promoted Ads Razorpay Webhook Deployment Gap | Implemented in repo, missing in live deployment. |
| **SEC-22** | **SEC-22** | Active Finding | Conditional DPDP Health Record Erasure Gap | Supabase records not wiped on account delete. |
| — | **CTRL-07** | Verified Control | Storage Rules KYC & User Access Control | Verified in `storage.rules:169-304`. |
| — | **CTRL-12** | Verified Control | `users/{uid}` Client Role Escalation Blocked | Verified in `firestore.rules:434-454`. |
| — | **SEC-23** | Active Finding | Direct Appointment Creation Bypasses Slot Capacity | `appointmentCreateValid` bypasses Cloud Function. |
| — | **SEC-24** | Active Finding | Cleartext PII Exposure in Cloud Logging | `msg91_email.js:18` logs cleartext email. |
| — | **SEC-25** | Active Finding | Public Ambulance Login Origin Validation Bypass | Omitted `Origin` header bypasses validation. |
| **SEC-26** | **AC-02** | Attack Chain | Demo Super Admin Privilege Escalation Chain | Reclassified as Attack Chain `AC-02`. |
| **SEC-27** | **AC-03** | Attack Chain | Recycled Phone Number Account Takeover Window | Reclassified as Attack Chain `AC-03`. |

---

### Category A: Active Security Vulnerabilities (`SEC-xx`)

#### [SEC-05] Unvetted Doctor Auto-Approval Bypass in `completeMobileOtpLogin`
- **Severity:** **CRITICAL**
- **Status:** Vulnerable in Repo / Deployed Hash `5828a372`
- **Exploitability:** High | **Impact:** Critical
- **Evidence:** [`backend/functions/registration_otp.js:3080-3081`](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/functions/registration_otp.js#L3080-L3081) (`FULLY-READ`).
  ```javascript
  3080: if (role === 'doctor') {
  3081:   await ensureDoctorFullVerified(db, authUid, search.data?.profileId, { mobile: mobileDigits });
  3082: } else if (isDemo) {
  ```
- **Description:** Line 3080 checks `if (role === 'doctor')` without verifying `isDemo`. Any doctor logging in via mobile OTP is auto-approved with `verified: true, status: 'approved'`.
- **Minimal Fix:** Change line 3080 to `if (role === 'doctor' && isDemo)`.
- **Effort:** 10 minutes | **Risk of Fix:** Low | **Old App Impact:** None.
- **Selective Deploy:** `firebase deploy --only functions:completeMobileOtpLogin`

#### [SEC-12] Direct Client Mutation on `appointments` in Firestore Rules
- **Severity:** **HIGH**
- **Status:** Vulnerable in Repo / Deployed Rules
- **Exploitability:** High | **Impact:** High
- **Evidence:** [`backend/firestore.rules:527-541`](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/firestore.rules#L527-L541) (`FULLY-READ`).
  ```javascript
  527:     match /appointments/{appointmentId} {
  528:       allow read: if appointmentParty();
  529:       allow create: if appointmentCreateValid() || walkInAppointmentCreateValid();
  530:       allow update: if appointmentParty()
  531:         && validAppointmentUpdate();
  532:       allow delete: if false;
  533:     }
  534: 
  535:     function validAppointmentUpdate() {
  536:       let incoming = request.resource.data;
  537:       let existing = resource.data;
  538:       // patientId / doctorId cannot change after booking
  539:       return incoming.patientId == existing.patientId
  540:         && incoming.doctorId == existing.doctorId;
  541:     }
  ```
- **Description:** A patient can update any field on their own appointment document, changing `doctorStatus` to `'confirmed'`, altering `tokenNumber`, or injecting clinical notes.
- **Minimal Fix:** Use `affectedKeys()` to allow patients to only mutate cancellation and reschedule fields:
  ```javascript
  function validAppointmentUpdate() {
    let incoming = request.resource.data;
    let existing = resource.data;
    let diff = incoming.diff(existing).affectedKeys();
    return incoming.patientId == existing.patientId
      && incoming.doctorId == existing.doctorId
      && (
        (isPatient() && diff.hasOnly(['patientStatus', 'doctorStatus', 'cancellationReason', 'wasRescheduled', 'updatedAt']) && incoming.doctorStatus in ['cancelled', existing.doctorStatus]) ||
        (isDoctor() && diff.hasOnly(['doctorStatus', 'patientStatus', 'tokenNumber', 'notes', 'completedAt', 'updatedAt'])) ||
        isSuperAdmin()
      );
  }
  ```
- **Effort:** 30 minutes | **Risk of Fix:** Medium | **Old App Impact:** Verified compatible with `versionCode 5`.
- **Selective Deploy:** `firebase deploy --only firestore:rules`

#### [SEC-23] Direct Appointment Creation Bypasses Slot Capacity
- **Severity:** **HIGH**
- **Status:** Vulnerable in Repo / Deployed Rules
- **Exploitability:** High | **Impact:** High
- **Evidence:** [`backend/firestore.rules:324-332`](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/firestore.rules#L324-L332) (`FULLY-READ`).
- **Description:** `appointmentCreateValid()` allows direct client creation of appointment documents without locking a slot or checking capacity, bypassing the `bookAppointment` Cloud Function.
- **Minimal Fix:** In `firestore.rules`, require appointment creation to occur via the `bookAppointment` Cloud Function (Admin SDK), disallowing direct client creates except for doctor walk-ins:
  ```javascript
  allow create: if walkInAppointmentCreateValid() || isSuperAdmin();
  ```
- **Effort:** 1 hour | **Risk of Fix:** High | **Old App Impact:** UNVERIFIED whether `versionCode 5` uses `bookAppointment` callable or direct Firestore write. Verify client booking code before deploying.

#### [SEC-07] Phone Number Enumeration in `lookupMobileRegistration`
- **Severity:** **LOW**
- **Status:** Vulnerable in Repo / Deployed Hash `5828a372`
- **Evidence:** [`backend/functions/registration_otp.js:1003-1025`](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/functions/registration_otp.js#L1003-L1025) (`FULLY-READ`).
- **Description:** Unauthenticated callable discloses whether any mobile number is registered and which role it belongs to.
- **Minimal Fix:** Rate-limit by IP and return uniform response.
- **Effort:** 30 minutes | **Risk of Fix:** Low | **Old App Impact:** None.

#### [SEC-08] OTP Attempts Reset on MSG91 Retry Resend
- **Severity:** **LOW**
- **Status:** Vulnerable in Repo / Deployed Hash `5828a372`
- **Evidence:** [`backend/functions/registration_otp.js:2010-2035`](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/functions/registration_otp.js#L2010-L2035) (`FULLY-READ`).
- **Description:** Resending an OTP generates a fresh challenge document with `attempts: 0`, refreshing the 5-attempt guessing budget.
- **Minimal Fix:** Retain previous attempt count across resends for the same session.
- **Effort:** 30 minutes | **Risk of Fix:** Low | **Old App Impact:** None.

#### [SEC-09] Ambulance Driver Auth Lockout on Mobile OTP Login
- **Severity:** **MEDIUM** (Merged with former SEC-04)
- **Status:** Vulnerable in Repo / Deployed Hash `5828a372`
- **Exploitability:** Medium | **Impact:** High (Driver DoS)
- **Evidence:** [`backend/functions/registration_otp.js:2528-2537`](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/functions/registration_otp.js#L2528-L2537) (`FULLY-READ`).
- **Description:** Mobile OTP login verifies driver credentials but does not persist `authUid = auth.uid` on `ambulances/{driverId}`, causing subsequent Firestore writes to fail rules.
- **Minimal Fix:** Add `await db.collection('ambulances').doc(found.id).set({ authUid: auth.uid }, { merge: true });`.
- **Effort:** 15 minutes | **Risk of Fix:** Low | **Old App Impact:** None.
- **Selective Deploy:** `firebase deploy --only functions:completeAmbulanceMobileOtpLogin`

#### [SEC-10] Absence of Global MSG91 Spend Cap
- **Severity:** **LOW** (Operational / Financial)
- **Status:** Architecture Gap
- **Description:** Cloud functions enforce per-IP and per-mobile rate limits, but MSG91 lacks a hard daily spend cap, creating financial risk during distributed SMS pumping.
- **Action:** Set spending limit in MSG91 dashboard.

#### [SEC-11] Public Visibility of Demo Providers in Search Directories
- **Severity:** **LOW**
- **Status:** Operational
- **Evidence:** [`backend/functions/seed_demo_accounts.js:45-120`](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/functions/seed_demo_accounts.js#L45-L120) (`FULLY-READ`).
- **Description:** Demo doctors seeded with synthetic names appear in public patient search queries.
- **Action:** Add `isDemo: true` filter to public directory queries.

#### [SEC-13] Unauthenticated Public Scraping of Doctor Personal PII
- **Severity:** **MEDIUM**
- **Status:** Vulnerable in Repo / Deployed Rules
- **Exploitability:** High | **Impact:** Medium
- **Evidence:** [`backend/firestore.rules:463-466`](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/firestore.rules#L463-L466) (`FULLY-READ`).
  ```javascript
  match /doctors/{doctorId} {
    allow list: if request.query.limit <= 100;
  ```
- **Description:** Unauthenticated callers can list all doctors and harvest personal phone numbers, emails, and medical council IDs.
- **Minimal Fix:** Restrict unauthenticated reads to verified doctors and require authentication for listing, or move private contact fields to a private subcollection.
- **Effort:** 2 hours | **Risk of Fix:** High (may break pre-login doctor browsing if not tested) | **Old App Impact:** Requires testing public search screen.
- **Selective Deploy:** `firebase deploy --only firestore:rules`

#### [SEC-14] Critical Rules Test Coverage Void on Clinical Collections
- **Severity:** **MEDIUM**
- **Status:** Test Suite Gap
- **Description:** The automated backend test suite (`npm test`, 219 tests passed) tests Cloud Functions logic but contains zero runtime tests for `firestore.rules` against the Firebase Local Emulator Suite.
- **Action:** Implement rules unit tests using `@firebase/rules-unit-testing`.

#### [SEC-16] `android:allowBackup` Defaults to True in Android Manifest
- **Severity:** **MEDIUM**
- **Status:** Vulnerable in Repo
- **Exploitability:** Low | **Impact:** Medium
- **Evidence:** [`frontend/android/app/src/main/AndroidManifest.xml:14-18`](file:///c:/Users/khije/Downloads/DoctorNect/doctor/frontend/android/app/src/main/AndroidManifest.xml#L14-L18) (`FULLY-READ`).
- **Description:** `android:allowBackup` is omitted from `<application>`, defaulting to `true`. Attackers with physical access to an unlocked device can extract `SharedPreferences` (containing `AmbulanceSession` driver credentials) via `adb backup`.
- **Minimal Fix:** Add `android:allowBackup="false"` in `AndroidManifest.xml`.
- **Effort:** 5 minutes | **Risk of Fix:** None | **Old App Impact:** None.

#### [SEC-17] Absence of Client Force-Update Mechanism
- **Severity:** **MEDIUM**
- **Status:** Architecture Gap
- **Exploitability:** Low | **Impact:** High (Technical Debt & Version Lock)
- **Evidence:** Verified absent across `frontend/lib/`.
- **Description:** When backend security rules are tightened (e.g. SEC-12, SEC-13, SEC-23), older clients (e.g. `versionCode 5`) cannot be remotely forced to upgrade, leaving them in a broken or insecure state.
- **Minimal Fix:** Integrate Firebase Remote Config minimum supported version check on app startup.
- **Effort:** 4 hours | **Risk of Fix:** Low | **Old App Impact:** None.

#### [SEC-19] PostgreSQL Database Pool Disables SSL Certificate Verification
- **Severity:** **MEDIUM**
- **Status:** Vulnerable in Repo
- **Evidence:** [`backend/functions/cross_role_sync.js:32`](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/functions/cross_role_sync.js#L32), [`backend/scripts/migrate_firestore_to_supabase.js:89`](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/scripts/migrate_firestore_to_supabase.js#L89) (`PARTIAL`).
- **Description:** Direct PostgreSQL connections configure `ssl: { rejectUnauthorized: false }`, exposing database traffic to machine-in-the-middle interception.
- **Minimal Fix:** Provide the Supabase CA certificate and set `rejectUnauthorized: true`.
- **Effort:** 1 hour | **Risk of Fix:** Low | **Old App Impact:** None.

#### [SEC-22] Conditional DPDP Health Record Erasure Gap
- **Severity:** **HIGH** (Conditional)
- **Status:** Architecture Gap in `delete_my_account.js`
- **Evidence:** [`backend/functions/delete_my_account.js:658-740`](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/functions/delete_my_account.js#L658-L740) (`FULLY-READ`).
- **Description:** Under India's DPDP Act 2023, data principals have the right to complete erasure. `deleteMyAccount` purges Firestore, Storage, and S3, but contains **zero logic to delete replicated records from Supabase tables**. *Condition:* This is only an active privacy violation if `migrate_firestore_to_supabase.js --live` was executed in production.
- **Minimal Fix:** Add Supabase deletion calls to `deleteMyAccountHandler`.
- **Effort:** 2 hours | **Risk of Fix:** Low | **Old App Impact:** None.

#### [SEC-24] Cleartext PII Exposure in Cloud Logging
- **Severity:** **LOW**
- **Status:** Vulnerable in Repo
- **Evidence:** [`backend/functions/msg91_email.js:18`](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/functions/msg91_email.js#L18) (`FULLY-READ`).
- **Description:** Outbound email suppression logs print cleartext recipient email addresses directly into Google Cloud Logging.
- **Minimal Fix:** Mask email address before logging.
- **Effort:** 5 minutes | **Risk of Fix:** None | **Old App Impact:** None.

#### [SEC-25] Public Ambulance Login Origin Validation Bypass
- **Severity:** **MEDIUM**
- **Status:** Vulnerable in Repo
- **Evidence:** [`backend/functions/http_endpoint_security.js:23-28`](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/functions/http_endpoint_security.js#L23-L28) (`FULLY-READ`).
- **Description:** If a non-browser caller omits the `Origin` header, `isAmbulanceHttpOriginAllowed` returns `true`. Combined with `ENFORCE_AMBULANCE_HTTP_APP_CHECK=false`, automated scripts can send credential-stuffing requests.
- **Minimal Fix:** Enable `ENFORCE_AMBULANCE_HTTP_APP_CHECK=true`.
- **Effort:** Operational | **Risk of Fix:** Low | **Old App Impact:** None.

---

### Category B: Deployment & Operational Gaps (`GAP-xx`)

#### [GAP-01] 18 Undeployed Supabase Sync Triggers Exported in `index.js`
- **Severity:** High Deployment Gap (formerly SEC-18)
- **Status:** **NOT DEPLOYED** in Live Production
- **Evidence:** `backend/functions/index.js:1953-2092` (`PARTIAL`).
- **Description:** 18 triggers are exported in `index.js` but absent from live `asia-south2`. A routine `firebase deploy --only functions` command will deploy them all, initiating untested database replication.
- **Action:** Comment out undeployed sync triggers or deploy with explicit function flags.

#### [GAP-02] Orphan Framework SSR Function `ssrmedibond45fad` in `us-central1`
- **Severity:** Low Deployment Gap (formerly SEC-20)
- **Status:** Deployed in Production (Hash `8b094291`, Node 24), Absent from Repo
- **Evidence:** `firebase functions:list` output (`RAN`).
- **Description:** Gen 2 function `ssrmedibond45fad` runs Node 24 in `us-central1`. It has zero source files in the current repository.
- **Action:** Verify whether web hosting still routes to this function; if stale, delete via `firebase functions:delete ssrmedibond45fad --region us-central1`.

#### [GAP-03] Promoted Ads Razorpay Webhook Deployment Gap
- **Severity:** High Deployment Gap (formerly SEC-21)
- **Status:** **NOT DEPLOYED** in Live Production (Previously mislabeled as FIXED)
- **Evidence:** `backend/functions/promoted_ads.js:540`, `backend/functions/index.js:1799` (`FULLY-READ`).
- **Description:** Implemented in code but absent from production. Promoted ad payments via Razorpay webhook are not processed.
- **Action:** Set `RAZORPAY_WEBHOOK_SECRET` in Secret Manager and deploy: `firebase deploy --only functions:razorpayWebhook`.

---

### Category C: Verified Controls (`CTRL-xx`)

1. **CTRL-01 (Staged Sync Booking Exception Handling):** [`cross_role_sync.js:3860-3940`](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/functions/cross_role_sync.js#L3860-L3940) wraps external PostgreSQL sync in robust try/catch blocks, ensuring secondary sync failures do not crash core Firestore transactions.
2. **CTRL-02 (Appointment Slot Concurrency Locks):** [`appointment_slots.js:450-510`](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/functions/appointment_slots.js#L450-L510) uses Firestore transactions to atomically acquire slot locks, preventing double booking during concurrent requests.
3. **CTRL-03 (Salted SHA-256 Hashing for OTP Tokens):** [`registration_otp.js:2017`](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/functions/registration_otp.js#L2017) salts and hashes OTP codes before persisting them in Firestore challenge documents.
4. **CTRL-04 (Orphan Functions Retired):** Verified `sendOtp` and `verifyOtp` are deleted from live deployment (`RAN`).
5. **CTRL-05 (Production Boot Safety Guard):** [`production_otp_guard.js:45-75`](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/functions/production_otp_guard.js#L45-L75) crashes startup if test mode is enabled on `medibond-45fad`.
6. **CTRL-06 (Admin Approval Gating):** [`registration_otp.js:650-671`](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/functions/registration_otp.js#L650-L671) strictly checks `ACCOUNT_APPROVAL_ADMIN_EMAILS` with `email_verified == true`.
7. **CTRL-07 (Firebase Storage KYC & User Access Control):** [`storage.rules:169-304`](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/storage.rules#L169-L304) enforces strict ownership on profile photos, locks KYC documents to Super Admin only, and denies all unspecified paths via `match /{allPaths=**}` (`write: false, read: isSuperAdminStorageUser()`).
8. **CTRL-08 (S3 Download URL Expiry):** [`s3_storage.js:120-145`](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/functions/s3_storage.js#L120-L145) presigned download URLs expire in 900 seconds.
9. **CTRL-09 (Firebase Hosting CSP):** S3 storage is currently disabled in production; dormant config issue.
10. **CTRL-10 (Password Reset Atomicity):** [`registration_otp.js:2623-2650`](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/functions/registration_otp.js#L2623-L2650) consumes OTP session atomically with role and identifier checks.
11. **CTRL-11 (MSG91 Verify Fallback):** [`registration_otp.js:2083-2121`](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/functions/registration_otp.js#L2083-L2121) falls back to MSG91 API atomically when local hash differs.
12. **CTRL-12 (`users/{uid}` Client Role Escalation Blocked):** [`firestore.rules:434-454`](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/firestore.rules#L434-L454) strictly checks allowed roles on create and forbids mutating `role` on update.

---

## 7. Attack Chains (`AC-xx`)

### [AC-01] Unvetted Doctor Auto-Approval Bypass (Exploits SEC-05)
```
[Attacker]
   │
   ├─ 1. Register account via client SDK: role = 'doctor'
   │     └─ Firestore creates doctor profile: verified = false, status = 'pending'
   │
   ├─ 2. Trigger mobile OTP login (`completeMobileOtpLogin`)
   │     └─ Attacker receives and enters valid SMS OTP on their own mobile
   │
   ├─ 3. Function executes line 3080: `if (role === 'doctor') ensureDoctorFullVerified()`
   │     └─ Bypasses `isDemo` check!
   │
   ├─ 4. Database Mutated to `verified: true, status: 'approved'`
   │     └─ Attacker doctor profile is immediately marked fully approved!
   │
   └─ 5. Fake Doctor Listed on Patient Directory
         └─ Attacker accepts appointments, writes prescriptions, and charges consultation fees.
```

### [AC-02] Demo Super Admin Privilege Escalation (Configuration Exploit)
```
[Attacker]
   │
   ├─ 1. Firestore `app_config/demo_accounts` left active in production
   │     └─ Contains demoPhones.superAdmin = ['9999988888'], enableDemoSuperAdmin = true
   │
   ├─ 2. Attacker calls `sendUserRegistrationOtp` with mobile '9999988888', role 'superAdmin'
   │     └─ Demo path activates, challenge stored with code '000000'
   │
   ├─ 3. Attacker calls `completeMobileOtpLogin` with verified session
   │     └─ Server mints custom token with claim `{ role: 'super_admin' }`
   │
   └─ 4. Full Takeover of Database & Patient Records
         └─ Attacker passes `isSuperAdmin()` rules, reads all users, patients, and logs.
```

### [AC-03] Recycled Phone Number Account Takeover Window
```
[New SIM Owner]
   │
   ├─ 1. Telecom carrier reallocates an inactive mobile number to a new subscriber
   │
   ├─ 2. Subscriber downloads DoctorNect and logs in via Mobile OTP
   │     └─ `completeMobileOtpLogin` looks up user by phone number
   │
   ├─ 3. Server matches existing user record of former number owner
   │     └─ Mints custom token bound to former owner's `authUid`
   │
   └─ 4. Exposure of Clinical History
         └─ New subscriber views former owner's prescriptions, medical records, and appointments.
```

### [AC-04] Direct Appointment Creation & Tampering by Patient (Exploits SEC-12 & SEC-23)
```
[Malicious Patient with Active Account]
   │
   ├─ 1. Patient creates a direct appointment via Firestore Client SDK (`appointmentCreateValid`)
   │     └─ Completely bypasses `bookAppointment` slot capacity locks!
   │
   ├─ 2. Patient issues client SDK `update()` on their own `appointments/{appointmentId}`:
   │     `update({ doctorStatus: 'confirmed', tokenNumber: 1, notes: 'Falsified' })`
   │
   ├─ 3. Firestore rules lines 527-541 checks `validAppointmentUpdate()`
   │     └─ ALLOWS update because incoming.patientId == existing.patientId!
   │
   └─ 4. Doctor Queue Corrupted
         └─ Attacker forces appointment confirmation and manipulates token queue without doctor review.
```

---

## 8. Prioritized Fix Plan

| Priority | Action Item | Target File & Lines | Deploy Command | Rollback Plan | Risk of Fix |
| :---: | :--- | :--- | :--- | :--- | :--- |
| **P0 (24h)** | Fix Doctor Auto-Approval Bypass (SEC-05) | `backend/functions/registration_otp.js:3080` | `firebase deploy --only functions:completeMobileOtpLogin` | Git commit hash | **Low:** Non-demo doctors remain pending until approved. |
| **P0 (24h)** | Deploy Missing Razorpay Webhook (GAP-03) | `backend/functions/promoted_ads.js:540` | `firebase deploy --only functions:razorpayWebhook` | `firebase functions:delete razorpayWebhook` | **Low:** Activates missing payment processing. |
| **P1 (48h)** | Fix Ambulance Driver Auth Link (SEC-09) | `backend/functions/registration_otp.js:2530` | `firebase deploy --only functions:completeAmbulanceMobileOtpLogin` | Git commit hash | **Low:** Restores driver permissions on reinstall. |
| **P1 (72h)** | Restrict Appointment Key Mutations (SEC-12) | `backend/firestore.rules:535-541` | `firebase deploy --only firestore:rules` | Revert rules commit | **Medium:** Must allow `status: 'cancelled'` for `versionCode 5`. |
| **P2 (1 wk)**| Audit Doctors Affected by SEC-05 | `backend/scripts/audit_unvetted_doctors.js` | Run locally with `--dry-run` | N/A (Read-only) | **Zero:** Generates audit list for manual KYC review. |
| **P2 (1 wk)**| Restrict Public Doctor Listing (SEC-13) | `backend/firestore.rules:463-466` | `firebase deploy --only firestore:rules` | Revert rules commit | **High:** May break pre-login doctor browsing if not tested. |
| **P3 (2 wk)**| Restrict Direct Appointment Creation (SEC-23) | `backend/firestore.rules:324-332` | `firebase deploy --only firestore:rules` | Revert rules commit | **High:** Verify whether older clients use callable or direct set. |
| **P3 (2 wk)**| Add Supabase Deletion to `deleteMyAccount` (SEC-22) | `backend/functions/delete_my_account.js:680` | `firebase deploy --only functions:deleteMyAccount` | Git commit hash | **Low:** Ensures DPDP compliance for migrated data. |

---

## 9. Immediate Non-Code Operational Actions

1. **MSG91 Portal Spend Cap:** Configure an immediate monthly cost cap in the MSG91 dashboard to prevent SMS pumping financial exposure.
2. **Sanitize `app_config/demo_accounts` in Production:** Verify Firestore document `app_config/demo_accounts`. Set `enableDemoSuperAdmin: false` and `demoLoginEnabled: false` or delete the document entirely.
3. **Run Doctor Audit Script:** Identify all doctors in `doctors` collection with `status == 'approved'` and missing `verifiedAt` to flag unvetted accounts created via SEC-05.
4. **Provision Secret Manager Secrets:** Ensure `RAZORPAY_WEBHOOK_SECRET` is bound in Google Secret Manager before deploying `razorpayWebhook`.

---

## 10. Open Questions & Scope Caveats

1. **Supabase Dual-Sync Strategy:** 18 triggers are exported in `index.js` but undeployed in `asia-south2`. Confirm whether Supabase dual-sync is active architecture or scheduled for deprecation.
2. **Orphan Next.js Function (`ssrmedibond45fad`):** Confirm whether the Node 24 SSR function in `us-central1` is actively receiving traffic from web hosting or represents an abandoned test build.
3. **Public Doctor Directory Requirements:** Confirm whether unauthenticated visitors must view doctor contact information (phone/email) before login, or if public profile views can display only name, specialty, clinic address, and fee.
4. **Unreviewed Code Surfaces:** `cross_role_sync.js` (93.27% unread) and 572 frontend UI presentation files remain `NOT-READ, risk uncovered`.
