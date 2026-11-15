-- Block client UPDATE of aggregate/rating fields on doctors (harness + security parity with domain guards).

CREATE OR REPLACE FUNCTION private.block_doctors_privileged_rating_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF COALESCE(private.is_super_admin(), FALSE) OR auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;
  IF NEW.rating IS DISTINCT FROM OLD.rating
     OR NEW.review_count IS DISTINCT FROM OLD.review_count THEN
    RAISE EXCEPTION 'FORBIDDEN: rating fields are server-maintained'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION private.block_doctors_privileged_rating_update() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_block_doctors_rating_update ON public.doctors;
CREATE TRIGGER trg_block_doctors_rating_update
  BEFORE UPDATE ON public.doctors
  FOR EACH ROW
  EXECUTE FUNCTION private.block_doctors_privileged_rating_update();