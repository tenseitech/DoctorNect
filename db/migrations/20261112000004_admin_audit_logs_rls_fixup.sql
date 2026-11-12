-- Fix admin_audit_logs 403: legacy policies referenced public.is_super_admin() (permission denied).
-- Normalize to private.is_super_admin() + table GRANTs + append-only deny policies.

GRANT SELECT, INSERT ON TABLE public.admin_audit_logs TO authenticated;
REVOKE UPDATE, DELETE ON TABLE public.admin_audit_logs FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION private.is_super_admin() TO authenticated, service_role;

DROP POLICY IF EXISTS "audit_logs_select" ON public.admin_audit_logs;
DROP POLICY IF EXISTS "audit_logs_insert" ON public.admin_audit_logs;
DROP POLICY IF EXISTS "audit_logs_deny_update" ON public.admin_audit_logs;
DROP POLICY IF EXISTS "audit_logs_deny_delete" ON public.admin_audit_logs;

DROP POLICY IF EXISTS "admin_audit_logs_select" ON public.admin_audit_logs;
CREATE POLICY "admin_audit_logs_select" ON public.admin_audit_logs
  FOR SELECT TO authenticated
  USING (private.is_super_admin());

DROP POLICY IF EXISTS "admin_audit_logs_insert" ON public.admin_audit_logs;
CREATE POLICY "admin_audit_logs_insert" ON public.admin_audit_logs
  FOR INSERT TO authenticated
  WITH CHECK (private.is_super_admin());

DROP POLICY IF EXISTS "admin_audit_logs_deny_update" ON public.admin_audit_logs;
CREATE POLICY "admin_audit_logs_deny_update" ON public.admin_audit_logs
  FOR UPDATE TO authenticated
  USING (false);

DROP POLICY IF EXISTS "admin_audit_logs_deny_delete" ON public.admin_audit_logs;
CREATE POLICY "admin_audit_logs_deny_delete" ON public.admin_audit_logs
  FOR DELETE TO authenticated
  USING (false);
