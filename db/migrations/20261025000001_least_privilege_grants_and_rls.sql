-- ==============================================================================
-- Migration: 20261025000001_least_privilege_grants_and_rls.sql
-- Description: Least-privilege role permissions and RLS enforcement for DoctorNect.
-- Replaces blanket GRANTs with granular, per-table, per-operation grants based on
-- actual Flutter client and Cloud Function usage.
-- Author: Gravitas Engine
-- DO NOT APPLY TO PRODUCTION WITHOUT OPERATOR CONFIRMATION.
-- ==============================================================================

-- 1. Ensure RLS is active on internal tables and add explicit deny policies for public/anon
ALTER TABLE IF EXISTS public.abuse_rate_limits ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.ambulance_locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.ambulance_trip_contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.otp_challenges ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'deny_all_abuse_rate_limits' AND polrelid = 'public.abuse_rate_limits'::regclass) THEN
    CREATE POLICY deny_all_abuse_rate_limits ON public.abuse_rate_limits FOR ALL TO anon, authenticated USING (false);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'deny_all_ambulance_locations' AND polrelid = 'public.ambulance_locations'::regclass) THEN
    CREATE POLICY deny_all_ambulance_locations ON public.ambulance_locations FOR ALL TO anon, authenticated USING (false);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'deny_all_ambulance_trip_contacts' AND polrelid = 'public.ambulance_trip_contacts'::regclass) THEN
    CREATE POLICY deny_all_ambulance_trip_contacts ON public.ambulance_trip_contacts FOR ALL TO anon, authenticated USING (false);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polname = 'deny_all_otp_challenges' AND polrelid = 'public.otp_challenges'::regclass) THEN
    CREATE POLICY deny_all_otp_challenges ON public.otp_challenges FOR ALL TO anon, authenticated USING (false);
  END IF;
END $$;

-- 1.1 Enforce Role-Verification on Provider Table Inserts (Prevent Role Escalation)
DROP POLICY IF EXISTS doctors_insert ON public.doctors;
CREATE POLICY doctors_insert ON public.doctors
  FOR INSERT TO authenticated
  WITH CHECK (
    ((owner_uid = (auth.jwt() ->> 'sub')) AND (verified = false) AND ((auth.jwt() ->> 'app_role' = 'doctor') OR (auth.jwt() ->> 'user_role' = 'doctor')))
    OR private.is_super_admin()
  );

DROP POLICY IF EXISTS medical_stores_insert ON public.medical_stores;
CREATE POLICY medical_stores_insert ON public.medical_stores
  FOR INSERT TO authenticated
  WITH CHECK (
    ((owner_uid = (auth.jwt() ->> 'sub')) AND ((auth.jwt() ->> 'app_role' IN ('pharmacy', 'medicalStore')) OR (auth.jwt() ->> 'user_role' IN ('pharmacy', 'medicalStore'))))
    OR private.is_super_admin()
  );

DROP POLICY IF EXISTS labs_insert ON public.labs;
CREATE POLICY labs_insert ON public.labs
  FOR INSERT TO authenticated
  WITH CHECK (
    ((owner_uid = (auth.jwt() ->> 'sub')) AND ((auth.jwt() ->> 'app_role' = 'lab') OR (auth.jwt() ->> 'user_role' = 'lab')))
    OR private.is_super_admin()
  );

DROP POLICY IF EXISTS ambulances_insert ON public.ambulances;
CREATE POLICY ambulances_insert ON public.ambulances
  FOR INSERT TO authenticated
  WITH CHECK (
    ((auth_uid = (auth.jwt() ->> 'sub')) AND ((auth.jwt() ->> 'app_role' = 'ambulance') OR (auth.jwt() ->> 'user_role' = 'ambulance')))
    OR private.is_super_admin()
  );

-- 1.2 Harden patient_safe View: Enforce caller RLS by setting security_invoker = true
-- This ensures that querying public.patient_safe strictly executes under the calling user's
-- identity and evaluates public.patients RLS (preventing unauthorized cross-patient data exposure).
DROP VIEW IF EXISTS public.patient_safe;
CREATE VIEW public.patient_safe
WITH (security_invoker = true)
AS
SELECT
    patient_id,
    name,
    age,
    gender,
    blood_group,
    height,
    weight,
    address,
    photo_url,
    share_records_with_doctors,
    primary_doctor_id,
    invited_doctor_id,
    care_team_doctor_ids,
    profile_completed,
    verified,
    created_at,
    updated_at,
    photo_updated_at
FROM public.patients;

ALTER VIEW public.patient_safe OWNER TO postgres;
REVOKE ALL ON public.patient_safe FROM PUBLIC, anon;
GRANT SELECT ON public.patient_safe TO authenticated, service_role;

-- 2. Strip existing blanket permissions from anon and authenticated across public schema
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon, authenticated;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM anon, authenticated;
REVOKE ALL ON ALL ROUTINES IN SCHEMA public FROM anon, authenticated;

-- 3. Grant schema usage
GRANT USAGE ON SCHEMA public TO anon, authenticated;

-- 4. Grant least-privilege READ-ONLY access to 'anon' for unauthenticated discovery views
-- Written Security Justification for remaining 'anon' grants:
-- 1. doctor_directory:
--    - Explicitly filtered: WHERE verified = TRUE AND deactivated = FALSE.
--    - Contains ONLY public professional directory info (name, clinic, specialization, fee, rating, city).
--    - Deliberately EXCLUDES sensitive PII (mobile, email, registration council number,
--      registration certificates, owner_uid, bank details, and FCM tokens).
--    - Necessary so prospective patients on the web/mobile app landing page can search and view doctors before creating an account.
-- 2. review_public:
--    - Contains aggregated public feedback (rating, review text, doctor_id, reviewer first name).
--    - Populated exclusively by server triggers; excludes private user identifiers.
-- 3. system_config:
--    - Public platform configuration flags (supported cities, client app min-version, terms URLs).
-- 4. promoted_ads:
--    - Public verified banner advertisements for healthcare services.
-- 5. medical_directory:
--    - Public listing of verified healthcare facilities and clinics.
GRANT SELECT ON public.doctor_directory TO anon;
GRANT SELECT ON public.review_public TO anon;
GRANT SELECT ON public.system_config TO anon;
GRANT SELECT ON public.promoted_ads TO anon;
GRANT SELECT ON public.medical_directory TO anon;

-- 5. Grant least-privilege operations to 'authenticated' based on client application inventory

-- 5.1 Identity & User Profiles
GRANT SELECT, INSERT, UPDATE ON public.users TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.user_devices TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.patients TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.doctors TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.pharmacies TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.medical_stores TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.labs TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.ambulances TO authenticated;

-- 5.2 Doctor Module & Availability
GRANT SELECT, INSERT, UPDATE, DELETE ON public.doctor_availability TO authenticated;
GRANT SELECT, INSERT, DELETE ON public.doctor_blocked_dates TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.doctor_education TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.doctor_facilities TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.medical_directory TO authenticated;
GRANT SELECT ON public.doctor_directory TO authenticated;
GRANT SELECT ON public.doctor_private TO authenticated;

-- 5.3 Appointments & Prescriptions
GRANT SELECT, INSERT, UPDATE ON public.appointments TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.prescriptions TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.prescription_medicines TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.prescription_investigations TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.prescription_referrals TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.referrals TO authenticated;

-- 5.4 Patient Health Records & Family
GRANT SELECT, INSERT, UPDATE, DELETE ON public.family_members TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.health_records TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.patient_doctor_links TO authenticated;
GRANT SELECT ON public.patient_safe TO authenticated;

-- 5.5 Pharmacy & Deliveries
GRANT SELECT, INSERT, UPDATE ON public.pharmacy_connections TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.pharmacy_deliveries TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.pharmacy_delivery_medicines TO authenticated;

-- 5.6 Lab Orders & Diagnostics
GRANT SELECT, INSERT, UPDATE ON public.lab_bookings TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.lab_orders TO authenticated;
GRANT SELECT ON public.lab_catalog_tests TO authenticated;
GRANT SELECT ON public.lab_connections TO authenticated;

-- 5.7 Ambulance Module
GRANT SELECT, INSERT, UPDATE ON public.ambulance_broadcasts TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.ambulance_requests TO authenticated;
GRANT SELECT, INSERT ON public.ambulance_location_updates TO authenticated;

-- 5.8 Reviews
GRANT SELECT, INSERT, UPDATE ON public.reviews TO authenticated;
GRANT SELECT ON public.review_public TO authenticated;
GRANT SELECT, INSERT, DELETE ON public.review_votes TO authenticated;

-- 5.9 Support Tickets & Notifications
GRANT SELECT, INSERT ON public.support_tickets TO authenticated;
GRANT SELECT, INSERT ON public.support_ticket_messages TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.in_app_notifications TO authenticated;

-- 5.10 Community Clinical Knowledge & Promoted Ads & Config
GRANT SELECT, INSERT ON public.community_diagnoses TO authenticated;
GRANT SELECT ON public.community_lab_tests TO authenticated;
GRANT SELECT ON public.community_radiology TO authenticated;
GRANT SELECT ON public.community_body_parts TO authenticated;
GRANT SELECT ON public.community_medicines TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.promoted_ads TO authenticated;
GRANT SELECT ON public.system_config TO authenticated;

-- 5.11 Sequences required for client-inserted tables
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO authenticated;

-- 6. Replace reschedule_appointment_atomic with strict caller identity and ownership validation
CREATE OR REPLACE FUNCTION public.reschedule_appointment_atomic(
    p_appointment_id VARCHAR(64),
    p_doctor_id VARCHAR(64),
    p_new_date DATE,
    p_new_slot VARCHAR(64),
    p_rescheduled_by VARCHAR(32) DEFAULT 'patient',
    p_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_appt RECORD;
    v_slot_count INT;
    v_token INT;
    v_new_timestamp TIMESTAMPTZ;
    v_caller_uid TEXT;
BEGIN
    -- 0. Caller authentication and ownership validation
    v_caller_uid := NULLIF(COALESCE(
        auth.jwt() ->> 'sub',
        auth.jwt() ->> 'uid'
    ), '');
    IF v_caller_uid IS NULL THEN
        RAISE EXCEPTION 'UNAUTHORIZED: Authentication required.' USING ERRCODE = '42501';
    END IF;

    -- 1. Lock appointment row
    SELECT * INTO v_appt
    FROM public.appointments
    WHERE appointment_id = p_appointment_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'APPOINTMENT_NOT_FOUND' USING ERRCODE = 'P0002';
    END IF;

    -- Validate caller ownership: patient, doctor, or super_admin
    IF v_appt.patient_id != private.current_profile_id()
       AND v_appt.doctor_id != private.current_profile_id()
       AND NOT private.is_super_admin() THEN
        RAISE EXCEPTION 'FORBIDDEN: You do not have permission to reschedule this appointment.' USING ERRCODE = '42501';
    END IF;

    -- 2. Validate slot capacity (maximum 3 concurrent bookings per slot)
    SELECT COUNT(*) INTO v_slot_count
    FROM public.appointments
    WHERE doctor_id = v_appt.doctor_id
      AND slot_label = p_new_slot
      AND date_time::date = p_new_date
      AND appointment_id != p_appointment_id
      AND patient_status != 'cancelled'
      AND doctor_status != 'cancelled';

    IF v_slot_count >= 3 THEN
        RAISE EXCEPTION 'SLOT_CAPACITY_REACHED' USING ERRCODE = '54000';
    END IF;

    -- 3. Calculate sequential queue token for target date
    SELECT COALESCE(MAX(token_number), 0) + 1 INTO v_token
    FROM public.appointments
    WHERE doctor_id = v_appt.doctor_id
      AND date_time::date = p_new_date;

    v_new_timestamp := (p_new_date::text || ' 10:00:00+05:30')::timestamptz;

    -- 4. Update appointment
    UPDATE public.appointments
    SET date_time = v_new_timestamp,
        slot_label = p_new_slot,
        token_number = v_token,
        patient_status = 'confirmed',
        doctor_status = 'pendingRequest',
        was_rescheduled = TRUE,
        updated_at = CURRENT_TIMESTAMP
    WHERE appointment_id = p_appointment_id;

    RETURN jsonb_build_object(
        'ok', true,
        'appointment_id', p_appointment_id,
        'token_number', v_token,
        'date_time', v_new_timestamp,
        'slot_label', p_new_slot
    );
END;
$$;

-- 6.1 Grant EXECUTE on client-invoked SECURITY DEFINER RPC functions
GRANT EXECUTE ON FUNCTION public.book_appointment_atomic(character varying, character varying, character varying, character varying, character varying, integer, character varying, timestamp with time zone, character varying, character varying, integer, character varying, text, character varying, character varying) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reschedule_appointment_atomic(character varying, character varying, date, character varying, character varying, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_prescription_atomic(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.accept_ambulance_request(character varying, character varying) TO authenticated;
GRANT EXECUTE ON FUNCTION public.complete_ambulance_trip(character varying) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_ambulance_broadcast(character varying, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_ambulance_location(character varying, double precision, double precision, double precision, double precision) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_ambulance_trip_location(character varying) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_ambulance_trip_contact(character varying) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_lab_booking_status(character varying, character varying, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_lab_order_status(character varying, character varying, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_pharmacy_delivery_status(character varying, character varying, text, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.register_device_token(text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_user_role() TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_profile_id() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_profile_completed() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_verified_doctor() TO authenticated;
GRANT EXECUTE ON FUNCTION public.doctor_can_access_patient(text) TO authenticated;

-- 7. Internal / Service-Role only tables (ZERO grants to authenticated or anon):
-- - public.admin_audit_logs
-- - public.storage_audit_logs
-- - public.security_events
-- - public.sync_dead_letter_queue
-- - public.razorpay_webhook_events
-- - public.razorpay_orders
-- - public.razorpay_payments
-- - public.mail_queue
-- - public.abuse_rate_limits
-- - public.otp_challenges
-- - public.super_admins
-- - public.ambulance_locations (internal; accessed solely via SECURITY DEFINER RPC)
-- - public.ambulance_trip_contacts (internal; accessed solely via SECURITY DEFINER RPC)
-- - public.doctor_directory_updates
-- (These tables remain restricted to service_role and postgres).
