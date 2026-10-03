-- ============================================================================
-- DoctorNect Migration: Atomic Appointment Booking RPC (Concurrency Guard)
-- File: 20260926000001_atomic_appointment_booking.sql
-- ============================================================================
-- Purpose:
-- 1. Eliminates race conditions in multi-patient slot sharing by acquiring a
--    PostgreSQL transaction-level advisory lock on (doctor_id, date_time).
-- 2. Enforces the strict hard capacity limit: max 3 active non-cancelled
--    patients per doctor time slot (kMaxPatientsPerTimeSlot = 3).
-- 3. Provides defense-in-depth against same-patient duplicate bookings.
-- 4. Computes next incremental token number safely under lock.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.book_appointment_atomic(
    p_appointment_id VARCHAR(64),
    p_doctor_id VARCHAR(64),
    p_patient_id VARCHAR(64),
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
    p_sync_origin VARCHAR(32) DEFAULT 'patient_supabase'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_active_count INTEGER;
    v_token_number INTEGER;
    v_appointment RECORD;
    v_lock_key1 INTEGER;
    v_lock_key2 INTEGER;
BEGIN
    -- 1. Caller Authorization Check (defense-in-depth)
    IF auth.role() = 'authenticated' AND NOT is_super_admin() THEN
        IF p_patient_id != current_profile_id() THEN
            RAISE EXCEPTION 'FORBIDDEN: Cannot book appointment for another patient profile (Caller: %, Requested: %).',
                current_profile_id(), p_patient_id
                USING ERRCODE = '42501';
        END IF;
    END IF;

    -- 2. Acquire Transaction-Level Advisory Lock on (doctor_id, date_time)
    -- Two 32-bit integer hashes serialize concurrent booking requests for this exact slot
    v_lock_key1 := hashtext(p_doctor_id);
    v_lock_key2 := hashtext(p_date_time::text);
    PERFORM pg_advisory_xact_lock(v_lock_key1, v_lock_key2);

    -- 3. Check for Duplicate Active Booking by the Same Patient
    IF EXISTS (
        SELECT 1 FROM public.appointments
        WHERE patient_id = p_patient_id
          AND doctor_id = p_doctor_id
          AND date_time = p_date_time
          AND patient_status != 'cancelled'
    ) THEN
        RAISE EXCEPTION 'DUPLICATE_PATIENT_BOOKING: Patient % already has an active booking for this slot.', p_patient_id
            USING ERRCODE = '23505';
    END IF;

    -- 4. Enforce Hard Slot Capacity (Max 3 Patients per Doctor Slot)
    SELECT COUNT(*) INTO v_active_count
    FROM public.appointments
    WHERE doctor_id = p_doctor_id
      AND date_time = p_date_time
      AND patient_status != 'cancelled';

    IF v_active_count >= 3 THEN
        RAISE EXCEPTION 'SLOT_CAPACITY_REACHED: Slot "%" for doctor "%" already has % active bookings (maximum capacity is 3).',
            p_slot_label, p_doctor_name, v_active_count
            USING ERRCODE = 'P0001';
    END IF;

    -- 5. Calculate Sequential Daily Token Number (if not supplied)
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
        patient_status,
        doctor_status,
        token_number,
        clinic_name,
        clinic_address,
        sync_origin,
        created_at,
        updated_at
    ) VALUES (
        p_appointment_id,
        p_doctor_id,
        p_patient_id,
        p_doctor_name,
        p_specialization,
        p_patient_name,
        p_patient_age,
        p_patient_gender,
        p_date_time,
        p_slot_label,
        COALESCE(p_visit_type, 'newVisit'),
        'confirmed',
        'pendingRequest',
        v_token_number,
        p_clinic_name,
        p_clinic_address,
        COALESCE(p_sync_origin, 'patient_supabase'),
        NOW(),
        NOW()
    )
    RETURNING * INTO v_appointment;

    RETURN to_jsonb(v_appointment);
END;
$$;

-- Grant execution permissions
GRANT EXECUTE ON FUNCTION public.book_appointment_atomic TO authenticated;
GRANT EXECUTE ON FUNCTION public.book_appointment_atomic TO service_role;

COMMENT ON FUNCTION public.book_appointment_atomic IS
'Atomically locks slot (doctor_id, date_time), enforces max 3 patients capacity, prevents same-patient duplicate, and creates appointment record.';
