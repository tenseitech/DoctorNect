-- RDS + staging: idempotent public discovery grants for anon (harness + Play review).
-- Does not weaken RLS; only restores table/view privileges dropped during partial applies.

GRANT USAGE ON SCHEMA public TO anon;

GRANT SELECT ON public.doctor_directory TO anon;
GRANT SELECT ON public.review_public TO anon;
GRANT SELECT ON public.promoted_ads TO anon;
GRANT SELECT ON public.medical_directory TO anon;
GRANT SELECT ON public.lab_catalog_tests TO anon;

-- Owner may update safe profile fields on public.users (column-level; see 20260930000003).
GRANT UPDATE (display_name, photo_url, photo_key, photo_storage, profile_completed)
  ON public.users TO authenticated;