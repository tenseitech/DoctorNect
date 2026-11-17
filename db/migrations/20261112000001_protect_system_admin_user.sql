-- Protect fixed platform super admin (admin@doctornect.com) from role/suspend/email mutations.
-- Apply on STAGING first; production: run same file during next RDS migration window.

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS is_system_admin BOOLEAN NOT NULL DEFAULT FALSE;

UPDATE public.users
SET is_system_admin = TRUE
WHERE lower(trim(email)) = 'admin@doctornect.com';

CREATE OR REPLACE FUNCTION private.is_system_admin_user(p_user_id TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SET search_path = public, private
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.users u
    WHERE u.id = p_user_id
      AND (
        u.is_system_admin IS TRUE
        OR lower(trim(u.email)) = 'admin@doctornect.com'
      )
  );
$$;

CREATE OR REPLACE FUNCTION private.trg_users_protect_system_admin()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, private
AS $$
BEGIN
  IF NOT private.is_system_admin_user(OLD.id) THEN
    RETURN NEW;
  END IF;

  IF NEW.role IS DISTINCT FROM OLD.role THEN
    RAISE EXCEPTION 'SYSTEM_ADMIN_PROTECTED: role cannot change for platform admin';
  END IF;

  IF lower(trim(COALESCE(NEW.email, ''))) IS DISTINCT FROM lower(trim(COALESCE(OLD.email, ''))) THEN
    RAISE EXCEPTION 'SYSTEM_ADMIN_PROTECTED: email cannot change for platform admin';
  END IF;

  IF NEW.is_system_admin IS DISTINCT FROM OLD.is_system_admin AND NEW.is_system_admin IS NOT TRUE THEN
    RAISE EXCEPTION 'SYSTEM_ADMIN_PROTECTED: is_system_admin cannot be cleared';
  END IF;

  IF NEW.deactivated IS TRUE AND COALESCE(OLD.deactivated, FALSE) IS NOT TRUE THEN
    RAISE EXCEPTION 'SYSTEM_ADMIN_PROTECTED: platform admin cannot be suspended';
  END IF;

  IF lower(COALESCE(NEW.status, '')) = 'suspended'
     AND lower(COALESCE(OLD.status, '')) IS DISTINCT FROM 'suspended' THEN
    RAISE EXCEPTION 'SYSTEM_ADMIN_PROTECTED: platform admin status cannot be suspended';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS users_protect_system_admin ON public.users;
CREATE TRIGGER users_protect_system_admin
  BEFORE UPDATE ON public.users
  FOR EACH ROW
  EXECUTE FUNCTION private.trg_users_protect_system_admin();

COMMENT ON COLUMN public.users.is_system_admin IS
  'Immutable marker for admin@doctornect.com — excluded from user counts and protected by trigger.';
