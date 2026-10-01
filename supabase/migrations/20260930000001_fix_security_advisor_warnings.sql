-- ============================================================================
-- DoctorNect Platform — Security Advisor Hardening Migration
-- File: 20260930000001_fix_security_advisor_warnings.sql
-- ============================================================================
-- NOTE: Every new function must explicitly REVOKE EXECUTE FROM PUBLIC, anon.
--
-- Purpose:
-- 1. Fix all 19 WARN-level lints reported by Supabase Security Advisor:
--    - Issue 1: function_search_path_mutable (2 functions)
--    - Issue 2: SECURITY DEFINER functions executable by anon/public (8 functions)
--    - Issue 3: Auth leaked password protection (guidance documented)
-- 2. Establish dedicated 'private' schema for internal RLS helper logic.
-- 3. Maintain zero-downtime backwards compatibility for existing RLS policies
--    via SECURITY INVOKER wrappers in 'public' delegating to 'private'.
-- 4. Harden book_appointment_atomic with strict authentication & authorization,
--    specifically guarding against NULL comparison bypasses.
-- 5. Revoke default EXECUTE on future functions globally and in 'public' schema.
-- ============================================================================

BEGIN;

-- ============================================================================
-- 0. SCHEMA INITIALIZATION: PRIVATE HELPER SCHEMA
-- ============================================================================
CREATE SCHEMA IF NOT EXISTS private;

-- Grant USAGE to authenticated users and service_role so RLS evaluations and backend jobs succeed
GRANT USAGE ON SCHEMA private TO authenticated;
GRANT USAGE ON SCHEMA private TO service_role;
-- Restrict anon from schema usage
REVOKE ALL ON SCHEMA private FROM PUBLIC, anon;

-- ============================================================================
-- 1. ISSUE 1: FIX FUNCTION_SEARCH_PATH_MUTABLE (TRIGGERS)
-- ============================================================================

-- 1A. trigger_set_timestamp()
ALTER FUNCTION public.trigger_set_timestamp() 
    SET search_path = public, pg_temp;
REVOKE ALL ON FUNCTION public.trigger_set_timestamp() FROM PUBLIC, anon;

-- 1B. check_appointment_cancellation_integrity()
ALTER FUNCTION public.check_appointment_cancellation_integrity() 
    SET search_path = public, pg_temp;
REVOKE ALL ON FUNCTION public.check_appointment_cancellation_integrity() FROM PUBLIC, anon;

-- ============================================================================
-- 2. CREATE SECURE CANONICAL IMPLEMENTATIONS IN 'private' SCHEMA
-- ============================================================================

-- 2A. private.current_user_role()
CREATE OR REPLACE FUNCTION private.current_user_role()
RETURNS TEXT 
STABLE 
SECURITY DEFINER 
SET search_path = public, pg_temp 
AS $$
    SELECT role FROM public.users WHERE id = auth.uid();
$$ LANGUAGE sql;

-- 2B. private.current_profile_id()
CREATE OR REPLACE FUNCTION private.current_profile_id()
RETURNS TEXT 
STABLE 
SECURITY DEFINER 
SET search_path = public, pg_temp 
AS $$
    SELECT profile_id FROM public.users WHERE id = auth.uid();
$$ LANGUAGE sql;

-- 2C. private.is_super_admin()
CREATE OR REPLACE FUNCTION private.is_super_admin()
RETURNS BOOLEAN 
STABLE 
SECURITY DEFINER 
SET search_path = public, pg_temp 
AS $$
    SELECT (
        private.current_user_role() IN ('super_admin', 'superAdmin', 'admin')
        OR LOWER(auth.jwt() ->> 'email') IN (
            'sharmasd2@gmail.com',
            'tenseitechpvtltd@gmail.com',
            'admin@doctornect.com',
            'superadmin@doctornect.com',
            'support@doctornect.com'
        )
    );
$$ LANGUAGE sql;

-- 2D. private.is_verified_doctor()
CREATE OR REPLACE FUNCTION private.is_verified_doctor()
RETURNS BOOLEAN 
STABLE 
SECURITY DEFINER 
SET search_path = public, pg_temp 
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.doctors 
        WHERE doctor_id = private.current_profile_id() 
          AND verified = TRUE 
          AND deactivated = FALSE
    );
$$ LANGUAGE sql;

-- 2E. private.is_profile_completed()
CREATE OR REPLACE FUNCTION private.is_profile_completed()
RETURNS BOOLEAN 
STABLE 
SECURITY DEFINER 
SET search_path = public, pg_temp 
AS $$
    SELECT COALESCE(profile_completed, FALSE) FROM public.users WHERE id = auth.uid();
$$ LANGUAGE sql;

-- 2F. private.doctor_can_access_patient(target_patient_id TEXT)
CREATE OR REPLACE FUNCTION private.doctor_can_access_patient(target_patient_id TEXT)
RETURNS BOOLEAN 
STABLE 
SECURITY DEFINER 
SET search_path = public, pg_temp 
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.patients p
        WHERE p.patient_id = target_patient_id
          AND p.share_records_with_doctors = TRUE
          AND private.is_verified_doctor()
          AND (
              p.primary_doctor_id = private.current_profile_id()
              OR p.invited_doctor_id = private.current_profile_id()
              OR private.current_profile_id() = ANY(p.care_team_doctor_ids)
              OR EXISTS (
                  SELECT 1 FROM public.patient_doctor_links pdl
                  WHERE pdl.patient_id = target_patient_id
                    AND pdl.doctor_id = private.current_profile_id()
              )
              OR EXISTS (
                  SELECT 1 FROM public.appointments a
                  WHERE a.patient_id = target_patient_id
                    AND a.doctor_id = private.current_profile_id()
              )
          )
    );
$$ LANGUAGE sql;

-- Lock down execution privileges on private schema functions
REVOKE ALL ON FUNCTION private.current_user_role() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION private.current_profile_id() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION private.is_super_admin() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION private.is_verified_doctor() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION private.is_profile_completed() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION private.doctor_can_access_patient(TEXT) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION private.current_user_role() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION private.current_profile_id() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION private.is_super_admin() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION private.is_verified_doctor() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION private.is_profile_completed() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION private.doctor_can_access_patient(TEXT) TO authenticated, service_role;

-- ============================================================================
-- 3. HARDEN PUBLIC FUNCTIONS & RETIRE UNPRIVILEGED ACCESS
-- ============================================================================

-- 3A. public.rls_auto_enable()
-- Event-trigger utility: Should NEVER be executable by any client role (anon, authenticated, or public).
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_proc p 
        JOIN pg_namespace n ON p.pronamespace = n.oid 
        WHERE n.nspname = 'public' AND p.proname = 'rls_auto_enable'
    ) THEN
        EXECUTE 'REVOKE ALL ON FUNCTION public.rls_auto_enable() FROM PUBLIC, anon, authenticated;';
        EXECUTE 'ALTER FUNCTION public.rls_auto_enable() SET search_path = public, pg_temp;';
    END IF;
END $$;

-- 3B. public.current_user_role()
-- Not called directly by any RLS policy or client RPC.
-- Convert to SECURITY INVOKER delegating to private schema and revoke from all API roles.
CREATE OR REPLACE FUNCTION public.current_user_role()
RETURNS TEXT 
STABLE 
SECURITY INVOKER 
SET search_path = public, pg_temp 
AS $$
    SELECT private.current_user_role();
$$ LANGUAGE sql;

REVOKE ALL ON FUNCTION public.current_user_role() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.current_user_role() TO service_role;

-- 3C. public.current_profile_id()
-- Convert to SECURITY INVOKER wrapper. Prevents prosecdef warning while keeping 89 policies working.
CREATE OR REPLACE FUNCTION public.current_profile_id()
RETURNS TEXT 
STABLE 
SECURITY INVOKER 
SET search_path = public, pg_temp 
AS $$
    SELECT private.current_profile_id();
$$ LANGUAGE sql;

REVOKE ALL ON FUNCTION public.current_profile_id() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.current_profile_id() TO authenticated, service_role;

-- 3D. public.is_super_admin()
-- Convert to SECURITY INVOKER wrapper.
CREATE OR REPLACE FUNCTION public.is_super_admin()
RETURNS BOOLEAN 
STABLE 
SECURITY INVOKER 
SET search_path = public, pg_temp 
AS $$
    SELECT private.is_super_admin();
$$ LANGUAGE sql;

REVOKE ALL ON FUNCTION public.is_super_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_super_admin() TO authenticated, service_role;

-- 3E. public.is_verified_doctor()
-- Convert to SECURITY INVOKER wrapper.
CREATE OR REPLACE FUNCTION public.is_verified_doctor()
RETURNS BOOLEAN 
STABLE 
SECURITY INVOKER 
SET search_path = public, pg_temp 
AS $$
    SELECT private.is_verified_doctor();
$$ LANGUAGE sql;

REVOKE ALL ON FUNCTION public.is_verified_doctor() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_verified_doctor() TO authenticated, service_role;

-- 3F. public.is_profile_completed()
-- Convert to SECURITY INVOKER wrapper.
CREATE OR REPLACE FUNCTION public.is_profile_completed()
RETURNS BOOLEAN 
STABLE 
SECURITY INVOKER 
SET search_path = public, pg_temp 
AS $$
    SELECT private.is_profile_completed();
$$ LANGUAGE sql;

REVOKE ALL ON FUNCTION public.is_profile_completed() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_profile_completed() TO authenticated, service_role;

-- 3G. public.doctor_can_access_patient(TEXT)
-- Convert to SECURITY INVOKER wrapper.
CREATE OR REPLACE FUNCTION public.doctor_can_access_patient(target_patient_id TEXT)
RETURNS BOOLEAN 
STABLE 
SECURITY INVOKER 
SET search_path = public, pg_temp 
AS $$
    SELECT private.doctor_can_access_patient(target_patient_id);
$$ LANGUAGE sql;

REVOKE ALL ON FUNCTION public.doctor_can_access_patient(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.doctor_can_access_patient(TEXT) TO authenticated, service_role;

-- ============================================================================
-- 4. HARDEN public.book_appointment_atomic
-- ============================================================================
-- Keeps SECURITY DEFINER (necessary for cross-patient capacity check under lock),
-- but revokes all access from anon/PUBLIC, restricts to authenticated, pins search_path,
-- and adds rigorous ownership & authorization assertions with strict NULL guards.

CREATE OR REPLACE FUNCTION public.book_appointment_atomic(
    p_appointment_id VARCHAR(64),
    p_doctor_id VARCHAR(64),
    p_patient_id VARCHAR(64),
    p_doctor_name VARCHAR(255),
    p_specialization VARCHAR(128),
    p_patient_name VARCHAR(255),
    p_patient_age INTEGER,
    p_patient_gender VARCHAR(16),
    p_date_time TIMESTAMPTZ,
    p_slot_label VARCHAR(64),
    p_visit_type VARCHAR(32) DEFAULT 'newVisit',
    p_token_number INTEGER DEFAULT NULL,
    p_clinic_name VARCHAR(255) DEFAULT NULL,
    p_clinic_address TEXT DEFAULT NULL,
    p_sync_origin VARCHAR(32) DEFAULT 'patient_supabase'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_active_count INTEGER;
    v_token_number INTEGER;
    v_appointment RECORD;
    v_lock_key1 INTEGER;
    v_lock_key2 INTEGER;
    v_caller_profile_id TEXT;
    v_is_admin BOOLEAN;
BEGIN
    -- 0. Strictly require authenticated session via auth.uid()
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'UNAUTHORIZED: Authentication required to book an appointment.'
            USING ERRCODE = '42501';
    END IF;

    -- Validate critical non-nullable parameters
    IF p_appointment_id IS NULL OR p_doctor_id IS NULL OR p_patient_id IS NULL OR p_date_time IS NULL THEN
        RAISE EXCEPTION 'BAD_REQUEST: Required booking parameters (appointment_id, doctor_id, patient_id, date_time) cannot be null.'
            USING ERRCODE = '22004';
    END IF;

    -- 1. Caller Authorization Check (defense-in-depth with strict NULL guards)
    v_caller_profile_id := private.current_profile_id();
    v_is_admin := COALESCE(private.is_super_admin(), FALSE);

    -- If caller is not admin, they MUST have a valid profile_id in public.users
    IF NOT v_is_admin AND v_caller_profile_id IS NULL THEN
        RAISE EXCEPTION 'PROFILE_NOT_FOUND: Authenticated user % has no active profile in public.users.', auth.uid()
            USING ERRCODE = '42501';
    END IF;

    -- Strict authorization: Super admin OR booking for caller's own profile
    IF NOT v_is_admin THEN
        IF p_patient_id IS DISTINCT FROM v_caller_profile_id THEN
            RAISE EXCEPTION 'FORBIDDEN: Cannot book appointment for another patient profile (Caller: %, Requested: %).',
                v_caller_profile_id, p_patient_id
                USING ERRCODE = '42501';
        END IF;
    END IF;

    -- 2. Acquire Transaction-Level Advisory Lock on (doctor_id, epoch seconds)
    -- Epoch timestamp ensures the advisory lock key is immutable regardless of session TimeZone settings
    v_lock_key1 := hashtext(p_doctor_id);
    v_lock_key2 := hashtext(extract(epoch from p_date_time)::text);
    PERFORM pg_advisory_xact_lock(v_lock_key1, v_lock_key2);

    -- 3. Check for Duplicate Active Booking by the Same Patient
    IF EXISTS (
        SELECT 1 FROM public.appointments
        WHERE patient_id = p_patient_id
          AND doctor_id = p_doctor_id
          AND date_time = p_date_time
          AND patient_status != 'cancelled'
    ) THEN
        RAISE EXCEPTION 'DUPLICATE_PATIENT_BOOKING: Patient % already has an active booking for this slot.', p_patient_id
            USING ERRCODE = '23505';
    END IF;

    -- 4. Enforce Hard Slot Capacity (Max 3 Patients per Doctor Slot)
    SELECT COUNT(*) INTO v_active_count
    FROM public.appointments
    WHERE doctor_id = p_doctor_id
      AND date_time = p_date_time
      AND patient_status != 'cancelled';

    IF v_active_count >= 3 THEN
        RAISE EXCEPTION 'SLOT_CAPACITY_REACHED: Slot "%" for doctor "%" already has % active bookings (maximum capacity is 3).',
            p_slot_label, p_doctor_name, v_active_count
            USING ERRCODE = 'P0001';
    END IF;

    -- 5. Calculate Sequential Daily Token Number (if not supplied)
    IF p_token_number IS NULL THEN
        SELECT COALESCE(MAX(token_number), 0) + 1 INTO v_token_number
        FROM public.appointments
        WHERE doctor_id = p_doctor_id
          AND date_time::date = p_date_time::date;
    ELSE
        v_token_number := p_token_number;
    END IF;

    -- 6. Insert Appointment Record
    INSERT INTO public.appointments (
        appointment_id,
        doctor_id,
        patient_id,
        doctor_name,
        specialization,
        patient_name,
        patient_age,
        patient_gender,
        date_time,
        slot_label,
        visit_type,
        patient_status,
        doctor_status,
        token_number,
        clinic_name,
        clinic_address,
        sync_origin,
        created_at,
        updated_at
    ) VALUES (
        p_appointment_id,
        p_doctor_id,
        p_patient_id,
        p_doctor_name,
        p_specialization,
        p_patient_name,
        p_patient_age,
        p_patient_gender,
        p_date_time,
        p_slot_label,
        COALESCE(p_visit_type, 'newVisit'),
        'confirmed',
        'pendingRequest',
        v_token_number,
        p_clinic_name,
        p_clinic_address,
        COALESCE(p_sync_origin, 'patient_supabase'),
        NOW(),
        NOW()
    )
    RETURNING * INTO v_appointment;

    RETURN to_jsonb(v_appointment);
END;
$$;

-- Revoke all permissions from anon and PUBLIC
REVOKE ALL ON FUNCTION public.book_appointment_atomic(
    VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR,
    INTEGER, VARCHAR, TIMESTAMPTZ, VARCHAR, VARCHAR, INTEGER,
    VARCHAR, TEXT, VARCHAR
) FROM PUBLIC, anon;

-- Grant execution only to authenticated and service_role
GRANT EXECUTE ON FUNCTION public.book_appointment_atomic(
    VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR,
    INTEGER, VARCHAR, TIMESTAMPTZ, VARCHAR, VARCHAR, INTEGER,
    VARCHAR, TEXT, VARCHAR
) TO authenticated, service_role;

COMMENT ON FUNCTION public.book_appointment_atomic IS
'Atomically locks slot (doctor_id, date_time), enforces max 3 capacity, validates caller authorization, and books appointment.';

-- ============================================================================
-- 5. DEFAULT PRIVILEGES HARDENING
-- ============================================================================
-- Ensure future functions created by postgres or supabase_admin do not inherit default EXECUTE for PUBLIC or anon.
-- Wrapped in individual exception handlers so insufficient_privilege never aborts the migration.

DO $$
BEGIN
  EXECUTE 'ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon;';
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'skipped supabase_admin default privileges (insufficient privilege)';
END $$;

DO $$
BEGIN
  EXECUTE 'ALTER DEFAULT PRIVILEGES FOR ROLE postgres REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon;';
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'skipped postgres default privileges (insufficient privilege)';
END $$;

DO $$
BEGIN
  EXECUTE 'ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon;';
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'skipped public schema default privileges (insufficient privilege)';
END $$;

COMMIT;
