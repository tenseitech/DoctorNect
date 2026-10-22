# Firestore Remaining Touch Points & Stage 2 Cutover Map

## 1. Overview & Classification Strategy
This document audits every single Firestore touch point across `backend/functions` and `frontend/lib`, categorizing each into one of three classifications:
- **MIGRATE**: Production code path migrated in Phase F to Supabase PostgreSQL, Redis, or S3 behind the cutover flag (`DoctorPatientCutoverFlag.isEnabled` / `USE_SUPABASE_DB_DOCTOR_PATIENT=true`).
- **DELETE-AT-STAGE-2**: Legacy repository, trigger, or dual-write sync bridge that is already bypassed when the cutover flag is ON, and will be physically removed in Stage 2.
- **ADMIN-OWNED**: Super Admin verification console and back-office triggers that receive dual-path support (Supabase path behind cutover flag).

---

## 2. Backend Functions Touch Points (`backend/functions`)

| File:Line | Operation / Collection | Classification | Target Architecture & Replacement |
| :--- | :--- | :--- | :--- |
| `backend/functions/caller_identity.js` (NEW) | Caller identity resolution across callables | **MIGRATE** | Shared helper querying Supabase `users` via service role |
| `backend/functions/index.js:126` | `getUserProfile` callable (`users/{uid}`) | **MIGRATE** | Supabase `users` via `resolveCallerIdentity` |
| `backend/functions/index.js:1013` | `getUserRole` callable (`users/{auth.uid}`) | **MIGRATE** | Supabase `users` via `resolveCallerIdentity` |
| `backend/functions/index.js:1032` | `lookupMobileRegistration` (`users`) | **MIGRATE** | Supabase `users.mobile` query via service role |
| `backend/functions/index.js:1450` | `approveUserAccount` (`users/{auth.uid}`) | **ADMIN-OWNED** | Supabase `users` (PATCH status/verified) + custom claims |
| `backend/functions/index.js:1487` | `approvePatientAccount` (`users/{auth.uid}`) | **ADMIN-OWNED** | Supabase `users` (PATCH status/verified) + custom claims |
| `backend/functions/index.js:1524` | `rejectUserAccount` (`users/{auth.uid}`) | **ADMIN-OWNED** | Supabase `users` (PATCH status/rejection) |
| `backend/functions/index.js:2040` | `getUserAccountStatus` (`users/{userId}`) | **MIGRATE** | Supabase `users` via `resolveCallerIdentity` |
| `backend/functions/s3_storage.js:281` | `resolveCallerIdentity` (`users/{uid}`) | **MIGRATE** | Supabase `users` via `resolveCallerIdentity` |
| `backend/functions/promoted_ads.js:522` | `reviewPromotedAdHandler` (`users/{auth.uid}`) | **MIGRATE** | Supabase `users` + `private.is_super_admin()` check |
| `backend/functions/fcm_push.js:60` | FCM token lookup on profile documents | **MIGRATE** | Supabase `user_devices` table (service role) |
| `backend/functions/security_logger.js:75` | Security events write (`security_events`) | **MIGRATE** | Supabase `security_events` table (service role) |
| `backend/functions/abuse_rate_limit.js:61` | Fallback abuse rate limits (`abuse_rate_limits`) | **MIGRATE** | Pure Redis TTL keys (`rate:`, `abuse:`); fail closed |
| `backend/functions/delete_my_account.js:1036-1140`| User account deletion Firestore queries | **MIGRATE** | Supabase `cleanupUserSupabaseRows` + S3 prefix deletion + Redis keys |
| `backend/functions/appointment_slots.js` | `doctor_slots`, `doctor_day_counters`, appointments | **DELETE-AT-STAGE-2** | Replaced by PostgreSQL RPC `book_appointment_atomic` |
| `backend/functions/index.js:1265` | `acceptAmbulanceInvite` (`ambulance_invites`) | **MIGRATE** | Supabase `ambulance_invites` table + single-use RPC |
| `backend/functions/index.js:1320` | `acceptDoctorInvite` (`doctor_invites`) | **MIGRATE** | Supabase `doctor_invites` table / `doctors.doctor_id` |
| `backend/functions/index.js:1375` | `acceptPharmacyDoctorInvite` (`pharmacy_doctor_invites`) | **MIGRATE** | Supabase `pharmacy_doctor_invites` table |
| `backend/functions/index.js:231-285` | Ambulance PIN login & lockout | **MIGRATE** | Supabase `ambulance_driver_login` RPC + Redis attempt lockout |
| `backend/functions/cross_role_sync.js:136` | Sync bridge fallback DLQ (`_sync_dlq`) | **DELETE-AT-STAGE-2** | Supabase `sync_dead_letters` table / `security_events` |
| `backend/functions/seed_demo_accounts.js:36` | Demo accounts config (`app_config/demo_accounts`) | **DELETE-AT-STAGE-2** | Reviewer login via env / Supabase seed script |

---

## 3. Frontend App Touch Points (`frontend/lib`)

| File | Module / Collections | Classification | Target Architecture & Replacement |
| :--- | :--- | :--- | :--- |
| `frontend/lib/core/firebase/repositories/user_repository.dart` | `users` profile fetch/create/search | **MIGRATE** | `UserSupabaseRepository` querying Supabase `users` |
| `frontend/lib/core/auth/onboarding_service.dart` | User profile drafting & completion | **MIGRATE** | Supabase `users` table via `UserSupabaseRepository` |
| `frontend/lib/core/auth/profile_completion_service.dart` | Profile metadata persistence | **MIGRATE** | Supabase `users` table via `UserSupabaseRepository` |
| `frontend/lib/core/auth/profile_draft_store.dart` | Draft profile persistence | **MIGRATE** | Local secure storage / SharedPreferences |
| `frontend/lib/core/services/banner_config_service.dart` | `system_config/promoted_ads` | **MIGRATE** | Supabase `system_config` table / client safe defaults |
| `frontend/lib/core/models/banner_config_model.dart` | Banner config model mapping | **MIGRATE** | Supabase row mapper + default fallback |
| `frontend/lib/core/services/promoted_ads_service.dart` | `promotedAds` queries & mutations | **MIGRATE** | Supabase `promoted_ads` table behind cutover flag |
| `frontend/lib/core/invite/ambulance_invite_service.dart` | `ambulance_invites` link & metadata | **MIGRATE** | Supabase `ambulance_invites` table via REST |
| `frontend/lib/core/invite/doctor_invite_service.dart` | Doctor invite link metadata | **MIGRATE** | Deterministic URL generation with `doctor_id` |
| `frontend/lib/core/invite/pharmacy_doctor_invite_service.dart` | Pharmacy doctor invite link metadata | **MIGRATE** | Deterministic URL generation with `store_id` |
| `frontend/lib/features/doctor/clinical/data/community_diagnosis_repository.dart` | `community_diagnoses` | **MIGRATE** | Supabase `community_diagnoses` table via Supabase client |
| `frontend/lib/features/doctor/clinical/data/community_investigations_repository.dart`| `community_lab_tests` | **MIGRATE** | Supabase `community_lab_tests` table via Supabase client |
| `frontend/lib/features/doctor/clinical/data/community_medicine_repository.dart` | `community_medicines` | **MIGRATE** | Supabase `community_medicines` table via Supabase client |
| `frontend/lib/core/firebase/repositories/appointment_repository.dart` | `appointments` | **DELETE-AT-STAGE-2** | Already delegates to `AppointmentSupabaseRepository` |
| `frontend/lib/core/firebase/repositories/prescription_repository.dart` | `prescriptions` | **DELETE-AT-STAGE-2** | Already delegates to `PrescriptionSupabaseRepository` |
| `frontend/lib/core/firebase/repositories/doctor_directory_repository.dart` | `doctors` directory | **DELETE-AT-STAGE-2** | Already delegates to `DoctorSupabaseRepository` |
| `frontend/lib/core/firebase/repositories/pharmacy_firestore_repository.dart` | `pharmacy_deliveries` | **DELETE-AT-STAGE-2** | Already delegates to `PharmacySupabaseRepository` |
| `frontend/lib/core/firebase/repositories/lab_booking_repository.dart` | `lab_bookings` | **DELETE-AT-STAGE-2** | Already delegates to `LabSupabaseRepository` |
| `frontend/lib/core/firebase/repositories/ambulance_repository.dart` | `ambulances`, `ambulance_broadcasts` | **DELETE-AT-STAGE-2** | Already delegates to `AmbulanceSupabaseRepository` |
| `frontend/lib/core/firebase/repositories/in_app_notification_repository.dart` | `in_app_notifications` | **DELETE-AT-STAGE-2** | Already delegates to `InAppNotificationSupabaseRepository` |
| `frontend/lib/features/patient/profile/support/*` | `support_tickets`, `ticket_messages` | **DELETE-AT-STAGE-2** | Already wired to `SupportTicketSupabaseRepository` |
| `frontend/lib/core/admin/super_admin_verification_service.dart` | Admin verification actions | **ADMIN-OWNED** | Cloud Functions with dual-path support |
