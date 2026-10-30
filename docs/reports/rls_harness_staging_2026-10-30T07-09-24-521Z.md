# RLS SQL Harness Report (STAGING)

**Timestamp:** 2026-10-30T07:09:24.522Z  
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
| Happy Path: Patient A books family member appointment via book_appointment_atomic | PASS | PASS | **unchanged-pass** | Maintained pass |
| Happy Path: Patient A reschedules own appointment (assert return keys) | PASS | PASS | **unchanged-pass** | Maintained pass |
| Happy Path: Doctor A reschedules appointment (assert return keys) | PASS | PASS | **unchanged-pass** | Maintained pass |
| Happy Path: Family owner reschedules family appointment | PASS | PASS | **unchanged-pass** | Maintained pass |
| Happy Path: Doctor A creates full atomic prescription | PASS | PASS | **unchanged-pass** | Maintained pass |
| Unverified Doctor: create_prescription_atomic rejected with 42501 | PASS | PASS | **unchanged-pass** | Maintained pass |
| Happy Path: Driver accepts ambulance request | PASS | PASS | **unchanged-pass** | Maintained pass |
| Happy Path: Driver updates ambulance location | PASS | PASS | **unchanged-pass** | Maintained pass |
| Revoked RPC: Authenticated driver denied get_ambulance_trip_contact | PASS | PASS | **unchanged-pass** | Maintained pass |
| Revoked RPC: Authenticated patient denied get_ambulance_trip_contact | PASS | PASS | **unchanged-pass** | Maintained pass |
| Revoked RPC: Authenticated medical store denied get_ambulance_trip_contact | PASS | PASS | **unchanged-pass** | Maintained pass |
| Service Role Access: service_role allowed get_ambulance_trip_contact | PASS | PASS | **unchanged-pass** | Maintained pass |
| Phone Privacy: Driver on pending broadcast sees masked contact_phone IS NULL | PASS | PASS | **unchanged-pass** | Maintained pass |
| Phone Privacy: Accepted driver reads accepted broadcast and sees patient contact_phone | PASS | PASS | **unchanged-pass** | Maintained pass |
| Phone Privacy: Owning patient reads accepted broadcast and sees accepted_driver_phone | PASS | PASS | **unchanged-pass** | Maintained pass |
| Phone Privacy: Unrelated driver ambB blocked from accepted broadcast | PASS | PASS | **unchanged-pass** | Maintained pass |
| Phone Privacy: Unrelated patient pB blocked from accepted broadcast | PASS | PASS | **unchanged-pass** | Maintained pass |
| Happy Path: Driver completes ambulance trip | PASS | PASS | **unchanged-pass** | Maintained pass |
| Happy Path: Patient cancels pending ambulance broadcast | PASS | PASS | **unchanged-pass** | Maintained pass |
| Happy Path: Lab updates lab booking status to sampleCollected | PASS | PASS | **unchanged-pass** | Maintained pass |
| Happy Path: Lab updates lab order status to received | PASS | PASS | **unchanged-pass** | Maintained pass |
| Happy Path: Pharmacy marks delivery viewed | PASS | PASS | **unchanged-pass** | Maintained pass |
| Happy Path: Pharmacy dispenses delivery with p_medicine_lines | PASS | PASS | **unchanged-pass** | Maintained pass |
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
| Account Provisioning Tampering: Authenticated user inserts users row claiming admin role | PASS | PASS | **unchanged-pass** | Maintained pass |
| Resource Ownership Hijack: Authenticated user updates patients.owner_uid | PASS | PASS | **unchanged-pass** | Maintained pass |
| Account Provisioning Tampering: User B inserts users row claiming orphan doctor profile_id | PASS | PASS | **unchanged-pass** | Maintained pass |
| Resource Ownership Hijack: User B inserts doctors row with mismatched doctor_id | PASS | PASS | **unchanged-pass** | Maintained pass |
| Account Provisioning Tampering: Anon user inserts users row | PASS | PASS | **unchanged-pass** | Maintained pass |
| Anon Access: Select from doctor_directory view | PASS | PASS | **unchanged-pass** | Maintained pass |
| Anon Access: Select from lab_catalog_tests table | PASS | PASS | **unchanged-pass** | Maintained pass |
| Anon Access: Select from review_public view | PASS | PASS | **unchanged-pass** | Maintained pass |
| Anon Access: Select from promoted_ads table | PASS | PASS | **unchanged-pass** | Maintained pass |
| Anon Access: Select whitelisted keys from system_config (patient_module_status, promoted_ads) | PASS | PASS | **unchanged-pass** | Maintained pass |
| Anon Access Denied: Select from users table | PASS | PASS | **unchanged-pass** | Maintained pass |
| Anon Access Denied: Select from appointments table | PASS | PASS | **unchanged-pass** | Maintained pass |
| Anon Access Denied: Select from patients table | PASS | PASS | **unchanged-pass** | Maintained pass |
| Anon Access Denied: Select from doctors table | PASS | PASS | **unchanged-pass** | Maintained pass |
| Happy Path Registration: 2-step registration for patient (users -> patients) | PASS | PASS | **unchanged-pass** | Maintained pass |
| Happy Path Registration: 2-step registration for doctor (users -> doctors) | PASS | PASS | **unchanged-pass** | Maintained pass |
| Happy Path Registration: 2-step registration for medicalStore (users -> medical_stores) | PASS | PASS | **unchanged-pass** | Maintained pass |
| Happy Path Registration: 2-step registration for lab (users -> labs) | PASS | PASS | **unchanged-pass** | Maintained pass |
| Happy Path Registration: 2-step registration for ambulance (users -> ambulances) | PASS | PASS | **unchanged-pass** | Maintained pass |
| Privileged Columns: Doctor owner cannot insert with verified=true | PASS | PASS | **unchanged-pass** | Maintained pass |
| Privileged Columns: Doctor owner cannot update verified flag | PASS | PASS | **unchanged-pass** | Maintained pass |
| Privileged Columns: Doctor owner cannot update deactivated flag | PASS | PASS | **unchanged-pass** | Maintained pass |
| Privileged Columns: Doctor owner cannot change owner_uid | PASS | PASS | **unchanged-pass** | Maintained pass |
| Privileged Columns: Normal profile edit allowed for doctor owner | PASS | PASS | **unchanged-pass** | Maintained pass |
| Privileged Columns: Lab owner cannot insert with verified=true | PASS | PASS | **unchanged-pass** | Maintained pass |
| Privileged Columns: Lab owner cannot update verified flag | PASS | PASS | **unchanged-pass** | Maintained pass |
| Privileged Columns: Lab owner cannot change owner_uid | PASS | PASS | **unchanged-pass** | Maintained pass |
| Privileged Columns: Normal profile edit allowed for lab owner | PASS | PASS | **unchanged-pass** | Maintained pass |
| Privileged Columns: Store owner cannot insert with verified=true | PASS | PASS | **unchanged-pass** | Maintained pass |
| Privileged Columns: Store owner cannot update verified flag | PASS | PASS | **unchanged-pass** | Maintained pass |
| Privileged Columns: Normal profile edit allowed for store owner | PASS | PASS | **unchanged-pass** | Maintained pass |
| Privileged Columns: Ambulance owner cannot insert with verified=true | PASS | PASS | **unchanged-pass** | Maintained pass |
| Privileged Columns: Ambulance owner cannot update verified flag | PASS | PASS | **unchanged-pass** | Maintained pass |
| Privileged Columns: Ambulance owner cannot change auth_uid | PASS | PASS | **unchanged-pass** | Maintained pass |
| Privileged Columns: Normal profile edit allowed for ambulance owner | PASS | PASS | **unchanged-pass** | Maintained pass |
| Family Guard: Attacker B denied squatting un-namespaced patient_id as family member | PASS | PASS | **unchanged-pass** | Maintained pass |
| Family Guard: Patient A inserts namespaced family patient successfully | PASS | PASS | **unchanged-pass** | Maintained pass |
| Family Guard: Unsquatted victim registers primary profile without collision | PASS | PASS | **unchanged-pass** | Maintained pass |
| Users Upsert: Existing verified doctor re-login upsert succeeds | PASS | PASS | **unchanged-pass** | Maintained pass |
| Users Upsert: Existing verified medical store re-login upsert succeeds | PASS | PASS | **unchanged-pass** | Maintained pass |
| Users Upsert: Existing verified lab re-login upsert succeeds | PASS | PASS | **unchanged-pass** | Maintained pass |
| Users Upsert: Existing verified ambulance re-login upsert succeeds | PASS | PASS | **unchanged-pass** | Maintained pass |
| Anon Access Denied: Anonymous caller cannot SELECT from medical_directory | PASS | PASS | **unchanged-pass** | Maintained pass |
| Anon Access Denied: Anonymous caller cannot SELECT amount_paid from promoted_ads | PASS | PASS | **unchanged-pass** | Maintained pass |
| Anon Access Denied: Anonymous caller cannot SELECT payment_status from promoted_ads | PASS | PASS | **unchanged-pass** | Maintained pass |
| Anon Access Allow: Anonymous caller selects public columns from promoted_ads | PASS | PASS | **unchanged-pass** | Maintained pass |
| Privileged Columns: Doctor owner cannot update own rating | PASS | PASS | **unchanged-pass** | Maintained pass |
| Trusted Writers: Patient A submits review on Doctor A and aggregates update rating | PASS | FAIL | **FAIL** | FORBIDDEN: Caller is not the owner of this domain profile |
| Trusted Writers: Assigned driver completes ambulance trip via complete_ambulance_trip RPC | PASS | PASS | **unchanged-pass** | Maintained pass |
| Trusted Writers: Super admin verifies unverified doctor account | PASS | PASS | **unchanged-pass** | Maintained pass |
| Admin Write Denied: Authenticated patient denied admin write to verify doctor (UPDATE doctors SET verified=true as non-owner) | N/A | FAIL | **new-test** | Added in Staging Round 2 |
| Privileged Columns: Unverified doctor owner cannot self-verify by updating verified=true | PASS | PASS | **unchanged-pass** | Maintained pass |
| Privileged Columns: Doctor owner cannot update owner_uid | PASS | PASS | **unchanged-pass** | Maintained pass |
| Privileged Columns: Lab owner cannot update rating | PASS | PASS | **unchanged-pass** | Maintained pass |
| Privileged Columns: Unverified lab owner cannot self-verify by updating verified=true | PASS | PASS | **unchanged-pass** | Maintained pass |
| Privileged Columns: Lab owner cannot update owner_uid | PASS | PASS | **unchanged-pass** | Maintained pass |
| Privileged Columns: Unverified medical store owner cannot self-verify by updating verified=true | PASS | PASS | **unchanged-pass** | Maintained pass |
| Privileged Columns: Medical store owner cannot update owner_uid | PASS | PASS | **unchanged-pass** | Maintained pass |
| Privileged Columns: Medical store owner cannot update unallowlisted column (deactivated) | PASS | PASS | **unchanged-pass** | Maintained pass |
| Privileged Columns: Ambulance owner cannot update total_rating | PASS | PASS | **unchanged-pass** | Maintained pass |
| Privileged Columns: Unverified ambulance owner cannot self-verify by updating verified=true | PASS | PASS | **unchanged-pass** | Maintained pass |
| Privileged Columns: Ambulance owner cannot update auth_uid (via UPDATE guard) | PASS | PASS | **unchanged-pass** | Maintained pass |
| Privileged Columns: Patient owner cannot update verified flag | PASS | PASS | **unchanged-pass** | Maintained pass |
| Privileged Columns: Patient owner cannot update owner_uid | PASS | PASS | **unchanged-pass** | Maintained pass |
| Reviews Guard: Patient B denied review without completed appointment | PASS | PASS | **unchanged-pass** | Maintained pass |
| Reviews Guard: Doctor A denied self-reviewing own profile | PASS | PASS | **unchanged-pass** | Maintained pass |
| Ambulance Phone: Driver reads accepted broadcast through exact PostgREST query with unmasked contact_phone | PASS | PASS | **unchanged-pass** | Maintained pass |
| Ambulance Phone: Patient reads accepted broadcast through exact PostgREST query with accepted_driver_phone | PASS | PASS | **unchanged-pass** | Maintained pass |
| KYC Immutability: Verified doctor owner cannot update council_number | N/A | PASS | **new-test** | Added in Staging Round 2 |
| KYC Immutability: Unverified doctor owner can update council_number | N/A | PASS | **new-test** | Added in Staging Round 2 |
| KYC Immutability: Verified lab owner cannot update license_number | N/A | PASS | **new-test** | Added in Staging Round 2 |
| KYC Immutability: Unverified lab owner can update license_number | N/A | PASS | **new-test** | Added in Staging Round 2 |
| KYC Immutability: Verified medical store owner cannot update drug_license_number | N/A | PASS | **new-test** | Added in Staging Round 2 |
| KYC Immutability: Unverified medical store owner can update drug_license_number | N/A | PASS | **new-test** | Added in Staging Round 2 |
| KYC Immutability: Verified ambulance owner cannot update vehicle_number | N/A | PASS | **new-test** | Added in Staging Round 2 |
| KYC Immutability: Unverified ambulance owner can update vehicle_number | N/A | PASS | **new-test** | Added in Staging Round 2 |
| Client Compatibility: Doctor owner updates profile with exact frontend payload | N/A | PASS | **new-test** | Added in Staging Round 2 |
| Provider Lifecycle: Doctor owner deactivates profile via owner-bound RPC | N/A | PASS | **new-test** | Added in Staging Round 2 |
| Provider Lifecycle: Doctor owner reactivates profile via owner-bound RPC | N/A | PASS | **new-test** | Added in Staging Round 2 |
| Reviews Integrity: Patient cannot self-complete appointment to bypass review gating | N/A | PASS | **new-test** | Added in Staging Round 2 |
| Reviews Support: Patient submits review on Doctor A for completed family member appointment | N/A | FAIL | **new-test** | Added in Staging Round 2 |
| System Config: Anon selects whitelisted patient_module_status key | N/A | PASS | **new-test** | Added in Staging Round 2 |
| System Config: Anon selects whitelisted promoted_ads key | N/A | PASS | **new-test** | Added in Staging Round 2 |
| System Config: Anon query on non-whitelisted key returns 0 rows | N/A | PASS | **new-test** | Added in Staging Round 2 |

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
| Happy Path: Family owner reschedules family appointment | appointments | authenticated | 00000 | 00000 | 1 | 1 | PASS |
| Happy Path: Doctor A creates full atomic prescription | prescriptions | authenticated | 00000 | 00000 | 1 | 1 | PASS |
| Unverified Doctor: create_prescription_atomic rejected with 42501 | prescriptions | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Happy Path: Driver accepts ambulance request | ambulance_broadcasts | authenticated | 00000 | 00000 | 1 | 1 | PASS |
| Happy Path: Driver updates ambulance location | ambulance_locations | authenticated | 00000 | 00000 | 1 | 1 | PASS |
| Revoked RPC: Authenticated driver denied get_ambulance_trip_contact | rpc/get_ambulance_trip_contact | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Revoked RPC: Authenticated patient denied get_ambulance_trip_contact | rpc/get_ambulance_trip_contact | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Revoked RPC: Authenticated medical store denied get_ambulance_trip_contact | rpc/get_ambulance_trip_contact | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Service Role Access: service_role allowed get_ambulance_trip_contact | rpc/get_ambulance_trip_contact | service_role | 00000 | 00000 | 1 | 1 | PASS |
| Phone Privacy: Driver on pending broadcast sees masked contact_phone IS NULL | ambulance_broadcasts | authenticated | 00000 | 00000 | 1 | 1 | PASS |
| Phone Privacy: Accepted driver reads accepted broadcast and sees patient contact_phone | ambulance_broadcasts | authenticated | 00000 | 00000 | 1 | 1 | PASS |
| Phone Privacy: Owning patient reads accepted broadcast and sees accepted_driver_phone | ambulance_broadcasts | authenticated | 00000 | 00000 | 1 | 1 | PASS |
| Phone Privacy: Unrelated driver ambB blocked from accepted broadcast | ambulance_broadcasts | authenticated | 00000 | 00000 | 0 | 0 | PASS |
| Phone Privacy: Unrelated patient pB blocked from accepted broadcast | ambulance_broadcasts | authenticated | 00000 | 00000 | 0 | 0 | PASS |
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
| Anon Access: Select from promoted_ads table | promoted_ads | anon | 00000 | 00000 | - | 0 | PASS |
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
| Privileged Columns: Doctor owner cannot insert with verified=true | doctors | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Privileged Columns: Doctor owner cannot update verified flag | doctors | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Privileged Columns: Doctor owner cannot update deactivated flag | doctors | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Privileged Columns: Doctor owner cannot change owner_uid | doctors | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Privileged Columns: Normal profile edit allowed for doctor owner | doctors | authenticated | 00000 | 00000 | 1 | 1 | PASS |
| Privileged Columns: Lab owner cannot insert with verified=true | labs | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Privileged Columns: Lab owner cannot update verified flag | labs | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Privileged Columns: Lab owner cannot change owner_uid | labs | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Privileged Columns: Normal profile edit allowed for lab owner | labs | authenticated | 00000 | 00000 | 1 | 1 | PASS |
| Privileged Columns: Store owner cannot insert with verified=true | medical_stores | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Privileged Columns: Store owner cannot update verified flag | medical_stores | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Privileged Columns: Normal profile edit allowed for store owner | medical_stores | authenticated | 00000 | 00000 | 1 | 1 | PASS |
| Privileged Columns: Ambulance owner cannot insert with verified=true | ambulances | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Privileged Columns: Ambulance owner cannot update verified flag | ambulances | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Privileged Columns: Ambulance owner cannot change auth_uid | ambulances | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Privileged Columns: Normal profile edit allowed for ambulance owner | ambulances | authenticated | 00000 | 00000 | 1 | 1 | PASS |
| Family Guard: Attacker B denied squatting un-namespaced patient_id as family member | patients | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Family Guard: Patient A inserts namespaced family patient successfully | patients | authenticated | 00000 | 00000 | 1 | 1 | PASS |
| Family Guard: Unsquatted victim registers primary profile without collision | patients | authenticated | 00000 | 00000 | 1 | 1 | PASS |
| Users Upsert: Existing verified doctor re-login upsert succeeds | users | authenticated | 00000 | 00000 | 1 | 1 | PASS |
| Users Upsert: Existing verified medical store re-login upsert succeeds | users | authenticated | 00000 | 00000 | 1 | 1 | PASS |
| Users Upsert: Existing verified lab re-login upsert succeeds | users | authenticated | 00000 | 00000 | 1 | 1 | PASS |
| Users Upsert: Existing verified ambulance re-login upsert succeeds | users | authenticated | 00000 | 00000 | 1 | 1 | PASS |
| Anon Access Denied: Anonymous caller cannot SELECT from medical_directory | medical_directory | anon | 42501 | 42501 | 0 | 0 | PASS |
| Anon Access Denied: Anonymous caller cannot SELECT amount_paid from promoted_ads | promoted_ads | anon | 42501 | 42501 | 0 | 0 | PASS |
| Anon Access Denied: Anonymous caller cannot SELECT payment_status from promoted_ads | promoted_ads | anon | 42501 | 42501 | 0 | 0 | PASS |
| Anon Access Allow: Anonymous caller selects public columns from promoted_ads | promoted_ads | anon | 00000 | 00000 | - | 0 | PASS |
| Privileged Columns: Doctor owner cannot update own rating | doctors | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Trusted Writers: Patient A submits review on Doctor A and aggregates update rating | reviews | authenticated | 00000 | 42501 | 0 | 0 | FAIL |
| Trusted Writers: Assigned driver completes ambulance trip via complete_ambulance_trip RPC | ambulance_broadcasts | authenticated | 00000 | 00000 | - | 1 | PASS |
| Trusted Writers: Super admin verifies unverified doctor account | doctors | authenticated | 00000 | 00000 | 1 | 1 | PASS |
| Admin Write Denied: Authenticated patient denied admin write to verify doctor (UPDATE doctors SET verified=true as non-owner) | doctors | authenticated | 42501 | 00000 | - | 0 | FAIL |
| Privileged Columns: Unverified doctor owner cannot self-verify by updating verified=true | doctors | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Privileged Columns: Doctor owner cannot update owner_uid | doctors | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Privileged Columns: Lab owner cannot update rating | labs | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Privileged Columns: Unverified lab owner cannot self-verify by updating verified=true | labs | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Privileged Columns: Lab owner cannot update owner_uid | labs | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Privileged Columns: Unverified medical store owner cannot self-verify by updating verified=true | medical_stores | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Privileged Columns: Medical store owner cannot update owner_uid | medical_stores | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Privileged Columns: Medical store owner cannot update unallowlisted column (deactivated) | medical_stores | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Privileged Columns: Ambulance owner cannot update total_rating | ambulances | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Privileged Columns: Unverified ambulance owner cannot self-verify by updating verified=true | ambulances | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Privileged Columns: Ambulance owner cannot update auth_uid (via UPDATE guard) | ambulances | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Privileged Columns: Patient owner cannot update verified flag | patients | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Privileged Columns: Patient owner cannot update owner_uid | patients | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Reviews Guard: Patient B denied review without completed appointment | reviews | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Reviews Guard: Doctor A denied self-reviewing own profile | reviews | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Ambulance Phone: Driver reads accepted broadcast through exact PostgREST query with unmasked contact_phone | ambulance_broadcasts | authenticated | 00000 | 00000 | 1 | 1 | PASS |
| Ambulance Phone: Patient reads accepted broadcast through exact PostgREST query with accepted_driver_phone | ambulance_broadcasts | authenticated | 00000 | 00000 | 1 | 1 | PASS |
| KYC Immutability: Verified doctor owner cannot update council_number | doctors | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| KYC Immutability: Unverified doctor owner can update council_number | doctors | authenticated | 00000 | 00000 | 1 | 1 | PASS |
| KYC Immutability: Verified lab owner cannot update license_number | labs | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| KYC Immutability: Unverified lab owner can update license_number | labs | authenticated | 00000 | 00000 | 1 | 1 | PASS |
| KYC Immutability: Verified medical store owner cannot update drug_license_number | medical_stores | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| KYC Immutability: Unverified medical store owner can update drug_license_number | medical_stores | authenticated | 00000 | 00000 | 1 | 1 | PASS |
| KYC Immutability: Verified ambulance owner cannot update vehicle_number | ambulances | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| KYC Immutability: Unverified ambulance owner can update vehicle_number | ambulances | authenticated | 00000 | 00000 | 1 | 1 | PASS |
| Client Compatibility: Doctor owner updates profile with exact frontend payload | doctors | authenticated | 00000 | 00000 | 1 | 1 | PASS |
| Provider Lifecycle: Doctor owner deactivates profile via owner-bound RPC | doctors | authenticated | 00000 | 00000 | - | 1 | PASS |
| Provider Lifecycle: Doctor owner reactivates profile via owner-bound RPC | doctors | authenticated | 00000 | 00000 | - | 1 | PASS |
| Reviews Integrity: Patient cannot self-complete appointment to bypass review gating | appointments | authenticated | 42501 | 42501 | 0 | 0 | PASS |
| Reviews Support: Patient submits review on Doctor A for completed family member appointment | reviews | authenticated | 00000 | 42501 | 0 | 0 | FAIL |
| System Config: Anon selects whitelisted patient_module_status key | system_config | anon | 00000 | 00000 | 1 | 1 | PASS |
| System Config: Anon selects whitelisted promoted_ads key | system_config | anon | 00000 | 00000 | 1 | 1 | PASS |
| System Config: Anon query on non-whitelisted key returns 0 rows | system_config | anon | 00000 | 00000 | 0 | 0 | PASS |

**Summary:** Total: 181 | PASS: 178 | FAIL: 3
