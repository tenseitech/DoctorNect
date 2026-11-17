-- Allow backend (PostgREST service_role JWT) to append audit rows; clients remain INSERT-denied (000005).

DROP POLICY IF EXISTS admin_audit_logs_insert_service ON public.admin_audit_logs;
CREATE POLICY admin_audit_logs_insert_service
    ON public.admin_audit_logs
    FOR INSERT
    TO service_role
    WITH CHECK (true);

GRANT INSERT ON TABLE public.admin_audit_logs TO service_role;
