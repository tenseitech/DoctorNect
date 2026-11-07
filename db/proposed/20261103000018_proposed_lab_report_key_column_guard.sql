-- PROPOSED (do not apply): prevent direct PostgREST mutation of report_storage_key / report_s3_key.
-- Keys may change only via update_lab_*_status RPC (session app.allow_lab_status_change) or service_role.

CREATE OR REPLACE FUNCTION private.lab_report_keys_update_guard()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_record_id TEXT;
  v_patient_id TEXT;
  v_expected TEXT;
BEGIN
  IF COALESCE(private.is_super_admin(), FALSE) THEN
    RETURN NEW;
  END IF;

  IF (NEW.report_storage_key IS NOT DISTINCT FROM OLD.report_storage_key)
     AND (NEW.report_s3_key IS NOT DISTINCT FROM OLD.report_s3_key) THEN
    RETURN NEW;
  END IF;

  IF TG_TABLE_NAME = 'lab_bookings' THEN
    v_record_id := NEW.booking_id;
    v_patient_id := NEW.patient_id;
  ELSIF TG_TABLE_NAME = 'lab_orders' THEN
    v_record_id := NEW.order_id;
    v_patient_id := NEW.patient_id;
  ELSE
    RETURN NEW;
  END IF;

  IF current_setting('app.allow_lab_status_change', true) <> 'true' THEN
    RAISE EXCEPTION 'FORBIDDEN: report keys may only change via lab status RPC'
      USING ERRCODE = '42501';
  END IF;

  v_expected := 'lab_reports/' || v_patient_id || '/' || v_record_id || '/';

  IF NEW.report_storage_key IS NOT NULL AND NOT starts_with(NEW.report_storage_key, v_expected) THEN
    RAISE EXCEPTION 'Invalid report_storage_key prefix' USING ERRCODE = '22023';
  END IF;
  IF NEW.report_s3_key IS NOT NULL AND NOT starts_with(NEW.report_s3_key, v_expected) THEN
    RAISE EXCEPTION 'Invalid report_s3_key prefix' USING ERRCODE = '22023';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_lab_bookings_report_keys ON public.lab_bookings;
CREATE TRIGGER trg_lab_bookings_report_keys
  BEFORE UPDATE ON public.lab_bookings
  FOR EACH ROW
  EXECUTE FUNCTION private.lab_report_keys_update_guard();

DROP TRIGGER IF EXISTS trg_lab_orders_report_keys ON public.lab_orders;
CREATE TRIGGER trg_lab_orders_report_keys
  BEFORE UPDATE ON public.lab_orders
  FOR EACH ROW
  EXECUTE FUNCTION private.lab_report_keys_update_guard();
