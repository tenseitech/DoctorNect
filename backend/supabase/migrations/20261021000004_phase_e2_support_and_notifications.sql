-- 20261021000004_phase_e2_support_and_notifications.sql
-- Phase E2: Enhance support tickets, in-app notifications, mail queue, and security events.

BEGIN;

-- 1. ENHANCE SUPPORT TICKETS TABLE
ALTER TABLE public.support_tickets 
  ADD COLUMN IF NOT EXISTS user_id TEXT REFERENCES public.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS firebase_uid TEXT,
  ADD COLUMN IF NOT EXISTS store_id VARCHAR(64) REFERENCES public.medical_stores(store_id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS lab_id VARCHAR(64) REFERENCES public.labs(lab_id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS ambulance_id VARCHAR(64) REFERENCES public.ambulances(ambulance_id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS role VARCHAR(32);

-- Update RLS policies for support_tickets
DROP POLICY IF EXISTS "support_tickets_insert" ON public.support_tickets;
DROP POLICY IF EXISTS "support_tickets_select" ON public.support_tickets;
DROP POLICY IF EXISTS "support_tickets_write" ON public.support_tickets;
DROP POLICY IF EXISTS "support_tickets_update" ON public.support_tickets;

CREATE POLICY "support_tickets_insert" ON public.support_tickets
  FOR INSERT TO authenticated
  WITH CHECK (
    (patient_id = private.current_profile_id()) OR 
    (doctor_id = private.current_profile_id()) OR 
    (store_id = private.current_profile_id()) OR 
    (lab_id = private.current_profile_id()) OR 
    (ambulance_id = private.current_profile_id()) OR 
    (user_id = (auth.jwt() ->> 'sub')) OR 
    (firebase_uid = (auth.jwt() ->> 'sub')) OR 
    public.is_super_admin(auth.jwt() ->> 'sub')
  );

CREATE POLICY "support_tickets_select" ON public.support_tickets
  FOR SELECT TO authenticated
  USING (
    (patient_id = private.current_profile_id()) OR 
    (doctor_id = private.current_profile_id()) OR 
    (store_id = private.current_profile_id()) OR 
    (lab_id = private.current_profile_id()) OR 
    (ambulance_id = private.current_profile_id()) OR 
    (user_id = (auth.jwt() ->> 'sub')) OR 
    (firebase_uid = (auth.jwt() ->> 'sub')) OR 
    public.is_super_admin(auth.jwt() ->> 'sub')
  );

CREATE POLICY "support_tickets_update" ON public.support_tickets
  FOR UPDATE TO authenticated
  USING (
    (patient_id = private.current_profile_id()) OR 
    (doctor_id = private.current_profile_id()) OR 
    (store_id = private.current_profile_id()) OR 
    (lab_id = private.current_profile_id()) OR 
    (ambulance_id = private.current_profile_id()) OR 
    (user_id = (auth.jwt() ->> 'sub')) OR 
    (firebase_uid = (auth.jwt() ->> 'sub')) OR 
    public.is_super_admin(auth.jwt() ->> 'sub')
  )
  WITH CHECK (
    (patient_id = private.current_profile_id()) OR 
    (doctor_id = private.current_profile_id()) OR 
    (store_id = private.current_profile_id()) OR 
    (lab_id = private.current_profile_id()) OR 
    (ambulance_id = private.current_profile_id()) OR 
    (user_id = (auth.jwt() ->> 'sub')) OR 
    (firebase_uid = (auth.jwt() ->> 'sub')) OR 
    public.is_super_admin(auth.jwt() ->> 'sub')
  );

GRANT SELECT, INSERT, UPDATE ON public.support_tickets TO authenticated;

-- 2. ENHANCE SUPPORT TICKET MESSAGES TABLE
ALTER TABLE public.support_ticket_messages
  DROP CONSTRAINT IF EXISTS support_ticket_messages_sender_role_check;

ALTER TABLE public.support_ticket_messages
  ADD CONSTRAINT support_ticket_messages_sender_role_check
  CHECK (sender_role::text = ANY (ARRAY[
    'patient', 'doctor', 'medicalStore', 'pharmacy', 'lab', 'ambulance', 'support', 'superAdmin', 'super_admin'
  ]::text[]));

DROP POLICY IF EXISTS "support_messages_policy" ON public.support_ticket_messages;
DROP POLICY IF EXISTS "support_messages_insert" ON public.support_ticket_messages;
DROP POLICY IF EXISTS "support_messages_select" ON public.support_ticket_messages;

CREATE POLICY "support_messages_select" ON public.support_ticket_messages
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.support_tickets st
      WHERE st.ticket_id = support_ticket_messages.ticket_id
        AND (
          st.patient_id = private.current_profile_id() OR
          st.doctor_id = private.current_profile_id() OR
          st.store_id = private.current_profile_id() OR
          st.lab_id = private.current_profile_id() OR
          st.ambulance_id = private.current_profile_id() OR
          st.user_id = (auth.jwt() ->> 'sub') OR
          st.firebase_uid = (auth.jwt() ->> 'sub') OR
          public.is_super_admin(auth.jwt() ->> 'sub')
        )
    )
  );

CREATE POLICY "support_messages_insert" ON public.support_ticket_messages
  FOR INSERT TO authenticated
  WITH CHECK (
    (sender_id = (auth.jwt() ->> 'sub')) OR
    (sender_id = private.current_profile_id()) OR
    public.is_super_admin(auth.jwt() ->> 'sub')
  );

GRANT SELECT, INSERT ON public.support_ticket_messages TO authenticated;

-- 3. ENHANCE IN-APP NOTIFICATIONS
DROP POLICY IF EXISTS "notifications_select" ON public.in_app_notifications;
DROP POLICY IF EXISTS "notifications_update" ON public.in_app_notifications;

CREATE POLICY "notifications_select" ON public.in_app_notifications
  FOR SELECT TO authenticated
  USING (
    (recipient_uid = (auth.jwt() ->> 'sub')) OR
    (recipient_uid = (SELECT u.id::text FROM public.users u WHERE u.firebase_uid = (auth.jwt() ->> 'sub'))) OR
    public.is_super_admin(auth.jwt() ->> 'sub')
  );

CREATE POLICY "notifications_update" ON public.in_app_notifications
  FOR UPDATE TO authenticated
  USING (
    (recipient_uid = (auth.jwt() ->> 'sub')) OR
    (recipient_uid = (SELECT u.id::text FROM public.users u WHERE u.firebase_uid = (auth.jwt() ->> 'sub'))) OR
    public.is_super_admin(auth.jwt() ->> 'sub')
  )
  WITH CHECK (
    (recipient_uid = (auth.jwt() ->> 'sub')) OR
    (recipient_uid = (SELECT u.id::text FROM public.users u WHERE u.firebase_uid = (auth.jwt() ->> 'sub'))) OR
    public.is_super_admin(auth.jwt() ->> 'sub')
  );

GRANT SELECT, UPDATE ON public.in_app_notifications TO authenticated;

-- 4. ENHANCE MAIL QUEUE
ALTER TABLE public.mail_queue
  ADD COLUMN IF NOT EXISTS attempts INT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS error_message TEXT,
  ADD COLUMN IF NOT EXISTS metadata JSONB NOT NULL DEFAULT '{}'::jsonb;

DROP POLICY IF EXISTS "mail_queue_select" ON public.mail_queue;
DROP POLICY IF EXISTS "mail_queue_insert" ON public.mail_queue;

CREATE POLICY "mail_queue_select" ON public.mail_queue
  FOR SELECT TO authenticated
  USING (public.is_super_admin(auth.jwt() ->> 'sub'));

CREATE POLICY "mail_queue_insert" ON public.mail_queue
  FOR INSERT TO authenticated
  WITH CHECK (public.is_super_admin(auth.jwt() ->> 'sub'));

GRANT SELECT, INSERT ON public.mail_queue TO authenticated;

-- 5. VERIFY SECURITY EVENTS RLS
DROP POLICY IF EXISTS "security_events_admin" ON public.security_events;
CREATE POLICY "security_events_admin" ON public.security_events
  FOR SELECT TO authenticated
  USING (public.is_super_admin(auth.jwt() ->> 'sub'));

GRANT SELECT ON public.security_events TO authenticated;

COMMIT;
