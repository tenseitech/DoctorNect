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