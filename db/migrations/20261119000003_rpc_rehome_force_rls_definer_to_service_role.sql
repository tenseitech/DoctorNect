-- Re-home DEFINER RPCs (live audit: owners without BYPASSRLS that touch FORCE RLS tables).

GRANT CREATE ON SCHEMA private TO service_role;
GRANT CREATE ON SCHEMA public TO service_role;

DO $rehome$
DECLARE
  sigs text[] := ARRAY[
    'private.trigger_autolink_lab_booking_report()',
    'private.trigger_autolink_lab_order_report()',
    'private.upsert_system_config(text,jsonb)',
    'public.book_appointment_atomic(text,text,timestamp with time zone,text,text,text,integer,text,text,text)',
    'public.cancel_ambulance_broadcast(character varying)',
    'public.claim_ambulance_driver(text)',
    'public.complete_ambulance_trip(character varying,character varying)',
    'public.create_prescription_atomic(text,text,text,text,integer,jsonb,jsonb,jsonb)',
    'public.deactivate_provider_profile(text,text)',
    'public.expire_stale_ambulance_broadcasts()',
    'public.fn_sync_review_helpful_count()',
    'public.reactivate_provider_profile(text,text)',
    'public.reschedule_appointment_atomic(text,timestamp with time zone,text,text)',
    'public.update_lab_booking_status(character varying,character varying)',
    'public.update_lab_order_status(character varying,character varying)',
    'public.update_pharmacy_delivery_status(character varying,character varying,text,jsonb)'
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