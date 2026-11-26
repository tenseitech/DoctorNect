-- DoctorNect Migration: 20261126000001_reschedule_appointment_slot_time_and_guards.sql
-- Description: FIX (PROJECT_ANALYSIS.md H2). reschedule_appointment_atomic
--   * stored 10:00 IST for every slot (the app then failed its slot/time consistency check);
--     it now uses the chosen slot ("hh:mm AM/PM", Asia/Kolkata), refusing anything else;
--   * counted capacity by slot label without a lock; it now takes the same advisory lock and
--     the same capacity rule as book_appointment_atomic (max 3 active at that exact time);
--   * could re-open cancelled / completed / no-show / in-progress appointments: refused now;
--   * accepted dates in the past: refused now.
-- Same signature and grants (CREATE OR REPLACE). Idempotent.

CREATE OR REPLACE FUNCTION public.reschedule_appointment_atomic(p_appointment_id character varying, p_doctor_id character varying, p_new_date date, p_new_slot character varying, p_rescheduled_by character varying DEFAULT 'patient'::character varying, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
    v_appt RECORD;
    v_slot_count INT;
    v_token INT;
    v_new_timestamp TIMESTAMPTZ;
    v_caller_uid TEXT;
    v_profile_id TEXT;
    v_is_admin BOOLEAN;
BEGIN
    -- 0. Caller authentication and ownership validation
    v_caller_uid := NULLIF(COALESCE(
        auth.jwt() ->> 'sub',
        auth.jwt() ->> 'uid',
        current_setting('request.jwt.claims', true)::jsonb ->> 'sub'
    ), '');
    IF v_caller_uid IS NULL THEN
        RAISE EXCEPTION 'UNAUTHORIZED: Authentication required.' USING ERRCODE = '42501';
    END IF;

    v_profile_id := private.current_profile_id();
    v_is_admin := COALESCE(private.is_super_admin(), FALSE);

    -- Early raise when profile is null and caller is not admin
    IF v_profile_id IS NULL AND NOT v_is_admin THEN
        RAISE EXCEPTION 'FORBIDDEN: Caller has no registered profile.' USING ERRCODE = '42501';
    END IF;

    -- 1. Lock appointment row
    SELECT * INTO v_appt
    FROM public.appointments
    WHERE appointment_id = p_appointment_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'APPOINTMENT_NOT_FOUND' USING ERRCODE = 'P0002';
    END IF;

    -- Null-safe ownership validation: patient, doctor, family member owner, or super_admin
    IF (v_appt.doctor_id IS DISTINCT FROM v_profile_id)
       AND (v_appt.patient_id IS DISTINCT FROM v_profile_id)
       AND NOT (
           EXISTS (SELECT 1 FROM public.patients WHERE patient_id = v_appt.patient_id AND owner_uid = v_caller_uid)
           OR EXISTS (SELECT 1 FROM public.family_members WHERE member_id = v_appt.patient_id AND patient_id = v_profile_id)
       )
       AND NOT v_is_admin THEN
        RAISE EXCEPTION 'FORBIDDEN: You do not have permission to reschedule this appointment.' USING ERRCODE = '42501';
    END IF;

    -- 2. Only an open appointment can move.
    IF v_appt.patient_status IN ('cancelled', 'completed')
       OR v_appt.doctor_status IN ('cancelled', 'completed', 'noShow', 'inProgress') THEN
        RAISE EXCEPTION 'INVALID_STATE: Only an open appointment can be rescheduled.' USING ERRCODE = 'P0001';
    END IF;

    -- 3. Target time from the chosen slot (same "hh:mm AM/PM" labels the app shows), in IST.
    IF p_new_date IS NULL OR p_new_slot IS NULL
       OR p_new_slot !~* '^\s*(0?[1-9]|1[0-2]):[0-5][0-9]\s*(AM|PM)\s*$' THEN
        RAISE EXCEPTION 'BAD_REQUEST: A date and a slot like "10:30 AM" are required.' USING ERRCODE = '22023';
    END IF;
    v_new_timestamp := pg_catalog.timezone(
        'Asia/Kolkata',
        p_new_date + pg_catalog.to_timestamp(pg_catalog.upper(pg_catalog.btrim(p_new_slot)), 'HH12:MI AM')::time
    );
    IF v_new_timestamp < pg_catalog.now() THEN
        RAISE EXCEPTION 'BAD_REQUEST: Cannot reschedule into the past.' USING ERRCODE = '22023';
    END IF;

    -- 4. Same serialization and capacity rule as book_appointment_atomic.
    PERFORM pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtext(v_appt.doctor_id),
        pg_catalog.hashtext(EXTRACT(epoch FROM v_new_timestamp)::text)
    );
    SELECT COUNT(*) INTO v_slot_count
    FROM public.appointments
    WHERE doctor_id = v_appt.doctor_id
      AND date_time = v_new_timestamp
      AND appointment_id != p_appointment_id
      AND patient_status != 'cancelled';

    IF v_slot_count >= 3 THEN
        RAISE EXCEPTION 'SLOT_CAPACITY_REACHED' USING ERRCODE = '54000';
    END IF;

    -- 5. Sequential queue token for the target date.
    SELECT COALESCE(MAX(token_number), 0) + 1 INTO v_token
    FROM public.appointments
    WHERE doctor_id = v_appt.doctor_id
      AND (date_time AT TIME ZONE 'Asia/Kolkata')::date = p_new_date;

    -- 6. Atomically update the appointment.
    UPDATE public.appointments
    SET date_time = v_new_timestamp,
        slot_label = pg_catalog.btrim(p_new_slot),
        token_number = v_token,
        patient_status = 'confirmed',
        doctor_status = 'pendingRequest',
        was_rescheduled = TRUE,
        updated_at = CURRENT_TIMESTAMP
    WHERE appointment_id = p_appointment_id;

    RETURN jsonb_build_object(
        'ok', true,
        'appointment_id', p_appointment_id,
        'token_number', v_token,
        'date_time', v_new_timestamp,
        'slot_label', pg_catalog.btrim(p_new_slot)
    );
END;
$function$;
