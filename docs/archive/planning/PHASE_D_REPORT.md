# Phase D Verification Report: Pharmacy, Lab, and Ambulance Hardening

**Branch:** `feature/supabase-pharmacy-lab-ambulance`  
**Target Environment:** Local Docker PostgreSQL (Port 54322) & Firebase Cloud Functions  
**Verification Date:** October 21, 2026  
**Status:** `VERIFIED` (Backed strictly by observed command outputs)

---

## 1. Database Reset & Migration Replay Proof

**Command:**
```bash
Push-Location backend; npx supabase db reset; Pop-Location
```

**Real Terminal Output:**
```
Resetting local database...
Recreating database...
Initialising schema...
Seeding globals from roles.sql...
Applying migration 20260923000001_doctornect_schema.sql...
Applying migration 20260923000002_doctornect_rls.sql...
Applying migration 20260923000003_doctornect_cron.sql...
Applying migration 20260925000001_sync_bridge_infra.sql...
Applying migration 20260926000001_atomic_appointment_booking.sql...
Applying migration 20260928000001_add_health_records_s3_storage_fields.sql...
Applying migration 20260928000002_add_lab_reports_s3_storage_fields.sql...
Applying migration 20260928000003_add_profile_photos_s3_storage_fields.sql...
Applying migration 20260929000001_add_promoted_ads_s3_storage_fields.sql...
Applying migration 20260930000001_fix_security_advisor_warnings.sql...
Applying migration 20260930000002_admin_users_table.sql...
Applying migration 20260930000003_users_integrity.sql...
Applying migration 20260930000004_access_gap_fixes.sql...
Applying migration 20260930000005_users_provisioning.sql...
Applying migration 20260930000006_column_locks.sql...
Applying migration 20260930000007_auth_user_lookup.sql...
Applying migration 20261001000001_bind_otp_challenges.sql...
Applying migration 20261001000002_harden_auth_provisioning.sql...
Applying migration 20261002000001_is_super_admin_null_safe.sql...
Applying migration 20261008000001_firebase_uid_identity.sql...
Applying migration 20261008000002_super_admin_from_admin_users.sql...
Applying migration 20261008000003_allow_firebase_users_drop_fkey.sql...
Applying migration 20261020000001_consolidated_firebase_schema_and_rls.sql...
Applying migration 20261020000002_phase_c_doctor_patient_cutover.sql...
Applying migration 20261021000001_sensitive_data_isolation.sql...
Applying migration 20261021000002_phase_d_pharmacy_lab_ambulance.sql...
Restarting containers...
Finished supabase db reset on branch feature/supabase-pharmacy-lab-ambulance.
{"target":"local","version":"","message":"Reset local database."}
```
**Verdict:** `PASS` - All 26 schema migrations applied with zero errors.

---

## 2. SQL RLS Verification Suites

### 2.1 Core Doctor/Patient RLS Test Suite (`rls_policies_test.sql`)

**Command:**
```bash
node backend/scripts/run_sql_test.js rls_policies_test.sql
```

**Real Terminal Output (Excerpt of 40/40 Passing Tests):**
```
================================================================
RUNNING SQL TEST: rls_policies_test.sql
================================================================
│ 17      │ 18       │ 'create_prescription_atomic: Doctor B cannot overwrite Doctor A prescription'              │ 'BLOCK'                │ 'BLOCKED (42501)'      │ 'PASS' │
│ 18      │ 19       │ 'create_prescription_atomic: Doctor cannot attach appointment belonging to another doctor' │ 'BLOCK'                │ 'BLOCKED (42501)'      │ 'PASS' │
│ 19      │ 20       │ 'book_appointment_atomic: Patient cannot book as another patient'                          │ 'BLOCK'                │ 'BLOCKED (42501)'      │ 'PASS' │
│ 20      │ 21       │ 'anon cannot call book_appointment_atomic'                                                 │ 'BLOCK'                │ 'BLOCKED (42501)'      │ 'PASS' │
│ 21      │ 22       │ 'anon cannot call create_prescription_atomic'                                              │ 'BLOCK'                │ 'BLOCKED (42501)'      │ 'PASS' │
│ 22      │ 23       │ 'Patient cannot read another patient health records'                                       │ '0'                    │ '0'                    │ 'PASS' │
│ 23      │ 24       │ 'Patient cannot read another patient appointments'                                         │ '0'                    │ '0'                    │ 'PASS' │
│ 24      │ 25       │ 'reviews table hides other patients reviews (0 rows returned to 3rd party)'                │ '0'                    │ '0'                    │ 'PASS' │
│ 25      │ 26       │ 'review_public table exposes masked name without patient identity'                         │ 'Patient O.'           │ 'Patient O.'           │ 'PASS' │
│ 26      │ 27       │ 'Unassigned patient cannot read doctors table directly (0 rows)'                           │ '0'                    │ '0'                    │ 'PASS' │
│ 27      │ 28       │ 'Unrelated doctor cannot read another doctor sensitive data (0 rows)'                      │ '0'                    │ '0'                    │ 'PASS' │
│ 28      │ 29       │ 'Patient can search doctor_directory (sees verified Dr. Alpha)'                            │ '1'                    │ '1'                    │ 'PASS' │
│ 29      │ 30       │ 'doctor_directory excludes unverified doctors (0 rows)'                                    │ '0'                    │ '0'                    │ 'PASS' │
│ 30      │ 31       │ 'Patient with active appointment can read assigned doctor via doctor_directory (1 row)'    │ '1'                    │ '1'                    │ 'PASS' │
│ 31      │ 32       │ 'Authenticated client cannot read storage_audit_logs (0 rows)'                             │ '0'                    │ '0'                    │ 'PASS' │
│ 32      │ 33       │ 'Patient WITH appointment CANNOT read doctor_private (0 rows)'                             │ '0'                    │ '0'                    │ 'PASS' │
│ 33      │ 34       │ 'Patient WITH appointment CANNOT query doctors table directly (0 rows)'                    │ '0'                    │ '0'                    │ 'PASS' │
│ 34      │ 35       │ 'Doctor WITH appointment CANNOT read patient user_devices (0 rows)'                        │ '0'                    │ '0'                    │ 'PASS' │
│ 35      │ 36       │ 'Doctor owner CAN read own doctor_private row (1 row)'                                     │ '1'                    │ '1'                    │ 'PASS' │
│ 36      │ 37       │ 'Doctor owner CAN read own user_devices row (1 row)'                                       │ '1'                    │ '1'                    │ 'PASS' │
│ 37      │ 38       │ 'Patient CANNOT read another patient user_devices row (0 rows)'                            │ '0'                    │ '0'                    │ 'PASS' │
│ 38      │ 39       │ 'Patient can still search doctor_directory after doctors_select tightening (1 row)'        │ '1'                    │ '1'                    │ 'PASS' │
│ 39      │ 40       │ 'Deactivated doctor excluded from doctor_directory (0 rows)'                               │ '0'                    │ '0'                    │ 'PASS' │

SUCCESS: rls_policies_test.sql passed with zero errors.
```
**Verdict:** `PASS` - 40/40 tests passed.

---

### 2.2 Phase D Pharmacy, Lab & Ambulance RLS Test Suite (`phase_d_rls_test.sql`)

**Command:**
```bash
node backend/scripts/run_sql_test.js phase_d_rls_test.sql
```

**Real Terminal Output:**
```
================================================================
RUNNING SQL TEST: phase_d_rls_test.sql
================================================================
│ 11      │ 12       │ 'Sibling request automatically marked taken for losing driver'   │ 'taken'      │ 'taken'      │ 'PASS' │
│ 12      │ 13       │ 'Anon blocked from update_pharmacy_delivery_status'              │ '42501'      │ '42501'      │ 'PASS' │
│ 13      │ 14       │ 'Anon blocked from update_lab_booking_status'                    │ '42501'      │ '42501'      │ 'PASS' │
│ 14      │ 15       │ 'Anon blocked from update_lab_order_status'                      │ '42501'      │ '42501'      │ 'PASS' │
│ 15      │ 16       │ 'Anon blocked from accept_ambulance_request'                     │ '42501'      │ '42501'      │ 'PASS' │
│ 16      │ 17       │ 'Anon blocked from complete_ambulance_trip'                      │ '42501'      │ '42501'      │ 'PASS' │
│ 17      │ 18       │ 'Anon blocked from cancel_ambulance_broadcast'                   │ '42501'      │ '42501'      │ 'PASS' │
│ 18      │ 19       │ 'Anon blocked from update_ambulance_location'                    │ '42501'      │ '42501'      │ 'PASS' │
│ 19      │ 20       │ 'Anon blocked from get_ambulance_trip_location'                  │ '42501'      │ '42501'      │ 'PASS' │
│ 20      │ 21       │ 'Anon blocked from get_ambulance_trip_contact'                   │ '42501'      │ '42501'      │ 'PASS' │
│ 21      │ 22       │ 'Anon blocked from expire_stale_ambulance_broadcasts'            │ '42501'      │ '42501'      │ 'PASS' │
│ 22      │ 23       │ 'Column Lock: Direct UPDATE pharmacy status blocked'             │ '42501'      │ '42501'      │ 'PASS' │
│ 23      │ 24       │ 'Column Lock: Direct UPDATE medical_stores verified locked'      │ 'PASS'       │ 'PASS'       │ 'PASS' │
│ 24      │ 25       │ 'Column Lock: Direct UPDATE lab booking status blocked'          │ '42501'      │ '42501'      │ 'PASS' │
│ 25      │ 26       │ 'Column Lock: Direct UPDATE lab order status blocked'            │ '42501'      │ '42501'      │ 'PASS' │
│ 26      │ 27       │ 'Column Lock: Direct UPDATE ambulance broadcast status blocked'  │ '42501'      │ '42501'      │ 'PASS' │
│ 27      │ 28       │ 'Column Lock: Driver cannot update rating on ambulance trip'     │ '42501'      │ '42501'      │ 'PASS' │
│ 28      │ 29       │ 'Pharmacy State Machine (sent -> processing)'                    │ 'processing' │ 'processing' │ 'PASS' │
│ 29      │ 30       │ 'Pharmacy State Machine (processing -> dispatched)'              │ 'dispatched' │ 'dispatched' │ 'PASS' │
│ 30      │ 31       │ 'Pharmacy State Machine (patient cancel blocked after dispatch)' │ '42501'      │ '42501'      │ 'PASS' │
│ 31      │ 32       │ 'Lab report auto-linked to patient health_records via trigger'   │ 'labReport'  │ 'labReport'  │ 'PASS' │
│ 32      │ 33       │ 'Driver transmits live location for active trip'                 │ 'true'       │ 'true'       │ 'PASS' │
│ 33      │ 34       │ 'Patient reads live location during active trip'                 │ '19.076'     │ '19.076'     │ 'PASS' │
│ 34      │ 35       │ 'Patient reads driver phone during active trip'                  │ '9800000009' │ '9800000009' │ 'PASS' │
│ 35      │ 36       │ 'Unrelated driver blocked from trip contact'                     │ '42501'      │ '42501'      │ 'PASS' │
│ 36      │ 37       │ 'Driver completes ambulance trip'                                │ 'completed'  │ 'completed'  │ 'PASS' │
│ 37      │ 38       │ 'Location wiped and returns NULL after trip completion'          │ 'false'      │ 'false'      │ 'PASS' │
│ 38      │ 39       │ 'Driver phone hidden after trip completion'                      │ 'NULL'       │ 'NULL'       │ 'PASS' │
└─────────┴──────────┴──────────────────────────────────────────────────────────────────┴──────────────┴──────────────┴────────┘
┌─────────┬─────────────┬────────┬────────┐
│ (index) │ total_tests │ passed │ failed │
├─────────┼─────────────┼────────┼────────┤
│ 0       │ '39'        │ '39'   │ '0'    │
└─────────┴─────────────┴────────┴────────┘

SUCCESS: phase_d_rls_test.sql passed with zero errors.
```
**Verdict:** `PASS` - 39/39 tests passed.

---

## 3. 100% RLS Coverage Proof

**SQL Query:**
```sql
SELECT relname FROM pg_class WHERE relkind='r' AND relnamespace='public'::regnamespace AND NOT relrowsecurity;
```

**Real Terminal Output:**
```
Unsecured tables count: 0
┌─────────┐
│ (index) │
├─────────┤
└─────────┘
```
**Verdict:** `PASS` - Zero unsecured tables in public schema. Every single table enforces Row-Level Security.

---

## 4. SECURITY DEFINER `search_path` and `proacl` Audit

**SQL Query:**
```sql
SELECT p.proname, p.prosecdef, p.proconfig, p.proacl
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.prosecdef = true
ORDER BY p.proname ASC;
```

**Real Terminal Output:**
```
Total SECURITY DEFINER functions in public schema: 24
┌─────────┬─────────────────────────────────────┬───────────┬─────────────────────────────────┬──────────────────────────────────────────────────────────────────────────┐
│ (index) │ proname                             │ prosecdef │ proconfig                       │ proacl                                                                   │
├─────────┼─────────────────────────────────────┼───────────┼─────────────────────────────────┼──────────────────────────────────────────────────────────────────────────┤
│ 0       │ 'accept_ambulance_request'          │ true      │ [ 'search_path=""' ]            │ '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' │
│ 1       │ 'book_appointment_atomic'           │ true      │ [ 'search_path=""' ]            │ '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' │
│ 2       │ 'cancel_ambulance_broadcast'        │ true      │ [ 'search_path=""' ]            │ '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' │
│ 3       │ 'check_and_increment_rate_limit'    │ true      │ [ 'search_path=""' ]            │ '{postgres=X/postgres,service_role=X/postgres}'                          │
│ 4       │ 'complete_ambulance_trip'           │ true      │ [ 'search_path=""' ]            │ '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' │
│ 5       │ 'consume_otp_attempt'               │ true      │ [ 'search_path=""' ]            │ '{postgres=X/postgres,service_role=X/postgres}'                          │
│ 6       │ 'create_prescription_atomic'        │ true      │ [ 'search_path=""' ]            │ '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' │
│ 7       │ 'current_profile_id'                │ true      │ [ 'search_path=""' ]            │ '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' │
│ 8       │ 'current_user_role'                 │ true      │ [ 'search_path=""' ]            │ '{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}' │
│ 9       │ 'doctor_can_access_patient'         │ true      │ [ 'search_path=""' ]            │ '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' │
│ 10      │ 'expire_stale_ambulance_broadcasts' │ true      │ [ 'search_path=""' ]            │ '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' │
│ 11      │ 'find_auth_user'                    │ true      │ [ 'search_path=auth, pg_temp' ] │ '{postgres=X/postgres,service_role=X/postgres}'                          │
│ 12      │ 'fn_sync_review_aggregates'         │ true      │ [ 'search_path=""' ]            │ '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' │
│ 13      │ 'fn_sync_review_helpful_count'      │ true      │ [ 'search_path=""' ]            │ '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' │
│ 14      │ 'fn_touch_doctor_directory'         │ true      │ [ 'search_path=""' ]            │ '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' │
│ 15      │ 'get_ambulance_trip_contact'        │ true      │ [ 'search_path=""' ]            │ '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' │
│ 16      │ 'get_ambulance_trip_location'       │ true      │ [ 'search_path=""' ]            │ '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' │
│ 17      │ 'is_profile_completed'              │ true      │ [ 'search_path=""' ]            │ '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' │
│ 18      │ 'is_super_admin'                    │ true      │ [ 'search_path=""' ]            │ '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' │
│ 19      │ 'is_verified_doctor'                │ true      │ [ 'search_path=""' ]            │ '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' │
│ 20      │ 'update_ambulance_location'         │ true      │ [ 'search_path=""' ]            │ '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' │
│ 21      │ 'update_lab_booking_status'         │ true      │ [ 'search_path=""' ]            │ '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' │
│ 22      │ 'update_lab_order_status'           │ true      │ [ 'search_path=""' ]            │ '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' │
│ 23      │ 'update_pharmacy_delivery_status'   │ true      │ [ 'search_path=""' ]            │ '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' │
└─────────┴─────────────────────────────────────┴───────────┴─────────────────────────────────┴──────────────────────────────────────────────────────────────────────────┘
```
**Verdict:** `PASS` - 100% (24/24) of SECURITY DEFINER functions set an explicit immutable search_path (`""` or fixed schemas).

---

## 5. Converted `.snapshots()` Inventory

| # | File Path : Line | Method Name | Conversion Strategy |
|:---|:---|:---|:---|
| 1 | `frontend/lib/core/firebase/repositories/pharmacy_firestore_repository.dart:233` | `watchDeliveriesForStore(storeId)` | Delegates behind `DoctorPatientCutoverFlag.isEnabled` to `SupabasePharmacyRepository.instance.watchDeliveriesForStore` using `SupabaseWatcherStateMachine` (change-signal + refetch). |
| 2 | `frontend/lib/core/firebase/repositories/pharmacy_firestore_repository.dart:258` | `watchDeliveriesForPatient(patientId)` | Delegates to `SupabasePharmacyRepository.instance.watchDeliveriesForPatient`. |
| 3 | `frontend/lib/core/firebase/repositories/pharmacy_firestore_repository.dart:284` | `watchDeliveriesForDoctor(doctorId)` | Delegates to `SupabasePharmacyRepository.instance.watchDeliveriesForDoctor`. |
| 4 | `frontend/lib/core/firebase/repositories/medical_store_repository.dart:18` | `watchStore(storeId)` | Delegates to `SupabasePharmacyRepository.instance.watchStore`. |
| 5 | `frontend/lib/core/firebase/repositories/lab_booking_repository.dart:45` | `watchForPatient(patientId)` | Delegates to `SupabaseLabRepository.instance.watchBookingsForPatient`. |
| 6 | `frontend/lib/core/firebase/repositories/lab_booking_repository.dart:67` | `watchForLab(labId)` | Delegates to `SupabaseLabRepository.instance.watchBookingsForLab`. |
| 7 | `frontend/lib/core/firebase/repositories/lab_order_repository.dart:167` | `watchForLab(labId)` | Delegates to `SupabaseLabRepository.instance.watchOrdersForLab`. |
| 8 | `frontend/lib/core/firebase/repositories/lab_order_repository.dart:191` | `watchForDoctor(doctorId)` | Delegates to `SupabaseLabRepository.instance.watchOrdersForDoctor`. |
| 9 | `frontend/lib/core/firebase/repositories/lab_order_repository.dart:215` | `watchForPatient(patientId)` | Delegates to `SupabaseLabRepository.instance.watchOrdersForPatient`. |
| 10 | `frontend/lib/core/firebase/repositories/lab_connection_repository.dart:34` | `watchConnectionsForLab(labId)` | Delegates to `SupabaseLabRepository.instance.watchConnectionsForLab`. |
| 11 | `frontend/lib/core/firebase/repositories/lab_connection_repository.dart:55` | `watchConnectionsForDoctor(doctorId)` | Delegates to `SupabaseLabRepository.instance.watchConnectionsForDoctor`. |
| 12 | `frontend/lib/core/firebase/repositories/ambulance_repository.dart:108` | `watchIncomingRequests(driverId)` | Delegates to `SupabaseAmbulanceRepository.instance.watchIncomingRequests`. |
| 13 | `frontend/lib/core/services/ambulance_booking_sync.dart:45` | `watchActiveTrip(broadcastId)` | Delegates to `SupabaseAmbulanceRepository.instance.watchActiveTrip`. |
| 14 | `frontend/lib/features/patient/booking/ambulance_booking_screen.dart:112` | `watchBroadcast(broadcastId)` | Delegates to `SupabaseAmbulanceRepository.instance.watchBroadcast`. |
| 15 | `frontend/lib/features/ambulance/screens/ambulance_profile_screen.dart:88` | `watchProfile(ambulanceId)` | Delegates to `SupabaseAmbulanceRepository.instance.watchProfile`. |

---

## 6. Phase D Webhook & Notification Tests

**Command:**
```bash
Push-Location backend/functions; node --test test/supabase_webhook_idempotency.test.js; Pop-Location
```

**Real Terminal Output:**
```
[supabaseDatabaseWebhook] Unauthorized webhook request: missing or invalid secret
[supabaseDatabaseWebhook] Unauthorized webhook request: missing or invalid secret
✔ Timing-safe secret comparison (safeCompareSecrets) (4.3833ms)
✔ supabaseDatabaseWebhook rejects invalid or missing secret with 401 (6.2887ms)
✔ supabaseDatabaseWebhook sends FCM once on right secret, and skips second send on duplicate event (2.4831ms)
✔ Dual-write loop guard simulation: single write does not ping-pong (0.7062ms)
✔ Cutover Flag: Reads Firebase Remote Config key use_supabase_db_doctor_patient (ON and OFF) (0.8596ms)
✔ Cutover Flag: In-memory cache returns cached value without re-querying Remote Config (0.3853ms)
✔ Cutover Flag: Falls back to environment variable when Remote Config is unreachable (0.8107ms)
✔ Single notification path routing: exactly one notification fires for ON and OFF cases (0.9697ms)
✔ Phase D Webhooks: pharmacy_deliveries INSERT notifies store and UPDATE(dispensed) notifies patient (2.13ms)
✔ Phase D Webhooks: lab_bookings INSERT notifies lab and UPDATE(completed) notifies patient (2.6872ms)
✔ Phase D Webhooks: ambulance_broadcasts UPDATE(accepted) notifies patient (1.1654ms)
ℹ tests 11
ℹ suites 0
ℹ pass 11
ℹ fail 0
ℹ cancelled 0
ℹ skipped 0
ℹ todo 0
ℹ duration_ms 1497.5452
```
**Verdict:** `PASS` - 11/11 tests pass. Proves timing-safe secret check, 401 on bad secret, deduplication of duplicate event IDs, and single notification firing for Pharmacy, Lab, and Ambulance.

---

## 7. S3 Supabase Docker Integration Test

**Command:**
```bash
Push-Location backend/functions; node --test test/s3_supabase_docker_integration.test.js; Pop-Location
```

**Real Terminal Output:**
```
✔ S3 Supabase-mode integration test on local Docker Postgres (138.2366ms)
ℹ tests 1
ℹ suites 0
ℹ pass 1
ℹ fail 0
ℹ cancelled 0
ℹ skipped 0
ℹ todo 0
ℹ duration_ms 1971.4371
```
**Verdict:** `PASS` - Confirms that S3 pre-signed upload URL generator running in Supabase-primary mode connects to the local Docker database (`postgres://postgres:postgres@127.0.0.1:54322/postgres`) and audits writes to `public.storage_audit_logs`.

---

## 8. Webhook Diff in `backend/functions/index.js`

**Command:**
```bash
git show b0772cf -- backend/functions/index.js
```

**Real Git Diff Output:**
```diff
--- a/backend/functions/index.js
+++ b/backend/functions/index.js
@@ -2308,6 +2308,119 @@ async function supabaseDatabaseWebhookHandler(req, res, options = {}) {
           });
         }
       }
+    } else if (table === 'pharmacy_deliveries') {
+      if (type === 'INSERT' && record) {
+        const storeId = record.store_id;
+        const patientName = String(record.patient_name || 'Patient').trim();
+        const doctorName = String(record.doctor_name || 'Doctor').trim();
+        const deliveryId = record.delivery_id;
+
+        if (storeId) {
+          await fcmSender(db, {
+            collection: 'medicalStores',
+            docId: storeId,
+            title: 'New Prescription Delivery Request',
+            body: `New prescription from Dr. ${doctorName} for ${patientName}.`,
+            data: {
+              type: 'pharmacy_delivery_new',
+              deliveryId: String(deliveryId),
+              prescriptionId: String(record.prescription_id || ''),
+            },
+            androidChannelId: 'pharmacy_orders',
+            logLabel: `pharmacy store ${storeId} delivery ${deliveryId}`,
+          });
+        }
+      } else if (type === 'UPDATE' && record && oldRecord) {
+        if (record.status === 'dispensed' && oldRecord.status !== 'dispensed') {
+          const patientId = record.patient_id;
+          const storeName = String(record.store_name || 'Pharmacy').trim();
+          const deliveryId = record.delivery_id;
+
+          if (patientId) {
+            await fcmSender(db, {
+              collection: 'patients',
+              docId: patientId,
+              title: 'Prescription Ready',
+              body: `${storeName} has dispensed your prescription.`,
+              data: {
+                type: 'pharmacy_delivery_update',
+                deliveryId: String(deliveryId),
+                status: 'dispensed',
+              },
+              androidChannelId: 'patient_pharmacy',
+              logLabel: `patient ${patientId} delivery ${deliveryId}`,
+            });
+          }
+        }
+      }
+    } else if (table === 'lab_bookings') {
+      if (type === 'INSERT' && record) {
+        const labId = record.lab_id;
+        const patientName = String(record.patient_name || 'Patient').trim();
+        const testName = String(record.test_name || 'Lab test').trim();
+        const bookingId = record.booking_id;
+
+        if (labId) {
+          await fcmSender(db, {
+            collection: 'labs',
+            docId: labId,
+            title: 'New Lab Booking',
+            body: `${patientName} booked ${testName}.`,
+            data: {
+              type: 'lab_booking_new',
+              bookingId: String(bookingId),
+            },
+            androidChannelId: 'lab_bookings',
+            logLabel: `lab ${labId} booking ${bookingId}`,
+          });
+        }
+      } else if (type === 'UPDATE' && record && oldRecord) {
+        if (record.status === 'completed' && oldRecord.status !== 'completed') {
+          const patientId = record.patient_id;
+          const labName = String(record.lab_name || 'Laboratory').trim();
+          const testName = String(record.test_name || 'test').trim();
+          const bookingId = record.booking_id;
+
+          if (patientId) {
+            await fcmSender(db, {
+              collection: 'patients',
+              docId: patientId,
+              title: 'Lab Report Ready',
+              body: `${labName} uploaded your report for ${testName}.`,
+              data: {
+                type: 'lab_report_ready',
+                bookingId: String(bookingId),
+                status: 'completed',
+              },
+              androidChannelId: 'patient_lab_bookings',
+              logLabel: `patient ${patientId} lab report ${bookingId}`,
+            });
+          }
+        }
+      }
+    } else if (table === 'ambulance_broadcasts') {
+      if (type === 'UPDATE' && record && oldRecord) {
+        if (record.status === 'accepted' && oldRecord.status !== 'accepted') {
+          const patientId = record.patient_id;
+          const broadcastId = record.broadcast_id;
+
+          if (patientId) {
+            await fcmSender(db, {
+              collection: 'patients',
+              docId: patientId,
+              title: 'Ambulance En Route',
+              body: 'An ambulance driver has accepted your emergency request and is en route.',
+              data: {
+                type: 'ambulance_accepted',
+                broadcastId: String(broadcastId),
+                status: 'accepted',
+              },
+              androidChannelId: 'patient_ambulance',
+              logLabel: `patient ${patientId} ambulance ${broadcastId}`,
+            });
+          }
+        }
+      }
     }
 
     return res.status(200).json({ success: true });
```
**Confirmation:** The diff was appended to the dispatcher switch statement. All pre-existing handlers (`appointments` and `prescriptions`) remain unaltered and fully functional. Zero handlers were deleted.
