-- support_tickets policies referenced public.is_super_admin(text) without schema; resolve to denied overload under SET search_path = ''.

DROP POLICY IF EXISTS support_tickets_insert ON public.support_tickets;
DROP POLICY IF EXISTS support_tickets_select ON public.support_tickets;
DROP POLICY IF EXISTS support_tickets_update ON public.support_tickets;
DROP POLICY IF EXISTS "support_tickets_write" ON public.support_tickets;

CREATE POLICY support_tickets_insert ON public.support_tickets
  FOR INSERT TO authenticated
  WITH CHECK (
    patient_id = private.current_profile_id()
    OR doctor_id = private.current_profile_id()
    OR store_id = private.current_profile_id()
    OR lab_id = private.current_profile_id()
    OR ambulance_id = private.current_profile_id()
    OR user_id = (auth.jwt() ->> 'sub')
    OR firebase_uid = (auth.jwt() ->> 'sub')
    OR private.is_super_admin()
  );

CREATE POLICY support_tickets_select ON public.support_tickets
  FOR SELECT TO authenticated
  USING (
    patient_id = private.current_profile_id()
    OR doctor_id = private.current_profile_id()
    OR store_id = private.current_profile_id()
    OR lab_id = private.current_profile_id()
    OR ambulance_id = private.current_profile_id()
    OR user_id = (auth.jwt() ->> 'sub')
    OR firebase_uid = (auth.jwt() ->> 'sub')
    OR private.is_super_admin()
  );

CREATE POLICY support_tickets_update ON public.support_tickets
  FOR UPDATE TO authenticated
  USING (
    patient_id = private.current_profile_id()
    OR doctor_id = private.current_profile_id()
    OR store_id = private.current_profile_id()
    OR lab_id = private.current_profile_id()
    OR ambulance_id = private.current_profile_id()
    OR user_id = (auth.jwt() ->> 'sub')
    OR firebase_uid = (auth.jwt() ->> 'sub')
    OR private.is_super_admin()
  )
  WITH CHECK (
    patient_id = private.current_profile_id()
    OR doctor_id = private.current_profile_id()
    OR store_id = private.current_profile_id()
    OR lab_id = private.current_profile_id()
    OR ambulance_id = private.current_profile_id()
    OR user_id = (auth.jwt() ->> 'sub')
    OR firebase_uid = (auth.jwt() ->> 'sub')
    OR private.is_super_admin()
  );

GRANT EXECUTE ON FUNCTION private.is_super_admin() TO authenticated, service_role;
