# Launch-critical flows — Firestore reachability (flow-based)

Postgres-primary repos are reached **without** `FirestoreService.instance` when noted **migrated**. Rows still using `FirestoreService` / `FirestoreClient` in release are **LIVE_AND_THROWS** (see `FIRESTORE_REACHABLE_RELEASE.md`).

## Patient

| Flow | Entry screen | Call chain (release) | Firestore rows | Status |
|------|--------------|----------------------|----------------|--------|
| Login / registration | `welcome_screen.dart` → auth | `FirebaseAuthService` → `UserRepository` (Supabase) | — | **migrated** (this pass) |
| Home | `patient_home_screen.dart` | `RegisteredDoctorsStore` → `DoctorDirectoryRepository`; ads → Supabase `promoted_ads` | — | **migrated** |
| Search / nearby | `doctor_search_screen.dart` | `LabCatalogRepository`; `DoctorDirectoryRepository`; ambulance list off when `AMBULANCE_ENABLED=false` | — | **migrated** |
| Appointment booking | `booking_flow_screen.dart` | `FirestoreService.doctorAvailability` / `doctorProfileDetail` | `booking_flow_screen.dart` (multiple) | **post-launch** (`FirestoreUi` or Supabase availability) |
| Prescriptions | `patient_prescription_opener.dart` | `FirestoreService.prescription` | LIVE | **post-launch** |
| Lab order / report | `lab_booking_flow_screen.dart`, `lab_report_submit_flow.dart` | `SupabaseLabRepository` RPC keys | — | **migrated** (RPC skew message in repo) |
| Pharmacy order | patient pharmacy screens | Supabase pharmacy repos | pharmacy LIVE rows in partner flows | **partial** |
| Profile | `edit_profile_screen.dart` | `PatientProfileMock` / Supabase profile | `patient_profile_mock.dart` family paths if cutover off | **migrated** when cutover on (default) |

## Doctor

| Flow | Entry screen | Call chain | Firestore rows | Status |
|------|--------------|------------|----------------|--------|
| Login / gate | `doctor_verification_gate.dart` | `DoctorVerificationRepository` | — | **migrated** |
| Home | `doctor_home_screen.dart` | appointments sync, clinical tools | `doctor_home_screen.dart`, prefetch | **post-launch** |
| Appointments | doctor shell tabs | `FirestoreScreenSync` → `AppointmentRepository` | — | **migrated** (sync gateway) |
| Prescriptions | clinical screens | community repos Supabase-primary; some `FirestoreService` in forms | mixed | **partial** |
| Lab orders | doctor lab screens | Supabase lab + connection repos | connected labs screen orders sub | **partial** |
| Pharmacy partners | `doctor_connected_stores_screen.dart` | `PharmacyFirestoreRepository`, `MedicalStoreRepository` | — | **migrated** |
| Profile | doctor profile store | `SupabaseDoctorRepository` | — | **migrated** |

## Pharmacy / Lab modules

| Flow | Entry | Firestore in release | Status |
|------|-------|---------------------|--------|
| Store onboarding / shell | pharmacy shell | connection + delivery watchers via Supabase repos | **migrated** gateways |
| Lab worklist | lab shell | `FirestoreScreenSync.attachLabWorklist` → lab order/booking repos | **migrated** |

## Shared-core LIVE rows (32) — who calls them

| Shared-core LIVE file | Called from modules |
|-----------------------|---------------------|
| `role_session_guard.dart`, `unified_auth_flow_controller.dart`, `unified_auth_navigation.dart` | auth (all roles) |
| `firestore_data_prefetch.dart`, `firestore_query_limits.dart` | doctor home / shell prefetch |
| `firebase_bootstrap.dart` (settings) | app init |
| `promoted_ads_service.dart` (fallback branch) | patient home carousel when Supabase down |
| `profile_photo_uploader.dart` | profile flows |
| FCM token writers on `FirestoreService.patientProfile` / ambulance | notifications |

Full line list: `docs/audit/FIRESTORE_REACHABLE_RELEASE.md` (filter `module = shared-core`, class `LIVE_AND_THROWS`).

## Admin (consumer build)

- Routes under `features/admin/*` (e.g. promoted ad review) are **not** in patient/doctor/lab/pharmacy shells; reachable only if super-admin signs in and navigates there → still **LIVE_AND_THROWS** until migrated.

## Smoke coverage

`frontend/test/release_firestore_forbidden_smoke_test.dart` pumps Welcome, DoctorSearch, PatientHome, DoctorVerificationGate/Pending under `debugForceReleaseMode` and fails on `FIRESTORE_FORBIDDEN` `StateError`.
