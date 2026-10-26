# DoctorNect: Supabase to Firestore Sync Rollout Runbook (SYNC-01)

> **Document Classification:** Operational Runbook / Production Rollout  
> **Target Function:** `sync-to-firestore` (Supabase Edge Function)  
> **Production Project Reference:** `rnltknemwnjrjxthtull`  
> **Status:** Edge function deployed (`--no-verify-jwt`), pending secrets configuration and DB webhook binding.
>
> **NOTE (CLEAN CUTOVER): NOT REQUIRED FOR LAUNCH**  
> DoctorNect is launching via a clean cutover architecture with no live production users. The Firestore<->Supabase sync bridge (`ENABLE_SUPABASE_SYNC`, `sync-to-firestore`, DB webhooks) is **NOT required for launch**. Keep `ENABLE_SUPABASE_SYNC=0` (disabled) and do not configure or trigger this bridge. Retain this runbook solely for prospective future phased migrations if needed.

---

## 1. Overview & Architecture

The `sync-to-firestore` edge function acts as the authenticated reverse-synchronization bridge between Supabase PostgreSQL and Google Cloud Firestore. When records (appointments, cancellations, patient updates) are created or mutated in Supabase, a PostgreSQL Database Webhook invokes this function with an authenticated secret header (`x-sync-secret`). The function translates the relational record into Firestore document representations.

### Security Boundaries
- **Fail-Closed Authentication:** If `SYNC_TO_FIRESTORE_SECRET` is unset or does not match the incoming webhook header, the edge function immediately rejects the request with HTTP 401 / 500 without writing to Firestore.
- **Least-Privilege Google Service Account:** `FIREBASE_SERVICE_ACCOUNT_KEY` must use a dedicated IAM service account restricted strictly to Firestore operations. **Never** assign Project Owner or Editor roles.

---

## 2. Staged Rollout Checklist

Follow these steps in strict sequence. All remote CLI / dashboard commands are **MANUAL** actions for authorized administrators.

### Step 1: Pre-requisites & Local Staging Verification
- [ ] Confirm local test suite passes:
  ```bash
  cd backend/functions
  npm test
  ```
- [ ] Verify loop prevention tests pass:
  - `sync-to-firestore.test.js:2462` (Forward & reverse loop prevention)
  - `user_identity_bridge.test.js:72` (User sync loop prevention)
  - `cross_role_sync.test.js:39` (Cross-role loop prevention)

### Step 2: Generate Reverse-Sync Webhook Secret
- [ ] Generate a secure, high-entropy 256-bit secret locally using OpenSSL:
  ```bash
  openssl rand -hex 32
  ```
  *(Store this secret in your secure password manager. NEVER commit or log this value).*

### Step 3: Provision Least-Privilege Firebase Service Account
- [ ] In Google Cloud Console / Firebase Console:
  1. Navigate to **IAM & Admin** > **Service Accounts**.
  2. Create a service account: `supabase-firestore-sync-worker@medibond-45fad.iam.gserviceaccount.com`.
  3. Assign only the minimal required role:
     - `Cloud Datastore User` (`roles/datastore.user`) — permits read/write to Firestore documents.
     - **DO NOT** assign `Firebase Admin`, `Editor`, or `Owner`.
  4. Generate a new private JSON key for this service account and download securely.

### Step 4: Configure Supabase Cloud Secrets (MANUAL)
- [ ] Set secrets on production project `rnltknemwnjrjxthtull`:
  ```bash
  # Run from backend/ directory:
  npx supabase secrets set --project-ref rnltknemwnjrjxthtull \
    SYNC_TO_FIRESTORE_SECRET="<YOUR_OPENSSL_GENERATED_HEX>" \
    FIREBASE_SERVICE_ACCOUNT_KEY='<MINIFIED_SERVICE_ACCOUNT_JSON>'
  ```
- [ ] Verify secrets are registered (names present, values hidden):
  ```bash
  npx supabase secrets list --project-ref rnltknemwnjrjxthtull
  ```
  Expected output:
  - `SYNC_TO_FIRESTORE_SECRET`: Digest present
  - `FIREBASE_SERVICE_ACCOUNT_KEY`: Digest present

### Step 5: Configure Supabase Database Webhook (MANUAL)
- [ ] In the Supabase Dashboard:
  1. Go to **Database** > **Webhooks** > **Create a new webhook**.
  2. **Name:** `sync_appointments_to_firestore`
  3. **Table:** `public.appointments`
  4. **Events:** `INSERT`, `UPDATE`
  5. **Type:** HTTP Request
  6. **Method:** `POST`
  7. **URL:** `https://rnltknemwnjrjxthtull.supabase.co/functions/v1/sync-to-firestore`
  8. **HTTP Headers:**
     - Key: `x-sync-secret`
     - Value: `<YOUR_OPENSSL_GENERATED_HEX>`
     - Key: `Content-Type`
     - Value: `application/json`
  9. Click **Save Webhook**.

### Step 6: Enable Cloud Functions Forward Sync Trigger
- [ ] Set `ENABLE_SUPABASE_SYNC=1` in `backend/functions/.env` (and Firebase Functions runtime config).
- [ ] Deploy Cloud Functions:
  ```bash
  firebase deploy --only functions
  ```

### Step 7: End-to-End Smoke Test
- [ ] **Patient Booking Flow:**
  1. Patient books an appointment via the app or test client in Supabase.
  2. Confirm Supabase edge function `sync-to-firestore` logs HTTP 200 in Supabase Dashboard (Functions > sync-to-firestore > Invocations).
  3. Confirm the corresponding document appears in Firestore `appointments/{appointmentId}`.
  4. Confirm Doctor Dashboard calendar reflects the newly synced appointment.
- [ ] **Cancellation Flow:**
  1. Cancel the appointment in Supabase.
  2. Confirm Firestore document status updates to `cancelled` with `cancellationReason`.

---

## 3. Loop Prevention (Echo-Chamber Guard)

Both forward and reverse sync bridges implement strict origin and actor tagging to prevent infinite write loops:

```
[Patient / Client]
        │
        ▼ (sync_origin: 'patient_supabase', synced_by: null)
┌─────────────────┐
│ Supabase DB     │
└────────┬────────┘
         │ (DB Webhook)
         ▼
┌─────────────────────────┐
│ sync-to-firestore       │─── Writes to Firestore ───► ┌────────────────────┐
│ (Edge Function)         │    synced_by:               │ Firestore DB       │
└─────────────────────────┘    'supabase_edge_function' └─────────┬──────────┘
                                                                  │ (Cloud Function trigger)
                                                                  ▼
                                                        ┌────────────────────┐
                                                        │ Cloud Function     │
                                                        │ Sync Trigger       │
                                                        └─────────┬──────────┘
                                                                  │ Checks synced_by!
                                                                  │ IF synced_by == 'supabase_edge_function':
                                                                  ▼
                                                           [DROP / IGNORE]
                                                         (Loop Terminated)
```

### Covered Test Specs:
- [sync_to_firestore.test.js:2462](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/functions/test/sync_to_firestore.test.js#L2462)
- [sync_to_firestore.test.js:2583](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/functions/test/sync_to_firestore.test.js#L2583)
- [user_identity_bridge.test.js:72](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/functions/test/user_identity_bridge.test.js#L72)
- [cross_role_sync.test.js:39](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/functions/test/cross_role_sync.test.js#L39)

---

## 4. Rollback Plan

If reverse-sync exhibits unexpected latency, serialization errors, or Firestore schema mismatch:
1. **Immediate Decouple:**
   - In Supabase Dashboard > **Database** > **Webhooks**, toggle `sync_appointments_to_firestore` to **Disabled**.
2. **Disable Forward Sync:**
   - Set `ENABLE_SUPABASE_SYNC=0` in Cloud Functions and re-deploy:
     ```bash
     firebase deploy --only functions
     ```
3. **Audit Dead Letters:**
   - Inspect Firestore `syncDeadLetters` collection for any un-synchronized payloads during the rollout window.
   - Run reconcile script:
     ```bash
     node backend/scripts/reconcile_sync_dead_letters.js
     ```
