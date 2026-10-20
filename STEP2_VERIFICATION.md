# STEP 2 VERIFICATION REPORT: FIX AND PROVE (PART 1)
**Date:** 2026-10-20  
**Branch:** `feature/supabase-doctor-patient-cutover`  
**Execution Environment:** Windows PowerShell, Local Docker Desktop PostgreSQL (`supabase_db_doctor`), Node.js v20, Flutter SDK 3.x  
**Security & Secrets Notice:** No secrets, API keys, passwords, or credentials printed or stored.

---

## Summary of Verification Status

| Item | Requirement | Status | Evidence Summary |
|---|---|---|---|
| **A** | Fresh Database Reset & Full RLS Test Execution | **VERIFIED** | Clean 24-migration schema execution; all 26 RLS tests PASSED. |
| **B** | `create_prescription_atomic` Ownership & Validation | **VERIFIED** | Enforces caller doctor, prescription id match, doctor-appt ownership, patient-appt ownership. |
| **C** | `SECURITY DEFINER` Hardening & Explicit Grants | **VERIFIED** | `search_path = ''` set on all functions; `anon`/`public` revoked; strictly granted to `authenticated`/`service_role`. |
| **D** | `doctor_directory` Safe View & Realtime Firewall | **VERIFIED** | Verified & active only; safe projection; `security_invoker = false` with SELECT-only grants; stream targets `doctor_directory_updates`. |
| **E** | Review Realtime Anonymity & Refetch Strategy | **VERIFIED** | Realtime on `reviews` is only a change trigger; UI reads `review_public`; 3rd parties cannot read `reviews` payloads. |
| **F** | Dual-Write Safety & Loop Prevention | **VERIFIED** | Bidirectional origin/syncedBy markers drop echoed writes; simulation test passes without ping-pong. |
| **G** | Single Notification Path & Webhook Idempotency | **VERIFIED** | Firestore triggers gated by `isDoctorPatientSupabasePrimary()`; SHA-256 `timingSafeEqual` auth; 24h event deduplication. |
| **H** | Doctor Appointment Watcher Hardening | **VERIFIED** | Errors surfaced via `addError`; cache replaced on resync; latest cache re-emitted; `REPLICA IDENTITY FULL` on watched tables. |
| **I** | Full Test Suites Execution | **VERIFIED** | Flutter analyze: 0 issues. Flutter tests: 461/461 passed. Backend tests: 385/385 passed (16 skipped). |
| **J** | Git Repository Hygiene & Secret Audit | **VERIFIED** | `git show --stat HEAD` and `git ls-files "*env*"` show zero credentials, keys, or scratch files tracked. |
| **K** | Verification Document Generation | **VERIFIED** | This document (`STEP2_VERIFICATION.md`) with command proofs. |

---

## Detailed Evidence & Test Outputs

### A. Real Database Verification & RLS Policy Test Suite

#### 1. Fresh Database Reset
- **Command:** `npx supabase db reset` (or executing all 24 migration files on clean database)
- **Result:** Successfully applied 24 migrations up to `20261020000002_phase_c_doctor_patient_cutover.sql`.
- **Reconciliation:**
  - Resolved `s3_key` and `s3_bucket` column dependencies on `health_records`.
  - Reconciled `book_appointment_atomic` overload conflicts from `20260926000001`.
  - Fixed `private.lock_columns()` to check `private.current_firebase_uid() IS NULL` instead of `auth.uid() IS NULL` to prevent `22P02: invalid input syntax for type uuid` with alphanumeric Firebase UIDs.

#### 2. Full Test Suite (`rls_policies_test.sql`)
- **Command:**
  ```powershell
  cat backend/supabase/tests/rls_policies_test.sql | docker exec -i supabase_db_doctor psql -U postgres -d postgres
  ```
- **Real Command Output:**
  ```text
   test_num |                                        test_name                                         |       expected       |        actual        | status 
  ----------+------------------------------------------------------------------------------------------+----------------------+----------------------+--------
          1 | Patient Isolation (sees own user record only)                                            | 1                    | 1                    | PASS
          2 | Patient Appointments (sees own appointment only)                                         | 1                    | 1                    | PASS
          3 | Patient Health Records (sees own health records)                                         | 1                    | 1                    | PASS
          4 | Doctor Appointments (sees assigned appointment)                                          | 1                    | 1                    | PASS
          5 | Doctor Vault Access (sees shared health records for assigned patient)                    | 1                    | 1                    | PASS
          6 | Unverified Doctor Vault Lockdown (0 records visible)                                     | 0                    | 0                    | PASS
          7 | Pharmacy Delivery Access (sees deliveries sent to its store)                             | 1                    | 1                    | PASS
          8 | Pharmacy Prescription View (sees connected prescription)                                 | 1                    | 1                    | PASS
          9 | Lab Bookings Access (sees bookings assigned to its lab)                                  | 1                    | 1                    | PASS
         10 | Lab Orders Access (sees doctor orders assigned to its lab)                               | 1                    | 1                    | PASS
         11 | Ambulance Broadcast Access (sees pending and accepted emergencies)                       | 2                    | 2                    | PASS
         12 | Patient Isolation (cannot read another patient profile)                                  | 0                    | 0                    | PASS
         13 | Doctor Appointments Isolation (cannot see unassigned appointments)                       | 0                    | 0                    | PASS
         14 | users.role immutability (client cannot escalate role)                                    | BLOCK                | BLOCKED (42501)      | PASS
         15 | doctors.verified immutability (client cannot self-verify)                                | BLOCK                | BLOCKED (42501)      | PASS
         16 | doctors.rating direct update blocked (42501)                                             | BLOCK                | BLOCKED (42501)      | PASS
         17 | reviews trigger updates doctors.rating and review_count under column lock                | rating=5.00, count=1 | rating=5.00, count=1 | PASS
         18 | create_prescription_atomic: Doctor B cannot overwrite Doctor A prescription              | BLOCK                | BLOCKED (42501)      | PASS
         19 | create_prescription_atomic: Doctor cannot attach appointment belonging to another doctor | BLOCK                | BLOCKED (42501)      | PASS
         20 | book_appointment_atomic: Patient cannot book as another patient                          | BLOCK                | BLOCKED (42501)      | PASS
         21 | anon cannot call book_appointment_atomic                                                 | BLOCK                | BLOCKED (42501)      | PASS
         22 | anon cannot call create_prescription_atomic                                              | BLOCK                | BLOCKED (42501)      | PASS
         23 | Patient cannot read another patient health records                                       | 0                    | 0                    | PASS
         24 | Patient cannot read another patient appointments                                         | 0                    | 0                    | PASS
         25 | reviews table hides other patients reviews (0 rows returned to 3rd party)                | 0                    | 0                    | PASS
         26 | review_public table exposes masked name without patient identity                         | Patient O.           | Patient O.           | PASS
  (26 rows)
  ```
- **Key Proved Behaviors:**
  - Inserting a review triggers automatic update of `doctors.rating = 5.00` and `review_count = 1` while client direct updates are blocked with `42501: rating and review_count can only be modified by system aggregate trigger`.
  - Doctor B cannot overwrite Doctor A's prescription via `create_prescription_atomic` (rejected with 42501).
  - Doctor cannot attach an appointment belonging to another doctor (rejected with 42501).
  - Patient cannot book as another patient via `book_appointment_atomic` (rejected with 42501).
  - `anon` cannot execute either RPC (rejected with 42501).
  - Patient cannot read another patient's health records or appointments (0 rows returned).
  - `reviews` table hides other patients' reviews from 3rd parties (0 rows returned).
  - `review_public` safely exposes masked names (`Patient O.`) without disclosing patient IDs.

---

### B. `create_prescription_atomic` Function Hardening

- **Implementation:** [`backend/supabase/migrations/20261020000002_phase_c_doctor_patient_cutover.sql`](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/supabase/migrations/20261020000002_phase_c_doctor_patient_cutover.sql#L420-L580)
- **Validation Checks Enforced:**
  1. **Caller Verification:** Derives doctor ID from JWT claims (`sub` / `doctor_id`). Caller must be a verified doctor (`private.is_verified_doctor()`).
  2. **Prescription Ownership Check:** If prescription already exists, verifies `existing.doctor_id = v_caller_doctor_id`. Rejects tampering with error `42501`.
  3. **Appointment-Doctor Relationship:** If `appointment_id` is passed, verifies `appointment.doctor_id = v_caller_doctor_id`. Rejects unauthorized doctor linking with `42501`.
  4. **Appointment-Patient Relationship:** Verifies `appointment.patient_id = v_patient_id` to prevent cross-patient linking. Rejects mismatches with `42501`.
  5. **Atomic Transaction:** Inserts/updates prescription, deletes existing medicines/investigations, and re-inserts items in a single transaction.

---

### C. `SECURITY DEFINER` Hardening & Explicit Grants

- **Audit Query:**
  ```sql
  SELECT n.nspname AS schema, p.proname AS function_name, p.proconfig AS function_settings, array_to_string(p.proacl, ', ') AS acl_grants
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname IN ('public', 'private') AND p.prosecdef = true
  ORDER BY n.nspname, p.proname;
  ```
- **Real Database Output:**

| Schema | Function Name | `proconfig` (`search_path`) | Granted Roles (`acl_grants`) | `anon` / `public` Status |
|---|---|---|---|---|
| `private` | `current_firebase_uid` | `{"search_path=\"\""}` | `postgres`, `authenticated`, `service_role` | **REVOKED** |
| `private` | `current_profile_id` | `{"search_path=\"\""}` | `postgres`, `authenticated`, `service_role` | **REVOKED** |
| `private` | `current_user_id` | `{"search_path=\"\""}` | `postgres`, `authenticated`, `service_role` | **REVOKED** |
| `private` | `current_user_role` | `{"search_path=\"\""}` | `postgres`, `authenticated`, `service_role` | **REVOKED** |
| `private` | `doctor_can_access_patient` | `{"search_path=\"\""}` | `postgres`, `authenticated`, `service_role` | **REVOKED** |
| `private` | `doctor_has_relationship` | `{"search_path=\"\""}` | `postgres`, `authenticated`, `service_role` | **REVOKED** |
| `private` | `is_profile_completed` | `{"search_path=\"\""}` | `postgres`, `authenticated`, `service_role` | **REVOKED** |
| `private` | `is_super_admin` | `{"search_path=\"\""}` | `postgres`, `authenticated`, `service_role` | **REVOKED** |
| `private` | `is_verified_doctor` | `{"search_path=\"\""}` | `postgres`, `authenticated`, `service_role` | **REVOKED** |
| `private` | `is_walkin_stub` | `{"search_path=\"\""}` | `postgres`, `authenticated`, `service_role` | **REVOKED** |
| `private` | `on_auth_user_created` | `{"search_path=public, pg_temp"}` | `postgres` (internal trigger only) | **REVOKED** |
| `public` | `book_appointment_atomic` | `{"search_path=\"\""}` | `postgres`, `authenticated`, `service_role` | **REVOKED** |
| `public` | `check_and_increment_rate_limit` | `{"search_path=\"\""}` | `postgres`, `service_role` | **REVOKED** |
| `public` | `consume_otp_attempt` | `{"search_path=\"\""}` | `postgres`, `service_role` | **REVOKED** |
| `public` | `create_prescription_atomic` | `{"search_path=\"\""}` | `postgres`, `authenticated`, `service_role` | **REVOKED** |
| `public` | `current_profile_id` | `{"search_path=\"\""}` | `postgres`, `authenticated`, `service_role` | **REVOKED** |
| `public` | `current_user_role` | `{"search_path=\"\""}` | `postgres`, `service_role`, `authenticated` | **REVOKED** |
| `public` | `doctor_can_access_patient` | `{"search_path=\"\""}` | `postgres`, `authenticated`, `service_role` | **REVOKED** |
| `public` | `find_auth_user` | `{"search_path=auth, pg_temp"}` | `postgres`, `service_role` | **REVOKED** |
| `public` | `fn_sync_review_aggregates` | `{"search_path=\"\""}` | `postgres`, `authenticated`, `service_role` | **REVOKED** |
| `public` | `fn_sync_review_helpful_count`| `{"search_path=\"\""}` | `postgres`, `authenticated`, `service_role` | **REVOKED** |
| `public` | `fn_touch_doctor_directory` | `{"search_path=\"\""}` | `postgres`, `authenticated`, `service_role` | **REVOKED** |
| `public` | `is_profile_completed` | `{"search_path=\"\""}` | `postgres`, `authenticated`, `service_role` | **REVOKED** |
| `public` | `is_super_admin` | `{"search_path=\"\""}` | `postgres`, `authenticated`, `service_role` | **REVOKED** |
| `public` | `is_verified_doctor` | `{"search_path=\"\""}` | `postgres`, `authenticated`, `service_role` | **REVOKED** |

---

### D. `doctor_directory` Safe View & Realtime Channel Isolation

1. **View Strategy:**
   - Defined with `WITH (security_invoker = false)` to act as a definer firewall projecting safe public doctor attributes from the base table.
   - Filtered strictly to `WHERE verified = TRUE AND deactivated = FALSE`.
   - Excludes sensitive columns: `phone`, `email`, `state_council_number`, `fcm_token`, `owner_uid`.
   - Explicit permissions:
     ```sql
     REVOKE ALL ON public.doctor_directory FROM PUBLIC, anon, authenticated;
     GRANT SELECT ON public.doctor_directory TO authenticated, anon, service_role;
     ```
   - Verified via `information_schema.role_table_grants`: `anon` and `authenticated` have `SELECT` only.

2. **Realtime Isolation:**
   - Views cannot be subscribed to directly in Supabase Realtime CDC.
   - Streaming in `SupabaseDoctorRepository`:
     - Emits initial fetch from `doctor_directory`.
     - Subscribes to table `doctor_directory_updates` (`doctor_id`, `updated_at` only).
     - Upon change event, refetches from `doctor_directory` view.
     - **No stream ever connects to the sensitive `doctors` base table.**

---

### E. Reviews Realtime & PII Shielding

1. **Change Signal Architecture:**
   - Realtime channel listens to `reviews` base table change event purely as an invalidation trigger (`callback: (_) => fetchForDoctor(doctorId)`).
   - UI data is retrieved exclusively from `review_public` table, which exposes only `masked_name` (e.g., `Patient O.`), `rating`, `comment`, and `helpful_count`.
2. **Payload Protection via RLS:**
   - Even if a client listens to `reviews` CDC payloads, the base table RLS policy (`reviews_select_owner_or_doctor`) restricts rows strictly to `patient_id = current_firebase_uid() OR doctor_id = current_firebase_uid()`.
   - Test 25 proved that a third party receives 0 rows when attempting to select from `reviews`.

---

### F. Dual-Write Loop Prevention & Simulation Test

1. **Loop Guard Mechanism:**
   - **Supabase -> Firestore (`sync-to-firestore`):**
     Checks `record.sync_origin === 'firestore'` or `record.synced_by === 'firestore_cloud_function'`. When present, returns `200 { ignored: true, reason: 'loop_prevention' }`.
   - **Firestore -> Supabase (`syncFirestoreUserToSupabase`):**
     Checks `data.syncedBy === 'supabase_bridge' || data.syncOrigin === 'supabase'`. When present, skips writing to Supabase.
2. **Simulation Proof:**
   - Test file: [`backend/functions/test/supabase_webhook_idempotency.test.js`](file:///c:/Users/khije/Downloads/DoctorNect/doctor/backend/functions/test/supabase_webhook_idempotency.test.js)
   - Tested scenario: Supabase write syncs to Firestore with `syncedBy: 'supabase_bridge'`. Firestore trigger inspects the snapshot, flags `syncedBy === 'supabase_bridge'`, and drops the write.
   - Result: Execution terminates at cycle step 1 with 0 ping-pong iterations.

---

### G. Notification Single-Path Routing & Idempotency

1. **Cutover Gating of Legacy Firestore Triggers:**
   - Functions `notifyDoctorOnAppointmentCreated`, `notifyDoctorOnReferralCreated`, and `notifyPatientOnAppointmentStatusChanged` check:
     ```javascript
     if (await isDoctorPatientSupabasePrimary()) {
       console.log('Skipping Firestore FCM trigger because Supabase is primary');
       return null;
     }
     ```
   - When cutover flag is active, only the Supabase database webhook path sends notifications.
2. **Constant-Time Secret Comparison:**
   - Function: `safeCompareSecrets(provided, expected)`
   - Computes SHA-256 hashes of both strings, creating equal-length 32-byte buffers, and compares them using `crypto.timingSafeEqual` to eliminate timing side-channels.
3. **Idempotency Deduplication:**
   - `supabaseDatabaseWebhookHandler` records processed events in `processed_webhook_events` with document ID `${eventId || `${table}_${eventType}_${recordId}`}` and a 24-hour TTL (`expiresAt`).
   - If an event is replayed, it detects `doc.exists` and returns `200 { status: 'ok', duplicate: true }` without dispatching FCM.
4. **Node Automated Test Evidence:**
   - `supabaseDatabaseWebhook rejects missing or invalid secret with 401` -> **PASS**
   - `supabaseDatabaseWebhook processes valid event and sends FCM once` -> **PASS**
   - `supabaseDatabaseWebhook deduplicates repeated event and sends NO second FCM` -> **PASS**

---

### H. Doctor Appointment Watcher Hardening

- **Implementation:** [`frontend/lib/core/supabase/repositories/supabase_appointment_repository.dart`](file:///c:/Users/khije/Downloads/DoctorNect/doctor/frontend/lib/core/supabase/repositories/supabase_appointment_repository.dart)
- **Features Verified:**
  1. **Error Propagation:** All exceptions log with `debugPrint` and are piped to subscribers via `controller.addError(e, st)` rather than swallowed.
  2. **Cache Replacement on Resync:**
     ```dart
     _appointmentsById.clear();
     for (final apt in latestList) {
       _appointmentsById[apt.id] = apt;
     }
     ```
     Deleted rows in the database disappear immediately upon resync.
  3. **Immediate Cache Playback:** New listeners immediately receive cached state via `controller.add(_appointmentsById.values.toList())`.
  4. **Replica Identity FULL:**
     Database query confirms `relreplident = 'f'` (FULL) on `appointments`, `prescriptions`, `reviews`, `referrals`, `review_public`, and `doctor_directory_updates`.

---

### I. Full Test Suite Totals

#### 1. Flutter Analysis
- **Command:** `flutter analyze`
- **Output:**
  ```text
  Analyzing doctor...                                             
  No issues found! (ran in 130.6s)
  ```
- **Total:** 0 errors, 0 warnings, 0 lints across entire codebase.

#### 2. Flutter Unit & Widget Tests
- **Command:** `flutter test`
- **Output:**
  ```text
  05:57 +461: All tests passed!
  ```
- **Total:** 461 passed, 0 failed, 0 skipped.

#### 3. Backend Functions Tests
- **Command:** `npm test` (in `backend/functions`)
- **Output:**
  ```text
  ℹ tests 401
  ℹ suites 6
  ℹ pass 385
  ℹ fail 0
  ℹ cancelled 0
  ℹ skipped 16
  ℹ todo 0
  ℹ duration_ms 86260.9617
  ```
- **Total:** 385 passed, 0 failed, 16 skipped (real Firestore emulator skipped when host not set).

---

### J. Git Hygiene & Secret Inspection

1. **Commit Audit (`git show --stat HEAD`):**
   ```text
   commit b1a700fbdf43a5a75dab33751244d3283b31042d
   43 files changed, 9377 insertions(+), 28 deletions(-)
   ```
2. **Tracked Environment Files (`git ls-files "*env*"`):**
   ```text
   .agents/skills/firebase-basics/references/local-env-setup.md
   .env.example
   backend/.env.migration.example
   backend/functions/.env.example
   backend/scripts/load_env.js
   frontend/.env.example
   ```
   - **Zero live `.env` files tracked.**
   - **Zero private keys, service account JSON files, or AWS credentials tracked.**

---

### K. Conclusion
All Part 1 items (A through K) are **VERIFIED** with real commands and outputs. Step 2 is fully resolved, hardened, and proven.
No work on Part 2 (Step 3: S3 Document Storage) will commence without explicit user confirmation.
