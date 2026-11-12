# Firestore final state (`frontend/lib`)

Inventory of **direct** `FirebaseFirestore.instance` and `.collection(` usage under `frontend/lib` (grep, 2026-11-06). The app still calls many features through `FirestoreService` repositories that wrap Firestore without always using the exact `FirebaseFirestore.instance` substring in each file; this list is the **string-level** surface called out in the Phase 2 audit.

## Summary

| Pattern | File count (approx.) | Release typical? |
|--------|----------------------|------------------|
| `FirebaseFirestore.instance` | 21 files | Mixed: several paths are debug-only, gated, or admin/ambulance-only |

## File-by-file (direct `FirebaseFirestore` / `.collection(`)

| File | Role | Reachable in default **release** patient/doctor flow? | Under deny-all Firestore rules |
|------|------|--------------------------------------------------------|--------------------------------|
| `core/auth/profile_completion_service.dart` | Legacy profile flags when cutover/Supabase path not used | **Rare**: cutover flag is always on in release; primary path is Supabase. Legacy branch uses `_effectiveFirestore()` (overridable in tests). | Writes/reads to `users` / role docs **fail**; UI may show `lastError` on Supabase path instead. |
| `core/storage/profile_photo_uploader.dart` | Photo metadata / upload coordination | **Yes** if that flow runs before full storage cutover | Upload or metadata writes **fail**; user-visible upload errors. |
| `core/services/promoted_ads_service.dart` | Sponsored ads | **Yes** on home/carousel | Ads stream **empty** or errors in UI. |
| `features/doctor/profile/data/doctor_profile_store.dart` | Doctor profile cache | **Yes** for doctors | Profile load/save **fails**; degraded dashboard. |
| `features/doctor/doctor_shell.dart` | Shell bootstrap | **Yes** for doctors | Shell retries / blank sections. |
| `features/ambulance/ambulance_profile_screen.dart` | Ambulance profile | **Only if** `AMBULANCE_ENABLED` and ambulance module used | Same; feature hidden when flag off. |
| `core/firebase/firebase_bootstrap.dart` | Firebase init | **Yes** (Firebase still initializes) | Firestore operations elsewhere **fail**; auth may still work. |
| `core/admin/super_admin_verification_service.dart` | Super-admin verification | **No** (admin-only) | Admin tools **broken** for Firestore-backed steps. |
| `core/firebase/repositories/ambulance_repository.dart` | Ambulance Firestore API | **Only if** ambulance flows enabled | Requests/drivers **fail**. |
| `features/doctor/clinical/data/community_medicine_repository.dart` | Clinical community data | **Yes** when doctor uses those tools | Lists **empty** / errors. |
| `features/doctor/clinical/data/community_diagnosis_repository.dart` | Same | Same | Same |
| `features/doctor/clinical/data/community_investigations_repository.dart` | Same | Same | Same |
| `core/services/banner_config_service.dart` | Remote banner config | **Yes** if used on startup | Banners **default/off**. |
| `core/auth/profile_draft_store.dart` | Draft registration/profile | **Yes** during onboarding | Draft save **fails**. |
| `features/patient/profile/support/support_tickets_history_screen.dart` | Legacy ticket history | **If** screen opened | History **empty**. |
| `features/patient/profile/support/help_support_screen.dart` | Help content | **If** opened | **Fails** or static fallback. |
| `features/patient/profile/data/patient_profile_mock.dart` | Demo/mock profile | **Mostly dev** | Low impact in release. |
| `features/admin/promoted_ad_review_screen.dart` | Admin ads | Admin-only | N/A for patients. |
| `features/patient/booking/utils/booking_flow_helpers.dart` | Booking helpers | **Yes** during booking | Helper Firestore touches **fail** if still used. |
| `core/invite/doctor_invite_service.dart` | Invites | **If** invite flow used | Invite writes **fail**. |
| `core/invite/pharmacy_doctor_invite_service.dart` | Pharmacy invites | Same | Same |
| `core/invite/ambulance_invite_service.dart` | Ambulance invites | Only if ambulance enabled | Same |

### Broader `.collection(` usage (includes `FirebaseFirestore.instance` and `FakeFirebaseFirestore`)

The following files also contain `.collection(` (some via test doubles or the same classes above):

Same set as the table plus any thin wrappers; **grep count** snapshot: 21 files under `frontend/lib` with both patterns combined.

## Notes

- **FirestoreService** (`core/firebase/firestore_service.dart`) centralizes many reads/writes; it does **not** always contain the literal `FirebaseFirestore.instance` in the grep hit list but still talks to Firestore through repositories.
- **Phase 2 goal**: production paths for appointments, in-app notifications, and profile completion favor **Supabase**; Firestore remains for legacy/admin/ambulance and incremental migration.
