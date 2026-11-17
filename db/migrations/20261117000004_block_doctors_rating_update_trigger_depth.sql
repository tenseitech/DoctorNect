-- Allow trusted-writer / aggregate triggers to update rating fields (server-maintained only).

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
  IF pg_trigger_depth() > 1 THEN
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