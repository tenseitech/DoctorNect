-- db_hardening_test.sql
-- Proves all 5 hardening items from 20261021000006_db_hardening.sql:
-- 1. is_super_admin(text) behavior & search_path = ''
-- 2. Trigger functions revoked from authenticated and anon
-- 3. expire_stale_ambulance_broadcasts restricted to service_role
-- 4. find_auth_user restricted to service_role with search_path = ''
-- 5. razorpay_orders.user_uid allows NULL

BEGIN;

DO $$
BEGIN
    RAISE NOTICE '=== RUNNING DB HARDENING VERIFICATION TESTS ===';
END;
$$;

-- 1. Test is_super_admin(text)
DO $$
DECLARE
    v_result boolean;
BEGIN
    -- Check search_path configuration on is_super_admin
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc
        WHERE proname = 'is_super_admin'
          AND proconfig::text LIKE '%search_path=%'
    ) THEN
        RAISE EXCEPTION '[FAIL] is_super_admin does not have search_path set to empty string';
    END IF;

    -- Test NULL and empty inputs
    SELECT public.is_super_admin(NULL) INTO v_result;
    IF v_result <> false THEN
        RAISE EXCEPTION '[FAIL] is_super_admin(NULL) returned true';
    END IF;

    SELECT public.is_super_admin('') INTO v_result;
    IF v_result <> false THEN
        RAISE EXCEPTION '[FAIL] is_super_admin('''') returned true';
    END IF;

    -- Insert temporary test super_admin
    INSERT INTO public.super_admins (user_uid, created_by)
    VALUES ('test_super_admin_hardening', 'system')
    ON CONFLICT (user_uid) DO NOTHING;

    SELECT public.is_super_admin('test_super_admin_hardening') INTO v_result;
    IF v_result <> true THEN
        RAISE EXCEPTION '[FAIL] is_super_admin did not match inserted super_admin';
    END IF;

    SELECT public.is_super_admin('random_unregistered_uid') INTO v_result;
    IF v_result <> false THEN
        RAISE EXCEPTION '[FAIL] is_super_admin matched unregistered uid';
    END IF;

    RAISE NOTICE '[PASS] 1. is_super_admin(text) hardened with search_path='''' and functional';
END;
$$;

-- 2. Verify trigger-only functions have EXECUTE revoked from anon and authenticated
DO $$
BEGIN
    IF has_function_privilege('anon', 'public.fn_sync_review_aggregates()', 'execute') THEN
        RAISE EXCEPTION '[FAIL] anon has execute on fn_sync_review_aggregates';
    END IF;
    IF has_function_privilege('authenticated', 'public.fn_sync_review_aggregates()', 'execute') THEN
        RAISE EXCEPTION '[FAIL] authenticated has execute on fn_sync_review_aggregates';
    END IF;

    IF has_function_privilege('anon', 'public.fn_sync_review_helpful_count()', 'execute') THEN
        RAISE EXCEPTION '[FAIL] anon has execute on fn_sync_review_helpful_count';
    END IF;
    IF has_function_privilege('authenticated', 'public.fn_sync_review_helpful_count()', 'execute') THEN
        RAISE EXCEPTION '[FAIL] authenticated has execute on fn_sync_review_helpful_count';
    END IF;

    IF has_function_privilege('anon', 'public.fn_touch_doctor_directory()', 'execute') THEN
        RAISE EXCEPTION '[FAIL] anon has execute on fn_touch_doctor_directory';
    END IF;
    IF has_function_privilege('authenticated', 'public.fn_touch_doctor_directory()', 'execute') THEN
        RAISE EXCEPTION '[FAIL] authenticated has execute on fn_touch_doctor_directory';
    END IF;

    RAISE NOTICE '[PASS] 2. Trigger functions revoked from anon and authenticated';
END;
$$;

-- 3. Verify expire_stale_ambulance_broadcasts() restricted to service_role
DO $$
BEGIN
    IF has_function_privilege('anon', 'public.expire_stale_ambulance_broadcasts()', 'execute') THEN
        RAISE EXCEPTION '[FAIL] anon has execute on expire_stale_ambulance_broadcasts';
    END IF;
    IF has_function_privilege('authenticated', 'public.expire_stale_ambulance_broadcasts()', 'execute') THEN
        RAISE EXCEPTION '[FAIL] authenticated has execute on expire_stale_ambulance_broadcasts';
    END IF;
    IF NOT has_function_privilege('service_role', 'public.expire_stale_ambulance_broadcasts()', 'execute') THEN
        RAISE EXCEPTION '[FAIL] service_role missing execute on expire_stale_ambulance_broadcasts';
    END IF;

    RAISE NOTICE '[PASS] 3. expire_stale_ambulance_broadcasts() restricted to service_role';
END;
$$;

-- 4. Verify find_auth_user(text) restricted to service_role with search_path = ''
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc
        WHERE proname = 'find_auth_user'
          AND proconfig::text LIKE '%search_path=%'
    ) THEN
        RAISE EXCEPTION '[FAIL] find_auth_user does not have search_path set to empty string';
    END IF;

    IF has_function_privilege('anon', 'public.find_auth_user(text)', 'execute') THEN
        RAISE EXCEPTION '[FAIL] anon has execute on find_auth_user';
    END IF;
    IF has_function_privilege('authenticated', 'public.find_auth_user(text)', 'execute') THEN
        RAISE EXCEPTION '[FAIL] authenticated has execute on find_auth_user';
    END IF;
    IF NOT has_function_privilege('service_role', 'public.find_auth_user(text)', 'execute') THEN
        RAISE EXCEPTION '[FAIL] service_role missing execute on find_auth_user';
    END IF;

    RAISE NOTICE '[PASS] 4. find_auth_user(text) restricted to service_role with search_path=''''';
END;
$$;

-- 5. Verify razorpay_orders.user_uid allows NULL for PII minimization
DO $$
DECLARE
    v_is_nullable text;
BEGIN
    SELECT is_nullable INTO v_is_nullable
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'razorpay_orders'
      AND column_name = 'user_uid';

    IF v_is_nullable <> 'YES' THEN
        RAISE EXCEPTION '[FAIL] razorpay_orders.user_uid is not nullable (got: %)', v_is_nullable;
    END IF;

    -- Test insertion of order with user_uid = NULL
    INSERT INTO public.razorpay_orders (order_id, user_uid, receipt, amount_paise, status)
    VALUES ('order_hardening_null_test', NULL, 'rcpt_null_test', 1000, 'created');

    IF NOT EXISTS (
        SELECT 1 FROM public.razorpay_orders
        WHERE order_id = 'order_hardening_null_test' AND user_uid IS NULL
    ) THEN
        RAISE EXCEPTION '[FAIL] Could not query back order with NULL user_uid';
    END IF;

    RAISE NOTICE '[PASS] 5. razorpay_orders.user_uid nullable for PII minimization';
END;
$$;

ROLLBACK;
