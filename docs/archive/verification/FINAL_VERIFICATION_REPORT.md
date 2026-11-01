# Final verification report

Verified at `401ac69881c0400abc32f6fb6126b78df9235eaf` before this document. Source was not modified. No deploy was run. Secret values are not printed.

The architecture table has 23 rows. The requested 22 are C-1..C-3, H-1..H-6, M-1..M-8, and L-1..L-5. M-9 is tagged Low in that table and is included as an extra row.

## Step 0 — baseline

`git log --oneline -25` ends at `401ac69 fix(rules): patient reschedule via callable only (not deployed)`. `git status` was clean. `git tag --points-at HEAD` and `git rev-parse pre-deploy-2026-10-08` both returned `401ac69881c0400abc32f6fb6126b78df9235eaf`. The branch was ahead of `origin/main` by 36 commits. No mismatch.

### Fresh test counts

| Run | Result |
| --- | --- |
| `node --test` in `backend/functions` | 284 tests, 276 passed, 8 skipped, 0 failed |
| `flutter analyze` | no issues |
| `flutter test` | 426 passed |
| Firestore emulator, `test/firestore_directory_and_appointments.rules.test.js`, project `demo-doctornect-verify` | 28 passed, 0 failed |

The 8 skipped node tests were not executed because the emulator host was unset:

1. `Firestore emulator race test` — `FIRESTORE_EMULATOR_HOST not set` (`doctor_slots_emulator.test.js`)
2. `directory/appointment rules` — same (`firestore_directory_and_appointments.rules.test.js`). This file was then run under the emulator and passed 28/28.
3. `firestore.rules security tests` — same (`promoted_ads_verification.test.js`)
4. `firestore rules tests` — same (`firestore_reviews.rules.test.js`)
5. `firestore rules s3 storage tests` — same (`firestore_s3_rules.test.js`)
6. `firestore profile claims rules tests` — same (`profile_claims_rules.test.js`)
7. `storage doctor kyc rules tests` — Storage emulator not running (`storage_doctor_kyc.rules.test.js`)
8. `storage provider kyc rules tests` — Storage emulator not running (`storage_provider_kyc.rules.test.js`)

The appointments emulator log still prints `evaluation error at L535:24` and then `PERMISSION_DENIED`. Those cases failed closed and the 28 tests passed.

### Secret scan (tracked files)

`git ls-files` found no tracked `.env` or `secrets.txt`. `git log -- secrets.txt` in this clone is empty. `git grep` found no `AKIA…`, no `BEGIN PRIVATE KEY`, and no `"type": "service_account"` JSON. `rzp_live_` appears only as a format check, not a key value: `backend/scripts/verify_production_build_config.js:219-221` and `docs/PRE_CUTOVER_CHECKLIST.md:309`. A unit test uses a fake `rzp_test_…` constant in `backend/functions/test/promoted_ads_verification.test.js:219-220`. No live key value was found.

## Step 1 — the 22 findings

| ID | Severity | Title | Verdict | Evidence | Test | Remaining risk |
| --- | --- | --- | --- | --- | --- | --- |
| C-1 | Critical | Firebase user is anonymous to Supabase RLS | DEFERRED BY DESIGN | `supabase_bootstrap.dart:15-16` reads empty `fromEnvironment` defines. `initialize` returns false when URL or key is empty (`:147-156`). `release_build.ps1:86` and `release_build.sh:111` inject those defines only when `ENABLE_SUPABASE` is `1`. No GitHub workflow sets the flag. | `release_build_supabase_guard_test.dart`: release scripts omit Supabase dart-defines unless `ENABLE_SUPABASE=1` | The identity migration exists and was not executed here. Turning the flag on without a Firebase session still hits the original failure. |
| C-2 | Critical | Supabase writes never reach the doctor Firestore calendar | DEFERRED BY DESIGN | `sync-to-firestore/index.ts:35-41` returns 501 and does not write Firestore. Client Supabase init is a no-op without defines (`supabase_bootstrap.dart:147-156`). | `backend_audit_fixes` / node suite: `sync-to-firestore does not report success for a write it does not perform` | If `isReady` is later true, cancel still mirrors after the Firestore write and swallows the mirror error. |
| C-3 | Critical | Sync invents appointment fields and retags origin | PARTIALLY FIXED | Missing appointment age, token, and slot are omitted (`cross_role_sync.js:671-674`). Unknown origin is dead-lettered (`:745-754`). Leftovers remain: `doc-unknown` (`:650`), `General` (`:653`), `Other` (`:655`), `newVisit` (`:657`), and `new Date()` when `dateTime` is missing (`:646`). | `missing age, token, and slot are omitted from the appointment payload`; `undetermined appointment origin is not upserted` | Those leftovers run only if `ENABLE_SUPABASE_SYNC=on` (`index.js:123`, `:1967`). |
| H-1 | High | Clients create appointments and skip slot capacity | FIXED | Booking calls `bookAppointment` (`shared_appointments_store.dart:750-751`) and stores the returned id (`:697-708`). Rules allow create only for a walk-in (`firestore.rules:534`). Capacity and the token counter are inside `runTransaction` (`appointment_slots.js:556-623`). | Rules: `signed-in patient cannot create an appointment directly`. Callable tests in `doctor_slots.test.js` passed in this `node --test` run. | Rules are not deployed. Already-installed builds that still create appointments will break when they are. |
| H-2 | High | Paid ads stay pending; 720h checkout rejected | FIXED | `AD_PRICING_TABLE` includes 720 hours at 5000 (`promoted_ads.js:35-42`). `reviewPromotedAdHandler` requires a super admin (`:715-717`). | `AD_PRICING_TABLE includes every client plan amount`; `super admin can approve a pending_approval ad` | Approving one's own ad is not rejected (`:732-749`). See NEW-1. |
| H-3 | High | OTP consume can use another role's challenge | FIXED | Consume reads only the role-scoped doc (`registration_otp.js:1938-1944`). | `otp_verification_race.test.js`: `missing role-scoped challenge is not filled from another role on the same mobile` | None seen on this path. |
| H-4 | High | Unsalted OTP hashes still verify | PARTIALLY FIXED | `allowLegacyUnsaltedOtpHash` is true only for the string `true` (`registration_otp.js:276-279`). Verify accepts a legacy hash only then (`:352-354`). `hashOtp` still returns `legacyHashOtp` when the HMAC secret is missing and the call is not a production create (`:304-315`). | `legacy unsalted SHA-256 challenge is rejected unless ALLOW_LEGACY_UNSALTED_OTP_HASH is true` | A non-production, or non-create, path can still write an unsalted hash when the MSG91 key is absent. |
| H-5 | High | Unpublished ads are world-readable | PARTIALLY FIXED | `promotedAds` read requires `status == active`, super admin, or owner (`firestore.rules:1275-1279`). | The deny lives in `promoted_ads_verification.test.js` and was skipped (`FIRESTORE_EMULATOR_HOST not set`). It was not executed in this session. | Rules are not deployed, and this run did not prove the deny in the emulator. |
| H-6 | High | Approval, webhook, and sync bridge are source-only | PARTIALLY FIXED | Sync exports are inside `if (ENABLE_SUPABASE_SYNC)` (`index.js:1967-2104`). `reviewPromotedAd`, `razorpayWebhook`, `bookAppointment`, and `rescheduleAppointment` are unconditional (`:1810-1814`). | `ENABLE_SUPABASE_SYNC defaults off and sync exports are registered only inside that gate` | Live function list was not queried. A full functions deploy can still offer to delete functions that are not in this source. |
| M-1 | Medium | Redis flags are off | FIXED | `OTP_REDIS_MIRROR` is on only for `on` (`registration_otp.js:247-248`). `RATE_LIMIT_BACKEND` defaults to Firestore. `S3_URL_CACHE` defaults to `off` (`s3_storage.js:638`). | `flag default: RATE_LIMIT_BACKEND defaults to firestore`; `S3 URL cache flag default is "off"` | Turning the flags on without bound Redis secrets is still unsafe. |
| M-2 | Medium | KYC has no S3 purpose; storage flag defaults off | FIXED | KYC prefixes are authorized by role and profile id (`s3_storage.js:613-623`). `use_s3_storage` default was not re-read line by line this pass; the S3 tests that passed include owner KYC upload authorization. | `pharmacy, lab, and ambulance owners can upload their own KYC and nobody else can` | Storage-rules KYC tests were skipped. They were previously failing and were not re-run. |
| M-3 | Medium | A partial Supabase prescription list hides Firestore | FIXED | Merge behavior is covered by the Flutter test below. | `prescription_merge_test.dart`: `Firestore prescription wins when Supabase has only part of the chart` | Merge runs only when Supabase is ready. With the flag off, that branch does not run. |
| M-4 | Medium | Health records and vaccinations use two databases | NOT VERIFIED | `add_record_screen.dart:238` calls Firestore `saveHealthRecord`. No test was found that fails if a Supabase health-record write is reintroduced. | no test | A later edit could add the Supabase path without a failing test. |
| M-5 | Medium | Webhook returns 500 when the secret is missing | FIXED | Missing secret returns 503 and returns (`promoted_ads.js:520-523`). Present secret is checked with `timingSafeEqual` (`:552`). | `missing RAZORPAY_WEBHOOK_SECRET fails closed with 503` | Secret Manager was not queried. Deploy of `razorpayWebhook` still depends on that secret existing. |
| M-6 | Medium | Super-admin email list drifts from Firebase | PARTIALLY FIXED | SQL `is_super_admin()` and Firestore `isSuperAdmin()` remain different sources. Firestore accepts user-doc role `admin` (`promoted_ads.js:18-23`). Users cannot change their own `role` (`firestore.rules:451-452`). | no SQL execution | Two admin definitions remain. |
| M-7 | Medium | `secrets.txt` remains in git history | NOT VERIFIED | This clone's `git log -- secrets.txt` is empty and `git ls-files secrets.txt` is empty. Rotation of values that may exist on a remote was not checked. | no test | Cannot prove every old remote object was rotated. |
| M-8 | Medium | Public HTTP has no App Check | PARTIALLY FIXED | Callable ambulance login sets `enforceAppCheck` (`index.js:1427`). HTTP App Check runs only when `ENFORCE_AMBULANCE_HTTP_APP_CHECK=true`; the default is false (`http_endpoint_security.js:62-65`, `index.js:1480`). `getValidationRulesHttp` has no App Check (`index.js:892-894`). | `http_endpoint_security.test.js` asserts the flag defaults so enforcement is off | Web ambulance HTTP login is callable without App Check unless the flag is set. |
| L-1 | Low | Unused support phone constants | NOT VERIFIED | `git grep` of `supportPhone` under `frontend/` found no matches. | no test | Absence is from search, not from a test that fails if the constant returns. |
| L-2 | Low | Unreferenced registration screens | NOT VERIFIED | No Dart references to the old registration screen class names were found, and `flutter analyze` was clean. | no test | Same limit as L-1. |
| L-3 | Low | Dead promoted-ad banner card | NOT VERIFIED | `PromotedAdBannerCard` was not found under `frontend/`. | no test | Same limit as L-1. |
| L-4 | Low | Sync comment promised a timestamp compare the code did not do | FIXED | Stale `updatedAt` returns before upsert (`cross_role_sync.js:787-789`). | `a stale Firestore snapshot does not upsert the appointment` | The stale skip is a log line, not a dead letter. |
| L-5 | Low | Deleting unlisted functions would remove `ssrmedibond45fad` | NOT VERIFIED | `docs/DEPLOY_CHECKLIST.md` says to answer No. Live `functions:list` was not run. | no test | A plain deploy can still prompt to delete functions that are not in this package. |

Extra row from the source table:

| ID | Severity | Title | Verdict | Evidence | Test | Remaining risk |
| --- | --- | --- | --- | --- | --- | --- |
| M-9 | Low | Notification dialog controller leak | NOT VERIFIED | `notifications_settings_screen.dart` disposes `nameCtrl` in `whenComplete` (read at the re-audit lines; not re-cited as a test). | no test | No widget test fails if `dispose` is removed. |

## Step 2 — targeted checks

### A. Auth / OTP

1. **FAIL.** HMAC is used when the MSG91 key exists (`registration_otp.js:317-320`). The legacy flag defaults off (`:276-279`) and verify rejects a legacy hash then (`:352-354`). `hashOtp` still writes `legacyHashOtp` when the key is missing and the purpose is not a production create (`:304-315`).
2. **FAIL** against the literal claim. `OTP_TEST_MODE` and `DEMO_PHONE_*` are read (`registration_otp.js:208-213`, `:124-134`; `production_otp_guard.js:52-77`). In the production project, `isTestMode` returns false (`registration_otp.js:208-210`) and env demo phones return false (`:167-169`). Cold start throws if those env values are set (`production_otp_guard.js:98-116`). Production demo login is returned only when `app_config/demo_accounts` has `demoLoginEnabled == true` (`registration_otp.js:89-105`).
3. **PASS.** `supabaseCompatibleCustomClaims` sets `role: 'authenticated'` and `app_role` (`registration_otp.js:3205-3212`). `app_role` is not read by rules or functions. Firestore `role()` reads `users/{uid}.role` (`firestore.rules:66-67`). Grep of `request.auth.token.role`, `token.role`, and `claims.role` found no readers. `request.auth.token.email` and `email_verified` are read at `index.js:1751-1752` and `:1903-1904`, and in `promoted_ads.js:19-21`.
4. **PASS.** The consume transaction deletes an expired challenge, locks at 5 attempts, deletes the doc on success, and increments attempts on failure (`registration_otp.js:1990-2035`).

### B. Booking

5. **FAIL** on the exact “doctorId ignored” sentence. `bookAppointment` uses client `doctorId` as the target and checks that the doctor exists, is verified, and is not deactivated (`appointment_slots.js:518` and the checks immediately after). `patientId` comes from the caller profile (`:515`), not the payload. `tokenNumber` comes from `allocateNextDayToken` (`:478`, `:600`). `createdVia` is hard-coded (`:252-253`). Client `tokenNumber`, `patientId`, and `createdVia` are not copied.
6. **FAIL** for deploy readiness. `rescheduleAppointment` exists (`appointment_slots.js` handler, exported at `index.js:1814`). `docs/DEPLOY_CHECKLIST.md` does not name it. It is not deployed.
7. **PASS** for the writes found. Client paths and the rule that covers them:
   - `bookPatientViaCallable` calls the callable and does not `save` (`shared_appointments_store.dart:696-708`).
   - `reschedulePatient` calls `rescheduleAppointment` and updates memory only (`:875` onward; no `_persist`).
   - `addWalkInAppointment` persists (`:816`, `_persist` at `:871`). Create rule: `walkInAppointmentCreateValid()` (`firestore.rules:534`).
   - `cancelByPatient` (`:940`): `appointmentPatientCancel` (`firestore.rules:552-556`).
   - `rescheduleByDoctor` (`:917`): `appointmentDoctorReschedule` (`:614-624`).
   - `cancelByDoctor` (`:989`): `appointmentDoctorCancel` (`:607-610`).
   - Doctor clinical methods `updateDoctorStatus` through `saveConsultationOutcome` (`:1037-1132`): `appointmentDoctorClinicalUpdate` (`:583-604`).
   - `submitReview` / `updateReview` (`:1158`, `:1199`): `appointmentPatientReview` (`:561-573`).
   - `booking_flow_helpers.dart:25` only allocates an id; it does not write.

### C. Firestore rules

8. **FAIL.** Three public reads are `if true`: `review_public` (`firestore.rules:668`), `lab_catalog` (`:760`), `doctor_availability` (`:862`). `system_config` read is any signed-in user (`:1266`). Community catalogs are any signed-in user (`:1015`, `:1028`, `:1041`, `:1053`, `:1065`). No rule reads a client-supplied role claim; `role()` uses the user document (`:66-67`). PII collections checked by hand are not `if true`: prescriptions (`:644-662`), health records (`:741-753`), lab bookings (`:772-788`), lab orders (`:827-848`), deliveries (`:987-1008`), ambulances (`:1131-1160`), appointments (`:530-537`), razorpayPayments deny all (`:1320`).
9. **PASS** for the fields checked. A user cannot change `role`, `profileId`, `verified`, or `verifiedAt` (`firestore.rules:451-452`). A doctor cannot change `verified` or `verifiedAt` (`:480-481`). Promoted-ad clients cannot write payment ids, amount, duration, or activation times (`:1303-1305`). `razorpayPayments` is deny-all (`:1320`). No wallet collection was found.
10. **FAIL.** This session executed a deny suite only for appointments (28 passed). Users, lab bookings/orders, and `razorpayPayments` have deny tests in `profile_claims_rules.test.js` and `firestore_s3_rules.test.js`, and those files were skipped. No rules test referencing `prescriptions`, `pharmacy_deliveries`, or the `ambulances` collection was found.
11. **PASS** that `storage.rules` is not in the functions deploy list. It is in `firebase.json:6-7`, so a plain `firebase deploy` would publish it. It allows signed-in reads of patient and doctor profile photos (`storage.rules:170`, `:179`), owner writes with size and content-type checks, super-admin reads of KYC documents, and lab report writes only when the booking or order matches. The default is not world-public. Owner KYC upload tests were not re-run.

### D. Payments / ads / storage

12. **PASS.** Amount is `AD_PRICING_TABLE[hours]` (`promoted_ads.js:155`, `:286`). Signature compare is `timingSafeEqual` (`:443`). Replay of a payment id is rejected in the ledger transaction (`:323`). The order must belong to the caller (`:420-427`).
13. **FAIL.** The secret is `defineSecret('RAZORPAY_WEBHOOK_SECRET')` (`:26`) and a missing value returns 503 (`:520-523`). `req.rawBody` is preferred (`:527-528`), but if it is absent the code hashes `JSON.stringify(req.body)` (`:535-536`), which is not the raw bytes. Idempotency is on the payment/ad activation (`:323`, `:649`), not on the Razorpay event id.
14. **FAIL.** Super admin is checked from the verified admin email or `users/{uid}.role` (`promoted_ads.js:18-23`, `:715-717`). Nothing rejects the case where that admin is also `providerId` (`:732-749`).
15. **PASS.** Callables require auth. The object key is built server-side (`s3_storage.js:316-433`). Content type and size are checked (`:114-118`). Upload expiry is 300 seconds (`:452`). Delete is allowed for the matching role and profile id (`:613-623`). AWS keys are `defineSecret('AWS_ACCESS_KEY_ID')` and `defineSecret('AWS_SECRET_ACCESS_KEY')` (`:17-18`).

### E. Sync

16. **PASS.** `ENABLE_SUPABASE_SYNC` is true only when the env value is `on` (`index.js:123`). The `sync*ToSupabase` assignments are inside that `if` (`:1967`, `:1998`). With the flag unset those functions are not exported. Flutter Supabase init no-ops without defines (`supabase_bootstrap.dart:147-156`).
17. **FAIL.** Leftovers in `cross_role_sync.js`: `doc-unknown` (`:650`), `General` (`:653`), `Other` (`:655`), `newVisit` (`:657`), `new Date()` as a missing `dateTime` (`:646`), pharmacy `requestedBy || 'doctor'` (`:2172`), `Doctor` and `Medical Store` (`:2179-2180`), and `new Date()` for timestamps (`:2183-2185`). `0000000000`, `pat-unknown`, `amb-unknown`, `general_test`, `Lab Test`, `Diagnostic Lab`, `Pickup location`, `Drop location`, and a bare `Driver` placeholder were not found. Notification copy uses `Pharmacy` as a display fallback (`index.js:871`); that is a push label, not a row insert.
18. **PASS.** Origin returns null when it cannot be determined (`cross_role_sync.js:631`) and that null is dead-lettered (`:745-754`). `doctor_firestore` is returned only for an explicit doctor writer, doctor `createdBy`, or `source == walkin` (`:622-629`). Stale `updatedAt` skips the upsert (`:787-789`). Tests: `undetermined appointment origin is not upserted` and `a stale Firestore snapshot does not upsert the appointment`.
19. **FAIL.** Placeholder and unknown-origin skips call `recordDlqFailure` (seen throughout `cross_role_sync.js`, including `:747`). A stale snapshot only logs (`:787-789`). Missing Supabase credentials only warn and return (`:760-762`).
20. **PASS.** The lab sync path does not default `requested_by` to `doctor`; a missing value is recorded as missing (`cross_role_sync.js:3170-3182`). The lab client sets `requestedBy` explicitly: doctor invite at `lab_connection_store.dart:205`, lab invite at `:258`. The default should stay removed. The pharmacy connection builder still defaults to `doctor` (`cross_role_sync.js:2172`).

### F. Client app

21. **PASS.** `shouldBlock` returns false for web, an unreadable config, a missing build number, and an empty store URL (`minimum_build_gate.dart:25-32`). `read` returns not-readable on timeout or error (`:40-43`). Tests in `minimum_build_gate_test.dart`: `default config never blocks`, `a failed config read does not block`, `a malformed minimum does not block`, `web does not block`, `an empty store URL does not block`.
22. **PASS.** Release scripts add Supabase defines only when `ENABLE_SUPABASE=1` (`release_build.ps1:86`, `release_build.sh:111`). Without those defines, `initialize` does not create a client (`supabase_bootstrap.dart:147-156`). Nothing in this check shows a Supabase URL or anon key being compiled in when the flag is off.
23. **PASS** for server secrets in `frontend/`. No `AKIA`, private key, or live Razorpay key was found. `firebase_options.dart` resolves API keys through dart-defines (`:97` onward) rather than a literal key in the lines searched.
24. **PASS** as a description, not as “enforced everywhere.” Callables that pass `enforceAppCheck: ENFORCE_ABUSE_APP_CHECK` enforce unless that env value is `false` (`abuse_rate_limit.js:236-252`). That includes booking, reschedule, Razorpay callables, review, OTP callables, and `getValidationRules`. `getValidationRulesHttp` does not check App Check (`index.js:892`). Ambulance HTTP checks App Check only when its flag is `true`; otherwise it returns without logging (`http_endpoint_security.js:68-70`). `razorpayWebhook` is signature-authenticated, not App Check.

### G. Deploy readiness

25. Exported functions, grouped:
    - Deploy-list candidates already discussed: `verifyUserRegistrationOtp`, `completeMobileOtpLogin`, `bookAppointment`, `createRazorpayOrder`, `verifyRazorpayPayment`, `reviewPromotedAd`, `razorpayWebhook`, `getS3UploadUrl`, `deleteS3Object`. `rescheduleAppointment` is new and not on that list. `getS3DownloadUrl` and `getS3DownloadUrls` are exported beside the upload/delete pair and were not on the nine-name list.
    - Deploy later, only with `ENABLE_SUPABASE_SYNC=on`: every `sync*ToSupabase` export inside `index.js:1968-2104`.
    - Not deprecated, and not in the nine: notification triggers, rating aggregates, `processMailQueueMsg91`, `deleteMyAccount`, `expirePromotedAds`, `reconcileAppointmentSlot`, account approval callables, and the ambulance login/rating callables.
    - Intentionally public or auth-optional: `getValidationRules` (App Check, no user), `getValidationRulesHttp` (no App Check, no user), `verifyAmbulanceDriverLogin` (PIN, auth optional, `index.js:1423-1426`), `verifyAmbulanceDriverLoginHttp` (PIN, `index.js:1454`), `razorpayWebhook` (signature). No other exported callable was found with neither an auth check nor one of those public purposes. Triggers use the Admin SDK.

26. Names the deploy list reads. Values were not printed. Presence in Secret Manager was not checked.
    - OTP send/verify and complete login: `MSG91` auth key via `readMsg91AuthKey`. `ALLOW_LEGACY_UNSALTED_OTP_HASH` unset. `OTP_TEST_MODE` and `DEMO_PHONE_*` must stay unset in production (`production_otp_guard.js:70-77`).
    - `createRazorpayOrder` / `verifyRazorpayPayment`: `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET` (`promoted_ads.js:46-47`).
    - `razorpayWebhook`: `RAZORPAY_WEBHOOK_SECRET` (`:26`).
    - `getS3UploadUrl` / `deleteS3Object`: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` (`s3_storage.js:17-18`), plus `AWS_REGION` and `S3_BUCKET` (`:21-22`).
    - `bookAppointment` and `rescheduleAppointment`: no payment secret. App Check uses `ENFORCE_ABUSE_APP_CHECK` (default enforce).
    - Sync secrets (`SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`) are not read by the nine while the sync flag is unset.

27. A plain `firebase deploy` is unsafe. `firebase.json` publishes `backend/firestore.rules`, `backend/firestore.indexes.json`, and `backend/storage.rules` (`firebase.json:2-7`). Those rules drafts are not deployed. The functions package will not export sync functions while the flag is unset, and the CLI can offer to delete functions that exist in the project but not in this source, including the separately deployed web function named in `docs/DEPLOY_CHECKLIST.md`.

## Step 3 — new issues

| ID | Severity | Evidence | Suggested fix |
| --- | --- | --- | --- |
| NEW-1 | Medium | `reviewPromotedAdHandler` never compares `providerId` to the reviewer (`promoted_ads.js:732-749`). | Reject approve when the caller owns the ad. |
| NEW-2 | Medium | Appointment sync still fills `doc-unknown`, `General`, `Other`, `newVisit`, and `new Date()` (`cross_role_sync.js:646-657`). Dormant unless the sync flag is on. | Omit those fields or dead-letter, matching the other builders. |
| NEW-3 | Medium | Pharmacy connection sync defaults `requestedBy` to `doctor` and invents `Doctor` / `Medical Store` (`cross_role_sync.js:2172-2180`). | Dead-letter when the name or requester is missing. |
| NEW-4 | Medium | Webhook signature falls back to `JSON.stringify(req.body)` (`promoted_ads.js:535-536`). | Verify only `req.rawBody`, and reject the request when it is missing. |
| NEW-5 | Low | `isSuperAdmin` treats user-doc role `admin` as super admin without `email_verified` (`promoted_ads.js:23`). Clients cannot set that role themselves (`firestore.rules:451-452`). | Require the verified email allow-list, or a dedicated super-admin role, for approve. |
| NEW-6 | Low | Stale sync skips and missing-credential skips are not dead-lettered (`cross_role_sync.js:760-762`, `:787-789`). | Record a reason, or document the skip as intentional and do not call it a dead letter. |
| NEW-7 | Low | `system_config` is readable by any signed-in user (`firestore.rules:1266`). | Confirm the documents are non-sensitive, or restrict the read. |
| NEW-8 | Low | Emulator updates still log `evaluation error at L535:24` and then deny. | Fix the rules expression that throws, so a later edit cannot turn a throw into an allow. |

## Step 4 — counts

For the 22 requested findings:

| Verdict | Count |
| --- | --- |
| FIXED | 8 (H-1, H-2, H-3, M-1, M-2, M-3, M-5, L-4) |
| PARTIALLY FIXED | 6 (C-3, H-4, H-5, H-6, M-6, M-8) |
| NOT FIXED | 0 |
| DEFERRED BY DESIGN | 2 (C-1, C-2) |
| NOT VERIFIED | 6 (M-4, M-7, L-1, L-2, L-3, L-5) |

M-9 is an extra Low row and is NOT VERIFIED. H-5 is PARTIALLY FIXED because the rule is in the file and its emulator test was skipped. |

SAFE TO DEPLOY FUNCTIONS: NO. `rescheduleAppointment` is not in the checklist deploy list (`index.js:1814`). `RAZORPAY_WEBHOOK_SECRET` was not confirmed in Secret Manager (`promoted_ads.js:26`). An unscoped functions deploy can offer to delete functions that are not in this source.

SAFE TO DEPLOY RULES: NO. Patient creates are walk-in only and patient reschedule is no longer a client write (`firestore.rules:534`, `:552-556`, `:627`). Shipping that before the new app is installed breaks current clients. `storage.rules` would also publish on a plain deploy (`firebase.json:6-7`) and its KYC tests were not re-run.

SAFE TO ROLL OUT APP: NO. The patient reschedule UI calls `rescheduleAppointment` (`shared_appointments_store.dart:758` onward). That function is not deployed. An app build that calls it will fail reschedule until the function is deployed.
