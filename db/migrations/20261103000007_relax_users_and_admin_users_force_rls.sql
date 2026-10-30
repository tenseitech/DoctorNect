-- Migration: 20261103000007_relax_users_and_admin_users_force_rls.sql
-- Description: Relax FORCE ROW LEVEL SECURITY on public.users and private.admin_users to prevent mutual RLS recursion in is_super_admin()
--
-- Background:
-- When is_super_admin() is called by functions/triggers or RLS policies (e.g. in book_appointment_atomic),
-- it runs as a SECURITY DEFINER function owned by the migration runner (rds_master on RDS).
-- If public.users has FORCE ROW LEVEL SECURITY, rds_master (non-superuser) is subject to RLS policies
-- on public.users. The SELECT policy on public.users calls is_super_admin(), which queries public.users,
-- creating an infinite mutual recursion (SQLSTATE 54001: stack depth limit exceeded).
--
-- Relaxing FORCE ROW LEVEL SECURITY allows the table owner (and SECURITY DEFINER functions)
-- to query users and admin_users directly without triggering the table's own RLS policies.
-- ROW LEVEL SECURITY remains ENABLED (ENABLE ROW LEVEL SECURITY), so all client requests (anon, authenticated)
-- are still strictly restricted by RLS policies.

ALTER TABLE public.users NO FORCE ROW LEVEL SECURITY;
ALTER TABLE private.admin_users NO FORCE ROW LEVEL SECURITY;
