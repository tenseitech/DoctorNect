-- DoctorNect Migration: 20261124000003_submit_ambulance_rating_rpc.sql
-- Description: Postgres replacement for the Firestore-only submitAmbulanceRating callable.
--   * One rating per completed trip (compare-and-set on rating IS NULL), only by the booking
--     patient, only for the driver that actually accepted the trip.
--   * Aggregates (rating_count / total_rating) updated in the same statement, so concurrent
--     submissions cannot double count or lose increments.
--   * EXECUTE granted to service_role only (called by Cloud Functions after Firebase auth);
--     never callable by anon / authenticated clients directly.
-- Idempotent; PG17 (Supabase) and PG18 (RDS) compatible.

CREATE OR REPLACE FUNCTION public.submit_ambulance_rating(
    p_broadcast_id TEXT,
    p_ambulance_id TEXT,
    p_patient_id TEXT,
    p_stars INT,
    p_review TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_status TEXT;
    v_driver TEXT;
    v_patient TEXT;
    v_rating NUMERIC;
    v_updated INT;
BEGIN
    IF p_stars IS NULL OR p_stars < 1 OR p_stars > 5 THEN
        RAISE EXCEPTION 'BAD_REQUEST: stars must be between 1 and 5' USING ERRCODE = '22023';
    END IF;

    SELECT status, accepted_driver_id, patient_id, rating
      INTO v_status, v_driver, v_patient, v_rating
      FROM public.ambulance_broadcasts
     WHERE broadcast_id = p_broadcast_id
     FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'NOT_FOUND: trip not found' USING ERRCODE = 'P0002';
    END IF;
    IF v_status IS DISTINCT FROM 'completed' THEN
        RAISE EXCEPTION 'FAILED_PRECONDITION: trip not completed' USING ERRCODE = '55000';
    END IF;
    IF v_driver IS DISTINCT FROM p_ambulance_id THEN
        RAISE EXCEPTION 'INVALID_ARGUMENT: ambulance does not match this trip' USING ERRCODE = '22023';
    END IF;
    IF v_patient IS DISTINCT FROM p_patient_id THEN
        RAISE EXCEPTION 'FORBIDDEN: only the booking patient can rate this trip' USING ERRCODE = '42501';
    END IF;
    IF v_rating IS NOT NULL THEN
        IF v_rating = -1 THEN
            RAISE EXCEPTION 'FAILED_PRECONDITION: rating was skipped for this trip' USING ERRCODE = '55000';
        END IF;
        RAISE EXCEPTION 'ALREADY_EXISTS: already rated' USING ERRCODE = '23505';
    END IF;

    UPDATE public.ambulance_broadcasts
       SET rating = p_stars,
           review = NULLIF(left(btrim(coalesce(p_review, '')), 500), ''),
           updated_at = now()
     WHERE broadcast_id = p_broadcast_id
       AND rating IS NULL;
    GET DIAGNOSTICS v_updated = ROW_COUNT;
    IF v_updated = 0 THEN
        RAISE EXCEPTION 'ALREADY_EXISTS: already rated' USING ERRCODE = '23505';
    END IF;

    UPDATE public.ambulances
       SET rating_count = coalesce(rating_count, 0) + 1,
           total_rating = coalesce(total_rating, 0) + p_stars,
           updated_at = now()
     WHERE ambulance_id = p_ambulance_id;

    RETURN jsonb_build_object('ok', true);
END;
$$;

REVOKE ALL ON FUNCTION public.submit_ambulance_rating(TEXT, TEXT, TEXT, INT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.submit_ambulance_rating(TEXT, TEXT, TEXT, INT, TEXT) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.submit_ambulance_rating(TEXT, TEXT, TEXT, INT, TEXT) TO service_role;
