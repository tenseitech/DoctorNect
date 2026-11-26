-- DoctorNect Migration: 20261125000004_provider_rows_client_insert_guard.sql
-- Description: SECURITY FIX (state-machine bypass on INSERT), found in the round-3 audit.
-- The status-lock triggers on ambulance_broadcasts / lab_bookings / lab_orders /
-- pharmacy_deliveries only fire on UPDATE, so a client could INSERT a row that is already in a
-- late or terminal state. Example: a patient inserts an ambulance_broadcasts row with
-- status = 'completed' and accepted_driver_id = <any ambulance>, then calls
-- submitAmbulanceRating to post a rating for an ambulance that never served them. Same for lab
-- bookings created as 'completed' with a report pointer.
-- For INSERTs by PostgREST clients (authenticated / anon, not super admin) the row now starts in
-- its initial state and server-owned columns are cleared; all later transitions keep going
-- through the existing RPCs (accept/complete/update_*_status) and report upload confirmation.
-- Trusted writers (SECURITY DEFINER RPCs, service_role, migrations) are unaffected.
-- Idempotent; PG17 (Supabase) and PG18 (RDS) compatible.

CREATE SCHEMA IF NOT EXISTS private;

CREATE OR REPLACE FUNCTION private.trg_client_insert_initial_state()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO ''
AS $$
DECLARE
    v_clear jsonb;
BEGIN
    IF current_user NOT IN ('authenticated', 'anon') THEN
        RETURN NEW;
    END IF;
    IF COALESCE(private.is_super_admin(), FALSE) THEN
        RETURN NEW;
    END IF;

    -- Report pointers are written only by the backend after an authorised S3 upload.
    SELECT jsonb_object_agg(k, NULL) INTO v_clear
      FROM jsonb_object_keys(to_jsonb(NEW)) AS k
     WHERE k LIKE 'report\_%';

    IF TG_TABLE_NAME = 'ambulance_broadcasts' THEN
        NEW.status := 'pending';
        NEW.accepted_driver_id := NULL;
        NEW.accepted_driver_name := NULL;
        NEW.accepted_driver_phone := NULL;
        NEW.accepted_vehicle_number := NULL;
        NEW.accepted_ambulance_type := NULL;
        NEW.accepted_at := NULL;
        NEW.rating := NULL;
    ELSIF TG_TABLE_NAME = 'lab_bookings' THEN
        NEW.status := 'confirmed';
        IF v_clear IS NOT NULL THEN NEW := jsonb_populate_record(NEW, v_clear); END IF;
    ELSIF TG_TABLE_NAME = 'lab_orders' THEN
        NEW.status := 'ordered';
        IF v_clear IS NOT NULL THEN NEW := jsonb_populate_record(NEW, v_clear); END IF;
    ELSIF TG_TABLE_NAME = 'pharmacy_deliveries' THEN
        NEW.status := 'sent';
    END IF;
    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION private.trg_client_insert_initial_state() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION private.trg_client_insert_initial_state() TO authenticated, service_role;

DO $$
DECLARE
    t text;
BEGIN
    FOREACH t IN ARRAY ARRAY['ambulance_broadcasts', 'lab_bookings', 'lab_orders', 'pharmacy_deliveries'] LOOP
        IF to_regclass('public.' || t) IS NOT NULL THEN
            EXECUTE format('DROP TRIGGER IF EXISTS trg_client_insert_initial_state ON public.%I', t);
            EXECUTE format(
                'CREATE TRIGGER trg_client_insert_initial_state BEFORE INSERT ON public.%I '
                'FOR EACH ROW EXECUTE FUNCTION private.trg_client_insert_initial_state()', t);
        END IF;
    END LOOP;
END;
$$;
