-- ============================================================================
-- DoctorNect Platform — Live Database Pre-Migration Audit Suite
-- File: scratch/live_db_checks.sql
-- Run this script in the Supabase SQL Editor on Staging & Production
-- ============================================================================

-- ============================================================================
-- CHECK 1: Policies applying to anon/public that call RLS helper functions
-- (Checks across both 'public' and 'storage' schemas)
-- Expected: 0 rows (confirms revoking anon from helpers causes zero regressions)
-- ============================================================================
SELECT 
    schemaname, 
    tablename, 
    policyname, 
    roles, 
    cmd,
    qual, 
    with_check
FROM pg_policies
WHERE schemaname IN ('public', 'storage')
  AND (
      'anon' = ANY(roles) 
      OR 'public' = ANY(roles) 
      OR roles IS NULL 
      OR array_length(roles, 1) = 0
  )
  AND (
      qual ~* '(current_profile_id|current_user_role|is_super_admin|is_verified_doctor|is_profile_completed|doctor_can_access_patient)'
      OR with_check ~* '(current_profile_id|current_user_role|is_super_admin|is_verified_doctor|is_profile_completed|doctor_can_access_patient)'
  );

-- ============================================================================
-- CHECK 2: All policies in the 'storage' schema referencing the 6 helpers
-- (Ensures storage bucket RLS policies are accounted for)
-- ============================================================================
SELECT 
    schemaname, 
    tablename, 
    policyname, 
    roles, 
    cmd,
    qual, 
    with_check
FROM pg_policies
WHERE schemaname = 'storage'
  AND (
      qual ~* '(current_profile_id|current_user_role|is_super_admin|is_verified_doctor|is_profile_completed|doctor_can_access_patient)'
      OR with_check ~* '(current_profile_id|current_user_role|is_super_admin|is_verified_doctor|is_profile_completed|doctor_can_access_patient)'
  );

-- ============================================================================
-- CHECK 3: Views, Functions & Triggers referencing the 6 helpers outside policies
-- ============================================================================

-- 3A. Functions referencing the 6 helpers (excluding definitions of the helpers themselves)
-- Uses a CTE to filter p.prokind IN ('f', 'p') (standard functions and procedures)
-- before calling pg_get_functiondef, which errors on aggregate or window functions.
WITH candidate_procs AS (
    SELECT 
        p.oid,
        n.nspname AS schema_name,
        p.proname AS function_name
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname IN ('public', 'private', 'storage')
      AND p.prokind IN ('f', 'p')
      AND p.proname NOT IN (
          'current_profile_id', 'current_user_role', 'is_super_admin',
          'is_verified_doctor', 'is_profile_completed', 'doctor_can_access_patient'
      )
)
SELECT 
    schema_name,
    function_name,
    pg_get_functiondef(oid) AS definition
FROM candidate_procs
WHERE pg_get_functiondef(oid) ~* '(current_profile_id|current_user_role|is_super_admin|is_verified_doctor|is_profile_completed|doctor_can_access_patient)';

-- 3B. Views referencing the 6 helpers
SELECT 
    schemaname,
    viewname,
    definition
FROM pg_views
WHERE schemaname IN ('public', 'private', 'storage')
  AND definition ~* '(current_profile_id|current_user_role|is_super_admin|is_verified_doctor|is_profile_completed|doctor_can_access_patient)';

-- 3C. Triggers referencing the 6 helpers
SELECT 
    event_object_schema AS schema_name,
    event_object_table AS table_name,
    trigger_name,
    action_statement
FROM information_schema.triggers
WHERE event_object_schema IN ('public', 'storage')
  AND action_statement ~* '(current_profile_id|current_user_role|is_super_admin|is_verified_doctor|is_profile_completed|doctor_can_access_patient)';

-- ============================================================================
-- CHECK 4: Allowlist Admin Email Existence & Email Verification Status
-- (Crucial pre-condition before applying 20260930000002_admin_users_table.sql)
-- ============================================================================
SELECT 
    id AS auth_user_id,
    email,
    email_confirmed_at,
    created_at,
    last_sign_in_at,
    (email_confirmed_at IS NOT NULL) AS is_email_confirmed
FROM auth.users
WHERE lower(email) IN (
    'sharmasd2@gmail.com',
    'tenseitechpvtltd@gmail.com',
    'admin@doctornect.com',
    'superadmin@doctornect.com',
    'support@doctornect.com'
)
ORDER BY email;

-- ============================================================================
-- CHECK 5: Verify Exposure State of Schema 'private'
-- ============================================================================
-- 5A. Check PostgREST exposed schemas configured on the authenticator role:
SELECT rolname, rolconfig 
FROM pg_roles 
WHERE rolname = 'authenticator';

-- 5B. Verify that 'anon' has NO usage on schema 'private'
SELECT 
    nspname AS schema_name,
    has_schema_privilege('anon', nspname, 'USAGE') AS anon_has_usage,
    has_schema_privilege('authenticated', nspname, 'USAGE') AS authenticated_has_usage
FROM pg_namespace
WHERE nspname IN ('public', 'private');
-- Reminder: Also inspect Supabase Dashboard -> Project Settings -> API -> "Exposed schemas"
-- Ensure 'private' is NOT listed in the exposed schemas list.

-- ============================================================================
-- CHECK 6: Duplicate Mobile Number Detection (public.users)
-- ============================================================================
-- Must return 0 rows before applying partial unique index idx_users_active_mobile:
SELECT 
    mobile,
    COUNT(*) AS duplicate_count,
    array_agg(id) AS user_ids,
    array_agg(role) AS roles,
    array_agg(profile_id) AS profile_ids,
    array_agg(created_at ORDER BY created_at ASC) AS creation_dates
FROM public.users
WHERE mobile IS NOT NULL 
  AND deactivated = FALSE
GROUP BY mobile
HAVING COUNT(*) > 1;

-- ============================================================================
-- CHECK 7: Column Verification for Locked Tables
-- (Confirms exact column names passed to private.lock_columns triggers)
-- ============================================================================
SELECT 
    table_name,
    column_name,
    data_type,
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name IN ('doctors', 'medical_stores', 'labs', 'ambulances', 'patients', 'appointments')
  AND column_name IN ('deactivated', 'owner_uid', 'auth_uid', 'verified', 'patient_id', 'doctor_id')
ORDER BY table_name, column_name;

