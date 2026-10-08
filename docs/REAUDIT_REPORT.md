# DoctorNect re-audit (after `317af8d`)

Read-only check of commits `b84a4ee`, `c8d037f`, `0bf62c7`, `6c14d62`, and `542ea9b`. Claims below are from the current tree, `git diff 317af8d..HEAD`, and the commands in section 6. `docs/FIXES_REPORT.md` was not used as evidence.

## 1. Verdict

**FIX FIRST**

1. A patient booking now creates the Firestore appointment in `bookAppointment`, then keeps a different in-memory id (`pa` + timestamp). Cancel and reschedule persist that in-memory id, so they write a second document (or fail once patient creates are denied) and leave the callable document unchanged (`frontend/lib/core/data/shared_appointments_store.dart:654-664`, `frontend/lib/core/firebase/repositories/appointment_repository.dart:34-39`, `backend/firestore.rules:537`).
2. Web ambulance login calls `verifyAmbulanceDriverLoginHttp`. That handler returns 503 whenever `ENFORCE_AMBULANCE_HTTP_APP_CHECK` is not `true`, and the flag defaults to false (`frontend/lib/core/firebase/ambulance_callable_client.dart:26-29`, `backend/functions/index.js:1478-1485`, `backend/functions/http_endpoint_security.js:62-65`). Mobile still uses the callable.
3. Appointment sync no longer invents age, token, or slot, but other payloads still invent `age || 30` and `experience_years || 1` (`backend/functions/cross_role_sync.js:843`, `backend/functions/cross_role_sync.js:1491`). Do not set `ENABLE_SUPABASE_SYNC=on` until those are removed. The identity SQL has not been executed (`backend/supabase/migrations/20261008000001_firebase_uid_identity.sql:5-10`).

## 2. Scope check

`git log --oneline 317af8d..HEAD` is exactly these five commits, in this order:

- `542ea9b` fix(audit): phase 5 M-1 M-2 M-6 M-7 M-8 M-9 L-1 L-2 L-3
- `6c14d62` fix(audit): phase 4 H-3 H-4
- `0bf62c7` fix(audit): phase 3 H-1 H-2 H-5 M-5
- `c8d037f` fix(audit): phase 2 C-1 C-2 M-3 M-4
- `b84a4ee` fix(audit): phase 1 C-3 H-6 L-4 L-5

No other commit is in the range. `git diff --stat 317af8d..HEAD` is 45 files, +2179 / −1437.

Working tree outside that range: `docs/ARCHITECTURE_AUDIT_REPORT.md` is modified and unstaged. It is not part of the five commits.

Every file in the diff maps to a finding, a test, a checklist, or a new migration:

| File | Finding |
| --- | --- |
| `backend/functions/cross_role_sync.js`, `test/cross_role_sync.test.js` | C-3, L-4 |
| `backend/functions/index.js`, `test/supabase_sync_gate.test.js` | H-6, M-8 |
| `backend/supabase/migrations/20261008000001_firebase_uid_identity.sql`, `backend/supabase/config.toml`, `frontend/lib/core/supabase/supabase_bootstrap.dart`, `backend/functions/registration_otp.js` (claims), `test/firebase_supabase_claims.test.js`, `frontend/test/supabase_firebase_access_token_test.dart` | C-1 |
| `backend/supabase/functions/sync-to-firestore/index.ts`, `frontend/lib/features/patient/booking/booking_flow_screen.dart`, `frontend/lib/core/data/shared_appointments_store.dart`, `test/sync_to_firestore_honest.test.js`, `frontend/test/patient_cancel_firestore_test.dart` | C-2 |
| `frontend/lib/features/doctor/clinical/data/clinical_prescription_store.dart`, `frontend/test/prescription_merge_test.dart` | M-3 |
| `frontend/lib/features/patient/records/add_record_screen.dart`, `frontend/lib/features/patient/profile/health/vaccination_records_screen.dart` | M-4 |
| `backend/firestore.rules`, `backend/functions/appointment_slots.js`, `frontend/test/booking_uses_callable_test.dart`, `test/doctor_slots.test.js`, `test/firestore_directory_and_appointments.rules.test.js` | H-1 |
| `backend/functions/promoted_ads.js`, `test/promoted_ads_verification.test.js` | H-2, M-5 |
| `frontend/lib/features/admin/promoted_ad_review_screen.dart`, `frontend/lib/features/admin/super_admin_verification_screen.dart` | H-5 |
| `backend/functions/registration_otp.js`, OTP tests | H-3, H-4 |
| `docs/DEPLOY_CHECKLIST.md` | M-1, L-5 |
| `backend/functions/s3_storage.js`, `test/s3_storage.test.js` | M-2 |
| `backend/supabase/migrations/20261008000002_super_admin_from_admin_users.sql` | M-6 |
| `docs/SECRET_ROTATION_CHECKLIST.md` | M-7 |
| `backend/functions/test/http_endpoint_security.test.js` | M-8 |
| `frontend/lib/features/patient/profile/settings/notifications_settings_screen.dart` | M-9 |
| `frontend/lib/features/patient/profile/data/patient_profile_mock.dart` | L-1 |
| deleted `*_registration_screen.dart` (five files) | L-2 |
| deleted `frontend/lib/widgets/promoted_ad_banner_card.dart` | L-3 |
| `docs/FIXES_REPORT.md` | allowed checklist |

`appointment_slots.js` is the one behavior change that goes past the original finding text: the same `patientId` with a different `patientName` is no longer rejected (`backend/functions/appointment_slots.js:548-563`). Max 3 and `slotShareReason` are unchanged. That is a product change, not a secret or a permissions widening of the rules.

`git diff --name-only 317af8d..HEAD` contains no `.env*`, `secrets*.txt`, service-account JSON, `firebase_options.secrets.dart`, or `baseline_functions.json`. `git ls-files secrets.txt` is empty. `.gitignore` still has `secrets.txt`, `secrets*.txt`, `firebase_options.secrets.dart`, and `baseline_functions.json` (`.gitignore:65-66`, `.gitignore:110-112`).

`frontend/scripts/release_build.ps1` and `release_build.sh` are not in the diff. They still inject Supabase defines only when `ENABLE_SUPABASE` is already `1` (`frontend/scripts/release_build.ps1:84-86`). They do not set it. No committed file in the diff sets `ENABLE_SUPABASE_SYNC` to `on`. The gate is `=== 'on'` (`backend/functions/index.js:122`).

`git diff 317af8d..HEAD -- backend/supabase/migrations/` is only the two new files `20261008000001_firebase_uid_identity.sql` and `20261008000002_super_admin_from_admin_users.sql`. No migration at or before `20261002000001` was edited.

Added lines that contain `@` are the seed address `admin@doctornect.com` plus Dart annotations. No other mailbox was added.

## 3. Verification table

| ID | Status | Evidence | Note |
| --- | --- | --- | --- |
| C-1 | PARTIAL | `20261008000001_firebase_uid_identity.sql:12-43`, `:98-116`, `:217-226`; `config.toml:344-346`; `supabase_bootstrap.dart:165`; `registration_otp.js:3205-3212` | `current_firebase_uid()` is `auth.jwt()->>'sub'`. `current_profile_id()` looks up `public.users.firebase_uid`. `book_appointment_atomic` raises `42501` when that sub is null and `PROFILE_NOT_FOUND` when no row matches. DEFINER functions in this file set `search_path = public, pg_temp` and are revoked from `PUBLIC` and `anon`. 23 policies were recreated to compare `current_firebase_uid()` instead of `auth.uid()` (`:303-524`). Custom token `role` is `authenticated`; app role is `app_role`. `app_role` is not read anywhere else in `*.js`, `*.dart`, `*.rules`, or `*.sql`. Firestore rules read `users/{uid}.role`. SQL was not executed. `patients.owner_uid` still defaults to `auth.uid()` in the already-applied `20261001000002` file, which this diff correctly did not edit, so a Firebase insert that omits `owner_uid` still gets null. |
| C-2 | PARTIAL | `booking_flow_screen.dart:698-744`; `shared_appointments_store.dart:909-942`, `:968-1014`; `sync-to-firestore/index.ts:35-42` | Book calls `bookPatientViaCallable` first; the Supabase call is inside try/catch. Cancel persists, then mirrors, and swallows the mirror error. Reschedule persists Firestore only; the screen mirrors only if `isReady` (`booking_flow_screen.dart:568-576`). The edge function returns 501 `{error: not_implemented}` for a normal body and does not return `{success: true}`. It still returns 200 `{skipped: true}` for `doctor_firestore` / `reconciler_bot` (`index.ts:24-32`) and 500 on a bad body (`:43-46`). Cancel/reschedule can target the wrong document id (section 4). |
| C-3 | PARTIAL | `cross_role_sync.js:182-236`, `:303-347`; tests at `cross_role_sync.test.js:79`, `:98`, `:120`, `:142` | Appointment payload omits missing age, token, and slot. Origin comes from the document; unknown origin is dead-lettered and not upserted. A missing or older `updatedAt` skips the upsert. No `\|\| '10:00 AM'` remains. `experience_years` still uses `\|\| 1` (`:843`) and a placeholder patient still uses `\|\| 30` (`:1491`). |
| H-1 | PARTIAL | `booking_flow_screen.dart:699`; `shared_appointments_store.dart:706-707`; `firestore.rules:328-349`, `:533-541`; `appointment_slots.js:7`, `:541-577`, `:624-632` | The booking screen calls `bookAppointment` in `asia-south1`. `newAppointmentId()` only allocates `collection('appointments').doc().id` (`booking_flow_helpers.dart:23-26`). `appointment_repository.dart:35` is `set(merge)` used by walk-in create and by updates. Lines 101, 112, and 140 are reads. `addBooking` still client-creates but has no callers. Rules create is walk-in only. Emulator: patient create denied, walk-in create allowed, doctor status-key updates allowed (section 6). Max is still 3. A share reason is still required when the slot already has 1 or 2 bookings. Callable returns `appointmentId` and `tokenNumber`; the client requires a non-empty id and `tokenNumber > 0` (`shared_appointments_store.dart:654-658`). The in-memory id is not that document id. |
| H-2 | PARTIAL | `promoted_ads.js:35-43`; `promoted_ads_service.dart:40-45` | Server table is 6/12/24/72/168/720 hours at 100/180/300/750/1500/5000. Client `defaultPricingTiers` is only 24/72/168/720 at 300/750/1500/5000. The four shared tiers match. 6h/100 and 12h/180 are server-only. |
| H-3 | VERIFIED | `registration_otp.js:1938-1944` | The consume path uses only the role-scoped challenge ref. The comment says a missing doc is not replaced from another role on the same mobile. |
| H-4 | VERIFIED | `registration_otp.js:275-277` | `allowLegacyUnsaltedOtpHash()` is true only when `ALLOW_LEGACY_UNSALTED_OTP_HASH` is the string `true`. Unset is false. |
| H-5 | PARTIAL | `firestore.rules:1227-1231`; `promoted_ads_service.dart:358-361`; `dashboard_shell.dart:26-27`; `super_admin_verification_screen.dart:120`; `promoted_ad_review_screen.dart:33-35`; `promoted_ads.js:18-23` | Reads require `status == active`, or super admin, or owner. Emulator confirmed draft/pending reads fail for non-owners and active ads are readable. The Citywide query is `.where('status', isEqualTo: 'active')` only. `endTime` is filtered in Dart (`promoted_ads_service.dart:343-344`). Rules do not require `endTime`. `firestore.indexes.json` was not in the diff; the existing composite is `promotedAds` `status` ASC + `endTime` ASC (`firestore.indexes.json:249-254`), which this equality query does not need. The review screen is pushed only from the super-admin shell and calls `reviewPromotedAd`. The callable allows a verified `admin@doctornect.com` email or a user-doc role of `super_admin`, `superAdmin`, or `admin`. That role path is not an email-verified check. |
| H-6 | VERIFIED | `index.js:122`, `:1975-1989`, `:2006-2118` | `ENABLE_SUPABASE_SYNC` is on only when the env value is `on`. Exports inside the two gates: `syncAppointmentToSupabase`, `syncPrescriptionToSupabase`, `syncDoctorToSupabase`, `syncDoctorAvailabilityToSupabase`, `syncDoctorBlockedDatesToSupabase`, `syncMedicalStoreToSupabase`, `syncPharmacyConnectionToSupabase`, `syncPharmacyDeliveryToSupabase`, `syncLabToSupabase`, `syncLabCatalogTestToSupabase`, `syncLabBookingToSupabase`, `syncLabOrderToSupabase`, `syncLabConnectionToSupabase`, `syncAmbulanceToSupabase`, `syncAmbulancePrivateSettingsToSupabase`, `syncAmbulanceBroadcastToSupabase`, `syncAmbulanceRequestToSupabase`, `syncAmbulanceInviteToSupabase`. S3 exports at `:2001-2004` are outside the gate and are not `sync*ToSupabase`. `syncReviewHelpfulCount` (`:1729`) is a different name. `reviewPromotedAd` and `razorpayWebhook` stay unconditional. |
| M-1 | VERIFIED | `index.js:120`; `abuse_rate_limit.js:88`; `s3_storage.js:638`; `DEPLOY_CHECKLIST.md:14` | `OTP_REDIS_MIRROR` is on only for the string `on`. `RATE_LIMIT_BACKEND` defaults to `firestore`. `S3_URL_CACHE` defaults to `off`. The checklist says to leave them off until `REDIS_HOST`, `REDIS_PORT`, and `REDIS_PASSWORD` are bound. |
| M-2 | VERIFIED | `s3_storage.js:401-434`, `:468-561`, `:613-623`; `storage_feature_flag.dart:37-38`; `s3_storage.test.js:198` | Upload of `pharmacy_kyc`, `lab_kyc`, and `ambulance_kyc` requires the matching role and `profileId`, or super admin. A patient is rejected. `authorizeRead` does not allow those prefixes, so a non-admin read is false (test asserts false at `s3_storage.test.js:246-251`). `authorizeDelete` allows the owner (`:613-623`). `use_s3_storage` `setDefaults` is false. |
| M-3 | VERIFIED | `clinical_prescription_store.dart:19-30`, `:275-311` | Merge writes Firestore rows over the same `prescriptionId` after Supabase rows. Supabase fetch runs only for a non-doctor context, on the first page, and only when `isReady`. |
| M-4 | VERIFIED | `add_record_screen.dart:206-207`; `vaccination_records_screen.dart:246-247` | Health-record and vaccination saves call Firestore. The record screen no longer calls `addHealthRecord` on Supabase. |
| M-5 | VERIFIED | `promoted_ads.js:517-524`, `:552` | Empty `RAZORPAY_WEBHOOK_SECRET` returns 503 JSON and returns. A present secret is checked with `timingSafeEqual`. The unit test `missing RAZORPAY_WEBHOOK_SECRET fails closed with 503` passed in the emulator run. Whether the secret exists in Secret Manager was not checked. The function's `secrets:` binding will still fail deploy until that secret exists. |
| M-6 | PARTIAL | `20261008000002_super_admin_from_admin_users.sql:19-50`; `firestore.rules:126-128`; `promoted_ads.js:18-23` | SQL `is_super_admin()` joins `private.admin_users` to `auth.users` on the verified JWT email. The seed insert is only `admin@doctornect.com`. SQL was not executed. Firestore `isSuperAdmin()` is a different source: user-doc role `super_admin` / `superAdmin` / `admin`, or verified email `admin@doctornect.com`. That split is stated in `docs/FIXES_REPORT.md` and is acceptable only as a documented deviation. Rules cannot read Postgres. |
| M-7 | VERIFIED | `docs/SECRET_ROTATION_CHECKLIST.md:5-11`; `.gitignore:65-66`, `:110-112` | Checklist names MSG91, Razorpay, CCAvenue, AWS, Redis, Supabase, and Firebase keys. No values. Ignore rules still cover the secret filenames. `git ls-files secrets.txt` is empty. |
| M-8 | REGRESSION | `index.js:1478-1489`; `http_endpoint_security.js:62-65`; `ambulance_callable_client.dart:26-51` | The HTTP handler returns 503 until the flag is `true`, then calls `assertAmbulanceHttpAppCheck` with `enforce: true`. The flag defaults to false. The web client always uses this HTTP function, so web ambulance login is blocked on a normal deploy. The mobile callable `verifyAmbulanceDriverLogin` (`index.js:1425`) is not gated by this flag. |
| M-9 | VERIFIED | `notifications_settings_screen.dart:51`, `:216` | `nameCtrl` is created before the dialog builder and disposed in `showDialog(...).whenComplete`. |
| L-1 | VERIFIED | `patient_profile_mock.dart:623` | `supportEmail` remains. `git grep` of `supportPhone` and `supportWhatsApp` under `frontend/lib` found no matches. |
| L-2 | VERIFIED | diff deletes the five `*_registration_screen.dart` files | `git grep` of the five class names and file names under `frontend/` found no Dart references. `flutter analyze` reported no issues. |
| L-3 | VERIFIED | diff deletes `promoted_ad_banner_card.dart` | `git grep` of `PromotedAdBannerCard` and the file name found only `frontend/scripts/refactor/unused_dart_files.txt:39`, which is a stale path list, not an import. Patient home still streams active ads (`patient_home_screen.dart:298-299`). |
| L-4 | VERIFIED | `cross_role_sync.js:9-16` | The header describes compare-and-skip on `updatedAt` and dead-letter when origin cannot be determined. That matches `syncFirestoreAppointmentToSupabase` (`:303-347`). It does not describe the remaining invented defaults at `:843` and `:1491`. |
| L-5 | VERIFIED | `DEPLOY_CHECKLIST.md:9-10` | The checklist says to answer No when Firebase asks to delete functions not in the source tree, and it names `ssrmedibond45fad`. |

## 4. Regressions and new risks

Ordered by severity. Nothing here was changed.

1. **Patient cancel and reschedule write the wrong appointment id.** `bookPatientViaCallable` stores `appointmentId` from the callable and sets `id` to `pa` plus the current timestamp (`shared_appointments_store.dart:654-664`). It does not call `_persist`. `cancelByPatient` and `reschedulePatient` look up `record.id` and `_persist` calls `appointment.save`, which `set`s `appointments/{record.id}` (`appointment_repository.dart:34-39`). That path is a create. After the new rules, a patient create is denied (`firestore.rules:537`). The document `bookAppointment` created stays active. A snapshot merge later replaces the optimistic row (`shared_appointments_store.dart:236-247`, `patient_appointment_watcher.dart:19`), so cancel works only after that refresh. Fix: set the in-memory `id` to the callable `appointmentId` before any cancel or reschedule, and do not `set` a second document.

2. **Web ambulance login is fail-closed by default.** `AmbulanceCallableClient.verifyDriverLogin` uses `verifyAmbulanceDriverLoginHttp` when `kIsWeb` (`ambulance_callable_client.dart:26-29`). The handler returns 503 before any PIN check while `ENFORCE_AMBULANCE_HTTP_APP_CHECK` is not `true` (`index.js:1478-1485`). Fix: keep the existing callable for web until App Check enforcement is turned on in the same deploy that starts requiring the header, or return 503 only when a separate kill-switch is set, and leave the default path that works today unchanged.

3. **Sync still invents clinical numbers outside the appointment payload.** `experience_years` falls back to 1 (`cross_role_sync.js:843`). Placeholder patient age falls back to 30 and a zero mobile (`:1491`). Fix: omit those fields when the Firestore document does not have them, the same way `buildAppointmentSupabasePayload` omits age. Do not set `ENABLE_SUPABASE_SYNC=on` before that.

4. **`refreshForPatient` prefers Supabase and returns without reading Firestore when `isReady` is true** (`shared_appointments_store.dart:277-287`). Release scripts do not set `ENABLE_SUPABASE`, so this is latent. If that flag is turned on, a failed or empty Supabase mirror hides the Firestore booking. Fix: always merge the Firestore query, and treat Supabase as a secondary read.

5. **Storage rules emulator: owner KYC upload is denied.** Four tests failed (section 6). `storage.rules` is not in `317af8d..HEAD`, so this is not one of the 22 fixes. Do not deploy Storage rules with this batch until those tests pass. Firestore appointment and `promotedAds` rules in the same run passed.

6. **`addBooking` is still a patient client create** (`shared_appointments_store.dart:714-716`). Nothing calls it. The new rules would deny it. Fix: delete it so a later caller cannot bypass `bookAppointment`.

7. **`appointmentCreateValid` is now unused** (`firestore.rules:328-336`). Create no longer calls it. That is intentional for patients. A doctor client create that is not `source == walkin` with `patientId` matching `^wi\d+$` is denied. Walk-in still sets `source: 'walkin'` and a `wi` patient id (`shared_appointments_store.dart:864-900`) and the mapper writes `source` (`appointment_firestore_mapper.dart:83-84`).

8. **Same account, different name, same slot is now allowed** (`appointment_slots.js:553-563`). Cap 3 and the share-reason check still apply. Confirm that is the intended family-booking rule before deploy.

9. **`sync-to-firestore` can still return 200** for a loop-prevention skip (`index.ts:24-32`). It never returns `{success: true}`. Do not attach a database webhook. The header already says not to (`index.ts:1-4`).

## 5. Demo-accounts trace

Production does not use `DEFAULT_DEMO_CONFIG`. `getDemoConfig` returns that constant only when the project is not the production project (`registration_otp.js:115-121`). On the production project, outside the Functions emulator, it returns the `app_config/demo_accounts` document only when the document exists and `demoLoginEnabled === true` (`:88-105`). Otherwise it returns null (`:115-118`).

`assertProductionOtpSafety` runs on a real Cloud Functions instance and throws `failed-precondition` when `collectProductionOtpViolations` is non-empty (`production_otp_guard.js:98-117`). It does not run during deploy analysis or the emulator (`:103-105`).

`isDemoPhone` then matches the submitted digits to `demoPhones` for that role only (`registration_otp.js:156-164`). Env-configured numbers are rejected on the production project (`:167-169`). Super admin also requires `enableDemoSuperAdmin` or `demoSuperAdminEnabled` (`:145-152`). Send stores `config.demoOtp` as the challenge code and refuses to send if that field is missing (`:1800-1810`). Verify accepts that code inside `consumeOtpChallengeAtomically` (`:2013-2014`). If the challenge is tagged `demoAccount` and `demoLoginEnabled` is not true, the challenge is deleted and the result is `stale_demo` (`:2004-2009`).

Firestore document `app_config/demo_accounts` must contain:

- `demoLoginEnabled`: `true`
- `demoOtp`: `000000`
- `demoPhones`: a map of arrays, one array per role key used at login (`patient`, `doctor`, `medicalStore`, `lab`, `ambulance`, and `superAdmin` if that role is reviewed). The numbers have to be the Play review numbers already configured for those roles. This report does not copy them.
- `enableDemoSuperAdmin`: `true` if the super-admin review number must work. If this is false or absent, that role is not a demo phone even when listed.

If the document is missing, or `demoLoginEnabled` is not `true`, `getDemoConfig` returns null, `isDemoPhone` is false, and the number is a normal SMS OTP login. `000000` is not accepted.

These environment variable names must be unset or empty on the production Cloud Functions runtime or cold start throws: `OTP_TEST_MODE`, `DEMO_PHONE_PATIENT`, `GOOGLE_PLAY_REVIEW_PHONE`, `TEST_PHONE_NUMBER`, `DEMO_PHONE_DOCTOR`, `DEMO_PHONE_MEDICAL_STORE`, `DEMO_PHONE_PHARMACY`, `DEMO_PHONE_LAB`, `DEMO_PHONE_AMBULANCE`, `DEMO_PHONE_SUPER_ADMIN` (`production_otp_guard.js:6-16`, `:70-76`).

## 6. Test results

| Command | Result |
| --- | --- |
| `flutter analyze` in `frontend/` | exit 0. `No issues found! (ran in 351.5s).` |
| `flutter test` in `frontend/` | exit 0. 415 passed, 0 failed. |
| `node --test` in `backend/functions/` | exit 0. 258 tests, 250 passed, 8 skipped, 0 failed. The 8 skips are the emulator-gated rules files. |
| `npx firebase emulators:exec --only firestore,storage --project demo-doctornect-reaudit` with the eight previously skipped test files | exit 1. Java is present (OpenJDK 21). Emulators started. 128 tests, 124 passed, 4 failed, 0 skipped. |

Failures, all Storage rules, all owner upload denied with `storage/unauthorized`:

- `test/storage_doctor_kyc.rules.test.js`: owner doctor can upload KYC but cannot read it back
- `test/storage_provider_kyc.rules.test.js`: pharmacy owner can upload KYC but cannot read it back
- same file: lab owner can upload KYC but cannot read it back
- same file: ambulance owner can upload KYC but cannot read it back

Firestore rules in that run did execute. Passed cases include patient direct create denied, verified doctor walk-in create allowed, patient and doctor update key locks, and `promotedAds` draft/pending reads denied for non-owners. `storage.rules` is not in the fix diff.

## 7. Still UNVERIFIED

- Hosted Supabase has not had `20261008000001` or `20261008000002` applied, and third-party Firebase auth in the dashboard was not opened.
- No SQL session was opened, so `book_appointment_atomic` anon rejection and the rewritten policies were not executed.
- Secret Manager was not listed. `RAZORPAY_WEBHOOK_SECRET` presence is unknown. Razorpay dashboard webhook URL and signing secret were not checked.
- Play Console review accounts were not checked against the live `app_config/demo_accounts` document.
- A real device was not used to book, cancel, and reschedule with `ENABLE_SUPABASE` unset.
- App Check enforcement for ambulance HTTP login was not turned on, and the web client was not logged in against a deployed function.
- Remote Config `use_s3_storage` in the Firebase console was not read. The code default is false.
- Secret rotation checkboxes are unticked. Rotation was not confirmed with the vendors.
- `ssrmedibond45fad` was not listed from the live project in this pass. The checklist still says to answer No.

## 8. Recommended deploy order

Do not deploy this tree as it stands.

1. Fix the in-memory appointment id so cancel and reschedule update the `bookAppointment` document. Add a test that the persisted document id equals the callable `appointmentId`.
2. Decide the web ambulance HTTP behavior. A deploy of current `index.js` with the flag unset returns 503 to `AmbulanceCallableClient` on web. Ship the callable path, or turn App Check on and set `ENFORCE_AMBULANCE_HTTP_APP_CHECK=true` in the same change that starts requiring the header.
3. Leave `ENABLE_SUPABASE` unset on release builds and leave `ENABLE_SUPABASE_SYNC` unset. Do not register the `sync*ToSupabase` functions. Do not apply the two SQL files and do not add a webhook on `sync-to-firestore` until a later explicit Supabase cutover.
4. After the client id fix is in a build users already have, deploy already-live functions by name. When the CLI asks to delete functions that are not in the source tree, answer No. That keeps `ssrmedibond45fad`.
5. Deploy Firestore rules only after that build is installed. The emulator shows patient client creates are denied. Installed builds that still create `appointments` from the client will break.
6. Create `RAZORPAY_WEBHOOK_SECRET` in Secret Manager out of band, then deploy `functions:reviewPromotedAd` and `functions:razorpayWebhook` by name. Confirm the production cold start does not have `OTP_TEST_MODE` or any `DEMO_PHONE_*` name set, and that `app_config/demo_accounts` matches section 5, before that functions deploy.
7. Do not deploy Storage rules with this batch. The four owner KYC upload tests failed against the current `storage.rules`.
