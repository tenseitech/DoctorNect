# Remaining Firestore usage (inventory + launch plan)

Generated / updated: 2026-11-03. Sources: `rg 'Firestore|FirebaseFirestore|\.collection\(' frontend/lib backend/functions`, `backend/firestore.rules`, `DoctorPatientCutoverFlag`, `sync_flags.isDoctorPatientSupabasePrimary`, `confirmS3UploadHandler` Firestore branch.

## Current deployed rules (`backend/firestore.rules`)

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /{document=**} {
      allow read, write: if false;
    }
  }
}
```

**Every client read/write is denied.** Admin SDK in Cloud Functions still works. Any Flutter path that still calls `FirebaseFirestore.instance` without a Supabase bypass **fails at runtime** unless `firestoreOverride` is set (tests only) or the code path is dead on production builds.

---

## Reconcile with `DOCTORNECT_VERIFICATION_REPORT.md`

The verification report’s “UI decoupled from Firestore” rows mean **specific screens** were rewired to Supabase/S3 (e.g. lab upload sheet, ambulance booking screens, profile completion modal). It does **not** mean zero Firestore imports remain in `frontend/lib`.

What still routes to Firestore in **release** when deny-all rules are deployed:

| Gate | Location | When Firestore is used |
|------|----------|------------------------|
| `DoctorPatientCutoverFlag.isEnabled` + `SupabaseBootstrap.isReady` | `profile_photo_uploader.dart`, many doctor/patient repos | **Off or not ready** → legacy Firestore writes for photos and some profile paths. Production cutover flag is intended **on**. |
| `firestoreOverride != null` | Tests only | Never in release APK/IPA. |
| `!ctx.isSupabase` in `confirmS3UploadHandler` | `backend/functions/s3_storage.js` ~1379–1413 | When `isDoctorPatientSupabasePrimary()` is false, confirm writes `health_records`, `lab_bookings`, `patients`, `doctors` via Firestore merge. **Production primary = Supabase.** |
| OTP / abuse fallbacks | `registration_otp.js`, rate limit backend | Redis/Supabase primary; Firestore `otp_challenges`, `otp_verification_sessions` on fallback. |
| Ambulance / notifications / shared appointment store | See modules below | **Still Firestore-first** in several hot paths unless explicitly migrated. |
| Backend sync jobs | `cross_role_sync.js`, `appointment_slots.js`, webhooks | Admin SDK writes; not governed by client rules. |

---

## Module deep dives (requested)

### `ambulance_repository.dart`

- **Collections:** `ambulances` (+ subcollection `private/settings`), `ambulance_requests`, `ambulance_broadcasts`, `ambulance_invites` (via paths).
- **PHI/PII:** **Yes** — patient location, request status, driver identifiers, broadcast payloads (emergency context).
- **Current rules:** deny-all for clients; repo assumes readable/writable Firestore (broken under deny-all unless Admin-only).
- **Migration effort:** **L** — full booking lifecycle, broadcasts, driver settings; Supabase mappers exist for some flows but repository is still Firestore-heavy (~58 `.collection` refs).
- **Before launch:** Must migrate **or** ship with temporary owner-scoped rules (see below) if ambulance is in scope for v1.

### `shared_appointments_store.dart`

- **Collections:** `appointments`, `reviews` (via `FirestoreService.instance.appointment` / `.review`).
- **PHI/PII:** **Yes** — appointment times, doctor/patient IDs, review text.
- **Current rules:** deny-all; store still calls `fetchForDoctor`, `fetchForPatient`, `save`, review submit unless Supabase debug hooks replace refresh.
- **Migration effort:** **M** — partial Supabase merge paths exist (`mergeFromFirestore`, Supabase-first comments); cancel flow notes Firestore as source of truth today.
- **Before launch:** Doctor/patient appointment UX must use Supabase-primary store wiring already registered in service locator, or Firestore rules for `appointments` owner-scoped.

### `in_app_notification_service.dart`

- **Collections:** `in_app_notifications` (via `FirestoreService.instance.inAppNotification`).
- **PHI/PII:** **Moderate** — notification titles/bodies may reference clinical events; not full records.
- **Current rules:** deny-all; merge/markRead paths still hit Firestore when IDs are tracked in `_doctorFirestoreIds` / `_patientFirestoreIds`.
- **Migration effort:** **M** — mirror table `in_app_notifications` on Postgres + RLS; FCM remains Firebase.
- **Before launch:** If in-app inbox is required, migrate reads/writes to Supabase or add scoped rules.

### `profile_completion_service.dart`

- **Collections:** `users`, role collections (`doctors`, `patients`, `labs`, …), `ambulances`.
- **PHI/PII:** **Yes** for clinical roles (doctor/patient profile fields); operational for ambulance.
- **Current rules:** deny-all; service still reads/writes Firestore for completion flags when Supabase path not taken.
- **Migration effort:** **S–M** — modal/widget layer migrated per verification report; this service is legacy glue for older onboarding entry points.
- **Before launch:** Ensure all entry points call Supabase user repos only; delete or guard Firestore calls behind `kDebugMode` + override.

---

## Remaining collections (frontend + backend touch)

| Collection | PHI/PII | Client rules today | Release still used? | Effort |
|------------|---------|-------------------|---------------------|--------|
| `users` | PII (phone, role) | deny-all | Fallback profile completion | M |
| `doctors` | PII + professional | deny-all | Legacy repos bypassed by locator; confirmS3 Firestore branch | S |
| `patients` | PHI/PII | deny-all | Same | S |
| `appointments` | PHI | deny-all | `shared_appointments_store` | M |
| `prescriptions` | PHI | deny-all | Legacy `prescription_repository` mappers | M |
| `health_records` | PHI | deny-all | confirmS3 fallback only if !Supabase primary | S |
| `lab_bookings` / `lab_orders` | PHI | deny-all | Lab submit **Supabase-only**; legacy read helpers + confirm fallback | S |
| `in_app_notifications` | Low–moderate | deny-all | `in_app_notification_service` | M |
| `ambulances` / `ambulance_requests` / `ambulance_broadcasts` | PHI/PII | deny-all | `ambulance_repository` | L |
| `pharmacy_connections` / `pharmacy_deliveries` | PHI | deny-all | Mixed; Supabase repos primary when cutover on | M |
| `reviews` / `review_public` | PII | deny-all | Review submit from appointment store | M |
| `otp_challenges` / `otp_verification_sessions` | PII | deny-all | Cloud Functions Admin only | S (keep Admin) |
| Community catalogs (`community_medicines`, etc.) | Low | deny-all | Legacy suggestion UIs | M |
| `medical_directory` / `lab_catalog` | Low | deny-all | Directory screens | M |

---

## Ordered launch plan

### Must migrate before launch (deny-all safe)

1. **Ambulance** — if feature flag on for store listing.
2. **Shared appointments + reviews** — core doctor/patient scheduling.
3. **In-app notification inbox** — if not replaced by FCM-only UX.
4. **Profile completion service** — remove Firestore writes on onboarding.

### Can stay on Firestore temporarily (with tightened rules — **do not deploy without review**)

Only for collections still actively read/written **from the client** during phased cutover. Example **illustrative** rules (NOT deployed):

```
// appointments — patient or assigned doctor only
match /appointments/{id} {
  allow read: if request.auth != null && (
    resource.data.patientId == get(/databases/$(database)/documents/users/$(request.auth.uid)).data.profileId
    || resource.data.doctorId == get(/databases/$(database)/documents/users/$(request.auth.uid)).data.profileId
  );
  allow create, update: if request.auth != null && (
    request.resource.data.patientId == get(...).data.profileId
    || request.resource.data.doctorId == get(...).data.profileId
  );
}

// in_app_notifications — ownerUid field required on docs
match /in_app_notifications/{id} {
  allow read, update: if request.auth != null && resource.data.ownerUid == request.auth.uid;
  allow create: if false; // server only
}
```

Prefer **Postgres RLS** over re-opening Firestore for PHI.

### Server-only Firestore (keep Admin SDK)

- OTP challenge fallback collections (until Redis-only proven).
- Abuse rate limits when `RATE_LIMIT_BACKEND=firestore`.
- One-off migration scripts.

---

## Per-file summary (deny-all impact)

| Module / file | Active Firestore? | Breaks without Firestore |
|---------------|-------------------|---------------------------|
| `profile_photo_uploader.dart` | S3 + Supabase when cutover on; legacy path if not | S3 profile upload works on Postgres-primary; legacy base64/Firestore path breaks |
| `promoted_ads_service.dart` | Supabase upsert when no override | Ads work via Supabase |
| `lab_*` repositories | Read helpers; submit Supabase-only | Lab report submit OK |
| `ambulance_repository.dart` | **Yes** | Ambulance breaks |
| `in_app_notification_service.dart` | **Yes** | In-app inbox sync breaks |
| `prescription_repository.dart` | Mixed | Prescribing UI where not Supabase repo |
| `shared_appointments_store.dart` | **Yes** | Appointment lists break |
| `profile_completion_service.dart` | **Yes** | Legacy onboarding paths break |
| `doctor_shell.dart` / features | Mixed | Depends on locator wiring |
| Backend `functions/` | Admin sync | Server-side only |

Frontend counts: `features/*` ~81 files, `core/*` ~68 files reference Firestore APIs (inventory for cutover).
