-- FORCE RLS: SECURITY DEFINER helpers that DML FORCE RLS / deny-all tables must run as service_role (BYPASSRLS), not doctornect_admin.
-- PostgreSQL ALTER ... OWNER TO requires temporary CREATE on schema for the new owner.

GRANT CREATE ON SCHEMA private TO service_role;
GRANT CREATE ON SCHEMA public TO service_role;

ALTER FUNCTION private.doctor_can_access_patient(text) OWNER TO service_role;
ALTER FUNCTION private.current_profile_id() OWNER TO service_role;
ALTER FUNCTION private.is_verified_doctor() OWNER TO service_role;
ALTER FUNCTION public.fn_sync_review_aggregates() OWNER TO service_role;

-- Re-home DEFINER functions that write FORCE RLS internal tables (harness seed + RPC/triggers).
DO $rehome$
DECLARE
  targets text[] := ARRAY[
    'private.trg_ambulance_broadcast_contact_guard()',
    'public.enqueue_notification_outbox()',
    'public.accept_ambulance_request(character varying, character varying)',
    'public.update_ambulance_location(character varying, double precision, double precision, double precision, double precision)',
    'public.check_and_increment_rate_limit(text, integer, integer, text)'
  ];
  t text;
BEGIN
  FOREACH t IN ARRAY targets LOOP
    BEGIN
      EXECUTE format('ALTER FUNCTION %s OWNER TO service_role', t);
    EXCEPTION
      WHEN undefined_function THEN
        RAISE NOTICE 'skip missing function %', t;
    END;
  END LOOP;
END;
$rehome$;

REVOKE CREATE ON SCHEMA private FROM service_role;
REVOKE CREATE ON SCHEMA public FROM service_role;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.review_public TO service_role;