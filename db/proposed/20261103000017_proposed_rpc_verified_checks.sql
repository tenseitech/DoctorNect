-- PROPOSED (do not apply): verified-provider guards on SECURITY DEFINER mutator RPCs.
-- Depends on private.is_verified_* helpers in db/proposed/20261103000014_proposed_role_verified_rls_hardening.sql
-- and lab report key rules in db/proposed/20261103000015_proposed_lab_report_storage_key.sql (column adds).
-- Ambulance mutators moved to db/proposed/later/20261103000017_later_rpc_ambulance_verified.sql


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

    IF (v_appt.doctor_id IS NOT DISTINCT FROM v_profile_id)
       AND COALESCE(lower(p_rescheduled_by), '') LIKE 'doctor%'
       AND NOT v_is_admin
       AND NOT COALESCE(private.is_verified_doctor(), FALSE) THEN
        RAISE EXCEPTION 'FORBIDDEN: Verified doctor required' USING ERRCODE = '42501';
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

    -- 4. Construct new target timestamp (+05:30)
    v_new_timestamp := (p_new_date::text || ' 10:00:00+05:30')::TIMESTAMPTZ;

    -- 5. Atomically update the appointment
    UPDATE public.appointments
    SET date_time = v_new_timestamp,
        slot_label = p_new_slot,
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
        'slot_label', p_new_slot
    );
END;
$$;
R


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
        IF NOT COALESCE(private.is_verified_medical_store(), FALSE) AND NOT v_is_admin THEN
            RAISE EXCEPTION 'FORBIDDEN: Verified medical store required' USING ERRCODE = '42501';
        END IF;
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
            availability VARCHAR(32),
            substitute_name VARCHAR(255)
        ) LOOP
            UPDATE public.pharmacy_delivery_medicines
            SET availability = COALESCE(v_line.availability, availability),
                substitute_name = COALESCE(v_line.substitute_name, substitute_name)
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
R


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

    IF NOT v_is_admin AND NOT COALESCE(private.is_verified_doctor(), FALSE) THEN
        RAISE EXCEPTION 'FORBIDDEN: Verified doctor required' USING ERRCODE = '42501';
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
                doctor_name,
                specialization,
                reason
            ) VALUES (
                v_prescription_id,
                v_ref->>'to_doctor_id',
                COALESCE(v_ref->>'doctor_name', v_ref->>'to_doctor_name', ''),
                COALESCE(v_ref->>'specialization', v_ref->>'specialty', ''),
                COALESCE(v_ref->>'reason', v_ref->>'notes')
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
R


CREATE OR REPLACE FUNCTION public.update_lab_booking_status(
    p_booking_id VARCHAR(64),
    p_new_status VARCHAR(32),
    p_notes TEXT DEFAULT NULL,
    p_report_storage_key TEXT DEFAULT NULL
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
    v_key TEXT;
    v_expected_prefix TEXT;
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

    v_key := NULLIF(trim(both from p_report_storage_key), '');
    IF v_key IS NOT NULL AND p_new_status IS DISTINCT FROM 'completed' THEN
        RAISE EXCEPTION 'report_storage_key only allowed when p_new_status is completed' USING ERRCODE = '22023';
    END IF;
    IF v_key IS NOT NULL THEN
        IF COALESCE(v_is_patient, FALSE) AND NOT v_is_admin THEN
            RAISE EXCEPTION 'Patients cannot set report storage key' USING ERRCODE = '42501';
        END IF;
        IF NOT (COALESCE(v_is_lab, FALSE) OR v_is_admin) THEN
            RAISE EXCEPTION 'Only the assigned lab or an admin may set report storage key' USING ERRCODE = '42501';
        END IF;
        v_expected_prefix := 'lab_reports/' || v_booking.patient_id || '/' || p_booking_id || '/';
        IF NOT starts_with(v_key, v_expected_prefix)
            OR position('..' IN v_key) > 0
            OR position(E'\\' IN v_key) > 0
            OR v_key ~ '[[:cntrl:]]'
        THEN
            RAISE EXCEPTION 'Invalid report_storage_key prefix for booking %', p_booking_id USING ERRCODE = '22023';
        END IF;
    END IF;

    IF v_is_patient AND NOT v_is_admin THEN
        IF p_new_status != 'cancelled' THEN
            RAISE EXCEPTION 'Patients can only cancel lab bookings' USING ERRCODE = '42501';
        END IF;
        IF v_booking.status IS DISTINCT FROM 'confirmed' THEN
            RAISE EXCEPTION 'Patient cannot cancel after sample collection (status: %)', v_booking.status
                USING ERRCODE = '42501';
        END IF;
        IF v_key IS NOT NULL THEN
            RAISE EXCEPTION 'Patients cannot set report storage key' USING ERRCODE = '42501';
        END IF;
    ELSIF v_is_lab THEN
        IF NOT COALESCE(private.is_verified_lab(), FALSE) AND NOT v_is_admin THEN
            RAISE EXCEPTION 'FORBIDDEN: Verified lab required' USING ERRCODE = '42501';
        END IF;
        IF v_booking.status = 'confirmed' AND p_new_status NOT IN ('sampleCollected', 'cancelled') THEN
            RAISE EXCEPTION 'Invalid transition from confirmed to %', p_new_status USING ERRCODE = '22023';
        ELSIF v_booking.status = 'sampleCollected' AND p_new_status NOT IN ('inAnalysis') THEN
            RAISE EXCEPTION 'Invalid transition from sampleCollected to %', p_new_status USING ERRCODE = '22023';
        ELSIF v_booking.status = 'inAnalysis' AND p_new_status NOT IN ('completed') THEN
            RAISE EXCEPTION 'Invalid transition from inAnalysis to %', p_new_status USING ERRCODE = '22023';
        ELSIF v_booking.status = 'cancelled' THEN
            RAISE EXCEPTION 'Booking is already in terminal state: %', v_booking.status USING ERRCODE = '22023';
        ELSIF v_booking.status = 'completed' THEN
            IF p_new_status <> 'completed' OR v_key IS NULL THEN
                RAISE EXCEPTION 'Completed booking only allows completed status with a new report_storage_key' USING ERRCODE = '22023';
            END IF;
        END IF;
    END IF;

    PERFORM set_config('app.allow_lab_status_change', 'true', true);

    UPDATE public.lab_bookings
    SET status = p_new_status,
        notes = CASE
            WHEN p_notes IS NOT NULL AND (p_notes !~ '^lab_reports/') THEN p_notes
            ELSE notes
        END,
        report_storage_key = COALESCE(v_key, report_storage_key),
        report_s3_key = COALESCE(v_key, report_s3_key),
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
CREATE OR REPLACE FUNCTION public.update_lab_order_status(
    p_order_id VARCHAR(64),
    p_new_status VARCHAR(32),
    p_notes TEXT DEFAULT NULL,
    p_report_storage_key TEXT DEFAULT NULL
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
    v_key TEXT;
    v_patient_id TEXT;
    v_expected_prefix TEXT;
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

    v_key := NULLIF(trim(both from p_report_storage_key), '');
    v_patient_id := v_order.patient_id;
    IF v_key IS NOT NULL AND p_new_status IS DISTINCT FROM 'completed' THEN
        RAISE EXCEPTION 'report_storage_key only allowed when p_new_status is completed' USING ERRCODE = '22023';
    END IF;
    IF v_key IS NOT NULL THEN
        IF NOT (COALESCE(v_is_lab, FALSE) OR v_is_admin) THEN
            RAISE EXCEPTION 'Only the assigned lab or an admin may set report storage key' USING ERRCODE = '42501';
        END IF;
        IF v_patient_id IS NULL OR v_patient_id = '' THEN
            RAISE EXCEPTION 'Lab order has no patient_id for report key validation' USING ERRCODE = '22023';
        END IF;
        v_expected_prefix := 'lab_reports/' || v_patient_id || '/' || p_order_id || '/';
        IF NOT starts_with(v_key, v_expected_prefix)
            OR position('..' IN v_key) > 0
            OR position(E'\\' IN v_key) > 0
            OR v_key ~ '[[:cntrl:]]'
        THEN
            RAISE EXCEPTION 'Invalid report_storage_key prefix for order %', p_order_id USING ERRCODE = '22023';
        END IF;
    END IF;

    IF v_is_doctor AND NOT v_is_admin THEN
        IF p_new_status != 'cancelled' THEN
            RAISE EXCEPTION 'Doctor can only cancel lab order' USING ERRCODE = '42501';
        END IF;
        IF v_order.status IN ('inProgress', 'completed') THEN
            RAISE EXCEPTION 'Cannot cancel order after lab processing has begun (status: %)', v_order.status
                USING ERRCODE = '42501';
        END IF;
        IF v_key IS NOT NULL THEN
            RAISE EXCEPTION 'Doctors cannot set report storage key' USING ERRCODE = '42501';
        END IF;
    ELSIF v_is_lab THEN
        IF NOT COALESCE(private.is_verified_lab(), FALSE) AND NOT v_is_admin THEN
            RAISE EXCEPTION 'FORBIDDEN: Verified lab required' USING ERRCODE = '42501';
        END IF;
        IF v_order.status = 'ordered' AND p_new_status NOT IN ('received', 'cancelled') THEN
            RAISE EXCEPTION 'Invalid transition from ordered to %', p_new_status USING ERRCODE = '22023';
        ELSIF v_order.status = 'received' AND p_new_status NOT IN ('inProgress') THEN
            RAISE EXCEPTION 'Invalid transition from received to %', p_new_status USING ERRCODE = '22023';
        ELSIF v_order.status = 'inProgress' AND p_new_status NOT IN ('completed') THEN
            RAISE EXCEPTION 'Invalid transition from inProgress to %', p_new_status USING ERRCODE = '22023';
        ELSIF v_order.status = 'cancelled' THEN
            RAISE EXCEPTION 'Order is in terminal state: %', v_order.status USING ERRCODE = '22023';
        ELSIF v_order.status = 'completed' THEN
            IF p_new_status <> 'completed' OR v_key IS NULL THEN
                RAISE EXCEPTION 'Completed order only allows completed status with a new report_storage_key' USING ERRCODE = '22023';
            END IF;
        END IF;
    END IF;

    PERFORM set_config('app.allow_lab_status_change', 'true', true);

    UPDATE public.lab_orders
    SET status = p_new_status,
        notes = CASE
            WHEN p_notes IS NOT NULL AND (p_notes !~ '^lab_reports/') THEN p_notes
            ELSE notes
        END,
        report_storage_key = COALESCE(v_key, report_storage_key),
        report_s3_key = COALESCE(v_key, report_s3_key),
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

REVOKE ALL ON FUNCTION public.update_lab_booking_status(VARCHAR, VARCHAR, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_lab_booking_status(VARCHAR, VARCHAR, TEXT, TEXT) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.update_lab_order_status(VARCHAR, VARCHAR, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_lab_order_status(VARCHAR, VARCHAR, TEXT, TEXT) TO authenticated, service_role;
