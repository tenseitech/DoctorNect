# DoctorNect deploy checklist

Do not run these commands until the matching local phase is committed and you have explicitly approved the step. Nothing in this file deploys by itself.

Project: `medibond-45fad`. Run commands from the repo root.

## Never

- Do not run an unqualified `firebase deploy --only functions`. The CLI will ask to delete functions that are not in this source tree. **Answer No.** That question is what protects the web service `ssrmedibond45fad` (`us-central1`), which is not part of `backend/functions`.
- Do not delete `ssrmedibond45fad`.
- Do not set `ENABLE_SUPABASE_SYNC=on` for a deploy until the sync payload rules in `backend/functions/cross_role_sync.js` have been reviewed. With the variable unset, `sync*ToSupabase` functions are not registered.
- Do not set `ENABLE_SUPABASE=1` on a release build.
- Do not paste secret values into chat, git, or this file.
- Do not set `OTP_REDIS_MIRROR`, `RATE_LIMIT_BACKEND=redis`, or `S3_URL_CACHE=on` until the `REDIS_HOST`, `REDIS_PORT`, and `REDIS_PASSWORD` secrets are bound to the functions that read them. Redis stays fail-open: a Redis outage must not block OTP, rate limits, or S3 downloads.
- Do not set `ENFORCE_AMBULANCE_HTTP_APP_CHECK=true` until the ambulance web client sends `X-Firebase-AppCheck`. With the flag unset, `verifyAmbulanceDriverLoginHttp` still checks the PIN and does not require App Check. M-8 stays open until the web client sends the App Check header; then set the flag to `true` in the same deploy. `getValidationRulesHttp` stays as it is; it serves declarative validation rules and is low-sensitivity.

## Order

1. Create `RAZORPAY_WEBHOOK_SECRET` out of band (value from the Razorpay dashboard, never pasted here):

   ```powershell
   firebase functions:secrets:set RAZORPAY_WEBHOOK_SECRET --project medibond-45fad
   ```

2. Deploy functions **by name** only, after that secret exists. These were not in the 2026-10-08 live list. `rescheduleAppointment` is new and must be included before the app build that calls it is rolled out:

   ```powershell
   firebase deploy --project medibond-45fad --only functions:reviewPromotedAd,functions:razorpayWebhook,functions:rescheduleAppointment
   ```

   The repo does not record the last deployed commit. `origin/main` is `4fc3a6b` and is not proof of what is live. Confirm the deployed commit before using the comparison below.

   Since `origin/main`, `getS3DownloadUrl` and `getS3DownloadUrls` have no change to auth, object-key checks, or expiry (`s3_storage.js` download handlers, `expiresIn` at lines 737 and 788). They do not need a deploy solely to match `getS3UploadUrl` / `deleteS3Object`. `deleteS3Object` does change: `authorizeDelete` now allows the pharmacy, lab, and ambulance prefixes (`s3_storage.js:613-623`). Deploy `functions:deleteS3Object` with `functions:getS3UploadUrl` if those KYC deletes should work. `getS3UploadUrl` gained `pharmacy_kyc`, `lab_kyc`, and `ambulance_kyc` purposes in the same file.

   If the CLI still asks to delete functions that are not in the source, answer **No** and stop. Do not add `--force`.

   Updating functions that are already live is a separate explicit list, for example `functions:bookAppointment,functions:deleteMyAccount`. Do not fold the `sync*ToSupabase` names into that list unless `ENABLE_SUPABASE_SYNC=on` is a conscious choice for that one deploy. After they have been deployed once, leave the flag `on` for later deploys or the CLI will offer to delete them. Answer **No** unless you intend that deletion.

Confirm this promoted-ad price table before deploying `createRazorpayOrder`, `verifyRazorpayPayment`, `reviewPromotedAd`, or `razorpayWebhook`. Amounts are INR. There is no 15-day (360h) plan in the app, so none was added.

| Hours | INR |
| --- | --- |
| 6 | 100 |
| 12 | 180 |
| 24 | 300 |
| 72 | 750 |
| 168 | 1500 |
| 720 | 5000 |

`razorpayWebhook` answers **503** until `RAZORPAY_WEBHOOK_SECRET` is available. Do not treat that as a crash to retry in a loop.

3. Deploy Firestore rules **only after** the new app build that uses the `bookAppointment` callable is in users' hands. A rules deploy that denies patient client creates will break already-installed builds that still create `appointments` directly. The Citywide banner query is `promotedAds` where `status == active` (single-field; the existing `status` + `endTime` index is unchanged).

## When to deploy Firestore rules

`bookAppointment` writes `createdVia: 'bookAppointment'` and `createdAt`. Old app builds that create `appointments` directly do not write `createdVia`. Doctor walk-ins also lack `createdVia`; they have `source == 'walkin'`. Leave those out of the old-build count.

In the Firebase console Firestore data viewer, for collection `appointments`, look at documents whose `createdAt` is in the last 24 hours and whose `source` is not `walkin`:

- Count A: those documents without `createdVia`.
- Count B: those documents with `createdVia` equal to `bookAppointment`.

Suggested threshold, adjust it if you want: deploy the rules when count A is under 2% of A + B, for 3 days in a row. Redeploy `bookAppointment` before you start counting, or the marker will not be on new callable bookings.

   ```powershell
   firebase deploy --project medibond-45fad --only firestore:rules
   ```

Supabase, only if a build is intentionally compiled with `ENABLE_SUPABASE=1` (release scripts still leave that unset):

- Apply `backend/supabase/migrations/20261008000001_firebase_uid_identity.sql` on DRNECT-DB. Do not point a database webhook at `sync-to-firestore` until that function actually writes Firestore.
- Enable Firebase third-party auth on the hosted Supabase project for Firebase project `medibond-45fad`. The local `config.toml` already sets `enabled = true`. The custom token claim `role` is `authenticated`; the app role is `app_role`.

Indexes, if needed, are separate and come before the rules change that depends on them:

```powershell
firebase deploy --project medibond-45fad --only firestore:indexes
```
