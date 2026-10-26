-- ============================================================================
-- DoctorNect Platform — Security Hardening Migration
-- Migration: 20260930000004_access_gap_fixes.sql
-- Description: Fix cross-tenant access gaps, lock critical columns against
-- unauthorized tampering, close walk-in appointment access holes, constrain
-- provider self-registration IDs, and enforce active clinical relationship
-- checks for prescription authoring.
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. HARDEN PATIENT_DOCTOR_LINKS POLICIES
-- ============================================================================
-- Replace referral branch: Doctors can only refer patients they already have
-- clinical authorization to access. Prevents unauthorized relationship creation.

DROP POLICY IF EXISTS "doc_links_insert" ON public.patient_doctor_links;
CREATE POLICY "doc_links_insert" ON public.patient_doctor_links
    FOR INSERT TO authenticated
    WITH CHECK (
        patient_id = private.current_profile_id()
        OR (
            private.is_verified_doctor() 
            AND source = 'referral' 
            AND from_doctor_id = private.current_profile_id() 
            AND private.doctor_can_access_patient(patient_id)
        )
    );

-- Explicitly block non-admin UPDATEs to prevent modifying doctor_id/patient_id/from_doctor_id
DROP POLICY IF EXISTS "doc_links_update" ON public.patient_doctor_links;
CREATE POLICY "doc_links_update" ON public.patient_doctor_links
    FOR UPDATE TO authenticated
    USING (FALSE);

-- Only Super Admins may delete established doctor links (audit trail preservation)
DROP POLICY IF EXISTS "doc_links_delete" ON public.patient_doctor_links;
CREATE POLICY "doc_links_delete" ON public.patient_doctor_links
    FOR DELETE TO authenticated
    USING (private.is_super_admin());

-- ============================================================================
-- 2. WALK-IN STUB VERIFICATION HELPER (private SCHEMA)
-- ============================================================================
-- Verifies whether a target patient is an unlinked clinic walk-in stub
-- (i.e. owner_uid IS NULL). Verified doctors may only book walk-ins for stubs,
-- never for registered platform patients (who must book via app self-service).

CREATE OR REPLACE FUNCTION private.is_walkin_stub(p_patient_id TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.patients p
        WHERE p.patient_id = p_patient_id
          AND p.owner_uid IS NULL
          AND (
            p.primary_doctor_id = private.current_profile_id()
            OR EXISTS (
                SELECT 1 FROM public.appointments a
                WHERE a.patient_id = p_patient_id
                  AND a.doctor_id = private.current_profile_id()
                  AND a.doctor_status IS DISTINCT FROM 'cancelled'
                  AND a.doctor_status IS DISTINCT FROM 'noShow'
                  AND a.patient_status IS DISTINCT FROM 'cancelled'
            )
            OR EXISTS (
                SELECT 1 FROM public.patient_doctor_links pdl
                WHERE pdl.patient_id = p_patient_id
                  AND pdl.doctor_id = private.current_profile_id()
            )
          )
    );
$$;

REVOKE ALL ON FUNCTION private.is_walkin_stub(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.is_walkin_stub(TEXT) TO authenticated, service_role;

-- ============================================================================
-- 3. HARDEN APPOINTMENTS INSERT & UPDATE POLICIES
-- ============================================================================

-- 3A. appointments_insert: Close the walk-in hole by requiring is_walkin_stub(patient_id).
DROP POLICY IF EXISTS "appointments_insert" ON public.appointments;
CREATE POLICY "appointments_insert" ON public.appointments
    FOR INSERT TO authenticated
    WITH CHECK (
        (patient_id = private.current_profile_id() AND source = 'app')
        OR (
            doctor_id = private.current_profile_id()
            AND private.is_verified_doctor()
            AND source = 'walkin'
            AND private.is_walkin_stub(patient_id)
        )
        OR private.is_super_admin()
    );

-- 3B. appointments_update: Replace self-referencing subquery tautology with a simple
-- non-subquery check. Ownership immutability is enforced by trg_appointments_lock_columns.
DROP POLICY IF EXISTS "appointments_update" ON public.appointments;
CREATE POLICY "appointments_update" ON public.appointments
    FOR UPDATE TO authenticated
    USING (
        (
            patient_id = private.current_profile_id()
            AND doctor_status NOT IN ('completed', 'inProgress', 'noShow')
            AND patient_status != 'completed'
        )
        OR (doctor_id = private.current_profile_id() AND private.is_verified_doctor())
        OR private.is_super_admin()
    )
    WITH CHECK (
        patient_id = private.current_profile_id()
        OR (doctor_id = private.current_profile_id() AND private.is_verified_doctor())
        OR private.is_super_admin()
    );

-- ============================================================================
-- 4. CONSTRAIN PROVIDER & PATIENT REGISTRATION INSERT POLICIES
-- ============================================================================
-- Ensure callers can only insert rows matching their own provisioned profile_id.
-- (Bypassed by service_role for backend sync and super_admin for administrative tooling).

-- 4A. patients_insert
DROP POLICY IF EXISTS "patients_insert" ON public.patients;
CREATE POLICY "patients_insert" ON public.patients
    FOR INSERT TO authenticated
    WITH CHECK (
        (owner_uid = auth.uid() AND patient_id = private.current_profile_id())
        OR private.is_super_admin()
    );

-- 4B. doctors_insert
DROP POLICY IF EXISTS "doctors_insert" ON public.doctors;
CREATE POLICY "doctors_insert" ON public.doctors
    FOR INSERT TO authenticated
    WITH CHECK (
        private.is_super_admin()
        OR (
            owner_uid = auth.uid()
            AND doctor_id = private.current_profile_id()
            AND verified = FALSE
            AND verified_at IS NULL
            AND rating = 0.00
            AND review_count = 0
            AND deactivated = FALSE
            AND deactivated_at IS NULL
        )
    );

-- 4C. medical_stores_insert
DROP POLICY IF EXISTS "medical_stores_insert" ON public.medical_stores;
CREATE POLICY "medical_stores_insert" ON public.medical_stores
    FOR INSERT TO authenticated
    WITH CHECK (
        private.is_super_admin()
        OR (
            owner_uid = auth.uid()
            AND store_id = private.current_profile_id()
            AND verified = FALSE
            AND verified_at IS NULL
            AND deactivated = FALSE
        )
    );

-- 4D. labs_insert
DROP POLICY IF EXISTS "labs_insert" ON public.labs;
CREATE POLICY "labs_insert" ON public.labs
    FOR INSERT TO authenticated
    WITH CHECK (
        private.is_super_admin()
        OR (
            owner_uid = auth.uid()
            AND lab_id = private.current_profile_id()
            AND verified = FALSE
            AND verified_at IS NULL
            AND rating = 0.00
            AND deactivated = FALSE
        )
    );

-- 4E. ambulances_insert
DROP POLICY IF EXISTS "ambulances_insert" ON public.ambulances;
CREATE POLICY "ambulances_insert" ON public.ambulances
    FOR INSERT TO authenticated
    WITH CHECK (
        private.is_super_admin()
        OR (
            auth_uid = auth.uid()
            AND verified = FALSE
            AND total_rating = 0.00
            AND rating_count = 0
        )
    );

-- ============================================================================
-- 5. GENERIC COLUMN-LOCK TRIGGER FUNCTION IN private SCHEMA
-- ============================================================================
-- Checks specified column arguments passed via TG_ARGV.
-- Compares to_jsonb(NEW)->>col vs to_jsonb(OLD)->>col.
-- Bypasses for super_admin or internal service_role (auth.uid() IS NULL).

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

REVOKE ALL ON FUNCTION private.lock_columns() FROM PUBLIC, anon, authenticated;

-- ============================================================================
-- 6. ATTACH COLUMN-LOCK TRIGGERS
-- ============================================================================

-- 6A. doctors: deactivated, owner_uid, verified
DROP TRIGGER IF EXISTS trg_doctors_lock_columns ON public.doctors;
CREATE TRIGGER trg_doctors_lock_columns
    BEFORE UPDATE ON public.doctors
    FOR EACH ROW
    EXECUTE FUNCTION private.lock_columns('deactivated', 'owner_uid', 'verified');

-- 6B. medical_stores: deactivated, owner_uid, verified
DROP TRIGGER IF EXISTS trg_medical_stores_lock_columns ON public.medical_stores;
CREATE TRIGGER trg_medical_stores_lock_columns
    BEFORE UPDATE ON public.medical_stores
    FOR EACH ROW
    EXECUTE FUNCTION private.lock_columns('deactivated', 'owner_uid', 'verified');

-- 6C. labs: deactivated, owner_uid, verified
DROP TRIGGER IF EXISTS trg_labs_lock_columns ON public.labs;
CREATE TRIGGER trg_labs_lock_columns
    BEFORE UPDATE ON public.labs
    FOR EACH ROW
    EXECUTE FUNCTION private.lock_columns('deactivated', 'owner_uid', 'verified');

-- 6D. ambulances: auth_uid, verified (Note: deactivated column does not exist on ambulances)
DROP TRIGGER IF EXISTS trg_ambulances_lock_columns ON public.ambulances;
CREATE TRIGGER trg_ambulances_lock_columns
    BEFORE UPDATE ON public.ambulances
    FOR EACH ROW
    EXECUTE FUNCTION private.lock_columns('auth_uid', 'verified');

-- 6E. patients: owner_uid
DROP TRIGGER IF EXISTS trg_patients_lock_columns ON public.patients;
CREATE TRIGGER trg_patients_lock_columns
    BEFORE UPDATE ON public.patients
    FOR EACH ROW
    EXECUTE FUNCTION private.lock_columns('owner_uid');

-- 6F. appointments: patient_id, doctor_id
DROP TRIGGER IF EXISTS trg_appointments_lock_columns ON public.appointments;
CREATE TRIGGER trg_appointments_lock_columns
    BEFORE UPDATE ON public.appointments
    FOR EACH ROW
    EXECUTE FUNCTION private.lock_columns('patient_id', 'doctor_id');

-- 6G. lab_bookings: patient_id
DROP TRIGGER IF EXISTS trg_lab_bookings_lock_columns ON public.lab_bookings;
CREATE TRIGGER trg_lab_bookings_lock_columns
    BEFORE UPDATE ON public.lab_bookings
    FOR EACH ROW
    EXECUTE FUNCTION private.lock_columns('patient_id');

-- 6H. referrals: referral_id, from_doctor_id, to_doctor_id, patient_id, appointment_id
DROP TRIGGER IF EXISTS trg_referrals_lock_columns ON public.referrals;
CREATE TRIGGER trg_referrals_lock_columns
    BEFORE UPDATE ON public.referrals
    FOR EACH ROW
    EXECUTE FUNCTION private.lock_columns('referral_id', 'from_doctor_id', 'to_doctor_id', 'patient_id', 'appointment_id');

-- ============================================================================
-- 7. PRESCRIPTIONS WRITE RELATIONSHIP GUARD (private SCHEMA)
-- ============================================================================
-- Doctors must have an active clinical relationship (non-cancelled appointment,
-- patient link, or primary/care-team assignment) to write prescriptions.
-- Distinct from doctor_can_access_patient() because it DOES NOT require
-- share_records_with_doctors = TRUE, ensuring treatment is never blocked
-- if a patient restricts general record browsing.

CREATE OR REPLACE FUNCTION private.doctor_has_relationship(p_patient_id TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT (
        private.is_verified_doctor()
        AND (
            EXISTS (
                SELECT 1 FROM public.appointments a
                WHERE a.patient_id = p_patient_id
                  AND a.doctor_id = private.current_profile_id()
                  AND a.doctor_status IS DISTINCT FROM 'cancelled'
                  AND a.doctor_status IS DISTINCT FROM 'noShow'
                  AND a.patient_status IS DISTINCT FROM 'cancelled'
            )
            OR EXISTS (
                SELECT 1 FROM public.patient_doctor_links pdl
                WHERE pdl.patient_id = p_patient_id
                  AND pdl.doctor_id = private.current_profile_id()
            )
            OR EXISTS (
                SELECT 1 FROM public.patients p
                WHERE p.patient_id = p_patient_id
                  AND (
                      p.primary_doctor_id = private.current_profile_id()
                      OR p.invited_doctor_id = private.current_profile_id()
                      OR private.current_profile_id() = ANY(p.care_team_doctor_ids)
                  )
            )
        )
    );
$$;

REVOKE ALL ON FUNCTION private.doctor_has_relationship(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.doctor_has_relationship(TEXT) TO authenticated, service_role;

-- ============================================================================
-- 8. HARDEN PRESCRIPTIONS WRITE POLICY
-- ============================================================================
DROP POLICY IF EXISTS "prescriptions_write" ON public.prescriptions;
CREATE POLICY "prescriptions_write" ON public.prescriptions
    FOR ALL TO authenticated
    USING (
        (doctor_id = private.current_profile_id() AND private.doctor_has_relationship(patient_id))
        OR private.is_super_admin()
    )
    WITH CHECK (
        (doctor_id = private.current_profile_id() AND private.doctor_has_relationship(patient_id))
        OR private.is_super_admin()
    );

-- ============================================================================
-- 9. HARDEN LAB_BOOKINGS AND REFERRALS UPDATE POLICIES
-- ============================================================================

-- 9A. lab_bookings_update: replace tautological self-referencing subquery
DROP POLICY IF EXISTS "lab_bookings_update" ON public.lab_bookings;
CREATE POLICY "lab_bookings_update" ON public.lab_bookings
    FOR UPDATE TO authenticated
    USING (
        patient_id = private.current_profile_id() 
        OR lab_id = private.current_profile_id() 
        OR private.is_super_admin()
    )
    WITH CHECK (
        patient_id = private.current_profile_id() 
        OR lab_id = private.current_profile_id() 
        OR private.is_super_admin()
    );

-- 9B. referrals_update: replace tautological self-referencing subquery
DROP POLICY IF EXISTS "referrals_update" ON public.referrals;
CREATE POLICY "referrals_update" ON public.referrals
    FOR UPDATE TO authenticated
    USING (
        (private.is_verified_doctor() AND to_doctor_id = private.current_profile_id()) 
        OR private.is_super_admin()
    )
    WITH CHECK (
        (private.is_verified_doctor() AND to_doctor_id = private.current_profile_id()) 
        OR private.is_super_admin()
    );

COMMIT;

-- ============================================================================
-- PENDING DATA CLEANUP: PARTIAL UNIQUE INDEX ON users.mobile
-- Run scratch/users_mobile_dupes.sql first to ensure no duplicates exist.
-- Once duplicates are resolved, execute the following statement manually:
--
-- CREATE UNIQUE INDEX idx_users_active_mobile 
-- ON public.users (mobile) 
-- WHERE deactivated = FALSE AND mobile IS NOT NULL;
-- ============================================================================
