# DoctorNect Schema Truth: Final Column Specifications

Derived by reading all migrations in chronological order:
- `20260923000001_doctornect_schema.sql`
- `20260923000002_doctornect_rls.sql`
- `20260923000003_doctornect_cron.sql`
- `20260925000001_sync_bridge_infra.sql`
- `20260926000001_atomic_appointment_booking.sql`
- `20260928000001_add_health_records_s3_storage_fields.sql`
- `20260928000002_add_lab_reports_s3_storage_fields.sql`
- `20260928000003_add_profile_photos_s3_storage_fields.sql`
- `20260929000001_add_promoted_ads_s3_storage_fields.sql`
- `20260930000001_fix_security_advisor_warnings.sql`
- `20260930000002_admin_users_table.sql`
- `20260930000003_users_integrity.sql`
- `20260930000004_access_gap_fixes.sql`
- `20260930000005_users_provisioning.sql`
- `20260930000006_column_locks.sql`
- `20260930000007_auth_user_lookup.sql`
- `20261001000001_bind_otp_challenges.sql`
- `20261001000002_harden_auth_provisioning.sql`

---

## 1. public.patients
- Defined in: `20260923000001_doctornect_schema.sql:212`
- Modified in: `20260925000001_sync_bridge_infra.sql:46, 114-120`, `20260928000003_add_profile_photos_s3_storage_fields.sql:5`, `20261001000002_harden_auth_provisioning.sql:13`

| Column | Type | Nullable | Default | Constraints |
|---|---|---|---|---|
| `patient_id` | VARCHAR(64) | NOT NULL | - | PRIMARY KEY |
| `owner_uid` | UUID | NULLABLE | `auth.uid()` | REFERENCES users(id) ON DELETE SET NULL |
| `name` | VARCHAR(255) | NOT NULL | - | |
| `email` | VARCHAR(255) | NULLABLE | - | |
| `mobile` | VARCHAR(32) | NOT NULL | - | |
| `age` | INT | NULLABLE | - | |
| `gender` | VARCHAR(16) | NULLABLE | - | CHECK (`gender IN ('Male', 'Female', 'Other')`) |
| `blood_group` | VARCHAR(8) | NULLABLE | - | |
| `height` | VARCHAR(32) | NULLABLE | - | |
| `weight` | VARCHAR(32) | NULLABLE | - | |
| `address` | TEXT | NULLABLE | - | |
| `photo_url` | TEXT | NULLABLE | - | |
| `share_records_with_doctors` | BOOLEAN | NOT NULL | `TRUE` | |
| `primary_doctor_id` | VARCHAR(64) | NULLABLE | - | REFERENCES doctors(doctor_id) ON DELETE SET NULL |
| `invited_doctor_id` | VARCHAR(64) | NULLABLE | - | REFERENCES doctors(doctor_id) ON DELETE SET NULL |
| `care_team_doctor_ids` | TEXT[] | NULLABLE | `ARRAY[]::TEXT[]` | |
| `profile_completed` | BOOLEAN | NOT NULL | `TRUE` | |
| `verified` | BOOLEAN | NOT NULL | `TRUE` | |
| `fcm_token` | TEXT | NULLABLE | - | |
| `fcm_token_updated_at` | TIMESTAMPTZ | NULLABLE | - | |
| `created_at` | TIMESTAMPTZ | NOT NULL | `CURRENT_TIMESTAMP` | |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `CURRENT_TIMESTAMP` | |
| `sync_origin` | VARCHAR(64) | NULLABLE | `'patient_supabase'` | |
| `synced_by` | VARCHAR(64) | NULLABLE | - | |
| `city` | VARCHAR(128) | NULLABLE | - | |
| `state` | VARCHAR(128) | NULLABLE | - | |
| `pincode` | VARCHAR(16) | NULLABLE | - | |
| `country` | VARCHAR(64) | NULLABLE | `'India'` | |
| `conditions` | TEXT[] | NULLABLE | `ARRAY[]::TEXT[]` | |
| `allergies` | TEXT[] | NULLABLE | `ARRAY[]::TEXT[]` | |
| `metadata` | JSONB | NULLABLE | `'{}'::jsonb` | |
| `photo_key` | TEXT | NULLABLE | - | |
| `photo_storage` | VARCHAR(32) | NULLABLE | `'legacy'` | |

---

## 2. public.doctors
- Defined in: `20260923000001_doctornect_schema.sql:98`
- Modified in: `20260928000003_add_profile_photos_s3_storage_fields.sql:19`

| Column | Type | Nullable | Default | Constraints |
|---|---|---|---|---|
| `doctor_id` | VARCHAR(64) | NOT NULL | - | PRIMARY KEY |
| `owner_uid` | UUID | NULLABLE | - | REFERENCES users(id) ON DELETE SET NULL |
| `name` | VARCHAR(255) | NOT NULL | - | |
| `email` | VARCHAR(255) | NOT NULL | - | |
| `mobile` | VARCHAR(32) | NOT NULL | - | |
| `specialization` | VARCHAR(128) | NOT NULL | - | |
| `super_specialization` | TEXT | NULLABLE | - | |
| `qualification` | VARCHAR(255) | NOT NULL | - | |
| `experience_years` | INT | NOT NULL | `1` | |
| `consultation_fee` | NUMERIC(10, 2) | NULLABLE | `0.00` | |
| `clinic_name` | VARCHAR(255) | NULLABLE | - | |
| `primary_facility_id` | VARCHAR(64) | NULLABLE | - | REFERENCES facilities(facility_id) ON DELETE SET NULL |
| `area` | VARCHAR(128) | NULLABLE | - | |
| `city` | VARCHAR(128) | NULLABLE | - | |
| `state` | VARCHAR(128) | NULLABLE | - | |
| `country` | VARCHAR(64) | NULLABLE | `'India'` | |
| `pincode` | VARCHAR(16) | NULLABLE | - | |
| `address_line1` | TEXT | NULLABLE | - | |
| `address_line2` | TEXT | NULLABLE | - | |
| `state_council` | VARCHAR(255) | NULLABLE | - | |
| `council_number` | VARCHAR(128) | NULLABLE | - | |
| `certifications` | TEXT[] | NULLABLE | `ARRAY[]::TEXT[]` | |
| `past_workplaces` | TEXT[] | NULLABLE | `ARRAY[]::TEXT[]` | |
| `memberships` | TEXT[] | NULLABLE | `ARRAY[]::TEXT[]` | |
| `awards` | TEXT[] | NULLABLE | `ARRAY[]::TEXT[]` | |
| `publications` | TEXT[] | NULLABLE | `ARRAY[]::TEXT[]` | |
| `about` | TEXT | NULLABLE | - | |
| `languages` | TEXT[] | NULLABLE | `ARRAY['English', 'Hindi']::TEXT[]` | |
| `photo_url` | TEXT | NULLABLE | - | |
| `maps_link` | TEXT | NULLABLE | - | |
| `landmark` | VARCHAR(255) | NULLABLE | - | |
| `rating` | NUMERIC(3, 2) | NOT NULL | `0.00` | |
| `review_count` | INT | NOT NULL | `0` | |
| `profile_completed` | BOOLEAN | NOT NULL | `FALSE` | |
| `verified` | BOOLEAN | NOT NULL | `FALSE` | |
| `verified_at` | TIMESTAMPTZ | NULLABLE | - | |
| `deactivated` | BOOLEAN | NOT NULL | `FALSE` | |
| `deactivated_at` | TIMESTAMPTZ | NULLABLE | - | |
| `reactivate_before` | TIMESTAMPTZ | NULLABLE | - | |
| `reactivated_at` | TIMESTAMPTZ | NULLABLE | - | |
| `fcm_token` | TEXT | NULLABLE | - | |
| `fcm_token_updated_at` | TIMESTAMPTZ | NULLABLE | - | |
| `created_at` | TIMESTAMPTZ | NOT NULL | `CURRENT_TIMESTAMP` | |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `CURRENT_TIMESTAMP` | |
| `photo_key` | TEXT | NULLABLE | - | |
| `photo_storage` | VARCHAR(32) | NULLABLE | `'legacy'` | |

---

## 3. public.labs
- Defined in: `20260923000001_doctornect_schema.sql:327`

| Column | Type | Nullable | Default | Constraints |
|---|---|---|---|---|
| `lab_id` | VARCHAR(64) | NOT NULL | - | PRIMARY KEY |
| `owner_uid` | UUID | NULLABLE | - | REFERENCES users(id) ON DELETE SET NULL |
| `lab_name` | VARCHAR(255) | NOT NULL | - | |
| `license_number` | VARCHAR(128) | NOT NULL | - | |
| `phone` | VARCHAR(32) | NOT NULL | - | |
| `email` | VARCHAR(255) | NOT NULL | - | |
| `gst_number` | VARCHAR(64) | NULLABLE | - | |
| `rating` | NUMERIC(3, 2) | NOT NULL | `0.00` | |
| `area` | VARCHAR(128) | NULLABLE | - | |
| `city` | VARCHAR(128) | NULLABLE | - | |
| `state` | VARCHAR(128) | NULLABLE | - | |
| `country` | VARCHAR(64) | NULLABLE | `'India'` | |
| `pincode` | VARCHAR(16) | NULLABLE | - | |
| `address_line1` | TEXT | NULLABLE | - | |
| `address_line2` | TEXT | NULLABLE | - | |
| `profile_completed` | BOOLEAN | NOT NULL | `FALSE` | |
| `verified` | BOOLEAN | NOT NULL | `FALSE` | |
| `verified_at` | TIMESTAMPTZ | NULLABLE | - | |
| `deactivated` | BOOLEAN | NOT NULL | `FALSE` | |
| `created_at` | TIMESTAMPTZ | NOT NULL | `CURRENT_TIMESTAMP` | |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `CURRENT_TIMESTAMP` | |

---

## 4. public.medical_stores
- Defined in: `20260923000001_doctornect_schema.sql:293`

| Column | Type | Nullable | Default | Constraints |
|---|---|---|---|---|
| `store_id` | VARCHAR(64) | NOT NULL | - | PRIMARY KEY |
| `owner_uid` | UUID | NULLABLE | - | REFERENCES users(id) ON DELETE SET NULL |
| `store_name` | VARCHAR(255) | NOT NULL | - | |
| `owner_name` | VARCHAR(255) | NOT NULL | - | |
| `drug_license_number` | VARCHAR(128) | NOT NULL | - | |
| `phone` | VARCHAR(32) | NOT NULL | - | |
| `email` | VARCHAR(255) | NOT NULL | - | |
| `gst_number` | VARCHAR(64) | NULLABLE | - | |
| `address_line1` | TEXT | NULLABLE | - | |
| `address_line2` | TEXT | NULLABLE | - | |
| `city` | VARCHAR(128) | NULLABLE | - | |
| `state` | VARCHAR(128) | NULLABLE | - | |
| `country` | VARCHAR(64) | NULLABLE | `'India'` | |
| `pincode` | VARCHAR(16) | NULLABLE | - | |
| `profile_completed` | BOOLEAN | NOT NULL | `FALSE` | |
| `verified` | BOOLEAN | NOT NULL | `FALSE` | |
| `verified_at` | TIMESTAMPTZ | NULLABLE | - | |
| `deactivated` | BOOLEAN | NOT NULL | `FALSE` | |
| `created_at` | TIMESTAMPTZ | NOT NULL | `CURRENT_TIMESTAMP` | |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `CURRENT_TIMESTAMP` | |

---

## 5. public.ambulances
- Defined in: `20260923000001_doctornect_schema.sql:376`

| Column | Type | Nullable | Default | Constraints |
|---|---|---|---|---|
| `ambulance_id` | VARCHAR(64) | NOT NULL | - | PRIMARY KEY |
| `auth_uid` | UUID | NULLABLE | - | REFERENCES users(id) ON DELETE SET NULL |
| `service_name` | VARCHAR(255) | NOT NULL | - | |
| `owner_name` | VARCHAR(255) | NULLABLE | - | |
| `driver_name` | VARCHAR(255) | NOT NULL | - | |
| `phone` | VARCHAR(32) | NOT NULL | - | |
| `vehicle_number` | VARCHAR(64) | NOT NULL | - | |
| `ambulance_type` | VARCHAR(32) | NOT NULL | - | CHECK (`ambulance_type IN ('bls', 'als', 'icu', 'patientTransport')`) |
| `username` | VARCHAR(64) | NULLABLE | - | UNIQUE |
| `city` | VARCHAR(128) | NOT NULL | - | |
| `base_address` | TEXT | NULLABLE | - | |
| `license_number` | VARCHAR(128) | NULLABLE | - | |
| `insurance_number` | VARCHAR(128) | NULLABLE | - | |
| `has_oxygen` | BOOLEAN | NOT NULL | `FALSE` | |
| `has_ventilator` | BOOLEAN | NOT NULL | `FALSE` | |
| `has_stretcher` | BOOLEAN | NOT NULL | `TRUE` | |
| `is_24x7` | BOOLEAN | NOT NULL | `FALSE` | |
| `rate_per_km` | NUMERIC(10, 2) | NULLABLE | - | |
| `total_rating` | NUMERIC(10, 2) | NOT NULL | `0.00` | |
| `rating_count` | INT | NOT NULL | `0` | |
| `is_available` | BOOLEAN | NOT NULL | `TRUE` | |
| `profile_completed` | BOOLEAN | NOT NULL | `FALSE` | |
| `verified` | BOOLEAN | NOT NULL | `FALSE` | |
| `address_line1` | TEXT | NULLABLE | - | |
| `address_line2` | TEXT | NULLABLE | - | |
| `state` | VARCHAR(128) | NULLABLE | - | |
| `country` | VARCHAR(64) | NULLABLE | `'India'` | |
| `pincode` | VARCHAR(16) | NULLABLE | - | |
| `service_areas` | TEXT[] | NULLABLE | `ARRAY[]::TEXT[]` | |
| `created_at` | TIMESTAMPTZ | NOT NULL | `CURRENT_TIMESTAMP` | |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `CURRENT_TIMESTAMP` | |

---

## 6. public.appointments
- Defined in: `20260923000001_doctornect_schema.sql:430`
- Modified in: `20260925000001_sync_bridge_infra.sql:40-41, 70-71`

| Column | Type | Nullable | Default | Constraints |
|---|---|---|---|---|
| `appointment_id` | VARCHAR(64) | NOT NULL | - | PRIMARY KEY |
| `doctor_id` | VARCHAR(64) | NOT NULL | - | REFERENCES doctors(doctor_id) ON DELETE RESTRICT |
| `patient_id` | VARCHAR(64) | NOT NULL | - | REFERENCES patients(patient_id) ON DELETE RESTRICT |
| `facility_id` | VARCHAR(64) | NULLABLE | - | REFERENCES facilities(facility_id) ON DELETE SET NULL |
| `encounter_type` | VARCHAR(32) | NOT NULL | `'opd'` | CHECK (`encounter_type IN ('opd', 'ipd', 'emergency', 'teleconsult')`) |
| `admission_id` | VARCHAR(64) | NULLABLE | - | |
| `doctor_name` | VARCHAR(255) | NOT NULL | - | |
| `specialization` | VARCHAR(128) | NOT NULL | - | |
| `patient_name` | VARCHAR(255) | NOT NULL | - | |
| `patient_age` | INT | NOT NULL | - | |
| `patient_gender` | VARCHAR(16) | NOT NULL | - | |
| `date_time` | TIMESTAMPTZ | NOT NULL | - | |
| `slot_label` | VARCHAR(32) | NOT NULL | - | |
| `token_number` | INT | NOT NULL | `0` | |
| `visit_type` | VARCHAR(32) | NOT NULL | - | CHECK (`visit_type IN ('newVisit', 'followUp', 'returning')`) |
| `patient_status` | VARCHAR(32) | NOT NULL | - | CHECK (`patient_status IN ('pending', 'confirmed', 'completed', 'cancelled')`) |
| `doctor_status` | VARCHAR(32) | NOT NULL | - | CHECK (`doctor_status IN ('pendingRequest', 'confirmed', 'inProgress', 'completed', 'cancelled', 'noShow', 'waiting')`) |
| `clinic_name` | VARCHAR(255) | NULLABLE | - | |
| `clinic_address` | TEXT | NULLABLE | - | |
| `maps_url` | TEXT | NULLABLE | - | |
| `cancellation_reason` | TEXT | NULLABLE | - | |
| `diagnosis` | TEXT | NULLABLE | - | |
| `has_prescription` | BOOLEAN | NOT NULL | `FALSE` | |
| `has_report` | BOOLEAN | NOT NULL | `FALSE` | |
| `has_review` | BOOLEAN | NOT NULL | `FALSE` | |
| `review_rating` | INT | NULLABLE | - | CHECK (`review_rating BETWEEN 1 AND 5`) |
| `review_id` | VARCHAR(128) | NULLABLE | - | |
| `review_created_at` | TIMESTAMPTZ | NULLABLE | - | |
| `clinical_notes` | TEXT | NULLABLE | - | |
| `contact_number` | VARCHAR(32) | NULLABLE | - | |
| `source` | VARCHAR(32) | NULLABLE | `'app'` | CHECK (`source IN ('app', 'walkin', 'referral')`) |
| `booked_by_name` | VARCHAR(255) | NULLABLE | - | |
| `patient_relation` | VARCHAR(64) | NULLABLE | - | |
| `slot_share_reason` | VARCHAR(128) | NULLABLE | - | |
| `was_rescheduled` | BOOLEAN | NOT NULL | `FALSE` | |
| `chief_complaints` | TEXT[] | NULLABLE | `ARRAY[]::TEXT[]` | |
| `symptoms` | TEXT[] | NULLABLE | `ARRAY[]::TEXT[]` | |
| `observations` | TEXT[] | NULLABLE | `ARRAY[]::TEXT[]` | |
| `lab_reports` | TEXT[] | NULLABLE | `ARRAY[]::TEXT[]` | |
| `created_at` | TIMESTAMPTZ | NOT NULL | `CURRENT_TIMESTAMP` | |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `CURRENT_TIMESTAMP` | |
| `sync_origin` | VARCHAR(64) | NULLABLE | `'patient_supabase'` | |
| `synced_by` | VARCHAR(64) | NULLABLE | - | |

---

## 7. public.reviews
- Defined in: `20260923000001_doctornect_schema.sql:817`
- Modified in: `20260925000001_sync_bridge_infra.sql:49-50`

| Column | Type | Nullable | Default | Constraints |
|---|---|---|---|---|
| `review_id` | VARCHAR(128) | NOT NULL | - | PRIMARY KEY |
| `patient_id` | VARCHAR(64) | NOT NULL | - | REFERENCES patients(patient_id) ON DELETE CASCADE |
| `doctor_id` | VARCHAR(64) | NOT NULL | - | REFERENCES doctors(doctor_id) ON DELETE CASCADE |
| `appointment_id` | VARCHAR(64) | NULLABLE | - | REFERENCES appointments(appointment_id) ON DELETE SET NULL |
| `patient_name` | VARCHAR(255) | NOT NULL | - | |
| `rating` | INT | NOT NULL | - | CHECK (`rating BETWEEN 1 AND 5`) |
| `comment` | TEXT | NOT NULL | - | |
| `doctor_reply` | TEXT | NULLABLE | - | |
| `helpful_count` | INT | NOT NULL | `0` | |
| `created_at` | TIMESTAMPTZ | NOT NULL | `CURRENT_TIMESTAMP` | |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `CURRENT_TIMESTAMP` | |
| `sync_origin` | VARCHAR(64) | NULLABLE | `'patient_supabase'` | |
| `synced_by` | VARCHAR(64) | NULLABLE | - | |
*(Unique constraint: `UNIQUE (patient_id, doctor_id)`)*

---

## 8. public.health_records
- Defined in: `20260923000001_doctornect_schema.sql:594`
- Modified in: `20260928000001_add_health_records_s3_storage_fields.sql:5-7`

| Column | Type | Nullable | Default | Constraints |
|---|---|---|---|---|
| `record_id` | VARCHAR(64) | NOT NULL | - | PRIMARY KEY |
| `patient_id` | VARCHAR(64) | NOT NULL | - | REFERENCES patients(patient_id) ON DELETE CASCADE |
| `facility_id` | VARCHAR(64) | NULLABLE | - | REFERENCES facilities(facility_id) ON DELETE SET NULL |
| `title` | VARCHAR(255) | NOT NULL | - | |
| `type` | VARCHAR(32) | NOT NULL | - | CHECK (`type IN ('prescription', 'labReport', 'dischargeSummary', 'vaccination', 'invoice', 'other')`) |
| `date` | TIMESTAMPTZ | NOT NULL | - | |
| `source` | VARCHAR(32) | NOT NULL | - | CHECK (`source IN ('selfUploaded', 'doctorPrescribed', 'labGenerated')`) |
| `file_name` | VARCHAR(255) | NOT NULL | - | |
| `doctor_name` | VARCHAR(255) | NULLABLE | - | |
| `lab_name` | VARCHAR(255) | NULLABLE | - | |
| `is_image` | BOOLEAN | NOT NULL | `FALSE` | |
| `notes` | TEXT | NULLABLE | - | |
| `shared_with_doctors` | BOOLEAN | NOT NULL | `FALSE` | |
| `file_storage` | VARCHAR(32) | NOT NULL | `'none'` | CHECK (`file_storage IN ('none', 'localOnly', 'cloudUploaded')`) |
| `storage_url` | TEXT | NULLABLE | - | |
| `created_at` | TIMESTAMPTZ | NOT NULL | `CURRENT_TIMESTAMP` | |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `CURRENT_TIMESTAMP` | |
| `storage_key` | TEXT | NULLABLE | - | |
| `storage_provider` | VARCHAR(32) | NULLABLE | `'legacy'` | |

---

## 9. public.prescriptions
- Defined in: `20260923000001_doctornect_schema.sql:489`
- Modified in: `20260925000001_sync_bridge_infra.sql:43-44`

| Column | Type | Nullable | Default | Constraints |
|---|---|---|---|---|
| `prescription_id` | VARCHAR(64) | NOT NULL | - | PRIMARY KEY |
| `doctor_id` | VARCHAR(64) | NOT NULL | - | REFERENCES doctors(doctor_id) ON DELETE RESTRICT |
| `patient_id` | VARCHAR(64) | NOT NULL | - | REFERENCES patients(patient_id) ON DELETE RESTRICT |
| `appointment_id` | VARCHAR(64) | NULLABLE | - | REFERENCES appointments(appointment_id) ON DELETE SET NULL |
| `facility_id` | VARCHAR(64) | NULLABLE | - | REFERENCES facilities(facility_id) ON DELETE SET NULL |
| `encounter_type` | VARCHAR(32) | NOT NULL | `'opd'` | CHECK (`encounter_type IN ('opd', 'ipd', 'emergency')`) |
| `admission_id` | VARCHAR(64) | NULLABLE | - | |
| `doctor_name` | VARCHAR(255) | NULLABLE | - | |
| `doctor_specialization` | VARCHAR(128) | NULLABLE | - | |
| `doctor_qualifications` | VARCHAR(255) | NULLABLE | - | |
| `doctor_reg_number` | VARCHAR(128) | NULLABLE | - | |
| `clinic_name` | VARCHAR(255) | NULLABLE | - | |
| `clinic_address` | TEXT | NULLABLE | - | |
| `doctor_phone` | VARCHAR(32) | NULLABLE | - | |
| `patient_name` | VARCHAR(255) | NOT NULL | - | |
| `patient_age` | INT | NOT NULL | - | |
| `patient_gender` | VARCHAR(16) | NULLABLE | - | |
| `prescription_date` | TIMESTAMPTZ | NOT NULL | `CURRENT_TIMESTAMP` | |
| `diagnosis_type` | VARCHAR(32) | NULLABLE | `'Provisional'` | CHECK (`diagnosis_type IN ('Provisional', 'Final')`) |
| `primary_diagnosis` | TEXT | NULLABLE | - | |
| `secondary_diagnosis` | TEXT | NULLABLE | - | |
| `chief_complaint` | TEXT | NULLABLE | - | |
| `symptoms` | TEXT | NULLABLE | - | |
| `symptom_duration` | VARCHAR(64) | NULLABLE | - | |
| `past_history` | TEXT | NULLABLE | - | |
| `allergies` | TEXT | NULLABLE | - | |
| `general_examination` | TEXT | NULLABLE | - | |
| `blood_pressure` | VARCHAR(32) | NULLABLE | - | |
| `temperature` | VARCHAR(32) | NULLABLE | - | |
| `pulse` | VARCHAR(32) | NULLABLE | - | |
| `spo2` | VARCHAR(32) | NULLABLE | - | |
| `weight_kg` | VARCHAR(32) | NULLABLE | - | |
| `height_cm` | VARCHAR(32) | NULLABLE | - | |
| `respiratory_rate` | VARCHAR(32) | NULLABLE | - | |
| `diet_advice` | TEXT | NULLABLE | - | |
| `activity_restrictions` | TEXT | NULLABLE | - | |
| `lifestyle_advice` | TEXT | NULLABLE | - | |
| `general_advice` | TEXT | NULLABLE | - | |
| `follow_up_note` | TEXT | NULLABLE | - | |
| `next_visit` | TIMESTAMPTZ | NULLABLE | - | |
| `created_at` | TIMESTAMPTZ | NOT NULL | `CURRENT_TIMESTAMP` | |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `CURRENT_TIMESTAMP` | |
| `sync_origin` | VARCHAR(64) | NULLABLE | `'doctor_firestore'` | |
| `synced_by` | VARCHAR(64) | NULLABLE | - | |

---

## 10. public.patient_doctor_links
- Defined in: `20260923000001_doctornect_schema.sql:255`

| Column | Type | Nullable | Default | Constraints |
|---|---|---|---|---|
| `patient_id` | VARCHAR(64) | NOT NULL | - | REFERENCES patients(patient_id) ON DELETE CASCADE, PRIMARY KEY (col 1) |
| `doctor_id` | VARCHAR(64) | NOT NULL | - | REFERENCES doctors(doctor_id) ON DELETE CASCADE, PRIMARY KEY (col 2) |
| `source` | VARCHAR(32) | NOT NULL | - | CHECK (`source IN ('appointment', 'referral', 'manual')`) |
| `from_doctor_id` | VARCHAR(64) | NULLABLE | - | REFERENCES doctors(doctor_id) ON DELETE SET NULL |
| `referral_id` | VARCHAR(64) | NULLABLE | - | |
| `created_at` | TIMESTAMPTZ | NOT NULL | `CURRENT_TIMESTAMP` | |
*(Primary Key: `PRIMARY KEY (patient_id, doctor_id)`)*

---

## 11. public.lab_bookings
- Defined in: `20260923000001_doctornect_schema.sql:625`
- Modified in: `20260928000002_add_lab_reports_s3_storage_fields.sql:5-7`

| Column | Type | Nullable | Default | Constraints |
|---|---|---|---|---|
| `booking_id` | VARCHAR(64) | NOT NULL | - | PRIMARY KEY |
| `patient_id` | VARCHAR(64) | NOT NULL | - | REFERENCES patients(patient_id) ON DELETE RESTRICT |
| `lab_id` | VARCHAR(64) | NULLABLE | - | REFERENCES labs(lab_id) ON DELETE SET NULL |
| `patient_name` | VARCHAR(255) | NOT NULL | - | |
| `patient_age` | INT | NOT NULL | - | |
| `patient_gender` | VARCHAR(16) | NULLABLE | - | |
| `contact_number` | VARCHAR(32) | NULLABLE | - | |
| `test_id` | VARCHAR(128) | NOT NULL | - | |
| `test_name` | TEXT | NOT NULL | - | |
| `test_names` | TEXT[] | NOT NULL | - | |
| `test_ids` | TEXT[] | NULLABLE | `ARRAY[]::TEXT[]` | |
| `booking_for_self` | BOOLEAN | NOT NULL | `TRUE` | |
| `family_member_id` | VARCHAR(64) | NULLABLE | - | REFERENCES family_members(member_id) ON DELETE SET NULL |
| `collection_type` | VARCHAR(32) | NOT NULL | - | CHECK (`collection_type IN ('homeCollection', 'labVisit', 'walkIn')`) |
| `partner_lab` | VARCHAR(255) | NULLABLE | - | |
| `address` | TEXT | NULLABLE | - | |
| `date_time` | TIMESTAMPTZ | NOT NULL | - | |
| `slot_label` | VARCHAR(32) | NOT NULL | - | |
| `status` | VARCHAR(32) | NOT NULL | - | CHECK (`status IN ('confirmed', 'sampleCollected', 'inAnalysis', 'completed', 'cancelled')`) |
| `source` | VARCHAR(32) | NULLABLE | `'app'` | CHECK (`source IN ('app', 'walkin')`) |
| `report_file_name` | VARCHAR(255) | NULLABLE | - | |
| `report_storage_url` | TEXT | NULLABLE | - | |
| `created_at` | TIMESTAMPTZ | NOT NULL | `CURRENT_TIMESTAMP` | |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `CURRENT_TIMESTAMP` | |
| `report_storage_key` | TEXT | NULLABLE | - | |
| `report_storage_provider` | VARCHAR(32) | NULLABLE | `'legacy'` | |

---

## 12. public.lab_orders
- Defined in: `20260923000001_doctornect_schema.sql:663`
- Modified in: `20260928000002_add_lab_reports_s3_storage_fields.sql:12-14`

| Column | Type | Nullable | Default | Constraints |
|---|---|---|---|---|
| `order_id` | VARCHAR(64) | NOT NULL | - | PRIMARY KEY |
| `doctor_id` | VARCHAR(64) | NOT NULL | - | REFERENCES doctors(doctor_id) ON DELETE RESTRICT |
| `patient_id` | VARCHAR(64) | NOT NULL | - | REFERENCES patients(patient_id) ON DELETE RESTRICT |
| `lab_id` | VARCHAR(64) | NULLABLE | - | REFERENCES labs(lab_id) ON DELETE SET NULL |
| `appointment_id` | VARCHAR(64) | NULLABLE | - | REFERENCES appointments(appointment_id) ON DELETE SET NULL |
| `facility_id` | VARCHAR(64) | NULLABLE | - | REFERENCES facilities(facility_id) ON DELETE SET NULL |
| `admission_id` | VARCHAR(64) | NULLABLE | - | |
| `doctor_name` | VARCHAR(255) | NOT NULL | - | |
| `patient_name` | VARCHAR(255) | NOT NULL | - | |
| `patient_age` | INT | NOT NULL | - | |
| `lab_name` | VARCHAR(255) | NULLABLE | - | |
| `test_ids` | TEXT[] | NOT NULL | - | |
| `test_names` | TEXT[] | NOT NULL | - | |
| `indication` | TEXT | NULLABLE | - | |
| `urgency` | VARCHAR(32) | NOT NULL | `'Routine'` | CHECK (`urgency IN ('Routine', 'Urgent', 'STAT')`) |
| `fasting_required` | BOOLEAN | NOT NULL | `FALSE` | |
| `home_collection` | BOOLEAN | NOT NULL | `FALSE` | |
| `source` | VARCHAR(32) | NOT NULL | `'investigations'` | |
| `status` | VARCHAR(32) | NOT NULL | `'ordered'` | CHECK (`status IN ('ordered', 'received', 'inProgress', 'completed', 'cancelled')`) |
| `report_file_name` | VARCHAR(255) | NULLABLE | - | |
| `report_storage_url` | TEXT | NULLABLE | - | |
| `report_submitted_at` | TIMESTAMPTZ | NULLABLE | - | |
| `created_at` | TIMESTAMPTZ | NOT NULL | `CURRENT_TIMESTAMP` | |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `CURRENT_TIMESTAMP` | |
| `report_storage_key` | TEXT | NULLABLE | - | |
| `report_storage_provider` | VARCHAR(32) | NULLABLE | `'legacy'` | |

---

## 13. public.in_app_notifications
- Defined in: `20260923000001_doctornect_schema.sql:997`

| Column | Type | Nullable | Default | Constraints |
|---|---|---|---|---|
| `notification_id` | VARCHAR(64) | NOT NULL | - | PRIMARY KEY |
| `recipient_uid` | UUID | NOT NULL | - | REFERENCES users(id) ON DELETE CASCADE |
| `title` | VARCHAR(255) | NOT NULL | - | |
| `body` | TEXT | NOT NULL | - | |
| `is_read` | BOOLEAN | NOT NULL | `FALSE` | |
| `type` | VARCHAR(32) | NOT NULL | `'system'` | |
| `target` | VARCHAR(64) | NULLABLE | - | |
| `target_id` | VARCHAR(64) | NULLABLE | - | |
| `doctor_trigger` | VARCHAR(64) | NULLABLE | - | |
| `patient_trigger` | VARCHAR(64) | NULLABLE | - | |
| `dedupe_key` | VARCHAR(128) | NULLABLE | - | |
| `created_at` | TIMESTAMPTZ | NOT NULL | `CURRENT_TIMESTAMP` | |

---

## 14. public.promoted_ads
- Defined in: `20260923000001_doctornect_schema.sql:965`
- Modified in: `20260929000001_add_promoted_ads_s3_storage_fields.sql:5-7`

| Column | Type | Nullable | Default | Constraints |
|---|---|---|---|---|
| `ad_id` | VARCHAR(64) | NOT NULL | - | PRIMARY KEY |
| `provider_type` | VARCHAR(32) | NOT NULL | - | CHECK (`provider_type IN ('doctor', 'lab', 'pharmacy', 'ambulance')`) |
| `provider_id` | VARCHAR(64) | NOT NULL | - | |
| `title` | VARCHAR(255) | NOT NULL | - | |
| `description` | TEXT | NOT NULL | - | |
| `image_url` | TEXT | NOT NULL | - | |
| `cta_label` | VARCHAR(64) | NOT NULL | `'View Details'` | |
| `duration_hours` | INT | NOT NULL | `24` | |
| `amount_paid` | NUMERIC(10, 2) | NOT NULL | `300.00` | |
| `target_city` | VARCHAR(128) | NULLABLE | - | |
| `razorpay_order_id` | VARCHAR(128) | NULLABLE | - | |
| `razorpay_payment_id` | VARCHAR(128) | NULLABLE | - | |
| `payment_status` | VARCHAR(32) | NOT NULL | `'pending'` | CHECK (`payment_status IN ('pending', 'verified', 'failed')`) |
| `status` | VARCHAR(32) | NOT NULL | `'draft'` | CHECK (`status IN ('draft', 'pending_payment', 'active', 'expired', 'rejected')`) |
| `start_time` | TIMESTAMPTZ | NULLABLE | - | |
| `end_time` | TIMESTAMPTZ | NULLABLE | - | |
| `created_at` | TIMESTAMPTZ | NOT NULL | `CURRENT_TIMESTAMP` | |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `CURRENT_TIMESTAMP` | |
| `image_key` | TEXT | NULLABLE | - | |
| `image_storage` | VARCHAR(32) | NULLABLE | `'legacy'` | |

---

## 15. private.admin_users
- Defined in: `20260930000002_admin_users_table.sql:17`

| Column | Type | Nullable | Default | Constraints |
|---|---|---|---|---|
| `user_id` | UUID | NOT NULL | - | PRIMARY KEY, REFERENCES auth.users(id) ON DELETE CASCADE |
| `granted_by` | UUID | NULLABLE | - | REFERENCES auth.users(id) ON DELETE SET NULL |
| `granted_at` | TIMESTAMPTZ | NOT NULL | `NOW()` | |
