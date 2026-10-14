# DoctorNect: Firebase → Supabase Migration & Cutover Runbook

This runbook provides the operational manual for executing the backend migration of **DoctorNect** from Firebase to Supabase without downtime, data loss, or disruption to live Google Play Store users.

---

## 1. Prerequisites & Environment Setup

### Required Tools
- Node.js (v18+)
- Supabase CLI (`npm install -g supabase` or `npx supabase`)
- Firebase CLI (`npm install -g firebase-tools`)
- Flutter SDK (Dart 3.2+)

### Environment Variables for Migration Scripts
Copy `.env.migration.example` to `.env.migration` (which is gitignored) and fill in credentials:
```bash
cp .env.migration.example .env.migration
```
> [!IMPORTANT]
> **Zero Plaintext Credentials Policy:**
> All migration and rollback scripts (`migrate_firestore_to_supabase.js`, `reverse_sync_supabase_to_firestore.js`, `test_rls_policies.js`) automatically load credentials from `.env.migration` via `scripts/load_env.js`.
> **NEVER pass connection strings inline in CLI commands or PowerShell `$env:` one-liners**, as this permanently exposes credentials in terminal transcripts and shell history.

### Sync Feature Switches & Strict Flag Parsing Contract

All sync enablement switches adhere to a strict boolean parsing policy (`backend/functions/sync_flags.js`):
- **Accepted Truthy Values**: strictly `'1'` and `'true'` (case-insensitive, trimmed).
- **Dormant Values (Default)**: unset, empty string (`""`), `'0'`, `'false'`, `'off'`, `'on'`.
- **Target Switches**:
  | Switch | Scope | Truthy Values | Behavior When Dormant (Default) |
  |---|---|---|---|
  | `ENABLE_SUPABASE_SYNC` | Cloud Functions (`backend/functions/index.js`) | `'1'`, `'true'` (case-insensitive) | Zero sync triggers are exported (`sync*ToSupabase` stay unexported). |
  | `ENABLE_SUPABASE` | Flutter build scripts (`release_build.sh`, `release_build.ps1`) | `'1'` | Omits `SUPABASE_URL` and `SUPABASE_ANON_KEY` dart-defines; app client stays 100% on Firebase. |

> [!CAUTION]
> **Production Safety Invariant**: **DO NOT enable `ENABLE_SUPABASE` or `ENABLE_SUPABASE_SYNC` in production** until staging cutover and parity audits are 100% verified.

---

## 2. Phase 1 & 3: Database & RLS Migration

All SQL migration scripts are located in `supabase/migrations/`:
1. `20260923000001_doctornect_schema.sql` (Full normalized relational DDL + IPD forward hooks)
2. `20260923000002_doctornect_rls.sql` (Security Definer helper functions & 33 RLS policy blocks)
3. `20260923000003_doctornect_cron.sql` (Automated pg_cron maintenance jobs)

### Execution via Supabase CLI
```bash
# Link your local project to Supabase cloud
supabase link --project-ref <your-project-ref>

# Push migrations to production database
supabase db push
```

*Alternatively, execute the contents of each `.sql` file in sequence directly inside the Supabase Studio SQL Editor.*

---

## 3. Phase 4: Edge Functions Deployment

Deploy the two core serverless Edge Functions to Supabase:

### 1. Set Function Secrets
```bash
# Egress Proxy & SMS Gateway Secrets
supabase secrets set \
  MSG91_PROXY_URL="https://msg91-proxy-658118593597.asia-south1.run.app/otp" \
  PROXY_SECRET="<proxy-secret-from-gcp-secret-manager>" \
  MSG91_TEMPLATE_ID_REGISTRATION="6a82fb0c248c482651029d14" \
  MSG91_TEMPLATE_ID_LOGIN="6a82f82114fa5616e7034772" \
  MSG91_TEMPLATE_ID_PASSWORD_RESET="6a82fabaaaba9478cd046022" \
  MSG91_SENDER_ID="DRNECT" \
  RAZORPAY_KEY_ID="<your-razorpay-key-id>" \
  RAZORPAY_KEY_SECRET="<your-razorpay-key-secret>" \
  RAZORPAY_WEBHOOK_SECRET="<your-razorpay-webhook-secret>"
```

> [!NOTE]
> **Egress Proxy Architecture & IP Tracking:**
> The `auth-otp` function routes outbound OTP dispatch through the `msg91-proxy` Cloud Run service attached to `msg91-connector` and Cloud NAT (`msg91-nat`), guaranteeing static outbound IP `35.200.245.73`. During initial verification, MSG91 accepted requests from this new IP without pre-registration, indicating MSG91 IP allowlisting is currently relaxed on the production Auth Key. The proxy is retained as a permanent defense-in-depth barrier so any future IP policy enforcement by MSG91 will not disrupt service.

### 2. Deploy Functions
```bash
# Deploy auth-otp (handles public pre-flight and MSG91 verification)
supabase functions deploy auth-otp --no-verify-jwt

# Deploy razorpay-payments (handles order creation, verification, and webhooks)
supabase functions deploy razorpay-payments --no-verify-jwt

# Deploy sync-to-firestore (handles reverse sync of cancellations/status changes to Firestore)
supabase functions deploy sync-to-firestore --no-verify-jwt
```

### 3. Dedicated Service Account Setup (`sync-to-firestore`)

To maintain least-privilege isolation, the `sync-to-firestore` Edge Function must not share administrative service accounts. It requires a dedicated GCP service account restricted to `roles/datastore.user`.

#### Creation Commands (gcloud):
```bash
# 1. Create dedicated service account
gcloud iam service-accounts create doctornect-sync-to-firestore \
  --description="Service account for Supabase sync-to-firestore reverse bridge" \
  --display-name="DoctorNect Sync To Firestore"

# 2. Grant least-privilege Firestore / Datastore user role ONLY
gcloud projects add-iam-policy-binding <GCP_PROJECT_ID> \
  --member="serviceAccount:doctornect-sync-to-firestore@<GCP_PROJECT_ID>.iam.gserviceaccount.com" \
  --role="roles/datastore.user"

# 3. Generate key file securely (store in secure credential vault, never commit to git)
gcloud iam service-accounts keys create sa-key.json \
  --iam-account="doctornect-sync-to-firestore@<GCP_PROJECT_ID>.iam.gserviceaccount.com"
```

#### Required Environment Variable Names for Edge Function:
Configure these secrets in Supabase via `supabase secrets set`:
- `SYNC_TO_FIRESTORE_SECRET`: Shared webhook authentication secret verified via constant-time comparison.
- **Either** full JSON key:
  - `FIREBASE_SERVICE_ACCOUNT_KEY`: Raw or base64-encoded JSON key file from `sa-key.json`.
- **Or** individual environment variables:
  - `FIREBASE_PROJECT_ID`: GCP / Firebase Project ID.
  - `FIREBASE_CLIENT_EMAIL`: Service account email (`doctornect-sync-to-firestore@<project>.iam.gserviceaccount.com`).
  - `FIREBASE_PRIVATE_KEY`: PKCS#8 PEM private key (including `-----BEGIN PRIVATE KEY-----`).
- **Optional Overrides** (for local emulator or staging endpoints):
  - `FIRESTORE_BASE_URL`: Overrides `https://firestore.googleapis.com/v1`.
  - `FIRESTORE_EMULATOR_HOST`: Point to local emulator (e.g. `127.0.0.1:8080`).
  - `GOOGLE_OAUTH_TOKEN_URL`: Overrides `https://oauth2.googleapis.com/token`.

> [!WARNING]
> **Strict Zero-Secret Policy**: Never print, echo, commit, or hardcode private keys or webhook secrets into repository source code or terminal histories.

### 3b. Supabase Database Webhook Configuration (`sync-to-firestore`)

To support live reverse synchronization of appointment status updates, cancellations, and fallback creation:
- **Target Table**: `public.appointments`
- **Events**: Must be configured for **BOTH `INSERT` and `UPDATE`** (not just `UPDATE`).
- **Webhook Target**: `POST https://<project-ref>.supabase.co/functions/v1/sync-to-firestore`
- **HTTP Headers**:
  - `Content-Type: application/json`
  - `x-webhook-secret: <SYNC_TO_FIRESTORE_SECRET>`

#### Event Semantics & Loop Prevention:
1. **Loop Prevention Filter**: Any `INSERT` or `UPDATE` where `sync_origin` indicates Firestore origin (`doctor_firestore`, `patient_firestore`, `reconciler_bot`, `firestore_cloud_function`, `firestore`) or was replicated by `synced_by` (`supabase_bridge`, `firestore_cloud_function`, `reconciler_bot`) is dropped with HTTP `200 { ignored: true }`. However, mutations authored in Supabase (`sync_origin = 'patient_supabase'` or `'doctor_supabase'`) are never dropped simply because `synced_by` holds a previous replication marker.
2. **`INSERT` Handling (Create-Only Guard)**:
   - When an appointment is inserted into Supabase, `sync-to-firestore` maps the row into a full Firestore appointment document matching the `bookAppointment` and `AppointmentFirestoreMapper` contract and injects `syncedBy: 'supabase_bridge'`.
   - The write enforces precondition `currentDocument.exists = false`.    - If the document already exists in Firestore (e.g. from client-side dual-write), Firestore reports `ALREADY_EXISTS` (unverified, see verification procedure). The Edge Function catches this and returns `200 { ignored: 'already_exists' }`, guaranteeing it **never overwrites** an existing document on `INSERT`.
3. **`UPDATE` Handling**:
   - Compares changed status and cancellation fields (`patient_status`, `doctor_status`, `cancellation_reason`). When an `UPDATE` changes `patient_status` to `'cancelled'`, also writes `doctorStatus: 'cancelled'` and `cancellationReason` (Firestore `patientStatus` is never written as `'cancelled'`).
   - Rejects transitions out of terminal states (`completed`, `inProgress`, `noShow`) with `200 { skipped: 'terminal_state' }` and records a durable dead letter in Firestore's `syncDeadLetters` collection (deterministic ID, zero free text).
   - Non-terminal updates write strictly changed fields with precondition `currentDocument.updateTime`, retrying once on concurrent modification / conflict (unverified, see verification procedure).

### 3c. Sync Parity Audit & Observability Reference

During the dual-run and staging window, cross-system consistency must be audited weekly using the read-only parity auditor:
```bash
node scripts/check_sync_parity.js --audit
```
#### Parity Verification Coverage:
1. **Appointments Existence**:
   - `inPgNotFs`: Count of appointments present in Supabase PostgreSQL but missing in Firestore.
   - `inFsNotPg`: Count of appointments present in Firestore but missing in Supabase PostgreSQL.
2. **Effective Status Parity**:
   - `mismatched`: Compares effective state (`doctor_status` vs `doctorStatus`, accounting for terminal state propagation where `patientStatus` is maintained as pending/confirmed).
3. **Weekly Observability & Alerting Manual**:
   For the complete operational guide covering skip/dead-letter dictionaries, GCP log metrics, Supabase Logs Explorer queries, and dead-letter replay procedures (re-reading from SoR), refer directly to:
   👉 **[SUPABASE_SYNC_OBSERVABILITY.md](SUPABASE_SYNC_OBSERVABILITY.md)**.

### 3d. Precondition Status Code Verification Procedure (Real Firestore Project)

> **Notice**: All HTTP status code claims for Cloud Firestore REST preconditions are **unverified on production; verify on a real project** using the throwaway test procedure below before cutover.

#### Setup:
Obtain an OAuth2 access token for a Google Cloud project with Cloud Datastore User role:
```bash
export ACCESS_TOKEN=$(gcloud auth print-access-token)
export PROJECT_ID="<your-throwaway-or-staging-project>"
export BASE_URL="https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents"
export COMMIT_URL="${BASE_URL}:commit"
```

#### Test Case 1: Precondition `currentDocument.exists = true` against non-existent document
```bash
# Attempt to PATCH document 'test-missing-doc-999' requiring exists=true
curl -s -w "\nHTTP_STATUS: %{http_code}\n" -X POST "${COMMIT_URL}" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "writes": [{
      "update": {
        "name": "projects/'"${PROJECT_ID}"'/databases/(default)/documents/appointments/test-missing-doc-999",
        "fields": { "doctorStatus": { "stringValue": "confirmed" } }
      },
      "currentDocument": { "exists": true }
    }]
  }'
# Expected observation:
# Record exact HTTP_STATUS and response JSON (specifically error.code, error.status, error.message).
# Does it return HTTP 404 with status NOT_FOUND, or HTTP 400 with status FAILED_PRECONDITION?
```

#### Test Case 2: Precondition `currentDocument.exists = false` against existing document
```bash
# 1. Create document first
curl -s -X PATCH "${BASE_URL}/appointments/test-existing-doc-111" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{ "fields": { "doctorStatus": { "stringValue": "pendingRequest" } } }'

# 2. Attempt INSERT with exists=false
curl -s -w "\nHTTP_STATUS: %{http_code}\n" -X POST "${COMMIT_URL}" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "writes": [{
      "update": {
        "name": "projects/'"${PROJECT_ID}"'/databases/(default)/documents/appointments/test-existing-doc-111",
        "fields": { "doctorStatus": { "stringValue": "confirmed" } }
      },
      "currentDocument": { "exists": false }
    }]
  }'
# Expected observation:
# Record exact HTTP_STATUS and response JSON (specifically error.code, error.status, error.message).
# Does it return HTTP 409 with status ALREADY_EXISTS, or HTTP 400 with status FAILED_PRECONDITION?
```

#### Test Case 3: Precondition `currentDocument.updateTime` mismatch (Stale Concurrency Token)
```bash
# Attempt update with a deliberately stale / mismatched RFC 3339 updateTime
curl -s -w "\nHTTP_STATUS: %{http_code}\n" -X POST "${COMMIT_URL}" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "writes": [{
      "update": {
        "name": "projects/'"${PROJECT_ID}"'/databases/(default)/documents/appointments/test-existing-doc-111",
        "fields": { "doctorStatus": { "stringValue": "confirmed" } }
      },
      "currentDocument": { "updateTime": "2020-01-01T00:00:00Z" }
    }]
  }'
# Expected observation:
# Record exact HTTP_STATUS and response JSON (specifically error.code, error.status, error.message).
# Does it return HTTP 412, HTTP 409, or HTTP 400 with status FAILED_PRECONDITION / ABORTED?
```

#### Cleanup:
```bash
curl -s -X DELETE "${BASE_URL}/appointments/test-existing-doc-111" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}"
```

---

## 4. Phase 5: Baseline Data Migration (T-7 Days)

Run the automated data migration script to copy historical data from Firestore into PostgreSQL.

### Step 1: Install Script Dependencies
```bash
cd scripts
npm install
cd ..
```

### Step 2: Run Dry-Run Simulation
```bash
node scripts/migrate_firestore_to_supabase.js --dry-run
```
*Review the output audit table to ensure zero schema errors and verify document counts match.*

### Step 3: Run Baseline Live Migration
```bash
node scripts/migrate_firestore_to_supabase.js --live
```

### Step 4: Verify Live Demo Accounts
Run these verification queries in Supabase SQL editor:
```sql
-- 1. Verify 5 Google Play review demo accounts exist and are verified
SELECT uid, role, mobile, verified, display_name 
FROM users 
WHERE mobile IN ('7058809803', '7666892394', '9359503874', '9409858233', '9307583929');

-- 2. Verify Doctor profile is approved
SELECT doctor_id, name, specialization, verified 
FROM doctors 
WHERE mobile = '7666892394';

-- 3. Verify Ambulance private settings and PIN hash
SELECT ambulance_id, pin_hash 
FROM ambulance_private_settings 
WHERE ambulance_id = '9307583929';
```

---

## 5. Phase 7: Live Cutover Window (Sunday 01:00 AM – 04:00 AM IST)

### Pre-Cutover Standing Prerequisites
- [ ] **Firebase CLI Authentication**: Ensure `npx firebase-tools projects:list` succeeds without error. Re-authenticate in advance via `firebase login --reauth`.
- [ ] **Traffic Isolation Mechanism**: Legacy Flutter clients (v1.0.x) do not contain a Remote Config `maintenance_mode` listener in code. Traffic isolation is enforced strictly at the database layer via Firestore Security Rules (read-only during freeze; restored upon completion/rollback).

### Cutover Execution Checklist

| Time (IST) | Action | Command / Procedure |
|---|---|---|
| **01:00 AM** | Standing Auth & Env Verification | Confirm `firebase projects:list` and Supabase DB connection |
| **01:15 AM** | Freeze Firestore Writes | Deploy read-only rules: `firebase deploy --only firestore:rules` |
| **01:20 AM** | Execute Final Delta Migration | `node scripts/migrate_firestore_to_supabase.js --live --since="<baseline_timestamp>"` |
| **02:00 AM** | Data Parity Check | Run count parity queries between Firestore & Postgres |
| **02:30 AM** | Release Supabase App Build | Promote Flutter v1.1.0 to Production on Google Play Console (Staged Rollout) |
| **03:00 AM** | Live Smoke Test 5 Roles | Test all 5 demo accounts (`000000` OTP) on real devices |
| **03:45 AM** | Finalize Cutover | Deploy final Firestore rules / monitor live Postgres metrics |

---

## 6. Emergency 3-to-4 Minute Rollback Plan (Verified Protocol)

If a critical blocker is encountered during cutover, execute the rollback immediately. Total verified execution time is **~3 to 4 minutes** (contingent on Firebase CLI standing authentication pre-condition).

### Rollback Execution Steps:

1. **Freeze Supabase Client Writes (T+0 min, Duration: < 1s):**
   - Instantly revoke all write permissions from public client roles (`anon` and `authenticated`) to prevent new records from entering Supabase while or after reverse-sync runs:
   ```sql
   -- Execute in Supabase Studio SQL Editor or via psql:
   REVOKE INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public FROM anon, authenticated;
   ```
   *(To undo/re-enable writes if rollback is cancelled:)*
   ```sql
   GRANT ALL ON ALL TABLES IN SCHEMA public TO anon, authenticated;
   ```

2. **Halt Google Play Rollout (T+1 min, Duration: ~1-2 min):**
   - **Manual step (cannot be automated):**
   - Navigate to **Google Play Console** -> **Release** -> **Production** -> Click **Halt Rollout**.
   - Halting stops new devices from downloading v1.1.0 (Supabase build).

3. **Execute Reverse Sync (T+2 min, Duration: ~3-5s, Verified: 1.34s):**
   - Synchronize any records created in Supabase during the live window back into Firestore (`appointments`, `prescriptions` + line items, `reviews`, and `users`):
   ```bash
   node scripts/reverse_sync_supabase_to_firestore.js --live --since="<cutover_start_time>"
   ```
   *Note: For testing without touching live collections, use the `--collection-prefix="test_rollback_"` flag:*
   ```bash
   node scripts/reverse_sync_supabase_to_firestore.js --live --collection-prefix="test_rollback_"
   ```

4. **Restore Firestore Security Rules (T+3 min, Duration: ~20-30s):**
   - Restore original production Firestore security rules to allow legacy app clients to resume writes:
   ```bash
   firebase deploy --only firestore:rules
   ```
   > [!IMPORTANT]
   > **Standing Pre-Condition:** Firebase CLI must already be authenticated beforehand (`npx firebase-tools projects:list`). Never leave CLI login to the moment of emergency.

5. **Legacy Client Traffic Resumption & Isolation (T+4 min):**
   - **Traffic Isolation Reality (Option A):** Because legacy Flutter clients (v1.0.x) do not implement Firebase Remote Config or an app-level `maintenance_mode` flag, write isolation relies 100% on Firestore Security Rules. As soon as production rules are restored in Step 4, all legacy Flutter clients immediately resume normal read/write operations without requiring an app update or maintenance flag flip.
   *(Long-term defense-in-depth: An app-level `maintenance_mode` Remote Config banner can be implemented in future client versions, but is not currently present in v1.0.x).*

### Rollback Timeline Breakdown (Verified vs. Documented)

| Step | Action | Type | Duration |
|---|---|---|---|
| **Step 1** | Freeze Supabase Writes | Automated SQL | **< 1s** (Tested: 48ms) |
| **Step 2** | Halt Google Play Rollout | Manual Web Console | **~1-2 min** |
| **Step 3** | Supabase → Firestore Reverse Sync | Automated Script | **~3-5s** (Tested: 1.34s) |
| **Step 4** | Restore Firestore Rules | Automated CLI | **~20-30s** |
| **Step 5** | Legacy Client Resumption | Immediate (via Rules) | **0s** (Instant) |
| **TOTAL** | **Full Emergency Rollback** | | **~3 to 4 minutes** |
