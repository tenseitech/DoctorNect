# RLS SQL Harness Report (STAGING)

**Timestamp:** 2026-10-29T09:04:04.139Z  
**Target:** staging  
**Zero Residue:** PROVEN (Count Before: 0, Count After: 0)  

## 1. Fixture Changes (Audit Justification)

| Fixture | Before | After | Schema Justification |
|---|---|---|---|
| `public.patients` | Only primary profiles (`pA`, `pB`) | Primary profiles + family patient profile `test_fam_a1` (owner_uid: `pA`) | Satisfies FK `appointments_patient_id_fkey` which references `patients(patient_id)` |
| `public.doctors` | Only verified doctors (`docA`, `docB`) | Verified doctors + unverified doctor `test_usr_doc_unverified` (`verified = false`) | Required to empirically test doctor verification check in `create_prescription_atomic` |
| `pharmacy_delivery_medicines` | Payload used `"availability": "dispensed"` | Payload uses `"availability": "available"` | Check constraint `pharmacy_delivery_medicines_availability_check` permits only: `('pending', 'available', 'outOfStock', 'substituted')` |

## 2. Before vs After Comparative Matrix

| Test Name | Previous Verdict | Current Verdict | Change Classification | Notes |
|---|---|---|---|---|
| Positive Control: Patient A read own profile | PASS | PASS | **unchanged-pass** | Maintained pass |
| Positive Control: Doctor A read own profile | PASS | PASS | **unchanged-pass** | Maintained pass |
| Positive Control: Patient A read own health record | PASS | PASS | **unchanged-pass** | Maintained pass |
| Happy Path: Patient A books own appointment via book_appointment_atomic | PASS | PASS | **unchanged-pass** | Maintained pass |
| Happy Path: Patient A books family member appointment via book_appointment_atomic | FAIL | PASS | **fixture-change** | Passing after schema-compliant fixture alignment |
| Happy Path: Patient A reschedules own appointment (assert return keys) | PASS | PASS | **unchanged-pass** | Maintained pass |
| Happy Path: Doctor A reschedules appointment (assert return keys) | PASS | PASS | **unchanged-pass** | Maintained pass |
| Happy Path: Family owner reschedules family appointment | FAIL | FAIL | **FAIL** | APPOINTMENT_NOT_FOUND |
| Happy Path: Doctor A creates full atomic prescription | PASS | PASS | **unchanged-pass** | Maintained pass |
| Unverified Doctor: create_prescription_atomic rejected with 42501 | N/A | PASS | **new-test** | Added in Staging Round 2 |
| Happy Path: Driver accepts ambulance request | PASS | PASS | **unchanged-pass** | Maintained pass |
| Happy Path: Driver updates ambulance location | PASS | PASS | **unchanged-pass** | Maintained pass |
| Happy Path: Driver views ambulance trip contact | FAIL | PASS | **migration-effect** | Fixed by migration 20261029000001 |
| Happy Path: Patient views ambulance trip contact on accepted broadcast | N/A | PASS | **new-test** | Added in Staging Round 2 |
| Happy Path: Patient views ambulance trip contact on pending broadcast | N/A | PASS | **new-test** | Added in Staging Round 2 |
| Happy Path: Driver views ambulance trip contact on pending broadcast | N/A | FAIL | **new-test** | Added in Staging Round 2 |
| Wrong Role: Medical Store calls get_ambulance_trip_contact on broadcast | N/A | PASS | **new-test** | Added in Staging Round 2 |
| Happy Path: Driver completes ambulance trip | PASS | PASS | **unchanged-pass** | Maintained pass |
| Happy Path: Patient cancels pending ambulance broadcast | PASS | PASS | **unchanged-pass** | Maintained pass |
| Happy Path: Lab updates lab booking status to sampleCollected | PASS | PASS | **unchanged-pass** | Maintained pass |
| Happy Path: Lab updates lab order status to received | PASS | PASS | **unchanged-pass** | Maintained pass |
| Happy Path: Pharmacy marks delivery viewed | PASS | PASS | **unchanged-pass** | Maintained pass |
| Happy Path: Pharmacy dispenses delivery with p_medicine_lines | FAIL | PASS | **fixture-change** | Passing after schema-compliant fixture alignment |
| Happy Path: Patient user insert | PASS | PASS | **unchanged-pass** | Maintained pass |
| Happy Path: Patient user upsert on conflict id | PASS | PASS | **unchanged-pass** | Maintained pass |
| Happy Path: Patient user update display_name | PASS | PASS | **unchanged-pass** | Maintained pass |
| Happy Path: Doctor user insert | PASS | PASS | **unchanged-pass** | Maintained pass |
| Happy Path: Doctor user upsert on conflict id | PASS | PASS | **unchanged-pass** | Maintained pass |
| Happy Path: Doctor user update display_name | PASS | PASS | **unchanged-pass** | Maintained pass |
| Happy Path: Medical Store user insert | PASS | PASS | **unchanged-pass** | Maintained pass |
| Happy Path: Medical Store user upsert on conflict id | PASS | PASS | **unchanged-pass** | Maintained pass |
| Happy Path: Medical Store user update display_name | PASS | PASS | **unchanged-pass** | Maintained pass |
| Happy Path: Lab user insert | PASS | PASS | **unchanged-pass** | Maintained pass |
| Happy Path: Lab user upsert on conflict id | PASS | PASS | **unchanged-pass** | Maintained pass |
| Happy Path: Lab user update display_name | PASS | PASS | **unchanged-pass** | Maintained pass |
| Happy Path: Ambulance user insert | PASS | PASS | **unchanged-pass** | Maintained pass |
| Happy Path: Ambulance user upsert on conflict id | PASS | PASS | **unchanged-pass** | Maintained pass |
| Happy Path: Ambulance user update display_name | PASS | PASS | **unchanged-pass** | Maintained pass |
| Happy Path: User devices upsert on conflict (user_id, platform) | PASS | PASS | **unchanged-pass** | Maintained pass |
| Cross-Tenant: Patient B read Patient A profile | PASS | PASS | **unchanged-pass** | Maintained pass |
| Cross-Tenant: Patient B update Patient A health record | PASS | PASS | **unchanged-pass** | Maintained pass |
| Cross-Tenant: Patient B delete Patient A health record | PASS | PASS | **unchanged-pass** | Maintained pass |
| Cross-Tenant INSERT: Patient B inserts record with Patient A owner id | PASS | PASS | **unchanged-pass** | Maintained pass |
| Role Escalation: Patient A inserts into doctors table | PASS | PASS | **unchanged-pass** | Maintained pass |
| Role Escalation: Patient A inserts into medical_stores table | PASS | PASS | **unchanged-pass** | Maintained pass |
| Role Escalation: Patient A elevates role in public.users | PASS | PASS | **unchanged-pass** | Maintained pass |
| Anon Access: Read table users | PASS | PASS | **unchanged-pass** | Maintained pass |
| Anon Access: Read table patients | PASS | PASS | **unchanged-pass** | Maintained pass |
| Anon Access: Read table appointments | PASS | PASS | **unchanged-pass** | Maintained pass |
| Anon Access: Read table health_records | PASS | PASS | **unchanged-pass** | Maintained pass |
| Anon Access: Read table prescriptions | PASS | PASS | **unchanged-pass** | Maintained pass |
| Relationship: Linked Doctor A reads Patient A health record | PASS | PASS | **unchanged-pass** | Maintained pass |
| Relationship: Unlinked Doctor B denied Patient A health record | PASS | PASS | **unchanged-pass** | Maintained pass |
| RPC Authz: book_appointment_atomic - Patient B books for Patient A | PASS | PASS | **unchanged-pass** | Maintained pass |
| RPC Authz: reschedule_appointment_atomic - Patient B reschedules Patient A appt | PASS | PASS | **unchanged-pass** | Maintained pass |
| RPC Authz: create_prescription_atomic - Doctor B prescribes for Doctor A appt | PASS | PASS | **unchanged-pass** | Maintained pass |
| RPC Authz: cancel_ambulance_broadcast - Patient B cancels Patient A broadcast | PASS | PASS | **unchanged-pass** | Maintained pass |
| RPC Authz: complete_ambulance_trip - Driver B completes Driver A trip | PASS | PASS | **unchanged-pass** | Maintained pass |
| RPC Authz: update_ambulance_location - Driver B updates Driver A location | PASS | PASS | **unchanged-pass** | Maintained pass |
| RPC Authz: get_ambulance_trip_location - Driver B views Patient A trip location | PASS | PASS | **unchanged-pass** | Maintained pass |
| RPC Authz: accept_ambulance_request - Patient A calls driver accept RPC | PASS | PASS | **unchanged-pass** | Maintained pass |
| RPC Authz: update_lab_booking_status - Lab B updates Lab A booking | PASS | PASS | **unchanged-pass** | Maintained pass |
| RPC Authz: update_lab_order_status - Lab B updates Lab A order | PASS | PASS | **unchanged-pass** | Maintained pass |
| RPC Authz: update_pharmacy_delivery_status - Store B updates Store A delivery | PASS | PASS | **unchanged-pass** | Maintained pass |
| Unprofiled Caller: book_appointment_atomic | PASS | PASS | **unchanged-pass** | Maintained pass |
| Unprofiled Caller: reschedule_appointment_atomic | PASS | PASS | **unchanged-pass** | Maintained pass |
| Unprofiled Caller: create_prescription_atomic | PASS | PASS | **unchanged-pass** | Maintained pass |
| Unprofiled Caller: cancel_ambulance_broadcast | PASS | PASS | **unchanged-pass** | Maintained pass |
| Unprofiled Caller: complete_ambulance_trip | PASS | PASS | **unchanged-pass** | Maintained pass |
| Unprofiled Caller: update_ambulance_location | PASS | PASS | **unchanged-pass** | Maintained pass |
| Unprofiled Caller: get_ambulance_trip_location | PASS | PASS | **unchanged-pass** | Maintained pass |
| Unprofiled Caller: accept_ambulance_request | PASS | PASS | **unchanged-pass** | Maintained pass |
| Unprofiled Caller: update_lab_booking_status | PASS | PASS | **unchanged-pass** | Maintained pass |
| Unprofiled Caller: update_lab_order_status | PASS | PASS | **unchanged-pass** | Maintained pass |
| Unprofiled Caller: update_pharmacy_delivery_status | PASS | PASS | **unchanged-pass** | Maintained pass |
| Wrong Role: Patient calls complete_ambulance_trip on accepted broadcast | PASS | PASS | **unchanged-pass** | Maintained pass |
| Wrong Role: Patient calls complete_ambulance_trip on pending broadcast | PASS | PASS | **unchanged-pass** | Maintained pass |
| Wrong Role: Patient calls complete_ambulance_trip on cancelled broadcast | PASS | PASS | **unchanged-pass** | Maintained pass |
| Wrong Role: Patient calls accept_ambulance_request on accepted broadcast | PASS | PASS | **unchanged-pass** | Maintained pass |
| Wrong Role: Patient calls accept_ambulance_request on pending broadcast | PASS | PASS | **unchanged-pass** | Maintained pass |
| Wrong Role: Patient calls accept_ambulance_request on cancelled broadcast | PASS | PASS | **unchanged-pass** | Maintained pass |
| Wrong Role: Patient calls update_ambulance_location | PASS | PASS | **unchanged-pass** | Maintained pass |
| Wrong Role: Medical Store calls create_prescription_atomic | PASS | PASS | **unchanged-pass** | Maintained pass |
| Wrong Role: Patient calls create_prescription_atomic | PASS | PASS | **unchanged-pass** | Maintained pass |
| Wrong Role: Doctor calls update_pharmacy_delivery_status | PASS | PASS | **unchanged-pass** | Maintained pass |
| Wrong Role: Ambulance driver calls update_lab_booking_status | PASS | PASS | **unchanged-pass** | Maintained pass |
| Wrong Role: Medical Store calls update_lab_order_status | PASS | PASS | **unchanged-pass** | Maintained pass |
| Wrong Role: Ambulance driver calls reschedule_appointment_atomic | PASS | PASS | **unchanged-pass** | Maintained pass |
| Wrong Role: Medical Store calls cancel_ambulance_broadcast on pending broadcast | PASS | PASS | **unchanged-pass** | Maintained pass |
| Wrong Role: Medical Store calls get_ambulance_trip_location on broadcast | PASS | PASS | **unchanged-pass** | Maintained pass |
| Idempotency Conflict: Patient B calls book_appointment_atomic with Patient A appointment_id | PASS | PASS | **unchanged-pass** | Maintained pass |
| Privilege Escalation: Authenticated user updates own users.role to admin | PASS | PASS | **unchanged-pass** | Maintained pass |
| Identity Tampering: Authenticated user updates own users.profile_id to victim id | PASS | PASS | **unchanged-pass** | Maintained pass |
| Account Provisioning Tampering: Authenticated user inserts users row claiming admin role | FAIL | PASS | **migration-effect** | Fixed by migration 20261029000001 |
| Resource Ownership Hijack: Authenticated user updates patients.owner_uid | PASS | PASS | **unchanged-pass** | Maintained pass |
| Account Provisioning Tampering: User B inserts users row claiming orphan doctor profile_id | FAIL | PASS | **migration-effect** | Fixed by migration 20261029000001 |
| Resource Ownership Hijack: User B inserts doctors row with mismatched doctor_id | FAIL | PASS | **migration-effect** | Fixed by migration 20261029000001 |
| Account Provisioning Tampering: Anon user inserts users row | N/A | PASS | **new-test** | Added in Staging Round 2 |
| Anon Access: Select from doctor_directory view | N/A | PASS | **new-test** | Added in Staging Round 2 |
| Anon Access: Select from lab_catalog_tests table | N/A | PASS | **new-test** | Added in Staging Round 2 |
| Anon Access: Select from review_public view | N/A | PASS | **new-test** | Added in Staging Round 2 |
| Anon Access: Select from promoted_ads table | N/A | PASS | **new-test** | Added in Staging Round 2 |
| Anon Access: Select from medical_directory table | N/A | PASS | **new-test** | Added in Staging Round 2 |
| Anon Access: Select whitelisted keys from system_config (patient_module_status, promoted_ads) | N/A | PASS | **new-test** | Added in Staging Round 2 |
| Anon Access Denied: Select from users table | N/A | PASS | **new-test** | Added in Staging Round 2 |
| Anon Access Denied: Select from appointments table | N/A | PASS | **new-test** | Added in Staging Round 2 |
| Anon Access Denied: Select from patients table | N/A | PASS | **new-test** | Added in Staging Round 2 |
| Anon Access Denied: Select from doctors table | N/A | PASS | **new-test** | Added in Staging Round 2 |
| Happy Path Registration: 2-step registration for patient (users -> patients) | PASS | PASS | **unchanged-pass** | Maintained pass |
| Happy Path Registration: 2-step registration for doctor (users -> doctors) | PASS | PASS | **unchanged-pass** | Maintained pass |
| Happy Path Registration: 2-step registration for medicalStore (users -> medical_stores) | PASS | PASS | **unchanged-pass** | Maintained pass |
| Happy Path Registration: 2-step registration for lab (users -> labs) | PASS | PASS | **unchanged-pass** | Maintained pass |
| Happy Path Registration: 2-step registration for ambulance (users -> ambulances) | PASS | PASS | **unchanged-pass** | Maintained pass |

## 3. Full Results Matrix

| Test | Table | Role | Expected SQLSTATE | Actual SQLSTATE | Expected Rows | Actual Rows | Verdict |
|---|---|---|---|---|---|---|---|
| Positive Control: Patient A read own profile | patients | authenticated | 00000 | 00000 | 1 | 1 | PASS |
| Positive Control: Doctor A read own profile | doctors | authenticated | 00000 | 00000 | 1 | 1 | PASS |
| Positive Control: Patient A read own health record | health_records | authenticated | 00000 | 00000 | 1 | 1 | PASS |
| Happy Path: Patient A books own appointment via book_appointment_atomic | appointments | authenticated | 00000 | 00000 | 1 | 1 | PASS |
| Happy Path: Patient A books family member appointment via book_appointment_atomic | appointments | authenticated | 00000 | 00000 | 1 | 1 | PASS |
| Happy Path: Patient A reschedules own appointment (assert return keys) | appointments | authenticated | 00000 | 00000 | 1 | 1 | PASS |
| Happy Path: Doctor A reschedules appointment (assert return keys) | appointments | authenticated | 00000 | 00000 | 1 | 1 | PASS |
| Happy Path: Family owner reschedules family appointment | appointments | authenticated | 00000 | P0002 | 0 | 0 | FAIL |
| Happy Path: Doctor A creates full atomic prescription | prescriptions | authenticated | 00000 | 00000 | 1 | 1 | PASS |
| Unverified Doctor: create_prescription_atomic rejected with 42501 | prescriptions | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Happy Path: Driver accepts ambulance request | ambulance_broadcasts | authenticated | 00000 | 00000 | 1 | 1 | PASS |
| Happy Path: Driver updates ambulance location | ambulance_locations | authenticated | 00000 | 00000 | 1 | 1 | PASS |
| Happy Path: Driver views ambulance trip contact | ambulance_trip_contacts | authenticated | 00000 | 00000 | 1 | 1 | PASS |
| Happy Path: Patient views ambulance trip contact on accepted broadcast | ambulance_trip_contacts | authenticated | 00000 | 00000 | 1 | 1 | PASS |
| Happy Path: Patient views ambulance trip contact on pending broadcast | ambulance_trip_contacts | authenticated | 00000 | 00000 | 1 | 1 | PASS |
| Happy Path: Driver views ambulance trip contact on pending broadcast | ambulance_trip_contacts | authenticated | 00000 | 42501 | 0 | 0 | FAIL |
| Wrong Role: Medical Store calls get_ambulance_trip_contact on broadcast | rpc/get_ambulance_trip_contact | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Happy Path: Driver completes ambulance trip | ambulance_broadcasts | authenticated | 00000 | 00000 | 1 | 1 | PASS |
| Happy Path: Patient cancels pending ambulance broadcast | ambulance_broadcasts | authenticated | 00000 | 00000 | 1 | 1 | PASS |
| Happy Path: Lab updates lab booking status to sampleCollected | lab_bookings | authenticated | 00000 | 00000 | 1 | 1 | PASS |
| Happy Path: Lab updates lab order status to received | lab_orders | authenticated | 00000 | 00000 | 1 | 1 | PASS |
| Happy Path: Pharmacy marks delivery viewed | pharmacy_deliveries | authenticated | 00000 | 00000 | 1 | 1 | PASS |
| Happy Path: Pharmacy dispenses delivery with p_medicine_lines | pharmacy_deliveries | authenticated | 00000 | 00000 | 1 | 1 | PASS |
| Happy Path: Patient user insert | public.users | authenticated | 00000 | 00000 | 1 | 1 | PASS |
| Happy Path: Patient user upsert on conflict id | public.users | authenticated | 00000 | 00000 | 1 | 1 | PASS |
| Happy Path: Patient user update display_name | public.users | authenticated | 00000 | 00000 | 1 | 1 | PASS |
| Happy Path: Doctor user insert | public.users | authenticated | 00000 | 00000 | 1 | 1 | PASS |
| Happy Path: Doctor user upsert on conflict id | public.users | authenticated | 00000 | 00000 | 1 | 1 | PASS |
| Happy Path: Doctor user update display_name | public.users | authenticated | 00000 | 00000 | 1 | 1 | PASS |
| Happy Path: Medical Store user insert | public.users | authenticated | 00000 | 00000 | 1 | 1 | PASS |
| Happy Path: Medical Store user upsert on conflict id | public.users | authenticated | 00000 | 00000 | 1 | 1 | PASS |
| Happy Path: Medical Store user update display_name | public.users | authenticated | 00000 | 00000 | 1 | 1 | PASS |
| Happy Path: Lab user insert | public.users | authenticated | 00000 | 00000 | 1 | 1 | PASS |
| Happy Path: Lab user upsert on conflict id | public.users | authenticated | 00000 | 00000 | 1 | 1 | PASS |
| Happy Path: Lab user update display_name | public.users | authenticated | 00000 | 00000 | 1 | 1 | PASS |
| Happy Path: Ambulance user insert | public.users | authenticated | 00000 | 00000 | 1 | 1 | PASS |
| Happy Path: Ambulance user upsert on conflict id | public.users | authenticated | 00000 | 00000 | 1 | 1 | PASS |
| Happy Path: Ambulance user update display_name | public.users | authenticated | 00000 | 00000 | 1 | 1 | PASS |
| Happy Path: User devices upsert on conflict (user_id, platform) | public.user_devices | authenticated | 00000 | 00000 | 1 | 1 | PASS |
| Cross-Tenant: Patient B read Patient A profile | patients | authenticated | 00000 | 00000 | 0 | 0 | PASS |
| Cross-Tenant: Patient B update Patient A health record | health_records | authenticated | 00000 | 00000 | 0 | 0 | PASS |
| Cross-Tenant: Patient B delete Patient A health record | health_records | authenticated | 00000 | 00000 | 0 | 0 | PASS |
| Cross-Tenant INSERT: Patient B inserts record with Patient A owner id | health_records | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Role Escalation: Patient A inserts into doctors table | doctors | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Role Escalation: Patient A inserts into medical_stores table | medical_stores | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Role Escalation: Patient A elevates role in public.users | users | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Anon Access: Read table users | users | anon | 42501 | 42501 | 0 | 0 | PASS |
| Anon Access: Read table patients | patients | anon | 42501 | 42501 | 0 | 0 | PASS |
| Anon Access: Read table appointments | appointments | anon | 42501 | 42501 | 0 | 0 | PASS |
| Anon Access: Read table health_records | health_records | anon | 42501 | 42501 | 0 | 0 | PASS |
| Anon Access: Read table prescriptions | prescriptions | anon | 42501 | 42501 | 0 | 0 | PASS |
| Relationship: Linked Doctor A reads Patient A health record | health_records | authenticated | 00000 | 00000 | 1 | 1 | PASS |
| Relationship: Unlinked Doctor B denied Patient A health record | health_records | authenticated | 00000 | 00000 | 0 | 0 | PASS |
| RPC Authz: book_appointment_atomic - Patient B books for Patient A | rpc/book_appointment_atomic | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| RPC Authz: reschedule_appointment_atomic - Patient B reschedules Patient A appt | rpc/reschedule_appointment_atomic | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| RPC Authz: create_prescription_atomic - Doctor B prescribes for Doctor A appt | rpc/create_prescription_atomic | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| RPC Authz: cancel_ambulance_broadcast - Patient B cancels Patient A broadcast | rpc/cancel_ambulance_broadcast | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| RPC Authz: complete_ambulance_trip - Driver B completes Driver A trip | rpc/complete_ambulance_trip | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| RPC Authz: update_ambulance_location - Driver B updates Driver A location | rpc/update_ambulance_location | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| RPC Authz: get_ambulance_trip_location - Driver B views Patient A trip location | rpc/get_ambulance_trip_location | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| RPC Authz: accept_ambulance_request - Patient A calls driver accept RPC | rpc/accept_ambulance_request | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| RPC Authz: update_lab_booking_status - Lab B updates Lab A booking | rpc/update_lab_booking_status | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| RPC Authz: update_lab_order_status - Lab B updates Lab A order | rpc/update_lab_order_status | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| RPC Authz: update_pharmacy_delivery_status - Store B updates Store A delivery | rpc/update_pharmacy_delivery_status | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Unprofiled Caller: book_appointment_atomic | rpc/book_appointment_atomic | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Unprofiled Caller: reschedule_appointment_atomic | rpc/reschedule_appointment_atomic | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Unprofiled Caller: create_prescription_atomic | rpc/create_prescription_atomic | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Unprofiled Caller: cancel_ambulance_broadcast | rpc/cancel_ambulance_broadcast | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Unprofiled Caller: complete_ambulance_trip | rpc/complete_ambulance_trip | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Unprofiled Caller: update_ambulance_location | rpc/update_ambulance_location | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Unprofiled Caller: get_ambulance_trip_location | rpc/get_ambulance_trip_location | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Unprofiled Caller: accept_ambulance_request | rpc/accept_ambulance_request | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Unprofiled Caller: update_lab_booking_status | rpc/update_lab_booking_status | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Unprofiled Caller: update_lab_order_status | rpc/update_lab_order_status | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Unprofiled Caller: update_pharmacy_delivery_status | rpc/update_pharmacy_delivery_status | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Wrong Role: Patient calls complete_ambulance_trip on accepted broadcast | rpc/complete_ambulance_trip | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Wrong Role: Patient calls complete_ambulance_trip on pending broadcast | rpc/complete_ambulance_trip | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Wrong Role: Patient calls complete_ambulance_trip on cancelled broadcast | rpc/complete_ambulance_trip | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Wrong Role: Patient calls accept_ambulance_request on accepted broadcast | rpc/accept_ambulance_request | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Wrong Role: Patient calls accept_ambulance_request on pending broadcast | rpc/accept_ambulance_request | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Wrong Role: Patient calls accept_ambulance_request on cancelled broadcast | rpc/accept_ambulance_request | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Wrong Role: Patient calls update_ambulance_location | rpc/update_ambulance_location | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Wrong Role: Medical Store calls create_prescription_atomic | rpc/create_prescription_atomic | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Wrong Role: Patient calls create_prescription_atomic | rpc/create_prescription_atomic | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Wrong Role: Doctor calls update_pharmacy_delivery_status | rpc/update_pharmacy_delivery_status | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Wrong Role: Ambulance driver calls update_lab_booking_status | rpc/update_lab_booking_status | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Wrong Role: Medical Store calls update_lab_order_status | rpc/update_lab_order_status | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Wrong Role: Ambulance driver calls reschedule_appointment_atomic | rpc/reschedule_appointment_atomic | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Wrong Role: Medical Store calls cancel_ambulance_broadcast on pending broadcast | rpc/cancel_ambulance_broadcast | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Wrong Role: Medical Store calls get_ambulance_trip_location on broadcast | rpc/get_ambulance_trip_location | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Idempotency Conflict: Patient B calls book_appointment_atomic with Patient A appointment_id | rpc/book_appointment_atomic | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Privilege Escalation: Authenticated user updates own users.role to admin | public.users | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Identity Tampering: Authenticated user updates own users.profile_id to victim id | public.users | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Account Provisioning Tampering: Authenticated user inserts users row claiming admin role | public.users | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Resource Ownership Hijack: Authenticated user updates patients.owner_uid | public.patients | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Account Provisioning Tampering: User B inserts users row claiming orphan doctor profile_id | public.users | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Resource Ownership Hijack: User B inserts doctors row with mismatched doctor_id | public.doctors | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Account Provisioning Tampering: Anon user inserts users row | public.users | anon | 42501 | 42501 | 0 | 0 | PASS |
| Anon Access: Select from doctor_directory view | doctor_directory | anon | 00000 | 00000 | - | 1 | PASS |
| Anon Access: Select from lab_catalog_tests table | lab_catalog_tests | anon | 00000 | 00000 | - | 1 | PASS |
| Anon Access: Select from review_public view | review_public | anon | 00000 | 00000 | - | 1 | PASS |
| Anon Access: Select from promoted_ads table | promoted_ads | anon | 00000 | 00000 | - | 1 | PASS |
| Anon Access: Select from medical_directory table | medical_directory | anon | 00000 | 00000 | - | 1 | PASS |
| Anon Access: Select whitelisted keys from system_config (patient_module_status, promoted_ads) | system_config | anon | 00000 | 00000 | - | 2 | PASS |
| Anon Access Denied: Select from users table | users | anon | 42501 | 42501 | 0 | 0 | PASS |
| Anon Access Denied: Select from appointments table | appointments | anon | 42501 | 42501 | 0 | 0 | PASS |
| Anon Access Denied: Select from patients table | patients | anon | 42501 | 42501 | 0 | 0 | PASS |
| Anon Access Denied: Select from doctors table | doctors | anon | 42501 | 42501 | 0 | 0 | PASS |
| Happy Path Registration: 2-step registration for patient (users -> patients) | public.users | authenticated | 00000 | 00000 | 1 | 1 | PASS |
| Happy Path Registration: 2-step registration for doctor (users -> doctors) | public.users | authenticated | 00000 | 00000 | 1 | 1 | PASS |
| Happy Path Registration: 2-step registration for medicalStore (users -> medical_stores) | public.users | authenticated | 00000 | 00000 | 1 | 1 | PASS |
| Happy Path Registration: 2-step registration for lab (users -> labs) | public.users | authenticated | 00000 | 00000 | 1 | 1 | PASS |
| Happy Path Registration: 2-step registration for ambulance (users -> ambulances) | public.users | authenticated | 00000 | 00000 | 1 | 1 | PASS |

**Summary:** Total: 113 | PASS: 111 | FAIL: 2
