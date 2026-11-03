-- PROPOSED (do not apply): backfill report_storage_key; notes remain free-text.
-- Apply via manual review only (db/proposed/ — excluded from scripts/db/migrate.js).

-- Drop prior 3-arg signature to avoid PostgREST overload ambiguity when adding 4th param.
DROP FUNCTION IF EXISTS public.update_lab_booking_status(VARCHAR, VARCHAR, TEXT);
DROP FUNCTION IF EXISTS public.update_lab_booking_status(character varying, character varying, text);

ALTER TABLE public.lab_bookings
  ADD COLUMN IF NOT EXISTS report_storage_key TEXT;

ALTER TABLE public.lab_orders
  ADD COLUMN IF NOT EXISTS report_storage_key TEXT;

UPDATE public.lab_bookings
SET report_storage_key = notes
WHERE report_storage_key IS NULL
  AND notes IS NOT NULL
  AND notes ~ '^lab_reports/[^[:space:]]+$';

UPDATE public.lab_orders
SET report_storage_key = notes
WHERE report_storage_key IS NULL
  AND notes IS NOT NULL
  AND notes ~ '^lab_reports/[^[:space:]]+$';

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

    SELECT * INTO v_booking FROM public.lab_bookings WHERE booking_id = p_booking_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Lab booking % not found', p_booking_id USING ERRCODE = 'P0002';
    END IF;

    v_is_lab := (v_booking.lab_id IS NOT DISTINCT FROM v_profile_id);
    v_is_patient := (v_booking.patient_id IS NOT DISTINCT FROM v_profile_id);

    IF NOT (COALESCE(v_is_lab, FALSE) OR COALESCE(v_is_patient, FALSE) OR v_is_admin) THEN
        RAISE EXCEPTION 'Unauthorized to update lab booking' USING ERRCODE = '42501';
    END IF;

    PERFORM set_config('app.allow_lab_status_change', 'true', true);

    UPDATE public.lab_bookings
    SET status = p_new_status,
        notes = CASE
            WHEN p_notes IS NOT NULL AND (p_notes !~ '^lab_reports/') THEN p_notes
            ELSE notes
        END,
        report_storage_key = COALESCE(p_report_storage_key, report_storage_key),
        report_s3_key = COALESCE(p_report_storage_key, report_s3_key),
        updated_at = CURRENT_TIMESTAMP
    WHERE booking_id = p_booking_id;

    PERFORM set_config('app.allow_lab_status_change', '', true);

    RETURN jsonb_build_object('success', true, 'booking_id', p_booking_id);
END;
$$;

REVOKE ALL ON FUNCTION public.update_lab_booking_status(VARCHAR, VARCHAR, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_lab_booking_status(VARCHAR, VARCHAR, TEXT, TEXT) TO authenticated, service_role;

-- lab_orders: mirror pattern (proposed)
DROP FUNCTION IF EXISTS public.update_lab_order_status(VARCHAR, VARCHAR, TEXT);
DROP FUNCTION IF EXISTS public.update_lab_order_status(character varying, character varying, text);

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
    v_profile_id TEXT;
    v_order public.lab_orders%ROWTYPE;
BEGIN
    v_profile_id := private.current_profile_id();

    SELECT * INTO v_order FROM public.lab_orders WHERE order_id = p_order_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Lab order % not found', p_order_id USING ERRCODE = 'P0002';
    END IF;

    PERFORM set_config('app.allow_lab_status_change', 'true', true);

    UPDATE public.lab_orders
    SET status = p_new_status,
        notes = CASE
            WHEN p_notes IS NOT NULL AND (p_notes !~ '^lab_reports/') THEN p_notes
            ELSE notes
        END,
        report_storage_key = COALESCE(p_report_storage_key, report_storage_key),
        report_s3_key = COALESCE(p_report_storage_key, report_s3_key),
        updated_at = CURRENT_TIMESTAMP
    WHERE order_id = p_order_id;

    PERFORM set_config('app.allow_lab_status_change', '', true);

    RETURN jsonb_build_object('success', true, 'order_id', p_order_id);
END;
$$;

REVOKE ALL ON FUNCTION public.update_lab_order_status(VARCHAR, VARCHAR, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_lab_order_status(VARCHAR, VARCHAR, TEXT, TEXT) TO authenticated, service_role;
