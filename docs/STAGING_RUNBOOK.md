# DoctorNect Staging Deployment & Operations Runbook

This runbook outlines the exact sequence for deploying, configuring, and verifying the DoctorNect backend and client apps in a dedicated **Staging Environment** prior to production cutover.

---

## 1. Prerequisites & Environment Architecture

DoctorNect operates two isolated environments:
- **Staging**: Dedicated Firebase staging project (`doctornect-staging`), Supabase staging instance, staging S3 bucket (`doctornect-staging`), Razorpay Test Mode keys, and separate Redis instance.
- **Production**: Production Firebase project, production Supabase project, production S3 bucket, Razorpay Live keys.

> **Security Rule**: Never reuse secrets or production data across staging and production. Never print secrets or credentials in logs or output.

---

## 2. Supabase Staging Migration Deployment

Apply all schema migrations to the Supabase staging project:

```bash
# 1. Login to Supabase CLI (if not already logged in)
npx supabase login

# 2. Link repository to the Staging project reference
npx supabase link --project-ref <STAGING_PROJECT_REF>

# 3. Push all pending migrations
npx supabase db push

# 4. Verify migration state against local migration files
npx supabase migration list
```

---

## 3. Third-Party Auth Configuration (Firebase JWT)

Configure Supabase to accept Firebase Auth tokens directly:

1. Navigate to **Supabase Dashboard** -> **Authentication** -> **Providers** -> **Third-Party Auth**.
2. Select **Add Provider** -> **Firebase**.
3. Set **Firebase Project ID** to `<STAGING_FIREBASE_PROJECT_ID>`.
4. The JWT Public Key discovery is automatically managed by Supabase using Google's public x509 certs.
5. In Postgres, verify the `sub` claim maps to the Firebase UID:
   ```sql
   SELECT auth.jwt()->>'sub' AS firebase_uid, auth.jwt()->>'role' AS jwt_role;
   ```
6. Ensure custom claims backfill has run for any test users:
   ```bash
   node backend/scripts/backfill_supabase_custom_claims.js --apply
   ```

---

## 4. Cloud Functions Secrets and Configuration

Set required secrets in Google Cloud Secret Manager for the staging Firebase project.

### Required Secret Names (Names only, no values in source control):
- `MSG91_AUTHKEY`
- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `SUPABASE_ANON_KEY`
- `RAZORPAY_KEY_ID`
- `RAZORPAY_KEY_SECRET`
- `RAZORPAY_WEBHOOK_SECRET`
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `S3_BUCKET`
- `AWS_REGION`
- `OTP_REDIS_URL`
- `PROXY_SECRET`
- `MSG91_PROXY_URL`
- `MSG91_TEMPLATE_ID_REGISTRATION`
- `MSG91_SENDER_ID`
- `REVIEW_TEST_NUMBERS` (Comma-separated fictitious review numbers, optional)
- `REVIEW_FIXED_OTP` (Fixed OTP for Play Store review testing, optional)
- `REVIEW_ACCESS_UNTIL` (ISO 8601 expiry timestamp for reviewer bypass)

### Deployment Commands:
```bash
# Set secrets individually
firebase functions:secrets:set MSG91_AUTHKEY --project <STAGING_PROJECT_ID>
firebase functions:secrets:set SUPABASE_URL --project <STAGING_PROJECT_ID>
firebase functions:secrets:set SUPABASE_SERVICE_ROLE_KEY --project <STAGING_PROJECT_ID>
firebase functions:secrets:set SUPABASE_ANON_KEY --project <STAGING_PROJECT_ID>
firebase functions:secrets:set RAZORPAY_KEY_ID --project <STAGING_PROJECT_ID>
firebase functions:secrets:set RAZORPAY_KEY_SECRET --project <STAGING_PROJECT_ID>
firebase functions:secrets:set RAZORPAY_WEBHOOK_SECRET --project <STAGING_PROJECT_ID>
firebase functions:secrets:set AWS_ACCESS_KEY_ID --project <STAGING_PROJECT_ID>
firebase functions:secrets:set AWS_SECRET_ACCESS_KEY --project <STAGING_PROJECT_ID>
firebase functions:secrets:set S3_BUCKET --project <STAGING_PROJECT_ID>
firebase functions:secrets:set OTP_REDIS_URL --project <STAGING_PROJECT_ID>

# Deploy Cloud Functions with staging project target
firebase deploy --only functions --project <STAGING_PROJECT_ID>
```

---

## 5. Supabase Database Webhook Setup

Configure Database Webhooks in Supabase to forward events to Cloud Functions:

1. Open **Supabase Dashboard** -> **Database** -> **Webhooks**.
2. Create Webhooks for real-time dispatch:
   - **Appointments Webhook**:
     - Name: `appointment_notification`
     - Table: `public.appointments`
     - Events: `INSERT`, `UPDATE`
     - URL: `https://asia-south1-<STAGING_PROJECT_ID>.cloudfunctions.net/supabaseDatabaseWebhook`
     - HTTP Headers:
       - `Content-Type`: `application/json`
       - `x-webhook-secret`: `<SUPABASE_WEBHOOK_SECRET>`
   - **Pharmacy Orders Webhook**:
     - Name: `pharmacy_order_notification`
     - Table: `public.pharmacy_orders`
     - Events: `INSERT`, `UPDATE`
     - URL: `https://asia-south1-<STAGING_PROJECT_ID>.cloudfunctions.net/supabaseDatabaseWebhook`
     - HTTP Headers:
       - `x-webhook-secret`: `<SUPABASE_WEBHOOK_SECRET>`
   - **Lab Bookings Webhook**:
     - Name: `lab_booking_notification`
     - Table: `public.lab_bookings`
     - Events: `INSERT`, `UPDATE`
     - URL: `https://asia-south1-<STAGING_PROJECT_ID>.cloudfunctions.net/supabaseDatabaseWebhook`
     - HTTP Headers:
       - `x-webhook-secret`: `<SUPABASE_WEBHOOK_SECRET>`
   - **Ambulance Requests Webhook**:
     - Name: `ambulance_request_notification`
     - Table: `public.ambulance_requests`
     - Events: `INSERT`, `UPDATE`
     - URL: `https://asia-south1-<STAGING_PROJECT_ID>.cloudfunctions.net/supabaseDatabaseWebhook`
     - HTTP Headers:
       - `x-webhook-secret`: `<SUPABASE_WEBHOOK_SECRET>`

---

## 6. AWS S3 Bucket Setup (Staging)

Create and harden the S3 bucket for media attachments, KYC files, and lab reports:

```bash
# 1. Create staging bucket in ap-south-1
aws s3 mb s3://doctornect-staging --region ap-south-1

# 2. Enforce Block Public Access (all public access strictly blocked)
aws s3api put-public-access-block \
  --bucket doctornect-staging \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# 3. Enforce default server-side encryption (SSE-S3 AES-256)
aws s3api put-bucket-encryption \
  --bucket doctornect-staging \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

# 4. Configure bucket lifecycle rules for temporary prescription uploads (optional 30-day archive)
aws s3api put-bucket-lifecycle-configuration \
  --bucket doctornect-staging \
  --lifecycle-configuration file://aws/s3_lifecycle_staging.json
```

---

## 7. Razorpay Test Mode Webhook Setup

1. In the **Razorpay Dashboard** (Switch to **Test Mode**).
2. Go to **Settings** -> **Webhooks** -> **Add New Webhook**.
3. **Webhook URL**: `https://asia-south1-<STAGING_PROJECT_ID>.cloudfunctions.net/razorpayWebhook`
4. **Secret**: Enter `<RAZORPAY_WEBHOOK_SECRET>`.
5. **Active Events**:
   - `order.paid`
   - `payment.captured`
   - `payment.failed`
6. Click **Save**.

---

## 8. Flutter Staging Client Build

Build the Flutter client targeting the staging environment using `--dart-define-from-file`:

1. Populate `frontend/.env.staging` (local gitignored file or CI environment injection):
   ```properties
   SUPABASE_URL=https://<STAGING_PROJECT_REF>.supabase.co
   SUPABASE_ANON_KEY=<STAGING_ANON_KEY>
   FIREBASE_PROJECT_ID=<STAGING_PROJECT_ID>
   S3_BUCKET=doctornect-staging
   USE_SUPABASE_DB_DOCTOR_PATIENT=true
   ```

2. Build Android APK:
   ```bash
   cd frontend
   flutter build apk --flavor staging --dart-define-from-file=.env.staging
   ```

3. Build iOS IPA (from macOS runner):
   ```bash
   cd frontend
   flutter build ipa --flavor staging --dart-define-from-file=.env.staging
   ```

---

## 9. Manual Smoke Testing Checklist per Module

Run through this end-to-end verification checklist on Staging:

### A. Authentication & Profile
- [ ] Send OTP to staging test number.
- [ ] Verify OTP, confirm session creation, check Firebase Auth UID.
- [ ] Inspect Firebase custom claims (`role: 'authenticated'`, `app_role: 'patient'`).
- [ ] Profile write creates/updates row in `public.users` and `public.patients`.

### B. Doctor & Appointments
- [ ] Doctor profile registration and slots setup.
- [ ] Patient searches doctor in `public.doctor_directory` view.
- [ ] Patient books appointment: inserts into `public.appointments`.
- [ ] Webhook triggers notification to doctor device.
- [ ] Doctor confirms/completes appointment; state machine transition verified.

### C. Pharmacy Module
- [ ] Patient creates pharmacy order with prescription upload (S3 upload + signed URL).
- [ ] Pharmacy receives order via Supabase Realtime watcher.
- [ ] Pharmacy transitions order status: `pending` -> `confirmed` -> `packed` -> `out_for_delivery` -> `delivered`.
- [ ] Patient real-time UI updates at each stage.

### D. Lab Module
- [ ] Patient books diagnostic test; inserts into `public.lab_bookings`.
- [ ] Lab receives booking notification; updates sample collection status.
- [ ] Lab uploads test report PDF to S3; signed download URL accessible to patient.

### E. Ambulance Module
- [ ] Patient broadcasts ambulance request; rows created in `public.ambulance_requests`.
- [ ] Nearby drivers receive broadcast via Realtime watcher.
- [ ] Single driver accepts: `accept_ambulance_request` RPC ensures winner-takes-all.
- [ ] Sibling requests transition to `taken`. Counterpart location streaming works during active trip.

### F. Support & In-App Notifications
- [ ] User opens support ticket; message appended to `public.ticket_messages`.
- [ ] Admin / automated notification inserted into `public.in_app_notifications`.
- [ ] User receives real-time badge update and marks notification read.

### G. Account Deletion & Data Retention
- [ ] User requests account deletion from profile screen.
- [ ] `deleteMyAccount` callable runs:
  - User rows cascaded in Supabase.
  - S3 user files deleted.
  - Redis OTP challenge keys deleted.
  - FCM tokens deleted from `user_devices`.
  - Financial records (`razorpay_orders`) retained with `user_uid = NULL` (anonymized).
  - Firebase Auth user deleted.

---

## 10. Production Migration Safety Section

When preparing for production cutover:

1. **Compare Migration History**:
   ```bash
   npx supabase migration list --project-ref <STAGING_REF>
   npx supabase migration list --project-ref <PROD_REF>
   ```
   Ensure the local git migration list is completely linear and all versions match.

2. **Pre-Migration Production Database Backup**:
   Always take a PITR backup or complete SQL dump before pushing migrations:
   ```bash
   npx supabase db dump --project-ref <PROD_REF> -f backup_pre_migration_$(date +%Y%m%d_%H%M%S).sql
   ```

3. **Database Reset Policy**:
   - `npx supabase db reset` is **STRICTLY FORBIDDEN** on production once real users exist.
   - Any schema adjustment on production MUST be applied through an append-only, forward-compatible migration (`supabase db push`).
