-- DoctorNect Migration: 20261125000002_policies_use_private_is_super_admin.sql
-- Description: BUG/SECURITY FIX found by the from-scratch SQL test replay (db/tests).
-- public.is_super_admin(text) is not executable by `authenticated` (deny-by-default overload,
-- see 20261113000003), but several RLS policies still call
--     is_super_admin((auth.jwt() ->> 'sub'))
-- PostgreSQL checks EXECUTE when the policy expression is initialised, so OR-ing it with an
-- owner predicate does not help: every authenticated query on those tables fails with
-- "permission denied for function is_super_admin" (in_app_notifications, mail_queue,
-- promoted_ads, razorpay_*, security_events, super_admins, support_ticket_messages).
-- Rewrites each affected policy in place (ALTER POLICY keeps name, command, roles, permissive)
-- to use private.is_super_admin(), which derives the caller from the JWT and is executable by
-- authenticated. Idempotent: a second run finds nothing to rewrite.

DO $$
DECLARE
    r record;
    v_pat constant text := '(public\.)?is_super_admin\(\(auth\.jwt\(\) ->> ''sub''::text\)\)';
    v_qual text;
    v_check text;
    v_sql text;
BEGIN
    PERFORM set_config('search_path', 'public', true);  -- pg_policies decompiles relative to public
    FOR r IN
        SELECT schemaname, tablename, policyname, qual, with_check
          FROM pg_policies
         WHERE schemaname = 'public'
           AND (coalesce(qual, '') ~ v_pat OR coalesce(with_check, '') ~ v_pat)
    LOOP
        v_qual := regexp_replace(r.qual, v_pat, 'private.is_super_admin()', 'g');
        v_check := regexp_replace(r.with_check, v_pat, 'private.is_super_admin()', 'g');
        v_sql := format('ALTER POLICY %I ON %I.%I', r.policyname, r.schemaname, r.tablename);
        IF v_qual IS NOT NULL THEN
            v_sql := v_sql || format(' USING (%s)', v_qual);
        END IF;
        IF v_check IS NOT NULL THEN
            v_sql := v_sql || format(' WITH CHECK (%s)', v_check);
        END IF;
        EXECUTE v_sql;
        RAISE NOTICE 'rewrote policy %.% to private.is_super_admin()', r.tablename, r.policyname;
    END LOOP;
END;
$$;
