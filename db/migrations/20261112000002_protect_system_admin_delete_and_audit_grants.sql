-- System admin hardening (complements 20261112000001 — do not edit prior file if already applied).
-- Staging + RDS: same file. Blocks DELETE on platform admin; audit_logs table grants for PostgREST.

-- Requires 20261112000001 (private.is_system_admin_user).

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

-- Super admins may delete other users, but never the fixed system admin row.
DROP POLICY IF EXISTS "users_delete_admin" ON public.users;
CREATE POLICY "users_delete_admin" ON public.users
  FOR DELETE TO authenticated
  USING (
    private.is_super_admin()
    AND NOT private.is_system_admin_user(id)
  );

-- PostgREST 403 root cause: least-privilege migration left zero GRANTs on admin_audit_logs for authenticated.
GRANT SELECT, INSERT ON TABLE public.admin_audit_logs TO authenticated;
REVOKE UPDATE, DELETE ON TABLE public.admin_audit_logs FROM PUBLIC, anon, authenticated;

DROP POLICY IF EXISTS "admin_audit_logs_deny_update" ON public.admin_audit_logs;
CREATE POLICY "admin_audit_logs_deny_update" ON public.admin_audit_logs
  FOR UPDATE TO authenticated
  USING (false);

DROP POLICY IF EXISTS "admin_audit_logs_deny_delete" ON public.admin_audit_logs;
CREATE POLICY "admin_audit_logs_deny_delete" ON public.admin_audit_logs
  FOR DELETE TO authenticated
  USING (false);

COMMENT ON TRIGGER users_protect_system_admin_delete ON public.users IS
  'Prevents DELETE of admin@doctornect.com / is_system_admin rows at DB level.';
