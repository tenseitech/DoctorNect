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
