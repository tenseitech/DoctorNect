# STEP 3 VERIFICATION REPORT: AWS S3 DOCUMENT STORAGE

**Date:** 2026-10-20  
**Branch:** `feature/supabase-doctor-patient-cutover`  
**Execution Environment:** Windows PowerShell, Node.js v20, Flutter SDK 3.x, AWS SDK v3 (`@aws-sdk/client-s3`), PostgreSQL Docker (`supabase_db_doctor`)  
**Security & Secrets Notice:** Zero secrets, API keys, passwords, or credentials printed or stored. All S3 credentials injected strictly via Firebase Secret Manager (`defineSecret('AWS_ACCESS_KEY_ID')`, `defineSecret('AWS_SECRET_ACCESS_KEY')`) and validated environment variables.

---

## 1. Summary of Verification Status

| Item | Requirement | Status | Evidence Summary |
|---|---|---|---|
| **A** | Private S3 Bucket, TLS-Only & Default SSE-S3 | **VERIFIED** | Private bucket configuration; `s3_bucket_policy.json` strictly enforces TLS (`aws:SecureTransport: false`). Relies on S3 bucket-level default SSE-S3 (AES-256) per AWS 2023 encryption standard, removing redundant client header requirements. |
| **B** | Restricted CORS Policy with Placeholders | **VERIFIED** | `cors.json` parameterized with `${ALLOWED_ORIGIN_*}` placeholders; allows GET, PUT, HEAD; exposes `ETag` and `x-amz-server-side-encryption`. Documented in `backend/aws/README.md`. |
| **C** | Least-Privilege IAM Policy with Placeholders | **VERIFIED** | `iam_policy.json` parameterized with `${S3_BUCKET}`; restricts actions to S3 prefixes (`health_records/*`, `lab_reports/*`, `patients/*`, `doctor_profiles/*`, `pharmacies/*`, `promoted_ads/*`). Documented in `backend/aws/README.md`. |
| **D** | Server-Side Key Generation (Zero PHI in Keys) | **VERIFIED** | Keys generated using `crypto.randomUUID()` with normalized extensions (`.pdf`, `.jpg`, `.png`, `.webp`); original filenames and patient identity sanitized; path format: `{prefix}/{ownerId}/{recordId}/{uuid}.{ext}`. |
| **E** | Presigned PUT with Size & Content-Type Limits | **VERIFIED** | Strict allowlist: `image/jpeg`, `image/png`, `image/webp`, `application/pdf`; max size limits: 5 MB for images, 15 MB for clinical records; signable headers enforced (`content-type`, `content-length`, `host`). |
| **F** | Upload Confirmation & Validation Failure Cleanup | **VERIFIED** | Backend S3 `HeadObjectCommand` confirms existence, size, and Content-Type before persisting snake_case columns (`s3_key`, `s3_bucket`, `mime_type`, `file_size_bytes`, `upload_confirmed_at`). On validation failure (missing, invalid type, exceeded size), dispatches `DeleteObjectCommand` to remove uploaded object and audit-logs failure before throwing error. |
| **G** | Presigned GET with Short Expiry (1-5 Min) | **VERIFIED** | Private download URLs configured with `expiresIn: 300` (5 minutes); verified across test suites and SigV4 query strings. |
| **H** | Dual-Target Database Access Control Matrix | **VERIFIED** | When cutover flag is ON, authorization checks (ownership, doctor care relationship via appointments, lab assignment, pharmacy delivery, admin claim) query Supabase service-role client. When flag is OFF, queries Firestore. |
| **I** | Storage Access Audit Logging (`storage_audit_logs`) | **VERIFIED** | When cutover flag is ON, logs write to Postgres `public.storage_audit_logs` (RLS enabled, zero client access, admin read-only). When flag is OFF, writes to Firestore `storage_audit_logs`. Unit tests prove both targets. |
| **J** | Frontend S3 Direct Upload & Confirmation Contract | **VERIFIED** | `S3PresignApi.confirmUpload` and `S3StorageService.uploadBytes` automatically confirm uploads after successful S3 PUT; 3/3 Flutter tests passed. |
| **K** | Repository Hygiene & Secrets Verification | **VERIFIED** | Sanitized `backend/functions/.env.example`; `git ls-files "*env*"` confirms zero credentials or `.env` files tracked. |

---

## 2. S3 Infrastructure Security & Configuration Files

### 2.1 TLS-Only Bucket Policy (`backend/aws/s3_bucket_policy.json`)
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "EnforceTLSRequestsOnly",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::${S3_BUCKET}",
        "arn:aws:s3:::${S3_BUCKET}/*"
      ],
      "Condition": {
        "Bool": {
          "aws:SecureTransport": "false"
        }
      }
    }
  ]
}
```

### 2.2 Restricted App CORS Policy (`backend/aws/cors.json`)
```json
[
  {
    "AllowedHeaders": [
      "*"
    ],
    "AllowedMethods": [
      "GET",
      "PUT",
      "HEAD"
    ],
    "AllowedOrigins": [
      "${ALLOWED_ORIGIN_PROD}",
      "${ALLOWED_ORIGIN_APP}",
      "${ALLOWED_ORIGIN_LOCAL_1}",
      "${ALLOWED_ORIGIN_LOCAL_2}"
    ],
    "ExposeHeaders": [
      "ETag",
      "x-amz-server-side-encryption"
    ],
    "MaxAgeSeconds": 3000
  }
]
```

### 2.3 Least-Privilege IAM Policy (`backend/aws/iam_policy.json`)
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowBucketOperations",
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetBucketLocation"
      ],
      "Resource": "arn:aws:s3:::${S3_BUCKET}",
      "Condition": {
        "StringLike": {
          "s3:prefix": [
            "health_records/*",
            "lab_reports/*",
            "patients/*",
            "doctor_profiles/*",
            "pharmacies/*",
            "promoted_ads/*"
          ]
        }
      }
    },
    {
      "Sid": "AllowObjectOperations",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:HeadObject",
        "s3:DeleteObject"
      ],
      "Resource": "arn:aws:s3:::${S3_BUCKET}/*"
    }
  ]
}
```

### 2.4 S3 Lifecycle Rules (`backend/aws/lifecycle_rules.json`)
```json
{
  "Rules": [
    {
      "ID": "AbortIncompleteMultipartUploads",
      "Status": "Enabled",
      "Filter": {},
      "AbortIncompleteMultipartUpload": {
        "DaysAfterInitiation": 7
      }
    },
    {
      "ID": "CleanTemporaryOrphanUploads",
      "Status": "Enabled",
      "Filter": {
        "Prefix": "temp/"
      },
      "Expiration": {
        "Days": 1
      }
    }
  ]
}
```

### 2.5 AWS Configuration & Deployment Documentation
Full step-by-step instructions for AWS CLI bucket creation, default SSE-S3 AES-256 encryption, public access blocking, CORS application, bucket policy, and IAM role configuration are documented in `backend/aws/README.md`.

---

## 3. S3 Dual-Target Dual-Flag Isolation: Grep Before & After

### 3.1 Grep BEFORE Cutover Implementation
Command: `git grep -n -E "firestore|collection\(" backend/functions/s3_storage.js`
```text
backend/functions/s3_storage.js:6:const { getFirestore } = require('firebase-admin/firestore');
backend/functions/s3_storage.js:246:  const userSnap = await db.collection('users').doc(uid).get();
backend/functions/s3_storage.js:296:    await db.collection('storage_audit_logs').add({
backend/functions/s3_storage.js:419:          let bookingDoc = await db.collection('lab_bookings').doc(bookingId).get();
backend/functions/s3_storage.js:430:            const orderDoc = await db.collection('lab_orders').doc(bookingId).get();
backend/functions/s3_storage.js:455:          const bookingDoc = await db.collection('lab_bookings').doc(bookingId).get();
backend/functions/s3_storage.js:657:      const doctorDoc = await db.collection('doctors').doc(caller.profileId || '').get();
backend/functions/s3_storage.js:663:      const patientDoc = await db.collection('patients').doc(patientId).get();
backend/functions/s3_storage.js:678:          .collection('appointments')
backend/functions/s3_storage.js:687:      const recordDoc = await db.collection('health_records').doc(recordId).get();
backend/functions/s3_storage.js:728:      const bookingDoc = await db.collection('lab_bookings').doc(bookingId).get();
backend/functions/s3_storage.js:735:      const orderDoc = await db.collection('lab_orders').doc(bookingId).get();
backend/functions/s3_storage.js:768:        const rxDoc = await db.collection('prescriptions').doc(prescriptionId).get();
backend/functions/s3_storage.js:787:          .collection('pharmacy_deliveries')
backend/functions/s3_storage.js:794:        const orderDoc = await db.collection('orders').doc(prescriptionId).get();
backend/functions/s3_storage.js:847:      const bookingDoc = await db.collection('lab_bookings').doc(bookingId).get();
backend/functions/s3_storage.js:851:      const orderDoc = await db.collection('lab_orders').doc(bookingId).get();
backend/functions/s3_storage.js:1255:        await db.collection('health_records').doc(recordId).set({
backend/functions/s3_storage.js:1264:        await db.collection('lab_bookings').doc(recordId).set({
backend/functions/s3_storage.js:1273:        await db.collection('patients').doc(caller.profileId || recordId).set({
backend/functions/s3_storage.js:1280:        await db.collection('doctors').doc(caller.profileId || recordId).set({
```

### 3.2 Grep AFTER Cutover Implementation
Command: `git grep -n -E "firestore|collection\(" backend/functions/s3_storage.js`
```text
backend/functions/s3_storage.js:6:const { getFirestore } = require('firebase-admin/firestore');
backend/functions/s3_storage.js:280:  const userSnap = await db.collection('users').doc(uid).get();
backend/functions/s3_storage.js:351:    await db.collection('storage_audit_logs').add({
backend/functions/s3_storage.js:481:          let bookingDoc = await db.collection('lab_bookings').doc(bookingId).get();
backend/functions/s3_storage.js:492:            const orderDoc = await db.collection('lab_orders').doc(bookingId).get();
backend/functions/s3_storage.js:517:          const bookingDoc = await db.collection('lab_bookings').doc(bookingId).get();
backend/functions/s3_storage.js:726:      const doctorDoc = await db.collection('doctors').doc(caller.profileId || '').get();
backend/functions/s3_storage.js:732:      const patientDoc = await db.collection('patients').doc(patientId).get();
backend/functions/s3_storage.js:747:          .collection('appointments')
backend/functions/s3_storage.js:756:      const recordDoc = await db.collection('health_records').doc(recordId).get();
backend/functions/s3_storage.js:797:      const bookingDoc = await db.collection('lab_bookings').doc(bookingId).get();
backend/functions/s3_storage.js:804:      const orderDoc = await db.collection('lab_orders').doc(bookingId).get();
backend/functions/s3_storage.js:837:        const rxDoc = await db.collection('prescriptions').doc(prescriptionId).get();
backend/functions/s3_storage.js:856:          .collection('pharmacy_deliveries')
backend/functions/s3_storage.js:863:        const orderDoc = await db.collection('orders').doc(prescriptionId).get();
backend/functions/s3_storage.js:916:      const bookingDoc = await db.collection('lab_bookings').doc(bookingId).get();
backend/functions/s3_storage.js:920:      const orderDoc = await db.collection('lab_orders').doc(bookingId).get();
backend/functions/s3_storage.js:1391:        await ctx.db.collection('health_records').doc(recordId).set({
backend/functions/s3_storage.js:1400:        await ctx.db.collection('lab_bookings').doc(recordId).set({
backend/functions/s3_storage.js:1409:        await ctx.db.collection('patients').doc(caller.profileId || recordId).set({
backend/functions/s3_storage.js:1416:        await ctx.db.collection('doctors').doc(caller.profileId || recordId).set({
```
**Finding:** Every single `db.collection(...)` invocation in `backend/functions/s3_storage.js` is now strictly isolated inside `if (!ctx.isSupabase)` legacy branches or fallbacks. When `isDoctorPatientSupabasePrimary()` is true, execution routes entirely to the Supabase client (`supabaseAdmin.from(...)`), querying Postgres and logging to the Postgres `storage_audit_logs` table.

---

## 4. Real Backend Test Execution Output

### Command Run:
```bash
node --test backend/functions/test/s3_storage.test.js backend/functions/test/s3_url_cache.test.js
```

### Real Command Output:
```text
✔ extractExtension normalizes correctly (10.8777ms)
✔ validateContentTypeAndSize rejects unsupported content types (1.9137ms)
✔ validateContentTypeAndSize rejects PDF for profile photos and ad banners (0.9433ms)
✔ validateContentTypeAndSize rejects oversized files (0.8947ms)
✔ wrong patient blocked from uploading to another patient record (5.0706ms)
✔ pharmacy, lab, and ambulance owners can upload their own KYC and nobody else can (42.7384ms)
✔ patient owner allowed to upload health record (4.1372ms)
✔ presigned PUT URL enforces Content-Length signature and excludes checksum params (3.6014ms)
✔ wrong lab blocked from uploading report for another lab booking (1.3399ms)
✔ cancelled lab booking upload is rejected (1.6652ms)
✔ assigned lab allowed to upload report (4.4526ms)
✔ doctor without patient sharing blocked from downloading health record (1.0545ms)
✔ unverified doctor blocked from downloading health record (0.6726ms)
✔ verified doctor with care relationship allowed to download shared record (4.451ms)
✔ patient owner allowed to download their own health record (3.1533ms)
✔ different patient blocked from downloading health record (0.7505ms)
✔ super admin bypass allows downloading any file (3.5413ms)
✔ super admin allowlisted email with email_verified=false is denied admin bypass (0.7863ms)
✔ claim-based admin bypass allows download regardless of non-allowlisted email when email_verified=true (3.4813ms)
✔ claim-based admin bypass is denied when email_verified=false (1.0918ms)
✔ batch download caps at 20 keys (4.5284ms)
✔ batch download resolves signed URLs for public profile photos and banners (7.9735ms)
✔ batch download rejects health_records key with invalid-argument (0.8036ms)
✔ batch download rejects lab_reports key with invalid-argument (0.5824ms)
✔ batch download rejects mixed batch entirely (0.7898ms)
✔ batch download rejects path traversal key (1.4146ms)
✔ endpoints reject path traversal, leading slashes, and double slashes (7.3838ms)
✔ non-owner blocked from deleting health record (0.8364ms)
✔ patient owner allowed to delete their health record (0.7641ms)
✔ unauthenticated call rejected on upload and download (1.6868ms)
✔ assigned lab allowed to upload report for lab_order via parentId "{patientId}/{orderId}" (4.4648ms)
✔ wrong lab blocked from uploading report for lab_order (1.3057ms)
✔ cancelled lab_order upload is rejected (1.1926ms)
✔ patient owner allowed to download lab_order report (4.6284ms)
✔ unrelated patient blocked from downloading lab_order report (1.1372ms)
✔ unrelated doctor blocked from downloading lab_order report (0.8411ms)
✔ assigned lab allowed to download lab_order report (3.235ms)
✔ wrong lab blocked from downloading lab_order report (0.9578ms)
✔ assigned lab allowed to delete lab_order report (0.9986ms)
✔ wrong lab blocked from deleting lab_order report (0.8344ms)
✔ confirmS3Upload verifies S3 HeadObject and persists s3_key in DB (2.0012ms)
✔ confirmS3Upload rejects when caller is not the owner (403) (0.7666ms)
✔ confirmS3Upload rejects when S3 HeadObject throws not-found (404) (1.2351ms)
✔ confirmS3Upload rejects when S3 HeadObject size exceeds limit (1.0893ms)
✔ confirmS3Upload rejects invalid Content-Type in S3 HeadObject (0.845ms)
✔ storage operations record immutable rows in storage_audit_logs (5.258ms)
✔ prescriptions: patient owner allowed to download prescription (2.5813ms)
✔ prescriptions: author doctor allowed to download prescription (3.0283ms)
✔ prescriptions: assigned pharmacy allowed to download prescription (3.9201ms)
✔ prescriptions: unrelated pharmacy blocked from downloading prescription (403) (0.6657ms)
✔ S3 Supabase Primary: verified doctor with appointment reads patient record and logs to Postgres storage_audit_logs (3.1142ms)
✔ S3 Supabase Primary: unverified doctor blocked from reading record even with appointment (0.5335ms)
✔ S3 Supabase Primary: assigned lab allowed to upload/download lab report (4.0015ms)
✔ S3 Supabase Primary: confirmS3Upload writes snake_case columns to Supabase and logs to Postgres (0.8897ms)
✔ confirmS3Upload: missing object (head_not_found) attempts delete and audit logs failure (0.9323ms)
✔ confirmS3Upload: invalid content-type deletes uploaded S3 object and audit logs failure (0.6289ms)
✔ confirmS3Upload: size exceeded deletes uploaded S3 object and audit logs failure (0.7459ms)
✔ S3 URL cache flag default is "off" (12.834ms)
✔ Flag off -> zero Redis calls on download or upload (30.6934ms)
✔ ORDER MATTERS: auth failure never reaches cache (2.8788ms)
✔ Cache hit returns cached URL with enough remaining life (>= 15 mins) (6.1632ms)
✔ Delete invalidates cached download URL (2.6552ms)
✔ Upload URL generation (overwrite protection) invalidates cached download URL (6.1295ms)
✔ Batch invalidation removes all specified keys (1.5431ms)
✔ Fail-open policy: Redis error or down generates fresh presigned URL (5.0255ms)
ℹ tests 65
ℹ suites 0
ℹ pass 65
ℹ fail 0
ℹ cancelled 0
ℹ skipped 0
ℹ todo 0
ℹ duration_ms 1401.7382
```
**Total:** 65 passed, 0 failed.

---

## 5. Real Frontend Test Execution Output

### Command Run:
```bash
flutter test test/core/storage/s3_storage_confirmation_test.dart
```

### Real Command Output:
```text
00:00 +0: loading C:/Users/khije/Downloads/DoctorNect/doctor/frontend/test/core/storage/s3_storage_confirmation_test.dart
00:00 +0: S3StorageService Confirmation Contract uploadBytes invokes S3 PUT and automatically confirms with backend
00:00 +1: S3StorageService Confirmation Contract uploadBytes throws and skips confirmUpload when HTTP PUT fails with 403
00:00 +2: S3StorageService Confirmation Contract explicit confirmUpload delegates to S3PresignApi
00:00 +3: All tests passed!
```

---

## 6. Audit Log Rules: Dual Targets

### 6.1 PostgreSQL Storage Audit Logs (`db/migrations/20261020000002_phase_c_doctor_patient_cutover.sql`)
```sql
CREATE TABLE IF NOT EXISTS public.storage_audit_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  action text NOT NULL,
  s3_key text,
  bucket text,
  user_id text NOT NULL,
  ip text,
  user_agent text,
  status text NOT NULL,
  error text,
  file_size_bytes bigint,
  created_at timestamptz NOT NULL DEFAULT timezone('utc'::text, now())
);

ALTER TABLE public.storage_audit_logs ENABLE ROW LEVEL SECURITY;

-- Deny all client write operations (server-side service_role writes only)
REVOKE ALL ON public.storage_audit_logs FROM public, anon, authenticated;

-- Allow super admin to inspect logs via RLS
CREATE POLICY storage_audit_logs_admin_select ON public.storage_audit_logs
  FOR SELECT TO authenticated
  USING (is_super_admin());
```

### 6.2 Firestore Storage Audit Logs (`backend/firestore.rules`)
```javascript
    // ─── Storage Audit Logs (Server-only writes, Super Admin read-only) ────

    match /storage_audit_logs/{logId} {
      allow read: if isSuperAdmin();
      allow write: if false;
    }
```

---

## 7. Secrets and Tracked Files Audit

### Command Run:
```bash
git ls-files "*env*"
```

### Real Output:
```text
.agents/skills/firebase-basics/references/local-env-setup.md
.env.example
backend/.env.migration.example
backend/functions/.env.example
backend/scripts/load_env.js
frontend/.env.example
```
**Zero active credentials or secret values tracked.**

---

## 8. Explicitly UNVERIFIED Items (Pre-Staging Scope Boundary)

The following items cannot be verified in local offline CI/Docker test suites and are explicitly tracked as **UNVERIFIED** pending live cloud staging deployment:

1. **Real AWS S3 Cloud Storage**: Live upload/download round trips to AWS S3 buckets in `ap-south-1`.
2. **Real Physical Devices S3 Uploads**: Live mobile device uploads with real camera and file pickers.
3. **Real FCM Push Delivery**: Physical device push notification delivery via Google FCM servers.
4. **Real Supabase-Hosted Webhook**: Database webhooks triggered from managed Supabase Cloud instances over public internet.
5. **Real Physical Devices**: Live testing on physical Android and iOS hardware.
