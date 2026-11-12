-- Phase E.1 RLS Test Suite: super_admins and is_super_admin
-- Verified against local Docker DB on port 54322

BEGIN;

CREATE TEMP TABLE IF NOT EXISTS test_results (
    test_id INT,
    description TEXT,
    expected TEXT,
    actual TEXT,
    status TEXT
);
GRANT ALL ON TABLE test_results TO authenticated, anon, public;

-- Seed test super admin
INSERT INTO public.super_admins (user_uid, created_by)
VALUES ('fb_uid_admin_001', 'system_init')
ON CONFLICT (user_uid) DO NOTHING;

-- Test 1: is_super_admin returns true for enrolled super admin
DO $$
DECLARE
    is_admin BOOLEAN;
BEGIN
    SELECT public.is_super_admin('fb_uid_admin_001') INTO is_admin;
    INSERT INTO test_results VALUES (1, 'is_super_admin returns true for enrolled admin', 'true', is_admin::text, CASE WHEN is_admin THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

-- Test 2: is_super_admin returns false for unenrolled user
DO $$
DECLARE
    is_admin BOOLEAN;
BEGIN
    SELECT public.is_super_admin('fb_uid_patient_999') INTO is_admin;
    INSERT INTO test_results VALUES (2, 'is_super_admin returns false for normal patient', 'false', is_admin::text, CASE WHEN NOT is_admin THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

-- Test 3: is_super_admin returns false for NULL and empty string
DO $$
DECLARE
    is_null_admin BOOLEAN;
    is_empty_admin BOOLEAN;
BEGIN
    SELECT public.is_super_admin(NULL) INTO is_null_admin;
    SELECT public.is_super_admin('') INTO is_empty_admin;
    INSERT INTO test_results VALUES (3, 'is_super_admin null and empty safe', 'false:false', (is_null_admin::text || ':' || is_empty_admin::text), CASE WHEN NOT is_null_admin AND NOT is_empty_admin THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

-- Test 4: Unauthenticated/normal patient client cannot read super_admins table
DO $$
DECLARE
    row_count INT;
BEGIN
    -- Simulate authenticated patient
    PERFORM set_config('request.jwt.claims', '{"sub": "fb_uid_patient_001", "role": "authenticated"}', true);
    SET LOCAL ROLE authenticated;

    SELECT count(*) INTO row_count FROM public.super_admins;
    INSERT INTO test_results VALUES (4, 'Normal patient cannot read super_admins table (0 rows)', '0', row_count::text, CASE WHEN row_count = 0 THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

-- Test 5: Super admin client CAN read super_admins table
DO $$
DECLARE
    row_count INT;
BEGIN
    -- Simulate authenticated super admin
    PERFORM set_config('request.jwt.claims', '{"sub": "fb_uid_admin_001", "role": "authenticated"}', true);
    SET LOCAL ROLE authenticated;

    SELECT count(*) INTO row_count FROM public.super_admins;
    INSERT INTO test_results VALUES (5, 'Super admin CAN read super_admins table (>=1 rows)', '1', CASE WHEN row_count >= 1 THEN '1' ELSE '0' END, CASE WHEN row_count >= 1 THEN 'PASS' ELSE 'FAIL' END);
END;
$$;

-- Output test results
SELECT * FROM test_results ORDER BY test_id ASC;

SELECT 
    count(*) AS total_tests,
    count(*) FILTER (WHERE status = 'PASS') AS passed,
    count(*) FILTER (WHERE status = 'FAIL') AS failed
FROM test_results;

ROLLBACK;
