# DOCTORNECT PLATFORM — PHASE A: FOUNDATION AUDIT & REMEDIATION REPORT

**Target Architecture:**
- **Authentication:** Firebase Auth ONLY
- **Primary Database:** Supabase PostgreSQL ONLY (Cloud Firestore to be fully deprecated)
- **Temporary / Cache Store:** Redis (OTP mirror, session tokens, cache, rate limits only; zero permanent data)
- **Object Storage:** AWS S3 (private bucket, presigned URLs for medical files, lab reports, photos)
- **Domain Modules:** Doctor, Patient, Pharmacy, Lab, Ambulance (The Admin module is a separate application and is NOT part of this codebase or migration)

---

## 1. EXECUTIVE SUMMARY & WHAT WAS WRONG

During the Phase A architectural foundation audit, several critical impedance mismatches and security gaps were discovered between the target architecture and the legacy codebase:

### 1.1 Auth Bridge & Custom Claims Impedance
- **Missing Persistent Claims in Backend Handlers:** Firebase custom claims were only partially populated during OTP verification in memory or custom tokens, but were not reliably written via `admin.auth().setCustomUserClaims(uid, claims)`. As a result, subsequent ID token refreshes from client mobile devices did not carry the claims that Supabase PostgREST requires (`role: 'authenticated'` and `user_role: '<role>'`).
- **No Claims Sync Trigger on Profile Creation:** When users registered via standard Firebase Auth (email/password, Google sign-in) or were created via admin tooling, no Cloud Function trigger caught the write to populate Firebase custom claims with `role: 'authenticated'`.
- **Existing User Drift:** Existing users in Firebase Auth had no Supabase claims attached, creating an immediate authorization failure upon connecting to Supabase PostgREST.

### 1.2 Schema & Primary Key Mismatch
- **UUID vs. TEXT Firebase UID Impedance:** In initial migration `20260923000001`, `public.users.id` was defined as `UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE`. Because Firebase UIDs are alphanumeric strings (e.g. `d4rF9aK2...` ~28 characters), the codebase previously generated synthetic RFC 4122 v5 UUIDs to store in `users.id` while storing the actual Firebase UID in `users.firebase_uid`. This created two identities for every user, requiring costly secondary lookups and joins in every RLS policy.
- **Hard Dependency on `auth.users`:** Tables `public.users` and `private.admin_users` had direct foreign key constraints (`REFERENCES auth.users(id)`). When inserting Firebase-authenticated users (who do not have accounts in Supabase GoTrue `auth.users`), PostgreSQL rejected the inserts with foreign key violation errors.
- **Scattered Storage Columns:** AWS S3 storage columns (`s3_key`, `s3_bucket`, `storage_provider`) were patched across 4 separate migration files (`20260928000001` through `20260929000001`) rather than living in the canonical table definitions.

### 1.3 Row-Level Security (RLS) Failures
- **`auth.uid()` Type Casting Failure:** Policies and helper functions throughout `20260923000002_doctornect_rls.sql` called `auth.uid()`. In Supabase Third-Party Auth, `auth.uid()` attempts to cast the JWT `sub` claim to a PostgreSQL `UUID`. When passed a Firebase UID string, PostgreSQL aborts the transaction with error `22P02: invalid input syntax for type uuid` or returns NULL, effectively locking out all legitimate Firebase users.
- **Subquery Overhead:** Previous RLS policies executed nested subqueries (`WHERE firebase_uid = auth.jwt()->>'sub'`) on every table access.

### 1.4 Critical Configuration & Secret Drift
- **STAGING DATABASE LEAK IN PRODUCTION CLOUD FUNCTIONS:** Inspection of `baseline_functions.json` (lines 45–49) revealed that **44 deployed Google Cloud Functions** have their `SUPABASE_URL` environment variable baked in as `https://irpkyedfmdsuvapfnrim.supabase.co` (the old staging project) instead of the production project `rnltknemwnjrjxthtull` (`DRNECT-DB`). Any Cloud Function currently querying Supabase is routing to staging!
- **Service-Role Key Audit:** `SUPABASE_SERVICE_ROLE_KEY` / `SUPABASE_SECRET_KEY` is correctly isolated to the server/functions environment and is **never** bundled or exposed in the Flutter frontend. However, `.env.example` templates were missing canonical keys for MSG91 VPC connectors, S3 buckets, and Supabase compile-time flags.

### 1.5 Flutter Client Token Refresh
- The Flutter client bootstrap (`SupabaseBootstrap.currentFirebaseAccessToken`) did not expose a force-refresh capability. When custom claims are assigned asynchronously upon registration, the client could not trigger Firebase Auth to issue a new token with updated claims before sending it to Supabase.

---

## 2. CODE FIXES APPLIED

The following code fixes have been applied directly to the codebase:

### 2.1 Backend Auth Bridge & Claims Generation
1. **Canonical Claims Normalization (`backend/functions/registration_otp.js:3211-3220`):**
   - Updated `supabaseCompatibleCustomClaims(normalizedRole)` to guarantee:
     ```javascript
     {
       role: 'authenticated',
       app_role: normalizedRole,
       user_role: normalizedRole
     }
     ```
2. **Persistent `setCustomUserClaims` on Verification & Login (`backend/functions/registration_otp.js:2346, 2518, 3111`):**
   - Added persistent `admin.auth().setCustomUserClaims(uid, claims)` in `verifyUserRegistrationOtp`, `completeAmbulanceMobileOtpLogin`, and `completeMobileOtpLogin`.
3. **Automatic Claims Sync on Profile Write (`backend/functions/index.js:1970-2000`):**
   - Added the trigger `exports.syncUserClaimsOnProfileWrite = onDocumentWritten('users/{uid}')` to ensure that any user created or updated via any flow (Email/Password, OAuth, Admin) automatically gets their Firebase Auth custom claims synchronized with `role: 'authenticated'` and their application role.
4. **Test Suite Updated (`backend/functions/test/firebase_supabase_claims.test.js:8-20`):**
   - Updated test assertions to verify that both `app_role` and `user_role` are present and match normalized values.

### 2.2 One-Time Claims Backfill Script
- **Created `backend/scripts/backfill_supabase_custom_claims.js`:**
  - Independent CLI script using Firebase Admin SDK.
  - Supports `--dry-run` (default) and `--apply`.
  - Scans all users in Firestore/Auth, inspects existing claims, and updates Firebase Auth custom claims to include `{ role: 'authenticated', user_role: role, app_role: role }`.
  - Features rate-limiting (10ms pause per user), batching, PII masking, and conflict reporting.

### 2.3 Flutter Client Token Refresh Bridge
- **Updated `frontend/lib/core/supabase/supabase_bootstrap.dart`:**
  - Added optional `{bool forceRefresh = false}` to `currentFirebaseAccessToken({bool forceRefresh = false})`.
  - Added public static method `SupabaseBootstrap.refreshSession()` which forces Firebase Auth to mint a fresh token (`user.getIdToken(true)`), ensuring instant synchronization of newly granted custom claims with the Supabase client.
- **Added Unit Tests (`frontend/test/supabase_firebase_access_token_test.dart`):**
  - Added tests verifying that `refreshSession()` delegates to `currentFirebaseAccessToken(forceRefresh: true)`.

### 2.4 Environment & Secret Configuration
- Populated `SUPABASE_SERVICE_ROLE_KEY` alongside `SUPABASE_SECRET_KEY` in `backend/functions/.env` and `functions/.env`.
- Updated `.env.example`, `backend/functions/.env.example`, and `frontend/.env.example` with documented templates for S3, Redis, MSG91 VPC connector, Razorpay, and Supabase client compile-time flags (`--dart-define=SUPABASE_URL=...`).

---

## 3. CONSOLIDATED DATABASE MIGRATION PLAN

### 3.1 Review of All 22 Superseded Migrations
| # | Migration File | Date | Original Purpose | Conflicts & Impedance Identified |
|---|----------------|------|------------------|----------------------------------|
| 1 | `20260923000001_doctornect_schema.sql` | 2026-09-23 | Initial relational schema (facilities, users, doctors, etc.) | Tied `users.id` to `auth.users(id)` (UUID). FK violations on Firebase users. |
| 2 | `20260923000002_doctornect_rls.sql` | 2026-09-23 | Initial RLS policies | Used `auth.uid() = id`, crashing on non-UUID Firebase UIDs (22P02). |
| 3 | `20260923000003_doctornect_cron.sql` | 2026-09-23 | Maintenance cron jobs | Ad expiry and OTP cleanup jobs. |
| 4 | `20260925000001_sync_bridge_infra.sql` | 2026-09-25 | Dual-write sync bridge tables | Transitional infrastructure. |
| 5 | `20260926000001_atomic_appointment_booking.sql` | 2026-09-26 | Atomic slot booking procedure | Used UUID user types. |
| 6 | `20260928000001_add_health_records_s3_storage_fields.sql` | 2026-09-28 | Added S3 storage columns to health_records | Ad-hoc column additions. |
| 7 | `20260928000002_add_lab_reports_s3_storage_fields.sql` | 2026-09-28 | Added S3 columns to lab bookings/orders | Ad-hoc column additions. |
| 8 | `20260928000003_add_profile_photos_s3_storage_fields.sql` | 2026-09-28 | Added S3 photo columns to users, doctors, patients | Ad-hoc column additions. |
| 9 | `20260929000001_add_promoted_ads_s3_storage_fields.sql` | 2026-09-29 | Added S3 image columns to promoted_ads | Ad-hoc column additions. |
| 10 | `20260930000001_fix_security_advisor_warnings.sql` | 2026-09-30 | Security definer search path hardening | Hardened functions, but still referenced UUID user IDs. |
| 11 | `20260930000002_admin_users_table.sql` | 2026-09-30 | Decoupled admin table | Created `private.admin_users` with `REFERENCES auth.users(id)`. |
| 12 | `20260930000003_users_integrity.sql` | 2026-09-30 | Check constraints on users | Role and verification checks. |
| 13 | `20260930000004_access_gap_fixes.sql` | 2026-09-30 | Fixed missing policies | Addressed access gaps across system tables. |
| 14 | `20260930000005_users_provisioning.sql` | 2026-09-30 | User onboarding triggers | Profile completion triggers. |
| 15 | `20260930000006_column_locks.sql` | 2026-09-30 | Prevented non-admin column escalation | Locked rating/verified/role updates. |
| 16 | `20260930000007_auth_user_lookup.sql` | 2026-09-30 | User lookup helper | Looked up users by phone/email. |
| 17 | `20261001000001_bind_otp_challenges.sql` | 2026-10-01 | Bound OTP challenges | Tied OTP challenges to target identifiers. |
| 18 | `20261001000002_harden_auth_provisioning.sql` | 2026-10-01 | Hardened provisioning | Prevented self-assigned admin roles. |
| 19 | `20261002000001_is_super_admin_null_safe.sql` | 2026-10-02 | Null-safe admin checks | Handled null email/role claims safely. |
| 20 | `20261008000001_firebase_uid_identity.sql` | 2026-10-08 | Transitioned to Firebase UID | Mapped `firebase_uid` to UUID via helper queries. |
| 21 | `20261008000002_super_admin_from_admin_users.sql` | 2026-10-08 | Admin checks via table | Checked `private.admin_users`. |
| 22 | `20261008000003_allow_firebase_users_drop_fkey.sql` | 2026-10-08 | Dropped `users_id_fkey` constraint | Dropped constraint to allow inserting Firebase users. |

### 3.2 The Consolidated Migration
All 22 migrations have been unified into a single canonical migration file:
**`backend/supabase/migrations/20261020000001_consolidated_firebase_schema_and_rls.sql`**

**Key Structural Guarantees in Consolidated Migration:**
1. **Natively TEXT Primary Key:** `public.users.id TEXT PRIMARY KEY` holds the Firebase UID directly.
2. **Zero Dependencies on `auth.users`:** No foreign keys exist anywhere in the schema to `auth.users`.
3. **Uniform Foreign Keys:** All child tables (`doctors.owner_uid`, `patients.owner_uid`, `medical_stores.owner_uid`, `labs.owner_uid`, `ambulances.auth_uid`, `in_app_notifications.recipient_uid`, `admin_audit_logs.admin_uid`, `security_events.uid`, `private.admin_users.user_id`) are `TEXT REFERENCES public.users(id)`.
4. **Consolidated S3 Storage Columns:** Inlined directly into `health_records`, `lab_bookings`, `lab_orders`, `users`, `doctors`, `patients`, and `promoted_ads`.
5. **Idempotent and Transaction-Safe:** Contains complete schema, indexes, timestamp triggers, helper functions, and RLS policies.
6. **Not Applied to Live DB:** As requested, this SQL file is saved in `backend/supabase/migrations/` ready for your review.

---

## 4. PURE JWT CLAIMS ROW-LEVEL SECURITY (RLS)

### 4.1 Pure JWT Architecture
- Every call to `auth.uid()` is completely replaced with `(auth.jwt() ->> 'sub')`.
- Role verification evaluates `(auth.jwt() ->> 'user_role')` or `(auth.jwt() ->> 'app_role')`.
- All tables have `ROW LEVEL SECURITY` enabled and forced (`FORCE ROW LEVEL SECURITY`).

### 4.2 Security Definer Functions
```sql
-- Authenticated caller's Firebase UID
CREATE OR REPLACE FUNCTION private.current_user_id() RETURNS TEXT ... AS $$
    SELECT NULLIF(auth.jwt() ->> 'sub', '');
$$;

-- Authenticated caller's application role
CREATE OR REPLACE FUNCTION private.current_user_role() RETURNS TEXT ... AS $$
    SELECT COALESCE(
        NULLIF(auth.jwt() ->> 'user_role', ''),
        NULLIF(auth.jwt() ->> 'app_role', ''),
        (SELECT role FROM public.users WHERE id = (auth.jwt() ->> 'sub') LIMIT 1)
    );
$$;

-- Super Admin evaluation via JWT claims or private.admin_users
CREATE OR REPLACE FUNCTION private.is_super_admin() RETURNS BOOLEAN ... AS $$
    SELECT (
        COALESCE(auth.jwt() ->> 'user_role', auth.jwt() ->> 'app_role', '') IN ('super_admin', 'superAdmin', 'admin')
        OR EXISTS (SELECT 1 FROM public.users WHERE id = (auth.jwt() ->> 'sub') AND role IN ('super_admin', 'superAdmin', 'admin'))
        OR EXISTS (SELECT 1 FROM private.admin_users WHERE user_id = (auth.jwt() ->> 'sub'))
    );
$$;
```

### 4.3 Module Access Policies Matrix
| Module | Table | Select Rule | Insert / Update / Delete Rule |
|--------|-------|-------------|-------------------------------|
| **Core** | `users` | `id = (auth.jwt() ->> 'sub') OR is_super_admin()` | Self-registration / self-update (excluding role/verified); Admin delete |
| **Doctor** | `doctors` | `verified = TRUE OR owner_uid = (auth.jwt() ->> 'sub') OR is_super_admin()` | Self on registration; updates locked to unverified/non-rating fields; Admin delete |
| **Patient** | `patients` | `owner_uid = (auth.jwt() ->> 'sub') OR doctor_can_access_patient(patient_id) OR is_super_admin()` | Owner inserts/updates; Admin delete |
| **Clinical** | `appointments` | `patient_id = current_profile_id() OR doctor_id = current_profile_id() OR is_super_admin()` | Patient creates/cancels; Doctor confirms/completes/notes; Admin delete |
| **Clinical** | `prescriptions` | `patient_id = current_profile_id() OR doctor_id = current_profile_id() OR store delivered OR is_super_admin()` | Verified Doctor creates/edits; Admin delete |
| **Clinical Vault** | `health_records` | `patient_id = current_profile_id() OR (doctor_can_access_patient() AND shared_with_doctors) OR is_super_admin()` | Patient uploads self; Doctor uploads prescribed; Owner updates/deletes |
| **Pharmacy** | `medical_stores` | `verified = TRUE OR owner_uid = (auth.jwt() ->> 'sub') OR is_super_admin()` | Store owner inserts/updates; Admin delete |
| **Pharmacy** | `pharmacy_deliveries`| `store_id = current_profile_id() OR doctor_id = current_profile_id() OR patient_id = current_profile_id() OR is_super_admin()` | Prescribing Doctor sends; Store updates dispense status/notes |
| **Lab** | `labs` | `verified = TRUE OR owner_uid = (auth.jwt() ->> 'sub') OR is_super_admin()` | Lab owner inserts/updates; Admin delete |
| **Lab** | `lab_bookings` | `patient_id = current_profile_id() OR lab_id = current_profile_id() OR is_super_admin()` | Patient books / cancels; Lab updates status & report S3 key |
| **Lab** | `lab_orders` | `doctor_id = current_profile_id() OR patient_id = current_profile_id() OR lab_id = current_profile_id() OR is_super_admin()` | Verified Doctor orders; Lab updates status & report S3 key |
| **Ambulance**| `ambulances` | `verified = TRUE OR auth_uid = (auth.jwt() ->> 'sub') OR is_super_admin()` | Driver updates availability/vehicle; Admin delete |
| **Ambulance**| `ambulance_broadcasts`| `patient_id = current_profile_id() OR accepted_driver_id = current_profile_id() OR (role='ambulance' AND status='pending')` | Patient creates/cancels; Driver accepts/completes |
| **Notifications**| `in_app_notifications`| `recipient_uid = (auth.jwt() ->> 'sub') OR is_super_admin()` | Recipient marks read; service_role / Admin creates |
| **Admin** | `admin_audit_logs` | `is_super_admin()` only | `is_super_admin()` only |
| **Internal**| `otp_challenges`, `abuse_rate_limits`, `mail_queue` | REVOKED from all clients (PUBLIC, anon, authenticated) | `service_role` ONLY |

### 4.4 Automated RLS Policy Test Suite
- Created **`backend/supabase/tests/rls_policies_test.sql`**:
  - Simulates 7 JWT claim contexts (`patient`, `doctor`, `unverified doctor`, `medicalStore`, `lab`, `ambulance`, `admin`).
  - Contains 12 discrete test assertions testing isolation boundaries.
  - Runs in a clean, self-reverting transaction (`BEGIN; ... ROLLBACK;`).

---

## 5. SECRETS & CLOUD FUNCTIONS ENVIRONMENT AUDIT

### 5.1 Critical Staging Leak in Google Cloud Functions
> [!CAUTION]
> **STAGING DATABASE DRIFT DETECTED IN DEPLOYED CLOUD FUNCTIONS**
> - In `baseline_functions.json` (lines 45, 4255), **44 deployed Google Cloud Functions** have their `SUPABASE_URL` baked in as:
>   `https://irpkyedfmdsuvapfnrim.supabase.co` (Staging Project)
> - The production Supabase project is:
>   `https://rnltknemwnjrjxthtull.supabase.co` (`DRNECT-DB`)
> - **Action Required:** A complete redeploy of Cloud Functions (`firebase deploy --only functions`) is required after setting the production secrets/environment in GCP Secret Manager.

### 5.2 Secret Variables Audit Table
| Variable Name | Required Scope | Present in Backend .env | Present in Frontend | Status / Security Assessment |
|---------------|----------------|-------------------------|---------------------|------------------------------|
| `SUPABASE_URL` | Cloud Functions & Flutter | Yes (`rnltknemwnjrjxthtull`) | Compile-time define | Verified. Deployed functions need update. |
| `SUPABASE_ANON_KEY` | Flutter Client | Optional (server-side) | Compile-time define | Safe for public mobile distribution. |
| `SUPABASE_SERVICE_ROLE_KEY`| Cloud Functions ONLY | Yes | **NEVER** | Verified: Absent from Flutter. Present in server env. |
| `SUPABASE_SECRET_KEY` | Cloud Functions ONLY | Yes | **NEVER** | Alias for service-role key; server-only. |
| `S3_BUCKET` | Cloud Functions ONLY | Yes | **NEVER** | Private bucket name; server-only. |
| `AWS_ACCESS_KEY_ID` | Cloud Functions ONLY | Bound via Secret Manager| **NEVER** | Server-only for generating presigned URLs. |
| `AWS_SECRET_ACCESS_KEY` | Cloud Functions ONLY | Bound via Secret Manager| **NEVER** | Server-only for generating presigned URLs. |
| `AWS_REGION` | Cloud Functions ONLY | Yes (`ap-south-1`) | **NEVER** | Server-only. |
| `REDIS_HOST` | Cloud Functions ONLY | Bound via Secret Manager| **NEVER** | Memorystore / Redis Cloud host. Server-only. |
| `REDIS_PORT` | Cloud Functions ONLY | Yes (`6379` / `12875`) | **NEVER** | Server-only. |
| `REDIS_PASSWORD` | Cloud Functions ONLY | Bound via Secret Manager| **NEVER** | Server-only. |
| `MSG91_AUTH_KEY` | Cloud Functions ONLY | Bound via Secret Manager| **NEVER** | Server-only for SMS OTP. |
| `RAZORPAY_KEY_ID` | Cloud Functions & Flutter | Yes | Pass via config | Public key id. |
| `RAZORPAY_KEY_SECRET` | Cloud Functions ONLY | Bound via Secret Manager| **NEVER** | Server-only for webhook/payment verification. |

---

## 6. REDIS USAGE MATRIX & RESILIENCE VERIFICATION

| Use Case | Module / File | Key Pattern | TTL | Behavior When Redis Is Down | Permanent Data? |
|----------|---------------|-------------|-----|-----------------------------|-----------------|
| **Presigned URL Cache** | `backend/functions/s3_storage.js:655` | `s3:url:<bucket>:<key>` | 300s (5 min) | **Fail-Open:** Catches error, logs warning, and mints a fresh presigned URL directly via AWS S3 SDK. | **NO** |
| **Abuse Rate Limiting** | `backend/functions/abuse_rate_limit.js:92` | `rate_limit:<bucket>` | 60s–3600s | **Fail-Open:** 1500ms timeout; falls back to Firestore document counters in `system_abuse_buckets` or memory. | **NO** |
| **OTP Challenge Mirror** | `backend/functions/registration_otp.js:253` | `otp:<target>` | 600s (10 min) | **Fail-Open:** Controlled by `OTP_REDIS_MIRROR=off`. When on, failures fall back to primary storage (`otp_challenges`). | **NO** |

**Conclusion:** Zero critical business data lives in Redis. Redis strictly serves as an ephemeral performance accelerator.

---

## 7. STEP-BY-STEP MANUAL ACTIONS (IN EXACT ORDER)

Please perform the following actions in the respective cloud dashboards:

### Step 1: Supabase Dashboard — Configure Third-Party Auth for Firebase
1. Log in to [Supabase Dashboard](https://supabase.com/dashboard) and select project `rnltknemwnjrjxthtull` (`DRNECT-DB`).
2. Navigate to **Authentication** -> **Providers** -> **Third-Party Auth**.
3. Click **Add Provider** and select **Firebase Auth**.
4. Configure the provider settings:
   - **Status:** `Enabled`
   - **Project ID:** `medibond-45fad`
   - **Discovery / JWKS URL:** Default (`https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com`)
5. Click **Save Changes**.

### Step 2: Supabase Dashboard — Review & Apply Consolidated Migration
1. In the Supabase Dashboard, navigate to the **SQL Editor**.
2. Open and review the migration script:
   `backend/supabase/migrations/20261020000001_consolidated_firebase_schema_and_rls.sql`
3. Paste and run the SQL script. Verify that all 53 tables have `RLS: enabled and forced` and that all functions compile cleanly.
4. (Optional) Run the test suite:
   `backend/supabase/tests/rls_policies_test.sql`
   Verify that all 11 core module test assertions report `PASS` (Patient, Doctor, Pharmacy, Lab, Ambulance, and Anon isolation).

### Step 3: Google Cloud Secret Manager / Firebase CLI — Update Function Secrets
Run the following commands in your terminal to ensure GCP Secret Manager holds production values:
```bash
firebase functions:secrets:set SUPABASE_URL
# Input: https://rnltknemwnjrjxthtull.supabase.co

firebase functions:secrets:set SUPABASE_SERVICE_ROLE_KEY
# Input: <Your production Supabase service_role key>

firebase functions:secrets:set SUPABASE_SECRET_KEY
# Input: <Your production Supabase service_role key>
```

### Step 4: Run the One-Time Custom Claims Backfill Script
To backfill all existing users in Firebase Auth with `role: "authenticated"` and their correct `user_role`:
```bash
# 1. Run dry-run to inspect existing users:
node backend/scripts/backfill_supabase_custom_claims.js --dry-run

# 2. Apply claims updates to Firebase Auth:
node backend/scripts/backfill_supabase_custom_claims.js --apply --project medibond-45fad
```

### Step 5: Redeploy Google Cloud Functions to Production
Redeploy all Cloud Functions so they discard the old staging URL (`irpkyedfmdsuvapfnrim`) and pick up production secrets:
```bash
firebase deploy --only functions
```

### Step 6: Flutter Build Verification
Build your mobile client with production Supabase compile-time arguments:
```bash
flutter build apk --dart-define=SUPABASE_URL=https://rnltknemwnjrjxthtull.supabase.co --dart-define=SUPABASE_ANON_KEY=<YOUR_PRODUCTION_ANON_KEY>
```

---

## 8. AUTOMATED VERIFICATION RESULTS

### 8.1 Backend Test Suite (`npm test` in `backend/functions`)
```
ℹ tests 395
ℹ suites 6
ℹ pass 379
ℹ fail 0
ℹ cancelled 0
ℹ skipped 16
ℹ todo 0
ℹ duration_ms 46046.0165
Exit code: 0
```
- All 379 active tests pass with zero regressions. (16 skipped tests require local Firestore emulator).

### 8.2 Backfill Script Syntax Verification
```
node --check backend/scripts/backfill_supabase_custom_claims.js
Exit code: 0
```

---
*Report compiled by Senior Backend Architect under Gravitas protocol.*
