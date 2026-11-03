-- STAGING ONLY — rollback db/proposed/20261103000014_proposed_role_verified_rls_hardening.sql
-- Restores policies to latest deployed definitions (pre-000014). Manual run: change ROLLBACK to COMMIT if satisfied.

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

-- appointments_update (20261026000001_rpc_null_safe_authz.sql)
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

-- prescriptions_select (20261021000002_phase_d_pharmacy_lab_ambulance.sql)
DROP POLICY IF EXISTS "prescriptions_select" ON public.prescriptions;
CREATE POLICY "prescriptions_select" ON public.prescriptions
    FOR SELECT TO authenticated
    USING (
        patient_id = private.current_profile_id()
        OR doctor_id = private.current_profile_id()
        OR EXISTS (
            SELECT 1 FROM public.pharmacy_deliveries pd
            WHERE pd.prescription_id = prescriptions.prescription_id
              AND (
                  pd.store_id = private.current_profile_id()
                  OR EXISTS (
                      SELECT 1 FROM public.medical_stores ms
                      WHERE ms.store_id = pd.store_id AND ms.owner_uid = (auth.jwt() ->> 'sub')
                  )
              )
        )
        OR private.is_super_admin()
    );

-- lab_bookings_update (20261020000001_consolidated — latest WITH CHECK for patient cancel)
DROP POLICY IF EXISTS "lab_bookings_update" ON public.lab_bookings;
CREATE POLICY "lab_bookings_update" ON public.lab_bookings
    FOR UPDATE TO authenticated
    USING (
        lab_id = private.current_profile_id()
        OR patient_id = private.current_profile_id()
        OR private.is_super_admin()
    )
    WITH CHECK (
        lab_id = private.current_profile_id()
        OR (patient_id = private.current_profile_id() AND status = 'cancelled')
        OR private.is_super_admin()
    );

-- lab_orders_insert / lab_orders_update (20261020000001_consolidated)
DROP POLICY IF EXISTS "lab_orders_insert" ON public.lab_orders;
CREATE POLICY "lab_orders_insert" ON public.lab_orders
    FOR INSERT TO authenticated
    WITH CHECK (
        doctor_id = private.current_profile_id()
        OR private.is_super_admin()
    );

DROP POLICY IF EXISTS "lab_orders_update" ON public.lab_orders;
CREATE POLICY "lab_orders_update" ON public.lab_orders
    FOR UPDATE TO authenticated
    USING (
        lab_id = private.current_profile_id()
        OR doctor_id = private.current_profile_id()
        OR private.is_super_admin()
    )
    WITH CHECK (
        lab_id = private.current_profile_id()
        OR doctor_id = private.current_profile_id()
        OR private.is_super_admin()
    );

-- pharmacy_connections (20261020000001_consolidated)
DROP POLICY IF EXISTS "pharmacy_conn_policy" ON public.pharmacy_connections;
DROP POLICY IF EXISTS "pharmacy_connections_select" ON public.pharmacy_connections;
DROP POLICY IF EXISTS "pharmacy_connections_write" ON public.pharmacy_connections;
CREATE POLICY "pharmacy_connections_select" ON public.pharmacy_connections
    FOR SELECT TO authenticated
    USING (
        doctor_id = private.current_profile_id()
        OR medical_store_id = private.current_profile_id()
        OR private.is_super_admin()
    );
CREATE POLICY "pharmacy_connections_write" ON public.pharmacy_connections
    FOR ALL TO authenticated
    USING (
        doctor_id = private.current_profile_id()
        OR medical_store_id = private.current_profile_id()
        OR private.is_super_admin()
    )
    WITH CHECK (
        doctor_id = private.current_profile_id()
        OR medical_store_id = private.current_profile_id()
        OR private.is_super_admin()
    );

-- lab_connections (20261020000001_consolidated)
DROP POLICY IF EXISTS "lab_conn_policy" ON public.lab_connections;
DROP POLICY IF EXISTS "lab_connections_select" ON public.lab_connections;
DROP POLICY IF EXISTS "lab_connections_write" ON public.lab_connections;
CREATE POLICY "lab_connections_select" ON public.lab_connections
    FOR SELECT TO authenticated
    USING (
        doctor_id = private.current_profile_id()
        OR lab_id = private.current_profile_id()
        OR private.is_super_admin()
    );
CREATE POLICY "lab_connections_write" ON public.lab_connections
    FOR ALL TO authenticated
    USING (
        doctor_id = private.current_profile_id()
        OR lab_id = private.current_profile_id()
        OR private.is_super_admin()
    )
    WITH CHECK (
        doctor_id = private.current_profile_id()
        OR lab_id = private.current_profile_id()
        OR private.is_super_admin()
    );

-- patient_doctor_links (20261020000001 consolidated pdl_select)
DROP POLICY IF EXISTS "doc_links_select" ON public.patient_doctor_links;
DROP POLICY IF EXISTS "pdl_select" ON public.patient_doctor_links;
CREATE POLICY "pdl_select" ON public.patient_doctor_links
    FOR SELECT TO authenticated
    USING (
        doctor_id = private.current_profile_id()
        OR EXISTS (
            SELECT 1 FROM public.patients p
            WHERE p.patient_id = patient_doctor_links.patient_id
              AND p.owner_uid = (auth.jwt() ->> 'sub')
        )
        OR private.is_super_admin()
    );

COMMIT;
