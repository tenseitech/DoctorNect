# DOCTORNECT SECURITY AND RELIABILITY AUDIT
**Date:** 2026-10-06  
**Auditor:** Antigravity AI (Advanced Agentic Pair Programmer)  
**Firebase Project:** `medibond-45fad`  
**Repository State Baseline:** Commit `4885d33` + Local Working Tree  

---

## 1. Executive Summary

This comprehensive security and reliability re-audit of DoctorNect evaluated the Flutter client (`frontend/`), Cloud Functions (`backend/functions`), Firestore security rules (`backend/firestore.rules`), Supabase bridge (`backend/functions/cross_role_sync.js`), and production deployment state (`medibond-45fad`). 

### Top 5 Critical & High Risks:
1. **Unvetted Doctor Auto-Approval ([SEC-05](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/functions/registration_otp.js#L3080)):** Any unverified user registering as a doctor who logs in via `completeMobileOtpLogin` is unconditionally upgraded to `verified: true, status: 'approved'`, completely bypassing SuperAdmin KYC approval and gaining full medical privileges.
2. **Direct Appointment Field Tampering in Firestore Rules ([SEC-12](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/firestore.rules#L530-L541)):** `appointments/{id}` update rules lack field blacklists, allowing patients or doctors to directly mutate appointment `status`, reschedule `dateTime` without slot capacity checks, or manipulate financial metadata.
3. **Public Doctor Personal PII Scraping ([SEC-13](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/firestore.rules#L463-L466)):** Firestore rules permit unauthenticated `get` and `list` queries on `doctors`, exposing personal mobile numbers, emails, council registration numbers, and clinic addresses to unauthenticated scrapers.
4. **Hosting CSP Blocks S3 Storage ([SEC-15](file:///c:/Users/khije/Downloads/DoctorNect/doctor/firebase.json#L163)):** Web hosting Content Security Policy (`firebase.json`) omits AWS S3 origins (`https://*.amazonaws.com`) from `img-src`. Activating `use_s3_storage` will instantly break doctor photos, banners, and records on web.
5. **Bulk Deploy Trap & Undeployed Supabase Triggers ([SEC-18](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/functions/index.js#L55-L72)):** 18 Supabase sync triggers are exported in `index.js` but undeployed. A standard `firebase deploy --only functions` will deploy all 18, connect with `rejectUnauthorized: false`, and potentially fail every Firestore write if Supabase credentials or schemas are unaligned.

---

## 2. Scope and Methodology

### Scope
- **Client:** Flutter application (`frontend/lib/`, `frontend/android/`, `frontend/pubspec.yaml`).
- **Backend Services:** Firebase Cloud Functions 2nd Gen (`backend/functions/`).
- **Database & Storage Rules:** `backend/firestore.rules`, `backend/storage.rules`.
- **Hosting & Infrastructure:** `firebase.json`, Redis Memorystore TLS, AWS S3 presigned URLs, Supabase sync pipeline.
- **Production Project:** Firebase project `medibond-45fad` (Firestore in `asia-south2`, Callables in `asia-south1`).

### Methodology & Evidence Labels
- **RAN:** Directly executed commands inspected via terminal output (`firebase functions:list`, `git log`, `git status`, `npm test`, `npm audit`).
- **READ:** Verified source code inspection with exact `file:line` locations.
- **UNVERIFIED:** State that could not be evaluated safely without side effects (e.g. `flutter analyze` due to lock contention from an active development session).
- **Hard Constraints Honored:** Strictly read-only; no code files modified, no git operations performed, no production writes or deploys triggered. Secrets cited by NAME only.

---

## 3. Part 0: Baseline & Deployed State Drift

### A. Live Deployed Functions Matrix (56 Functions Deployed)
*Source:* Live Firebase API CLI query `firebase functions:list --project medibond-45fad --json` (**RAN**).

| Function Name | Region | Trigger / Gen | App Check (OTP) | App Check (Abuse) | Update Time (UTC) | Build Hash | Exported in index.js? |
| :--- | :--- | :--- | :---: | :---: | :--- | :---: | :---: |
| `bookAppointment` | asia-south1 | Callable (2nd Gen) | `true` | `true` | 2026-10-06 05:22:30 | `fb8e2e13` | Yes |
| `expirePromotedAds` | asia-south1 | Schedule (hourly) | `true` | `true` | 2026-10-06 05:22:30 | `fb8e2e13` | Yes |
| `sendUserRegistrationOtp` | asia-south1 | Callable (2nd Gen) | `true` | `true` | 2026-10-06 05:15:37 | `fb8e2e13` | Yes |
| `verifyUserRegistrationOtp` | asia-south1 | Callable (2nd Gen) | `true` | `true` | 2026-10-06 05:15:37 | `fb8e2e13` | Yes |
| `reconcileAppointmentSlot` | asia-south2 | Firestore onWritten | `true` | `true` | 2026-10-06 05:22:30 | `fb8e2e13` | Yes |
| `deleteMyAccount` | asia-south1 | Callable (2nd Gen) | `true` | `true` | 2026-10-05 18:14:48 | `24434143` | Yes |
| `deleteS3Object` | asia-south1 | Callable (2nd Gen) | `true` | `true` | 2026-10-05 18:14:48 | `24434143` | Yes |
| `getS3DownloadUrl` | asia-south1 | Callable (2nd Gen) | `true` | `true` | 2026-10-05 18:14:48 | `24434143` | Yes |
| `getS3DownloadUrls` | asia-south1 | Callable (2nd Gen) | `true` | `true` | 2026-10-05 18:14:48 | `24434143` | Yes |
| `getS3UploadUrl` | asia-south1 | Callable (2nd Gen) | `true` | `true` | 2026-10-05 18:14:48 | `24434143` | Yes |
| `assertLoginAllowed` | asia-south1 | Callable (2nd Gen) | `true` | `true` | 2026-10-05 15:52:13 | `5828a372` | Yes |
| `clearFailedLogins` | asia-south1 | Callable (2nd Gen) | `true` | `true` | 2026-10-05 15:52:13 | `5828a372` | Yes |
| `completeAmbulanceMobileOtpLogin` | asia-south1 | Callable (2nd Gen) | `true` | `true` | 2026-10-05 15:52:13 | `5828a372` | Yes |
| `completeMobileOtpLogin` | asia-south1 | Callable (2nd Gen) | `true` | `true` | 2026-10-05 15:52:13 | `5828a372` | Yes |
| `createRazorpayOrder` | asia-south1 | Callable (2nd Gen) | `true` | `true` | 2026-10-05 15:52:13 | `5828a372` | Yes |
| `getValidationRulesHttp` | asia-south1 | HTTPS onRequest | `true` | `true` | 2026-10-05 15:52:13 | `5828a372` | Yes |
| `handleAmbulanceSmsWebhook` | asia-south1 | HTTPS onRequest | `true` | `true` | 2026-10-05 15:52:13 | `5828a372` | Yes |
| `lookupMobileRegistration` | asia-south1 | Callable (2nd Gen) | `true` | `true` | 2026-10-05 15:52:13 | `5828a372` | Yes |
| `recordFailedLogin` | asia-south1 | Callable (2nd Gen) | `true` | `true` | 2026-10-05 15:52:13 | `5828a372` | Yes |
| `resyncAmbulanceAuthUid` | asia-south1 | Callable (2nd Gen) | `true` | `true` | 2026-10-05 15:52:13 | `5828a372` | Yes |
| `sendAmbulanceBroadcastSms` | asia-south1 | Callable (2nd Gen) | `true` | `true` | 2026-10-05 15:52:13 | `5828a372` | Yes |
| `sendAmbulanceDriverLoginOtp` | asia-south1 | Callable (2nd Gen) | `true` | `true` | 2026-10-05 15:52:13 | `5828a372` | Yes |
| `sendBookingSmsNotification` | asia-south1 | Callable (2nd Gen) | `true` | `true` | 2026-10-05 15:52:13 | `5828a372` | Yes |
| `sendGenericSms` | asia-south1 | Callable (2nd Gen) | `true` | `true` | 2026-10-05 15:52:13 | `5828a372` | Yes |
| `sendLabOrderSmsNotification` | asia-south1 | Callable (2nd Gen) | `true` | `true` | 2026-10-05 15:52:13 | `5828a372` | Yes |
| `sendOrderSmsNotification` | asia-south1 | Callable (2nd Gen) | `true` | `true` | 2026-10-05 15:52:13 | `5828a372` | Yes |
| `sendOtp` | asia-south1 | Callable (2nd Gen) | `true` | `true` | 2026-10-05 15:52:13 | `5828a372` | **No (Orphan)** |
| `sendPrescriptionSmsNotification` | asia-south1 | Callable (2nd Gen) | `true` | `true` | 2026-10-05 15:52:13 | `5828a372` | Yes |
| `syncSingleDoctorToSupabase` | asia-south1 | Callable (2nd Gen) | `true` | `true` | 2026-10-05 15:52:13 | `5828a372` | Yes |
| `verifyAmbulanceDriverLogin` | asia-south1 | Callable (2nd Gen) | `true` | `true` | 2026-10-05 15:52:13 | `5828a372` | Yes |
| `verifyAmbulanceDriverLoginHttp` | asia-south1 | HTTPS onRequest | `true` | `true` | 2026-10-05 15:52:13 | `5828a372` | Yes |
| `verifyAmbulanceDriverLoginOtp` | asia-south1 | Callable (2nd Gen) | `true` | `true` | 2026-10-05 15:52:13 | `5828a372` | Yes |
| `verifyOtp` | asia-south1 | Callable (2nd Gen) | `true` | `true` | 2026-10-05 15:52:13 | `5828a372` | **No (Orphan)** |
| `verifyRazorpayPayment` | asia-south1 | Callable (2nd Gen) | `true` | `true` | 2026-10-05 15:52:13 | `5828a372` | Yes |
| `cleanupOldRateLimits` | asia-south1 | Schedule (24h) | `true` | `true` | 2026-10-05 15:52:13 | `5828a372` | Yes |
| `archiveExpiredPromotedAdsCron` | asia-south1 | Schedule (24h) | `true` | `true` | 2026-10-05 15:52:13 | `5828a372` | Yes |
| `processNotificationQueueCron` | asia-south1 | Schedule (1m) | `true` | `true` | 2026-10-05 15:52:13 | `5828a372` | Yes |
| `sendDailyAppointmentRemindersCron` | asia-south1 | Schedule (daily) | `true` | `true` | 2026-10-05 15:52:13 | `5828a372` | Yes |
| `aggregateDoctorRatingOnReviewCreate` | asia-south2 | Firestore onCreate | `true` | `true` | 2026-10-05 15:56:07 | `5828a372` | Yes |
| `cleanOrphanPatientLinks` | asia-south2 | Firestore onDelete | `true` | `true` | 2026-10-05 15:56:07 | `5828a372` | Yes |
| `cleanupAmbulanceOnDelete` | asia-south2 | Firestore onDelete | `true` | `true` | 2026-10-05 15:56:07 | `5828a372` | Yes |
| `cleanupDoctorOnDelete` | asia-south2 | Firestore onDelete | `true` | `true` | 2026-10-05 15:56:07 | `5828a372` | Yes |
| `cleanupLabOnDelete` | asia-south2 | Firestore onDelete | `true` | `true` | 2026-10-05 15:56:07 | `5828a372` | Yes |
| `cleanupMedicalStoreOnDelete` | asia-south2 | Firestore onDelete | `true` | `true` | 2026-10-05 15:56:07 | `5828a372` | Yes |
| `createNotificationQueueOnWrite` | asia-south2 | Firestore onWrite | `true` | `true` | 2026-10-05 15:56:07 | `5828a372` | Yes |
| `enqueueAppointmentNotification` | asia-south2 | Firestore onCreate | `true` | `true` | 2026-10-05 15:56:07 | `5828a372` | Yes |
| `enqueueLabBookingNotification` | asia-south2 | Firestore onCreate | `true` | `true` | 2026-10-05 15:56:07 | `5828a372` | Yes |
| `enqueueLabOrderNotification` | asia-south2 | Firestore onCreate | `true` | `true` | 2026-10-05 15:56:07 | `5828a372` | Yes |
| `enqueueOrderNotification` | asia-south2 | Firestore onCreate | `true` | `true` | 2026-10-05 15:56:07 | `5828a372` | Yes |
| `enqueuePrescriptionNotification` | asia-south2 | Firestore onCreate | `true` | `true` | 2026-10-05 15:56:07 | `5828a372` | Yes |
| `notifyDoctorOnAppointmentCreated` | asia-south2 | Firestore onCreate | `true` | `true` | 2026-10-05 15:56:07 | `5828a372` | Yes |
| `onDoctorStatusChanged` | asia-south2 | Firestore onUpdate | `true` | `true` | 2026-10-05 15:56:07 | `5828a372` | Yes |
| `onPatientStatusChanged` | asia-south2 | Firestore onUpdate | `true` | `true` | 2026-10-05 15:56:07 | `5828a372` | Yes |
| `processMailQueueMsg91` | asia-south2 | Firestore onCreate | `true` | `true` | 2026-10-05 15:56:07 | `5828a372` | Yes |
| `updateDoctorReviewAggregate` | asia-south2 | Firestore onWrite | `true` | `true` | 2026-10-05 15:56:07 | `5828a372` | Yes |
| `ssrmedibond45fad` | us-central1 | HTTPS (Next.js Framework) | *N/A* | *N/A* | 2026-03-08 07:11:42 | `8b094291` | **No (Framework)** |

*Note:* `verifyAmbulanceDriverLoginHttp` has `ENFORCE_AMBULANCE_HTTP_APP_CHECK=false` in its specific runtime environment.

### B. Discrepancies: Exported vs Deployed
- **Exported in `index.js` but Undeployed (20 total):**
  - `razorpayWebhook` (`asia-south1`): Local working tree implementation.
  - `enforceSendUserRegistrationOtpRateLimit` (`index.js:14`): Unit test helper export.
  - 18 Supabase Sync Triggers (`asia-south2`, `index.js:55-72`): `syncAppointmentToSupabase`, `syncPrescriptionToSupabase`, `syncDoctorToSupabase`, `syncDoctorAvailabilityToSupabase`, `syncDoctorBlockedDatesToSupabase`, `syncMedicalStoreToSupabase`, `syncPharmacyConnectionToSupabase`, `syncPharmacyDeliveryToSupabase`, `syncLabToSupabase`, `syncLabCatalogTestToSupabase`, `syncLabBookingToSupabase`, `syncLabOrderToSupabase`, `syncLabConnectionToSupabase`, `syncAmbulanceToSupabase`, `syncAmbulancePrivateSettingsToSupabase`, `syncAmbulanceBroadcastToSupabase`, `syncAmbulanceRequestToSupabase`, `syncAmbulanceInviteToSupabase`.
- **Deployed but Not Exported in `backend/functions/index.js` (3 total):**
  - `sendOtp` (`asia-south1`, build `5828a372`): Orphan callable.
  - `verifyOtp` (`asia-south1`, build `5828a372`): Orphan callable.
  - `ssrmedibond45fad` (`us-central1`, build `8b094291`): Firebase Frameworks Next.js web SSR deployment.

### C. CI/CD & Deploy Paths
- [.github/workflows/build-apk.yml](file:///c:/Users/khije/Downloads/DoctorNect/doctor/.github/workflows/build-apk.yml) (**READ**): Builds release APK on push to `main` with paths in `frontend/**`. Does **not** deploy.
- [.github/workflows/flutter-ci.yml](file:///c:/Users/khije/Downloads/DoctorNect/doctor/.github/workflows/flutter-ci.yml) (**READ**): Runs format, analyze, and tests. Does **not** deploy.
- **Automated Deployment:** Zero automated deployment pipelines exist. All deploys are manual CLI operations.

### D. Test & Dependency Health
- **`npm test` in `backend/functions` (RAN):** 226 tests (219 passed, 7 skipped due to local emulators not running, 0 failed).
- **`npm audit` in `backend/functions` (RAN):** 0 vulnerabilities found.
- **`flutter analyze` (RAN):** Invoked `flutter analyze --no-pub`. Stalled due to file lock contention from an active `flutter run` terminal session (>3h). Marked **UNVERIFIED** to preserve zero side-effects constraint.

---

## 4. Part 1: Identity, OTP and Demo Access

### A. Full OTP Lifecycle & Storage
- **OTP Generation & Salted HMAC:** Generated as a 6-digit cryptographic random code. Stored in `otp_challenges/{mobileHash}` where `mobileHash = sha256(role + ":" + digits)`. Stored hash is `HMAC-SHA256(normRole + ":" + normDigits + ":" + code, MSG91_AUTH_KEY)` ([registration_otp.js:284](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/functions/registration_otp.js#L284), **READ**).
- **Fail-Closed Secret Check:** In production, if `MSG91_AUTH_KEY` is missing during challenge creation, it logs a security event and throws `HttpsError('internal')` ([registration_otp.js:270](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/functions/registration_otp.js#L270), **READ**).
- **Challenge TTL & Cooldown:** 10 minutes expiry (`OTP_EXPIRY_MS = 600,000ms`), 60 seconds resend cooldown (`RESEND_COOLDOWN_MS = 60,000ms`).
- **Atomic Verification:** Evaluated within a Firestore transaction in `consumeOtpChallengeAtomically` ([registration_otp.js:1910](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/functions/registration_otp.js#L1910), **READ**). 5 maximum attempts.
- **Session Tokens:** Valid verification generates unguessable UUID in `otp_verification_sessions/{sessionId}` with 30-minute expiry (`SESSION_EXPIRY_MS = 1,800,000ms`).
- **Atomic Session Consumption:** `consumeOtpVerificationSessionAtomically` ([registration_otp.js:2130](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/functions/registration_otp.js#L2130), **READ**) marks `consumed: true` in a transaction, preventing replay attacks.
- **Redis Cache Privacy:** Redis key is `otp:challenge:{role}:{HMAC(digits, secret)}`, payload is `{ otpHash, role, expiresAt }` with 600s TTL ([registration_otp.js:1807](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/functions/registration_otp.js#L1807), **READ**). Plaintext OTP and phone numbers are **never** stored in Redis.

### B. Demo Accounts & Production Gating
- **Remote Config Gating:** `getDemoConfig()` ([registration_otp.js:71](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/functions/registration_otp.js#L71), **READ**) reads `app_config/demo_accounts` in Firestore. In production (`medibond-45fad`), if the document is missing or `demoLoginEnabled !== true`, it returns `null`. `DEFAULT_DEMO_CONFIG` is **strictly prevented** in production ([registration_otp.js:115](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/functions/registration_otp.js#L115), **READ**).
- **Stale Challenge Purge:** Stale demo challenges with `demoAccount: true` are rejected when demo mode is disabled ([registration_otp.js:2255](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/functions/registration_otp.js#L2255), **READ**).
- **Public Directory Leakage:** Provisioned demo accounts (`Dr. Demo Doctor`, `Demo Ambulance`) create real records in `doctors`, `ambulances`, `labs` with `verified: true, status: 'approved'`. Neither Firestore rules nor the Flutter client filter demo accounts from search listings ([SEC-27](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/firestore.rules#L466)).

### C. Ambulance Authentication & Re-Binding
- **PIN vs OTP Paths:** Drivers authenticate via username/PIN (`verifyAmbulanceDriverLogin`) or phone OTP (`completeAmbulanceMobileOtpLogin`).
- **Reinstall Lockout:** Firestore rules block client updates to `ambulances/{driverId}.authUid` if already populated ([firestore.rules:988](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/firestore.rules#L988), **READ**). Stale UID reclaims require `resyncAmbulanceAuthUid` with username + PIN ([index.js:1625](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/functions/index.js#L1625), **READ**).
- **Driver Lockout Flaw:** `completeAmbulanceMobileOtpLogin` fails to update `authUid = auth.uid` on the ambulance document, leaving drivers unable to update availability or accept rides after mobile OTP login ([SEC-09](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/functions/registration_otp.js#L2481)).

### D. Admin and SuperAdmin Authorization
- **SuperAdmin Resolution:** Firestore rules define `isSuperAdmin()` as `users/{uid}.role in ['super_admin', 'superAdmin', 'admin']` OR verified email `admin@doctornect.com` ([firestore.rules:122](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/firestore.rules#L122), **READ**).
- **Approval Gating:** `approveUserAccount` strictly enforces caller email in `ACCOUNT_APPROVAL_ADMIN_EMAILS` with `email_verified == true` ([registration_otp.js:2436](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/functions/registration_otp.js#L2436), **READ**).

---

## 5. Part 2: Firestore Rules and Data Access

### A. Access Control Summary
- **Strict Default Deny:** Unmatched collections fall through to `{document=**} { allow read, write: if false; }` ([firestore.rules:1225](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/firestore.rules#L1225), **READ**).
- **Server-Only Collections:** `doctor_slots`, `doctor_day_counters`, `otp_challenges`, `otp_verification_sessions`, `otp_rate_limits`, `abuse_rate_limits`, `security_events`, `razorpayPayments` are completely inaccessible to client SDKs.
- **Clinical Data Protection:** `health_records/{id}` requires patient ownership OR explicit opt-in sharing (`sharedWithDoctors == true`) AND established care-team relationship ([firestore.rules:643](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/firestore.rules#L643), **READ**). An unrelated doctor cannot self-grant access.
- **Walk-in Clinical Bypass:** `doctorCanReadPatientClinicalData` allows doctors to issue prescriptions and lab orders for non-`p\d+` patient IDs (walk-ins) without requiring a pre-existing patient profile document ([firestore.rules:203](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/firestore.rules#L203), **READ**).

### B. Identified Rules Vulnerabilities
1. **Direct Appointment Field Tampering ([SEC-12](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/firestore.rules#L530-L541)):** `appointments` update rules do not restrict affected keys. Clients can change `status`, reschedule `dateTime`, or alter billing fields directly in Firestore.
2. **Unauthenticated Doctor Directory Scraping ([SEC-13](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/firestore.rules#L463-L466)):** Verified doctor records are readable and listable without authentication, exposing mobile numbers, emails, and medical council IDs.
3. **Missing Automated Rules Tests ([SEC-14](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/functions/package.json#L28-L32)):** Zero unit tests exist for `appointments`, `prescriptions`, `health_records`, `lab_orders`, or `ambulances`.

---

## 6. Part 3: Booking, Slots and Business Logic

### A. Booking Architecture & Race Condition Defense
- **Atomic Capacity Checks:** `bookAppointment` ([appointment_slots.js:461](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/functions/appointment_slots.js#L461), **READ**) runs inside a Firestore transaction:
  - Validates caller role is `patient` and overrides `patientId` with authenticated profile ID.
  - Verifies doctor exists, is verified, and is not deactivated.
  - Evaluates `isSlotInsideDoctorAvailability` against weekly off-days, blocked dates, and leaves.
  - Enforces `MAX_PATIENTS_PER_SLOT = 3`.
  - Rejects double bookings by the same patient in the same slot.
  - Atomically increments daily token counter `doctor_day_counters/{doctorId}_{YYYY-MM-DD}`.
  - Inserts appointment with `status: 'confirmed'`.
- **Reconciliation Trigger Idempotency:** `reconcileAppointmentSlot` ([appointment_slots.js:428](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/functions/appointment_slots.js#L428), **READ**) uses early returns on non-slot changes (notes, prescriptions) to eliminate trigger loops. If a slot overflows due to legacy direct writes, it logs a warning, flags `slotOverflow: true`, and never deletes records.
- **Backfill Script Safety:** `backend/scripts/backfill_doctor_slots.js` reuses identical slot ID derivation and date formatting logic. Running with `--apply` processes appointments in batches of 500 without dropping active bookings.

---

## 7. Part 4: Money, Storage and Payments

### A. Razorpay Promoted Ads & Webhook
- **Order & Signature Verification:** `createRazorpayOrder` enforces pricing tiers in INR. `verifyRazorpayPayment` verifies signatures and re-queries Razorpay REST API `/v1/payments/{paymentId}` to confirm status is `captured` and `notes.adId` matches ([promoted_ads.js:90](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/functions/promoted_ads.js#L90), **READ**).
- **Replay Protection:** `razorpayPayments/{paymentId}` ledger doc created in transaction. Replaying payment IDs is rejected.
- **Webhook Implementation ([promoted_ads.js:540](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/functions/promoted_ads.js#L540), READ):** Validates `x-razorpay-signature` using HMAC-SHA256 of `req.rawBody` with `crypto.timingSafeEqual` and `defineSecret('RAZORPAY_WEBHOOK_SECRET')`. Shared helper `activatePromotedAdPayment` ensures identical ledger updates.
- **Scheduled Expiry:** `expirePromotedAds` runs hourly to archive expired ads from `promotedAds`.

### B. S3 Storage & Presigned URLs
- **Upload Validation:** `getS3UploadUrl` enforces content-type whitelist (`image/jpeg`, `image/png`, `image/webp`, `application/pdf`), size limits (5MB images, 15MB PDFs), and path ownership (`health_records/{patientId}/...`, `doctor_profiles/{doctorId}/...`) ([s3_storage.js:34](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/functions/s3_storage.js#L34), **READ**).
- **Download Authorization:** `getS3DownloadUrl` checks ownership or care-team relationship before generating presigned GET URLs with 15-minute TTL.
- **Redis Cache & Invalidation:** S3 URLs cached in Redis when `S3_URL_CACHE=true`. Deletions and uploads invalidate cache entries.
- **Hosting CSP Defect ([SEC-15](file:///c:/Users/khije/Downloads/DoctorNect/doctor/firebase.json#L163)):** Web CSP header omits `https://*.amazonaws.com` from `img-src`.

### C. Account Deletion (`deleteMyAccount`)
- Deletes user profile, appointments, health records, reviews, and Firebase Auth account ([delete_my_account.js:40](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/functions/delete_my_account.js#L40), **READ**).
- **Compliance Gap ([SEC-22](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/functions/delete_my_account.js#L350)):** Does not delete orphaned S3 storage objects or Supabase database rows.

---

## 8. Part 5: Backend Platform, Secrets and Supabase

### A. Secrets Management
- **Secret Manager vs Environment:** Sensitive keys (`MSG91_AUTH_KEY`, `RAZORPAY_KEY_SECRET`, `RAZORPAY_WEBHOOK_SECRET`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`) are declared via `defineSecret` or read via `secure_config.js`. Non-sensitive flags (`ENFORCE_OTP_APP_CHECK`, `ENFORCE_ABUSE_APP_CHECK`) reside in `.env`.
- **Git History Hygiene:** Verified `.env` was never committed to git history (**RAN**). Only `.env.example` templates exist.

### B. Supabase Bridge & RLS
- **Undeployed Sync Triggers ([SEC-18](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/functions/index.js#L55-L72)):** 18 triggers exported in `index.js` are undeployed. A bulk deploy will activate them immediately.
- **Insecure SSL in Database Pool ([SEC-19](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/functions/cross_role_sync.js#L32)):** `getPgPool` uses `ssl: { rejectUnauthorized: false }`, disabling certificate validation for PostgreSQL connections.

### C. Redis Memorystore
- Connects via TLS using CA cert `redis_ca.pem` and `rejectUnauthorized: true`. Rate limiting falls back gracefully to Firestore transactions if Redis is unavailable ([abuse_rate_limit.js:180](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/functions/abuse_rate_limit.js#L180), **READ**).

---

## 9. Part 6: Client and Release Configuration

### A. Android Configuration
- **Missing `allowBackup` Restriction ([SEC-16](file:///c:/Users/khije/Downloads/DoctorNect/doctor/frontend/android/app/src/main/AndroidManifest.xml#L14)):** `AndroidManifest.xml` omits `android:allowBackup="false"`, defaulting to `true` and allowing ADB backup extraction of app databases and preferences.
- **Permissions:** Scoped properly. Camera, fine location, coarse location, and post notifications requested. Broad storage permissions are explicitly removed.

### B. Force-Update Mechanism Absence ([SEC-17])
- Shipped Play Store build is `versionCode 5`.
- **Zero In-App Update Gate:** The Flutter client has no remote version check or force-update dialog. Server-side breaking changes (e.g. blocking direct appointment writes) will break users on `versionCode 5`.

---

## 10. Consolidated Findings Register

| Finding ID | Title | Severity | Status | Deployed Hash / State |
| :--- | :--- | :---: | :---: | :--- |
| **SEC-05** | Unvetted Doctor Auto-Approval Bypass in `completeMobileOtpLogin` | **CRITICAL** | OPEN | `5828a372` / Repo |
| **SEC-12** | Direct Client Mutation on `appointments` in Firestore Rules | **HIGH** | OPEN | Deployed Rules / Repo |
| **SEC-15** | Firebase Hosting CSP Blocks AWS S3 Image Origins on Web | **HIGH** | OPEN | Repo (`firebase.json`) |
| **SEC-18** | 18 Undeployed Supabase Triggers Exported in `index.js` (Bulk Deploy Trap) | **HIGH** | OPEN | Undeployed / Repo |
| **SEC-06** | Orphan Deployed Cloud Functions `sendOtp` and `verifyOtp` | **MEDIUM** | OPEN | `5828a372` (Deployed only) |
| **SEC-09** | Ambulance Driver Auth Lockout on Mobile OTP Login (`authUid` Unbound) | **MEDIUM** | OPEN | `5828a372` / Repo |
| **SEC-13** | Unauthenticated Public Scraping of Doctor Personal PII | **MEDIUM** | OPEN | Deployed Rules / Repo |
| **SEC-14** | Critical Rules Test Coverage Void on Clinical Collections | **MEDIUM** | OPEN | Repo (`package.json`) |
| **SEC-16** | `android:allowBackup` Defaults to True in Android Manifest | **MEDIUM** | OPEN | Repo (`AndroidManifest.xml`) |
| **SEC-17** | Absence of Client Force-Update Mechanism (versionCode 5 Trap) | **MEDIUM** | OPEN | Shipped Play Build / Repo |
| **SEC-19** | Supabase Postgres Pool Disables SSL Certificate Verification | **MEDIUM** | OPEN | Repo (`cross_role_sync.js`) |
| **SEC-20** | Orphan Framework SSR Function `ssrmedibond45fad` in `us-central1` | **MEDIUM** | OPEN | `8b094291` (Deployed only) |
| **SEC-21** | Razorpay Webhook Implemented in Repo but Undeployed in Production | **MEDIUM** | FIXED-IN-REPO | Undeployed / Repo |
| **SEC-22** | `deleteMyAccount` Leaves Orphaned S3 Objects and Supabase Records | **MEDIUM** | OPEN | `24434143` / Repo |
| **SEC-07** | Phone Number Registration Enumeration via `lookupMobileRegistration` | **LOW** | OPEN | `5828a372` / Repo |
| **SEC-08** | OTP Attempt Counter Reset on MSG91 Retry Resend | **LOW** | OPEN | `fb8e2e13` / Repo |
| **SEC-10** | Absence of Global Outbound SMS Pumping Cost Caps | **LOW** | OPEN | `fb8e2e13` / Repo |
| **SEC-11** | Public Visibility of Demo Provider Accounts in Search Directories | **LOW** | OPEN | `5828a372` / Repo |
| **SEC-01** | Supabase Client Unhandled Exception on Booking (SEC-01 style abort) | RESOLVED | FIXED-IN-REPO | Repo (Guarded by `isReady`) |
| **SEC-02** | Appointment Double Booking & Slot Overbooking | RESOLVED | FIXED-AND-DEPLOYED | `fb8e2e13` |
| **SEC-03** | Plaintext OTP / Phone Storage in Redis Cache | RESOLVED | FIXED-AND-DEPLOYED | `fb8e2e13` |
| **SEC-04** | OTP Test Mode Bypass in Production Project | RESOLVED | FIXED-AND-DEPLOYED | `fb8e2e13` |

---

### Detailed Findings

#### [SEC-05] Unvetted Doctor Auto-Approval Bypass in `completeMobileOtpLogin`
- **Severity:** CRITICAL
- **Status:** OPEN (Present in Repo and Deployed build `5828a372`)
- **Exploitability:** Any user who registers as a doctor. By logging in via `completeMobileOtpLogin`, line 3080 unconditionally calls `ensureDoctorFullVerified` because the check is `if (role === 'doctor')` instead of `if (role === 'doctor' && isDemo)`.
- **Impact:** Any unverified user self-approves their doctor profile (`verified: true, status: 'approved'`), gaining the ability to write prescriptions, view medical records, and appear in patient searches without KYC approval.
- **Evidence:** [registration_otp.js:3080-3084](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/functions/registration_otp.js#L3080-L3084) (**READ**):
  ```javascript
  let authUid = search.uid;
  if (role === 'doctor') {
    await ensureDoctorFullVerified(db, authUid, search.data?.profileId, { mobile: mobileDigits });
  } else if (isDemo) {
  ```
- **Minimal Fix:** Change line 3080 to:
  ```javascript
  if (isDemo && role === 'doctor') {
  ```
- **Effort:** S
- **Risk of Fix:** None. Pending doctors will correctly wait for SuperAdmin verification.
- **How to Test:** Register a doctor account, log in via `completeMobileOtpLogin`; assert `users/{uid}.verified` remains `false`.

---

#### [SEC-12] Direct Client Mutation on `appointments/{appointmentId}` in Firestore Rules
- **Severity:** HIGH
- **Status:** OPEN (Present in Repo and Deployed rules)
- **Exploitability:** Any authenticated patient or doctor party to an appointment.
- **Impact:** A patient or doctor can bypass `bookAppointment` to directly alter `dateTime` (bypassing capacity), flip `status: 'completed'` (to leave reviews without consultation), or tamper with `tokenNumber` and billing amounts.
- **Evidence:** [firestore.rules:530-541](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/firestore.rules#L530-L541) (**READ**):
  ```javascript
  allow update: if appointmentParty()
    && validAppointmentUpdate();

  function validAppointmentUpdate() {
    let incoming = request.resource.data;
    let existing = resource.data;
    return incoming.patientId == existing.patientId
      && incoming.doctorId == existing.doctorId;
  }
  ```
- **Minimal Fix:** Add key restrictions:
  ```javascript
  function validAppointmentUpdate() {
    let incoming = request.resource.data;
    let existing = resource.data;
    return incoming.patientId == existing.patientId
      && incoming.doctorId == existing.doctorId
      && !request.resource.data.diff(resource.data).affectedKeys()
          .hasAny(['patientId', 'doctorId', 'tokenNumber', 'amountPaid', 'paymentStatus', 'createdAt']);
  }
  ```
- **Effort:** S
- **Risk of Fix:** Low. Does not break cancellation or note updates.
- **How to Test:** Attempt direct Firestore SDK update setting `tokenNumber: 999`; verify rejection.

---

#### [SEC-15] Firebase Hosting CSP Blocks AWS S3 Image Origins on Web
- **Severity:** HIGH
- **Status:** OPEN (Present in Repo `firebase.json`)
- **Exploitability:** Any web client user when `use_s3_storage` is active.
- **Impact:** When S3 storage presigned URLs (`https://doctornect.s3.ap-south-1.amazonaws.com/...`) are loaded for doctor photos, banners, or health records, the browser CSP blocks all images.
- **Evidence:** [firebase.json:163](file:///c:/Users/khije/Downloads/DoctorNect/doctor/firebase.json#L163) (**READ**):
  `img-src` specifies Firebase Storage and Google accounts, but omits AWS S3 origins (`https://*.amazonaws.com`).
- **Minimal Fix:** Add `https://*.amazonaws.com` to `img-src` in [firebase.json:163](file:///c:/Users/khije/Downloads/DoctorNect/doctor/firebase.json#L163).
- **Effort:** S
- **Risk of Fix:** None.
- **How to Test:** Run `npm run test:hosting-csp` or deploy hosting to a preview channel and load an S3 presigned image; inspect browser console for CSP violations.

---

#### [SEC-18] 18 Undeployed Supabase Triggers Exported in `index.js` (Bulk Deploy Trap)
- **Severity:** HIGH
- **Status:** OPEN (Present in Repo `backend/functions/index.js`)
- **Exploitability:** Running `firebase deploy --only functions`.
- **Impact:** Deploys 18 sync triggers to `asia-south2`. On every Firestore write, triggers will attempt to sync data to Supabase using `rejectUnauthorized: false` and may crash or throw errors on every write if Supabase credentials are missing in production.
- **Evidence:** [index.js:55-72](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/functions/index.js#L55-L72) (**READ**). Triggers are exported but absent from `firebase functions:list` (**RAN**).
- **Minimal Fix:** Comment out or gate the 18 trigger exports in `index.js` until Supabase migration is fully ready:
  ```javascript
  if (process.env.ENABLE_SUPABASE_SYNC === 'true') { ... }
  ```
- **Effort:** S
- **Risk of Fix:** None. Triggers are not running in production today.
- **How to Test:** Run `node --check index.js`; verify exports are clean.

---

#### [SEC-09] Ambulance Driver Auth Lockout on Mobile OTP Login (`authUid` Unbound)
- **Severity:** MEDIUM
- **Status:** OPEN (Present in Repo and Deployed build `5828a372`)
- **Exploitability:** Ambulance drivers authenticating via mobile OTP.
- **Impact:** Driver logs in successfully, but their anonymous `authUid` is never updated on `ambulances/{driverId}`. Subsequent Firestore writes to update availability or claim emergency rides fail with `PERMISSION_DENIED`.
- **Evidence:** [registration_otp.js:2481-2537](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/functions/registration_otp.js#L2481-L2537) (**READ**).
- **Minimal Fix:** Update `authUid` on the ambulance document in `completeAmbulanceMobileOtpLogin`:
  ```javascript
  await db.collection('ambulances').doc(found.id).set({ authUid: auth.uid }, { merge: true });
  ```
- **Effort:** S
- **Risk of Fix:** None. Restores intended driver functionality.
- **How to Test:** Call `completeAmbulanceMobileOtpLogin` with an anonymous UID; verify `ambulances/{driverId}.authUid` matches.

---

#### [SEC-13] Unauthenticated Public Scraping of Doctor Personal PII
- **Severity:** MEDIUM
- **Status:** OPEN (Present in Repo and Deployed rules)
- **Exploitability:** Unauthenticated web/HTTP scrapers.
- **Impact:** Scrapers can extract doctor phone numbers, emails, council registration numbers, and clinic addresses without logging in.
- **Evidence:** [firestore.rules:463-466](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/firestore.rules#L463-L466) (**READ**):
  `allow list: if request.query.limit <= 100;` and `allow get: if ... || resource.data.get('verified', false) == true;` require no auth.
- **Minimal Fix:** Require `isSignedIn()` for list queries and sensitive field access:
  ```javascript
  allow list: if isSignedIn() && request.query.limit <= 100;
  ```
- **Effort:** S
- **Risk of Fix:** Verify if versionCode 5 client allows unauthenticated doctor searches before login.
- **How to Test:** Attempt unauthenticated curl request to Firestore REST API for `doctors`; assert rejection.

---

#### [SEC-16] `android:allowBackup` Defaults to True in Android Manifest
- **Severity:** MEDIUM
- **Status:** OPEN (Present in Repo `AndroidManifest.xml`)
- **Exploitability:** Physical or ADB access to the device.
- **Impact:** Sensitive local storage, tokens, and cached databases can be dumped via `adb backup`.
- **Evidence:** [AndroidManifest.xml:14-18](file:///c:/Users/khije/Downloads/DoctorNect/doctor/frontend/android/app/src/main/AndroidManifest.xml#L14-L18) (**READ**).
- **Minimal Fix:** Add `android:allowBackup="false"` to `<application>`.
- **Effort:** S
- **Risk of Fix:** None.
- **How to Test:** Inspect merged manifest in `build/app/intermediates/merged_manifests/release/AndroidManifest.xml`.

---

#### [SEC-17] Absence of Client Force-Update Mechanism (versionCode 5 Trap)
- **Severity:** MEDIUM
- **Status:** OPEN (Shipped Play Store build versionCode 5 / Repo)
- **Exploitability:** Users on old app versions continuing to operate indefinitely.
- **Impact:** Prevents server-side breaking security fixes (e.g. locking down direct appointment writes) because old clients will break with `PERMISSION_DENIED`.
- **Evidence:** Absence of version gating or in-app update checks in `frontend/lib/` (**READ**).
- **Minimal Fix:** Add a lightweight `app_config/version` document check at boot in `frontend/lib/main.dart` showing a non-dismissible modal if `currentVersionCode < minVersionCode`.
- **Effort:** M
- **Risk of Fix:** Requires a new Play Store release before server-side lockdown can proceed.
- **How to Test:** Set `minVersionCode` above local build; verify update prompt displays.

---

## 11. Attack Chains

### Chain A: Unvetted Doctor Self-Approval & Clinical Data Hijack
1. **Attacker Action:** Register an account as `doctor` using any unverified phone number.
2. **Execution:** Call `sendUserRegistrationOtp` and `verifyUserRegistrationOtp` to obtain a valid `sessionId`.
3. **Exploit:** Call `completeMobileOtpLogin` ([registration_otp.js:3080](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/functions/registration_otp.js#L3080)). Line 3080 executes `ensureDoctorFullVerified`, setting `users/{uid}.verified = true` and `doctors/{doctorId}.status = 'approved'`.
4. **Outcome:** Attacker becomes a verified doctor, bypassing SuperAdmin KYC review, appearing in directory searches, and gaining permission to view shared patient records and write prescriptions.

### Chain B: Direct Appointment Hijack & False Rating Fraud
1. **Attacker Action:** Create a booking directly via Firestore SDK `appointments.add(...)` without invoking `bookAppointment`.
2. **Tampering:** Patient immediately executes a direct Firestore update setting `status: 'completed'`.
3. **Outcome:** Because `appointments` update rules lack key blacklists ([firestore.rules:530](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/firestore.rules#L530)), the appointment transitions to `completed`. The patient can now post reviews or access post-consultation features without the doctor ever accepting the booking.

---

## 12. Prioritized Remediation Plan

### Step 1: Immediate Critical Backend Fix (Zero Client Impact)
- **Target Functions:** `completeMobileOtpLogin` ([registration_otp.js:3080](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/functions/registration_otp.js#L3080)), `completeAmbulanceMobileOtpLogin` ([registration_otp.js:2530](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/functions/registration_otp.js#L2530)).
- **Changes:**
  1. Patch line 3080: `if (isDemo && role === 'doctor')`.
  2. Patch line 2530: update `authUid` on ambulance document.
- **Deploy Command (Selective Deploy Only):**
  ```bash
  firebase deploy --only functions:completeMobileOtpLogin,functions:completeAmbulanceMobileOtpLogin
  ```
- **Rollback:** Redeploy previous working commit `5828a372`.
- **Old App Impact:** None.

### Step 2: Hosting CSP & Undeployed Triggers Cleanup
- **Changes:**
  1. Add `https://*.amazonaws.com` to `img-src` in `firebase.json:163`.
  2. Gate the 18 undeployed Supabase triggers in `index.js:55-72` behind `ENABLE_SUPABASE_SYNC`.
  3. Deploy Razorpay webhook (`razorpayWebhook`).
- **Deploy Command:**
  ```bash
  firebase deploy --only hosting,functions:razorpayWebhook
  ```
- **Old App Impact:** None.

### Step 3: Firestore Rules Tightening
- **Changes:**
  1. Restrict update keys on `appointments/{appointmentId}` ([firestore.rules:535](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/firestore.rules#L535)).
  2. Require `isSignedIn()` for `doctors` list queries.
- **Deploy Command:**
  ```bash
  firebase deploy --only firestore:rules
  ```
- **Old App Impact:** None for normal booking flows; blocks malicious client tampering.

### Step 4: Next Client Release (Play Store)
- **Changes:**
  1. Add `android:allowBackup="false"` in `AndroidManifest.xml`.
  2. Implement Remote Config version check / force-update mechanism.
  3. Filter `isDemo: true` from doctor/ambulance search listings.

---

## 13. Immediate Non-Code Actions (Next 48 Hours)

1. **Audit Unapproved Doctors in Production:**
   Run a Firestore query in Firebase Console:
   ```javascript
   db.collection('doctors').where('verified', '==', true).where('status', '==', 'approved')
   ```
   Check if any doctor documents lack corresponding SuperAdmin audit logs in `admin_audit_logs`. Revert any doctors created through SEC-05 auto-approval.
2. **Verify `app_config/demo_accounts` in Production:**
   Inspect Firestore collection `app_config`, doc `demo_accounts`. Ensure `demoLoginEnabled` is `false` (or doc does not exist).
3. **Configure MSG91 Outbound Spend Cap:**
   Log into the MSG91 dashboard and set a daily SMS spending threshold and balance alert to protect against botnet SMS pumping.
4. **Configure Razorpay Webhook Secret:**
   In Google Cloud Secret Manager, set `RAZORPAY_WEBHOOK_SECRET` and add the webhook endpoint URL in Razorpay Dashboard (`https://asia-south1-medibond-45fad.cloudfunctions.net/razorpayWebhook`).

---

## 14. Open Questions & Assumptions

1. **Guest Doctor Browsing in Old App (versionCode 5):**
   *Assumption:* If versionCode 5 allows unauthenticated users to view doctor listings on launch, tightening `doctors` list rules to require `isSignedIn()` will cause permission errors for guests. Must verify guest browsing flow before deploying rule changes.
2. **Supabase Production Timeline:**
   *Assumption:* Supabase sync triggers are not currently used in production. Leaving them undeployed and gating their exports prevents catastrophic failures during accidental bulk deploys.
