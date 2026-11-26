-- DoctorNect Migration: 20261125000003_appointments_client_write_guard.sql
-- Description: SECURITY FIX (double booking / slot capacity bypass), found in the round-3 audit.
-- The "appointments_insert" policy lets a patient INSERT a row whose patient_id is their own
-- profile directly through PostgREST. That skipped every check in book_appointment_atomic
-- (advisory lock, one active booking per patient per slot, capacity 3, server token number,
-- doctor name from doctors) and let the client choose doctor_status (e.g. 'accepted') and
-- token_number. The policy cannot simply be dropped: the app cancels through an upsert
-- (INSERT ... ON CONFLICT DO UPDATE), which evaluates the INSERT path first.
--
-- Guard (SECURITY INVOKER so current_user is the PostgREST role):
--   * trusted writers (book/reschedule RPCs run as their owner, service_role, migrations): allowed
--   * super admin: allowed
--   * the doctor of the row (walk-ins; the policy still requires source = 'walkin'): allowed
--   * any other authenticated INSERT of a NEW appointment_id: rejected -> use book_appointment_atomic
--   * an upsert that hits an existing row is passed through to the UPDATE policy
--   * UPDATE by a non-doctor client: slot / identity / doctor-side columns are pinned
-- Idempotent; PG17 (Supabase) and PG18 (RDS) compatible.

CREATE SCHEMA IF NOT EXISTS private;

CREATE OR REPLACE FUNCTION private.trg_appointments_client_write_guard()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO ''
AS $$
DECLARE
    v_profile TEXT;
BEGIN
    IF current_user NOT IN ('authenticated', 'anon') THEN
        RETURN NEW;
    END IF;
    IF COALESCE(private.is_super_admin(), FALSE) THEN
        RETURN NEW;
    END IF;
    v_profile := private.current_profile_id();

    IF TG_OP = 'INSERT' THEN
        IF v_profile IS NOT NULL AND NEW.doctor_id IS NOT DISTINCT FROM v_profile THEN
            RETURN NEW;
        END IF;
        IF EXISTS (SELECT 1 FROM public.appointments a WHERE a.appointment_id = NEW.appointment_id) THEN
            RETURN NEW;  -- upsert onto an existing row: ON CONFLICT DO UPDATE + UPDATE policy decide
        END IF;
        RAISE EXCEPTION 'FORBIDDEN: appointments must be booked through book_appointment_atomic'
            USING ERRCODE = '42501';
    END IF;

    -- UPDATE by a patient / family owner: only patient-side fields may change.
    IF v_profile IS NULL OR OLD.doctor_id IS DISTINCT FROM v_profile THEN
        NEW.appointment_id := OLD.appointment_id;
        NEW.doctor_id := OLD.doctor_id;
        NEW.patient_id := OLD.patient_id;
        NEW.date_time := OLD.date_time;
        NEW.slot_label := OLD.slot_label;
        NEW.token_number := OLD.token_number;
        NEW.doctor_status := OLD.doctor_status;
        NEW.doctor_name := OLD.doctor_name;
        NEW.specialization := OLD.specialization;
    END IF;
    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION private.trg_appointments_client_write_guard() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION private.trg_appointments_client_write_guard() TO authenticated, service_role;

DROP TRIGGER IF EXISTS trg_appointments_client_write_guard ON public.appointments;
CREATE TRIGGER trg_appointments_client_write_guard
    BEFORE INSERT OR UPDATE ON public.appointments
    FOR EACH ROW EXECUTE FUNCTION private.trg_appointments_client_write_guard();
