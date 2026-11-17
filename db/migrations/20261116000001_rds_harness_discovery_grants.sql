-- Idempotent RDS grant repair after partial applies (NOT applied to production RDS as of 2026-11-15).
-- Aligns with 20261103000008: anon discovery = doctor_directory, review_public, lab_catalog_tests,
-- system_config only (RLS restricts rows). Does NOT grant anon on medical_directory or promoted_ads.
-- authenticated column-level UPDATE on users matches 20260930000003 (re-assert after REVOKE ALL drift).

GRANT USAGE ON SCHEMA public TO anon;

GRANT SELECT ON public.doctor_directory TO anon;
GRANT SELECT ON public.review_public TO anon;
GRANT SELECT ON public.lab_catalog_tests TO anon;
GRANT SELECT ON public.system_config TO anon;

REVOKE ALL ON TABLE public.medical_directory FROM anon;
REVOKE ALL ON TABLE public.promoted_ads FROM anon;

GRANT UPDATE (display_name, photo_url, photo_key, photo_storage, profile_completed)
  ON public.users TO authenticated;