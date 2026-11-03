# Remaining Firestore usage (deny-all impact)

Generated from `rg 'Firestore|FirebaseFirestore|\.collection\(' frontend/lib backend/functions`.

## If Firestore rules are deny-all

| Module / file | Active Firestore? | Breaks without Firestore |
|---------------|-------------------|---------------------------|
| **`profile_photo_uploader.dart`** | S3 path: **no** (Supabase `patients`/`doctors`/`users` when `firestoreOverride == null`). Legacy non-S3 + `firestoreOverride` tests still use Firestore. | S3 profile upload **works** on Postgres-only builds; legacy base64/Firebase Storage path still writes Firestore. |
| **`promoted_ads_service.dart`** | Production: **no** (`promoted_ads` Supabase upsert). `firestoreOverride` tests only. | Ad create/update **works** via Supabase; test doubles still need override. |
| **`lab_*` repositories** | Mixed read helpers; lab submit uses Supabase only. | Lab report submit unaffected. |
| **`ambulance_repository.dart`** | Heavy Firestore (58 refs) | Ambulance flows break until Supabase-primary. |
| **`in_app_notification_service.dart`** | Heavy (38 refs) | In-app notification sync breaks. |
| **`prescription_repository.dart` / clinical stores** | Firestore mappers + reads | Doctor prescribing UI may break where not cut over to `supabase_prescription_repository`. |
| **`shared_appointments_store.dart`** | 18 refs | Appointment lists may break. |
| **`profile_completion_service.dart`** | 22 refs | Onboarding completion paths may break. |
| **`doctor_shell.dart` / features/doctor/** | Many screens | Mixed; depends on repository wiring. |
| **Backend `functions/`** | `cross_role_sync.js`, `appointment_slots.js`, webhooks | Server-side Firestore sync still expected where not migrated. |

## Per-area file counts (frontend/lib)

- `features/*`: ~81 files touching Firestore APIs  
- `core/*`: ~68 files  
- Not exhaustive; treat as inventory for Postgres-only cutover.
