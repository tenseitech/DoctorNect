-- PROPOSED (do not apply): verified-role checks on provider policies.
-- Rebuilt from latest migration definitions per policy (not 20261020-only baseline).
-- Drops legacy duplicate policy names (OR-combined) before CREATE.

-- ---------------------------------------------------------------------------
-- Helpers (labs.deactivated / medical_stores.deactivated: 20260923000001_doctornect_schema.sql)
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
-- Appointments (base: select 20261102000001, update 20261026000001)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "appointments_select" ON public.appointments;
CREATE POLICY "appointments_select" ON public.appointments
    FOR SELECT TO authenticated
    USING (
        patient_id = private.current_profile_id()
        OR (doctor_id = private.current_profile_id() AND private.is_verified_doctor())
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

DROP POLICY IF EXISTS "appointments_update" ON public.appointments;
CREATE POLICY "appointments_update" ON public.appointments
    FOR UPDATE TO authenticated
    USING (
        patient_id = private.current_profile_id()
        OR (doctor_id = private.current_profile_id() AND private.is_verified_doctor())
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
        (doctor_id = private.current_profile_id() AND private.is_verified_doctor())
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

-- ---------------------------------------------------------------------------
-- Prescriptions SELECT (base: 20261021000002_phase_d_pharmacy_lab_ambulance.sql)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "prescriptions_select" ON public.prescriptions;
CREATE POLICY "prescriptions_select" ON public.prescriptions
    FOR SELECT TO authenticated
    USING (
        patient_id = private.current_profile_id()
        OR (doctor_id = private.current_profile_id() AND private.is_verified_doctor())
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

-- ---------------------------------------------------------------------------
-- Lab bookings UPDATE (base: 20260930000004_access_gap_fixes.sql)
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

-- ---------------------------------------------------------------------------
-- Lab orders (base: 20261020000001 consolidated lab_orders_*)
-- ---------------------------------------------------------------------------
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
-- Pharmacy connections — drop ALL legacy names (609230002 pharmacy_conn_policy + consolidated)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "pharmacy_conn_policy" ON public.pharmacy_connections;
DROP POLICY IF EXISTS "pharmacy_connections_select" ON public.pharmacy_connections;
DROP POLICY IF EXISTS "pharmacy_connections_write" ON public.pharmacy_connections;
CREATE POLICY "pharmacy_connections_select" ON public.pharmacy_connections
    FOR SELECT TO authenticated
    USING (
        (doctor_id = private.current_profile_id() AND private.is_verified_doctor())
        OR medical_store_id = private.current_profile_id()
        OR private.is_super_admin()
    );
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
-- Lab connections — drop legacy lab_conn_policy + consolidated names
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "lab_conn_policy" ON public.lab_connections;
DROP POLICY IF EXISTS "lab_connections_select" ON public.lab_connections;
DROP POLICY IF EXISTS "lab_connections_write" ON public.lab_connections;
CREATE POLICY "lab_connections_select" ON public.lab_connections
    FOR SELECT TO authenticated
    USING (
        (private.is_verified_doctor() AND doctor_id = private.current_profile_id())
        OR lab_id = private.current_profile_id()
        OR private.is_super_admin()
    );
CREATE POLICY "lab_connections_write" ON public.lab_connections
    FOR ALL TO authenticated
    USING (
        (private.is_verified_doctor() AND doctor_id = private.current_profile_id())
        OR (lab_id = private.current_profile_id() AND private.is_verified_lab())
        OR private.is_super_admin()
    )
    WITH CHECK (
        (private.is_verified_doctor() AND doctor_id = private.current_profile_id())
        OR (lab_id = private.current_profile_id() AND private.is_verified_lab())
        OR private.is_super_admin()
    );

-- ---------------------------------------------------------------------------
-- Patient doctor links — drop doc_links_select (609230002) + pdl_select (consolidated)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "doc_links_select" ON public.patient_doctor_links;
DROP POLICY IF EXISTS "pdl_select" ON public.patient_doctor_links;
CREATE POLICY "pdl_select" ON public.patient_doctor_links
    FOR SELECT TO authenticated
    USING (
        (doctor_id = private.current_profile_id() AND private.is_verified_doctor())
        OR EXISTS (
            SELECT 1 FROM public.patients p
            WHERE p.patient_id = patient_doctor_links.patient_id
              AND p.owner_uid = (auth.jwt() ->> 'sub')
        )
        OR private.is_super_admin()
    );
