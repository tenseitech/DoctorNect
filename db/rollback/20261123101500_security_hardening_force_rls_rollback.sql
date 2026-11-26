-- Rollback for 20261123101500_security_hardening_force_rls.sql (idempotent).
-- Not applied by migrate.js — run manually when approved.

ALTER TABLE IF EXISTS private.admin_users NO FORCE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS private.provisioning_errors NO FORCE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.doctor_directory_updates NO FORCE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.doctor_invites NO FORCE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.doctor_private NO FORCE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.pharmacy_doctor_invites NO FORCE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.storage_audit_logs NO FORCE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.user_devices NO FORCE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.users NO FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS schema_migrations_migrator_only ON public._schema_migrations;
-- Intentionally leaves RLS enabled on _schema_migrations if it was enabled by forward migration.