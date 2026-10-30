-- ============================================================================
-- Migration: 20261022000001_phase_f_complete_cutover.sql
-- Description: Phase F complete cutover migration
-- 1. user_devices RLS policies and register_device_token RPC
-- 2. doctor_invites and pharmacy_doctor_invites tables
-- 3. system_config table for app configuration and ad banners
-- 4. reschedule_appointment_atomic RPC
-- 5. Drop obsolete Supabase Auth & SQL rate limit procedures
-- 6. Default UUIDs for community tables
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. USER_DEVICES RLS POLICIES & RPC
-- ----------------------------------------------------------------------------
GRANT INSERT, UPDATE, DELETE ON public.user_devices TO authenticated;

DROP POLICY IF EXISTS "user_devices_owner_insert" ON public.user_devices;
CREATE POLICY "user_devices_owner_insert" ON public.user_devices
    FOR INSERT TO authenticated
    WITH CHECK (user_id = (auth.jwt() ->> 'sub'));

DROP POLICY IF EXISTS "user_devices_owner_update" ON public.user_devices;
CREATE POLICY "user_devices_owner_update" ON public.user_devices
    FOR UPDATE TO authenticated
    USING (user_id = (auth.jwt() ->> 'sub'))
    WITH CHECK (user_id = (auth.jwt() ->> 'sub'));

DROP POLICY IF EXISTS "user_devices_owner_delete" ON public.user_devices;
CREATE POLICY "user_devices_owner_delete" ON public.user_devices
    FOR DELETE TO authenticated
    USING (user_id = (auth.jwt() ->> 'sub'));

CREATE OR REPLACE FUNCTION public.register_device_token(
    p_platform TEXT,
    p_fcm_token TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_uid TEXT := (auth.jwt() ->> 'sub');
BEGIN
    IF v_uid IS NULL OR v_uid = '' THEN
        RAISE EXCEPTION 'Unauthenticated';
    END IF;

    INSERT INTO public.user_devices (user_id, platform, fcm_token, updated_at)
    VALUES (v_uid, COALESCE(p_platform, 'unknown'), p_fcm_token, CURRENT_TIMESTAMP)
    ON CONFLICT (user_id, platform)
    DO UPDATE SET fcm_token = EXCLUDED.fcm_token, updated_at = CURRENT_TIMESTAMP;
END;
$$;

REVOKE ALL ON FUNCTION public.register_device_token(TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.register_device_token(TEXT, TEXT) TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 2. DOCTOR_INVITES & PHARMACY_DOCTOR_INVITES
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.doctor_invites (
    invite_id VARCHAR(64) PRIMARY KEY,
    doctor_id VARCHAR(64) NOT NULL REFERENCES public.doctors(doctor_id) ON DELETE CASCADE,
    target_role VARCHAR(32) NOT NULL DEFAULT 'patient',
    invite_link TEXT NOT NULL,
    status VARCHAR(32) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'completed', 'cancelled')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE public.doctor_invites ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.doctor_invites TO service_role;
GRANT SELECT ON public.doctor_invites TO authenticated;

DROP POLICY IF EXISTS "doctor_invites_doctor_read" ON public.doctor_invites;
CREATE POLICY "doctor_invites_doctor_read" ON public.doctor_invites
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.doctors d
            WHERE d.doctor_id = doctor_invites.doctor_id
              AND d.owner_uid = (auth.jwt() ->> 'sub')
        )
    );

CREATE TABLE IF NOT EXISTS public.pharmacy_doctor_invites (
    invite_id VARCHAR(64) PRIMARY KEY,
    store_id VARCHAR(64) NOT NULL REFERENCES public.medical_stores(store_id) ON DELETE CASCADE,
    doctor_id VARCHAR(64),
    invite_link TEXT NOT NULL,
    status VARCHAR(32) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'completed', 'cancelled')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE public.pharmacy_doctor_invites ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.pharmacy_doctor_invites TO service_role;
GRANT SELECT ON public.pharmacy_doctor_invites TO authenticated;

DROP POLICY IF EXISTS "pharmacy_invites_store_read" ON public.pharmacy_doctor_invites;
CREATE POLICY "pharmacy_invites_store_read" ON public.pharmacy_doctor_invites
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.medical_stores s
            WHERE s.store_id = pharmacy_doctor_invites.store_id
              AND s.owner_uid = (auth.jwt() ->> 'sub')
        )
    );

-- ----------------------------------------------------------------------------
-- 3. SYSTEM_CONFIG (APP CONFIG & PROMOTED ADS BANNER CONFIG)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.system_config (
    config_key VARCHAR(64) PRIMARY KEY,
    config_value JSONB NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE public.system_config ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.system_config TO authenticated, anon;
GRANT ALL ON public.system_config TO service_role;

DROP POLICY IF EXISTS "system_config_public_read" ON public.system_config;
CREATE POLICY "system_config_public_read" ON public.system_config
    FOR SELECT TO public
    USING (TRUE);

-- Seed default promoted_ads system configuration
ALTER TABLE public.system_config NO FORCE ROW LEVEL SECURITY;
INSERT INTO public.system_config (config_key, config_value)
VALUES (
    'promoted_ads',
    jsonb_build_object(
        'enabled', true,
        'price_per_day', 300,
        'max_active_banners', 10,
        'pricing_tiers', jsonb_build_object(
            '24', 300,
            '72', 750,
            '168', 1500,
            '720', 5000
        )
    )
)
ON CONFLICT (config_key) DO UPDATE
SET config_value = EXCLUDED.config_value;
ALTER TABLE public.system_config FORCE ROW LEVEL SECURITY;

-- ----------------------------------------------------------------------------
-- 4. RESCHEDULE_APPOINTMENT_ATOMIC RPC
-- ----------------------------------------------------------------------------
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
BEGIN
    -- 1. Lock appointment row
    SELECT * INTO v_appt
    FROM public.appointments
    WHERE appointment_id = p_appointment_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'APPOINTMENT_NOT_FOUND';
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
        RAISE EXCEPTION 'SLOT_CAPACITY_REACHED';
    END IF;

    -- 3. Calculate sequential queue token for target date
    SELECT COALESCE(MAX(token_number), 0) + 1 INTO v_token
    FROM public.appointments
    WHERE doctor_id = v_appt.doctor_id
      AND date_time::date = p_new_date;

    v_new_timestamp := (p_new_date::text || ' 10:00:00+05:30')::timestamptz;

    -- 4. Update appointment
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

REVOKE ALL ON FUNCTION public.reschedule_appointment_atomic(VARCHAR, VARCHAR, DATE, VARCHAR, VARCHAR, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.reschedule_appointment_atomic(VARCHAR, VARCHAR, DATE, VARCHAR, VARCHAR, TEXT) TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 5. DROP UNUSED AUTH & RATE LIMITING PROCEDURES
-- ----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS private.on_auth_user_created();
DROP FUNCTION IF EXISTS public.find_auth_user(TEXT);
DROP FUNCTION IF EXISTS public.find_auth_user(TEXT, TEXT);
DROP FUNCTION IF EXISTS public.consume_otp_attempt(TEXT);
DROP FUNCTION IF EXISTS public.check_and_increment_rate_limit(TEXT, INT, INT, TEXT);

-- ----------------------------------------------------------------------------
-- 6. DEFAULT UUIDs FOR COMMUNITY TABLES
-- ----------------------------------------------------------------------------
ALTER TABLE IF EXISTS public.community_medicines ALTER COLUMN id SET DEFAULT gen_random_uuid()::text;
ALTER TABLE IF EXISTS public.community_diagnoses ALTER COLUMN id SET DEFAULT gen_random_uuid()::text;
ALTER TABLE IF EXISTS public.community_lab_tests ALTER COLUMN id SET DEFAULT gen_random_uuid()::text;
ALTER TABLE IF EXISTS public.community_radiology ALTER COLUMN id SET DEFAULT gen_random_uuid()::text;
ALTER TABLE IF EXISTS public.community_body_parts ALTER COLUMN id SET DEFAULT gen_random_uuid()::text;
