# Release smoke test

Run this by hand after the functions deploy, and again after the app release. Do not paste phone numbers or OTP values into this file or into chat. Demo OTP and phones come from Firestore `app_config/demo_accounts`.

## 1. OTP login

For each role, use a real number you control, then the demo number for that role from `app_config/demo_accounts`. Roles: patient, doctor, medical store (pharmacy), lab, ambulance.

1. Open the role's login, enter the mobile number, and request OTP.
2. Enter the SMS code, or the demo OTP from `app_config/demo_accounts` for that role's demo number.
3. Expected: the app opens that role's home screen. Logs for `sendUserRegistrationOtp` and `verifyUserRegistrationOtp` show success. `completeMobileOtpLogin` runs after verify for a mobile login.
4. Failure: a wrong code stays on the OTP screen with an invalid-OTP error. Check `verifyUserRegistrationOtp` in Cloud Logging. If send never arrives, check `sendUserRegistrationOtp`. Ambulance web login is a different function; see section 7.

## 2. Patient booking (new build)

Use a doctor slot that is empty.

1. Book one slot. Expected: one `appointments` document whose id matches the booking, `createdVia` is `bookAppointment`, and `tokenNumber` is the next number for that doctor-day. The doctor appointment list shows the same token.
2. Book a second person in the same slot without a share reason. Expected: the app asks for a share reason and the callable rejects the write until one is provided.
3. Provide a share reason and book. Expected: the slot has 2 active bookings.
4. Book a third with a share reason. Expected: success. Book a fourth. Expected: rejection that the slot is full (maximum 3).
5. From the same patient account, book a family member with a different name in a slot that already has this account. Expected: the second booking succeeds when a share reason is set. Same name in the same slot is rejected.

## 3. Patient cancel and reschedule (new build)

1. Cancel the booking from step 2. Expected: Firestore shows the same document id. `doctorStatus` becomes cancelled. No second `appointments` document appears. The doctor list shows the cancellation.
2. Reschedule another booking from that account. Expected: the same document id changes `dateTime`, `slotLabel`, and `tokenNumber`. The doctor list shows the new slot. No second document.

## 4. Previous Play build, before and after Firestore rules

Before the rules deploy:

- Booking, cancel, and reschedule on the previous Play build still use that build's client writes. Booking can succeed. Cancel and reschedule on that build may write a different id than the callable document. Check the console if a patient reports a cancel that the doctor does not see.

After the rules deploy:

- New-build booking, cancel, and reschedule keep working.
- Previous-build booking that creates an `appointments` document from the client is denied.
- Previous-build cancel or reschedule that writes a new id is denied. A cancel that updates the real document id still works.
- Doctor walk-in create still works.

## 5. Doctor

1. Create a walk-in. Expected: a new `appointments` document with `source` `walkin` and no `createdVia`. It shows on the doctor list.
2. Change that appointment's status. Expected: the same document updates and the patient view follows it.

## 6. Promoted ads

Use Razorpay test mode.

1. Create an ad and pay, including the 720-hour plan. Expected: the ad document becomes `pending_approval`. Razorpay shows the webhook delivery as HTTP 200.
2. Sign in as the super admin and approve it on the review screen. Expected: status becomes `active` and the patient Citywide banner shows it.
3. Leave a second ad in draft or `pending_approval`. Sign in as a different user. Expected: that user cannot read it.

## 7. Web ambulance login

On the web app, with `ENFORCE_AMBULANCE_HTTP_APP_CHECK` unset, sign in with an ambulance username and PIN. Expected: login succeeds and the driver home opens. The log function is `verifyAmbulanceDriverLoginHttp`. A wrong PIN is rejected and does not return 503.

## 8. S3 flag

Confirm Remote Config `use_s3_storage` is false and the app was not built with `USE_S3_STORAGE=true`. Upload a profile photo or record the way that build did before. Expected: the upload still uses Firebase Storage, not `getS3UploadUrl`.

## 9. Rollback

One function, from tag `pre-deploy-2026-10-08`:

```powershell
git checkout pre-deploy-2026-10-08 -- backend/functions
firebase deploy --project medibond-45fad --only functions:<functionName>
```

Replace `<functionName>` with the single function to restore. Do not deploy every function. Restore your working tree afterward with `git checkout HEAD -- backend/functions` if you still need the newer source locally.

OTP legacy-hash rollback: set `ALLOW_LEGACY_UNSALTED_OTP_HASH=true` and redeploy `verifyUserRegistrationOtp`. The flag does nothing until that function is redeployed.

## 10. Sign-off

| Item | Tester | Date | Pass/fail | Notes |
| --- | --- | --- | --- | --- |
| 1. OTP, five roles, real and demo | | | | |
| 2. Booking, share reason, full slot, family | | | | |
| 3. Cancel and reschedule, same document | | | | |
| 4. Previous Play build | | | | |
| 5. Walk-in and doctor status | | | | |
| 6. Promoted ads, including 720 hours | | | | |
| 7. Web ambulance login | | | | |
| 8. S3 flag off | | | | |
