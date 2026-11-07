-- STAGING ONLY — apply db/proposed/20261103000015 + 000017 + 000018 first.
-- psql "$STAGING_SUPABASE_DB_URL" -f scripts/audit/lab_report_key_staging_probes.sql

BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.set_jwt(sub text, role text DEFAULT 'authenticated')
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', json_build_object('sub', sub, 'role', role)::text, true);
  PERFORM set_config('role', role, true);
END;
$$;

-- Lab JWT: uid_lab_a / lab_id lab_staging_a; patient pat_staging_1; booking bk_staging_1

SELECT pg_temp.set_jwt('uid_lab_a');
SET LOCAL role authenticated;

DO $$
BEGIN
  UPDATE public.lab_bookings
  SET report_storage_key = 'lab_reports/pat_other/bk_staging_1/evil.pdf'
  WHERE booking_id = 'bk_staging_1';
  RAISE EXCEPTION 'FAIL [lab_direct_wrong_patient_key]: UPDATE should have been rejected';
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%report keys may only change via lab status RPC%'
       AND SQLERRM NOT LIKE '%FORBIDDEN%' THEN
      RAISE;
    END IF;
    RAISE NOTICE 'PASS [lab_direct_wrong_patient_key]: %', SQLERRM;
END;
$$;

SELECT pg_temp.set_jwt('uid_patient_staging');
SET LOCAL role authenticated;

DO $$
BEGIN
  UPDATE public.lab_bookings
  SET report_storage_key = 'lab_reports/pat_staging_1/bk_staging_1/p.pdf'
  WHERE booking_id = 'bk_staging_1';
  RAISE EXCEPTION 'FAIL [patient_direct_key]: UPDATE should have been rejected';
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%report keys may only change via lab status RPC%' THEN
      RAISE;
    END IF;
    RAISE NOTICE 'PASS [patient_direct_key]: %', SQLERRM;
END;
$$;

SELECT pg_temp.set_jwt('uid_lab_a');
SET LOCAL role authenticated;

DO $$
DECLARE
  v jsonb;
BEGIN
  v := public.update_lab_booking_status(
    'bk_staging_1',
    'completed',
    NULL,
    'lab_reports/pat_staging_1/bk_staging_1/ok.pdf'
  );
  IF COALESCE(v->>'success', 'false') <> 'true' THEN
    RAISE EXCEPTION 'FAIL [lab_rpc_valid_key]: unexpected %', v;
  END IF;
  RAISE NOTICE 'PASS [lab_rpc_valid_key]';
END;
$$;

RESET role;
SET LOCAL role service_role;

DO $$
BEGIN
  UPDATE public.lab_bookings
  SET report_storage_key = 'lab_reports/pat_staging_1/bk_staging_1/svc.pdf'
  WHERE booking_id = 'bk_staging_1';
  RAISE NOTICE 'PASS [service_role_direct_key]';
END;
$$;

ROLLBACK;
