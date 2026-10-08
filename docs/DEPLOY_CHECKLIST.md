# DoctorNect deploy checklist

Do not run these commands until the matching local phase is committed and you have explicitly approved the step. Nothing in this file deploys by itself.

Project: `medibond-45fad`. Run commands from the repo root.

## Never

- Do not run an unqualified `firebase deploy --only functions`. The CLI will ask to delete functions that are not in this source tree. **Answer No.** That question is what protects the web service `ssrmedibond45fad` (`us-central1`), which is not part of `backend/functions`.
- Do not delete `ssrmedibond45fad`.
- Do not set `ENABLE_SUPABASE_SYNC=on` for a deploy until the sync payload rules in `backend/functions/cross_role_sync.js` have been reviewed. With the variable unset, `sync*ToSupabase` functions are not registered.
- Do not set `ENABLE_SUPABASE=1` on a release build.
- Do not paste secret values into chat, git, or this file.

## Order

1. Create `RAZORPAY_WEBHOOK_SECRET` out of band (value from the Razorpay dashboard, never pasted here):

   ```powershell
   firebase functions:secrets:set RAZORPAY_WEBHOOK_SECRET --project medibond-45fad
   ```

2. Deploy functions **by name** only, after that secret exists. These two are in source and were not in the 2026-10-08 live list:

   ```powershell
   firebase deploy --project medibond-45fad --only functions:reviewPromotedAd,functions:razorpayWebhook
   ```

   If the CLI still asks to delete functions that are not in the source, answer **No** and stop. Do not add `--force`.

   Updating functions that are already live is a separate explicit list, for example `functions:bookAppointment,functions:deleteMyAccount`. Do not fold the `sync*ToSupabase` names into that list unless `ENABLE_SUPABASE_SYNC=on` is a conscious choice for that one deploy. After they have been deployed once, leave the flag `on` for later deploys or the CLI will offer to delete them. Answer **No** unless you intend that deletion.

3. Deploy Firestore rules **only after** the new app build that uses the `bookAppointment` callable is in users' hands. A rules deploy that denies patient client creates will break already-installed builds that still create `appointments` directly.

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
