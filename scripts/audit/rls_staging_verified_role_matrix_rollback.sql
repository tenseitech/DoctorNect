-- STAGING ONLY — rollback db/proposed/20261103000014_proposed_role_verified_rls_hardening.sql
-- Restores provider policies to pre-000014 shape (from db/migrations on disk).

BEGIN;

DROP FUNCTION IF EXISTS private.is_verified_lab();
DROP FUNCTION IF EXISTS private.is_verified_medical_store();

-- appointments_select (20261102000001_round6_guards_and_kyc.sql)
DROP POLICY IF EXISTS "appointments_select" ON public.appointments;
CREATE POLICY "appointments_select" ON public.appointments
    FOR SELECT TO authenticated
    USING (
        patient_id = private.current_profile_id()
        OR doctor_id = private.current_profile_id()
        OR EXISTS (
            SELECT 1 FROM public.patients p
            WHERE p.patient_id = appointments.patient_id
              AND p.owner_uid = (auth.jwt() ->> 'sub')
        )
        OR EXISTS (
            SELECT 1 FROM public.family_members fm
            WHERE fm.member_id = appointments.patient_id
              AND fm.patient_id = private.current_profile_id()
        )
        OR private.is_super_admin()
    );

-- appointments_update (20261026000001_rpc_null_safe_authz.sql excerpt)
DROP POLICY IF EXISTS "appointments_update" ON public.appointments;
CREATE POLICY "appointments_update" ON public.appointments
    FOR UPDATE TO authenticated
    USING (
        patient_id = private.current_profile_id()
        OR doctor_id = private.current_profile_id()
        OR EXISTS (
            SELECT 1 FROM public.patients p
            WHERE p.patient_id = appointments.patient_id
              AND p.owner_uid = private.current_firebase_uid()
        )
        OR EXISTS (
            SELECT 1 FROM public.family_members fm
            WHERE fm.member_id = appointments.patient_id
              AND fm.patient_id = private.current_profile_id()
        )
        OR private.is_super_admin()
    )
    WITH CHECK (
        doctor_id = private.current_profile_id()
        OR (
            (
                patient_id = private.current_profile_id()
                OR EXISTS (
                    SELECT 1 FROM public.patients p
                    WHERE p.patient_id = appointments.patient_id
                      AND p.owner_uid = private.current_firebase_uid()
                )
                OR EXISTS (
                    SELECT 1 FROM public.family_members fm
                    WHERE fm.member_id = appointments.patient_id
                      AND fm.patient_id = private.current_profile_id()
                )
            )
            AND patient_status = 'cancelled'
        )
        OR private.is_super_admin()
    );

-- prescriptions_select (20261020000001_consolidated_firebase_schema_and_rls.sql)
DROP POLICY IF EXISTS "prescriptions_select" ON public.prescriptions;
CREATE POLICY "prescriptions_select" ON public.prescriptions
    FOR SELECT TO authenticated
    USING (
        patient_id = private.current_profile_id()
        OR doctor_id = private.current_profile_id()
        OR EXISTS (
            SELECT 1 FROM pharmacy_deliveries pd
            WHERE pd.prescription_id = prescriptions.prescription_id
              AND pd.store_id = private.current_profile_id()
        )
        OR private.is_super_admin()
    );

-- lab_bookings_update, lab_orders_insert/update, pharmacy_connections_*, pdl_select:
-- restore from db/migrations/20261020000001_consolidated_firebase_schema_and_rls.sql
-- (lines ~2087–2128 lab/pharmacy, ~1816 pdl_select) before running on staging.

ROLLBACK;
