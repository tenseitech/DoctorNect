-- ============================================================================
-- Migration: 20261021000002_phase_d_pharmacy_lab_ambulance.sql
-- Description: Phase D - Hardened Schema, RLS, and RPCs for Pharmacy, Lab, Ambulance
--   1. Column additions & constraints (lab_orders report columns, pharmacy status check)
--   2. Atomic ambulance live tracking tables (ambulance_locations, ambulance_location_updates)
--   3. Ambulance trip contacts privacy store & safe contact RPC (active-trip only)
--   4. Drop duplicate legacy policies & harden prescription cross-store isolation
--   5. Strict status column-locks (status transitions ONLY via RPC)
--   6. Validated state-machine RPCs (pharmacy delivery, lab booking, lab order)
--   7. Atomic race-safe accept_ambulance_request RPC (FOR UPDATE lock, siblings marked taken)
--   8. Ambulance privacy & location refetch RPC (location + counterpart contact only during active trip)
--   9. Automated lab report auto-linking to patient health_records
--   10. pg_cron automated expiration of stale pending ambulance broadcasts
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. SCHEMA EXTENSIONS & MISSING COLUMNS
-- ----------------------------------------------------------------------------

-- Add S3 report metadata columns to lab_orders if missing
ALTER TABLE public.lab_orders ADD COLUMN IF NOT EXISTS report_s3_key TEXT;
ALTER TABLE public.lab_orders ADD COLUMN IF NOT EXISTS report_s3_bucket TEXT;
ALTER TABLE public.lab_orders ADD COLUMN IF NOT EXISTS report_file_size_bytes BIGINT;
ALTER TABLE public.lab_orders ADD COLUMN IF NOT EXISTS report_mime_type VARCHAR(128);
ALTER TABLE public.lab_orders ADD COLUMN IF NOT EXISTS report_uploaded_at TIMESTAMPTZ;

-- Expand pharmacy_deliveries status check constraint to include processing, dispatched, delivered, cancelled
ALTER TABLE public.pharmacy_deliveries DROP CONSTRAINT IF EXISTS pharmacy_deliveries_status_check;
ALTER TABLE public.pharmacy_deliveries ADD CONSTRAINT pharmacy_deliveries_status_check
  CHECK (status::text = ANY (ARRAY[
    'sent'::character varying,
    'viewed'::character varying,
    'processing'::character varying,
    'dispatched'::character varying,
    'delivered'::character varying,
    'partiallyDispensed'::character varying,
    'dispensed'::character varying,
    'cancelled'::character varying
  ]::text[]));

-- Allow null contact phone on broadcasts/requests for privacy isolation
ALTER TABLE public.ambulance_broadcasts ALTER COLUMN contact_phone DROP NOT NULL;
ALTER TABLE public.ambulance_requests ALTER COLUMN contact_phone DROP NOT NULL;

-- ----------------------------------------------------------------------------
-- 2. AMBULANCE LIVE LOCATION & CHANGE-SIGNAL TABLES
-- ----------------------------------------------------------------------------

-- Private location storage (coordinates visible ONLY via get_ambulance_trip_location RPC)
CREATE TABLE IF NOT EXISTS public.ambulance_locations (
    broadcast_id VARCHAR(64) PRIMARY KEY REFERENCES public.ambulance_broadcasts(broadcast_id) ON DELETE CASCADE,
    driver_id VARCHAR(64) NOT NULL REFERENCES public.ambulances(ambulance_id) ON DELETE CASCADE,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    heading DOUBLE PRECISION,
    speed DOUBLE PRECISION,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE public.ambulance_locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ambulance_locations FORCE ROW LEVEL SECURITY;

-- Deny direct client table reads (must query through get_ambulance_trip_location RPC)
REVOKE ALL ON public.ambulance_locations FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.ambulance_locations TO service_role;

-- Change-signal table (Contains ZERO coordinates, ZERO phone numbers, ZERO driver/patient IDs)
CREATE TABLE IF NOT EXISTS public.ambulance_location_updates (
    broadcast_id VARCHAR(64) PRIMARY KEY REFERENCES public.ambulance_broadcasts(broadcast_id) ON DELETE CASCADE,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE public.ambulance_location_updates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ambulance_location_updates FORCE ROW LEVEL SECURITY;

REVOKE ALL ON public.ambulance_location_updates FROM PUBLIC, anon;
GRANT SELECT ON public.ambulance_location_updates TO authenticated, service_role;
GRANT INSERT, UPDATE ON public.ambulance_location_updates TO service_role;

-- RLS on location updates: counterpart patient and accepted driver can listen
DROP POLICY IF EXISTS "ambulance_location_updates_select" ON public.ambulance_location_updates;
CREATE POLICY "ambulance_location_updates_select" ON public.ambulance_location_updates
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.ambulance_broadcasts b
            WHERE b.broadcast_id = ambulance_location_updates.broadcast_id
              AND (
                  b.patient_id = private.current_profile_id()
                  OR b.accepted_driver_id = private.current_profile_id()
                  OR private.is_super_admin()
              )
        )
    );

-- Enable Realtime publication for signal table
ALTER PUBLICATION supabase_realtime ADD TABLE public.ambulance_location_updates;
ALTER TABLE public.ambulance_location_updates REPLICA IDENTITY FULL;

-- ----------------------------------------------------------------------------
-- 3. AMBULANCE TRIP CONTACTS (Sensitive Phone Isolation)
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.ambulance_trip_contacts (
    broadcast_id VARCHAR(64) PRIMARY KEY REFERENCES public.ambulance_broadcasts(broadcast_id) ON DELETE CASCADE,
    patient_phone VARCHAR(32) NOT NULL,
    driver_phone VARCHAR(32),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE public.ambulance_trip_contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ambulance_trip_contacts FORCE ROW LEVEL SECURITY;

REVOKE ALL ON public.ambulance_trip_contacts FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.ambulance_trip_contacts TO service_role;

-- ----------------------------------------------------------------------------
-- 4. CLEAN UP DUPLICATE LEGACY POLICIES & ENFORCE PRESCRIPTION ISOLATION
-- ----------------------------------------------------------------------------

DROP POLICY IF EXISTS "pharmacy_deliv_insert" ON public.pharmacy_deliveries;
DROP POLICY IF EXISTS "pharmacy_deliv_select" ON public.pharmacy_deliveries;
DROP POLICY IF EXISTS "pharmacy_deliv_update" ON public.pharmacy_deliveries;

DROP POLICY IF EXISTS "amb_broadcast_insert" ON public.ambulance_broadcasts;
DROP POLICY IF EXISTS "amb_broadcast_select" ON public.ambulance_broadcasts;
DROP POLICY IF EXISTS "amb_broadcast_update" ON public.ambulance_broadcasts;

DROP POLICY IF EXISTS "presc_meds_policy" ON public.prescription_medicines;

-- Re-assert prescriptions_select: store sees prescriptions ONLY for its own connected deliveries
DROP POLICY IF EXISTS "prescriptions_select" ON public.prescriptions;
CREATE POLICY "prescriptions_select" ON public.prescriptions
    FOR SELECT TO authenticated
    USING (
        patient_id = private.current_profile_id()
        OR doctor_id = private.current_profile_id()
        OR EXISTS (
            SELECT 1 FROM public.pharmacy_deliveries pd 
            WHERE pd.prescription_id = prescriptions.prescription_id 
              AND (
                  pd.store_id = private.current_profile_id()
                  OR EXISTS (
                      SELECT 1 FROM public.medical_stores ms 
                      WHERE ms.store_id = pd.store_id AND ms.owner_uid = (auth.jwt() ->> 'sub')
                  )
              )
        )
        OR private.is_super_admin()
    );

-- Re-assert prescription_medicines_select
DROP POLICY IF EXISTS "presc_meds_select" ON public.prescription_medicines;
CREATE POLICY "presc_meds_select" ON public.prescription_medicines
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.prescriptions p
            WHERE p.prescription_id = prescription_medicines.prescription_id
              AND (
                  p.patient_id = private.current_profile_id()
                  OR p.doctor_id = private.current_profile_id()
                  OR EXISTS (
                      SELECT 1 FROM public.pharmacy_deliveries pd
                      WHERE pd.prescription_id = p.prescription_id
                        AND (
                            pd.store_id = private.current_profile_id()
                            OR EXISTS (
                                SELECT 1 FROM public.medical_stores ms 
                                WHERE ms.store_id = pd.store_id AND ms.owner_uid = (auth.jwt() ->> 'sub')
                            )
                        )
                  )
                  OR private.is_super_admin()
              )
        )
    );

-- ----------------------------------------------------------------------------
-- 5. STATUS COLUMN LOCK TRIGGERS (Enforce RPC-Only State Transitions)
-- ----------------------------------------------------------------------------

-- A. Pharmacy Deliveries status lock
CREATE OR REPLACE FUNCTION private.trg_lock_pharmacy_delivery_status()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'UPDATE' AND OLD.status IS DISTINCT FROM NEW.status THEN
        IF current_setting('app.allow_delivery_status_change', true) IS DISTINCT FROM 'true' THEN
            RAISE EXCEPTION 'Delivery status can only be modified via update_pharmacy_delivery_status RPC'
                USING ERRCODE = '42501';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

DROP TRIGGER IF EXISTS trg_lock_pharmacy_delivery_status ON public.pharmacy_deliveries;
CREATE TRIGGER trg_lock_pharmacy_delivery_status
    BEFORE UPDATE ON public.pharmacy_deliveries
    FOR EACH ROW EXECUTE FUNCTION private.trg_lock_pharmacy_delivery_status();

-- B. Lab Bookings status lock
CREATE OR REPLACE FUNCTION private.trg_lock_lab_booking_status()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'UPDATE' AND OLD.status IS DISTINCT FROM NEW.status THEN
        IF current_setting('app.allow_lab_status_change', true) IS DISTINCT FROM 'true' THEN
            RAISE EXCEPTION 'Lab booking status can only be modified via update_lab_booking_status RPC'
                USING ERRCODE = '42501';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

DROP TRIGGER IF EXISTS trg_lock_lab_booking_status ON public.lab_bookings;
CREATE TRIGGER trg_lock_lab_booking_status
    BEFORE UPDATE ON public.lab_bookings
    FOR EACH ROW EXECUTE FUNCTION private.trg_lock_lab_booking_status();

-- C. Lab Orders status lock
CREATE OR REPLACE FUNCTION private.trg_lock_lab_order_status()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'UPDATE' AND OLD.status IS DISTINCT FROM NEW.status THEN
        IF current_setting('app.allow_lab_status_change', true) IS DISTINCT FROM 'true' THEN
            RAISE EXCEPTION 'Lab order status can only be modified via update_lab_order_status RPC'
                USING ERRCODE = '42501';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

DROP TRIGGER IF EXISTS trg_lock_lab_order_status ON public.lab_orders;
CREATE TRIGGER trg_lock_lab_order_status
    BEFORE UPDATE ON public.lab_orders
    FOR EACH ROW EXECUTE FUNCTION private.trg_lock_lab_order_status();

-- D. Ambulance Broadcasts status lock & driver rating column lock
CREATE OR REPLACE FUNCTION private.trg_lock_ambulance_broadcast_status()
RETURNS TRIGGER AS $$
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
            IF NOT private.is_super_admin() AND (OLD.patient_id != private.current_profile_id() OR OLD.status != 'completed') THEN
                RAISE EXCEPTION 'Only patient can rate completed ambulance trip' USING ERRCODE = '42501';
            END IF;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

DROP TRIGGER IF EXISTS trg_lock_ambulance_broadcast_status ON public.ambulance_broadcasts;
CREATE TRIGGER trg_lock_ambulance_broadcast_status
    BEFORE UPDATE ON public.ambulance_broadcasts
    FOR EACH ROW EXECUTE FUNCTION private.trg_lock_ambulance_broadcast_status();

-- E. Ambulance Requests status lock
CREATE OR REPLACE FUNCTION private.trg_lock_ambulance_request_status()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'UPDATE' AND OLD.status IS DISTINCT FROM NEW.status THEN
        IF current_setting('app.allow_ambulance_status_change', true) IS DISTINCT FROM 'true' THEN
            RAISE EXCEPTION 'Ambulance request status can only be modified via accept_ambulance_request RPC'
                USING ERRCODE = '42501';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

DROP TRIGGER IF EXISTS trg_lock_ambulance_request_status ON public.ambulance_requests;
CREATE TRIGGER trg_lock_ambulance_request_status
    BEFORE UPDATE ON public.ambulance_requests
    FOR EACH ROW EXECUTE FUNCTION private.trg_lock_ambulance_request_status();

-- ----------------------------------------------------------------------------
-- 6. AUTO-LINK LAB REPORTS TO PATIENT HEALTH RECORDS
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION private.trigger_autolink_lab_booking_report()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.report_s3_key IS NOT NULL AND (OLD.report_s3_key IS NULL OR OLD.report_s3_key != NEW.report_s3_key) THEN
        INSERT INTO public.health_records (
            record_id,
            patient_id,
            title,
            type,
            source,
            file_name,
            file_storage,
            date,
            s3_key,
            s3_bucket,
            storage_provider,
            file_size_bytes,
            mime_type,
            upload_confirmed_at,
            created_at,
            updated_at
        )
        VALUES (
            'hr_bkg_' || NEW.booking_id,
            NEW.patient_id,
            COALESCE(NEW.test_name, 'Diagnostic Lab Report'),
            'labReport',
            'labGenerated',
            COALESCE(NEW.report_file_name, 'lab_report.pdf'),
            'cloudUploaded',
            CURRENT_TIMESTAMP,
            NEW.report_s3_key,
            COALESCE(NEW.report_s3_bucket, 'doctornect-clinical-vault'),
            's3',
            NEW.report_file_size_bytes,
            NEW.report_mime_type,
            CURRENT_TIMESTAMP,
            CURRENT_TIMESTAMP,
            CURRENT_TIMESTAMP
        )
        ON CONFLICT (record_id) DO UPDATE SET
            s3_key = EXCLUDED.s3_key,
            s3_bucket = EXCLUDED.s3_bucket,
            file_size_bytes = EXCLUDED.file_size_bytes,
            mime_type = EXCLUDED.mime_type,
            upload_confirmed_at = EXCLUDED.upload_confirmed_at,
            updated_at = CURRENT_TIMESTAMP;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

DROP TRIGGER IF EXISTS trg_autolink_lab_booking_report ON public.lab_bookings;
CREATE TRIGGER trg_autolink_lab_booking_report
    AFTER INSERT OR UPDATE OF report_s3_key ON public.lab_bookings
    FOR EACH ROW EXECUTE FUNCTION private.trigger_autolink_lab_booking_report();

CREATE OR REPLACE FUNCTION private.trigger_autolink_lab_order_report()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.report_s3_key IS NOT NULL AND (OLD.report_s3_key IS NULL OR OLD.report_s3_key != NEW.report_s3_key) THEN
        INSERT INTO public.health_records (
            record_id,
            patient_id,
            title,
            type,
            source,
            file_name,
            file_storage,
            doctor_name,
            date,
            s3_key,
            s3_bucket,
            storage_provider,
            file_size_bytes,
            mime_type,
            upload_confirmed_at,
            created_at,
            updated_at
        )
        VALUES (
            'hr_ord_' || NEW.order_id,
            NEW.patient_id,
            COALESCE(NEW.doctor_name || ' Order Lab Report', 'Diagnostic Lab Report'),
            'labReport',
            'labGenerated',
            COALESCE(NEW.report_file_name, 'lab_order_report.pdf'),
            'cloudUploaded',
            NEW.doctor_name,
            CURRENT_TIMESTAMP,
            NEW.report_s3_key,
            COALESCE(NEW.report_s3_bucket, 'doctornect-clinical-vault'),
            's3',
            NEW.report_file_size_bytes,
            NEW.report_mime_type,
            CURRENT_TIMESTAMP,
            CURRENT_TIMESTAMP,
            CURRENT_TIMESTAMP
        )
        ON CONFLICT (record_id) DO UPDATE SET
            s3_key = EXCLUDED.s3_key,
            s3_bucket = EXCLUDED.s3_bucket,
            file_size_bytes = EXCLUDED.file_size_bytes,
            mime_type = EXCLUDED.mime_type,
            upload_confirmed_at = EXCLUDED.upload_confirmed_at,
            updated_at = CURRENT_TIMESTAMP;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

DROP TRIGGER IF EXISTS trg_autolink_lab_order_report ON public.lab_orders;
CREATE TRIGGER trg_autolink_lab_order_report
    AFTER INSERT OR UPDATE OF report_s3_key ON public.lab_orders
    FOR EACH ROW EXECUTE FUNCTION private.trigger_autolink_lab_order_report();

-- ----------------------------------------------------------------------------
-- 7. PHARMACY RPC: update_pharmacy_delivery_status
-- ----------------------------------------------------------------------------

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
    v_caller_uid := auth.jwt() ->> 'sub';
    IF v_caller_uid IS NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
    END IF;

    v_profile_id := private.current_profile_id();
    v_is_admin := private.is_super_admin();

    SELECT * INTO v_delivery
    FROM public.pharmacy_deliveries
    WHERE delivery_id = p_delivery_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Delivery % not found', p_delivery_id USING ERRCODE = 'P0002';
    END IF;

    v_is_store := (v_delivery.store_id = v_profile_id) OR EXISTS (
        SELECT 1 FROM public.medical_stores ms WHERE ms.store_id = v_delivery.store_id AND ms.owner_uid = v_caller_uid
    );
    v_is_patient := (v_delivery.patient_id = v_profile_id) OR EXISTS (
        SELECT 1 FROM public.patients p WHERE p.patient_id = v_delivery.patient_id AND p.owner_uid = v_caller_uid
    );

    IF NOT (v_is_store OR v_is_patient OR v_is_admin) THEN
        RAISE EXCEPTION 'Unauthorized to update delivery status' USING ERRCODE = '42501';
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

    -- Optionally update medicine dispense lines
    IF p_medicine_lines IS NOT NULL AND jsonb_typeof(p_medicine_lines) = 'array' THEN
        FOR v_line IN SELECT * FROM jsonb_to_recordset(p_medicine_lines) AS x(
            medicine_entry_id VARCHAR(64),
            availability VARCHAR(32),
            substitute_name VARCHAR(255)
        )
        LOOP
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

REVOKE ALL ON FUNCTION public.update_pharmacy_delivery_status(VARCHAR, VARCHAR, TEXT, JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_pharmacy_delivery_status(VARCHAR, VARCHAR, TEXT, JSONB) TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 8. LAB RPCS: update_lab_booking_status & update_lab_order_status
-- ----------------------------------------------------------------------------

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
    v_caller_uid := auth.jwt() ->> 'sub';
    IF v_caller_uid IS NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
    END IF;

    v_profile_id := private.current_profile_id();
    v_is_admin := private.is_super_admin();

    SELECT * INTO v_booking
    FROM public.lab_bookings
    WHERE booking_id = p_booking_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Lab booking % not found', p_booking_id USING ERRCODE = 'P0002';
    END IF;

    v_is_lab := (v_booking.lab_id = v_profile_id) OR EXISTS (
        SELECT 1 FROM public.labs l WHERE l.lab_id = v_booking.lab_id AND l.owner_uid = v_caller_uid
    );
    v_is_patient := (v_booking.patient_id = v_profile_id) OR EXISTS (
        SELECT 1 FROM public.patients p WHERE p.patient_id = v_booking.patient_id AND p.owner_uid = v_caller_uid
    );

    IF NOT (v_is_lab OR v_is_patient OR v_is_admin) THEN
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
    v_caller_uid := auth.jwt() ->> 'sub';
    IF v_caller_uid IS NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
    END IF;

    v_profile_id := private.current_profile_id();
    v_is_admin := private.is_super_admin();

    SELECT * INTO v_order
    FROM public.lab_orders
    WHERE order_id = p_order_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Lab order % not found', p_order_id USING ERRCODE = 'P0002';
    END IF;

    v_is_lab := (v_order.lab_id = v_profile_id) OR EXISTS (
        SELECT 1 FROM public.labs l WHERE l.lab_id = v_order.lab_id AND l.owner_uid = v_caller_uid
    );
    v_is_doctor := (v_order.doctor_id = v_profile_id) OR EXISTS (
        SELECT 1 FROM public.doctors d WHERE d.doctor_id = v_order.doctor_id AND d.owner_uid = v_caller_uid
    );

    IF NOT (v_is_lab OR v_is_doctor OR v_is_admin) THEN
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

-- ----------------------------------------------------------------------------
-- 9. AMBULANCE RPCS: accept, cancel, complete, location, contact
-- ----------------------------------------------------------------------------

-- Atomic, Race-Safe Broadcast Acceptance
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
    v_driver_id TEXT;
    v_driver public.ambulances%ROWTYPE;
    v_broadcast public.ambulance_broadcasts%ROWTYPE;
    v_contact public.ambulance_trip_contacts%ROWTYPE;
    v_winning_request_id VARCHAR(64);
BEGIN
    v_caller_uid := auth.jwt() ->> 'sub';
    IF v_caller_uid IS NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
    END IF;

    -- Resolve driver profile
    SELECT * INTO v_driver
    FROM public.ambulances
    WHERE auth_uid = v_caller_uid OR ambulance_id = private.current_profile_id();

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

    -- Determine winning request id
    IF p_request_id IS NOT NULL THEN
        v_winning_request_id := p_request_id;
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

-- Complete Active Trip
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
    v_broadcast public.ambulance_broadcasts%ROWTYPE;
    v_driver_id TEXT;
BEGIN
    v_caller_uid := auth.jwt() ->> 'sub';
    IF v_caller_uid IS NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
    END IF;

    SELECT ambulance_id INTO v_driver_id
    FROM public.ambulances WHERE auth_uid = v_caller_uid OR ambulance_id = private.current_profile_id();

    SELECT * INTO v_broadcast
    FROM public.ambulance_broadcasts WHERE broadcast_id = p_broadcast_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Broadcast % not found', p_broadcast_id USING ERRCODE = 'P0002';
    END IF;

    IF v_broadcast.accepted_driver_id != v_driver_id AND NOT private.is_super_admin() THEN
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

-- Cancel Ambulance Broadcast
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
    v_broadcast public.ambulance_broadcasts%ROWTYPE;
    v_is_patient BOOLEAN;
    v_is_admin BOOLEAN;
BEGIN
    v_caller_uid := auth.jwt() ->> 'sub';
    IF v_caller_uid IS NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
    END IF;

    v_is_admin := private.is_super_admin();

    SELECT * INTO v_broadcast
    FROM public.ambulance_broadcasts WHERE broadcast_id = p_broadcast_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Broadcast % not found', p_broadcast_id USING ERRCODE = 'P0002';
    END IF;

    v_is_patient := (v_broadcast.patient_id = private.current_profile_id()) OR EXISTS (
        SELECT 1 FROM public.patients p WHERE p.patient_id = v_broadcast.patient_id AND p.owner_uid = v_caller_uid
    );

    IF NOT (v_is_patient OR v_is_admin) THEN
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

-- Update Live Location (Driver Only during Active Trip)
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
    v_driver_id TEXT;
    v_broadcast public.ambulance_broadcasts%ROWTYPE;
BEGIN
    v_caller_uid := auth.jwt() ->> 'sub';
    IF v_caller_uid IS NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
    END IF;

    SELECT ambulance_id INTO v_driver_id
    FROM public.ambulances WHERE auth_uid = v_caller_uid OR ambulance_id = private.current_profile_id();

    IF v_driver_id IS NULL THEN
        RAISE EXCEPTION 'Ambulance driver profile not registered' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_broadcast
    FROM public.ambulance_broadcasts
    WHERE broadcast_id = p_broadcast_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Broadcast % not found', p_broadcast_id USING ERRCODE = 'P0002';
    END IF;

    IF v_broadcast.accepted_driver_id != v_driver_id AND NOT private.is_super_admin() THEN
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

-- Safe RPC Refetch: Location visible only to counterpart during active trip
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
    v_caller_uid := auth.jwt() ->> 'sub';
    IF v_caller_uid IS NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
    END IF;

    v_profile_id := private.current_profile_id();
    v_is_admin := private.is_super_admin();

    SELECT * INTO v_broadcast
    FROM public.ambulance_broadcasts
    WHERE broadcast_id = p_broadcast_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Broadcast % not found', p_broadcast_id USING ERRCODE = 'P0002';
    END IF;

    v_is_patient := (v_broadcast.patient_id = v_profile_id) OR EXISTS (
        SELECT 1 FROM public.patients p WHERE p.patient_id = v_broadcast.patient_id AND p.owner_uid = v_caller_uid
    );
    v_is_driver := (v_broadcast.accepted_driver_id = v_profile_id) OR EXISTS (
        SELECT 1 FROM public.ambulances a WHERE a.ambulance_id = v_broadcast.accepted_driver_id AND a.auth_uid = v_caller_uid
    );

    IF NOT (v_is_patient OR v_is_driver OR v_is_admin) THEN
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

-- Safe RPC Refetch: Counterpart phone visible ONLY after acceptance and ONLY during active trip
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
    v_caller_uid := auth.jwt() ->> 'sub';
    IF v_caller_uid IS NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
    END IF;

    v_profile_id := private.current_profile_id();
    v_is_admin := private.is_super_admin();

    SELECT * INTO v_broadcast FROM public.ambulance_broadcasts WHERE broadcast_id = p_broadcast_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Broadcast not found' USING ERRCODE = 'P0002';
    END IF;

    v_is_patient := (v_broadcast.patient_id = v_profile_id) OR EXISTS (
        SELECT 1 FROM public.patients p WHERE p.patient_id = v_broadcast.patient_id AND p.owner_uid = v_caller_uid
    );
    v_is_driver := (v_broadcast.accepted_driver_id = v_profile_id) OR EXISTS (
        SELECT 1 FROM public.ambulances a WHERE a.ambulance_id = v_broadcast.accepted_driver_id AND a.auth_uid = v_caller_uid
    );

    IF NOT (v_is_patient OR v_is_driver OR v_is_admin) THEN
        RAISE EXCEPTION 'Unauthorized to view trip contact' USING ERRCODE = '42501';
    END IF;

    -- Visible to the counterpart ONLY after acceptance and ONLY during active trip
    IF v_broadcast.status != 'accepted' THEN
        IF v_is_patient THEN
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

-- ----------------------------------------------------------------------------
-- 10. EXPIRATION MAINTENANCE (pg_cron & Stored Proc)
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.expire_stale_ambulance_broadcasts()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_expired_count INTEGER := 0;
BEGIN
    PERFORM set_config('app.allow_ambulance_status_change', 'true', true);

    WITH expired AS (
        UPDATE public.ambulance_broadcasts
        SET status = 'cancelled',
            notes = COALESCE(notes || ' | Expired automatically after 15m timeout', 'Expired automatically after 15m timeout'),
            updated_at = CURRENT_TIMESTAMP
        WHERE status = 'pending'
          AND created_at < CURRENT_TIMESTAMP - INTERVAL '15 minutes'
        RETURNING broadcast_id
    )
    SELECT COUNT(*) INTO v_expired_count FROM expired;

    IF v_expired_count > 0 THEN
        UPDATE public.ambulance_requests
        SET status = 'cancelled',
            updated_at = CURRENT_TIMESTAMP
        WHERE broadcast_id IN (
            SELECT broadcast_id FROM public.ambulance_broadcasts
            WHERE status = 'cancelled' AND notes LIKE '%Expired automatically%'
        )
        AND status = 'pending';
    END IF;

    PERFORM set_config('app.allow_ambulance_status_change', '', true);

    RETURN v_expired_count;
END;
$$;

REVOKE ALL ON FUNCTION public.expire_stale_ambulance_broadcasts() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.expire_stale_ambulance_broadcasts() TO authenticated, service_role;

-- Schedule cron job if pg_cron is enabled
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        PERFORM cron.unschedule('expire-stale-ambulance-broadcasts')
        WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'expire-stale-ambulance-broadcasts');

        PERFORM cron.schedule(
            'expire-stale-ambulance-broadcasts',
            '*/5 * * * *',
            'SELECT public.expire_stale_ambulance_broadcasts();'
        );
    END IF;
END $$;
