-- Fix anon discovery: doctor_directory must run as definer (security_invoker=false) on RDS.
-- Re-assert 20261103000008 anon least-privilege (idempotent).

ALTER VIEW IF EXISTS public.doctor_directory SET (security_invoker = false);

DO $$
DECLARE
  v_owner name := current_user;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'doctornect_admin') THEN
    v_owner := 'doctornect_admin';
  ELSIF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rds_master') THEN
    v_owner := 'rds_master';
  END IF;
  EXECUTE format('ALTER VIEW public.doctor_directory OWNER TO %I', v_owner);
END
$$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    RETURN;
  END IF;
  REVOKE ALL ON TABLE public.medical_directory FROM anon;
  REVOKE ALL ON TABLE public.promoted_ads FROM anon;
  GRANT SELECT ON public.doctor_directory TO anon;
  GRANT SELECT ON public.review_public TO anon;
  GRANT SELECT ON public.lab_catalog_tests TO anon;
  GRANT SELECT ON public.system_config TO anon;
END
$$;