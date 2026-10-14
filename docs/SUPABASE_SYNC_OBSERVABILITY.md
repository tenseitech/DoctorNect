# DoctorNect: Supabase ↔ Firestore Sync Observability & Dead-Letter Runbook

This guide documents the error codes, dead-letter contracts, logging infrastructure, alerting mechanisms, weekly audit procedures, and manual reconciliation workflows for the bidirectional sync bridge between Supabase PostgreSQL and Firebase Cloud Firestore.

---

## 1. Dictionary of Skip & Dead-Letter Reasons

| Reason Code | Pipeline Direction | Description | Where Recorded | Action / Impact |
|---|---|---|---|---|
| `firestore_doc_missing` | Supabase $\to$ Firestore (`sync-to-firestore`) | An `UPDATE` event was received from Supabase for an appointment that does not exist in Firestore. | Firestore `syncDeadLetters` collection; Edge Function structured warning log. | Skipped (`200 { skipped: "not_found" }`). Target doc absent. |
| `terminal_state` | Supabase $\to$ Firestore (`sync-to-firestore`) | An update attempted to alter an appointment already in a terminal state (`completed`, `inProgress`, `noShow`). | Firestore `syncDeadLetters` collection; Edge Function structured warning log. | Skipped (`200 { skipped: "terminal_state" }`). Guard protects doctor consultation SoR. |
| `no_status_change` | Supabase $\to$ Firestore (`sync-to-firestore`) | Webhook delivered an `UPDATE` event where neither doctor/patient status nor cancellation fields changed (e.g. token-only update). | Edge Function HTTP response (`200 { ignored: "no_status_change" }`). | Skipped. No mutation needed. |
| `already_exists` | Supabase $\to$ Firestore (`sync-to-firestore`) | An `INSERT` event was received for an appointment doc that already exists in Firestore (precondition `currentDocument.exists = false` failed). | Edge Function HTTP response (`200 { ignored: "already_exists" }`). | Ignored. Never overwrites existing Firestore document. |
| `missing_required_fields` | Supabase $\to$ Firestore (`sync-to-firestore`) | An `INSERT` row is missing one or more required contract fields (`doctorId`, `patientId`, `doctorName`, `patientName`, `dateTime`, `slotLabel`, `tokenNumber`, `patientStatus`, `doctorStatus`, `visitType`). | Firestore `syncDeadLetters` collection; Edge Function log (field names only). | Rejected (`200 { skipped: "missing_required_fields" }`). No document created. |
| `invalid_status_value` | Supabase $\to$ Firestore (`sync-to-firestore`) | An `INSERT` has a non-allowed status (e.g. `patient_status` is `completed`/`cancelled`, or invalid `doctor_status`/`visit_type`). | Firestore `syncDeadLetters` collection; Edge Function log (field names only). | Rejected (`200 { skipped: "invalid_status_value" }`). No document created. |
| `email_collision_insert_synthetic` | Firestore $\to$ Supabase (`cross_role_sync.js`) | User identity bridge hits unique constraint `users_email_key` during new user INSERT. | Google Cloud Logging (`action: email_collision_insert_synthetic`); Supabase `public.users`. | Retried with synthetic email (`user_<uuid>@synthetic.doctornect.local`). |
| `SYNC_BRIDGE_PAYLOAD_VALIDATION_FAILED` | Firestore $\to$ Supabase (`cross_role_sync.js`) | Firestore mutation failed schema validation before syncing into PostgreSQL. | Google Cloud Logging (`action: sync.validation_failed`); `public.sync_dead_letter_queue` (if DB connected). | Skipped. Investigated via Cloud Logging. |

---

## 2. Infrastructure & Log Routing Reality

> [!IMPORTANT]
> **Logs Separation Warning:**
> - **Supabase Edge Functions** (`sync-to-firestore`) run on Deno deploy infrastructure managed by Supabase. Their runtime logs are stored in the **Supabase Dashboard / Logs Explorer** and are **NOT visible in Google Cloud Logging** unless an external HTTPS log drain is configured.
> - **Firebase Cloud Functions** (`cross_role_sync.js`, `index.js`) run on Google Cloud Functions (asia-south1 / asia-south2). Their logs are streamed directly to **Google Cloud Logging (Cloud Operations Suite)**.

---

## 3. Alerting Options

### Option A: Firebase Cloud Functions via GCP Log-Based Metrics
To alert on Firestore $\to$ Supabase bridge failures, create log-based metrics and alerting policies in Google Cloud:

```bash
# 1. Create a log-based metric for sync failures in Cloud Functions
gcloud logging metrics create supabase_sync_failures \
  --description="Counts failed Firestore-to-Supabase sync bridge executions" \
  --log-filter='resource.type="cloud_function"
resource.labels.function_name="syncAppointmentToSupabase"
severity>=ERROR'

# 2. Create a log-based metric for email collision synthetic fallbacks
gcloud logging metrics create supabase_user_sync_collisions \
  --description="Counts user sync email collisions resolved via synthetic email" \
  --log-filter='jsonPayload.action="email_collision_insert_synthetic"'
```

### Option B: Firestore `syncDeadLetters` Automated Query
The `syncDeadLetters` collection in Firestore stores durable, deterministic dead letters without PII.
- **Monitoring Strategy**: A lightweight daily Cloud Function or cron worker queries:
  ```javascript
  const unhandledSnap = await db.collection('syncDeadLetters')
    .where('skippedAt', '>=', new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString())
    .get();
  if (!unhandledSnap.empty) {
    // Send Slack / PagerDuty alert with count of dead letters: unhandledSnap.size
  }
  ```
- **Privacy Guarantee**: Dead letters store only entity IDs and field names (`['patient_status']`), with zero patient names, phone numbers, or free-text cancellation reasons.

### Option C: Supabase Logs Explorer Queries (Edge Functions)
In **Supabase Studio** -> **Logs** -> **Edge Functions**:
- **All Skips & Dead Letters**:
  ```sql
  select timestamp, event_message 
  from edge_logs 
  where event_message like '%skipped:%' 
  order by timestamp desc limit 100;
  ```
- **Terminal State Guard Rejections**:
  ```sql
  select timestamp, event_message 
  from edge_logs 
  where event_message like '%sync.terminal_state_rejected%' 
  order by timestamp desc limit 100;
  ```
- **Precondition Conflicts & Retries**:
  ```sql
  select timestamp, event_message 
  from edge_logs 
  where event_message like '%Precondition conflict%' 
  order by timestamp desc limit 100;
  ```

---

## 4. Weekly Verification Procedure

Every Monday or during the cutover window:
1. **Run Parity Auditor (Read-Only)**:
   ```bash
   node scripts/check_sync_parity.js --audit
   ```
   Verify that `Missing in Firestore`, `Missing in Postgres`, and `Status Mismatches` counts are zero for all active appointments.
2. **Inspect Firestore Dead Letters**:
   Check the `syncDeadLetters` collection in Firestore console. Group by `reason` to spot any systematic validation or timing issues.
3. **Verify Function Health**:
   Check Supabase Edge Function error rate in Supabase Studio. Confirm HTTP 200 responses for valid updates and zero unexpected 500 errors.

---

## 5. Dead-Letter Replay Procedure

> [!CAUTION]
> **Never Replay from the Dead-Letter Document Itself:**
> Dead-letter records in `syncDeadLetters` intentionally exclude all clinical notes, symptoms, patient names, and free text to enforce zero-PII storage. Attempting to replay from the dead-letter payload would write incomplete records.

### Correct Replay Workflow:
1. **Identify the Entity**: Obtain the canonical `entityId` (`appointmentId`) from the dead-letter document key (`appointments_<appointmentId>_<reason>`).
2. **Read Directly from Source of Truth (SoR)**:
   - For patient cancellations / bookings: Query Supabase PostgreSQL:
     ```sql
     SELECT appointment_id, doctor_id, patient_id, doctor_status, patient_status, cancellation_reason, updated_at
     FROM public.appointments
     WHERE appointment_id = '<appointmentId>';
     ```
   - For doctor consultation outcomes: Query Firestore `appointments/<appointmentId>`.
3. **Resolve the Underlying Cause**:
   - If `firestore_doc_missing`: Verify if the appointment was created directly in Supabase without initial Firestore sync; run targeted single-document sync from Postgres row.
   - If `missing_required_fields`: Verify why required fields were omitted in the application client; patch the missing columns in Postgres before re-triggering.
4. **Issue Forward Update**: Trigger a clean forward update with `syncedBy: 'supabase_bridge'` to propagate the latest valid state without triggering recursion loops.
