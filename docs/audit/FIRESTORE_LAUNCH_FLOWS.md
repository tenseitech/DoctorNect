# Launch-critical flows — Firestore reachability (flow-based)

Generated against `npm run audit:firestore-reachability` and release smoke in `frontend/test/release_firestore_forbidden_smoke_test.dart`.

**MIGRATED** = entry screen pumps without `FirestoreService` / `FirestoreClient` under `FIRESTORE_FORBIDDEN`.  
**POST_LAUNCH** = still reaches **LIVE_AND_THROWS** rows (show `FirestoreUi.userMessage` or finish Supabase migration).

---

## Patient module

| Flow | Entry screen | Status | LIVE rows still on path (file:line) |
|------|--------------|--------|-------------------------------------|
| Login / registration | `features/welcome/welcome_screen.dart` | **MIGRATED** | `unified_auth_flow_controller.dart:353,380` if user proceeds into full auth wizard |
| Home | `features/patient/home/patient_home_screen.dart` | **MIGRATED** | none on initial pump (ads → Supabase / empty stream) |
| Search / nearby | `features/patient/search/doctor_search_screen.dart` | **MIGRATED** | none on initial pump |
| Appointment booking | `features/patient/booking/booking_flow_screen.dart` | **POST_LAUNCH** | `booking_flow_screen.dart:69,94,1069,1077` |
| Prescriptions list/detail | `features/patient/appointments/patient_prescription_opener.dart` | **POST_LAUNCH** | `patient_prescription_opener.dart:18` |
| Lab order | `features/patient/lab/lab_booking_flow_screen.dart` | **MIGRATED** | none ( `LabCatalogRepository` / `LabBookingRepository` ) |
| Lab report | `core/firebase/lab_report_submit_flow.dart` + lab status RPC | **MIGRATED** | none on patient submit path |
| My labs hub | `features/patient/lab/my_labs_screen.dart` | **MIGRATED** | none when `PatientSession` empty |
| Lab browse | `features/patient/lab/lab_home_screen.dart` | **MIGRATED** | none |
| Pharmacy order | patient pharmacy checkout (no dedicated shell in consumer build) | **POST_LAUNCH** | `pharmacy_firestore_repository.dart` only via gateway elsewhere |
| Profile | `features/patient/profile/edit_profile_screen.dart` | **MIGRATED** | `profile_photo_uploader.dart` on photo upload only |

---

## Doctor module

| Flow | Entry screen | Status | LIVE rows still on path |
|------|--------------|--------|-------------------------|
| Login / verification gate | `features/doctor/verification/doctor_verification_gate.dart` | **MIGRATED** | none on gate pump |
| Pending verification | `features/doctor/verification/doctor_verification_pending_screen.dart` | **MIGRATED** | none |
| Home | `features/doctor/home/doctor_home_screen.dart` | **POST_LAUNCH** | `firestore_data_prefetch.dart` (multiple), `doctor_home_screen.dart` refresh hooks |
| Appointments (shell tab) | doctor shell → shared appointment sync | **MIGRATED** | `AppointmentRepository` (no gateway) |
| Prescriptions (clinical) | clinical prescription form sections | **POST_LAUNCH** | `prescription_form_sections.dart` community + legacy paths |
| Lab orders (connected labs) | `features/doctor/lab/doctor_connected_labs_screen.dart` | **POST_LAUNCH** | `doctor_connected_labs_screen.dart:204` |
| Pharmacy partners | `features/doctor/pharmacy/doctor_connected_stores_screen.dart` | **MIGRATED** | none on attach sync |
| Profile | `features/doctor/profile/data/doctor_profile_store.dart` | **MIGRATED** | Supabase `SupabaseDoctorRepository` |

---

## Pharmacy module

| Flow | Entry screen | Status | LIVE rows still on path |
|------|--------------|--------|-------------------------|
| Store shell / dashboard | `features/pharmacy/medical_store_shell.dart` | **MIGRATED** | `role_session_guard` → `UserRepository` (no gateway) |
| Connections / deliveries | `FirestoreScreenSync` + pharmacy repos | **MIGRATED** | none |

---

## Lab module

| Flow | Entry screen | Status | LIVE rows still on path |
|------|--------------|--------|-------------------------|
| Lab shell / worklist | `features/lab/lab_shell.dart` | **MIGRATED** | sync via `LabOrderRepository` / `LabBookingRepository` |
| Walk-in / dashboard tabs | `features/lab/screens/lab_dashboard_tabs.dart` | **MIGRATED** | report upload sheet still uses gateway on submit only |

---

## Shared-core LIVE (32 rows) — callers

| File | Modules that reach it in release |
|------|----------------------------------|
| `role_session_guard.dart` | pharmacy shell, lab shell, ambulance shell |
| `unified_auth_flow_controller.dart` | welcome → registration/login |
| `unified_auth_navigation.dart` | auth navigation |
| `firestore_data_prefetch.dart` | doctor home / shell warm-start |
| `firestore_query_limits.dart` | ambulance repository scale helpers |
| `firebase_bootstrap.dart:41` | Firebase settings when misconfigured |
| `promoted_ads_service.dart` (Firestore fallback) | patient home if Supabase down |
| `profile_photo_uploader.dart` | profile photo flows |
| `patient_push_service.dart` | FCM token persist (patient) |
| `ambulance_push_service.dart` | FCM token persist (ambulance) |

Full inventory: `docs/audit/FIRESTORE_REACHABLE_RELEASE.md`.

---

## Admin (excluded from consumer build)

`features/admin/*` (e.g. `promoted_ad_review_screen.dart`) is **not** linked from patient/doctor/lab/pharmacy shells; reachable only when a super-admin session opens admin routes → **LIVE_AND_THROWS**.

---

## Release smoke coverage

`release_firestore_forbidden_smoke_test.dart` pumps **12 MIGRATED entry screens** (plus 3 guard unit tests = **15** total) with:

- `FirestoreForbiddenGuard.debugForceReleaseMode = true`
- `SupabaseBootstrap.isReady = true` + `debugTableFetcher` returning empty rows
- `FirebaseBootstrap.isReady = false`, `AmbulanceEnabled` off

Fails on any `StateError` containing `FIRESTORE_FORBIDDEN`.
