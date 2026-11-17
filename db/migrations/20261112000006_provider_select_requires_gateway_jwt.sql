-- Require gateway-minted JWT sub for provider directory SELECT (blocks authenticated role with empty claims).
-- Verified directory rows remain readable to any signed-in module user with a valid Firebase sub.

DROP POLICY IF EXISTS medical_stores_select ON public.medical_stores;
CREATE POLICY medical_stores_select ON public.medical_stores
    FOR SELECT TO authenticated
    USING (
        private.current_firebase_uid() IS NOT NULL
        AND (
            verified = TRUE
            OR owner_uid = private.current_user_id()
            OR private.is_super_admin()
        )
    );

DROP POLICY IF EXISTS labs_select ON public.labs;
CREATE POLICY labs_select ON public.labs
    FOR SELECT TO authenticated
    USING (
        private.current_firebase_uid() IS NOT NULL
        AND (
            verified = TRUE
            OR owner_uid = private.current_user_id()
            OR private.is_super_admin()
        )
    );

DROP POLICY IF EXISTS ambulances_select ON public.ambulances;
CREATE POLICY ambulances_select ON public.ambulances
    FOR SELECT TO authenticated
    USING (
        private.current_firebase_uid() IS NOT NULL
        AND (
            auth_uid = private.current_user_id()
            OR (is_available = TRUE AND verified = TRUE)
            OR private.is_super_admin()
        )
    );
