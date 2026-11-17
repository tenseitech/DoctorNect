-- AWS RDS PostgreSQL (no Supabase auth.jwt / anon-authenticated RLS roles).
-- Apply in approved DBA window only. Idempotent where noted.
-- Security: super-admin enforcement at gateway + Cloud Functions; DB triggers are defense-in-depth.

CREATE SCHEMA IF NOT EXISTS private;

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

CREATE OR REPLACE FUNCTION private.trg_users_protect_system_admin_delete()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, private
AS $$
BEGIN
  IF private.is_system_admin_user(OLD.id) THEN
    RAISE EXCEPTION 'SYSTEM_ADMIN_PROTECTED: platform admin cannot be deleted';
  END IF;
  RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS users_protect_system_admin_delete ON public.users;
CREATE TRIGGER users_protect_system_admin_delete
  BEFORE DELETE ON public.users
  FOR EACH ROW
  EXECUTE FUNCTION private.trg_users_protect_system_admin_delete();

-- Audit logs: append-only at DB layer (writes only via application service role).
REVOKE ALL ON TABLE public.admin_audit_logs FROM PUBLIC;
REVOKE INSERT, UPDATE, DELETE ON TABLE public.admin_audit_logs FROM PUBLIC;
-- PostgREST / gateway uses service_role only for this table (see api-gateway config).

CREATE OR REPLACE FUNCTION private.trg_admin_audit_logs_append_only()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, private
AS $$
BEGIN
  RAISE EXCEPTION 'admin_audit_logs is append-only';
END;
$$;

DROP TRIGGER IF EXISTS admin_audit_logs_append_only ON public.admin_audit_logs;
CREATE TRIGGER admin_audit_logs_append_only
  BEFORE UPDATE OR DELETE ON public.admin_audit_logs
  FOR EACH ROW
  EXECUTE FUNCTION private.trg_admin_audit_logs_append_only();

COMMENT ON TABLE public.admin_audit_logs IS
  'RDS: append-only; Cloud Functions + gateway service_role only.';
