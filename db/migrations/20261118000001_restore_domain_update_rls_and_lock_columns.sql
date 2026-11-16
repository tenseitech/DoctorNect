-- Revert round6 USING(true) domain UPDATE policies; tighten lock_columns (no auth.uid() NULL client bypass).

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
    IF v_is_admin THEN
        RETURN NEW;
    END IF;
    IF current_setting('role', true) = 'service_role'
       OR (auth.jwt() ->> 'role') = 'service_role' THEN
        RETURN NEW;
    END IF;
    IF pg_trigger_depth() > 1 THEN
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

DROP POLICY IF EXISTS "doctors_update" ON public.doctors;
CREATE POLICY "doctors_update" ON public.doctors
    FOR UPDATE TO authenticated
    USING (
        owner_uid = (auth.jwt() ->> 'sub')
        OR doctor_id = private.current_profile_id()
        OR private.is_super_admin()
    )
    WITH CHECK (
        owner_uid = (auth.jwt() ->> 'sub')
        OR doctor_id = private.current_profile_id()
        OR private.is_super_admin()
    );

DROP POLICY IF EXISTS "patients_update" ON public.patients;
CREATE POLICY "patients_update" ON public.patients
    FOR UPDATE TO authenticated
    USING (
        owner_uid = (auth.jwt() ->> 'sub')
        OR patient_id = private.current_profile_id()
        OR private.is_super_admin()
    )
    WITH CHECK (
        owner_uid = (auth.jwt() ->> 'sub')
        OR patient_id = private.current_profile_id()
        OR private.is_super_admin()
    );

DROP POLICY IF EXISTS "labs_update" ON public.labs;
CREATE POLICY "labs_update" ON public.labs
    FOR UPDATE TO authenticated
    USING (
        owner_uid = (auth.jwt() ->> 'sub')
        OR lab_id = private.current_profile_id()
        OR private.is_super_admin()
    )
    WITH CHECK (
        owner_uid = (auth.jwt() ->> 'sub')
        OR lab_id = private.current_profile_id()
        OR private.is_super_admin()
    );

DROP POLICY IF EXISTS "medical_stores_update" ON public.medical_stores;
CREATE POLICY "medical_stores_update" ON public.medical_stores
    FOR UPDATE TO authenticated
    USING (
        owner_uid = (auth.jwt() ->> 'sub')
        OR store_id = private.current_profile_id()
        OR private.is_super_admin()
    )
    WITH CHECK (
        owner_uid = (auth.jwt() ->> 'sub')
        OR store_id = private.current_profile_id()
        OR private.is_super_admin()
    );

DROP POLICY IF EXISTS "ambulances_update" ON public.ambulances;
CREATE POLICY "ambulances_update" ON public.ambulances
    FOR UPDATE TO authenticated
    USING (
        auth_uid = (auth.jwt() ->> 'sub')
        OR ambulance_id = private.current_profile_id()
        OR private.is_super_admin()
    )
    WITH CHECK (
        auth_uid = (auth.jwt() ->> 'sub')
        OR ambulance_id = private.current_profile_id()
        OR private.is_super_admin()
    );