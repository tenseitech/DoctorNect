-- Admin audit logs: append-only; only service_role (Cloud Functions) may INSERT.
-- Clients (authenticated JWT) may SELECT when super_admin.

REVOKE INSERT ON TABLE public.admin_audit_logs FROM authenticated;
DROP POLICY IF EXISTS "admin_audit_logs_insert" ON public.admin_audit_logs;
