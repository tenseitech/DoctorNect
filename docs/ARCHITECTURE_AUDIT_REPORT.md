# DoctorNect — End-to-End Architecture Audit (READ-ONLY)

- **Date:** 2026-10-12
- **Audited Ref:** `5936b7f` (`fix(ambulance): bind authUid server-side after OTP login (not deployed)`) on `main`
- **Mode:** Read-only architectural and security verification. No production changes were executed.
- **Secrets Policy:** Zero secret values, credentials, or tokens are printed. All environment variables, Secret Manager parameters, and connection identifiers are cited by **name only**.

---

## 1. Executive Summary

### Overall Health Score: **6 / 10**

The architecture presents a tale of two distinct systems:
1. **The Native Firestore Stack (Score: 8.5 / 10):** Highly mature, battle-tested, and secure. Authentication via MSG91 OTP -> Firebase custom tokens, role resolution, doctor/pharmacy/lab/ambulance workflows, S3 presigned storage via Cloud Functions v2, and Razorpay server-side payment verification are properly implemented with comprehensive rules test coverage (174 emulator tests passing).
2. **The Target Supabase + Bidirectional Sync Architecture (Score: 2.0 / 10):** Incomplete and currently non-functional for production. While 21 SQL migrations and client repository abstractions exist, Firebase-to-Supabase identity resolution fails because `public.users` has no sync writer, the reverse sync edge function is an empty stub, and the Cloud Functions Firestore-to-Supabase sync triggers remain un-deployed.

### Key Operational State Today
- **Release Build Defaults:** `frontend/scripts/release_build.ps1:84-97` and `frontend/scripts/release_build.sh` deliberately leave `ENABLE_SUPABASE` unset. This safely bypasses Supabase at runtime, keeping all 5 roles on the functional Firestore backend.
- **Storage & Caching Flags:** `use_s3_storage` defaults to `false` (Remote Config), keeping files on Firebase Storage. `RATE_LIMIT_BACKEND` defaults to `firestore`, and `S3_URL_CACHE` is `off`, meaning Redis Cloud is fail-open and dormant on the hot path.

### Top 5 Risks

| # | Risk | Severity | Evidence (`file:line`) | Impact |
|---|------|----------|------------------------|--------|
| 1 | **Supabase Identity Failure (`public.users` Missing)** | **Critical** | `backend/supabase/migrations/20261008000001_firebase_uid_identity.sql:98-117`<br>`backend/functions/cross_role_sync.js` (0 sync logic for users) | If `ENABLE_SUPABASE=1` is compiled in, `book_appointment_atomic` RPC and RLS throw `42501 PROFILE_NOT_FOUND`. No row in `public.users` is ever created for Firebase users. |
| 2 | **Reverse Sync is an Empty Stub** | **Critical** | `backend/supabase/functions/sync-to-firestore/index.ts:34-38`<br>`frontend/lib/core/data/shared_appointments_store.dart:814-832` | Patient cancellations or status changes committed to Supabase never propagate to Firestore. Doctor calendars never reflect patient cancellations. |
| 3 | **Un-deployed Cloud Functions & Client Drift** | **High** | `backend/functions/index.js:680-720`<br>`docs/DEPLOY_CHECKLIST.md:32-36` | `rescheduleAppointment` callable and server-side ambulance `authUid` relink are committed in source but **NOT deployed** to Cloud Functions `asia-south1`. Client calls fail with `functions/not-found`. |
| 4 | **Ambulance Stale `authUid` Re-login Lockout** | **High** | `backend/firestore.rules:1148-1156,1209-1220`<br>`frontend/lib/core/firebase/repositories/ambulance_repository.dart:89` | `canLinkAmbulanceAuthUid` rejects client writes if an existing `authUid` is present. When a driver logs in on a new device, client update throws `permission-denied` because server-side link (`5936b7f`) is not yet deployed. |
| 5 | **Promoted Ads Workflow Stall** | **High** | `backend/functions/promoted_ads.js:35-41,148-152`<br>`frontend/lib/features/promoted_ads/screens/create_promoted_ad_screen.dart:128-130` | Providers pay for ads via Razorpay, but ads enter `pending_approval`. No admin UI is linked in app release navigation to invoke `reviewPromotedAd`, leaving campaigns stalled indefinitely. |

### Go / No-Go Verdict
- **NO-GO for Target Supabase Architecture (`ENABLE_SUPABASE=1`):** Blocker C-1 (missing user synchronization) and C-2 (stub reverse sync) will cause runtime exceptions and split-brain data states.
- **CONDITIONAL GO for Firestore-Native Production Binary:** Safe to release **ONLY IF** `ENABLE_SUPABASE` remains unset, and pending backend callables (`rescheduleAppointment` and `completeAmbulanceMobileOtpLogin`) are deployed to Cloud Functions prior to app store release.

---

## 2. Audit Scope & Coverage

Every subsystem across the repository was systematically inspected:

| Subsystem | Inspected Paths & Components | Verification Method |
|:---|:---|:---|
| **Flutter Frontend** | `frontend/lib/core/auth/` (unified auth, OTP, lookup)<br>`frontend/lib/core/firebase/` (bootstraps, repositories, callables)<br>`frontend/lib/core/supabase/` (bootstrap, repositories, tokens)<br>`frontend/lib/features/` (patient, doctor, pharmacy, lab, ambulance, admin, ads)<br>`frontend/pubspec.yaml`, `frontend/scripts/release_build.*` | Static analysis (`flutter analyze` - 0 issues), 58 test suites (`flutter test` - 426 passing). |
| **Cloud Functions** | `backend/functions/index.js` (exports, regions, secrets, App Check)<br>`registration_otp.js`, `appointment_slots.js`, `cross_role_sync.js`<br>`promoted_ads.js`, `s3_storage.js`, `delete_my_account.js`<br>`abuse_rate_limit.js`, `http_endpoint_security.js`, `src/config/redis.js` | Unit test suite (`node --test test/**/*.test.js` - 285 passing, 8 emulator-skipped). |
| **Supabase Postgres** | `backend/supabase/config.toml`<br>`backend/supabase/migrations/` (21 migrations: `20260923000001` through `20261008000002`)<br>`backend/supabase/functions/` (`sync-to-firestore`, `auth-otp`) | Migration schema inspection, RLS SQL review, Edge Function AST inspection. |
| **Security Rules** | `backend/firestore.rules` (1,398 lines)<br>`backend/storage.rules`<br>`backend/firestore.indexes.json` | Firebase Emulator Rules Suite (`npm run test:all-rules` - 174 passing). |
| **Config & Secrets** | `.firebaserc`, `backend/functions/.env.example`<br>`docs/DEPLOY_CHECKLIST.md`, `docs/SECRET_ROTATION_CHECKLIST.md` | Verification of env names, Secret Manager bindings, and `.gitignore` coverage. |

---

## 3. Architecture As-Built Diagram

```mermaid
flowchart TD
  subgraph Client["Flutter Client (Android / iOS / Web)"]
    UI["Unified Auth & Feature Screens"]
    ROTP["RegistrationOtpService"]
    FAuth["FirebaseAuth (Custom Token)"]
    FS_Client["Cloud Firestore Client"]
    S3_Client["S3 Presign Client (use_s3_storage flag)"]
    SB_Client["Supabase Client (ENABLE_SUPABASE flag)"]
  end

  subgraph CloudFunctions["Firebase Cloud Functions v2 (asia-south1)"]
    CF_OTP["registration_otp (MSG91 SMS)"]
    CF_Appt["appointment_slots (book & reschedule)"]
    CF_S3["s3_storage (Presigned URLs)"]
    CF_Ads["promoted_ads (Razorpay Order/Verify)"]
    CF_Del["delete_my_account (Cascade Cleanup)"]
  end

  subgraph Databases["Primary Data Stores"]
    FS_DB[("Cloud Firestore\n(asia-south2 / Delhi)")]
    S3_Bucket[("AWS S3 Private Bucket\n(ap-south-1 / Mumbai)")]
    Redis_Cloud[("Redis Cloud (Fail-Open Cache)\nRATE_LIMIT_BACKEND / S3_URL_CACHE")]
    SB_DB[("Supabase PostgreSQL DRNECT-DB\n(RLS via Firebase JWT sub)")]
  end

  subgraph External["External Third-Party APIs"]
    MSG91["MSG91 SMS DLT Gateway"]
    Razorpay["Razorpay Gateway"]
  end

  %% Client Wiring
  UI --> ROTP
  ROTP --> CF_OTP
  CF_OTP --> MSG91
  CF_OTP -- "Mints Custom Token" --> FAuth
  FAuth --> FS_Client
  FS_Client <-->|Primary Read/Write Path| FS_DB

  UI --> S3_Client
  S3_Client --> CF_S3
  CF_S3 --> S3_Bucket

  UI --> CF_Ads
  CF_Ads --> Razorpay

  %% Supabase Staged Path
  UI -.->|Dormant in Release Build| SB_Client
  SB_Client -.->|Fails 42501 (No public.users row)| SB_DB

  %% Sync Bridge
  FS_DB -.->|"sync*ToSupabase (NOT DEPLOYED)"| SB_DB
  SB_DB -.->|"sync-to-firestore (EMPTY STUB)"| FS_DB
```

### Role-by-Role Runtime Summary (Release Build)

| Role | Auth Mechanism | Primary Database | File Storage | Payment / Promoted |
|:---|:---|:---|:---|:---|
| **Patient** | MSG91 OTP -> Firebase Custom Token | Cloud Firestore (`asia-south2`) | Firebase Storage (S3 if flagged) | Free (No payments) |
| **Doctor** | MSG91 OTP -> Firebase Custom Token | Cloud Firestore (`asia-south2`) | Firebase Storage (S3 if flagged) | Razorpay -> Ads (Stuck pending) |
| **Pharmacy** | MSG91 OTP -> Firebase Custom Token | Cloud Firestore (`asia-south2`) | Firebase Storage (S3 if flagged) | Razorpay -> Ads (Stuck pending) |
| **Lab** | MSG91 OTP -> Firebase Custom Token | Cloud Firestore (`asia-south2`) | Firebase Storage (S3 if flagged) | Razorpay -> Ads (Stuck pending) |
| **Ambulance** | Mobile: OTP Callable / Web: HTTP PIN | Cloud Firestore (`asia-south2`) | Firebase Storage (S3 if flagged) | Razorpay -> Ads (Stuck pending) |

---

## 4. Service-by-Service Verification (Part 1)

### 4.1 Firebase Auth
- **Client Init & Config:** `frontend/lib/core/firebase/firebase_bootstrap.dart:25-95` initializes Firebase via platform options. Secrets are loaded from gitignored `firebase_options.secrets.dart`.
- **Call Sites:** `frontend/lib/core/auth/registration_otp_service.dart:94,170,237,270` calls `sendUserRegistrationOtp`, `verifyUserRegistrationOtp`, `completeMobileOtpLogin`, and `completeAmbulanceMobileOtpLogin`.
- **Token Verification & Claims:** `backend/functions/registration_otp.js` mints Firebase custom tokens with `{ role, app_role, role_normalized }` and Supabase-compatible `{ role: 'authenticated' }`.
- **One-Mobile-One-Role Rule:** `registration_otp.js:findUserByMobileDigits` prevents duplicate registrations. `backend/firestore.rules:411-447` validates `profile_claims` ensuring 1:1 mobile-to-profile mapping.
- **Role Enforcement in Rules:** `backend/firestore.rules:66-68` evaluates `role()` from Firestore document `users/{uid}.role`, strictly independent of client-supplied claims.
- **Account Deletion:** `backend/functions/delete_my_account.js:40-120` deletes the Firebase Auth user (`admin.auth().deleteUser(uid)`) and cascades deletion across Firestore collections, S3 prefixes, and Supabase tables.

### 4.2 Supabase PostgreSQL
- **Client Init:** `frontend/lib/core/supabase/supabase_bootstrap.dart:141-188` safely no-ops unless compiled with `--dart-define=SUPABASE_URL=...` and `SUPABASE_ANON_KEY=...`.
- **Identity & JWT Mapping:** `backend/supabase/config.toml:344-346` enables Firebase third-party provider for project `medibond-45fad`. `supabase_bootstrap.dart:165` passes `accessToken: currentFirebaseAccessToken`.
- **The Identity Gap (C-1):** In `backend/supabase/migrations/20261008000001_firebase_uid_identity.sql:12-20`, `current_firebase_uid()` extracts `auth.jwt() ->> 'sub'`. Line 32 queries `SELECT role FROM public.users WHERE firebase_uid = ...`. However, **no service or trigger writes to `public.users` when a user registers in Firebase**. Any execution of `book_appointment_atomic` throws `42501 PROFILE_NOT_FOUND` at line 115.
- **Security Definer Functions:** All key helper functions (`private.current_firebase_uid`, `private.current_profile_id`, `private.is_super_admin`) have permissions revoked from `PUBLIC, anon` and granted to `authenticated, service_role`.
- **Reverse Sync Bridge (C-2):** `backend/supabase/functions/sync-to-firestore/index.ts:34-38` parses incoming webhook payloads but terminates with `{ success: true }` without performing any Firestore write.

### 4.3 Redis Cloud
- **Connection & TLS:** `backend/functions/src/config/redis.js:15-60` initializes `ioredis` with TLS support (enabled when port is 6380 or protocol is `rediss://`). Secrets `REDIS_HOST`, `REDIS_PORT`, `REDIS_PASSWORD` are managed in Secret Manager.
- **Fail-Open Behavior:** All Redis calls in `abuse_rate_limit.js:80-140` and `s3_storage.js:710-740` are protected by try-catch blocks. If Redis disconnects or throws `ECONNREFUSED`, rate limiting soft-falls back to Firestore, and S3 presigns generate directly without caching.
- **TTLs:** Every key written to Redis enforces an explicit TTL:
  - Rate limiting (`ratelimit:{category}:{hash}`): Millisecond TTL via `PEXPIRE`.
  - S3 Presign cache (`s3url:{key}:{purpose}`): `expiresIn - 900` seconds.
  - OTP Mirror (`otp_mirror:{role}:{mobileDigits}`): 600 seconds.
- **Zero Business Data in Redis:** Redis is strictly used as an ephemeral cache; no source-of-truth records reside in Redis.

### 4.4 AWS S3
- **Presigned URL Callables:** `backend/functions/s3_storage.js` exports `getS3UploadUrl`, `getS3DownloadUrl`, `getS3DownloadUrls`, and `deleteS3Object`. Region defaults to `ap-south-1`, bucket to `doctornect`.
- **Validation:** Strict content-type validation (`image/jpeg`, `image/png`, `image/webp`, `application/pdf`). Size capped at 5 MB for profile images, 15 MB for clinical documents.
- **Path Authorization:** S3 prefixes are strictly segmented by purpose and owner (`patients/{uid}/profile/`, `doctor_profiles/{uid}/`, `health_records/{patientId}/`, `lab_reports/{labId}/`). Unauthorized requests are rejected server-side.
- **Feature Flag Gating:** Gated behind Remote Config `use_s3_storage` (default `false` in `frontend/lib/core/firebase/storage_feature_flag.dart`). Active client operations route to Firebase Storage.

### 4.5 Cloud Functions v2 Inventory
All callables run in `asia-south1` (Mumbai). All Firestore triggers run in `asia-south2` (Delhi) matching the database location.

| Function Name | Trigger Type | Region | App Check Enforced | Live in Cloud Run? | Client Call Site |
|:---|:---|:---|:---|:---|:---|
| `sendUserRegistrationOtp` | Callable | `asia-south1` | Yes (`ENFORCE_OTP_APP_CHECK`) | **Live** | `registration_otp_service.dart:94` |
| `verifyUserRegistrationOtp` | Callable | `asia-south1` | Yes (`ENFORCE_OTP_APP_CHECK`) | **Live** | `registration_otp_service.dart:170` |
| `completeMobileOtpLogin` | Callable | `asia-south1` | Yes (`ENFORCE_OTP_APP_CHECK`) | **Live** | `registration_otp_service.dart:237` |
| `completeAmbulanceMobileOtpLogin` | Callable | `asia-south1` | Yes (`ENFORCE_OTP_APP_CHECK`) | **Live (Stale version)** | `registration_otp_service.dart:270` |
| `verifyAmbulanceDriverLoginHttp` | HTTPS | `asia-south1` | No (PIN-only) | **Live** | `ambulance_callable_client.dart:26` |
| `getValidationRulesHttp` | HTTPS | `asia-south1` | No (Public metadata) | **Live** | Unused / Ops |
| `getS3UploadUrl` | Callable | `asia-south1` | Yes (`ENFORCE_ABUSE_APP_CHECK`) | **Live** | `s3_presign_api.dart:35` |
| `getS3DownloadUrl` | Callable | `asia-south1` | Yes (`ENFORCE_ABUSE_APP_CHECK`) | **Live** | `s3_presign_api.dart:82` |
| `getS3DownloadUrls` | Callable | `asia-south1` | Yes (`ENFORCE_ABUSE_APP_CHECK`) | **Live** | `s3_presign_api.dart:110` |
| `deleteS3Object` | Callable | `asia-south1` | Yes (`ENFORCE_ABUSE_APP_CHECK`) | **Live** | `s3_presign_api.dart:138` |
| `createRazorpayOrder` | Callable | `asia-south1` | Yes | **Live** | `promoted_ads_service.dart:271` |
| `verifyRazorpayPayment` | Callable | `asia-south1` | Yes | **Live** | `promoted_ads_service.dart:289` |
| `reviewPromotedAd` | Callable | `asia-south1` | Yes | **Live** | Admin UI (Not wired in release nav) |
| `razorpayWebhook` | HTTPS | `asia-south1` | No (HMAC Signature) | **Live** | Razorpay Dashboard Webhook |
| `expirePromotedAds` | Scheduled | `asia-south1` | N/A | **Live** | Cloud Scheduler |
| `deleteMyAccount` | Callable | `asia-south1` | Yes | **Live** | `unified_account_service.dart:58` |
| `bookAppointment` | Callable | `asia-south1` | Yes | **Live** | `booking_flow_screen.dart:720` |
| `rescheduleAppointment` | Callable | `asia-south1` | Yes | ❌ **NOT DEPLOYED** | `appointment_callable_client.dart:45` |
| `notifyNewAppointment` | Firestore | `asia-south2` | N/A | **Live** | Event-driven trigger |
| `reconcileAppointmentSlot` | Firestore | `asia-south2` | N/A | **Live** | Event-driven trigger |
| `sync*ToSupabase` (16 funcs) | Firestore | `asia-south2` | N/A | ❌ **NOT DEPLOYED** | Gated by `ENABLE_SUPABASE_SYNC=on` |
| `ssrmedibond45fad` | HTTPS | `us-central1` | N/A | **Live** | App Hosting Web Frontend |

### 4.6 MSG91, Email, Razorpay, Remote Config, App Check
- **MSG91:** Server-side auth key bound via Secret Manager (`MSG91_AUTHKEY` / `MSG91_AUTH_KEY`). DLT sender header defaults to `DRNECT`. No client exposure.
- **Email:** `sendMsg91EmailCallable` exists in backend. Client Patient Help routes via device `mailto:`.
- **Razorpay:** Server verifies plan amounts against immutable server table (`AD_PRICING_TABLE`). `RAZORPAY_WEBHOOK_SECRET` must be set in Secret Manager.
- **App Check:** Integrated on Flutter client (`firebase_app_check`). Callables assert validity via `assertAppCheck`.
- **Remote Config:** Active parameter `use_s3_storage` (default `false`).

---

## 5. Per-Role End-to-End Matrix (Part 2)

| Lifecycle & Feature Step | Patient | Doctor | Pharmacy | Lab | Ambulance | Evidence (`file:line`) |
|:---|:---:|:---:|:---:|:---:|:---:|:---|
| **Registration -> OTP** | ✅ | ✅ | ✅ | ✅ | ✅ | `registration_otp_service.dart:94` |
| **Verify OTP -> Login** | ✅ | ✅ | ✅ | ✅ | ⚠️ | `registration_otp_service.dart:170,237`<br>Ambulance relies on stale callable |
| **`profileCompleted` Gating** | ➖ (Default true) | ✅ | ✅ | ✅ | ✅ | `doctor_shell.dart:179`<br>`medical_store_shell.dart:60`<br>`lab_shell.dart:41`<br>`ambulance_shell.dart:69` |
| **Admin Verification Gate** | ➖ | ✅ | ⚠️ | ⚠️ | ⚠️ | `doctor_verification_gate.dart:66`<br>Others guarded by `ProfileActionGuard` |
| **Profile & Photo Upload** | ✅ | ✅ | ➖ | ➖ | ➖ | `profile_photo_uploader.dart:48` |
| **Core Feature 1: Appointments / Requests** | ✅ | ✅ | ➖ | ➖ | ✅ | `booking_flow_screen.dart:720`<br>`appointment_repository.dart:34`<br>`ambulance_repository.dart:120` |
| **Core Feature 2: Prescriptions / Deliveries** | ✅ | ✅ | ✅ | ➖ | ➖ | `clinical_prescription_store.dart:259`<br>`pharmacy_deliveries` collection |
| **Core Feature 3: Records / Reports** | ✅ | ➖ | ➖ | ✅ | ➖ | `add_record_screen.dart:40`<br>`lab_bookings` collection |
| **Reschedule Appointment** | ⚠️ | ⚠️ | ➖ | ➖ | ➖ | ⚠️ Callable not deployed in backend |
| **Cross-Role: Doctor Rx -> Patient View** | ✅ | ✅ | ➖ | ➖ | ➖ | Dual read/write on Firestore `prescriptions` |
| **Cross-Role: Lab Report -> Patient View** | ✅ | ➖ | ➖ | ✅ | ➖ | Dual read/write on Firestore `lab_bookings` |
| **Cross-Role: Patient Booking -> Doctor View** | ✅ | ✅ | ➖ | ➖ | ➖ | Dual read/write on Firestore `appointments` |
| **Promote / Ads Creation** | ➖ (Forbidden) | ⚠️ | ⚠️ | ⚠️ | ⚠️ | `promoted_ads_service.dart:271`<br>Ads stuck in `pending_approval` |
| **In-App Notifications** | ✅ | ✅ | ✅ | ✅ | ✅ | Firestore `notifications` collection |
| **Support / Help Tickets** | ✅ | ✅ | ✅ | ✅ | ✅ | Device `mailto:` in `about_screen.dart` |
| **Delete Account Cascade** | ✅ | ✅ | ✅ | ✅ | ✅ | `delete_my_account.js:40-120` |

*Legend: ✅ Working as expected | ⚠️ Partial / Blocked on un-deployed item | ❌ Broken | ➖ Not Applicable by design*

---

## 6. Cross-Cutting Findings (Part 3)

### Data Consistency
- **Split-Brain Risk on Supabase Activation:** `booking_flow_screen.dart:701-736` performs a dual-write: first to Supabase (`book_appointment_atomic`), then to Firestore. Conversely, `shared_appointments_store.dart:814-832` cancels appointments on Supabase **without persisting to Firestore**. Because `sync-to-firestore` is an empty stub, doctor calendars on Firestore will never receive patient cancellations if Supabase is active.
- **Seven Entities Lack Sync Logic:** Entities `users`, `patients`, `reviews`, `promoted_ads`, `health_records`, `community_*` catalogs, and `support_tickets` have zero synchronization handlers in `cross_role_sync.js`.

### Security Parity & Rule Enforcement
- **Client Appointment Creates:** `backend/firestore.rules:535` still permits client `create` operations on `appointments` to maintain backwards compatibility with older client builds. Client create should be locked down to `bookAppointment` callable only after adoption threshold is met (`docs/DEPLOY_CHECKLIST.md:61-71`).
- **Promoted Ads Public Read:** `backend/firestore.rules:1222-1224` allows `read: if true;`, allowing unauthenticated queries to inspect draft and pending campaign metadata unless filtered in client queries.
- **Git History Secrets:** While `.gitignore:111-112` properly excludes `.env*`, `secrets*.txt`, and service-account files, historical commit `317af8d` ancestors contained local secret dumps. Credentials must be verified as rotated (`docs/SECRET_ROTATION_CHECKLIST.md`).

### Performance & Optimization
- **UI Tree Layout Cost:** 17 instances of `shrinkWrap: true` inside nested `ListView` / `GridView` structures across patient and doctor modules, risking micro-jank on lower-end Android hardware.
- **Cross-Region Latency:** Client callables execute in `asia-south1` (Mumbai), but Cloud Firestore triggers and storage execute in `asia-south2` (Delhi), introducing ~25ms inter-region hop latency on every trigger execution.
- **Web App Bundle Size:** Total web distribution bundle is 81.67 MB; `main.dart.js` is 7.85 MB uncompressed with no deferred module loading.

### Reliability & Error Handling
- **Graceful Fallbacks:** Supabase Bootstrap fails silently without crash (`supabase_bootstrap.dart:180-187`). Redis client soft-falls back to Firestore on connection drop.
- **Missing Cloud Function Error Code:** Calling `rescheduleAppointment` on release builds produces `FirebaseFunctionsException(code: not-found)`.

---

## 7. Comprehensive Findings Table

| ID | Severity | Area | Affected Roles | Evidence (`file:line`) | Why It Matters | Recommended Fix | Effort |
|:---|:---|:---|:---|:---|:---|:---|:---:|
| **C-1** | **Critical** | Identity | Patient | `backend/supabase/migrations/20261008000001_firebase_uid_identity.sql:98-117`<br>`backend/functions/cross_role_sync.js` | With `ENABLE_SUPABASE=1`, `book_appointment_atomic` throws `42501 PROFILE_NOT_FOUND` because `public.users` row is never created. | Build a Cloud Function trigger on `users/{uid}` create that inserts into Supabase `public.users` with `firebase_uid`. | M |
| **C-2** | **Critical** | Sync | Patient, Doctor | `backend/supabase/functions/sync-to-firestore/index.ts:34-38`<br>`shared_appointments_store.dart:814-832` | Reverse sync is an empty stub. Patient cancellations on Supabase never reach doctor Firestore calendars. | Implement Firestore write in `sync-to-firestore` Edge Function or remove Supabase-only cancel. | L |
| **C-3** | **Critical** | Sync | All Roles | `backend/functions/cross_role_sync.js:169-190`<br>`backend/functions/index.js:1962-1967` | Un-deployed sync triggers overwrite appointment fields with default placeholders (`age \|\| 30`, `token \|\| 1`). | Remove fallback placeholders and assert real doc attributes before deploying sync triggers. | M |
| **H-1** | **High** | Functions | Patient, Doctor | `backend/functions/appointment_slots.js:680-720`<br>`docs/DEPLOY_CHECKLIST.md:32` | `rescheduleAppointment` is not deployed in Cloud Functions. Patient reschedule throws `functions/not-found`. | Deploy `rescheduleAppointment` by name via Firebase CLI. | S |
| **H-2** | **High** | Auth | Ambulance | `backend/firestore.rules:1148-1156`<br>`frontend/lib/core/firebase/repositories/ambulance_repository.dart:89` | Deployed `completeAmbulanceMobileOtpLogin` lacks server-side `authUid` link. Client update throws `permission-denied` on device swap. | Deploy updated `completeAmbulanceMobileOtpLogin` from commit `5936b7f`. | S |
| **H-3** | **High** | Payments | Providers | `backend/functions/promoted_ads.js:35-41,148-152`<br>`create_promoted_ad_screen.dart:128-130` | Paid ads get stuck in `pending_approval` because no admin UI is wired to call `reviewPromotedAd`. | Wire `promoted_ad_review_screen.dart` into super admin navigation. | M |
| **H-4** | **High** | Rules | All Roles | `backend/firestore.rules:1222-1224` | `promotedAds` read rule allows unrestricted read access to draft and pending campaigns. | Restrict `allow read` to `resource.data.status == 'active'` or document owner. | S |
| **H-5** | **High** | Secrets | Ops / Backend | `backend/functions/promoted_ads.js:26`<br>`docs/DEPLOY_CHECKLIST.md:24` | `RAZORPAY_WEBHOOK_SECRET` is not set in Secret Manager. Webhook calls fail with HTTP 503. | Create secret in Secret Manager via `firebase functions:secrets:set`. | S |
| **M-1** | **Medium** | Config Drift | Backend | `backend/functions/.env.example:15-18`<br>`secure_config.js:25` | Environment variable name drift: `MSG91_AUTH_KEY` vs `MSG91_AUTHKEY`; `SUPABASE_SECRET_KEY` vs `SUPABASE_SERVICE_ROLE_KEY`. | Normalize environment variable names across `.env` and Secret Manager. | S |
| **M-2** | **Medium** | Storage | Providers | `backend/functions/s3_storage.js:613-623`<br>`storage_feature_flag.dart` | KYC upload purposes for pharmacy, lab, and ambulance in S3 are not deployed; client remains on Firebase Storage. | Keep `use_s3_storage` disabled until all provider KYC purposes are deployed. | M |
| **M-3** | **Medium** | Security | Admin | `backend/supabase/migrations/20261008000002_super_admin_from_admin_users.sql` | Migration decoupling super admin from hardcoded emails must be applied on live database. | Verify migration execution on hosted Supabase project DRNECT-DB. | S |
| **M-4** | **Medium** | Performance | Web | `build/web/main.dart.js`<br>`frontend/pubspec.yaml` | Web distribution bundle is 81.67 MB with uncompressed 7.85 MB JS bundle. | Enable deferred component imports and convert uncompressed icon PNGs to WebP. | M |
| **L-1** | **Low** | UI / Leaks | Patient | `notifications_settings_screen.dart:54` | `TextEditingController` inside dialog is not disposed on close. | Call `.dispose()` in State lifecycle. | S |
| **L-2** | **Low** | Code Health | Patient | `patient_profile_mock.dart:623-624` | Unused placeholder support constants. | Remove unused constants. | S |

---

## 8. Prioritized Fix Plan

### Phase 1: Pre-Release Blockers (Must Fix Before Launch)

#### Prompt 1.1: Deploy Missing Callable & Server-Side Ambulance Link (H-1, H-2)
```markdown
Run the following deployment commands to deploy the missing `rescheduleAppointment` callable and update `completeAmbulanceMobileOtpLogin` with server-side `authUid` linking:
```powershell
firebase deploy --project medibond-45fad --only functions:rescheduleAppointment,functions:completeAmbulanceMobileOtpLogin
```
Do NOT modify source files or deploy any other functions.
```

#### Prompt 1.2: Set Razorpay Webhook Secret & Tighten Ad Rules (H-4, H-5)
```markdown
Scope: Change only `backend/firestore.rules` around lines 1222-1224 and configure the Secret Manager parameter.
1. In `backend/firestore.rules`, update match `/promotedAds/{adId}` so read is allowed only if:
   `resource.data.status == 'active' || (isSignedIn() && resource.data.providerId == request.auth.uid) || isSuperAdmin();`
2. Run `firebase functions:secrets:set RAZORPAY_WEBHOOK_SECRET --project medibond-45fad` with the webhook secret from Razorpay dashboard.
3. Deploy rules: `firebase deploy --project medibond-45fad --only firestore:rules`.
```

### Phase 2: Provider Workflows & Admin Wiring (H-3, M-1)

#### Prompt 2.1: Wire Promoted Ad Admin Review Screen (H-3)
```markdown
Scope: Change only `frontend/lib/features/admin/super_admin_verification_screen.dart` and admin navigation routing.
Add an action card or navigation item for Super Admins to navigate to `PromotedAdReviewScreen` (`frontend/lib/features/admin/promoted_ad_review_screen.dart`), allowing approval/rejection of pending campaigns via `reviewPromotedAd`.
```

### Phase 3: Supabase Architecture Cutover (C-1, C-2, C-3)

#### Prompt 3.1: Supabase User Sync & Identity Bridge (C-1, C-2)
```markdown
Scope: Implement `syncUserToSupabase` in `backend/functions/cross_role_sync.js` and implement Firestore write in `backend/supabase/functions/sync-to-firestore/index.ts`.
1. In `backend/functions/cross_role_sync.js`, add a Firestore trigger on `users/{uid}` that upserts `public.users` in Supabase with `firebase_uid = uid`, `role`, and `profile_id`.
2. In `backend/supabase/functions/sync-to-firestore/index.ts`, implement the Firestore Admin SDK write for appointment cancellations with `syncedBy: 'supabase_bridge'`.
Do NOT enable `ENABLE_SUPABASE=1` in release builds until end-to-end integration tests verify this flow.
```

---

## 9. UNVERIFIED Items / Manual Checklist

The following items cannot be fully verified through static analysis and require manual console or physical device inspection:

| Item | Service / Location | What to Check |
|:---|:---|:---|
| **Supabase Migrations Execution** | Supabase Dashboard (`DRNECT-DB`) | Verify that migrations `20261008000001` and `20261008000002` have been applied under Database -> Migrations. |
| **Supabase Third-Party Auth** | Supabase Auth Dashboard | Confirm Firebase Auth is toggled ON under Authentication -> Providers -> Third-Party Auth with project ID `medibond-45fad`. |
| **AWS S3 Bucket & IAM** | AWS Console (`ap-south-1`) | Verify bucket `doctornect` exists, Block Public Access is ON, CORS allows `doctornect.com`, and IAM user matches credentials in Secret Manager. |
| **Remote Config Value** | Firebase Console -> Remote Config | Verify `use_s3_storage` is explicitly set to `false` for initial rollout. |
| **App Check Attestation** | Firebase Console -> App Check | Check whether App Check enforcement is set to "Enforce" or "Monitor" for Cloud Functions callables and Firestore. |
| **Secret Rotation Completeness** | Operator Audit | Confirm that all legacy credentials from earlier commits (MSG91, Razorpay, Firebase service account) have been rotated per `docs/SECRET_ROTATION_CHECKLIST.md`. |
| **App Hosting SSR Container** | Firebase Console -> App Hosting | Confirm `ssrmedibond45fad` (`us-central1`) is running healthy and is NOT deleted during function deployments. |
| **End-to-End Device Smoke Test** | Physical Device (Android/iOS) | Perform a live booking with `ENABLE_SUPABASE` unset: Patient books -> Doctor confirms -> Patient cancels. Verify both parties see real-time updates. |
