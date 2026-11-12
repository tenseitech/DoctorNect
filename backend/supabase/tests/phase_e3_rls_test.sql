-- File: backend/supabase/tests/phase_e3_rls_test.sql
-- Description: Comprehensive RLS test suite for Phase E3 (Promoted Ads & Razorpay Orders, Payments, Webhook Events)
-- Execution: psql -f phase_e3_rls_test.sql

BEGIN;

CREATE TEMP TABLE test_results (
  test_id INT,
  description TEXT,
  expected TEXT,
  actual TEXT,
  status TEXT
);
GRANT ALL ON test_results TO authenticated, anon;

-- Seed prerequisite test super admin and test users
INSERT INTO public.super_admins (user_uid)
VALUES ('fb_uid_super_admin_e3')
ON CONFLICT (user_uid) DO NOTHING;

DO $$
DECLARE
  v_user1_uid TEXT := 'fb_uid_adv_e3_001';
  v_user2_uid TEXT := 'fb_uid_adv_e3_002';
  v_admin_uid TEXT := 'fb_uid_super_admin_e3';
  v_ad1_id VARCHAR(64) := 'AD-E3-001';
  v_ad2_id VARCHAR(64) := 'AD-E3-002';
  v_order1_id VARCHAR(128) := 'order_E3_test_001';
  v_payment1_id VARCHAR(128) := 'pay_E3_test_001';
  v_event1_id VARCHAR(128) := 'evt_E3_test_001';
  v_cnt INT;
  v_err TEXT;
BEGIN
  -- Insert dummy user rows
  INSERT INTO public.users (id, firebase_uid, role, profile_id, display_name, email, mobile, profile_completed, verified, status)
  VALUES 
    (v_user1_uid, v_user1_uid, 'doctor', 'doc_e3_001', 'Doctor E3 One', 'doc1.e3@test.com', '9800000031', true, true, 'approved'),
    (v_user2_uid, v_user2_uid, 'doctor', 'doc_e3_002', 'Doctor E3 Two', 'doc2.e3@test.com', '9800000032', true, true, 'approved'),
    (v_admin_uid, v_admin_uid, 'superAdmin', 'admin_e3_001', 'Super Admin E3', 'admin.e3@test.com', '9800000033', true, true, 'approved')
  ON CONFLICT (id) DO NOTHING;

  -- 1. User 1 creates a draft ad and an active ad
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user1_uid, 'role', 'authenticated', 'user_role', 'doctor')::text, true);
  SET ROLE authenticated;

  INSERT INTO public.promoted_ads (ad_id, provider_type, provider_id, title, description, image_url, cta_label, duration_hours, amount_paid, status)
  VALUES 
    (v_ad1_id, 'doctor', v_user1_uid, 'Specialist Clinic', 'Best care', 'https://s3.example.com/ad1.jpg', 'Book Now', 24, 300, 'draft'),
    (v_ad2_id, 'doctor', v_user1_uid, 'Health Checkup', 'Comprehensive checkup', 'https://s3.example.com/ad2.jpg', 'Learn More', 24, 300, 'active');

  SELECT count(*) INTO v_cnt FROM public.promoted_ads WHERE ad_id = v_ad1_id;
  INSERT INTO test_results VALUES (1, 'User 1 can read own draft promoted ad', '1', v_cnt::text, CASE WHEN v_cnt = 1 THEN 'PASS' ELSE 'FAIL' END);

  -- 2. User 2 can read active ad
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user2_uid, 'role', 'authenticated', 'user_role', 'doctor')::text, true);
  SELECT count(*) INTO v_cnt FROM public.promoted_ads WHERE ad_id = v_ad2_id;
  INSERT INTO test_results VALUES (2, 'User 2 can read active promoted ad', '1', v_cnt::text, CASE WHEN v_cnt = 1 THEN 'PASS' ELSE 'FAIL' END);

  -- 3. User 2 cannot read User 1 draft ad
  SELECT count(*) INTO v_cnt FROM public.promoted_ads WHERE ad_id = v_ad1_id;
  INSERT INTO test_results VALUES (3, 'User 2 cannot read User 1 draft promoted ad', '0', v_cnt::text, CASE WHEN v_cnt = 0 THEN 'PASS' ELSE 'FAIL' END);

  -- 4. User 1 creates Razorpay order for own ad
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user1_uid, 'role', 'authenticated', 'user_role', 'doctor')::text, true);
  INSERT INTO public.razorpay_orders (order_id, user_uid, ad_id, amount_paise, receipt, status)
  VALUES (v_order1_id, v_user1_uid, v_ad1_id, 30000, 'rcpt_001', 'created');

  SELECT count(*) INTO v_cnt FROM public.razorpay_orders WHERE order_id = v_order1_id;
  INSERT INTO test_results VALUES (4, 'User 1 can read own razorpay order', '1', v_cnt::text, CASE WHEN v_cnt = 1 THEN 'PASS' ELSE 'FAIL' END);

  -- 5. User 1 cannot insert razorpay order for User 2 (user_uid mismatch)
  BEGIN
    INSERT INTO public.razorpay_orders (order_id, user_uid, ad_id, amount_paise, receipt, status)
    VALUES ('order_spoofed', v_user2_uid, v_ad1_id, 30000, 'rcpt_spoof', 'created');
    v_err := 'INSERT_SUCCEEDED';
  EXCEPTION WHEN OTHERS THEN
    v_err := 'BLOCKED';
  END;
  INSERT INTO test_results VALUES (5, 'User 1 cannot insert razorpay order for User 2', 'BLOCKED', v_err, CASE WHEN v_err = 'BLOCKED' THEN 'PASS' ELSE 'FAIL' END);

  -- 6. User 2 cannot read User 1 razorpay order
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user2_uid, 'role', 'authenticated', 'user_role', 'doctor')::text, true);
  SELECT count(*) INTO v_cnt FROM public.razorpay_orders WHERE order_id = v_order1_id;
  INSERT INTO test_results VALUES (6, 'User 2 cannot read User 1 razorpay order', '0', v_cnt::text, CASE WHEN v_cnt = 0 THEN 'PASS' ELSE 'FAIL' END);

  -- 7. User 1 cannot update razorpay order directly
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user1_uid, 'role', 'authenticated', 'user_role', 'doctor')::text, true);
  UPDATE public.razorpay_orders SET status = 'paid' WHERE order_id = v_order1_id;
  SELECT status INTO v_err FROM public.razorpay_orders WHERE order_id = v_order1_id;
  INSERT INTO test_results VALUES (7, 'User 1 cannot update razorpay order directly', 'created', v_err, CASE WHEN v_err = 'created' THEN 'PASS' ELSE 'FAIL' END);

  -- 8. Client cannot directly insert into razorpay_payments
  BEGIN
    INSERT INTO public.razorpay_payments (payment_id, order_id, signature, amount_paise, status)
    VALUES (v_payment1_id, v_order1_id, 'fake_sig', 30000, 'captured');
    v_err := 'INSERT_SUCCEEDED';
  EXCEPTION WHEN OTHERS THEN
    v_err := 'BLOCKED';
  END;
  INSERT INTO test_results VALUES (8, 'Client directly inserting razorpay_payment is blocked', 'BLOCKED', v_err, CASE WHEN v_err = 'BLOCKED' THEN 'PASS' ELSE 'FAIL' END);

  -- Switch to postgres role to simulate backend service role recording payment and webhook event
  RESET ROLE;
  INSERT INTO public.razorpay_payments (payment_id, order_id, signature, amount_paise, status, method)
  VALUES (v_payment1_id, v_order1_id, 'valid_sig_hash', 30000, 'captured', 'upi');

  INSERT INTO public.razorpay_webhook_events (event_id, event_type, payload)
  VALUES (v_event1_id, 'payment.captured', '{"payment_id": "pay_E3_test_001"}'::jsonb);

  -- 9. User 1 can select payment linked to their own order
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user1_uid, 'role', 'authenticated', 'user_role', 'doctor')::text, true);
  SET ROLE authenticated;

  SELECT count(*) INTO v_cnt FROM public.razorpay_payments WHERE payment_id = v_payment1_id;
  INSERT INTO test_results VALUES (9, 'User 1 can read razorpay payment for own order', '1', v_cnt::text, CASE WHEN v_cnt = 1 THEN 'PASS' ELSE 'FAIL' END);

  -- 10. User 2 cannot select payment linked to User 1 order
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user2_uid, 'role', 'authenticated', 'user_role', 'doctor')::text, true);
  SELECT count(*) INTO v_cnt FROM public.razorpay_payments WHERE payment_id = v_payment1_id;
  INSERT INTO test_results VALUES (10, 'User 2 cannot read razorpay payment for User 1 order', '0', v_cnt::text, CASE WHEN v_cnt = 0 THEN 'PASS' ELSE 'FAIL' END);

  -- 11. Client cannot directly insert into razorpay_webhook_events
  BEGIN
    INSERT INTO public.razorpay_webhook_events (event_id, event_type, payload)
    VALUES ('evt_spoofed', 'order.paid', '{}'::jsonb);
    v_err := 'INSERT_SUCCEEDED';
  EXCEPTION WHEN OTHERS THEN
    v_err := 'BLOCKED';
  END;
  INSERT INTO test_results VALUES (11, 'Client directly inserting razorpay_webhook_event is blocked', 'BLOCKED', v_err, CASE WHEN v_err = 'BLOCKED' THEN 'PASS' ELSE 'FAIL' END);

  -- 12. Non-admin cannot read razorpay_webhook_events
  SELECT count(*) INTO v_cnt FROM public.razorpay_webhook_events WHERE event_id = v_event1_id;
  INSERT INTO test_results VALUES (12, 'Non-admin cannot read razorpay_webhook_events', '0', v_cnt::text, CASE WHEN v_cnt = 0 THEN 'PASS' ELSE 'FAIL' END);

  -- 13. Super admin can read razorpay_webhook_events and all orders/payments
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_uid, 'role', 'authenticated', 'user_role', 'superAdmin')::text, true);
  SELECT count(*) INTO v_cnt FROM public.razorpay_webhook_events WHERE event_id = v_event1_id;
  INSERT INTO test_results VALUES (13, 'Super admin can read razorpay_webhook_events', '1', v_cnt::text, CASE WHEN v_cnt = 1 THEN 'PASS' ELSE 'FAIL' END);

  -- 14. Super admin can read any order
  SELECT count(*) INTO v_cnt FROM public.razorpay_orders WHERE order_id = v_order1_id;
  INSERT INTO test_results VALUES (14, 'Super admin can read any razorpay order', '1', v_cnt::text, CASE WHEN v_cnt = 1 THEN 'PASS' ELSE 'FAIL' END);

  -- 15. Super admin can read any non-active ad
  SELECT count(*) INTO v_cnt FROM public.promoted_ads WHERE ad_id = v_ad1_id;
  INSERT INTO test_results VALUES (15, 'Super admin can read draft promoted ad', '1', v_cnt::text, CASE WHEN v_cnt = 1 THEN 'PASS' ELSE 'FAIL' END);

  RESET ROLE;
END $$;

SELECT test_id, description, expected, actual, status FROM test_results ORDER BY test_id;

-- Ensure all passed
DO $$
DECLARE
  v_failed INT;
BEGIN
  SELECT count(*) INTO v_failed FROM test_results WHERE status <> 'PASS';
  IF v_failed > 0 THEN
    RAISE EXCEPTION 'Phase E3 RLS test suite had % failures!', v_failed;
  END IF;
END $$;

ROLLBACK;
