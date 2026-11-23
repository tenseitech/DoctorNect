-- Part C security hardening (idempotent): FORCE RLS on tables flagged in prod catalog 2026-11-23.
-- DEFERRED: Phase 2 — apply after staging `rls_sql_harness.js` passes with definer re-home plan.
-- Do not apply to production without operator "approved prod".

-- Migration ledger only: enable RLS (service_role/migrator still bypass via role).
ALTER TABLE IF EXISTS public._schema_migrations ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS schema_migrations_migrator_only ON public._schema_migrations;
CREATE POLICY schema_migrations_migrator_only ON public._schema_migrations
  FOR ALL TO doctornect_admin
  USING (true)
  WITH CHECK (true);
COMMENT ON POLICY schema_migrations_migrator_only ON public._schema_migrations IS
  'Migrator read/write; authenticated/anon have no policy rows.';

ALTER TABLE IF EXISTS private.admin_users FORCE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS private.provisioning_errors FORCE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.doctor_directory_updates FORCE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.doctor_invites FORCE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.doctor_private FORCE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.pharmacy_doctor_invites FORCE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.storage_audit_logs FORCE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.user_devices FORCE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.users FORCE ROW LEVEL SECURITY;