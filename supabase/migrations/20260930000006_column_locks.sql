-- ============================================================================
-- Migration: 20260930000006_column_locks.sql
-- Description: Comprehensive column locks, RLS subquery elimination,
--              walk-in least-privilege enforcement, and appointment status
--              filtering for doctor patient-access checks.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. DEFINE private.lock_columns()
-- ----------------------------------------------------------------------------
-- Enforces column-level immutability for non-admin authenticated users.
-- Bypasses naturally for service_role and background jobs (auth.uid() IS NULL)
-- and for super admins.

CREATE OR REPLACE FUNCTION private.lock_columns()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_col TEXT;
    v_old_val TEXT;
    v_new_val TEXT;
    v_is_admin BOOLEAN := COALESCE(private.is_super_admin(), FALSE);
BEGIN
    IF v_is_admin OR auth.uid() IS NULL THEN
        RETURN NEW;
    END IF;

    FOR i IN 0 .. (TG_NARGS - 1) LOOP
        v_col := TG_ARGV[i];
        v_old_val := to_jsonb(OLD) ->> v_col;
        v_new_val := to_jsonb(NEW) ->> v_col;

        IF v_new_val IS DISTINCT FROM v_old_val THEN
            RAISE EXCEPTION 'FORBIDDEN: Modifying column "%" on table "%" is not permitted (Current: %, Requested: %)',
                v_col, TG_TABLE_NAME, v_old_val, v_new_val
                USING ERRCODE = '42501';
        END IF;
    END LOOP;

    RETURN NEW;
END;
$$;

-- ----------------------------------------------------------------------------
-- 2. EXTEND COLUMN LOCKS (TRIGGER LEVEL IMMUTABILITY)
-- ----------------------------------------------------------------------------

-- Doctors: lock deactivated, owner_uid, verified, rating, review_count
DROP TRIGGER IF EXISTS trg_doctors_lock_columns ON public.doctors;
CREATE TRIGGER trg_doctors_lock_columns
    BEFORE UPDATE ON public.doctors
    FOR EACH ROW
    EXECUTE FUNCTION private.lock_columns('deactivated', 'owner_uid', 'verified', 'rating', 'review_count');

-- Ambulances: lock auth_uid, verified, total_rating, rating_count
DROP TRIGGER IF EXISTS trg_ambulances_lock_columns ON public.ambulances;
CREATE TRIGGER trg_ambulances_lock_columns
    BEFORE UPDATE ON public.ambulances
    FOR EACH ROW
    EXECUTE FUNCTION private.lock_columns('auth_uid', 'verified', 'total_rating', 'rating_count');

-- Patients: lock owner_uid, verified
DROP TRIGGER IF EXISTS trg_patients_lock_columns ON public.patients;
CREATE TRIGGER trg_patients_lock_columns
    BEFORE UPDATE ON public.patients
    FOR EACH ROW
    EXECUTE FUNCTION private.lock_columns('owner_uid', 'verified');

-- Labs: lock deactivated, owner_uid, verified, rating
DROP TRIGGER IF EXISTS trg_labs_lock_columns ON public.labs;
CREATE TRIGGER trg_labs_lock_columns
    BEFORE UPDATE ON public.labs
    FOR EACH ROW
    EXECUTE FUNCTION private.lock_columns('deactivated', 'owner_uid', 'verified', 'rating');

-- Medical Stores: lock deactivated, owner_uid, verified
DROP TRIGGER IF EXISTS trg_medical_stores_lock_columns ON public.medical_stores;
CREATE TRIGGER trg_medical_stores_lock_columns
    BEFORE UPDATE ON public.medical_stores
    FOR EACH ROW
    EXECUTE FUNCTION private.lock_columns('deactivated', 'owner_uid', 'verified');

-- ----------------------------------------------------------------------------
-- 3. REPLACE FRAGILE SUBQUERY UPDATE POLICIES WITH OWNER-ONLY CHECKS
-- ----------------------------------------------------------------------------

-- Doctors Update
DROP POLICY IF EXISTS "doctors_update" ON public.doctors;
CREATE POLICY "doctors_update" ON public.doctors
    FOR UPDATE TO authenticated
    USING (
        owner_uid = auth.uid()
        OR doctor_id = private.current_profile_id()
        OR private.is_super_admin()
    )
    WITH CHECK (
        owner_uid = auth.uid()
        OR doctor_id = private.current_profile_id()
        OR private.is_super_admin()
    );

-- Patients Update
DROP POLICY IF EXISTS "patients_update" ON public.patients;
CREATE POLICY "patients_update" ON public.patients
    FOR UPDATE TO authenticated
    USING (
        owner_uid = auth.uid()
        OR patient_id = private.current_profile_id()
        OR private.is_super_admin()
    )
    WITH CHECK (
        owner_uid = auth.uid()
        OR patient_id = private.current_profile_id()
        OR private.is_super_admin()
    );

-- Medical Stores Update
DROP POLICY IF EXISTS "medical_stores_update" ON public.medical_stores;
CREATE POLICY "medical_stores_update" ON public.medical_stores
    FOR UPDATE TO authenticated
    USING (
        owner_uid = auth.uid()
        OR store_id = private.current_profile_id()
        OR private.is_super_admin()
    )
    WITH CHECK (
        owner_uid = auth.uid()
        OR store_id = private.current_profile_id()
        OR private.is_super_admin()
    );

-- Labs Update
DROP POLICY IF EXISTS "labs_update" ON public.labs;
CREATE POLICY "labs_update" ON public.labs
    FOR UPDATE TO authenticated
    USING (
        owner_uid = auth.uid()
        OR lab_id = private.current_profile_id()
        OR private.is_super_admin()
    )
    WITH CHECK (
        owner_uid = auth.uid()
        OR lab_id = private.current_profile_id()
        OR private.is_super_admin()
    );

-- Ambulances Update
DROP POLICY IF EXISTS "ambulances_update" ON public.ambulances;
CREATE POLICY "ambulances_update" ON public.ambulances
    FOR UPDATE TO authenticated
    USING (
        auth_uid = auth.uid()
        OR ambulance_id = private.current_profile_id()
        OR private.is_super_admin()
    )
    WITH CHECK (
        auth_uid = auth.uid()
        OR ambulance_id = private.current_profile_id()
        OR private.is_super_admin()
    );

-- ----------------------------------------------------------------------------
-- 4. APPOINTMENTS INSERT: LEAST PRIVILEGE (REMOVE WALK-IN BRANCH)
-- ----------------------------------------------------------------------------
-- All clinic walk-in appointments originate in Firebase and replicate to Postgres
-- via Cloud Functions using service_role credentials (bypassing RLS).
-- Direct client insertions in Supabase mode are strictly patient-initiated bookings.
DROP POLICY IF EXISTS "appointments_insert" ON public.appointments;
CREATE POLICY "appointments_insert" ON public.appointments
    FOR INSERT TO authenticated
    WITH CHECK (
        private.is_super_admin()
        OR (
            patient_id = private.current_profile_id()
            AND source = 'app'
        )
    );

-- ----------------------------------------------------------------------------
-- 5. DOCTOR ACCESS FILTERING (IGNORE CANCELLED AND NOSHOW APPOINTMENTS)
-- ----------------------------------------------------------------------------
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
                    AND a.doctor_status IS DISTINCT FROM 'cancelled'
                    AND a.doctor_status IS DISTINCT FROM 'noShow'
                    AND a.patient_status IS DISTINCT FROM 'cancelled'
              )
          )
    );
$$ LANGUAGE sql;

CREATE OR REPLACE FUNCTION public.doctor_can_access_patient(target_patient_id TEXT)
RETURNS BOOLEAN 
STABLE 
SECURITY INVOKER 
SET search_path = public, pg_temp 
AS $$
    SELECT private.doctor_can_access_patient(target_patient_id);
$$ LANGUAGE sql;

-- Privileges
REVOKE ALL ON FUNCTION private.doctor_can_access_patient(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.doctor_can_access_patient(TEXT) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.doctor_can_access_patient(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.doctor_can_access_patient(TEXT) TO authenticated, service_role;

