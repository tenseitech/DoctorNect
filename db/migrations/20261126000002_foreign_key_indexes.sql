-- DoctorNect Migration: 20261126000002_foreign_key_indexes.sql
-- Description: PROJECT_ANALYSIS.md M2. 28 foreign-key columns had no index whose first column is
-- the FK column, so joins on them and ON DELETE / FK checks on the parent (account deletion,
-- cascades) scan the whole child table. Adds a plain btree index per FK column.
-- Idempotent (IF NOT EXISTS). Plain CREATE INDEX (not CONCURRENTLY) because the migration runner
-- wraps each file in a transaction; these tables are small at this stage.

CREATE INDEX IF NOT EXISTS idx_admin_audit_logs_admin_uid_fk ON public.admin_audit_logs (admin_uid);
CREATE INDEX IF NOT EXISTS idx_ambulance_broadcasts_accepted_driver_id_fk ON public.ambulance_broadcasts (accepted_driver_id);
CREATE INDEX IF NOT EXISTS idx_ambulance_locations_driver_id_fk ON public.ambulance_locations (driver_id);
CREATE INDEX IF NOT EXISTS idx_appointments_booked_by_uid_fk ON public.appointments (booked_by_uid);
CREATE INDEX IF NOT EXISTS idx_community_body_parts_added_by_doctor_id_fk ON public.community_body_parts (added_by_doctor_id);
CREATE INDEX IF NOT EXISTS idx_community_diagnoses_added_by_doctor_id_fk ON public.community_diagnoses (added_by_doctor_id);
CREATE INDEX IF NOT EXISTS idx_community_lab_tests_added_by_doctor_id_fk ON public.community_lab_tests (added_by_doctor_id);
CREATE INDEX IF NOT EXISTS idx_community_medicines_added_by_doctor_id_fk ON public.community_medicines (added_by_doctor_id);
CREATE INDEX IF NOT EXISTS idx_community_radiology_added_by_doctor_id_fk ON public.community_radiology (added_by_doctor_id);
CREATE INDEX IF NOT EXISTS idx_doctor_invites_doctor_id_fk ON public.doctor_invites (doctor_id);
CREATE INDEX IF NOT EXISTS idx_health_records_facility_id_fk ON public.health_records (facility_id);
CREATE INDEX IF NOT EXISTS idx_lab_bookings_family_member_id_fk ON public.lab_bookings (family_member_id);
CREATE INDEX IF NOT EXISTS idx_lab_orders_appointment_id_fk ON public.lab_orders (appointment_id);
CREATE INDEX IF NOT EXISTS idx_lab_orders_facility_id_fk ON public.lab_orders (facility_id);
CREATE INDEX IF NOT EXISTS idx_patient_doctor_links_doctor_id_fk ON public.patient_doctor_links (doctor_id);
CREATE INDEX IF NOT EXISTS idx_patient_doctor_links_from_doctor_id_fk ON public.patient_doctor_links (from_doctor_id);
CREATE INDEX IF NOT EXISTS idx_pharmacy_deliveries_doctor_id_fk ON public.pharmacy_deliveries (doctor_id);
CREATE INDEX IF NOT EXISTS idx_pharmacy_doctor_invites_store_id_fk ON public.pharmacy_doctor_invites (store_id);
CREATE INDEX IF NOT EXISTS idx_prescription_referrals_to_doctor_id_fk ON public.prescription_referrals (to_doctor_id);
CREATE INDEX IF NOT EXISTS idx_referrals_appointment_id_fk ON public.referrals (appointment_id);
CREATE INDEX IF NOT EXISTS idx_review_votes_patient_id_fk ON public.review_votes (patient_id);
CREATE INDEX IF NOT EXISTS idx_reviews_appointment_id_fk ON public.reviews (appointment_id);
CREATE INDEX IF NOT EXISTS idx_security_events_uid_fk ON public.security_events (uid);
CREATE INDEX IF NOT EXISTS idx_support_tickets_ambulance_id_fk ON public.support_tickets (ambulance_id);
CREATE INDEX IF NOT EXISTS idx_support_tickets_doctor_id_fk ON public.support_tickets (doctor_id);
CREATE INDEX IF NOT EXISTS idx_support_tickets_lab_id_fk ON public.support_tickets (lab_id);
CREATE INDEX IF NOT EXISTS idx_support_tickets_store_id_fk ON public.support_tickets (store_id);
CREATE INDEX IF NOT EXISTS idx_support_tickets_user_id_fk ON public.support_tickets (user_id);
