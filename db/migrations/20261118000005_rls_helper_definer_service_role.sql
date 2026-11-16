-- FORCE RLS: RLS policy helpers must run as service_role (BYPASSRLS), not doctornect_admin table owner.
-- Apply as migrator (function owner). PostgreSQL ALTER ... OWNER TO requires the new owner to hold CREATE on the function's schema (USAGE on private/public is not enough).

GRANT CREATE ON SCHEMA private TO service_role;
GRANT CREATE ON SCHEMA public TO service_role;

ALTER FUNCTION private.doctor_can_access_patient(text) OWNER TO service_role;
ALTER FUNCTION private.current_profile_id() OWNER TO service_role;
ALTER FUNCTION private.is_verified_doctor() OWNER TO service_role;
ALTER FUNCTION public.fn_sync_review_aggregates() OWNER TO service_role;

-- Trigger fn_sync_review_aggregates DMLs review_public as service_role (SECURITY DEFINER after re-home).
GRANT SELECT, INSERT, UPDATE, DELETE ON public.review_public TO service_role;