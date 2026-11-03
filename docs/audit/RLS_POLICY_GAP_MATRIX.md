# Derived from db/migrations/*.sql (final CREATE POLICY wins per table/policyname)

| schemaname | tablename | policyname | cmd | classification | qual | with_check |
|------------|-----------|------------|-----|----------------|------|------------|
| public | abuse_rate_limits | deny_all_abuse_rate_limits | ALL | n/a |  |  |
| public | admin_audit_logs | audit_logs_deny_delete | DELETE | n/a |  |  |
| public | admin_audit_logs | audit_logs_deny_update | UPDATE | n/a |  |  |
| public | admin_audit_logs | audit_logs_insert | INSERT | n/a |  | is_super_admin() |
| public | admin_audit_logs | audit_logs_select | SELECT | n/a |  |  |
| public | ambulance_invites | amb_invites_policy | ALL | REVIEW: uses current_profile_id() | (is_verified_doctor() AND doctor_id = current_profile_id()) OR is_super_admin() | (is_verified_doctor() AND doctor_id = current_profile_id()) OR is_super_admin() |
| public | ambulance_locations | deny_all_ambulance_locations | ALL | n/a |  |  |
| public | ambulance_private_settings | ambulance_private_settings_policy | ALL | REVIEW: uses current_profile_id() | ambulance_id = current_profile_id() OR is_super_admin() | ambulance_id = current_profile_id() OR is_super_admin() |
| public | ambulance_requests | amb_requests_insert | INSERT | REVIEW: uses current_profile_id() |  | patient_id = current_profile_id() AND status = 'pending' |
| public | ambulance_trip_contacts | deny_all_ambulance_trip_contacts | ALL | n/a |  |  |
| public | ambulances | ambulances_delete | DELETE | n/a |  |  |
| public | appointments | appointments_delete | DELETE | n/a |  |  |
| public | community_lab_tests | comm_lab_insert | INSERT | REVIEW: uses current_profile_id() |  | is_verified_doctor() AND added_by_doctor_id = current_profile_id() |
| public | community_lab_tests | comm_lab_select | SELECT | n/a |  |  |
| public | community_medicines | comm_med_insert | INSERT | REVIEW: uses current_profile_id() |  | is_verified_doctor() AND added_by_doctor_id = current_profile_id() |
| public | community_medicines | comm_med_select | SELECT | n/a |  |  |
| public | doctor_education | doctor_edu_modify | ALL | REVIEW: uses current_profile_id() | doctor_id = current_profile_id() OR is_super_admin() | doctor_id = current_profile_id() OR is_super_admin() |
| public | doctor_education | doctor_edu_select | SELECT | n/a |  |  |
| public | doctor_facilities | doctor_fac_modify | ALL | REVIEW: uses current_profile_id() | doctor_id = current_profile_id() OR is_super_admin() | doctor_id = current_profile_id() OR is_super_admin() |
| public | doctor_facilities | doctor_fac_select | SELECT | n/a |  |  |
| public | doctors | doctors_delete | DELETE | n/a |  |  |
| public | health_records | health_records_write | ALL | REVIEW: uses current_profile_id() | patient_id = current_profile_id() | patient_id = current_profile_id() |
| public | in_app_notifications | notifications_deny_client_delete | DELETE | n/a |  |  |
| public | in_app_notifications | notifications_deny_client_insert | INSERT | n/a |  | FALSE |
| public | lab_bookings | lab_bookings_delete | DELETE | n/a |  |  |
| public | lab_catalog_tests | lab_catalog_select | SELECT | n/a |  |  |
| public | lab_catalog_tests | lab_catalog_write | ALL | n/a | is_super_admin() | is_super_admin() |
| public | lab_connections | lab_conn_policy | ALL | REVIEW: uses current_profile_id() | (is_verified_doctor() AND doctor_id = current_profile_id()) OR lab_id = current_profile_id() | (is_verified_doctor() AND doctor_id = current_profile_id()) OR lab_id = current_profile_id() |
| public | lab_orders | lab_orders_delete | DELETE | n/a |  |  |
| public | labs | labs_delete | DELETE | n/a |  |  |
| public | mail_queue | mail_queue_deny_client_delete | DELETE | n/a |  |  |
| public | mail_queue | mail_queue_deny_client_update | UPDATE | n/a |  |  |
| public | medical_directory | medical_directory_policy | ALL | REVIEW: uses current_profile_id() | doctor_id = current_profile_id() AND is_verified_doctor() | doctor_id = current_profile_id() AND is_verified_doctor() |
| public | medical_stores | medical_stores_delete | DELETE | n/a |  |  |
| public | otp_challenges | deny_all_otp_challenges | ALL | n/a |  |  |
| public | otp_verification_sessions | otp_sessions_deny_all | ALL | n/a |  |  |
| public | patient_care_team | care_team_modify | ALL | REVIEW: uses current_profile_id() | patient_id = current_profile_id() | patient_id = current_profile_id() |
| public | patient_care_team | care_team_select | SELECT | n/a |  |  |
| public | patient_doctor_links | doc_links_select | SELECT | n/a |  |  |
| public | patients | patients_delete | DELETE | n/a |  |  |
| public | pharmacy_connections | pharmacy_conn_policy | ALL | REVIEW: uses current_profile_id() | (is_verified_doctor() AND doctor_id = current_profile_id()) OR medical_store_id = current_profile_id() | (is_verified_doctor() AND doctor_id = current_profile_id()) OR medical_store_id = current_profile_id() |
| public | pharmacy_delivery_medicines | pharmacy_deliv_meds_policy | ALL | REVIEW: uses current_profile_id() | EXISTS ( SELECT 1 FROM pharmacy_deliveries pd WHERE pd.delivery_id = pharmacy_delivery_medicines.delivery_id AND (pd.doctor_id = current_profile_id() OR pd.store_id = current_profile_id() OR pd.patien | EXISTS ( SELECT 1 FROM pharmacy_deliveries pd WHERE pd.delivery_id = pharmacy_delivery_medicines.delivery_id AND (pd.doctor_id = current_profile_id() OR pd.store_id = current_profile_id()) ) |
| public | prescription_investigations | presc_investigations_policy | ALL | REVIEW: uses current_profile_id() | EXISTS ( SELECT 1 FROM prescriptions p WHERE p.prescription_id = prescription_investigations.prescription_id AND (p.doctor_id = current_profile_id() OR p.patient_id = current_profile_id()) ) | EXISTS ( SELECT 1 FROM prescriptions p WHERE p.prescription_id = prescription_investigations.prescription_id AND p.doctor_id = current_profile_id() AND is_verified_doctor() ) |
| public | prescription_referrals | presc_referrals_policy | ALL | REVIEW: uses current_profile_id() | EXISTS ( SELECT 1 FROM prescriptions p WHERE p.prescription_id = prescription_referrals.prescription_id AND (p.doctor_id = current_profile_id() OR p.patient_id = current_profile_id()) ) | EXISTS ( SELECT 1 FROM prescriptions p WHERE p.prescription_id = prescription_referrals.prescription_id AND p.doctor_id = current_profile_id() AND is_verified_doctor() ) |
| public | razorpay_orders | razorpay_orders_insert | INSERT | n/a |  | user_uid = (auth.jwt()->>'sub') OR public.is_super_admin(auth.jwt()->>'sub') |
| public | razorpay_orders | razorpay_orders_select | SELECT | n/a |  |  |
| public | razorpay_orders | razorpay_orders_update | UPDATE | n/a | public.is_super_admin(auth.jwt()->>'sub') | public.is_super_admin(auth.jwt()->>'sub') |
| public | razorpay_payments | razorpay_payments_select | SELECT | n/a |  |  |
| public | razorpay_webhook_events | razorpay_webhook_events_admin_select | SELECT | n/a |  |  |
| public | referrals | referrals_insert | INSERT | REVIEW: uses current_profile_id() |  | is_verified_doctor() AND from_doctor_id = current_profile_id() |
| public | review_votes | review_votes_modify | ALL | REVIEW: uses current_profile_id() | patient_id = current_profile_id() | patient_id = current_profile_id() |
| public | security_events | security_events_deny_all | ALL | n/a |  |  |
| public | super_admins | super_admins_modify | ALL | n/a | public.is_super_admin(auth.jwt()->>'sub') | public.is_super_admin(auth.jwt()->>'sub') |
| public | super_admins | super_admins_select | SELECT | n/a |  |  |
| public | users | users_insert_admin_only | INSERT | n/a |  | private.is_super_admin() |
