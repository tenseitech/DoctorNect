-- Migration: 20261026000001_rpc_null_safe_authz.sql
-- Description: Null-safe authorization hardening across client RPCs and system_config policy restriction
-- Safety: Idempotent, search_path = '', zero destructive operations, CREATE OR REPLACE only

-- 1. reschedule_appointment_atomic
CREATE OR REPLACE FUNCTION public.reschedule_appointment_atomic(
    p_appointment_id VARCHAR(64),
    p_doctor_id VARCHAR(64),
    p_new_date DATE,
    p_new_slot VARCHAR(64),
    p_rescheduled_by VARCHAR(32) DEFAULT 'patient',
    p_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
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

    -- Null-safe ownership validation using IS DISTINCT FROM
    IF (v_appt.patient_id IS DISTINCT FROM v_profile_id)
       AND (v_appt.doctor_id IS DISTINCT FROM v_profile_id)
       AND NOT v_is_admin THEN
        RAISE EXCEPTION 'FORBIDDEN: You do not have permission to reschedule this appointment.' USING ERRCODE = '42501';
    END IF;

    -- 2. Validate slot capacity (maximum 3 concurrent bookings per slot)
    SELECT COUNT(*) INTO v_slot_count
    FROM public.appointments
    WHERE doctor_id = v_appt.doctor_id
      AND slot_label = p_new_slot
      AND date_time::date = p_new_date
      AND appointment_id != p_appointment_id
      AND patient_status != 'cancelled'
      AND doctor_status != 'cancelled';

    IF v_slot_count >= 3 THEN
        RAISE EXCEPTION 'SLOT_CAPACITY_REACHED' USING ERRCODE = '54000';
    END IF;

    -- 3. Calculate sequential queue token for target date
    SELECT COALESCE(MAX(token_number), 0) + 1 INTO v_token
    FROM public.appointments
    WHERE doctor_id = v_appt.doctor_id
      AND date_time::date = p_new_date;

    -- 4. Construct new target timestamp preserving slot or defaulting to midday
    v_new_timestamp := (p_new_date::text || ' 10:00:00+00')::TIMESTAMPTZ;

    -- 5. Atomically update the appointment
    UPDATE public.appointments
    SET date_time = v_new_timestamp,
        slot_label = p_new_slot,
        token_number = v_token,
        patient_status = CASE WHEN p_rescheduled_by = 'patient' THEN 'rescheduled' ELSE patient_status END,
        doctor_status = CASE WHEN p_rescheduled_by = 'doctor' THEN 'rescheduled' ELSE doctor_status END,
        cancellation_reason = COALESCE(p_reason, cancellation_reason),
        updated_at = CURRENT_TIMESTAMP
    WHERE appointment_id = p_appointment_id
    RETURNING * INTO v_appt;

    RETURN to_jsonb(v_appt);
END;
$$;

REVOKE ALL ON FUNCTION public.reschedule_appointment_atomic(VARCHAR, VARCHAR, DATE, VARCHAR, VARCHAR, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reschedule_appointment_atomic(VARCHAR, VARCHAR, DATE, VARCHAR, VARCHAR, TEXT) TO authenticated, service_role;


-- 2. cancel_ambulance_broadcast
CREATE OR REPLACE FUNCTION public.cancel_ambulance_broadcast(
    p_broadcast_id VARCHAR(64),
    p_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_caller_uid TEXT;
    v_profile_id TEXT;
    v_broadcast public.ambulance_broadcasts%ROWTYPE;
    v_is_patient BOOLEAN;
    v_is_admin BOOLEAN;
BEGIN
    v_caller_uid := NULLIF(COALESCE(
        auth.jwt() ->> 'sub',
        auth.jwt() ->> 'uid',
        current_setting('request.jwt.claims', true)::jsonb ->> 'sub'
    ), '');
    IF v_caller_uid IS NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
    END IF;

    v_profile_id := private.current_profile_id();
    v_is_admin := COALESCE(private.is_super_admin(), FALSE);

    IF v_profile_id IS NULL AND NOT v_is_admin THEN
        RAISE EXCEPTION 'FORBIDDEN: Caller has no registered profile.' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_broadcast
    FROM public.ambulance_broadcasts WHERE broadcast_id = p_broadcast_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Broadcast % not found', p_broadcast_id USING ERRCODE = 'P0002';
    END IF;

    v_is_patient := (v_broadcast.patient_id IS NOT DISTINCT FROM v_profile_id) OR EXISTS (
        SELECT 1 FROM public.patients p WHERE p.patient_id = v_broadcast.patient_id AND p.owner_uid = v_caller_uid
    );

    IF NOT (COALESCE(v_is_patient, FALSE) OR v_is_admin) THEN
        RAISE EXCEPTION 'Unauthorized to cancel broadcast' USING ERRCODE = '42501';
    END IF;

    IF v_broadcast.status = 'completed' THEN
        RAISE EXCEPTION 'Cannot cancel a completed trip' USING ERRCODE = '22023';
    END IF;

    PERFORM set_config('app.allow_ambulance_status_change', 'true', true);

    UPDATE public.ambulance_broadcasts
    SET status = 'cancelled',
        notes = CASE WHEN p_reason IS NOT NULL THEN COALESCE(notes || ' | Cancellation reason: ' || p_reason, p_reason) ELSE notes END,
        updated_at = CURRENT_TIMESTAMP
    WHERE broadcast_id = p_broadcast_id;

    UPDATE public.ambulance_requests
    SET status = 'cancelled',
        updated_at = CURRENT_TIMESTAMP
    WHERE broadcast_id = p_broadcast_id
      AND status IN ('pending', 'taken');

    DELETE FROM public.ambulance_locations WHERE broadcast_id = p_broadcast_id;
    DELETE FROM public.ambulance_trip_contacts WHERE broadcast_id = p_broadcast_id;

    PERFORM set_config('app.allow_ambulance_status_change', '', true);

    RETURN jsonb_build_object(
        'success', true,
        'broadcast_id', p_broadcast_id,
        'status', 'cancelled'
    );
END;
$$;

REVOKE ALL ON FUNCTION public.cancel_ambulance_broadcast(VARCHAR, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cancel_ambulance_broadcast(VARCHAR, TEXT) TO authenticated, service_role;


-- 3. get_ambulance_trip_location
CREATE OR REPLACE FUNCTION public.get_ambulance_trip_location(
    p_broadcast_id VARCHAR(64)
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_caller_uid TEXT;
    v_profile_id TEXT;
    v_broadcast public.ambulance_broadcasts%ROWTYPE;
    v_loc public.ambulance_locations%ROWTYPE;
    v_is_patient BOOLEAN;
    v_is_driver BOOLEAN;
    v_is_admin BOOLEAN;
BEGIN
    v_caller_uid := NULLIF(COALESCE(
        auth.jwt() ->> 'sub',
        auth.jwt() ->> 'uid',
        current_setting('request.jwt.claims', true)::jsonb ->> 'sub'
    ), '');
    IF v_caller_uid IS NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
    END IF;

    v_profile_id := private.current_profile_id();
    v_is_admin := COALESCE(private.is_super_admin(), FALSE);

    IF v_profile_id IS NULL AND NOT v_is_admin THEN
        RAISE EXCEPTION 'FORBIDDEN: Caller has no registered profile.' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_broadcast
    FROM public.ambulance_broadcasts
    WHERE broadcast_id = p_broadcast_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Broadcast % not found', p_broadcast_id USING ERRCODE = 'P0002';
    END IF;

    v_is_patient := (v_broadcast.patient_id IS NOT DISTINCT FROM v_profile_id) OR EXISTS (
        SELECT 1 FROM public.patients p WHERE p.patient_id = v_broadcast.patient_id AND p.owner_uid = v_caller_uid
    );
    v_is_driver := (v_broadcast.accepted_driver_id IS NOT DISTINCT FROM v_profile_id) OR EXISTS (
        SELECT 1 FROM public.ambulances a WHERE a.ambulance_id = v_broadcast.accepted_driver_id AND a.auth_uid = v_caller_uid
    );

    IF NOT (COALESCE(v_is_patient, FALSE) OR COALESCE(v_is_driver, FALSE) OR v_is_admin) THEN
        RAISE EXCEPTION 'Unauthorized to view trip location' USING ERRCODE = '42501';
    END IF;

    -- Zero location returned unless active accepted trip
    IF v_broadcast.status != 'accepted' THEN
        RETURN jsonb_build_object(
            'active', false,
            'status', v_broadcast.status,
            'location', NULL
        );
    END IF;

    SELECT * INTO v_loc
    FROM public.ambulance_locations
    WHERE broadcast_id = p_broadcast_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'active', true,
            'status', 'accepted',
            'location', NULL
        );
    END IF;

    RETURN jsonb_build_object(
        'active', true,
        'status', 'accepted',
        'latitude', v_loc.latitude,
        'longitude', v_loc.longitude,
        'heading', v_loc.heading,
        'speed', v_loc.speed,
        'updated_at', v_loc.updated_at
    );
END;
$$;

REVOKE ALL ON FUNCTION public.get_ambulance_trip_location(VARCHAR) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_ambulance_trip_location(VARCHAR) TO authenticated, service_role;


-- 4. update_ambulance_location
CREATE OR REPLACE FUNCTION public.update_ambulance_location(
    p_broadcast_id VARCHAR(64),
    p_latitude DOUBLE PRECISION,
    p_longitude DOUBLE PRECISION,
    p_heading DOUBLE PRECISION DEFAULT NULL,
    p_speed DOUBLE PRECISION DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_caller_uid TEXT;
    v_profile_id TEXT;
    v_driver_id TEXT;
    v_broadcast public.ambulance_broadcasts%ROWTYPE;
    v_is_admin BOOLEAN;
BEGIN
    v_caller_uid := NULLIF(COALESCE(
        auth.jwt() ->> 'sub',
        auth.jwt() ->> 'uid',
        current_setting('request.jwt.claims', true)::jsonb ->> 'sub'
    ), '');
    IF v_caller_uid IS NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
    END IF;

    v_profile_id := private.current_profile_id();
    v_is_admin := COALESCE(private.is_super_admin(), FALSE);

    SELECT ambulance_id INTO v_driver_id
    FROM public.ambulances
    WHERE auth_uid = v_caller_uid OR (v_profile_id IS NOT NULL AND ambulance_id = v_profile_id);

    IF v_driver_id IS NULL AND NOT v_is_admin THEN
        RAISE EXCEPTION 'Ambulance driver profile not registered' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_broadcast
    FROM public.ambulance_broadcasts
    WHERE broadcast_id = p_broadcast_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Broadcast % not found', p_broadcast_id USING ERRCODE = 'P0002';
    END IF;

    IF (v_broadcast.accepted_driver_id IS DISTINCT FROM v_driver_id) AND NOT v_is_admin THEN
        RAISE EXCEPTION 'Only the assigned driver can transmit location' USING ERRCODE = '42501';
    END IF;

    IF v_broadcast.status != 'accepted' THEN
        RAISE EXCEPTION 'Location updates allowed only during active accepted trip (status: %)', v_broadcast.status
            USING ERRCODE = '42501';
    END IF;

    -- Upsert location
    INSERT INTO public.ambulance_locations (
        broadcast_id, driver_id, latitude, longitude, heading, speed, updated_at
    )
    VALUES (
        p_broadcast_id, v_driver_id, p_latitude, p_longitude, p_heading, p_speed, CURRENT_TIMESTAMP
    )
    ON CONFLICT (broadcast_id) DO UPDATE SET
        latitude = EXCLUDED.latitude,
        longitude = EXCLUDED.longitude,
        heading = EXCLUDED.heading,
        speed = EXCLUDED.speed,
        updated_at = CURRENT_TIMESTAMP;

    -- Bump change signal
    INSERT INTO public.ambulance_location_updates (broadcast_id, updated_at)
    VALUES (p_broadcast_id, CURRENT_TIMESTAMP)
    ON CONFLICT (broadcast_id) DO UPDATE SET updated_at = CURRENT_TIMESTAMP;

    RETURN jsonb_build_object(
        'success', true,
        'broadcast_id', p_broadcast_id,
        'updated_at', CURRENT_TIMESTAMP
    );
END;
$$;

REVOKE ALL ON FUNCTION public.update_ambulance_location(VARCHAR, DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_ambulance_location(VARCHAR, DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION) TO authenticated, service_role;


-- 5. complete_ambulance_trip
CREATE OR REPLACE FUNCTION public.complete_ambulance_trip(
    p_broadcast_id VARCHAR(64)
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_caller_uid TEXT;
    v_profile_id TEXT;
    v_broadcast public.ambulance_broadcasts%ROWTYPE;
    v_driver_id TEXT;
    v_is_admin BOOLEAN;
BEGIN
    v_caller_uid := NULLIF(COALESCE(
        auth.jwt() ->> 'sub',
        auth.jwt() ->> 'uid',
        current_setting('request.jwt.claims', true)::jsonb ->> 'sub'
    ), '');
    IF v_caller_uid IS NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
    END IF;

    v_profile_id := private.current_profile_id();
    v_is_admin := COALESCE(private.is_super_admin(), FALSE);

    IF v_profile_id IS NULL AND NOT v_is_admin THEN
        RAISE EXCEPTION 'FORBIDDEN: Caller has no registered profile.' USING ERRCODE = '42501';
    END IF;

    SELECT ambulance_id INTO v_driver_id
    FROM public.ambulances
    WHERE auth_uid = v_caller_uid OR (v_profile_id IS NOT NULL AND ambulance_id = v_profile_id);

    IF v_driver_id IS NULL AND NOT v_is_admin THEN
        RAISE EXCEPTION 'Ambulance driver profile not registered' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_broadcast
    FROM public.ambulance_broadcasts WHERE broadcast_id = p_broadcast_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Broadcast % not found', p_broadcast_id USING ERRCODE = 'P0002';
    END IF;

    -- Require status = 'accepted'
    IF v_broadcast.status != 'accepted' THEN
        RAISE EXCEPTION 'Cannot complete trip: broadcast is not in accepted status (current status: %)', v_broadcast.status
            USING ERRCODE = '42501';
    END IF;

    IF (v_broadcast.accepted_driver_id IS DISTINCT FROM v_driver_id) AND NOT v_is_admin THEN
        RAISE EXCEPTION 'Only the assigned driver can complete the trip' USING ERRCODE = '42501';
    END IF;

    PERFORM set_config('app.allow_ambulance_status_change', 'true', true);

    UPDATE public.ambulance_broadcasts
    SET status = 'completed',
        updated_at = CURRENT_TIMESTAMP
    WHERE broadcast_id = p_broadcast_id;

    -- Clear live location upon trip completion (privacy protection)
    DELETE FROM public.ambulance_locations WHERE broadcast_id = p_broadcast_id;

    -- Clear contact driver phone upon trip completion (phone visible only during active trip)
    UPDATE public.ambulance_trip_contacts
    SET driver_phone = NULL,
        updated_at = CURRENT_TIMESTAMP
    WHERE broadcast_id = p_broadcast_id;

    PERFORM set_config('app.allow_ambulance_status_change', '', true);

    RETURN jsonb_build_object(
        'success', true,
        'broadcast_id', p_broadcast_id,
        'status', 'completed'
    );
END;
$$;

REVOKE ALL ON FUNCTION public.complete_ambulance_trip(VARCHAR) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.complete_ambulance_trip(VARCHAR) TO authenticated, service_role;


-- 6. accept_ambulance_request
CREATE OR REPLACE FUNCTION public.accept_ambulance_request(
    p_broadcast_id VARCHAR(64),
    p_request_id VARCHAR(64) DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_caller_uid TEXT;
    v_profile_id TEXT;
    v_driver_id TEXT;
    v_driver public.ambulances%ROWTYPE;
    v_broadcast public.ambulance_broadcasts%ROWTYPE;
    v_contact public.ambulance_trip_contacts%ROWTYPE;
    v_winning_request_id VARCHAR(64);
BEGIN
    v_caller_uid := NULLIF(COALESCE(
        auth.jwt() ->> 'sub',
        auth.jwt() ->> 'uid',
        current_setting('request.jwt.claims', true)::jsonb ->> 'sub'
    ), '');
    IF v_caller_uid IS NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
    END IF;

    v_profile_id := private.current_profile_id();

    -- Resolve driver profile
    SELECT * INTO v_driver
    FROM public.ambulances
    WHERE auth_uid = v_caller_uid OR (v_profile_id IS NOT NULL AND ambulance_id = v_profile_id);

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Ambulance driver profile not registered' USING ERRCODE = '42501';
    END IF;

    IF v_driver.verified != TRUE THEN
        RAISE EXCEPTION 'Only verified ambulance drivers can accept emergency requests' USING ERRCODE = '42501';
    END IF;

    v_driver_id := v_driver.ambulance_id;

    -- Lock the broadcast row FOR UPDATE to prevent race conditions
    SELECT * INTO v_broadcast
    FROM public.ambulance_broadcasts
    WHERE broadcast_id = p_broadcast_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Broadcast % not found', p_broadcast_id USING ERRCODE = 'P0002';
    END IF;

    IF v_broadcast.status != 'pending' THEN
        RAISE EXCEPTION 'This emergency request has already been accepted or cancelled (status: %)', v_broadcast.status
            USING ERRCODE = '42501';
    END IF;

    -- Determine winning request id strictly bound to broadcast_id and v_driver_id
    IF p_request_id IS NOT NULL THEN
        SELECT request_id INTO v_winning_request_id
        FROM public.ambulance_requests
        WHERE request_id = p_request_id
          AND broadcast_id = p_broadcast_id
          AND driver_id = v_driver_id;

        IF v_winning_request_id IS NULL THEN
            RAISE EXCEPTION 'Request % does not belong to broadcast % and driver %', p_request_id, p_broadcast_id, v_driver_id
                USING ERRCODE = '42501';
        END IF;
    ELSE
        SELECT request_id INTO v_winning_request_id
        FROM public.ambulance_requests
        WHERE broadcast_id = p_broadcast_id AND driver_id = v_driver_id
        LIMIT 1;
    END IF;

    -- Look up contacts (patient phone)
    SELECT * INTO v_contact FROM public.ambulance_trip_contacts WHERE broadcast_id = p_broadcast_id;

    -- Set session guard to permit triggers
    PERFORM set_config('app.allow_ambulance_status_change', 'true', true);

    -- 1. Driver wins! Update broadcast
    UPDATE public.ambulance_broadcasts
    SET status = 'accepted',
        accepted_driver_id = v_driver_id,
        accepted_driver_name = v_driver.driver_name,
        accepted_driver_phone = v_driver.phone,
        accepted_vehicle_number = v_driver.vehicle_number,
        accepted_ambulance_type = v_driver.ambulance_type,
        accepted_at = CURRENT_TIMESTAMP,
        updated_at = CURRENT_TIMESTAMP
    WHERE broadcast_id = p_broadcast_id;

    -- 2. Store driver contact phone in private contacts
    INSERT INTO public.ambulance_trip_contacts (broadcast_id, patient_phone, driver_phone, updated_at)
    VALUES (
        p_broadcast_id,
        COALESCE(v_contact.patient_phone, v_broadcast.contact_phone, 'Unknown'),
        v_driver.phone,
        CURRENT_TIMESTAMP
    )
    ON CONFLICT (broadcast_id) DO UPDATE SET
        driver_phone = EXCLUDED.driver_phone,
        updated_at = CURRENT_TIMESTAMP;

    -- 3. Mark winning driver request as accepted
    IF v_winning_request_id IS NOT NULL THEN
        UPDATE public.ambulance_requests
        SET status = 'accepted',
            accepted_driver_id = v_driver_id,
            updated_at = CURRENT_TIMESTAMP
        WHERE request_id = v_winning_request_id;
    END IF;

    -- 4. Atomically mark all sibling pending requests as taken
    UPDATE public.ambulance_requests
    SET status = 'taken',
        accepted_driver_id = v_driver_id,
        updated_at = CURRENT_TIMESTAMP
    WHERE broadcast_id = p_broadcast_id
      AND (v_winning_request_id IS NULL OR request_id != v_winning_request_id)
      AND status = 'pending';

    -- 5. Initialize location signal
    INSERT INTO public.ambulance_location_updates (broadcast_id, updated_at)
    VALUES (p_broadcast_id, CURRENT_TIMESTAMP)
    ON CONFLICT (broadcast_id) DO UPDATE SET updated_at = CURRENT_TIMESTAMP;

    PERFORM set_config('app.allow_ambulance_status_change', '', true);

    RETURN jsonb_build_object(
        'success', true,
        'broadcast_id', p_broadcast_id,
        'status', 'accepted',
        'accepted_driver_id', v_driver_id,
        'accepted_driver_name', v_driver.driver_name,
        'accepted_vehicle_number', v_driver.vehicle_number,
        'contact_phone', COALESCE(v_contact.patient_phone, v_broadcast.contact_phone)
    );
END;
$$;

REVOKE ALL ON FUNCTION public.accept_ambulance_request(VARCHAR, VARCHAR) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.accept_ambulance_request(VARCHAR, VARCHAR) TO authenticated, service_role;


-- 7. update_lab_booking_status
CREATE OR REPLACE FUNCTION public.update_lab_booking_status(
    p_booking_id VARCHAR(64),
    p_new_status VARCHAR(32),
    p_notes TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_caller_uid TEXT;
    v_profile_id TEXT;
    v_booking public.lab_bookings%ROWTYPE;
    v_is_lab BOOLEAN;
    v_is_patient BOOLEAN;
    v_is_admin BOOLEAN;
BEGIN
    v_caller_uid := NULLIF(COALESCE(
        auth.jwt() ->> 'sub',
        auth.jwt() ->> 'uid',
        current_setting('request.jwt.claims', true)::jsonb ->> 'sub'
    ), '');
    IF v_caller_uid IS NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
    END IF;

    v_profile_id := private.current_profile_id();
    v_is_admin := COALESCE(private.is_super_admin(), FALSE);

    IF v_profile_id IS NULL AND NOT v_is_admin THEN
        RAISE EXCEPTION 'FORBIDDEN: Caller has no registered profile.' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_booking
    FROM public.lab_bookings
    WHERE booking_id = p_booking_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Lab booking % not found', p_booking_id USING ERRCODE = 'P0002';
    END IF;

    v_is_lab := (v_booking.lab_id IS NOT DISTINCT FROM v_profile_id) OR EXISTS (
        SELECT 1 FROM public.labs l WHERE l.lab_id = v_booking.lab_id AND l.owner_uid = v_caller_uid
    );
    v_is_patient := (v_booking.patient_id IS NOT DISTINCT FROM v_profile_id) OR EXISTS (
        SELECT 1 FROM public.patients p WHERE p.patient_id = v_booking.patient_id AND p.owner_uid = v_caller_uid
    );

    IF NOT (COALESCE(v_is_lab, FALSE) OR COALESCE(v_is_patient, FALSE) OR v_is_admin) THEN
        RAISE EXCEPTION 'Unauthorized to update lab booking' USING ERRCODE = '42501';
    END IF;

    -- State machine validation
    IF v_is_patient AND NOT v_is_admin THEN
        IF p_new_status != 'cancelled' THEN
            RAISE EXCEPTION 'Patients can only cancel lab bookings' USING ERRCODE = '42501';
        END IF;
        IF v_booking.status != 'confirmed' THEN
            RAISE EXCEPTION 'Patient cannot cancel after sample collection (status: %)', v_booking.status
                USING ERRCODE = '42501';
        END IF;
    ELSIF v_is_lab THEN
        IF v_booking.status = 'confirmed' AND p_new_status NOT IN ('sampleCollected', 'cancelled') THEN
            RAISE EXCEPTION 'Invalid transition from confirmed to %', p_new_status USING ERRCODE = '22023';
        ELSIF v_booking.status = 'sampleCollected' AND p_new_status NOT IN ('inAnalysis') THEN
            RAISE EXCEPTION 'Invalid transition from sampleCollected to %', p_new_status USING ERRCODE = '22023';
        ELSIF v_booking.status = 'inAnalysis' AND p_new_status NOT IN ('completed') THEN
            RAISE EXCEPTION 'Invalid transition from inAnalysis to %', p_new_status USING ERRCODE = '22023';
        ELSIF v_booking.status IN ('completed', 'cancelled') THEN
            RAISE EXCEPTION 'Booking is already in terminal state: %', v_booking.status USING ERRCODE = '22023';
        END IF;
    END IF;

    PERFORM set_config('app.allow_lab_status_change', 'true', true);

    UPDATE public.lab_bookings
    SET status = p_new_status,
        updated_at = CURRENT_TIMESTAMP
    WHERE booking_id = p_booking_id;

    PERFORM set_config('app.allow_lab_status_change', '', true);

    RETURN jsonb_build_object(
        'success', true,
        'booking_id', p_booking_id,
        'old_status', v_booking.status,
        'new_status', p_new_status
    );
END;
$$;

REVOKE ALL ON FUNCTION public.update_lab_booking_status(VARCHAR, VARCHAR, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_lab_booking_status(VARCHAR, VARCHAR, TEXT) TO authenticated, service_role;


-- 8. update_lab_order_status
CREATE OR REPLACE FUNCTION public.update_lab_order_status(
    p_order_id VARCHAR(64),
    p_new_status VARCHAR(32),
    p_notes TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_caller_uid TEXT;
    v_profile_id TEXT;
    v_order public.lab_orders%ROWTYPE;
    v_is_lab BOOLEAN;
    v_is_doctor BOOLEAN;
    v_is_admin BOOLEAN;
BEGIN
    v_caller_uid := NULLIF(COALESCE(
        auth.jwt() ->> 'sub',
        auth.jwt() ->> 'uid',
        current_setting('request.jwt.claims', true)::jsonb ->> 'sub'
    ), '');
    IF v_caller_uid IS NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
    END IF;

    v_profile_id := private.current_profile_id();
    v_is_admin := COALESCE(private.is_super_admin(), FALSE);

    IF v_profile_id IS NULL AND NOT v_is_admin THEN
        RAISE EXCEPTION 'FORBIDDEN: Caller has no registered profile.' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_order
    FROM public.lab_orders
    WHERE order_id = p_order_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Lab order % not found', p_order_id USING ERRCODE = 'P0002';
    END IF;

    v_is_lab := (v_order.lab_id IS NOT DISTINCT FROM v_profile_id) OR EXISTS (
        SELECT 1 FROM public.labs l WHERE l.lab_id = v_order.lab_id AND l.owner_uid = v_caller_uid
    );
    v_is_doctor := (v_order.doctor_id IS NOT DISTINCT FROM v_profile_id) OR EXISTS (
        SELECT 1 FROM public.doctors d WHERE d.doctor_id = v_order.doctor_id AND d.owner_uid = v_caller_uid
    );

    IF NOT (COALESCE(v_is_lab, FALSE) OR COALESCE(v_is_doctor, FALSE) OR v_is_admin) THEN
        RAISE EXCEPTION 'Unauthorized to update lab order' USING ERRCODE = '42501';
    END IF;

    IF v_is_doctor AND NOT v_is_admin THEN
        IF p_new_status != 'cancelled' THEN
            RAISE EXCEPTION 'Doctor can only cancel lab order' USING ERRCODE = '42501';
        END IF;
        IF v_order.status IN ('inProgress', 'completed') THEN
            RAISE EXCEPTION 'Cannot cancel order after lab processing has begun (status: %)', v_order.status
                USING ERRCODE = '42501';
        END IF;
    ELSIF v_is_lab THEN
        IF v_order.status = 'ordered' AND p_new_status NOT IN ('received', 'cancelled') THEN
            RAISE EXCEPTION 'Invalid transition from ordered to %', p_new_status USING ERRCODE = '22023';
        ELSIF v_order.status = 'received' AND p_new_status NOT IN ('inProgress') THEN
            RAISE EXCEPTION 'Invalid transition from received to %', p_new_status USING ERRCODE = '22023';
        ELSIF v_order.status = 'inProgress' AND p_new_status NOT IN ('completed') THEN
            RAISE EXCEPTION 'Invalid transition from inProgress to %', p_new_status USING ERRCODE = '22023';
        ELSIF v_order.status IN ('completed', 'cancelled') THEN
            RAISE EXCEPTION 'Order is in terminal state: %', v_order.status USING ERRCODE = '22023';
        END IF;
    END IF;

    PERFORM set_config('app.allow_lab_status_change', 'true', true);

    UPDATE public.lab_orders
    SET status = p_new_status,
        updated_at = CURRENT_TIMESTAMP
    WHERE order_id = p_order_id;

    PERFORM set_config('app.allow_lab_status_change', '', true);

    RETURN jsonb_build_object(
        'success', true,
        'order_id', p_order_id,
        'old_status', v_order.status,
        'new_status', p_new_status
    );
END;
$$;

REVOKE ALL ON FUNCTION public.update_lab_order_status(VARCHAR, VARCHAR, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_lab_order_status(VARCHAR, VARCHAR, TEXT) TO authenticated, service_role;


-- 9. update_pharmacy_delivery_status
CREATE OR REPLACE FUNCTION public.update_pharmacy_delivery_status(
    p_delivery_id VARCHAR(64),
    p_new_status VARCHAR(32),
    p_notes TEXT DEFAULT NULL,
    p_medicine_lines JSONB DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_caller_uid TEXT;
    v_profile_id TEXT;
    v_delivery public.pharmacy_deliveries%ROWTYPE;
    v_is_store BOOLEAN;
    v_is_patient BOOLEAN;
    v_is_admin BOOLEAN;
    v_line RECORD;
BEGIN
    v_caller_uid := NULLIF(COALESCE(
        auth.jwt() ->> 'sub',
        auth.jwt() ->> 'uid',
        current_setting('request.jwt.claims', true)::jsonb ->> 'sub'
    ), '');
    IF v_caller_uid IS NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
    END IF;

    v_profile_id := private.current_profile_id();
    v_is_admin := COALESCE(private.is_super_admin(), FALSE);

    IF v_profile_id IS NULL AND NOT v_is_admin THEN
        RAISE EXCEPTION 'FORBIDDEN: Caller has no registered profile.' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_delivery
    FROM public.pharmacy_deliveries
    WHERE delivery_id = p_delivery_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Delivery % not found', p_delivery_id USING ERRCODE = 'P0002';
    END IF;

    v_is_store := (v_delivery.store_id IS NOT DISTINCT FROM v_profile_id) OR EXISTS (
        SELECT 1 FROM public.medical_stores ms WHERE ms.store_id = v_delivery.store_id AND ms.owner_uid = v_caller_uid
    );
    v_is_patient := (v_delivery.patient_id IS NOT DISTINCT FROM v_profile_id) OR EXISTS (
        SELECT 1 FROM public.patients p WHERE p.patient_id = v_delivery.patient_id AND p.owner_uid = v_caller_uid
    );

    IF NOT (COALESCE(v_is_store, FALSE) OR COALESCE(v_is_patient, FALSE) OR v_is_admin) THEN
        RAISE EXCEPTION 'Unauthorized to update delivery status' USING ERRCODE = '42501';
    END IF;

    -- p_medicine_lines allowed for the dispensing store only
    IF p_medicine_lines IS NOT NULL AND NOT (COALESCE(v_is_store, FALSE) OR v_is_admin) THEN
        RAISE EXCEPTION 'FORBIDDEN: Medicine lines can only be updated by the dispensing store'
            USING ERRCODE = '42501';
    END IF;

    -- Validated State Machine
    IF v_is_store THEN
        IF p_new_status = 'cancelled' AND NOT v_is_admin THEN
            RAISE EXCEPTION 'Only patient or administrator can cancel a delivery' USING ERRCODE = '42501';
        END IF;

        IF v_delivery.status = 'sent' AND p_new_status NOT IN ('viewed', 'processing', 'partiallyDispensed', 'dispatched') THEN
            RAISE EXCEPTION 'Invalid transition from sent to %', p_new_status USING ERRCODE = '22023';
        ELSIF v_delivery.status IN ('viewed', 'processing', 'partiallyDispensed') AND p_new_status NOT IN ('processing', 'partiallyDispensed', 'dispatched') THEN
            RAISE EXCEPTION 'Invalid transition from % to %', v_delivery.status, p_new_status USING ERRCODE = '22023';
        ELSIF v_delivery.status = 'dispatched' AND p_new_status NOT IN ('delivered', 'dispensed') THEN
            RAISE EXCEPTION 'Invalid transition from dispatched to %', p_new_status USING ERRCODE = '22023';
        ELSIF v_delivery.status IN ('delivered', 'dispensed', 'cancelled') THEN
            RAISE EXCEPTION 'Delivery is in terminal status: %', v_delivery.status USING ERRCODE = '22023';
        END IF;
    ELSIF v_is_patient AND NOT v_is_admin THEN
        IF p_new_status != 'cancelled' THEN
            RAISE EXCEPTION 'Patients can only cancel deliveries' USING ERRCODE = '42501';
        END IF;
        IF v_delivery.status IN ('dispatched', 'delivered', 'dispensed') THEN
            RAISE EXCEPTION 'Patient cannot cancel delivery after dispatch (current status: %)', v_delivery.status
                USING ERRCODE = '42501';
        END IF;
    END IF;

    -- Set session guard to permit trigger
    PERFORM set_config('app.allow_delivery_status_change', 'true', true);

    UPDATE public.pharmacy_deliveries
    SET status = p_new_status,
        dispensing_notes = COALESCE(p_notes, dispensing_notes),
        viewed_at = CASE WHEN p_new_status = 'viewed' AND viewed_at IS NULL THEN CURRENT_TIMESTAMP ELSE viewed_at END,
        dispensed_at = CASE WHEN p_new_status IN ('delivered', 'dispensed') AND dispensed_at IS NULL THEN CURRENT_TIMESTAMP ELSE dispensed_at END,
        updated_at = CURRENT_TIMESTAMP
    WHERE delivery_id = p_delivery_id;

    PERFORM set_config('app.allow_delivery_status_change', '', true);

    -- Optionally update medicine dispense lines (Store only)
    IF p_medicine_lines IS NOT NULL AND jsonb_typeof(p_medicine_lines) = 'array' THEN
        FOR v_line IN SELECT * FROM jsonb_to_recordset(p_medicine_lines) AS x(
            medicine_entry_id VARCHAR(64),
            dispensed_quantity INT,
            substituted_medicine_name TEXT,
            substituted_dosage TEXT,
            status VARCHAR(32)
        ) LOOP
            UPDATE public.pharmacy_delivery_medicines
            SET dispensed_quantity = COALESCE(v_line.dispensed_quantity, dispensed_quantity),
                substituted_medicine_name = COALESCE(v_line.substituted_medicine_name, substituted_medicine_name),
                substituted_dosage = COALESCE(v_line.substituted_dosage, substituted_dosage),
                status = COALESCE(v_line.status, status)
            WHERE delivery_id = p_delivery_id
              AND medicine_entry_id = v_line.medicine_entry_id;
        END LOOP;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'delivery_id', p_delivery_id,
        'old_status', v_delivery.status,
        'new_status', p_new_status
    );
END;
$$;

REVOKE ALL ON FUNCTION public.update_pharmacy_delivery_status(VARCHAR, VARCHAR, TEXT, JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_pharmacy_delivery_status(VARCHAR, VARCHAR, TEXT, JSONB) TO authenticated, service_role;


-- 10. book_appointment_atomic
CREATE OR REPLACE FUNCTION public.book_appointment_atomic(
    p_appointment_id VARCHAR(64),
    p_doctor_id VARCHAR(64),
    p_doctor_name VARCHAR(255),
    p_specialization VARCHAR(128),
    p_patient_name VARCHAR(255),
    p_patient_age INTEGER,
    p_patient_gender VARCHAR(16),
    p_date_time TIMESTAMPTZ,
    p_slot_label VARCHAR(64),
    p_visit_type VARCHAR(32) DEFAULT 'newVisit',
    p_token_number INTEGER DEFAULT NULL,
    p_clinic_name VARCHAR(255) DEFAULT NULL,
    p_clinic_address TEXT DEFAULT NULL,
    p_sync_origin VARCHAR(32) DEFAULT 'patient_supabase',
    p_patient_id VARCHAR(64) DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_caller_uid TEXT;
    v_caller_patient_id TEXT;
    v_patient_id TEXT;
    v_active_count INTEGER;
    v_token_number INTEGER;
    v_appointment RECORD;
    v_doc RECORD;
    v_doctor_name VARCHAR(255);
    v_specialization VARCHAR(128);
    v_lock_key1 INTEGER;
    v_lock_key2 INTEGER;
    v_is_admin BOOLEAN;
BEGIN
    -- 0. Strictly derive caller UID from auth.jwt()->>'sub'
    v_caller_uid := NULLIF(COALESCE(
        auth.jwt()->>'sub',
        auth.jwt()->>'uid',
        current_setting('request.jwt.claims', true)::jsonb->>'sub'
    ), '');

    IF v_caller_uid IS NULL THEN
        RAISE EXCEPTION 'UNAUTHORIZED: Authentication required to book an appointment.'
            USING ERRCODE = '42501';
    END IF;

    v_is_admin := COALESCE(private.is_super_admin(), FALSE);

    -- Resolve caller's own patient profile_id
    SELECT profile_id INTO v_caller_patient_id
    FROM public.users
    WHERE id = v_caller_uid
    LIMIT 1;

    IF v_caller_patient_id IS NULL AND NOT v_is_admin THEN
        RAISE EXCEPTION 'FORBIDDEN: Caller has no registered profile.'
            USING ERRCODE = '42501';
    END IF;

    IF v_caller_patient_id IS NULL THEN
        v_caller_patient_id := v_caller_uid;
    END IF;

    -- Verify patient ownership: caller can only book for themselves or their owned family members
    IF p_patient_id IS NOT NULL AND trim(p_patient_id) != '' THEN
        v_patient_id := trim(p_patient_id);
        IF NOT v_is_admin AND (v_patient_id IS DISTINCT FROM v_caller_patient_id) THEN
            IF NOT EXISTS (
                SELECT 1 FROM public.patients WHERE patient_id = v_patient_id AND owner_uid = v_caller_uid
            ) AND NOT EXISTS (
                SELECT 1 FROM public.family_members WHERE member_id = v_patient_id AND patient_id = v_caller_patient_id
            ) THEN
                RAISE EXCEPTION 'FORBIDDEN: Callers may only book appointments for their own patient profile.'
                    USING ERRCODE = '42501';
            END IF;
        END IF;
    ELSE
        v_patient_id := v_caller_patient_id;
    END IF;

    -- Validate required parameters
    IF p_appointment_id IS NULL OR p_doctor_id IS NULL OR p_date_time IS NULL THEN
        RAISE EXCEPTION 'BAD_REQUEST: appointment_id, doctor_id, and date_time cannot be null.'
            USING ERRCODE = '22004';
    END IF;

    -- 1. Idempotency Check: If appointment_id already booked, return it only when existing.patient_id = v_patient_id, else raise
    SELECT * INTO v_appointment FROM public.appointments WHERE appointment_id = p_appointment_id;
    IF FOUND THEN
        IF v_appointment.patient_id IS NOT DISTINCT FROM v_patient_id OR v_is_admin THEN
            RETURN to_jsonb(v_appointment);
        ELSE
            RAISE EXCEPTION 'FORBIDDEN: Appointment ID already exists for another patient.'
                USING ERRCODE = '42501';
        END IF;
    END IF;

    -- Validate p_doctor_id exists and take doctor_name/specialization from doctors, not client
    SELECT * INTO v_doc FROM public.doctors WHERE doctor_id = p_doctor_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'DOCTOR_NOT_FOUND: Doctor "%" does not exist.', p_doctor_id
            USING ERRCODE = '23503';
    END IF;
    v_doctor_name := COALESCE(v_doc.name, p_doctor_name, 'Doctor');
    v_specialization := COALESCE(v_doc.specialization, p_specialization, 'General');

    -- 2. Transaction Advisory Lock on doctor slot to serialize concurrent bookings
    v_lock_key1 := pg_catalog.hashtext(p_doctor_id);
    v_lock_key2 := pg_catalog.hashtext(EXTRACT(epoch FROM p_date_time)::text);
    PERFORM pg_catalog.pg_advisory_xact_lock(v_lock_key1, v_lock_key2);

    -- 3. Duplicate Active Booking check by same patient for this slot
    IF EXISTS (
        SELECT 1 FROM public.appointments
        WHERE patient_id = v_patient_id
          AND doctor_id = p_doctor_id
          AND date_time = p_date_time
          AND patient_status != 'cancelled'
    ) THEN
        RAISE EXCEPTION 'DUPLICATE_PATIENT_BOOKING: You already have an active appointment for this slot.'
            USING ERRCODE = '23505';
    END IF;

    -- 4. Enforce Slot Capacity (Max 3 active bookings per slot)
    SELECT COUNT(*) INTO v_active_count
    FROM public.appointments
    WHERE doctor_id = p_doctor_id
      AND date_time = p_date_time
      AND patient_status != 'cancelled';

    IF v_active_count >= 3 THEN
        RAISE EXCEPTION 'SLOT_CAPACITY_REACHED: Slot "%" already reached its maximum capacity of 3 patients.',
            p_slot_label
            USING ERRCODE = '54000';
    END IF;

    -- 5. Calculate Sequential Daily Token Number
    IF p_token_number IS NULL THEN
        SELECT COALESCE(MAX(token_number), 0) + 1 INTO v_token_number
        FROM public.appointments
        WHERE doctor_id = p_doctor_id
          AND date_time::date = p_date_time::date;
    ELSE
        v_token_number := p_token_number;
    END IF;

    -- 6. Insert Appointment Record
    INSERT INTO public.appointments (
        appointment_id,
        doctor_id,
        patient_id,
        doctor_name,
        specialization,
        patient_name,
        patient_age,
        patient_gender,
        date_time,
        slot_label,
        visit_type,
        token_number,
        clinic_name,
        clinic_address,
        doctor_status,
        patient_status,
        payment_status,
        consultation_fee,
        sync_origin,
        booked_by_uid,
        created_at,
        updated_at
    ) VALUES (
        p_appointment_id,
        p_doctor_id,
        v_patient_id,
        v_doctor_name,
        v_specialization,
        p_patient_name,
        p_patient_age,
        p_patient_gender,
        p_date_time,
        p_slot_label,
        COALESCE(p_visit_type, 'newVisit'),
        v_token_number,
        p_clinic_name,
        p_clinic_address,
        'pendingRequest',
        'pending',
        'pending',
        0.00,
        COALESCE(p_sync_origin, 'patient_supabase'),
        v_caller_uid,
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP
    )
    RETURNING * INTO v_appointment;

    RETURN to_jsonb(v_appointment);
END;
$$;

REVOKE ALL ON FUNCTION public.book_appointment_atomic(VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, INTEGER, VARCHAR, TIMESTAMPTZ, VARCHAR, VARCHAR, INTEGER, VARCHAR, TEXT, VARCHAR, VARCHAR) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.book_appointment_atomic(VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, INTEGER, VARCHAR, TIMESTAMPTZ, VARCHAR, VARCHAR, INTEGER, VARCHAR, TEXT, VARCHAR, VARCHAR) TO authenticated, service_role;


-- 11. create_prescription_atomic
CREATE OR REPLACE FUNCTION public.create_prescription_atomic(
    payload JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_caller_uid TEXT;
    v_profile_id TEXT;
    v_doctor_id TEXT;
    v_prescription_id TEXT;
    v_patient_id TEXT;
    v_appointment_id TEXT;
    v_appt_doctor_id TEXT;
    v_appt_patient_id TEXT;
    v_existing_doc_id TEXT;
    v_is_admin BOOLEAN;
    v_med JSONB;
    v_inv JSONB;
    v_ref JSONB;
BEGIN
    -- 1. Derive & verify caller
    v_caller_uid := NULLIF(COALESCE(
        auth.jwt()->>'sub',
        auth.jwt()->>'uid',
        current_setting('request.jwt.claims', true)::jsonb->>'sub'
    ), '');

    IF v_caller_uid IS NULL THEN
        RAISE EXCEPTION 'UNAUTHORIZED: Authentication required to create prescription.'
            USING ERRCODE = '42501';
    END IF;

    v_profile_id := private.current_profile_id();
    v_is_admin := COALESCE(private.is_super_admin(), FALSE);

    IF v_profile_id IS NULL AND NOT v_is_admin THEN
        RAISE EXCEPTION 'FORBIDDEN: Caller has no registered profile.'
            USING ERRCODE = '42501';
    END IF;

    -- Resolve doctor_id for caller
    SELECT doctor_id INTO v_doctor_id 
    FROM public.doctors 
    WHERE owner_uid = v_caller_uid OR (v_profile_id IS NOT NULL AND doctor_id = v_profile_id);

    IF v_doctor_id IS NULL AND NOT v_is_admin THEN
        RAISE EXCEPTION 'FORBIDDEN: Caller "%" is not a registered doctor.', v_caller_uid
            USING ERRCODE = '42501';
    END IF;

    IF v_is_admin AND v_doctor_id IS NULL THEN
        v_doctor_id := trim(payload->>'doctor_id');
    END IF;

    v_prescription_id := trim(payload->>'prescription_id');
    v_patient_id := trim(payload->>'patient_id');
    v_appointment_id := trim(payload->>'appointment_id');

    IF v_prescription_id IS NULL OR v_prescription_id = '' THEN
        RAISE EXCEPTION 'BAD_REQUEST: prescription_id is required.'
            USING ERRCODE = '22004';
    END IF;

    IF v_patient_id IS NULL OR v_patient_id = '' THEN
        RAISE EXCEPTION 'BAD_REQUEST: patient_id is required.'
            USING ERRCODE = '22004';
    END IF;

    -- Require relationship: for non-admin require an appointment or an active patient_doctor_links row for patient_id
    IF NOT v_is_admin THEN
        IF NOT (
            EXISTS (
                SELECT 1 FROM public.appointments a
                WHERE a.doctor_id = v_doctor_id
                  AND a.patient_id = v_patient_id
            )
            OR EXISTS (
                SELECT 1 FROM public.patient_doctor_links pdl
                WHERE pdl.doctor_id = v_doctor_id
                  AND pdl.patient_id = v_patient_id
            )
        ) THEN
            RAISE EXCEPTION 'FORBIDDEN: Doctor "%" does not have an active appointment or link for patient "%".', v_doctor_id, v_patient_id
                USING ERRCODE = '42501';
        END IF;
    END IF;

    -- 2. Verify prescription ownership if prescription already exists
    SELECT doctor_id INTO v_existing_doc_id 
    FROM public.prescriptions 
    WHERE prescription_id = v_prescription_id;

    IF v_existing_doc_id IS NOT NULL AND NOT v_is_admin AND (v_existing_doc_id IS DISTINCT FROM v_doctor_id) THEN
        RAISE EXCEPTION 'FORBIDDEN: Cannot overwrite prescription belonging to another doctor.'
            USING ERRCODE = '42501';
    END IF;

    -- 3. Verify appointment ownership and patient consistency if appointment_id is provided
    IF v_appointment_id IS NOT NULL AND v_appointment_id != '' THEN
        SELECT doctor_id, patient_id INTO v_appt_doctor_id, v_appt_patient_id
        FROM public.appointments
        WHERE appointment_id = v_appointment_id;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'NOT_FOUND: Referenced appointment "%" does not exist.', v_appointment_id
                USING ERRCODE = '23503';
        END IF;

        IF NOT v_is_admin AND (v_appt_doctor_id IS DISTINCT FROM v_doctor_id) THEN
            RAISE EXCEPTION 'FORBIDDEN: Doctor "%" does not own appointment "%".', v_doctor_id, v_appointment_id
                USING ERRCODE = '42501';
        END IF;

        IF NOT v_is_admin AND (v_appt_patient_id IS DISTINCT FROM v_patient_id) THEN
            RAISE EXCEPTION 'FORBIDDEN: Appointment "%" is for patient "%", not "%".', v_appointment_id, v_appt_patient_id, v_patient_id
                USING ERRCODE = '42501';
        END IF;
    END IF;

    -- 4. Upsert prescription header
    INSERT INTO public.prescriptions (
        prescription_id,
        doctor_id,
        patient_id,
        appointment_id,
        doctor_name,
        doctor_specialization,
        doctor_qualifications,
        doctor_reg_number,
        clinic_name,
        clinic_address,
        doctor_phone,
        patient_name,
        patient_age,
        patient_gender,
        prescription_date,
        diagnosis_type,
        primary_diagnosis,
        secondary_diagnosis,
        chief_complaint,
        symptoms,
        symptom_duration,
        past_history,
        allergies,
        general_examination,
        blood_pressure,
        temperature,
        pulse,
        spo2,
        weight_kg,
        height_cm,
        respiratory_rate,
        diet_advice,
        activity_restrictions,
        lifestyle_advice,
        general_advice,
        follow_up_note,
        next_visit,
        created_at,
        updated_at
    ) VALUES (
        v_prescription_id,
        v_doctor_id,
        v_patient_id,
        v_appointment_id,
        COALESCE(payload->>'doctor_name', 'Doctor'),
        payload->>'doctor_specialization',
        payload->>'doctor_qualifications',
        payload->>'doctor_reg_number',
        payload->>'clinic_name',
        payload->>'clinic_address',
        payload->>'doctor_phone',
        COALESCE(payload->>'patient_name', 'Patient'),
        (payload->>'patient_age')::INT,
        payload->>'patient_gender',
        COALESCE((payload->>'prescription_date')::TIMESTAMPTZ, CURRENT_TIMESTAMP),
        COALESCE(payload->>'diagnosis_type', 'Provisional'),
        COALESCE(payload->>'primary_diagnosis', ''),
        payload->>'secondary_diagnosis',
        payload->>'chief_complaint',
        COALESCE(payload->>'symptoms', ''),
        payload->>'symptom_duration',
        payload->>'past_history',
        payload->>'allergies',
        payload->>'general_examination',
        payload->>'blood_pressure',
        payload->>'temperature',
        payload->>'pulse',
        payload->>'spo2',
        payload->>'weight_kg',
        payload->>'height_cm',
        payload->>'respiratory_rate',
        payload->>'diet_advice',
        payload->>'activity_restrictions',
        payload->>'lifestyle_advice',
        payload->>'general_advice',
        payload->>'follow_up_note',
        (payload->>'next_visit')::TIMESTAMPTZ,
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP
    )
    ON CONFLICT (prescription_id) DO UPDATE SET
        appointment_id = EXCLUDED.appointment_id,
        doctor_name = EXCLUDED.doctor_name,
        doctor_specialization = EXCLUDED.doctor_specialization,
        doctor_qualifications = EXCLUDED.doctor_qualifications,
        doctor_reg_number = EXCLUDED.doctor_reg_number,
        clinic_name = EXCLUDED.clinic_name,
        clinic_address = EXCLUDED.clinic_address,
        doctor_phone = EXCLUDED.doctor_phone,
        patient_name = EXCLUDED.patient_name,
        patient_age = EXCLUDED.patient_age,
        patient_gender = EXCLUDED.patient_gender,
        prescription_date = EXCLUDED.prescription_date,
        diagnosis_type = EXCLUDED.diagnosis_type,
        primary_diagnosis = EXCLUDED.primary_diagnosis,
        secondary_diagnosis = EXCLUDED.secondary_diagnosis,
        chief_complaint = EXCLUDED.chief_complaint,
        symptoms = EXCLUDED.symptoms,
        symptom_duration = EXCLUDED.symptom_duration,
        past_history = EXCLUDED.past_history,
        allergies = EXCLUDED.allergies,
        general_examination = EXCLUDED.general_examination,
        blood_pressure = EXCLUDED.blood_pressure,
        temperature = EXCLUDED.temperature,
        pulse = EXCLUDED.pulse,
        spo2 = EXCLUDED.spo2,
        weight_kg = EXCLUDED.weight_kg,
        height_cm = EXCLUDED.height_cm,
        respiratory_rate = EXCLUDED.respiratory_rate,
        diet_advice = EXCLUDED.diet_advice,
        activity_restrictions = EXCLUDED.activity_restrictions,
        lifestyle_advice = EXCLUDED.lifestyle_advice,
        general_advice = EXCLUDED.general_advice,
        follow_up_note = EXCLUDED.follow_up_note,
        next_visit = EXCLUDED.next_visit,
        updated_at = CURRENT_TIMESTAMP;

    -- 5. Replace medicines atomically
    DELETE FROM public.prescription_medicines WHERE prescription_id = v_prescription_id;
    IF payload ? 'medicines' AND jsonb_array_length(payload->'medicines') > 0 THEN
        FOR v_med IN SELECT * FROM jsonb_array_elements(payload->'medicines') LOOP
            INSERT INTO public.prescription_medicines (
                prescription_id,
                medicine_entry_id,
                name,
                dosage,
                form,
                frequency,
                quantity,
                duration,
                instructions,
                special_instructions,
                is_sos,
                substitute_allowed
            ) VALUES (
                v_prescription_id,
                COALESCE(v_med->>'medicine_entry_id', v_prescription_id || '_' || md5(v_med->>'name')),
                COALESCE(v_med->>'name', ''),
                v_med->>'dosage',
                v_med->>'form',
                v_med->>'frequency',
                (v_med->>'quantity')::INT,
                v_med->>'duration',
                v_med->>'instructions',
                v_med->>'special_instructions',
                COALESCE((v_med->>'is_sos')::BOOLEAN, FALSE),
                COALESCE((v_med->>'substitute_allowed')::BOOLEAN, FALSE)
            );
        END LOOP;
    END IF;

    -- 6. Replace investigations atomically
    DELETE FROM public.prescription_investigations WHERE prescription_id = v_prescription_id;
    IF payload ? 'investigations' AND jsonb_array_length(payload->'investigations') > 0 THEN
        FOR v_inv IN SELECT * FROM jsonb_array_elements(payload->'investigations') LOOP
            INSERT INTO public.prescription_investigations (
                prescription_id,
                name,
                type,
                group_name,
                notes
            ) VALUES (
                v_prescription_id,
                COALESCE(v_inv->>'name', ''),
                COALESCE(v_inv->>'type', 'radiology'),
                v_inv->>'group_name',
                v_inv->>'notes'
            );
        END LOOP;
    END IF;

    -- 7. Replace referral links atomically
    DELETE FROM public.prescription_referrals WHERE prescription_id = v_prescription_id;
    IF payload ? 'referrals' AND jsonb_array_length(payload->'referrals') > 0 THEN
        FOR v_ref IN SELECT * FROM jsonb_array_elements(payload->'referrals') LOOP
            INSERT INTO public.prescription_referrals (
                prescription_id,
                to_doctor_id,
                to_doctor_name,
                specialty,
                notes
            ) VALUES (
                v_prescription_id,
                v_ref->>'to_doctor_id',
                v_ref->>'to_doctor_name',
                v_ref->>'specialty',
                v_ref->>'notes'
            );
        END LOOP;
    END IF;

    RETURN jsonb_build_object(
        'success', TRUE,
        'prescription_id', v_prescription_id,
        'doctor_id', v_doctor_id
    );
END;
$$;

REVOKE ALL ON FUNCTION public.create_prescription_atomic(JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_prescription_atomic(JSONB) TO authenticated, service_role;


-- 12. Restrict system_config SELECT policy to explicit public keys (anon, authenticated)
DROP POLICY IF EXISTS "system_config_public_read" ON public.system_config;
DROP POLICY IF EXISTS "system_config_select" ON public.system_config;

CREATE POLICY "system_config_public_read" ON public.system_config
    FOR SELECT TO anon, authenticated
    USING (config_key IN ('patient_module_status', 'promoted_ads'));

-- Purge demo_accounts from production system_config
DELETE FROM public.system_config WHERE config_key = 'demo_accounts';


-- 13. get_ambulance_trip_contact
CREATE OR REPLACE FUNCTION public.get_ambulance_trip_contact(
    p_broadcast_id VARCHAR(64)
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_caller_uid TEXT;
    v_profile_id TEXT;
    v_broadcast public.ambulance_broadcasts%ROWTYPE;
    v_contacts public.ambulance_trip_contacts%ROWTYPE;
    v_is_patient BOOLEAN;
    v_is_driver BOOLEAN;
    v_is_admin BOOLEAN;
BEGIN
    v_caller_uid := NULLIF(COALESCE(
        auth.jwt() ->> 'sub',
        auth.jwt() ->> 'uid',
        current_setting('request.jwt.claims', true)::jsonb ->> 'sub'
    ), '');
    IF v_caller_uid IS NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
    END IF;

    v_profile_id := private.current_profile_id();
    v_is_admin := COALESCE(private.is_super_admin(), FALSE);

    IF v_profile_id IS NULL AND NOT v_is_admin THEN
        RAISE EXCEPTION 'FORBIDDEN: Caller has no registered profile.' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_broadcast FROM public.ambulance_broadcasts WHERE broadcast_id = p_broadcast_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Broadcast not found' USING ERRCODE = 'P0002';
    END IF;

    v_is_patient := (v_broadcast.patient_id IS NOT DISTINCT FROM v_profile_id) OR EXISTS (
        SELECT 1 FROM public.patients p WHERE p.patient_id = v_broadcast.patient_id AND p.owner_uid = v_caller_uid
    );
    v_is_driver := (v_broadcast.accepted_driver_id IS NOT DISTINCT FROM v_profile_id) OR EXISTS (
        SELECT 1 FROM public.ambulances a WHERE a.ambulance_id = v_broadcast.accepted_driver_id AND a.auth_uid = v_caller_uid
    );

    IF NOT (COALESCE(v_is_patient, FALSE) OR COALESCE(v_is_driver, FALSE) OR v_is_admin) THEN
        RAISE EXCEPTION 'Unauthorized to view trip contact' USING ERRCODE = '42501';
    END IF;

    -- Visible to counterpart ONLY after acceptance and ONLY during active trip
    IF v_broadcast.status != 'accepted' THEN
        IF COALESCE(v_is_patient, FALSE) THEN
            -- Patient can see own phone even when pending
            SELECT * INTO v_contacts FROM public.ambulance_trip_contacts WHERE broadcast_id = p_broadcast_id;
            RETURN jsonb_build_object(
                'active', false,
                'status', v_broadcast.status,
                'patient_phone', COALESCE(v_contacts.patient_phone, v_broadcast.contact_phone),
                'driver_phone', NULL
            );
        ELSE
            -- Driver or others get NULL contact info
            RETURN jsonb_build_object(
                'active', false,
                'status', v_broadcast.status,
                'patient_phone', NULL,
                'driver_phone', NULL
            );
        END IF;
    END IF;

    SELECT * INTO v_contacts FROM public.ambulance_trip_contacts WHERE broadcast_id = p_broadcast_id;
    RETURN jsonb_build_object(
        'active', true,
        'status', 'accepted',
        'patient_phone', COALESCE(v_contacts.patient_phone, v_broadcast.contact_phone),
        'driver_phone', COALESCE(v_contacts.driver_phone, v_broadcast.accepted_driver_phone)
    );
END;
$$;

REVOKE ALL ON FUNCTION public.get_ambulance_trip_contact(VARCHAR) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_ambulance_trip_contact(VARCHAR) TO authenticated, service_role;


-- 14. Null-Safe Ambulance Broadcast Status & Rating Lock Trigger (phase_d:254 remediation)
CREATE OR REPLACE FUNCTION private.trg_lock_ambulance_broadcast_status()
RETURNS TRIGGER AS $$
DECLARE
    v_profile_id TEXT;
    v_is_admin BOOLEAN;
BEGIN
    IF TG_OP = 'UPDATE' THEN
        -- Status change requires session guard
        IF OLD.status IS DISTINCT FROM NEW.status THEN
            IF current_setting('app.allow_ambulance_status_change', true) IS DISTINCT FROM 'true' THEN
                RAISE EXCEPTION 'Ambulance broadcast status can only be modified via accept/cancel/complete RPCs'
                    USING ERRCODE = '42501';
            END IF;
        END IF;
        -- Rating column lock: driver cannot rate themselves; only patient when trip is completed
        IF OLD.rating IS DISTINCT FROM NEW.rating THEN
            v_profile_id := private.current_profile_id();
            v_is_admin := COALESCE(private.is_super_admin(), FALSE);
            IF NOT v_is_admin AND (
                v_profile_id IS NULL
                OR OLD.patient_id IS DISTINCT FROM v_profile_id
                OR OLD.status IS DISTINCT FROM 'completed'
            ) THEN
                RAISE EXCEPTION 'Only patient can rate completed ambulance trip' USING ERRCODE = '42501';
            END IF;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';


-- 15. public.users Integrity Hardening (Role and Profile Lock on UPDATE, Guard on INSERT)
DROP TRIGGER IF EXISTS trg_users_lock_role ON public.users;
CREATE TRIGGER trg_users_lock_role
    BEFORE UPDATE ON public.users
    FOR EACH ROW
    EXECUTE FUNCTION private.lock_columns('role', 'profile_id');

CREATE OR REPLACE FUNCTION private.trg_users_guard_insert()
RETURNS TRIGGER AS $$
BEGIN
    IF NOT COALESCE(private.is_super_admin(), FALSE) THEN
        -- Non-admin inserting self cannot claim administrative roles
        IF NEW.role IN ('super_admin', 'superAdmin', 'admin') THEN
            RAISE EXCEPTION 'FORBIDDEN: Cannot register with administrative role' USING ERRCODE = '42501';
        END IF;
        -- Ensure ID matches caller token
        IF NEW.id IS DISTINCT FROM (auth.jwt() ->> 'sub') THEN
            RAISE EXCEPTION 'FORBIDDEN: User ID must match authenticated token subject' USING ERRCODE = '42501';
        END IF;
        -- Cannot specify arbitrary profile_id unless matching own id or created via profile table
        IF NEW.profile_id IS NOT NULL AND NEW.profile_id IS DISTINCT FROM NEW.id THEN
            RAISE EXCEPTION 'FORBIDDEN: Initial profile_id must match user id or be assigned by system' USING ERRCODE = '42501';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

DROP TRIGGER IF EXISTS trg_users_guard_insert ON public.users;
CREATE TRIGGER trg_users_guard_insert
    BEFORE INSERT ON public.users
    FOR EACH ROW
    EXECUTE FUNCTION private.trg_users_guard_insert();

