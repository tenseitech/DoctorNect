# Audit fix report

Local commits only. Nothing was pushed or deployed. `ENABLE_SUPABASE` is still unset in the release scripts.

| ID | Status | What changed | Tests | Deviation |
| --- | --- | --- | --- | --- |
| C-1 | fixed-needs-manual-step | Firebase third-party auth in `config.toml`. Client passes the Firebase ID token via `accessToken`. New migration `20261008000001_firebase_uid_identity.sql` resolves `public.users.firebase_uid` from the JWT `sub`. Custom token `role` is `authenticated`; the app role is `app_role`. | Dart test checks the access-token callback only. SQL in the migration header was not executed. | Not verified in production. Hosted Supabase still needs the dashboard Firebase provider and this migration. Firestore rules read `users/{uid}.role`, not the custom claim, so renaming the claim is safe. |
| C-2 | fixed-needs-manual-step | Patient book, cancel, and reschedule write Firestore first. Supabase mirrors are best-effort. `sync-to-firestore` returns HTTP 501 and must not have a webhook. | Cancel tests: Firestore update when Supabase succeeds and when it throws. Source test that the function does not return success for a write it does not do. | Not verified on a device. A Supabase maintenance error on the mirror no longer blocks the Firestore write. |
| C-3 | fixed | Missing age, token, and slot are omitted. Unknown writer origin goes to the DLQ and is not synced. Stale `updatedAt` snapshots are skipped. | `cross_role_sync.test.js` | Current patient docs have no origin field, so they DLQ if sync is later turned on. That is intentional. |
| H-1 | fixed-needs-manual-step | New patient bookings call `bookAppointment` (asia-south1). Client create of `appointments` is denied. Walk-in create stays allowed. | Dart test that booking uses the callable and does not persist the document itself. Rules tests updated; they skip without the Firestore emulator. | `appointment_slots.js` allows a second booking in the same slot when `patientName` differs, still capped at 3 and still requiring `slotShareReason`. Deploying these rules will break already-installed builds that create appointments directly. |
| H-2 | fixed-needs-manual-step | `AD_PRICING_TABLE` adds `720: 5000`. Super-admin screen lists `pending_approval` ads and calls `reviewPromotedAd`. | Pricing test. Existing review handler tests. | No 15-day / 360h plan exists on the client, so none was added. Final table: 6=100, 12=180, 24=300, 72=750, 168=1500, 720=5000 INR. Confirm before deploy. |
| H-3 | fixed | Removed the fallback that consumed any `otp_challenges` doc with the same mobile when the role-scoped doc was missing. | Cross-role missing-doc test. Existing mismatch test still expects `permission-denied`. | |
| H-4 | fixed | `ALLOW_LEGACY_UNSALTED_OTP_HASH` defaults false. Set it to `true` for an instant rollback. | Default-off rejection and flag-on acceptance. | |
| H-5 | fixed-needs-manual-step | `promotedAds` read requires `status == active`, or the owner, or a super admin. Citywide query already filters `status == active`. Existing `status` + `endTime` index left unchanged. | Rules tests updated; emulator not running, so they were skipped. | Rules are not deployed. |
| H-6 | fixed | `sync*ToSupabase` exports register only when `ENABLE_SUPABASE_SYNC=on`. | Gate test reads the source. | |
| M-1 | documented-only | No code change. Checklist says Redis flags stay off until `REDIS_*` secrets are bound, and Redis stays fail-open. | | |
| M-2 | fixed | Pharmacy, lab, and ambulance KYC upload purposes added, with owner checks. `use_s3_storage` default remains false. | `s3_storage.test.js` | Remote Config was not changed. |
| M-3 | fixed | Prescriptions merge by id. Firestore wins. | Partial Supabase set plus a fuller Firestore set. | Real file is `frontend/lib/features/doctor/clinical/data/clinical_prescription_store.dart`. |
| M-4 | fixed | Health-record save no longer writes Supabase. Vaccination save was already Firestore-only. Repository code kept. | | Reads were already Firestore-only, so no second list was merged. |
| M-5 | fixed-needs-manual-step | Missing `RAZORPAY_WEBHOOK_SECRET` returns 503. Signature check is unchanged when the secret is present. | Webhook unit test. | The secret was not created. |
| M-6 | fixed-needs-manual-step | New migration `20261008000002_super_admin_from_admin_users.sql`. `private.is_super_admin()` reads only `private.admin_users`, matched by verified JWT email. Seed is `admin@doctornect.com` only. | Not executed. | Firestore rules still use the user-doc role or the verified `admin@doctornect.com` email. Rules cannot read Postgres. |
| M-7 | documented-only | `docs/SECRET_ROTATION_CHECKLIST.md`. No history rewrite. | `git ls-files secrets.txt` is empty. Ignore rules still cover the secrets files and `baseline_functions.json`. | |
| M-8 | fixed | `verifyAmbulanceDriverLoginHttp` returns 503 until `ENFORCE_AMBULANCE_HTTP_APP_CHECK=true`, then requires App Check. Flag default stays false. | Source gate test plus the existing default-false test. | `getValidationRulesHttp` is unchanged. It serves declarative validation rules and is low-sensitivity. |
| M-9 | fixed | Medicine-name `TextEditingController` is disposed when the dialog closes. | | |
| L-1 | fixed | Deleted unused `supportPhone` and `supportWhatsApp`. | Grep found no other references. | |
| L-2 | fixed | Deleted the five legacy `*_registration_screen.dart` files. | Grep found no route or import. | |
| L-3 | fixed | Deleted `promoted_ad_banner_card.dart`. | No call sites. | It opens the provider ad manager. The patient Citywide list uses `HomeBannerCarousel` / `streamActiveAds`, so the widget was not a duplicate banner. |
| L-4 | fixed | Header comment matches compare-and-skip. | Stale snapshot test. | |
| L-5 | fixed | Checklist says answer No when Firebase asks to delete functions not in source. That protects `ssrmedibond45fad`. | | |

## How the five demo accounts stay valid

`assertProductionOtpSafety` rejects a production cold start when `OTP_TEST_MODE` is on (that is the `DEV_TEST_OTP` `123456` switch) or when `DEMO_PHONE_*` env keys are set. `isTestMode()` is always false on the production project. `getDemoConfig()` does not use `DEFAULT_DEMO_CONFIG` in production.

The review accounts stay on only when Firestore `app_config/demo_accounts` has `demoLoginEnabled: true`, `demoOtp: 000000`, and the five phone numbers. That path was not removed.

## Manual steps only you can do

1. Create `RAZORPAY_WEBHOOK_SECRET` from the Razorpay dashboard, then deploy `razorpayWebhook` by name. Do not paste the value here.
2. Confirm the price table above before deploying promoted-ad functions.
3. On the hosted Supabase project: do not register a webhook on `sync-to-firestore`. Enable Firebase third-party auth for `medibond-45fad` only if you turn Supabase on. Apply the two new migrations. Release builds still leave `ENABLE_SUPABASE` unset.
4. Turn on App Check enforcement for ambulance HTTP login only after the web client sends the header.
5. Sign the rotation checklist after each old value is revoked.
6. On a build without `ENABLE_SUPABASE`, book and cancel as a patient and confirm the doctor sees both. Deploy the new Firestore rules only after that build is in users' hands.

## Commits

- Phase 1 `b84a4ee` — C-3 H-6 L-4 L-5
- Phase 2 `c8d037f` — C-1 C-2 M-3 M-4
- Phase 3 `0bf62c7` — H-1 H-2 H-5 M-5
- Phase 4 `6c14d62` — H-3 H-4
- Phase 5 is the commit that adds this file.

## Round 2

Re-audit verdict was FIX FIRST. Nothing was pushed or deployed. `ENABLE_SUPABASE` and `ENABLE_SUPABASE_SYNC` were not set.

| Task | Status | Files | Tests | Deviation |
| --- | --- | --- | --- | --- |
| A | fixed | `shared_appointments_store.dart`. Deleted unused `addBooking`. `booking_flow_screen.dart` already called the callable and was not edited. `patient_appointment_watcher.dart` merges Firestore docs by document id, which is the callable id, so it was not edited. | `booking_uses_callable_test.dart`: stored id equals the callable id; cancel and reschedule persist only that id. Rules: patient `set` merge cancel and reschedule on the existing doc succeed; a new patient create still fails. Emulator: 19 passed in the appointment rules file, including that test. | The repository still `set`s with merge. On an existing callable document, only changed keys count. Cancel changes `doctorStatus`, `cancellationReason`, and `updatedAt`. Reschedule changes `dateTime`, `slotLabel`, `tokenNumber`, `patientStatus`, `doctorStatus`, `wasRescheduled`, and `updatedAt`. Those keys are already allowed at `firestore.rules:548-561`. Rules were not loosened. |
| B | fixed | `index.js`, `http_endpoint_security.test.js`, `DEPLOY_CHECKLIST.md`. Web client was read only. | Flag unset: handler source has no 503 and still calls `runVerifyAmbulanceDriverLogin` after `assertAmbulanceHttpAppCheck` with the flag. Flag `true` without a token is rejected. Flag `true` with a token proceeds. | Restored the pre-`317af8d` default. App Check is required only when `ENFORCE_AMBULANCE_HTTP_APP_CHECK` is `true`. The mobile callable was not changed. |
| C | fixed | `cross_role_sync.js`, `cross_role_sync.test.js` | Missing experience is omitted. Age 0 is kept. Placeholder without mobile is skipped. Present age is copied. Missing mobile is dead-lettered and not inserted. | `doctors.experience_years` is `NOT NULL DEFAULT 1` (`20260923000001_doctornect_schema.sql:107`), so the field is omitted and the sync is not dead-lettered. `patients.age` is nullable (`:218`), so it is omitted. `patients.mobile` is `NOT NULL` with no default (`:217`), so the placeholder is skipped and dead-lettered. Other invented phone fallbacks in this file were left as they were. |
| D | fixed | `shared_appointments_store.dart`, `patient_refresh_firestore_test.dart` | Supabase empty or throwing still returns the Firestore booking. The same id keeps the Firestore row. | Supabase stays off in release builds. The merge runs only when Supabase is ready or a test override is set. Firestore is always queried. |
| E | kept | No source edit. | The existing family-slot test in `doctor_slots.test.js` stays. | Kept. See below. |
| F | verified, no source change | None. | Storage tests were run on `317af8d` in a temporary worktree, then the worktree was removed. | Not a client privilege escalation. Storage failures also fail on the base commit. See below. |

### Task E

Taken branch: **keep** the same-account, different-name slot exception.

`git show 317af8d:backend/functions/appointment_slots.js` rejected any second booking with the same `patientId` and no cancellation, regardless of name. Commit `0bf62c7` (`fix(audit): phase 3 H-1 H-2 H-5 M-5`) changed that to reject only when the incoming name is empty or equals the existing name, and added `same account can book a different family member in a shared slot`.

That change is required by the callable booking path. Before that commit, `booking_flow_screen.dart` already called `processBooking` once for the account holder and once per family member. Each call uses `PatientSession.loggedInPatientId` and a different `patientName`. Those writes used to be client creates, which did not hit this server check. H-1 moved them onto `bookAppointment`. Without the name check, the second person in the same slot would get `failed-precondition`. Max 3 and the share-reason rule were not changed.

### Task F

A normal client cannot write `super_admin`, `superAdmin`, or `admin` onto `users/{uid}`.

Create allows only `doctor`, `patient`, `medicalStore`, `medical`, `lab`, or `ambulance` (`firestore.rules:441`), and the matching `profile_claims` role is the same list (`firestore.rules:415`). Update by the owner requires `request.resource.data.role == resource.data.role` and forbids `role` in `affectedKeys()` (`firestore.rules:454-455`). `isSuperAdmin()` can still write the document (`firestore.rules:451`). That is not a self-grant.

`reviewPromotedAd` still treats an existing user-doc role of `super_admin`, `superAdmin`, or `admin` as super admin (`promoted_ads.js:18-23`). A client cannot create that role through these rules. This is not a new privilege escalation.

The four owner KYC upload tests fail on `317af8d` as well: 16 tests, 12 passed, 4 failed, same four names (`owner doctor`, `pharmacy owner`, `lab owner`, `ambulance owner` cannot upload). `storage.rules` was not edited.

### Round 2 commits

- `96ff5da` fix(reaudit): A patient cancel hits callable appointment id
- `7e32769` fix(reaudit): B web ambulance login stays open by default
- `2e9ac19` fix(reaudit): C omit invented sync numbers
- `9250db1` fix(reaudit): D patient refresh always reads Firestore
- Task E has no commit. The slot hunk was kept.
- Task F has no source commit.

### Round 2 test counts

After Task D, which is the last source change:

- `flutter analyze`: exit 0, no issues.
- `flutter test`: 418 passed, 0 failed.
- `node --test`: 261 tests, 253 passed, 8 skipped, 0 failed.

Final emulator (`firestore,storage`, project `demo-doctornect-reaudit`, the eight rules files): 129 tests, 125 passed, 4 failed, 0 skipped. The four failures are the same owner KYC upload tests, and they also fail on `317af8d`.

### Left unchanged

- Other invented phone and city fallbacks in `cross_role_sync.js` besides doctor experience and the patient placeholder age and mobile.
- `sync-to-firestore` still returns 200 for a loop-prevention skip.
- `appointmentCreateValid` is unused. Patient create stays denied.
- Storage rules and the four failing KYC upload tests.
- `docs/ARCHITECTURE_AUDIT_REPORT.md` remains an unstaged local edit. `docs/REAUDIT_REPORT.md` is untracked.
