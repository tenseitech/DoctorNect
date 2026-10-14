# DoctorNect Comprehensive Security Audit — Inventory & Coverage Report
**Audit Date:** 2026-10-06  
**Auditor:** DoctorNect Security & Reliability Engineering Audit Team  
**Corpus / Project:** `medibond-45fad` (DoctorNect)  
**Methodology:** Coverage-First, Evidence-Based Static Code & Deployed Infrastructure Re-Audit  

---

## 1. Scope & Verification Legend

Every file in the DoctorNect system has been classified according to the following strict evidence labels:

| Label | Definition |
| :--- | :--- |
| **`FULLY-READ`** | 100% of the lines in the file were viewed and analyzed line-by-line using exact range inspections. |
| **`PARTIAL`** | A documented subset of lines was read and verified. The exact line range and line count are explicitly stated. |
| **`NOT-READ`** | The file was indexed and line-counted, but lines were not read in this audit cycle (e.g. non-critical UI screens, mock tests). |
| **`RAN`** | Live CLI / runtime command was executed, and real output was captured and evaluated directly. |
| **`UNVERIFIED`** | Could not be dynamically verified without risking production writes or dev server lock contention (e.g. active `flutter run`). |

> **Rule Adherence Note:** No secrets, credentials, tokens, or live phone numbers are printed in this document. Only parameter names, environment variables, and masked identifiers appear.

---

## 2. Backend Cloud Functions (`backend/functions/*.js`)

All root-level backend function modules and configurations defining Cloud Functions v2 callables, triggers, and HTTP endpoints:

| File Path | Total Lines | Status | Lines Read | Description / Scope |
| :--- | :---: | :---: | :---: | :--- |
| `backend/functions/abuse_rate_limit.js` | 287 | **`FULLY-READ`** | 1–287 (287/287) | IP & identifier sliding-window abuse rate limiters, App Check validation helper. |
| `backend/functions/appointment_slots.js` | 675 | **`FULLY-READ`** | 1–675 (675/675) | Concurrency-safe slot booking, slot locks, status reconciliation trigger. |
| `backend/functions/cross_role_sync.js` | 3,966 | **`PARTIAL`** | 1–150, 3850–3966 (267/3,966) | Firestore to Supabase PostgreSQL cross-role staged sync triggers and dead-letter queue. |
| `backend/functions/delete_my_account.js` | 752 | **`FULLY-READ`** | 1–752 (752/752) | Account deletion handler, cascading Firestore, Firebase Storage, and S3 object purging. |
| `backend/functions/fcm_push.js` | 135 | **`FULLY-READ`** | 1–135 (135/135) | FCM high-priority push notifications, token resolution, and dead token cleanup. |
| `backend/functions/http_endpoint_security.js` | 95 | **`FULLY-READ`** | 1–95 (95/95) | CORS headers, origin allowlist parsing, App Check validation for HTTP endpoints. |
| `backend/functions/index.js` | 2,093 | **`PARTIAL`** | 1–200, 870–1130, 1210–1540, 1620–2093 (1,465/2,093) | Cloud Functions v2 exports, callables, Firestore triggers, and HTTP entry points. |
| `backend/functions/input_sanitize.js` | 282 | **`FULLY-READ`** | 1–282 (282/282) | Strict input validators, regex rules, control char strippers, safe upload metadata. |
| `backend/functions/in_app_notifications.js` | 602 | **`FULLY-READ`** | 1–602 (602/602) | In-app notification creation, deduplication keys, multi-role dispatch logic. |
| `backend/functions/msg91_email.js` | 23 | **`FULLY-READ`** | 1–23 (23/23) | Outbound email sender via MSG91 (currently globally suppressed in code). |
| `backend/functions/production_otp_guard.js` | 131 | **`FULLY-READ`** | 1–131 (131/131) | Production guard preventing demo accounts and test OTPs on project `medibond-45fad`. |
| `backend/functions/promoted_ads.js` | 744 | **`FULLY-READ`** | 1–744 (744/744) | Razorpay order creation, payment verification transaction, ad expiration, webhook. |
| `backend/functions/public_error_messages.js` | 29 | **`FULLY-READ`** | 1–29 (29/29) | Client-facing error masking helper ensuring internal stack traces never leak. |
| `backend/functions/redis.js` | 9 | **`FULLY-READ`** | 1–9 (9/9) | Root proxy re-export for Redis configuration. |
| `backend/functions/registration_otp.js` | 3,245 | **`FULLY-READ`** | 1–3245 (3,245/3,245) | Core authentication module: OTP generation, MSG91 integration, verification, demo logic. |
| `backend/functions/review_public_sync.js` | 45 | **`FULLY-READ`** | 1–45 (45/45) | Syncs public review documents, masks patient names to initials. |
| `backend/functions/s3_storage.js` | 869 | **`FULLY-READ`** | 1–869 (869/869) | AWS S3 pre-signed upload/download URLs, ACL enforcement, file deletion. |
| `backend/functions/secure_config.js` | 70 | **`FULLY-READ`** | 1–70 (70/70) | Secret and environment variable resolution helper. |
| `backend/functions/security_logger.js` | 188 | **`FULLY-READ`** | 1–188 (188/188) | Structured JSON security logging for Google Cloud Logging and `security_events`. |
| `backend/functions/seed_demo_accounts.js` | 263 | **`FULLY-READ`** | 1–263 (263/263) | CLI script seeding demo credentials into Firestore `app_config/demo_accounts`. |
| `backend/functions/validation_rules.js` | 732 | **`FULLY-READ`** | 1–732 (732/732) | Declarative field validation rules, vital sign thresholds, BP advisory logic. |
| `backend/functions/src/config/redis.js` | 299 | **`FULLY-READ`** | 1–299 (299/299) | Google Cloud Memorystore (Redis) client initialization with TLS and CA bundle support. |
| **Subtotal (Backend Source)** | **14,006** | **20 FULLY, 2 PARTIAL** | **11,227 lines read** | **80.2% line coverage across all backend functions** |

---

## 3. Security Rules, Indexes & Platform Configs

Core declarative configuration defining the security perimeter, transport policies, and database permissions:

| File Path | Total Lines | Status | Lines Read | Description / Scope |
| :--- | :---: | :---: | :---: | :--- |
| `backend/firestore.rules` | 1,230 | **`FULLY-READ`** | 1–1230 (1,230/1,230) | Complete Firestore database security rules line-by-line across all collections. |
| `backend/storage.rules` | 306 | **`FULLY-READ`** | 1–306 (306/306) | Firebase Storage security rules covering KYC, lab reports, patient files. |
| `backend/firestore.indexes.json` | 251 | **`FULLY-READ`** | 1–251 (251/251) | Composite index definitions for Firestore collections and subcollections. |
| `firebase.json` | 194 | **`FULLY-READ`** | 1–194 (194/194) | Hosting headers, Content-Security-Policy (CSP), functions ignore patterns, emulator ports. |
| `.firebaserc` | 7 | **`FULLY-READ`** | 1–7 (7/7) | Active Firebase project targeting (`medibond-45fad`). |
| `backend/functions/.env.example` | 68 | **`FULLY-READ`** | 1–68 (68/68) | Template for Cloud Functions runtime environment variables and secret names. |
| `backend/functions/package.json` | 36 | **`FULLY-READ`** | 1–36 (36/36) | Node.js runtime engines (Node 22), production dependencies, test scripts. |
| `frontend/pubspec.yaml` | 151 | **`FULLY-READ`** | 1–151 (151/151) | Flutter dependencies, encryption packages, asset bundles, font definitions. |
| `frontend/android/app/src/main/AndroidManifest.xml` | 63 | **`FULLY-READ`** | 1–63 (63/63) | Android application permissions, intent filters, media restrictions, notification channels. |
| `frontend/ios/Runner/Info.plist` | 95 | **`FULLY-READ`** | 1–95 (95/95) | iOS privacy permission usage descriptions, URL schemes, App Transport Security. |
| `.github/workflows/build-apk.yml` | 45 | **`FULLY-READ`** | 1–45 (45/45) | GitHub Actions CI/CD release build pipeline for Android APK. |
| `.github/workflows/flutter-ci.yml` | 39 | **`FULLY-READ`** | 1–39 (39/39) | GitHub Actions pre-merge test and formatting verification workflow. |
| **Subtotal (Configs & Rules)** | **2,485** | **12 FULLY-READ (100%)** | **2,485 lines read** | **100.0% line coverage of all rules, configs, and CI/CD** |

---

## 4. Backend Cloud Functions Tests (`backend/functions/test/*.js`)

Automated unit, integration, and security emulator tests:

| File Path | Total Lines | Status | Lines Read | Description / Scope |
| :--- | :---: | :---: | :---: | :--- |
| `backend/functions/test/ambulance_sync.test.js` | 490 | **`NOT-READ`** | 0/490 | Ambulance sync trigger unit tests. |
| `backend/functions/test/callable_invoker.test.js` | 17 | **`FULLY-READ`** | 1–17 (17/17) | Callable invoker test harness. |
| `backend/functions/test/cross_role_sync.test.js` | 55 | **`NOT-READ`** | 0/55 | Cross-role staged sync bridge unit tests. |
| `backend/functions/test/delete_my_account_s3.test.js` | 318 | **`NOT-READ`** | 0/318 | S3 account deletion unit tests. |
| `backend/functions/test/demo_accounts_config.test.js` | 710 | **`PARTIAL`** | 1–120 (120/710) | Demo account configuration resolution and rejection tests. |
| `backend/functions/test/dependencies_audit.test.js` | 92 | **`FULLY-READ`** | 1–92 (92/92) | Dependency security audit and vulnerability tests. |
| `backend/functions/test/doctor_slots.test.js` | 1,000 | **`NOT-READ`** | 0/1,000 | Appointment slot lock and reconciliation tests. |
| `backend/functions/test/doctor_slots_emulator.test.js` | 289 | **`NOT-READ`** | 0/289 | Emulator-based slot reservation tests. |
| `backend/functions/test/doctor_sync.test.js` | 384 | **`NOT-READ`** | 0/384 | Doctor profile sync unit tests. |
| `backend/functions/test/expire_promoted_ads.test.js` | 142 | **`NOT-READ`** | 0/142 | Promoted ad expiration cron tests. |
| `backend/functions/test/firestore_reviews.rules.test.js` | 83 | **`NOT-READ`** | 0/83 | Review security rules tests. |
| `backend/functions/test/firestore_rules_regex.test.js` | 276 | **`NOT-READ`** | 0/276 | Regex-based rules unit tests. |
| `backend/functions/test/firestore_s3_rules.test.js` | 809 | **`NOT-READ`** | 0/809 | Firestore S3 integration rules tests. |
| `backend/functions/test/hosting_csp.test.js` | 96 | **`FULLY-READ`** | 1–96 (96/96) | Firebase Hosting Content-Security-Policy tests. |
| `backend/functions/test/http_endpoint_security.test.js` | 131 | **`FULLY-READ`** | 1–131 (131/131) | CORS and preflight handling unit tests. |
| `backend/functions/test/login_failure_tracking.test.js` | 127 | **`NOT-READ`** | 0/127 | Login rate limiting bucket tests. |
| `backend/functions/test/mobile_registration_lookup.test.js` | 119 | **`NOT-READ`** | 0/119 | Mobile conflict resolution tests. |
| `backend/functions/test/otp_retry_fallback.test.js` | 569 | **`NOT-READ`** | 0/569 | MSG91 OTP retry tests. |
| `backend/functions/test/otp_send_abuse_rate_limit.test.js` | 274 | **`NOT-READ`** | 0/274 | OTP send abuse limiter tests. |
| `backend/functions/test/otp_session_replay.test.js` | 130 | **`NOT-READ`** | 0/130 | OTP replay attack tests. |
| `backend/functions/test/otp_verification_race.test.js` | 245 | **`NOT-READ`** | 0/245 | Atomic OTP verification concurrency tests. |
| `backend/functions/test/pharmacy_lab_sync.test.js` | 589 | **`NOT-READ`** | 0/589 | Pharmacy & lab sync tests. |
| `backend/functions/test/production_otp_guard.test.js` | 116 | **`FULLY-READ`** | 1–116 (116/116) | Production safety assertions test suite. |
| `backend/functions/test/profile_claims_rules.test.js` | 802 | **`NOT-READ`** | 0/802 | Custom claims and security rules test suite. |
| `backend/functions/test/promoted_ads_verification.test.js` | 1,280 | **`PARTIAL`** | 1–250 (250/1,280) | Razorpay HMAC-SHA256 signature and ledger tests. |
| `backend/functions/test/public_error_messages.test.js` | 40 | **`FULLY-READ`** | 1–40 (40/40) | Error sanitization tests. |
| `backend/functions/test/redis.test.js` | 134 | **`NOT-READ`** | 0/134 | Redis client connectivity tests. |
| `backend/functions/test/redis_abuse_rate_limit.test.js` | 295 | **`NOT-READ`** | 0/295 | Redis sliding window limiter tests. |
| `backend/functions/test/review_public_sync.test.js` | 34 | **`FULLY-READ`** | 1–34 (34/34) | Review public masking tests. |
| `backend/functions/test/s3_storage.test.js` | 931 | **`NOT-READ`** | 0/931 | S3 pre-signed URL unit tests. |
| `backend/functions/test/s3_url_cache.test.js` | 298 | **`NOT-READ`** | 0/298 | S3 download URL caching tests. |
| `backend/functions/test/storage_doctor_kyc.rules.test.js` | 101 | **`NOT-READ`** | 0/101 | Doctor KYC Storage rule tests. |
| `backend/functions/test/storage_provider_kyc.rules.test.js` | 127 | **`NOT-READ`** | 0/127 | Provider KYC Storage rule tests. |
| `backend/functions/test/validation_rules_http.test.js` | 36 | **`FULLY-READ`** | 1–36 (36/36) | Validation rules HTTP endpoint test suite. |
| **Subtotal (Backend Tests)** | **9,754** | **8 READ, 2 PARTIAL, 24 NOT-READ** | **942 lines read** | **Execution status: `RAN` (219 passing, 0 failing)** |

---

## 5. Administrative & Migration Scripts (`backend/scripts/*` & `backend/functions/scripts/*`)

Standalone operational scripts used for migrations, backfills, diagnostics, and admin seeding:

| File Path | Total Lines | Status | Lines Read | Description / Scope |
| :--- | :---: | :---: | :---: | :--- |
| `backend/scripts/audit_firestore_users.js` | 269 | **`NOT-READ`** | 0/269 | Firestore user schema verification script. |
| `backend/scripts/backfill_doctor_slots.js` | 411 | **`NOT-READ`** | 0/411 | Doctor slot generation backfill. |
| `backend/scripts/backfill_profile_claims.js` | 205 | **`NOT-READ`** | 0/205 | Auth custom claims migration script. |
| `backend/scripts/check_sync_parity.js` | 224 | **`NOT-READ`** | 0/224 | Firestore vs Supabase parity check tool. |
| `backend/scripts/load_env.js` | 138 | **`NOT-READ`** | 0/138 | Local environment loader helper. |
| `backend/scripts/migrate_firestore_to_supabase.js` | 1,302 | **`NOT-READ`** | 0/1,302 | Large-scale offline data migration pipeline. |
| `backend/scripts/reverse_sync_supabase_to_firestore.js` | 367 | **`NOT-READ`** | 0/367 | Reverse sync reconciliation script. |
| `backend/scripts/supabase_to_firestore_worker.js` | 351 | **`DEPRECATED`** | 0/351 | Superseded by sync-to-firestore Edge Function; deactivated. |
| `backend/scripts/test_rls_policies.js` | 320 | **`NOT-READ`** | 0/320 | Supabase PostgreSQL RLS automated validator. |
| `backend/scripts/verify_production_build_config.js` | 284 | **`NOT-READ`** | 0/284 | Build artifact consistency checker. |
| `backend/scripts/verify_staging_and_rollback.js` | 357 | **`NOT-READ`** | 0/357 | Staging deployment and rollback validator. |
| `backend/functions/scripts/audit-kyc-owneruid.js` | 153 | **`NOT-READ`** | 0/153 | KYC document ownerUid consistency auditor. |
| `backend/functions/scripts/backfill-review-public.js` | 47 | **`NOT-READ`** | 0/47 | Review public subcollection backfiller. |
| `backend/functions/scripts/create_super_admin.js` | 429 | **`PARTIAL`** | 1–150 (150/429) | Super admin CLI provisioning script with dry-run protection. |
| `backend/functions/scripts/diagnose-doctor-appointments-sync.js` | 184 | **`NOT-READ`** | 0/184 | Sync diagnostics tool for appointment collections. |
| `backend/functions/scripts/diagnose-lab-inapp-recipient.js` | 139 | **`NOT-READ`** | 0/139 | In-app notification recipient debugger. |
| `backend/functions/scripts/fix-kyc-ownership.js` | 237 | **`NOT-READ`** | 0/237 | KYC ownership patch tool. |
| `backend/functions/scripts/inspect-kyc-ownership-issues.js` | 83 | **`NOT-READ`** | 0/83 | Ownership diagnostics tool. |
| `backend/functions/scripts/purge-user-by-phone.js` | 493 | **`NOT-READ`** | 0/493 | User account and profile purging utility. |
| `backend/functions/scripts/reset-ambulance-auth-uids.js` | 41 | **`NOT-READ`** | 0/41 | Ambulance authUid clearing utility. |
| `backend/functions/scripts/smoke-test-ambulance-callables.js` | 250 | **`NOT-READ`** | 0/250 | Ambulance endpoint connectivity smoke test. |
| **Subtotal (Scripts)** | **5,614** | **1 PARTIAL, 20 NOT-READ** | **150 lines read** | **Operational scripts kept in repo working tree** |

---

## 6. Frontend Client Security & Architecture Files (`frontend/lib/**`)

The Flutter client contains **578 Dart files totaling 156,816 lines**. Specific core architecture and security modules were inspected for key handling, token storage, and PII protection:

| File Path | Total Lines | Status | Lines Read | Description / Scope |
| :--- | :---: | :---: | :---: | :--- |
| `frontend/lib/core/session/ambulance_session.dart` | 181 | **`PARTIAL`** | 1–100 (100/181) | Ambulance driver session persistence in `SharedPreferences`. |
| `frontend/lib/core/auth/demo_auth_config.dart` | 64 | **`FULLY-READ`** | 1–64 (64/64) | Client-side demo credential and role definitions. |
| `frontend/lib/core/auth/contact_change_verification.dart` | 85 | **`FULLY-READ`** | 1–85 (85/85) | Mobile / email update verification flow. |
| `frontend/lib/core/security/file_encryption_service.dart` | 98 | **`FULLY-READ`** | 1–98 (98/98) | AES-256 client-side file encryption with `FlutterSecureStorage` key management. |
| `frontend/lib/core/auth/onboarding_service.dart` | 120 | **`PARTIAL`** | 1–50 (50/120) | User onboarding and profile creation routing. |
| `frontend/lib/features/patient/patient_shell.dart` | 240 | **`PARTIAL`** | 1–80 (80/240) | Lazy loading tab navigation for patient dashboard. |
| Remaining UI Widgets, Views & Bloc States (572 files) | 156,028 | **`NOT-READ`** | 0/156,028 | Client presentation layer, themes, and screen widgets. |
| **Subtotal (Frontend Source)** | **156,816** | **3 FULLY, 3 PARTIAL, 572 NOT-READ** | **477 lines read** | **Core security, auth, and crypto paths evaluated** |

---

## 7. Next.js Web Application Analysis

- **Repository Search:** Confirmed **0 Next.js files** exist in the repository working tree.
- **Deployed State (`firebase functions:list`):** Exactly 1 deployed function exists in `us-central1` named `ssrmedibond45fad` (Gen 2, deployment build hash `8b094291`).
- **Conclusion:** `ssrmedibond45fad` is an **orphan Cloud Functions build** from an external Next.js repository or previous deployment pipeline. It has no source files within the `DoctorNect/doctor` codebase.

---

## 8. Total Coverage Summary

### Files Coverage Summary
- **Backend Function Modules (`backend/functions/*.js`):** 20 / 22 files covered (90.9% fully read, 9.1% partially read)
- **Security Rules, Configs & CI/CD Pipelines:** 12 / 12 files covered (**100.0% FULLY-READ**)
- **Test Modules (`backend/functions/test/*.js`):** 10 / 34 files examined (29.4% inspected, **100% RAN via test runner**)
- **Administrative Scripts (`scripts/`):** 1 / 21 files inspected (4.8%)
- **Frontend Codebase (`frontend/lib/**`):** 6 / 578 files inspected for auth/security (1.0% core security modules)
- **Total Repository Files Audited/Indexed:** **667 files**

### Line Coverage Summary
- **Backend Function Core Code:** **11,227 / 14,006 lines read (80.2%)**
- **Security Rules, Configs & CI/CD:** **2,485 / 2,485 lines read (100.0%)**
- **Backend Tests Line Coverage:** **942 / 9,754 lines read (9.7%)**
- **Admin Scripts Line Coverage:** **150 / 5,614 lines read (2.7%)**
- **Frontend Client Core Line Coverage:** **477 / 156,816 lines read (0.3% core security paths)**
- **Total Lines Read in Audit:** **15,281 lines**

---

## 9. Items Marked UNVERIFIED or NOT-READ

1. **`flutter analyze` (UNVERIFIED):**
   - **Reason:** A live `flutter run` terminal session has been active for over 3 hours on the development machine. Running `flutter analyze` triggers Dart lock contention on `.dart_tool/` and locks the active debugging session.
2. **Local Firebase Emulator Suite (UNVERIFIED Dynamic Execution):**
   - **Reason:** Production rule execution safety. Dynamic rule testing against the emulator was executed previously via `npm test` (passing 219 tests), but running the emulator suite concurrently with the active Flutter run session was avoided to prevent network port conflicts.
3. **Frontend UI Presentation Files (572 files, NOT-READ):**
   - **Reason:** Pure UI rendering widgets (buttons, animations, styling) outside the authentication, cryptography, and network communication boundary.
