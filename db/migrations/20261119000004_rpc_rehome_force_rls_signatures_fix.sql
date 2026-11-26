-- Correct OID-accurate signatures for 20261119000003 misses (replay catalog).

GRANT CREATE ON SCHEMA private TO service_role;
GRANT CREATE ON SCHEMA public TO service_role;

DO $rehome$
DECLARE
  sigs text[] := ARRAY[
    'public.book_appointment_atomic(p_appointment_id character varying, p_doctor_id character varying, p_doctor_name character varying, p_specialization character varying, p_patient_name character varying, p_patient_age integer, p_patient_gender character varying, p_date_time timestamp with time zone, p_slot_label character varying, p_visit_type character varying, p_token_number integer, p_clinic_name character varying, p_clinic_address text, p_sync_origin character varying, p_patient_id character varying)',
    'public.reschedule_appointment_atomic(p_appointment_id character varying, p_doctor_id character varying, p_new_date date, p_new_slot character varying, p_rescheduled_by character varying, p_reason text)',
    'public.complete_ambulance_trip(p_broadcast_id character varying)',
    'public.cancel_ambulance_broadcast(p_broadcast_id character varying, p_reason text)',
    'public.deactivate_provider_profile()',
    'public.reactivate_provider_profile()',
  'private.upsert_system_config(p_config_key character varying, p_config_value jsonb)',
    'public.update_lab_booking_status(p_booking_id character varying, p_new_status character varying, p_notes text)',
    'public.update_lab_order_status(p_order_id character varying, p_new_status character varying, p_notes text)',
    'public.create_prescription_atomic(payload jsonb)',
    'public.get_ambulance_trip_location(p_broadcast_id character varying)'
  ];
  s text;
BEGIN
  FOREACH s IN ARRAY sigs LOOP
    BEGIN
      EXECUTE format('ALTER FUNCTION %s OWNER TO service_role', s);
    EXCEPTION
      WHEN undefined_function THEN
        RAISE NOTICE 'skip missing function %', s;
    END;
  END LOOP;
END;
$rehome$;

REVOKE CREATE ON SCHEMA private FROM service_role;
REVOKE CREATE ON SCHEMA public FROM service_role;