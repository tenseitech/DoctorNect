-- File: backend/supabase/tests/phase_e2_rls_test.sql
-- Description: Comprehensive RLS test suite for Phase E2 (Support Tickets, Messages, In-App Notifications, Mail Queue, Security Events)
-- Execution: psql -f phase_e2_rls_test.sql

BEGIN;

CREATE TEMP TABLE test_results (
  test_id INT,
  description TEXT,
  expected TEXT,
  actual TEXT,
  status TEXT
);
GRANT ALL ON test_results TO authenticated, anon;

-- Seed prerequisite test users and super admin
INSERT INTO public.super_admins (user_uid)
VALUES ('fb_uid_super_admin_e2')
ON CONFLICT (user_uid) DO NOTHING;

DO $$
DECLARE
  v_pat1_uid TEXT := 'fb_uid_pat_e2_001';
  v_pat2_uid TEXT := 'fb_uid_pat_e2_002';
  v_admin_uid TEXT := 'fb_uid_super_admin_e2';
  v_ticket_id TEXT := 'TICK-E2-001';
  v_msg_id TEXT := 'MSG-E2-001';
  v_notif_id TEXT := 'NOTIF-E2-001';
  v_mail_id TEXT := 'MAIL-E2-001';
  v_event_id TEXT := 'SEC-E2-001';
  v_cnt INT;
  v_status TEXT;
BEGIN
  -- Insert dummy user rows
  INSERT INTO public.users (id, firebase_uid, role, profile_id, display_name, email, mobile, profile_completed, verified, status)
  VALUES 
    (v_pat1_uid, v_pat1_uid, 'patient', 'pat_e2_001', 'Patient E2 One', 'pat1.e2@test.com', '9800000021', true, true, 'approved'),
    (v_pat2_uid, v_pat2_uid, 'patient', 'pat_e2_002', 'Patient E2 Two', 'pat2.e2@test.com', '9800000022', true, true, 'approved'),
    (v_admin_uid, v_admin_uid, 'superAdmin', 'admin_e2_001', 'Super Admin E2', 'admin.e2@test.com', '9800000023', true, true, 'approved')
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.patients (patient_id, owner_uid, name, mobile, email, verified, profile_completed)
  VALUES 
    ('pat_e2_001', v_pat1_uid, 'Patient E2 One', '9800000021', 'pat1.e2@test.com', true, true),
    ('pat_e2_002', v_pat2_uid, 'Patient E2 Two', '9800000022', 'pat2.e2@test.com', true, true)
  ON CONFLICT (patient_id) DO NOTHING;

  -- 1. Patient 1 inserts own support ticket
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_pat1_uid, 'role', 'authenticated', 'user_role', 'patient')::text, true);
  SET ROLE authenticated;

  INSERT INTO public.support_tickets (ticket_id, patient_id, user_id, issue_type, message, status)
  VALUES (v_ticket_id, 'pat_e2_001', v_pat1_uid, 'Appointment', 'Need help rescheduling', 'open');

  SELECT count(*) INTO v_cnt FROM public.support_tickets WHERE ticket_id = v_ticket_id;
  INSERT INTO test_results VALUES (1, 'Patient 1 reads own support ticket', '1', v_cnt::text, CASE WHEN v_cnt = 1 THEN 'PASS' ELSE 'FAIL' END);

  -- 2. Patient 2 cannot read Patient 1 support ticket
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_pat2_uid, 'role', 'authenticated', 'user_role', 'patient')::text, true);
  SELECT count(*) INTO v_cnt FROM public.support_tickets WHERE ticket_id = v_ticket_id;
  INSERT INTO test_results VALUES (2, 'Patient 2 cannot read Patient 1 support ticket (0 rows)', '0', v_cnt::text, CASE WHEN v_cnt = 0 THEN 'PASS' ELSE 'FAIL' END);

  -- 3. Super Admin can read Patient 1 support ticket
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_uid, 'role', 'authenticated', 'user_role', 'superAdmin')::text, true);
  SELECT count(*) INTO v_cnt FROM public.support_tickets WHERE ticket_id = v_ticket_id;
  INSERT INTO test_results VALUES (3, 'Super admin CAN read support ticket (1 row)', '1', v_cnt::text, CASE WHEN v_cnt = 1 THEN 'PASS' ELSE 'FAIL' END);

  -- 4. Patient 1 inserts and reads message on own ticket
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_pat1_uid, 'role', 'authenticated', 'user_role', 'patient')::text, true);
  INSERT INTO public.support_ticket_messages (message_id, ticket_id, sender_id, sender_name, sender_role, text)
  VALUES (v_msg_id, v_ticket_id, v_pat1_uid, 'Patient One', 'patient', 'Please reply soon');

  SELECT count(*) INTO v_cnt FROM public.support_ticket_messages WHERE message_id = v_msg_id;
  INSERT INTO test_results VALUES (4, 'Patient 1 reads own ticket message', '1', v_cnt::text, CASE WHEN v_cnt = 1 THEN 'PASS' ELSE 'FAIL' END);

  -- 5. Patient 2 cannot read message on Patient 1 ticket
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_pat2_uid, 'role', 'authenticated', 'user_role', 'patient')::text, true);
  SELECT count(*) INTO v_cnt FROM public.support_ticket_messages WHERE message_id = v_msg_id;
  INSERT INTO test_results VALUES (5, 'Patient 2 cannot read Patient 1 ticket message (0 rows)', '0', v_cnt::text, CASE WHEN v_cnt = 0 THEN 'PASS' ELSE 'FAIL' END);

  -- Reset role to insert notifications and mail queue via service role
  RESET ROLE;

  INSERT INTO public.in_app_notifications (notification_id, recipient_uid, title, body, is_read, type)
  VALUES (v_notif_id, v_pat1_uid, 'Prescription Ready', 'Your prescription is ready', false, 'system')
  ON CONFLICT DO NOTHING;

  INSERT INTO public.mail_queue (mail_id, to_address, subject, text_body, status, attempts)
  VALUES (v_mail_id, 'pat1@test.com', 'Welcome', 'Welcome to DoctorNect', 'pending', 0)
  ON CONFLICT DO NOTHING;

  INSERT INTO public.security_events (event_id, severity, category, action, client_ip_hash, app_check_present, expires_at)
  VALUES (v_event_id, 'WARNING', 'auth', 'auth.failed_attempt', 'hash123', true, now() + interval '30 days')
  ON CONFLICT DO NOTHING;

  -- 6. Patient 1 reads own in_app_notifications
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_pat1_uid, 'role', 'authenticated', 'user_role', 'patient')::text, true);
  SET ROLE authenticated;

  SELECT count(*) INTO v_cnt FROM public.in_app_notifications WHERE notification_id = v_notif_id;
  INSERT INTO test_results VALUES (6, 'Patient 1 reads own in_app_notification', '1', v_cnt::text, CASE WHEN v_cnt = 1 THEN 'PASS' ELSE 'FAIL' END);

  -- 7. Patient 2 cannot read Patient 1 in_app_notifications
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_pat2_uid, 'role', 'authenticated', 'user_role', 'patient')::text, true);
  SELECT count(*) INTO v_cnt FROM public.in_app_notifications WHERE notification_id = v_notif_id;
  INSERT INTO test_results VALUES (7, 'Patient 2 cannot read Patient 1 in_app_notification (0 rows)', '0', v_cnt::text, CASE WHEN v_cnt = 0 THEN 'PASS' ELSE 'FAIL' END);

  -- 8. Normal patient cannot read mail_queue (0 rows)
  SELECT count(*) INTO v_cnt FROM public.mail_queue WHERE mail_id = v_mail_id;
  INSERT INTO test_results VALUES (8, 'Normal patient cannot read mail_queue (0 rows)', '0', v_cnt::text, CASE WHEN v_cnt = 0 THEN 'PASS' ELSE 'FAIL' END);

  -- 9. Super admin CAN read mail_queue
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_uid, 'role', 'authenticated', 'user_role', 'superAdmin')::text, true);
  SELECT count(*) INTO v_cnt FROM public.mail_queue WHERE mail_id = v_mail_id;
  INSERT INTO test_results VALUES (9, 'Super admin CAN read mail_queue (>=1 rows)', '1', v_cnt::text, CASE WHEN v_cnt >= 1 THEN 'PASS' ELSE 'FAIL' END);

  -- 10. Normal patient cannot read security_events (0 rows)
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_pat1_uid, 'role', 'authenticated', 'user_role', 'patient')::text, true);
  SELECT count(*) INTO v_cnt FROM public.security_events WHERE event_id = v_event_id;
  INSERT INTO test_results VALUES (10, 'Normal patient cannot read security_events (0 rows)', '0', v_cnt::text, CASE WHEN v_cnt = 0 THEN 'PASS' ELSE 'FAIL' END);

  -- 11. Super admin CAN read security_events
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_uid, 'role', 'authenticated', 'user_role', 'superAdmin')::text, true);
  SELECT count(*) INTO v_cnt FROM public.security_events WHERE event_id = v_event_id;
  INSERT INTO test_results VALUES (11, 'Super admin CAN read security_events (>=1 rows)', '1', v_cnt::text, CASE WHEN v_cnt >= 1 THEN 'PASS' ELSE 'FAIL' END);
END $$;

RESET ROLE;

SELECT test_id, description, expected, actual, status FROM test_results ORDER BY test_id ASC;

SELECT count(*) as total_tests, 
       count(*) FILTER (WHERE status = 'PASS') as passed,
       count(*) FILTER (WHERE status = 'FAIL') as failed
FROM test_results;

ROLLBACK;
