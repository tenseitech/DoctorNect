-- PROPOSED (do not apply automatically): verified-role checks on provider policies.
-- Idempotent DROP POLICY IF EXISTS + CREATE POLICY pattern.

-- ---------------------------------------------------------------------------
-- Helpers (mirror private.is_verified_doctor())
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.is_verified_lab()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.labs
        WHERE lab_id = private.current_profile_id()
          AND verified IS TRUE
          AND COALESCE(deactivated, FALSE) IS FALSE
    );
$$;

CREATE OR REPLACE FUNCTION private.is_verified_medical_store()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.medical_stores
        WHERE store_id = private.current_profile_id()
          AND verified IS TRUE
          AND COALESCE(deactivated, FALSE) IS FALSE
    );
$$;

REVOKE ALL ON FUNCTION private.is_verified_lab() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION private.is_verified_medical_store() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.is_verified_lab() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION private.is_verified_medical_store() TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Appointments (doctor accept / update without verified check today)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "appointments_select" ON public.appointments;
CREATE POLICY "appointments_select" ON public.appointments
    FOR SELECT TO authenticated
    USING (
        patient_id = private.current_profile_id()
        OR (doctor_id = private.current_profile_id() AND private.is_verified_doctor())
        OR private.is_super_admin()
    );

DROP POLICY IF EXISTS "appointments_update" ON public.appointments;
CREATE POLICY "appointments_update" ON public.appointments
    FOR UPDATE TO authenticated
    USING (
        patient_id = private.current_profile_id()
        OR (doctor_id = private.current_profile_id() AND private.is_verified_doctor())
        OR private.is_super_admin()
    )
    WITH CHECK (
        (doctor_id = private.current_profile_id() AND private.is_verified_doctor())
        OR (
            patient_id = private.current_profile_id()
            AND patient_status = 'cancelled'
        )
        OR private.is_super_admin()
    );

-- ---------------------------------------------------------------------------
-- Prescriptions SELECT (doctor_id match without verified today)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "prescriptions_select" ON public.prescriptions;
CREATE POLICY "prescriptions_select" ON public.prescriptions
    FOR SELECT TO authenticated
    USING (
        patient_id = private.current_profile_id()
        OR (doctor_id = private.current_profile_id() AND private.is_verified_doctor())
        OR EXISTS (
            SELECT 1 FROM pharmacy_deliveries pd
            WHERE pd.prescription_id = prescriptions.prescription_id
              AND pd.store_id = private.current_profile_id()
        )
        OR private.is_super_admin()
    );

-- ---------------------------------------------------------------------------
-- Lab bookings / orders (lab_id / doctor_id without verified)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "lab_bookings_update" ON public.lab_bookings;
CREATE POLICY "lab_bookings_update" ON public.lab_bookings
    FOR UPDATE TO authenticated
    USING (
        (lab_id = private.current_profile_id() AND private.is_verified_lab())
        OR patient_id = private.current_profile_id()
        OR private.is_super_admin()
    )
    WITH CHECK (
        (lab_id = private.current_profile_id() AND private.is_verified_lab())
        OR (patient_id = private.current_profile_id() AND status = 'cancelled')
        OR private.is_super_admin()
    );

DROP POLICY IF EXISTS "lab_orders_insert" ON public.lab_orders;
CREATE POLICY "lab_orders_insert" ON public.lab_orders
    FOR INSERT TO authenticated
    WITH CHECK (
        (doctor_id = private.current_profile_id() AND private.is_verified_doctor())
        OR private.is_super_admin()
    );

DROP POLICY IF EXISTS "lab_orders_update" ON public.lab_orders;
CREATE POLICY "lab_orders_update" ON public.lab_orders
    FOR UPDATE TO authenticated
    USING (
        (lab_id = private.current_profile_id() AND private.is_verified_lab())
        OR (doctor_id = private.current_profile_id() AND private.is_verified_doctor())
        OR private.is_super_admin()
    )
    WITH CHECK (
        (lab_id = private.current_profile_id() AND private.is_verified_lab())
        OR (doctor_id = private.current_profile_id() AND private.is_verified_doctor())
        OR private.is_super_admin()
    );

-- ---------------------------------------------------------------------------
-- Pharmacy connections (doctor_id without verified)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "pharmacy_connections_select" ON public.pharmacy_connections;
CREATE POLICY "pharmacy_connections_select" ON public.pharmacy_connections
    FOR SELECT TO authenticated
    USING (
        (doctor_id = private.current_profile_id() AND private.is_verified_doctor())
        OR (medical_store_id = private.current_profile_id() AND private.is_verified_medical_store())
        OR private.is_super_admin()
    );

DROP POLICY IF EXISTS "pharmacy_connections_write" ON public.pharmacy_connections;
CREATE POLICY "pharmacy_connections_write" ON public.pharmacy_connections
    FOR ALL TO authenticated
    USING (
        (doctor_id = private.current_profile_id() AND private.is_verified_doctor())
        OR (medical_store_id = private.current_profile_id() AND private.is_verified_medical_store())
        OR private.is_super_admin()
    )
    WITH CHECK (
        (doctor_id = private.current_profile_id() AND private.is_verified_doctor())
        OR (medical_store_id = private.current_profile_id() AND private.is_verified_medical_store())
        OR private.is_super_admin()
    );

-- ---------------------------------------------------------------------------
-- Patient doctor links (doctor_id without verified on SELECT)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "pdl_select" ON public.patient_doctor_links;
CREATE POLICY "pdl_select" ON public.patient_doctor_links
    FOR SELECT TO authenticated
    USING (
        (doctor_id = private.current_profile_id() AND private.is_verified_doctor())
        OR EXISTS (
            SELECT 1 FROM patients p
            WHERE p.patient_id = patient_doctor_links.patient_id
              AND p.owner_uid = (auth.jwt() ->> 'sub')
        )
        OR private.is_super_admin()
    );
