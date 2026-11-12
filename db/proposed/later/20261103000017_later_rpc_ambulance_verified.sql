-- PROPOSED (later — AMBULANCE_ENABLED off): verified-driver guards on ambulance mutator RPCs.
-- Apply only when ambulance product/SQL are enabled. Not part of launch 000017 bundle.

CREATE OR REPLACE FUNCTION private.is_verified_ambulance_driver()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.ambulances
        WHERE ambulance_id = private.current_profile_id()
          AND verified IS TRUE
    );
$$;

REVOKE ALL ON FUNCTION private.is_verified_ambulance_driver() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.is_verified_ambulance_driver() TO authenticated, service_role;

-- Patch pattern (apply inside deployed bodies from 20261026000001 after driver resolution):
-- IF NOT v_is_admin AND NOT COALESCE(private.is_verified_ambulance_driver(), FALSE) THEN
--   RAISE EXCEPTION 'FORBIDDEN: Verified ambulance driver required' USING ERRCODE = '42501';
-- END IF;
-- Functions: accept_ambulance_request, update_ambulance_location, complete_ambulance_trip
