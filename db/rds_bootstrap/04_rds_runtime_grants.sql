-- =============================================================================
-- DoctorNect RDS Bootstrap: 04_rds_runtime_grants.sql
-- Idempotent least-privilege grants for PostgREST roles on AWS RDS.
-- Run AFTER db/migrations/*.sql on cutover. Does not use GRANT ALL.
-- =============================================================================

GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;

GRANT USAGE ON SCHEMA private TO service_role;

-- --- service_role: gateway serviceRoleOnlyTables (backend / ops) ---
DO $$ BEGIN
  EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO service_role', 'abuse_rate_limits');
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'skip missing public.%', 'abuse_rate_limits';
END $$;
DO $$ BEGIN
  EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO service_role', 'admin_audit_logs');
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'skip missing public.%', 'admin_audit_logs';
END $$;
DO $$ BEGIN
  EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO service_role', 'ambulance_invites');
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'skip missing public.%', 'ambulance_invites';
END $$;
DO $$ BEGIN
  EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO service_role', 'ambulance_locations');
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'skip missing public.%', 'ambulance_locations';
END $$;
DO $$ BEGIN
  EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO service_role', 'ambulance_private_settings');
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'skip missing public.%', 'ambulance_private_settings';
END $$;
DO $$ BEGIN
  EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO service_role', 'ambulance_trip_contacts');
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'skip missing public.%', 'ambulance_trip_contacts';
END $$;
DO $$ BEGIN
  EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO service_role', 'doctor_education');
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'skip missing public.%', 'doctor_education';
END $$;
DO $$ BEGIN
  EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO service_role', 'doctor_facilities');
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'skip missing public.%', 'doctor_facilities';
END $$;
DO $$ BEGIN
  EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO service_role', 'doctor_invites');
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'skip missing public.%', 'doctor_invites';
END $$;
DO $$ BEGIN
  EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO service_role', 'doctor_private');
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'skip missing public.%', 'doctor_private';
END $$;
DO $$ BEGIN
  EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO service_role', 'mail_queue');
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'skip missing public.%', 'mail_queue';
END $$;
DO $$ BEGIN
  EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO service_role', 'notification_outbox');
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'skip missing public.%', 'notification_outbox';
END $$;
DO $$ BEGIN
  EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO service_role', 'otp_challenges');
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'skip missing public.%', 'otp_challenges';
END $$;
DO $$ BEGIN
  EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO service_role', 'patient_care_team');
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'skip missing public.%', 'patient_care_team';
END $$;
DO $$ BEGIN
  EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO service_role', 'pharmacy_doctor_invites');
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'skip missing public.%', 'pharmacy_doctor_invites';
END $$;
DO $$ BEGIN
  EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO service_role', 'provisioning_errors');
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'skip missing public.%', 'provisioning_errors';
END $$;
DO $$ BEGIN
  EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO service_role', 'razorpay_orders');
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'skip missing public.%', 'razorpay_orders';
END $$;
DO $$ BEGIN
  EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO service_role', 'razorpay_payments');
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'skip missing public.%', 'razorpay_payments';
END $$;
DO $$ BEGIN
  EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO service_role', 'razorpay_webhook_events');
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'skip missing public.%', 'razorpay_webhook_events';
END $$;
DO $$ BEGIN
  EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO service_role', 'security_events');
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'skip missing public.%', 'security_events';
END $$;
DO $$ BEGIN
  EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO service_role', 'storage_audit_logs');
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'skip missing public.%', 'storage_audit_logs';
END $$;
DO $$ BEGIN
  EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO service_role', 'super_admins');
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'skip missing public.%', 'super_admins';
END $$;
DO $$ BEGIN
  EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO service_role', 'sync_dead_letter_queue');
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'skip missing public.%', 'sync_dead_letter_queue';
END $$;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE private.admin_users TO service_role;

-- --- service_role: Cloud Functions maintenance (delete account, sync, webhooks) ---
DO $$ BEGIN
  EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO service_role', 'ambulance_broadcasts');
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'skip missing public.%', 'ambulance_broadcasts';
END $$;
DO $$ BEGIN
  EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO service_role', 'ambulance_requests');
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'skip missing public.%', 'ambulance_requests';
END $$;
DO $$ BEGIN
  EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO service_role', 'ambulances');
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'skip missing public.%', 'ambulances';
END $$;
DO $$ BEGIN
  EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO service_role', 'appointments');
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'skip missing public.%', 'appointments';
END $$;
DO $$ BEGIN
  EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO service_role', 'doctors');
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'skip missing public.%', 'doctors';
END $$;
DO $$ BEGIN
  EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO service_role', 'family_members');
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'skip missing public.%', 'family_members';
END $$;
DO $$ BEGIN
  EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO service_role', 'health_records');
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'skip missing public.%', 'health_records';
END $$;
DO $$ BEGIN
  EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO service_role', 'in_app_notifications');
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'skip missing public.%', 'in_app_notifications';
END $$;
DO $$ BEGIN
  EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO service_role', 'lab_bookings');
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'skip missing public.%', 'lab_bookings';
END $$;
DO $$ BEGIN
  EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO service_role', 'lab_orders');
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'skip missing public.%', 'lab_orders';
END $$;
DO $$ BEGIN
  EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO service_role', 'labs');
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'skip missing public.%', 'labs';
END $$;
DO $$ BEGIN
  EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO service_role', 'medical_stores');
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'skip missing public.%', 'medical_stores';
END $$;
DO $$ BEGIN
  EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO service_role', 'patient_doctor_links');
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'skip missing public.%', 'patient_doctor_links';
END $$;
DO $$ BEGIN
  EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO service_role', 'patients');
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'skip missing public.%', 'patients';
END $$;
DO $$ BEGIN
  EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO service_role', 'pharmacy_deliveries');
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'skip missing public.%', 'pharmacy_deliveries';
END $$;
DO $$ BEGIN
  EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO service_role', 'prescriptions');
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'skip missing public.%', 'prescriptions';
END $$;
DO $$ BEGIN
  EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO service_role', 'promoted_ads');
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'skip missing public.%', 'promoted_ads';
END $$;
DO $$ BEGIN
  EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO service_role', 'referrals');
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'skip missing public.%', 'referrals';
END $$;
DO $$ BEGIN
  EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO service_role', 'reviews');
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'skip missing public.%', 'reviews';
END $$;
DO $$ BEGIN
  EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO service_role', 'support_ticket_messages');
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'skip missing public.%', 'support_ticket_messages';
END $$;
DO $$ BEGIN
  EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO service_role', 'support_tickets');
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'skip missing public.%', 'support_tickets';
END $$;
DO $$ BEGIN
  EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO service_role', 'user_devices');
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'skip missing public.%', 'user_devices';
END $$;
DO $$ BEGIN
  EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO service_role', 'users');
EXCEPTION WHEN undefined_table THEN
  RAISE NOTICE 'skip missing public.%', 'users';
END $$;

GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO service_role;

-- --- service_role RPCs (cron/maintenance; client RPCs stay authenticated-only) ---
GRANT EXECUTE ON FUNCTION public.expire_stale_ambulance_broadcasts() TO service_role;
-- delete_my_account is enforced at API Gateway allowlist (no public SQL RPC in repo migrations).

-- --- anon hardening (re-assert; matches 20261103000008) ---
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon;
GRANT USAGE ON SCHEMA public TO anon;
GRANT SELECT ON public.doctor_directory TO anon;
GRANT SELECT ON public.lab_catalog_tests TO anon;
GRANT SELECT ON public.system_config TO anon;
GRANT SELECT ON public.review_public TO anon;
REVOKE ALL ON ALL ROUTINES IN SCHEMA public FROM anon;

-- --- PostgREST authenticator ---
GRANT anon, authenticated, service_role TO authenticator;

