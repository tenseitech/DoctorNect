# Part C — Production RDS security findings (read-only)

Generated: 2026-11-23T10:26:50.077Z

## Priority: tables without RLS enabled

| Schema | Table | Data class | Risk |
|--------|-------|------------|------|
| public | _schema_migrations | system/migration | Low — ledger/meta |

## RLS enabled but not FORCE

- `private.admin_users` — application/other
- `private.provisioning_errors` — application/other
- `public.doctor_directory_updates` — config/directory
- `public.doctor_invites` — application/other
- `public.doctor_private` — application/other
- `public.pharmacy_doctor_invites` — application/other
- `public.storage_audit_logs` — security/ops
- `public.user_devices` — application/other
- `public.users` — application/other

## Policies (PUBLIC role, ALL cmd, or USING/WITH CHECK containing true)

- **public.abuse_rate_limits** · `deny_all_abuse_rate_limits` · cmd=ALL · roles={anon,authenticated}
  - USING: `false`
- **public.admin_audit_logs** · `admin_audit_logs_insert_service` · cmd=INSERT · roles={service_role}
  - USING: ``
  - WITH CHECK: `true`
- **public.ambulance_invites** · `amb_invites_write` · cmd=ALL · roles={authenticated}
  - USING: `(((doctor_id)::text = private.current_profile_id()) OR private.is_super_admin())`
  - WITH CHECK: `(((doctor_id)::text = private.current_profile_id()) OR private.is_super_admin())`
- **public.ambulance_locations** · `deny_all_ambulance_locations` · cmd=ALL · roles={anon,authenticated}
  - USING: `false`
- **public.ambulance_private_settings** · `ambulance_private_settings_access` · cmd=ALL · roles={authenticated}
  - USING: `(EXISTS ( SELECT 1
   FROM ambulances a
  WHERE (((a.ambulance_id)::text = (ambulance_private_settings.ambulance_id)::text) AND ((a.auth_uid = (auth.jwt() ->> 'sub'::text)) OR private.is_super_admin()))))`
  - WITH CHECK: `(EXISTS ( SELECT 1
   FROM ambulances a
  WHERE (((a.ambulance_id)::text = (ambulance_private_settings.ambulance_id)::text) AND ((a.auth_uid = (auth.jwt() ->> 'sub'::text)) OR private.is_super_admin()))))`
- **public.ambulance_trip_contacts** · `deny_all_ambulance_trip_contacts` · cmd=ALL · roles={anon,authenticated}
  - USING: `false`
- **public.ambulances** · `ambulances_select` · cmd=SELECT · roles={authenticated}
  - USING: `((private.current_firebase_uid() IS NOT NULL) AND ((auth_uid = private.current_user_id()) OR ((is_available = true) AND (verified = true)) OR private.is_super_admin()))`
- **public.community_body_parts** · `comm_body_select` · cmd=SELECT · roles={authenticated}
  - USING: `true`
- **public.community_diagnoses** · `comm_diag_select` · cmd=SELECT · roles={authenticated}
  - USING: `true`
- **public.community_lab_tests** · `comm_tests_select` · cmd=SELECT · roles={authenticated}
  - USING: `true`
- **public.community_medicines** · `comm_meds_select` · cmd=SELECT · roles={authenticated}
  - USING: `true`
- **public.community_radiology** · `comm_rad_select` · cmd=SELECT · roles={authenticated}
  - USING: `true`
- **public.doctor_availability** · `doc_avail_select` · cmd=SELECT · roles={authenticated}
  - USING: `true`
- **public.doctor_availability** · `doc_avail_write` · cmd=ALL · roles={authenticated}
  - USING: `(((doctor_id)::text = private.current_profile_id()) OR private.is_super_admin())`
  - WITH CHECK: `(((doctor_id)::text = private.current_profile_id()) OR private.is_super_admin())`
- **public.doctor_blocked_dates** · `doc_blocked_select` · cmd=SELECT · roles={authenticated}
  - USING: `true`
- **public.doctor_blocked_dates** · `doc_blocked_write` · cmd=ALL · roles={authenticated}
  - USING: `(((doctor_id)::text = private.current_profile_id()) OR private.is_super_admin())`
  - WITH CHECK: `(((doctor_id)::text = private.current_profile_id()) OR private.is_super_admin())`
- **public.doctor_directory_updates** · `doctor_directory_updates_select` · cmd=SELECT · roles={authenticated}
  - USING: `true`
- **public.doctor_education** · `doc_education_select` · cmd=SELECT · roles={authenticated}
  - USING: `true`
- **public.doctor_education** · `doc_education_write` · cmd=ALL · roles={authenticated}
  - USING: `(((doctor_id)::text = private.current_profile_id()) OR private.is_super_admin())`
  - WITH CHECK: `(((doctor_id)::text = private.current_profile_id()) OR private.is_super_admin())`
- **public.doctor_facilities** · `doc_facilities_select` · cmd=SELECT · roles={authenticated}
  - USING: `true`
- **public.doctor_facilities** · `doc_facilities_write` · cmd=ALL · roles={authenticated}
  - USING: `(((doctor_id)::text = private.current_profile_id()) OR private.is_super_admin())`
  - WITH CHECK: `(((doctor_id)::text = private.current_profile_id()) OR private.is_super_admin())`
- **public.doctors** · `doctors_select_directory_definer` · cmd=SELECT · roles={doctornect_admin,rds_master}
  - USING: `((verified IS TRUE) AND (deactivated IS FALSE))`
- **public.facilities** · `facilities_select_auth` · cmd=SELECT · roles={authenticated}
  - USING: `true`
- **public.facilities** · `facilities_write_admin` · cmd=ALL · roles={authenticated}
  - USING: `private.is_super_admin()`
  - WITH CHECK: `private.is_super_admin()`
- **public.family_members** · `family_members_owner` · cmd=ALL · roles={authenticated}
  - USING: `(EXISTS ( SELECT 1
   FROM patients p
  WHERE (((p.patient_id)::text = (family_members.patient_id)::text) AND ((p.owner_uid = (auth.jwt() ->> 'sub'::text)) OR private.is_super_admin()))))`
  - WITH CHECK: `(EXISTS ( SELECT 1
   FROM patients p
  WHERE (((p.patient_id)::text = (family_members.patient_id)::text) AND ((p.owner_uid = (auth.jwt() ->> 'sub'::text)) OR private.is_super_admin()))))`
- **public.health_records** · `health_records_select` · cmd=SELECT · roles={authenticated}
  - USING: `(((patient_id)::text = private.current_profile_id()) OR (private.doctor_can_access_patient((patient_id)::text) AND ((shared_with_doctors = true) OR ((source)::text = 'doctorPrescribed'::text))) OR private.is_super_admin())`
- **public.lab_catalog_tests** · `lab_catalog_tests_select` · cmd=SELECT · roles={anon,authenticated}
  - USING: `true`
- **public.lab_catalog_tests** · `lab_catalog_tests_write` · cmd=ALL · roles={authenticated}
  - USING: `private.is_super_admin()`
  - WITH CHECK: `private.is_super_admin()`
- **public.lab_connections** · `lab_connections_write` · cmd=ALL · roles={authenticated}
  - USING: `(((doctor_id)::text = private.current_profile_id()) OR ((lab_id)::text = private.current_profile_id()) OR private.is_super_admin())`
  - WITH CHECK: `(((doctor_id)::text = private.current_profile_id()) OR ((lab_id)::text = private.current_profile_id()) OR private.is_super_admin())`
- **public.labs** · `labs_select` · cmd=SELECT · roles={authenticated}
  - USING: `((private.current_firebase_uid() IS NOT NULL) AND ((verified = true) OR (owner_uid = private.current_user_id()) OR private.is_super_admin()))`
- **public.medical_directory** · `med_directory_write` · cmd=ALL · roles={authenticated}
  - USING: `(((doctor_id)::text = private.current_profile_id()) OR private.is_super_admin())`
  - WITH CHECK: `(((doctor_id)::text = private.current_profile_id()) OR private.is_super_admin())`
- **public.medical_directory** · `medical_directory_select` · cmd=SELECT · roles={authenticated}
  - USING: `true`
- **public.medical_stores** · `medical_stores_select` · cmd=SELECT · roles={authenticated}
  - USING: `((private.current_firebase_uid() IS NOT NULL) AND ((verified = true) OR (owner_uid = private.current_user_id()) OR private.is_super_admin()))`
- **public.notification_outbox** · `notification_outbox_service_all` · cmd=ALL · roles={service_role}
  - USING: `true`
  - WITH CHECK: `true`
- **public.otp_challenges** · `deny_all_otp_challenges` · cmd=ALL · roles={anon,authenticated}
  - USING: `false`
- **public.patient_care_team** · `patient_care_team_write` · cmd=ALL · roles={authenticated}
  - USING: `(EXISTS ( SELECT 1
   FROM patients p
  WHERE (((p.patient_id)::text = (patient_care_team.patient_id)::text) AND ((p.owner_uid = (auth.jwt() ->> 'sub'::text)) OR private.is_super_admin()))))`
  - WITH CHECK: `(EXISTS ( SELECT 1
   FROM patients p
  WHERE (((p.patient_id)::text = (patient_care_team.patient_id)::text) AND ((p.owner_uid = (auth.jwt() ->> 'sub'::text)) OR private.is_super_admin()))))`
- **public.pharmacy_connections** · `pharmacy_connections_write` · cmd=ALL · roles={authenticated}
  - USING: `(((doctor_id)::text = private.current_profile_id()) OR ((medical_store_id)::text = private.current_profile_id()) OR private.is_super_admin())`
  - WITH CHECK: `(((doctor_id)::text = private.current_profile_id()) OR ((medical_store_id)::text = private.current_profile_id()) OR private.is_super_admin())`
- **public.pharmacy_delivery_medicines** · `pharmacy_delivery_meds_write` · cmd=ALL · roles={authenticated}
  - USING: `(EXISTS ( SELECT 1
   FROM pharmacy_deliveries pd
  WHERE (((pd.delivery_id)::text = (pharmacy_delivery_medicines.delivery_id)::text) AND (((pd.store_id)::text = private.current_profile_id()) OR private.is_super_admin()))))`
  - WITH CHECK: `(EXISTS ( SELECT 1
   FROM pharmacy_deliveries pd
  WHERE (((pd.delivery_id)::text = (pharmacy_delivery_medicines.delivery_id)::text) AND (((pd.store_id)::text = private.current_profile_id()) OR private.is_super_admin()))))`
- **public.prescription_investigations** · `presc_inv_write` · cmd=ALL · roles={authenticated}
  - USING: `(EXISTS ( SELECT 1
   FROM prescriptions p
  WHERE (((p.prescription_id)::text = (prescription_investigations.prescription_id)::text) AND (((p.doctor_id)::text = private.current_profile_id()) OR private.is_super_admin()))))`
  - WITH CHECK: `(EXISTS ( SELECT 1
   FROM prescriptions p
  WHERE (((p.prescription_id)::text = (prescription_investigations.prescription_id)::text) AND (((p.doctor_id)::text = private.current_profile_id()) OR private.is_super_admin()))))`
- **public.prescription_medicines** · `presc_meds_write` · cmd=ALL · roles={authenticated}
  - USING: `(EXISTS ( SELECT 1
   FROM prescriptions p
  WHERE (((p.prescription_id)::text = (prescription_medicines.prescription_id)::text) AND (((p.doctor_id)::text = private.current_profile_id()) OR private.is_super_admin()))))`
  - WITH CHECK: `(EXISTS ( SELECT 1
   FROM prescriptions p
  WHERE (((p.prescription_id)::text = (prescription_medicines.prescription_id)::text) AND (((p.doctor_id)::text = private.current_profile_id()) OR private.is_super_admin()))))`
- **public.prescription_referrals** · `presc_ref_write` · cmd=ALL · roles={authenticated}
  - USING: `(EXISTS ( SELECT 1
   FROM prescriptions p
  WHERE (((p.prescription_id)::text = (prescription_referrals.prescription_id)::text) AND (((p.doctor_id)::text = private.current_profile_id()) OR private.is_super_admin()))))`
  - WITH CHECK: `(EXISTS ( SELECT 1
   FROM prescriptions p
  WHERE (((p.prescription_id)::text = (prescription_referrals.prescription_id)::text) AND (((p.doctor_id)::text = private.current_profile_id()) OR private.is_super_admin()))))`
- **public.promoted_ads** · `promoted_ads_write` · cmd=ALL · roles={authenticated}
  - USING: `(((provider_id)::text = (auth.jwt() ->> 'sub'::text)) OR ((provider_id)::text = private.current_profile_id()) OR is_super_admin((auth.jwt() ->> 'sub'::text)))`
  - WITH CHECK: `(((provider_id)::text = (auth.jwt() ->> 'sub'::text)) OR ((provider_id)::text = private.current_profile_id()) OR is_super_admin((auth.jwt() ->> 'sub'::text)))`
- **public.referrals** · `referrals_write` · cmd=ALL · roles={authenticated}
  - USING: `(((from_doctor_id)::text = private.current_profile_id()) OR ((to_doctor_id)::text = private.current_profile_id()) OR private.is_super_admin())`
  - WITH CHECK: `(((from_doctor_id)::text = private.current_profile_id()) OR ((to_doctor_id)::text = private.current_profile_id()) OR private.is_super_admin())`
- **public.review_public** · `review_public_deny_client_write` · cmd=ALL · roles={authenticated}
  - USING: `false`
  - WITH CHECK: `false`
- **public.review_public** · `review_public_select_authenticated` · cmd=SELECT · roles={authenticated}
  - USING: `true`
- **public.review_votes** · `review_votes_select` · cmd=SELECT · roles={authenticated}
  - USING: `true`
- **public.review_votes** · `review_votes_write` · cmd=ALL · roles={authenticated}
  - USING: `(((patient_id)::text = private.current_profile_id()) OR private.is_super_admin())`
  - WITH CHECK: `(((patient_id)::text = private.current_profile_id()) OR private.is_super_admin())`
- **public.super_admins** · `super_admins_modify` · cmd=ALL · roles={authenticated}
  - USING: `is_super_admin((auth.jwt() ->> 'sub'::text))`
  - WITH CHECK: `is_super_admin((auth.jwt() ->> 'sub'::text))`
- **public.system_config** · `system_config_write` · cmd=ALL · roles={authenticated}
  - USING: `private.is_super_admin()`
  - WITH CHECK: `private.is_super_admin()`

## Grants to anon or PUBLIC

_No anon/PUBLIC table grants on health table names in scope._

### All anon/PUBLIC grants

- `public.doctor_directory` → anon SELECT
- `public.lab_catalog_tests` → anon SELECT
- `public.review_public` → anon SELECT
- `public.system_config` → anon SELECT

## SECURITY DEFINER without search_path

_None._

## SECURITY DEFINER EXECUTE granted to anon/PUBLIC

- `public.doctor_directory_rows` roles={anon,authenticated,doctornect_admin,service_role}

## Patient / isolation policy trace (logic only)

- **ambulance_requests** · `amb_requests_select` · SELECT · roles={authenticated}
  - Expression: `(((driver_id)::text = private.current_profile_id()) OR ((patient_id)::text = private.current_profile_id()) OR private.is_super_admin())`
  - Owner/UID check inferred: **yes**
- **ambulance_requests** · `amb_requests_update` · UPDATE · roles={authenticated}
  - Expression: `(((driver_id)::text = private.current_profile_id()) OR private.is_super_admin())`
  - Owner/UID check inferred: **yes**
- **appointments** · `appointments_delete_admin` · DELETE · roles={authenticated}
  - Expression: `private.is_super_admin()`
  - Owner/UID check inferred: **yes**
- **appointments** · `appointments_insert` · INSERT · roles={authenticated}
  - Expression: `(none)`
  - Owner/UID check inferred: **yes**
- **appointments** · `appointments_select` · SELECT · roles={authenticated}
  - Expression: `(((patient_id)::text = private.current_profile_id()) OR ((doctor_id)::text = private.current_profile_id()) OR (EXISTS ( SELECT 1
   FROM patients p
  WHERE (((p.patient_id)::text = (appointments.patient_id)::text) AND (p.owner_uid = (auth.jwt() ->> 'sub'::text))))) OR (EXISTS ( SELECT 1
   FROM fami`
  - Owner/UID check inferred: **yes**
- **appointments** · `appointments_update` · UPDATE · roles={authenticated}
  - Expression: `(((patient_id)::text = private.current_profile_id()) OR ((doctor_id)::text = private.current_profile_id()) OR (EXISTS ( SELECT 1
   FROM patients p
  WHERE (((p.patient_id)::text = (appointments.patient_id)::text) AND (p.owner_uid = private.current_firebase_uid())))) OR (EXISTS ( SELECT 1
   FROM fa`
  - Owner/UID check inferred: **yes**
- **family_members** · `family_members_owner` · ALL · roles={authenticated}
  - Expression: `(EXISTS ( SELECT 1
   FROM patients p
  WHERE (((p.patient_id)::text = (family_members.patient_id)::text) AND ((p.owner_uid = (auth.jwt() ->> 'sub'::text)) OR private.is_super_admin()))))`
  - Owner/UID check inferred: **yes**
- **health_records** · `health_records_delete` · DELETE · roles={authenticated}
  - Expression: `(((patient_id)::text = private.current_profile_id()) OR private.is_super_admin())`
  - Owner/UID check inferred: **yes**
- **health_records** · `health_records_insert` · INSERT · roles={authenticated}
  - Expression: `(none)`
  - Owner/UID check inferred: **yes**
- **health_records** · `health_records_select` · SELECT · roles={authenticated}
  - Expression: `(((patient_id)::text = private.current_profile_id()) OR (private.doctor_can_access_patient((patient_id)::text) AND ((shared_with_doctors = true) OR ((source)::text = 'doctorPrescribed'::text))) OR private.is_super_admin())`
  - Owner/UID check inferred: **yes**
- **health_records** · `health_records_update` · UPDATE · roles={authenticated}
  - Expression: `(((patient_id)::text = private.current_profile_id()) OR private.is_super_admin())`
  - Owner/UID check inferred: **yes**
- **lab_orders** · `lab_orders_insert` · INSERT · roles={authenticated}
  - Expression: `(none)`
  - Owner/UID check inferred: **yes**
- **lab_orders** · `lab_orders_select` · SELECT · roles={authenticated}
  - Expression: `(((doctor_id)::text = private.current_profile_id()) OR ((patient_id)::text = private.current_profile_id()) OR ((lab_id)::text = private.current_profile_id()) OR private.is_super_admin())`
  - Owner/UID check inferred: **yes**
- **lab_orders** · `lab_orders_update` · UPDATE · roles={authenticated}
  - Expression: `(((lab_id)::text = private.current_profile_id()) OR ((doctor_id)::text = private.current_profile_id()) OR private.is_super_admin())`
  - Owner/UID check inferred: **yes**
- **patient_doctor_links** · `pdl_select` · SELECT · roles={authenticated}
  - Expression: `(((doctor_id)::text = private.current_profile_id()) OR (EXISTS ( SELECT 1
   FROM patients p
  WHERE (((p.patient_id)::text = (patient_doctor_links.patient_id)::text) AND (p.owner_uid = (auth.jwt() ->> 'sub'::text))))) OR private.is_super_admin())`
  - Owner/UID check inferred: **yes**
- **patients** · `patients_delete_admin` · DELETE · roles={authenticated}
  - Expression: `private.is_super_admin()`
  - Owner/UID check inferred: **yes**
- **patients** · `patients_insert` · INSERT · roles={authenticated}
  - Expression: `(none)`
  - Owner/UID check inferred: **yes**
- **patients** · `patients_select` · SELECT · roles={authenticated}
  - Expression: `((owner_uid = (auth.jwt() ->> 'sub'::text)) OR ((patient_id)::text = private.current_profile_id()) OR private.is_super_admin() OR private.doctor_can_access_patient((patient_id)::text))`
  - Owner/UID check inferred: **yes**
- **patients** · `patients_update` · UPDATE · roles={authenticated}
  - Expression: `((owner_uid = (auth.jwt() ->> 'sub'::text)) OR ((patient_id)::text = private.current_profile_id()) OR private.is_super_admin())`
  - Owner/UID check inferred: **yes**
- **prescriptions** · `prescriptions_delete_admin` · DELETE · roles={authenticated}
  - Expression: `private.is_super_admin()`
  - Owner/UID check inferred: **yes**
- **prescriptions** · `prescriptions_insert` · INSERT · roles={authenticated}
  - Expression: `(none)`
  - Owner/UID check inferred: **yes**
- **prescriptions** · `prescriptions_select` · SELECT · roles={authenticated}
  - Expression: `(((patient_id)::text = private.current_profile_id()) OR ((doctor_id)::text = private.current_profile_id()) OR (EXISTS ( SELECT 1
   FROM pharmacy_deliveries pd
  WHERE (((pd.prescription_id)::text = (prescriptions.prescription_id)::text) AND (((pd.store_id)::text = private.current_profile_id()) OR (`
  - Owner/UID check inferred: **yes**
- **prescriptions** · `prescriptions_update` · UPDATE · roles={authenticated}
  - Expression: `((((doctor_id)::text = private.current_profile_id()) AND private.is_verified_doctor()) OR private.is_super_admin())`
  - Owner/UID check inferred: **yes**
- **users** · `users_delete_admin` · DELETE · roles={authenticated}
  - Expression: `(private.is_super_admin() AND (NOT private.is_system_admin_user(id)))`
  - Owner/UID check inferred: **yes**
- **users** · `users_insert_self_or_admin` · INSERT · roles={authenticated}
  - Expression: `(none)`
  - Owner/UID check inferred: **yes**
- **users** · `users_select_owner_or_admin` · SELECT · roles={authenticated}
  - Expression: `((id = (auth.jwt() ->> 'sub'::text)) OR private.is_super_admin())`
  - Owner/UID check inferred: **yes**
- **users** · `users_update_owner_or_admin` · UPDATE · roles={authenticated}
  - Expression: `((id = (auth.jwt() ->> 'sub'::text)) OR private.is_super_admin())`
  - Owner/UID check inferred: **yes**

## Findings summary

| ID | Severity | Issue | Evidence |
|----|----------|-------|----------|
| PC-01 | Medium | 9 tables RLS not FORCE | **Deferred (Phase 2):** `db/migrations/deferred/20261123101500_security_hardening_force_rls.sql` — apply after **staging RLS harness pass** + definer/`users`/`admin_users` recursion plan (`20261103000007`) |
| PC-02 | Info | pg_cron PUBLIC ALL policies | cron.job* USING username=CURRENT_USER |
| PC-03 | Medium | No RLS on public._schema_migrations | catalog query |